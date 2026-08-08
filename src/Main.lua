return function(Import)
	local Build = Import("Build")
	local Util = Import("Util")
	local Janitor = Import("Janitor")
	local FileSystem = Import("FileSystem")
	local ControlRegistry = Import("ControlRegistry")
	local ConfigManager = Import("ConfigManager")
	local SessionManager = Import("SessionManager")
	local ModuleManager = Import("ModuleManager")
	local UIManager = Import("UIManager")
	local MacLibProvider = Import("MacLibProvider")
	local GameAdapter = Import("GameAdapter")
	local MiscModule = Import("Misc")
	local AutoClaimModule = Import("AutoClaim")
	local AutoSummonModule = Import("AutoSummon")
	local PerformanceModule = Import("Performance")
	local AutoTraitRerollModule = Import("AutoTraitReroll")
	local SettingsModule = Import("Settings")

	local Players = game:GetService("Players")
	local CoreGui = game:GetService("CoreGui")
	local LocalPlayer = Players.LocalPlayer
	local Environment = (getgenv and getgenv()) or _G

	local previousRuntime = rawget(Environment, "__ANIME_EXPEDITIONS_RUNTIME")
	if type(previousRuntime) == "table" and type(previousRuntime.Shutdown) == "function" then
		pcall(function() previousRuntime:Shutdown("re-executed") end)
		task.wait()
	end
	local generation = (tonumber(rawget(Environment, "__ANIME_EXPEDITIONS_GENERATION")) or 0) + 1
	Environment.__ANIME_EXPEDITIONS_GENERATION = generation

	local Runtime = {
		Alive = true,
		ShuttingDown = false,
		Janitor = Janitor.new(),
		Window = nil,
		MacLib = nil,
		MacGui = nil,
		Build = Build,
		Generation = generation,
	}
	Environment.__ANIME_EXPEDITIONS_RUNTIME = Runtime

	function Runtime:Notify(title, description)
		if self.Window then
			Util.SafeCall("notification", self.Window.Notify, self.Window, {
				Title = tostring(title),
				Description = tostring(description),
				Lifetime = 5,
			})
		else
			Util.Warn(title .. ": " .. description)
		end
	end

	function Runtime:Shutdown(reason, windowAlreadyUnloaded)
		if self.ShuttingDown then return end
		self.ShuttingDown = true
		if self.Registry then self.Registry.OnChanged = nil end
		if self.Config then
			local flushOk, flushError = self.Config:Flush(true)
			if not flushOk then Util.Warn("final config flush failed: " .. tostring(flushError)) end
		end
		self.Alive = false
		if self.UIManager then self.UIManager:Destroy() end
		if self.Modules then self.Modules:DestroyAll() end
		if self.Session then self.Session:Destroy() end
		if self.Config then self.Config:Destroy() end
		self.Janitor:Cleanup()
		if self.Window and not windowAlreadyUnloaded then
			-- The inspected MacLib release leaves its global window key listener alive.
			-- Making it Unknown prevents an old generation from reacting after re-execution.
			Util.SafeCall("disable old UI keybind", self.Window.SetKeybind, self.Window, Enum.KeyCode.Unknown)
			Util.SafeCall("unload old window", self.Window.Unload, self.Window)
		end
		if self.MacGui and self.MacGui.Parent then
			Util.SafeCall("destroy MacLib GUI", self.MacGui.Destroy, self.MacGui)
		end
		if rawget(Environment, "__ANIME_EXPEDITIONS_RUNTIME") == self then
			Environment.__ANIME_EXPEDITIONS_RUNTIME = nil
		end
		self.Reason = reason
	end

	local function guiParent()
		if type(gethui) == "function" then
			local ok, value = pcall(gethui)
			if ok then return value end
		end
		return CoreGui
	end

	local function captureChildren(parent)
		local output = {}
		for _, child in ipairs(parent:GetChildren()) do output[child] = true end
		return output
	end

	local FileStore = FileSystem.new(Build.DataRoot)
	local Registry = ControlRegistry.new()
	Runtime.Registry = Registry
	local Config = ConfigManager.new(FileStore, Registry, LocalPlayer)
	Runtime.Config = Config
	local configOk, configError = Config:Initialize()
	if not configOk then
		Runtime:Shutdown("config initialization failed", true)
		error(configError)
	end

	local parent = guiParent()
	local beforeGui = captureChildren(parent)
	local MacLib = MacLibProvider.Load()
	Runtime.MacLib = MacLib
	local deviceClass = UIManager.DeviceClass()
	local accountKey = Enum.KeyCode[tostring(Config.Account.UI.ToggleKey)] or Enum.KeyCode.RightShift
	local Window = MacLib:Window({
		Title = Build.Name,
		Subtitle = "v" .. Build.Version,
		Size = UIManager.BaseSize(deviceClass),
		DragStyle = 1,
		DisabledWindowControls = {},
		ShowUserInfo = Config.Account.UI.HidePrivateInfo ~= true,
		Keybind = accountKey,
		AcrylicBlur = Config.Account.UI.UIBlur == true,
	})
	Runtime.Window = Window
	local ResponsiveUI = UIManager.new(Window, Config.Account)
	Runtime.UIManager = ResponsiveUI

	-- These use MacLib's own global-settings menu. Privacy is expressed as a
	-- positive "hide" toggle so its safe/default state is visually on.
	Window:GlobalSetting({
		Name = "UI Blur",
		Default = Config.Account.UI.UIBlur == true,
		Callback = function(enabled)
			Window:SetAcrylicBlurState(enabled == true)
			Config:UpdateAccount(function(account) account.UI.UIBlur = enabled == true end, false)
		end,
	})
	Window:GlobalSetting({
		Name = "Hide Private Info",
		Default = Config.Account.UI.HidePrivateInfo ~= false,
		Callback = function(hidden)
			Window:SetUserInfoState(hidden ~= true)
			Config:UpdateAccount(function(account) account.UI.HidePrivateInfo = hidden == true end, false)
		end,
	})

	for _, child in ipairs(parent:GetChildren()) do
		if not beforeGui[child] and child:IsA("ScreenGui") then
			Runtime.MacGui = child
			child.Name = "AnimeExpeditions_MacLib"
			break
		end
	end

	local TabGroup = Window:TabGroup()
	local Tabs = {
		Misc = TabGroup:Tab({Name = "Misc", Image = "rbxassetid://10734950309"}),
		Settings = TabGroup:Tab({Name = "Settings", Image = "rbxassetid://10734950020"}),
	}

	local Context = {
		Runtime = Runtime,
		Window = Window,
		MacLib = MacLib,
		Tabs = Tabs,
		Registry = Registry,
		Config = Config,
		FileSystem = FileStore,
		Player = LocalPlayer,
		Build = Build,
		UIManager = ResponsiveUI,
		Game = GameAdapter.new(),
	}
	local Session = SessionManager.new(Runtime, Config)
	Context.Session = Session
	Runtime.Session = Session

	local Modules = ModuleManager.new(Context)
	Runtime.Modules = Modules
	Modules:Register(MiscModule)
	Modules:Register(AutoClaimModule)
	Modules:Register(AutoSummonModule)
	Modules:Register(PerformanceModule)
	Modules:Register(AutoTraitRerollModule)
	Modules:Register(SettingsModule)

	Registry.OnChanged = function() Config:ScheduleAutoSave() end
	local modulesOk, modulesError = Modules:LoadAll()
	if not modulesOk then
		Runtime:Shutdown("module load failure")
		error(modulesError)
	end

	-- Applying through setters restores both the visual control and feature callback.
	if Config.Account.AutoLoadSelected then
		local ok, err = Config:Load(Config.Account.SelectedConfig)
		if not ok then
			Runtime:Notify("Config load failed", tostring(err))
			Registry:Apply({})
		end
	else
		Registry:Apply({})
	end

	if Config.Account.UI.HiddenOnExecute == true then Window:SetState(false) end
	Window.onUnloaded(function() Runtime:Shutdown("window unloaded", true) end)
	Tabs.Misc:Select()
	Runtime:Notify("Loaded", string.format(
		"Account %s | Config %s",
		LocalPlayer.Name,
		Config.Account.SelectedConfig
	))

	return Runtime
end
