local function resolveHub(...)
	local viaVarargs = ...
	if typeof(viaVarargs) == "table" and viaVarargs.Core ~= nil then
		return viaVarargs
	end
	local env = (getgenv and getgenv()) or shared or _G
	return env.__AEHubLoading
end

local Hub = resolveHub(...)
assert(Hub and Hub.Core and Hub.Core.Library, "[Anime Expeditions] Hub context missing while loading UI")
local Library = Hub.Core.Library

local UI = {}
UI.__index = UI

local function safeHeader(section, text)
	local ok = pcall(function()
		section:Header({ Text = text })
	end)
	if ok then
		return
	end
	pcall(function()
		section:Header({ Name = text })
	end)
end

function UI.new(hub)
	local self = setmetatable({}, UI)
	self.Hub = hub
	self.MacLib = nil
	self.Window = nil
	self.Tabs = {}
	self.SelectedConfigLabel = nil
	self.ConfigNameInput = ""
	self.ConfigDropdown = nil
	return self
end

function UI:LoadMacLib()
	local urls = {
		"https://github.com/biggaboy212/Maclib/releases/download/9.Maclib/maclib.txt",
		"https://raw.githubusercontent.com/biggaboy212/Public-Resources/main/MacLib/maclib.lua",
		"https://github.com/biggaboy212/Maclib/releases/latest/download/maclib.txt",
	}

	local lastErr
	for index, url in ipairs(urls) do
		print("[Anime Expeditions] Fetching MacLib (" .. index .. "/" .. #urls .. ")")
		local okGet, source = pcall(function()
			return game:HttpGet(url)
		end)
		if okGet and typeof(source) == "string" and #source > 100 then
			local chunk, compileErr = loadstring(source, "@MacLib/" .. index)
			if typeof(chunk) ~= "function" then
				chunk, compileErr = loadstring(source)
			end
			if typeof(chunk) == "function" then
				local okRun, result = xpcall(chunk, function(err)
					return Library.FormatError and Library.FormatError(err) or tostring(err)
				end)
				if okRun and typeof(result) == "table" and typeof(result.Window) == "function" then
					self.MacLib = result
					return self.MacLib
				end
				lastErr = result
			else
				lastErr = compileErr
			end
		else
			lastErr = source
		end
	end

	error("[Anime Expeditions] Failed to load MacLib:\n" .. tostring(lastErr), 0)
end

function UI:BindToggle(section, opts)
	local hub = self.Hub
	local flag = opts.Flag
	local default = hub.Config:GetValue(flag, opts.Default == true)

	local ok, element = pcall(function()
		return section:Toggle({
			Name = opts.Name,
			Default = default == true,
			Callback = function(value)
				hub.Config:SetValue(flag, value == true, { SkipUi = true })
				if opts.Callback then
					opts.Callback(value == true)
				end
			end,
		}, flag)
	end)

	if not ok or not element then
		error("[Anime Expeditions] Toggle bind failed for '" .. tostring(flag) .. "': " .. tostring(element), 0)
	end

	pcall(function()
		element.IgnoreConfig = true
	end)
	hub.Config:RegisterElement(flag, element, "Toggle")
	hub.Config.Values[flag] = default == true
	return element
end

function UI:BindSlider(section, opts)
	local hub = self.Hub
	local flag = opts.Flag
	local default = hub.Config:GetValue(flag, opts.Default)

	local ok, element = pcall(function()
		return section:Slider({
			Name = opts.Name,
			Default = tonumber(default) or tonumber(opts.Default) or 0,
			Minimum = opts.Minimum or 0,
			Maximum = opts.Maximum or 100,
			DisplayMethod = opts.DisplayMethod or "Value",
			Precision = opts.Precision or 0,
			Callback = function(value)
				hub.Config:SetValue(flag, value, { SkipUi = true })
				if opts.Callback then
					opts.Callback(value)
				end
			end,
		}, flag)
	end)

	if not ok or not element then
		error("[Anime Expeditions] Slider bind failed for '" .. tostring(flag) .. "': " .. tostring(element), 0)
	end

	pcall(function()
		element.IgnoreConfig = true
	end)
	hub.Config:RegisterElement(flag, element, "Slider")
	hub.Config.Values[flag] = tonumber(default) or tonumber(opts.Default) or 0
	return element
end

function UI:_refreshConfigDropdown(selectName)
	if not self.ConfigDropdown then
		return
	end
	local names = self.Hub.Config:GetDisplayNames()
	pcall(function()
		self.ConfigDropdown:ClearOptions()
		if #names > 0 then
			self.ConfigDropdown:InsertOptions(names)
		end
	end)

	local current = selectName or self.Hub.Config:GetCurrentDisplayName()
	if current then
		self.SelectedConfigLabel = current
		pcall(self.ConfigDropdown.UpdateSelection, self.ConfigDropdown, current)
	end
end

function UI:GetDeviceDefaults()
	local touch = false
	local keyboard = true
	pcall(function()
		local UIS = game:GetService("UserInputService")
		touch = UIS.TouchEnabled == true
		keyboard = UIS.KeyboardEnabled == true
	end)

	local mobile = touch and not keyboard
	if mobile then
		return {
			Scale = 0.7,
			Size = UDim2.fromOffset(620, 460),
			DragStyle = 2,
		}
	end
	if touch then
		return {
			Scale = 0.85,
			Size = UDim2.fromOffset(720, 520),
			DragStyle = 2,
		}
	end
	return {
		Scale = 1,
		Size = UDim2.fromOffset(860, 620),
		DragStyle = 1,
	}
end

function UI:ApplySetting(flag, value)
	if flag == "Settings.UIScale" then
		local scale = tonumber(value)
		if not scale then
			return
		end
		scale = math.max(0.45, math.min(1.4, scale))
		self:SetWindowScale(scale)
		if self.Hub and self.Hub.Config then
			self.Hub.Config.Prefs.UIScale = scale
			pcall(function()
				self.Hub.Config:_saveUserPrefs()
			end)
		end
	elseif flag == "Settings.AutoSave" then
		if self.Hub and self.Hub.Config then
			self.Hub.Config.Prefs.AutoSave = value == true
			pcall(function()
				self.Hub.Config:_saveUserPrefs()
			end)
		end
	elseif flag == "Settings.UIToggleKey" then
		local keyName = typeof(value) == "EnumItem" and value.Name or tostring(value or "")
		local keyCode = Enum.KeyCode[keyName]
		if not keyCode then
			return
		end
		local window = self.Window or (self.Hub and self.Hub.Window)
		if window and typeof(window.SetKeybind) == "function" then
			pcall(function()
				window:SetKeybind(keyCode)
			end)
		end
		if self.Hub and self.Hub.Config then
			self.Hub.Config.Prefs.UIToggleKey = keyName
			self.Hub.Config.Values["Settings.UIToggleKey"] = keyName
			pcall(function()
				self.Hub.Config:_saveUserPrefs()
			end)
		end
	end
end

function UI:SetWindowScale(scale)
	scale = math.max(0.45, math.min(1.4, tonumber(scale) or 1))
	self.CurrentScale = scale
	local window = self.Window or (self.Hub and self.Hub.Window)
	if not window then
		return
	end
	local ok = pcall(function()
		window:SetScale(scale)
	end)
	if not ok and window.SetSize and self.BaseSize then
		pcall(function()
			local base = self.BaseSize
			window:SetSize(UDim2.fromOffset(
				math.floor(base.X.Offset * scale),
				math.floor(base.Y.Offset * scale)
			))
		end)
	end
end

function UI:_buildSettingsTab(tab)
	local hub = self.Hub
	local left = tab:Section({ Side = "Left" })
	local right = tab:Section({ Side = "Right" })

	safeHeader(left, "Configs")

	left:Input({
		Name = "Name",
		Placeholder = "Config name",
		AcceptedCharacters = "All",
		Callback = function(text)
			self.ConfigNameInput = text
		end,
		onChanged = function(text)
			self.ConfigNameInput = text
		end,
	})

	local names = hub.Config:GetDisplayNames()
	self.ConfigDropdown = left:Dropdown({
		Name = "Config",
		Search = true,
		Multi = false,
		Required = false,
		Options = (#names > 0) and names or { "main" },
		Default = 1,
		Callback = function(value)
			if value and value ~= "" then
				self.SelectedConfigLabel = value
			end
		end,
	})
	pcall(function()
		self.ConfigDropdown.IgnoreConfig = true
	end)

	local currentLabel = hub.Config:GetCurrentDisplayName()
	if currentLabel then
		self.SelectedConfigLabel = currentLabel
		pcall(self.ConfigDropdown.UpdateSelection, self.ConfigDropdown, currentLabel)
	elseif #names > 0 then
		self.SelectedConfigLabel = names[1]
	end

	left:Button({
		Name = "Create",
		Callback = function()
			local ok, result = hub.Config:Create(self.ConfigNameInput)
			if ok then
				self:_refreshConfigDropdown(result.Name)
				Library.Notify(hub.Window, "Configs", "Created " .. tostring(result.Name))
			else
				Library.Notify(hub.Window, "Configs", tostring(result))
			end
		end,
	})

	left:Button({
		Name = "Save",
		Callback = function()
			local target = hub.Config:FindByDisplayName(self.SelectedConfigLabel) or hub.Config:FindById(hub.Config.CurrentId)
			local ok, result = hub.Config:Save(target and target.Id or nil)
			if ok then
				self:_refreshConfigDropdown(result.Name)
				Library.Notify(hub.Window, "Configs", "Saved " .. tostring(result.Name))
			else
				Library.Notify(hub.Window, "Configs", tostring(result))
			end
		end,
	})

	left:Button({
		Name = "Load",
		Callback = function()
			local ok, result = hub.Config:Load(self.SelectedConfigLabel)
			if ok then
				self:_refreshConfigDropdown(result.Name)
				Library.Notify(hub.Window, "Configs", "Loaded " .. tostring(result.Name))
			else
				Library.Notify(hub.Window, "Configs", tostring(result))
			end
		end,
	})

	left:Button({
		Name = "Set Auto Load",
		Callback = function()
			local ok, result = hub.Config:SetAutoLoadConfig(self.SelectedConfigLabel)
			if ok then
				self:_refreshConfigDropdown(result.Name)
				Library.Notify(hub.Window, "Configs", "Auto load: " .. tostring(result.Name))
			else
				Library.Notify(hub.Window, "Configs", tostring(result))
			end
		end,
	})

	left:Button({
		Name = "Delete",
		Callback = function()
			local entry = hub.Config:FindByDisplayName(self.SelectedConfigLabel)
			if not entry then
				Library.Notify(hub.Window, "Configs", "Select a config first")
				return
			end
			local ok, err = hub.Config:Delete(entry.Id)
			if ok then
				self.SelectedConfigLabel = nil
				hub.Config:EnsureMainConfig()
				self:_refreshConfigDropdown()
				Library.Notify(hub.Window, "Configs", "Deleted " .. tostring(entry.Name))
			else
				Library.Notify(hub.Window, "Configs", tostring(err))
			end
		end,
	})

	left:Button({
		Name = "Refresh",
		Callback = function()
			self:_refreshConfigDropdown()
		end,
	})

	safeHeader(right, "Settings")

	local defaultScale = hub.Config:GetValue("Settings.UIScale", self.CurrentScale or 1)
	self:BindSlider(right, {
		Name = "UI Scale",
		Default = tonumber(defaultScale) or 1,
		Minimum = 0.45,
		Maximum = 1.35,
		Precision = 2,
		DisplayMethod = "Value",
		Flag = "Settings.UIScale",
		Callback = function(value)
			self:ApplySetting("Settings.UIScale", value)
		end,
	})

	self:BindToggle(right, {
		Name = "Auto Save",
		Default = hub.Config.Prefs.AutoSave == true,
		Flag = "Settings.AutoSave",
		Callback = function(value)
			self:ApplySetting("Settings.AutoSave", value)
		end,
	})

	do
		local defaultKeyName = hub.Config.Prefs.UIToggleKey or "RightControl"
		if typeof(hub.Config.Values["Settings.UIToggleKey"]) == "string" then
			defaultKeyName = hub.Config.Values["Settings.UIToggleKey"]
		end
		local defaultKey = Enum.KeyCode[defaultKeyName] or Enum.KeyCode.RightControl
		hub.Config.Values["Settings.UIToggleKey"] = defaultKey.Name

		local keybind = right:Keybind({
			Name = "Toggle UI",
			Default = defaultKey,
			onBinded = function(key)
				if typeof(key) == "EnumItem" then
					hub.Config:SetValue("Settings.UIToggleKey", key.Name, { SkipUi = true })
				end
			end,
		})
		pcall(function()
			keybind.IgnoreConfig = true
		end)
		hub.Config:RegisterElement("Settings.UIToggleKey", keybind, "Keybind")
		self.UIToggleKeybind = keybind
	end

	right:Button({
		Name = "Unload",
		Callback = function()
			local ok, err = pcall(function()
				hub:Unload()
			end)
			if not ok then
				warn("[Anime Expeditions] Unload failed: " .. tostring(err))
				pcall(function()
					hub:ForceUnload()
				end)
			end
		end,
	})

	right:Button({
		Name = "Force Unload",
		Callback = function()
			local env = (getgenv and getgenv()) or shared or _G
			pcall(function()
				if hub.ForceUnload then
					hub:ForceUnload()
				end
			end)
			pcall(function()
				if typeof(env.AEHubForceUnload) == "function" then
					env.AEHubForceUnload()
				end
			end)
		end,
	})
end

function UI:Build()
	local hub = self.Hub
	self:LoadMacLib()

	if typeof(self.MacLib) ~= "table" or typeof(self.MacLib.Window) ~= "function" then
		error("[Anime Expeditions] MacLib.Window is missing", 0)
	end

	local device = self:GetDeviceDefaults()
	self.BaseSize = device.Size

	local preferredScale = hub.Config.Prefs.UIScale
	if typeof(preferredScale) ~= "number" then
		preferredScale = device.Scale
	end
	preferredScale = math.max(0.45, math.min(1.35, tonumber(preferredScale) or device.Scale))
	hub.Config.Values["Settings.UIScale"] = preferredScale
	hub.Config.Values["Settings.AutoSave"] = hub.Config.Prefs.AutoSave == true
	local toggleKeyName = hub.Config.Prefs.UIToggleKey or "RightControl"
	local toggleKey = Enum.KeyCode[toggleKeyName] or Enum.KeyCode.RightControl
	hub.Config.Values["Settings.UIToggleKey"] = toggleKey.Name
	self.CurrentScale = preferredScale

	local okWindow, windowOrErr = pcall(function()
		return self.MacLib:Window({
			Title = "Anime Expeditions",
			Subtitle = "v" .. Library.Version,
			Size = device.Size,
			DragStyle = device.DragStyle,
			DisabledWindowControls = {},
			ShowUserInfo = false,
			Keybind = toggleKey,
			AcrylicBlur = false,
		})
	end)
	if not okWindow then
		error("[Anime Expeditions] Window failed:\n" .. tostring(windowOrErr), 0)
	end

	self.Window = windowOrErr
	hub.Window = self.Window
	self:SetWindowScale(preferredScale)

	pcall(function()
		self.Window.onUnloaded(function()
			if hub.Alive then
				hub:Unload(true)
			end
		end)
	end)

	local tabGroup = self.Window:TabGroup()
	self.Tabs.Misc = tabGroup:Tab({ Name = "Misc" })
	self.Tabs.Settings = tabGroup:Tab({ Name = "Settings" })

	hub.Modules:BuildUi(self.Window, self.Tabs)
	self:_buildSettingsTab(self.Tabs.Settings)

	pcall(function()
		self.Tabs.Misc:Select()
	end)

	return self.Window
end

function UI:Destroy()
	if self.Window then
		pcall(function()
			self.Window:Unload()
		end)
		self.Window = nil
	end
	Library.DestroyUiInstances()
	self.MacLib = nil
	self.Tabs = {}
	self.ConfigDropdown = nil
end

return UI
