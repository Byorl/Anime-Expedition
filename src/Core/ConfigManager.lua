return function(Import)
	local Build = Import("Build")
	local Util = Import("Util")
	local ConfigManager = {}
	ConfigManager.__index = ConfigManager

	function ConfigManager.new(fileSystem, registry, player)
		local self = setmetatable({}, ConfigManager)
		self.FileSystem = fileSystem
		self.Registry = registry
		self.Player = player
		self.ConfigFolder = Build.DataRoot .. "/configs/global"
		self.AccountFolder = Build.DataRoot .. "/accounts/" .. tostring(player.UserId)
		self.AccountPath = self.AccountFolder .. "/state.json"
		self.Account = {
			Schema = 2,
			UserId = player.UserId,
			UserName = player.Name,
			SelectedConfig = "main",
			AutoLoadSelected = true,
			AutoSave = false,
			Session = {AutoExecute = false},
		}
		self.SaveNonce = 0
		self.Alive = true
		return self
	end

	function ConfigManager:_ConfigPath(name)
		return self.ConfigFolder .. "/" .. name .. ".json"
	end

	function ConfigManager:SanitizeName(name)
		name = tostring(name or "")
		name = string.gsub(name, "^%s+", "")
		name = string.gsub(name, "%s+$", "")
		name = string.gsub(name, "[<>:\"/\\|%?%*%c]", "_")
		name = string.gsub(name, "%s+", " ")
		name = string.gsub(name, "^[%. ]+", "")
		name = string.gsub(name, "[%. ]+$", "")
		if #name > 64 then name = string.sub(name, 1, 64) end
		return name
	end

	function ConfigManager:List()
		local names, seen = {}, {}
		for _, path in ipairs(self.FileSystem:List(self.ConfigFolder)) do
			local normalized = string.gsub(path, "\\", "/")
			local name = string.match(normalized, "([^/]+)%.json$")
			if name and not seen[string.lower(name)] then
				seen[string.lower(name)] = true
				table.insert(names, name)
			end
		end
		table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
		return names
	end

	function ConfigManager:ResolveName(name)
		local wanted = string.lower(self:SanitizeName(name))
		for _, existing in ipairs(self:List()) do
			if string.lower(existing) == wanted then return existing end
		end
		return nil
	end

	function ConfigManager:Exists(name)
		return self:ResolveName(name) ~= nil
	end

	function ConfigManager:Initialize()
		if not self.FileSystem.Available then
			return false, "Your executor does not expose the filesystem APIs required for configs."
		end
		self.FileSystem:EnsureFolder(self.ConfigFolder)
		self.FileSystem:EnsureFolder(self.AccountFolder)
		local loaded = self.FileSystem:ReadJson(self.AccountPath, self.Account)
		for key, value in pairs(loaded) do self.Account[key] = value end
		self.Account.Schema = 2
		self.Account.UserId = self.Player.UserId
		self.Account.UserName = self.Player.Name
		self.Account.Session = type(self.Account.Session) == "table" and self.Account.Session or {AutoExecute = false}

		local names = self:List()
		if #names == 0 then
			local ok, err = self:Create("main")
			if not ok then return false, err end
			names = self:List()
		end
		local selected = self:ResolveName(self.Account.SelectedConfig)
		self.Account.SelectedConfig = selected or names[1] or "main"
		self:SaveAccount()
		return true
	end

	function ConfigManager:SaveAccount()
		self.Account.UpdatedAt = os.time()
		return self.FileSystem:WriteJson(self.AccountPath, self.Account)
	end

	function ConfigManager:Create(name)
		name = self:SanitizeName(name)
		if name == "" then return false, "Config name cannot be empty." end
		if self:Exists(name) then return false, "A config with that name already exists." end
		local now = os.time()
		local data = {
			Schema = 2,
			Name = name,
			OwnerUserId = self.Player.UserId,
			OwnerUserName = self.Player.Name,
			CreatedAt = now,
			UpdatedAt = now,
			PlaceId = Build.PlaceId,
			Values = self.Registry:Snapshot(),
		}
		local ok, err = self.FileSystem:WriteJson(self:_ConfigPath(name), data)
		if ok then
			self.Account.SelectedConfig = name
			self:SaveAccount()
		end
		return ok, err
	end

	function ConfigManager:Delete(name)
		name = self:ResolveName(name)
		if #self:List() <= 1 then
			return false, "At least one config must exist. The last config cannot be deleted."
		end
		if not name then return false, "Selected config does not exist." end
		local ok, err = self.FileSystem:Delete(self:_ConfigPath(name))
		if not ok then return false, err end
		if self.Account.SelectedConfig == name then
			self.Account.SelectedConfig = self:List()[1]
		end
		self:SaveAccount()
		return true
	end

	function ConfigManager:SetSelected(name)
		local resolved = type(name) == "string" and self:ResolveName(name) or nil
		if not resolved then return false, "Invalid config selection." end
		self.Account.SelectedConfig = resolved
		self:SaveAccount()
		return true
	end

	function ConfigManager:Save(name)
		name = self:ResolveName(name or self.Account.SelectedConfig)
		if not name then return false, "Selected config does not exist." end
		local old = self.FileSystem:ReadJson(self:_ConfigPath(name), {})
		local now = os.time()
		local data = {
			Schema = 2,
			Name = name,
			OwnerUserId = old.OwnerUserId or self.Player.UserId,
			OwnerUserName = old.OwnerUserName or self.Player.Name,
			CreatedAt = old.CreatedAt or now,
			UpdatedAt = now,
			LastSavedByUserId = self.Player.UserId,
			LastSavedByUserName = self.Player.Name,
			PlaceId = Build.PlaceId,
			Values = self.Registry:Snapshot(),
		}
		return self.FileSystem:WriteJson(self:_ConfigPath(name), data)
	end

	function ConfigManager:Load(name)
		name = self:ResolveName(name or self.Account.SelectedConfig)
		if not name then return false, "Selected config does not exist." end
		local data = self.FileSystem:ReadJson(self:_ConfigPath(name), nil)
		if type(data) ~= "table" or type(data.Values) ~= "table" then
			return false, "Config is invalid or corrupted."
		end
		self.Account.SelectedConfig = name
		self:SaveAccount()
		self.Registry:Apply(data.Values)
		return true, data
	end

	function ConfigManager:ScheduleAutoSave()
		if not self.Account.AutoSave or not self.Alive then return end
		self.SaveNonce = self.SaveNonce + 1
		local nonce = self.SaveNonce
		task.delay(0.35, function()
			if self.Alive and self.Account.AutoSave and nonce == self.SaveNonce then
				local ok, err = self:Save(self.Account.SelectedConfig)
				if not ok then Util.Warn("auto-save failed: " .. tostring(err)) end
			end
		end)
	end

	function ConfigManager:Destroy()
		self.Alive = false
		self.SaveNonce = self.SaveNonce + 1
	end

	return ConfigManager
end
