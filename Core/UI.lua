local function resolveHub(...)
	local viaVarargs = ...
	if typeof(viaVarargs) == "table" and viaVarargs.Core ~= nil then
		return viaVarargs
	end
	local env = (getgenv and getgenv()) or shared or _G
	return env.__AEHubLoading
end

local Hub = resolveHub(...)
assert(Hub and Hub.Core and Hub.Core.Library, "[AEHub] Hub context missing while loading UI")
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
	ok = pcall(function()
		section:Header({ Name = text })
	end)
	if not ok then
		warn("[AEHub] Header failed for: " .. tostring(text))
	end
end

local function safeParagraph(section, header, body)
	local ok = pcall(function()
		section:Paragraph({
			Header = header,
			Body = body,
		})
	end)
	if not ok then
		warn("[AEHub] Paragraph failed for: " .. tostring(header))
	end
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
		print("[AEHub] Fetching MacLib (" .. index .. "/" .. #urls .. "): " .. url)
		local okGet, source = pcall(function()
			return game:HttpGet(url)
		end)
		if not okGet then
			lastErr = "HttpGet error: " .. tostring(source)
			warn("[AEHub] " .. lastErr)
		elseif typeof(source) ~= "string" or #source < 100 then
			lastErr = "Bad MacLib payload type/size: " .. typeof(source) .. " / " .. tostring(source and #source)
			warn("[AEHub] " .. lastErr)
		else
			local chunk, compileErr = loadstring(source, "@MacLib/" .. index)
			if typeof(chunk) ~= "function" then
				chunk, compileErr = loadstring(source)
			end
			if typeof(chunk) ~= "function" then
				lastErr = "MacLib compile failed: " .. tostring(compileErr)
				warn("[AEHub] " .. lastErr)
			else
				local okRun, result = xpcall(chunk, function(err)
					return Library.FormatError and Library.FormatError(err) or tostring(err)
				end)
				if okRun and typeof(result) == "table" and typeof(result.Window) == "function" then
					self.MacLib = result
					print("[AEHub] MacLib loaded from #" .. index)
					return self.MacLib
				end
				lastErr = "MacLib runtime failed or missing Window(): " .. tostring(result)
				warn("[AEHub] " .. lastErr)
			end
		end
	end

	error("[AEHub] Failed to load MacLib after all fallbacks:\n" .. tostring(lastErr), 0)
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
		error("[AEHub] Toggle bind failed for '" .. tostring(flag) .. "': " .. tostring(element), 0)
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
		error("[AEHub] Slider bind failed for '" .. tostring(flag) .. "': " .. tostring(element), 0)
	end

	pcall(function()
		element.IgnoreConfig = true
	end)
	hub.Config:RegisterElement(flag, element, "Slider")
	hub.Config.Values[flag] = tonumber(default) or tonumber(opts.Default) or 0
	return element
end

function UI:BindInput(section, opts)
	local hub = self.Hub
	local flag = opts.Flag
	local default = hub.Config:GetValue(flag, opts.Default or "")

	local ok, element = pcall(function()
		return section:Input({
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
	end)

	if not ok or not element then
		error("[AEHub] Input bind failed for '" .. tostring(flag) .. "': " .. tostring(element), 0)
	end

	pcall(function()
		element.IgnoreConfig = true
	end)
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

	local ok, element = pcall(function()
		return section:Dropdown({
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
	end)

	if not ok or not element then
		error("[AEHub] Dropdown bind failed for '" .. tostring(flag) .. "': " .. tostring(element), 0)
	end

	pcall(function()
		element.IgnoreConfig = true
	end)
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

	safeHeader(left, "Smart Configs")
	safeParagraph(
		left,
		"Per-account active config",
		"Configs are shared on this PC. Each Roblox account remembers its own last loaded config. Loading applies every toggle, slider, and module state."
	)

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
	pcall(function()
		self.ConfigDropdown.IgnoreConfig = true
	end)

	-- If a config is already selected via prefs, keep label in sync
	local currentLabel = hub.Config:GetCurrentDisplayName()
	if currentLabel then
		self.SelectedConfigLabel = currentLabel
	elseif #names > 0 then
		self.SelectedConfigLabel = names[1]
	end

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
		Name = "Auto Load Config",
		Callback = function()
			local label = self.SelectedConfigLabel
			local ok, result = hub.Config:SetAutoLoadConfig(label)
			if ok then
				if self.AutoLoadToggle then
					pcall(function()
						self.AutoLoadToggle:UpdateState(true)
					end)
				end
				self:_refreshConfigDropdown()
				Library.Notify(
					hub.Window,
					"Config",
					"'" .. tostring(result.Name) .. "' will auto-load every execute"
				)
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

	safeHeader(right, "Account Prefs")
	safeParagraph(
		right,
		"Auto Load",
		"Press Auto Load Config while a config is selected to lock it as your boot config. Toggle below enables/disables that behavior."
	)

	local autoLoad = hub.Config.Prefs.AutoLoad == true
	self.AutoLoadToggle = right:Toggle({
		Name = "Auto Load Enabled",
		Default = autoLoad,
		Callback = function(value)
			hub.Config.Prefs.AutoLoad = value == true
			hub.Config:_saveUserPrefs()
			Library.Notify(
				hub.Window,
				"Config",
				value and "Auto Load on" or "Auto Load off"
			)
		end,
	})
	pcall(function()
		self.AutoLoadToggle.IgnoreConfig = true
	end)

	right:Button({
		Name = "Refresh Config List",
		Callback = function()
			self:_refreshConfigDropdown()
			Library.Notify(hub.Window, "Config", "List refreshed")
		end,
	})
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
	local hybrid = touch and keyboard

	if mobile then
		return {
			Scale = 0.55,
			Size = UDim2.fromOffset(540, 400),
			DragStyle = 2,
		}
	end
	if hybrid then
		return {
			Scale = 0.65,
			Size = UDim2.fromOffset(620, 460),
			DragStyle = 2,
		}
	end
	return {
		Scale = 0.75,
		Size = UDim2.fromOffset(720, 520),
		DragStyle = 1,
	}
end

function UI:ApplySetting(flag, value)
	if flag == "Settings.UIScale" then
		local scale = tonumber(value)
		if not scale then
			return
		end
		scale = math.max(0.35, math.min(1.5, scale))
		self:SetWindowScale(scale)
		if self.Hub and self.Hub.Config then
			self.Hub.Config.Prefs.UIScale = scale
			pcall(function()
				self.Hub.Config:_saveUserPrefs()
			end)
		end
	end
end

function UI:SetWindowScale(scale)
	scale = math.max(0.35, math.min(1.5, tonumber(scale) or 0.75))
	self.CurrentScale = scale
	local window = self.Window or (self.Hub and self.Hub.Window)
	if not window then
		return
	end
	local ok = pcall(function()
		window:SetScale(scale)
	end)
	if not ok then
		pcall(function()
			if window.SetSize and self.BaseSize then
				local base = self.BaseSize
				window:SetSize(UDim2.fromOffset(
					math.floor(base.X.Offset * scale),
					math.floor(base.Y.Offset * scale)
				))
			end
		end)
	end
end

function UI:_buildSettingsTab(tab)
	local hub = self.Hub
	local left = tab:Section({ Side = "Left" })
	local right = tab:Section({ Side = "Right" })

	safeHeader(left, "Display")
	safeParagraph(
		left,
		"UI Scale",
		"Drag to resize the whole hub live. Smaller by default on mobile. This value is saved into configs."
	)

	local defaultScale = hub.Config:GetValue("Settings.UIScale", self.CurrentScale or 0.75)
	hub.UI:BindSlider(left, {
		Name = "UI Scale",
		Default = tonumber(defaultScale) or 0.75,
		Minimum = 0.35,
		Maximum = 1.25,
		Precision = 2,
		DisplayMethod = "Value",
		Flag = "Settings.UIScale",
		Callback = function(value)
			self:ApplySetting("Settings.UIScale", value)
		end,
	})

	safeHeader(left, "Unload")
	safeParagraph(
		left,
		"Clean shutdown",
		"Disables every module, restores hooks, cancels threads, destroys the UI, and clears hub state so nothing duplicates on re-execute."
	)

	left:Button({
		Name = "Unload Hub",
		Callback = function()
			print("[AEHub] Settings: Unload Hub pressed")
			local ok, err = pcall(function()
				hub:Unload()
			end)
			if not ok then
				warn("[AEHub] Unload failed: " .. tostring(err))
				pcall(function()
					hub:ForceUnload()
				end)
			end
		end,
	})

	left:Button({
		Name = "Force Unload (nuclear)",
		Callback = function()
			print("[AEHub] Settings: Force Unload pressed")
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
			Library.Notify(nil, "AEHub", "Force unload complete")
		end,
	})

	safeHeader(right, "Hub Info")
	safeParagraph(
		right,
		"Runtime",
		"Version "
			.. tostring(Library.Version)
			.. " · Generation "
			.. tostring(hub.Generation)
			.. " · RightControl toggles UI"
	)

	right:Button({
		Name = "Print Status To Console",
		Callback = function()
			local modules = hub.Modules
			print("========== AEHub STATUS ==========")
			print("Alive:", hub.Alive, "Generation:", hub.Generation, "Scale:", self.CurrentScale)
			if modules and modules.Order then
				for _, id in modules.Order do
					local mod = modules:Get(id)
					print(id, "enabled=", mod and mod.Enabled, "state.Enabled=", mod and mod.State and mod.State.Enabled)
				end
			end
			print("==================================")
		end,
	})
end

function UI:Build()
	local hub = self.Hub
	self:LoadMacLib()

	if typeof(self.MacLib) ~= "table" or typeof(self.MacLib.Window) ~= "function" then
		error("[AEHub] MacLib.Window is missing after LoadMacLib", 0)
	end

	local device = self:GetDeviceDefaults()
	self.BaseSize = device.Size

	local preferredScale = hub.Config.Prefs.UIScale
	if typeof(preferredScale) ~= "number" then
		preferredScale = device.Scale
	end
	preferredScale = math.max(0.35, math.min(1.25, tonumber(preferredScale) or device.Scale))
	hub.Config.Values["Settings.UIScale"] = preferredScale
	self.CurrentScale = preferredScale

	local okWindow, windowOrErr = pcall(function()
		return self.MacLib:Window({
			Title = "AEHub",
			Subtitle = "Anime Expeditions  ·  v" .. Library.Version,
			Size = device.Size,
			DragStyle = device.DragStyle,
			DisabledWindowControls = {},
			ShowUserInfo = false,
			Keybind = Enum.KeyCode.RightControl,
			AcrylicBlur = false,
		})
	end)
	if not okWindow then
		error("[AEHub] MacLib:Window() failed:\n" .. tostring(windowOrErr), 0)
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
	self.Tabs.Config = tabGroup:Tab({ Name = "Configs" })
	self.Tabs.Settings = tabGroup:Tab({ Name = "Settings" })

	if not self.Tabs.Misc then
		error("[AEHub] Failed to create Misc tab", 0)
	end

	hub.Modules:BuildUi(self.Window, self.Tabs)
	self:_buildConfigTab(self.Tabs.Config)
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
