return function(Import)
	local Util = Import("Util")
	local PrivacyManager = {}
	PrivacyManager.__index = PrivacyManager

	local function plainText(value)
		return string.gsub(tostring(value or ""), "<[^>]->", "")
	end

	local function screenName(instance, playerGui)
		local current = instance
		while current and current ~= playerGui do
			if current:IsA("ScreenGui") then
				return current.Name
			end
			current = current.Parent
		end
		return nil
	end

	function PrivacyManager.new(player)
		local self = setmetatable({}, PrivacyManager)
		self.Player = player
		self.PlayerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")
		self.Enabled = false
		self.Destroyed = false
		self.Masked = {}
		self.Connections = {}
		self.MaskConnections = {}

		local restoreIdentity = Util.ElevateIdentity()
		table.insert(self.Connections, self.PlayerGui.DescendantAdded:Connect(function(instance)
			self:_Run(function()
				self:_Inspect(instance)
			end)
			task.delay(0.1, function()
				self:_Run(function()
					self:_Inspect(instance)
				end)
			end)
		end))
		table.insert(self.Connections, player.CharacterAdded:Connect(function()
			task.delay(0.15, function()
				self:Refresh()
			end)
		end))
		restoreIdentity()
		return self
	end

	function PrivacyManager:_Run(callback)
		if self.Destroyed then
			return false
		end
		local restoreIdentity = Util.ElevateIdentity()
		local ok, result = xpcall(callback, Util.Traceback)
		restoreIdentity()
		if not ok then
			Util.Warn("privacy masking failed: " .. tostring(result))
		end
		return ok, result
	end

	function PrivacyManager:_Record(instance, property)
		local properties = self.Masked[instance]
		if not properties then
			properties = {}
			self.Masked[instance] = properties
		end
		local record = properties[property]
		if not record then
			record = {Value = instance[property], Applying = false}
			properties[property] = record
		end
		return record
	end

	function PrivacyManager:_Set(instance, property, value)
		local record = self:_Record(instance, property)
		record.Applying = true
		instance[property] = value
		record.Applying = false
		return record
	end

	function PrivacyManager:_MaskText(label, replacement)
		local properties = self.Masked[label]
		local existing = properties and properties.Text
		if existing and existing.Replacement == replacement then
			if label.Text ~= replacement then
				existing.Value = label.Text
				self:_Set(label, "Text", replacement)
			end
			return
		end

		local record = self:_Set(label, "Text", replacement)
		record.Replacement = replacement
		local connection = label:GetPropertyChangedSignal("Text"):Connect(function()
			self:_Run(function()
				if not self.Enabled or record.Applying or not label.Parent then
					return
				end
				local current = label.Text
				if current ~= record.Replacement then
					record.Value = current
					record.Applying = true
					label.Text = record.Replacement
					record.Applying = false
				end
			end)
		end)
		table.insert(self.MaskConnections, connection)
	end

	function PrivacyManager:_IsLocalOverhead(instance)
		if not instance:IsA("BillboardGui") then
			return false
		end
		if screenName(instance, self.PlayerGui) ~= "PlayerOverhead" then
			return false
		end
		local character = self.Player.Character
		if not character then
			return false
		end
		local adornee = instance.Adornee
		return instance:IsDescendantOf(character)
			or (adornee ~= nil and adornee:IsDescendantOf(character))
	end

	function PrivacyManager:_MaskPlayerRow(label)
		self:_MaskText(label, "Hidden Player")
		local row = label.Parent
		while row and row ~= self.PlayerGui do
			if row:IsA("GuiButton") then
				break
			end
			row = row.Parent
		end
		if not row or row == self.PlayerGui then
			return
		end
		for _, descendant in ipairs(row:GetDescendants()) do
			if descendant:IsA("TextLabel") then
				if descendant.Name == "Level" then
					self:_MaskText(descendant, "--")
				elseif descendant.Name == "Guild" then
					self:_MaskText(descendant, "Private")
				end
			end
		end
	end

	function PrivacyManager:_Inspect(instance)
		if not self.Enabled or not instance.Parent then
			return
		end
		if self:_IsLocalOverhead(instance) then
			self:_Set(instance, "Enabled", false)
			return
		end
		if not instance:IsA("TextLabel") and not instance:IsA("TextButton") then
			return
		end

		local rootName = screenName(instance, self.PlayerGui)
		local text = plainText(instance.Text)
		if rootName == "PlayerList" then
			local lower = string.lower(text)
			if lower == string.lower(self.Player.Name) or lower == string.lower(self.Player.DisplayName) then
				self:_MaskPlayerRow(instance)
			end
		elseif rootName == "BottomHUD" then
			if string.find(text, "XP", 1, true)
				and (string.match(text, "^Lvl%s+[%d,]+%s*%(") or string.match(text, "^Level%s+[%d,]+%s*%(")) then
				self:_MaskText(instance, "Level Hidden (Private)")
			end
		end
	end

	function PrivacyManager:Refresh()
		if not self.Enabled or self.Destroyed then
			return
		end
		self:_Run(function()
			for _, instance in ipairs(self.PlayerGui:GetDescendants()) do
				self:_Inspect(instance)
			end
		end)
	end

	function PrivacyManager:_Restore()
		for _, connection in ipairs(self.MaskConnections) do
			pcall(function()
				connection:Disconnect()
			end)
		end
		table.clear(self.MaskConnections)
		for instance, properties in pairs(self.Masked) do
			if instance.Parent then
				for property, record in pairs(properties) do
					pcall(function()
						instance[property] = record.Value
					end)
				end
			end
		end
		table.clear(self.Masked)
	end

	function PrivacyManager:SetEnabled(enabled)
		enabled = enabled == true
		if self.Destroyed then
			return
		end
		if self.Enabled == enabled then
			if enabled then
				self:Refresh()
			end
			return
		end
		self.Enabled = enabled
		if enabled then
			self:Refresh()
		else
			self:_Run(function()
				self:_Restore()
			end)
		end
	end

	function PrivacyManager:Destroy()
		if self.Destroyed then
			return
		end
		self:SetEnabled(false)
		self.Destroyed = true
		for _, connection in ipairs(self.Connections) do
			pcall(function()
				connection:Disconnect()
			end)
		end
		table.clear(self.Connections)
	end

	return PrivacyManager
end
