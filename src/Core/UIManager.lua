return function(Import)
	local Janitor = Import("Janitor")
	local UserInputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local UIManager = {}
	UIManager.__index = UIManager

	local BASE_SIZE = {
		Desktop = Vector2.new(800, 600),
		Mobile = Vector2.new(620, 465),
	}

	local DEFAULT_SCALE = {
		Desktop = 0.9,
		Mobile = 0.62,
	}

	local function viewportSize()
		local camera = workspace.CurrentCamera
		return camera and camera.ViewportSize or Vector2.new(1280, 720)
	end

	function UIManager.DeviceClass()
		local viewport = viewportSize()
		return UserInputService.TouchEnabled and (not UserInputService.KeyboardEnabled or viewport.X < 800)
			and "Mobile" or "Desktop"
	end

	function UIManager.BaseSize(device)
		local size = BASE_SIZE[device or UIManager.DeviceClass()] or BASE_SIZE.Desktop
		return UDim2.fromOffset(size.X, size.Y)
	end

	function UIManager.DefaultScale(device)
		return DEFAULT_SCALE[device or UIManager.DeviceClass()] or DEFAULT_SCALE.Desktop
	end

	function UIManager.new(window, account)
		local device = UIManager.DeviceClass()
		local stored = type(account.UI) == "table" and type(account.UI.Scale) == "table"
			and tonumber(account.UI.Scale[device]) or nil
		local self = setmetatable({
			Window = window,
			Account = account,
			Device = device,
			BasePixels = BASE_SIZE[device],
			RequestedScale = stored or UIManager.DefaultScale(device),
			CurrentScale = 0,
			TargetScale = 0,
			Janitor = Janitor.new(),
			Alive = true,
		}, UIManager)
		self.CurrentScale = self:_EffectiveScale(self.RequestedScale)
		self.TargetScale = self.CurrentScale
		window:SetScale(self.CurrentScale)

		self.Janitor:AddConnection(RunService.RenderStepped:Connect(function(deltaTime)
			if not self.Alive then return end
			local target = self:_EffectiveScale(self.RequestedScale)
			self.TargetScale = target
			local difference = target - self.CurrentScale
			if math.abs(difference) < 0.0005 then
				if self.CurrentScale ~= target then
					self.CurrentScale = target
					window:SetScale(target)
				end
				return
			end
			local alpha = 1 - math.exp(-math.min(deltaTime, 0.05) * 18)
			local step = math.clamp(difference * alpha, -0.018, 0.018)
			self.CurrentScale = self.CurrentScale + step
			window:SetScale(self.CurrentScale)
		end))
		return self
	end

	function UIManager:_ViewportFit()
		local viewport = viewportSize()
		local safeWidth = math.max(1, viewport.X - (self.Device == "Mobile" and 16 or 36))
		local safeHeight = math.max(1, viewport.Y - (self.Device == "Mobile" and 28 or 54))
		return math.min(safeWidth / self.BasePixels.X, safeHeight / self.BasePixels.Y, 1.2)
	end

	function UIManager:_EffectiveScale(requested)
		requested = math.clamp(tonumber(requested) or UIManager.DefaultScale(self.Device), 0.35, 1.2)
		return math.min(requested, self:_ViewportFit())
	end

	function UIManager:GetRequestedScale()
		return self.RequestedScale
	end

	function UIManager:SetRequestedScale(scale, immediate)
		self.RequestedScale = math.clamp(tonumber(scale) or self.RequestedScale, 0.35, 1.2)
		self.TargetScale = self:_EffectiveScale(self.RequestedScale)
		if immediate == true then
			self.CurrentScale = self.TargetScale
			self.Window:SetScale(self.CurrentScale)
		end
		return self.RequestedScale, self.TargetScale
	end

	function UIManager:Destroy()
		self.Alive = false
		self.Janitor:Cleanup()
	end

	return UIManager
end
