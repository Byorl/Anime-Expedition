local Hub = ...
local Library = Hub.Core.Library

local UI = {}
UI.__index = UI

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
	local source = game:HttpGet("https://github.com/biggaboy212/Maclib/releases/latest/download/maclib.txt")
	local chunk = assert(loadstring(source), "Failed to load MacLib")
	self.MacLib = chunk()
	return self.MacLib
end

function UI:BindToggle(section, opts)
	local hub = self.Hub
	local flag = opts.Flag
	local default = hub.Config:GetValue(flag, opts.Default == true)

	local element = section:Toggle({
		Name = opts.Name,
		Default = default == true,
		Callback = function(value)
			hub.Config:SetValue(flag, value == true, { SkipUi = true })
			if opts.Callback then
				opts.Callback(value == true)
			end
		end,
	}, flag)

	element.IgnoreConfig = true
	hub.Config:RegisterElement(flag, element, "Toggle")
	hub.Config.Values[flag] = default == true
	return element
end

function UI:BindSlider(section, opts)
	local hub = self.Hub
	local flag = opts.Flag
	local default = hub.Config:GetValue(flag, opts.Default)

	local element = section:Slider({
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

	element.IgnoreConfig = true
	hub.Config:RegisterElement(flag, element, "Slider")
	hub.Config.Values[flag] = tonumber(default) or tonumber(opts.Default) or 0
	return element
end

function UI:BindInput(section, opts)
	local hub = self.Hub
	local flag = opts.Flag
	local default = hub.Config:GetValue(flag, opts.Default or "")

	local element = section:Input({
		Name = opts.Name,
		Placeholder = opts.Placeholder or "",
		AcceptedCharacters = opts.AcceptedCharacters or "All",
		Callback = function(text)
			hub.Config:SetValue(flag, text, { SkipUi = true })
			if opts.Callback then
				opts.Callback(text)
			end
		end,
	}, flag)

	element.IgnoreConfig = true
	hub.Config:RegisterElement(flag, element, "Input")
	hub.Config.Values[flag] = tostring(default or "")
	pcall(element.UpdateText, element, tostring(default or ""))
	return element
end

function UI:BindDropdown(section, opts)
	local hub = self.Hub
	local flag = opts.Flag
	local options = opts.Options or {}
	local default = hub.Config:GetValue(flag, opts.Default)

	local element = section:Dropdown({
		Name = opts.Name,
		Search = opts.Search == true,
		Multi = opts.Multi == true,
		Required = opts.Required == true,
		Options = options,
		Default = default or opts.Default,
		Callback = function(value)
			hub.Config:SetValue(flag, value, { SkipUi = true })
			if opts.Callback then
				opts.Callback(value)
			end
		end,
	}, flag)

	element.IgnoreConfig = true
	hub.Config:RegisterElement(flag, element, "Dropdown")
	if default ~= nil then
		hub.Config.Values[flag] = default
	end
	return element
end

function UI:_refreshConfigDropdown()
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

	local current = self.Hub.Config:GetCurrentDisplayName()
	if current then
		self.SelectedConfigLabel = current
		pcall(self.ConfigDropdown.UpdateSelection, self.ConfigDropdown, current)
	end
end

function UI:_buildConfigTab(tab)
	local hub = self.Hub
	local left = tab:Section({ Side = "Left" })
	local right = tab:Section({ Side = "Right" })

	left:Header({ Name = "Smart Configs" })
	left:Paragraph({
		Header = "Per-account active config",
		Body = "Configs are shared on this PC. Each Roblox account remembers its own last loaded config. Loading applies every toggle, slider, and module state.",
	})

	left:Input({
		Name = "New Config Name",
		Placeholder = "e.g. Main Farm",
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
		Name = "Saved Configs",
		Search = true,
		Multi = false,
		Required = false,
		Options = (#names > 0) and names or { "No configs yet" },
		Default = 1,
		Callback = function(value)
			if value ~= "No configs yet" then
				self.SelectedConfigLabel = value
			end
		end,
	})
	self.ConfigDropdown.IgnoreConfig = true

	left:Button({
		Name = "Create Config",
		Callback = function()
			local ok, result = hub.Config:Create(self.ConfigNameInput)
			if ok then
				self:_refreshConfigDropdown()
				Library.Notify(hub.Window, "Config", "Created '" .. tostring(result.Name) .. "'")
			else
				Library.Notify(hub.Window, "Config", tostring(result))
			end
		end,
	})

	left:Button({
		Name = "Save Config",
		Callback = function()
			local target = hub.Config:FindByDisplayName(self.SelectedConfigLabel) or hub.Config:FindById(hub.Config.CurrentId)
			local ok, result = hub.Config:Save(target and target.Id or nil)
			if ok then
				self:_refreshConfigDropdown()
				Library.Notify(hub.Window, "Config", "Saved '" .. tostring(result.Name) .. "'")
			else
				Library.Notify(hub.Window, "Config", tostring(result))
			end
		end,
	})

	left:Button({
		Name = "Load Config",
		Callback = function()
			local label = self.SelectedConfigLabel
			local ok, result = hub.Config:Load(label)
			if ok then
				self:_refreshConfigDropdown()
				Library.Notify(hub.Window, "Config", "Loaded '" .. tostring(result.Name) .. "' — UI + modules synced")
			else
				Library.Notify(hub.Window, "Config", tostring(result))
			end
		end,
	})

	left:Button({
		Name = "Delete Config",
		Callback = function()
			local entry = hub.Config:FindByDisplayName(self.SelectedConfigLabel)
			if not entry then
				Library.Notify(hub.Window, "Config", "Select a config first.")
				return
			end
			local ok, err = hub.Config:Delete(entry.Id)
			if ok then
				self.SelectedConfigLabel = nil
				self:_refreshConfigDropdown()
				Library.Notify(hub.Window, "Config", "Deleted '" .. tostring(entry.Name) .. "'")
			else
				Library.Notify(hub.Window, "Config", tostring(err))
			end
		end,
	})

	right:Header({ Name = "Account Prefs" })
	right:Paragraph({
		Header = "Owner stamping",
		Body = "Every config stores the creator UserId + name. Any account can load any shared config. Your prefs file only tracks which config YOU last used.",
	})

	local autoLoad = hub.Config.Prefs.AutoLoad ~= false
	local autoToggle = right:Toggle({
		Name = "Auto-load last config",
		Default = autoLoad,
		Callback = function(value)
			hub.Config.Prefs.AutoLoad = value == true
			hub.Config:_saveUserPrefs()
		end,
	})
	autoToggle.IgnoreConfig = true

	right:Button({
		Name = "Refresh Config List",
		Callback = function()
			self:_refreshConfigDropdown()
			Library.Notify(hub.Window, "Config", "List refreshed")
		end,
	})

	right:Button({
		Name = "Unload Hub",
		Callback = function()
			hub:Unload()
		end,
	})
end

function UI:Build()
	local hub = self.Hub
	self:LoadMacLib()

	self.Window = self.MacLib:Window({
		Title = "AEHub",
		Subtitle = "Anime Expeditions  ·  v" .. Library.Version,
		Size = UDim2.fromOffset(860, 640),
		DragStyle = 1,
		DisabledWindowControls = {},
		ShowUserInfo = true,
		Keybind = Enum.KeyCode.RightControl,
		AcrylicBlur = false,
	})
	hub.Window = self.Window

	pcall(function()
		self.Window.onUnloaded(function()
			if hub.Alive then
				hub:Unload(true)
			end
		end)
	end)

	local tabGroup = self.Window:TabGroup()
	self.Tabs.Misc = tabGroup:Tab({ Name = "Misc" })
	self.Tabs.Config = tabGroup:Tab({ Name = "Configs" })

	hub.Modules:BuildUi(self.Window, self.Tabs)
	self:_buildConfigTab(self.Tabs.Config)

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
