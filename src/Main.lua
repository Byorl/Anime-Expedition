return function(Import)
	local Build = Import("Build")
	local Util = Import("Util")
	local Janitor = Import("Janitor")
	local FileSystem = Import("FileSystem")
	local ControlRegistry = Import("ControlRegistry")
	local ConfigManager = Import("ConfigManager")
	local SessionManager = Import("SessionManager")
	local ModuleManager = Import("ModuleManager")
	local MacLibProvider = Import("MacLibProvider")
	local MiscModule = Import("Misc")
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

	local Runtime = {
		Alive = true,
		ShuttingDown = false,
		Janitor = Janitor.new(),
		Window = nil,
		MacLib = nil,
		MacGui = nil,
		Build = Build,
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
		self.Alive = false
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
	local Window = MacLib:Window({
		Title = Build.Name,
		Subtitle = "Remote Modules | v" .. Build.Version,
		Size = UDim2.fromOffset(868, 650),
		DragStyle = 1,
		DisabledWindowControls = {},
		ShowUserInfo = true,
		Keybind = Enum.KeyCode.RightShift,
		AcrylicBlur = true,
	})
	Runtime.Window = Window

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
	}
	local Session = SessionManager.new(Runtime, Config)
	Context.Session = Session
	Runtime.Session = Session

	local Modules = ModuleManager.new(Context)
	Runtime.Modules = Modules
	Modules:Register(MiscModule)
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

	if Registry:Get("misc.hide_ui_on_execute") == true then Window:SetState(false) end
	Window.onUnloaded(function() Runtime:Shutdown("window unloaded", true) end)
	Tabs.Misc:Select()
	Runtime:Notify("Loaded", string.format(
		"Account %s | Config %s | %d remote modules",
		LocalPlayer.Name,
		Config.Account.SelectedConfig,
		#Modules.Order
	))

	return Runtime
end
