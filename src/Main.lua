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
	local JoinCoordinator = Import("JoinCoordinator")
	local ResultsHub = Import("ResultsHub")
	local WebhookReporter = Import("WebhookReporter")
	local JoinStoryModule = Import("JoinStory")
	local JoinChallengeModule = Import("JoinChallenge")
	local JoinEventModule = Import("JoinEvent")
	local JoinRaidModule = Import("JoinRaid")
	local AutoPlayModule = Import("AutoPlay")
	local GameMatchModule = Import("GameMatch")
	local GameEndModule = Import("GameEnd")
	local WebhookModule = Import("Webhook")
	local MiscModule = Import("Misc")
	local AutoClaimModule = Import("AutoClaim")
	local AutoSummonModule = Import("AutoSummon")
	local PerformanceModule = Import("Performance")
	local AutoTraitRerollModule = Import("AutoTraitReroll")
	local BountyModule = Import("Bounty")
	local JoinPriorityModule = Import("JoinPriority")
	local SettingsModule = Import("Settings")

	local Players = game:GetService("Players")
	local CoreGui = game:GetService("CoreGui")
	local LocalPlayer = Players.LocalPlayer
	local Environment = (getgenv and getgenv()) or _G

	local previousRuntime = rawget(Environment, "__ANIME_EXPEDITIONS_RUNTIME")
	if type(previousRuntime) == "table" and type(previousRuntime.Shutdown) == "function" then
		pcall(function()
			previousRuntime:Shutdown("re-executed")
		end)
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
		local restoreIdentity = Util.ElevateIdentity()
		if self.Window then
			Util.SafeCall("notification", self.Window.Notify, self.Window, {
				Title = tostring(title),
				Description = tostring(description),
				Lifetime = 5,
			})
		else
			Util.Warn(title .. ": " .. description)
		end
		restoreIdentity()
	end

	function Runtime:Shutdown(reason, windowAlreadyUnloaded)
		if self.ShuttingDown then
			return
		end
		local restoreIdentity = Util.ElevateIdentity()
		self.ShuttingDown = true
		if self.Registry then
			self.Registry.OnChanged = nil
		end
		self.Alive = false
		if reason == "manual unload" and self.Config and self.Config.Account then
			self.Config.Account.Session.AutoExecute = false
			self.Config.AccountDirty = true
			local accountOk, accountError = self.Config:SaveAccount(true)
			if not accountOk then
				Util.Warn("disable auto execute failed: " .. tostring(accountError))
			end
		end
		if self.Modules then
			self.Modules:DestroyAll()
		end
		if self.Results then
			self.Results:Destroy()
		end
		if self.Join then
			self.Join:Destroy()
		end
		if self.Session then
			self.Session:Destroy()
		end
		if self.UIManager then
			self.UIManager:Destroy()
		end
		if self.Config then
			local flushOk, flushError = self.Config:Flush(true)
			if not flushOk then
				Util.Warn("final config flush failed: " .. tostring(flushError))
			end
			self.Config:Destroy()
		end
		self.Janitor:Cleanup()
		if self.Window and not windowAlreadyUnloaded then
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
		restoreIdentity()
	end

	local function guiParent()
		if type(gethui) == "function" then
			local ok, value = pcall(gethui)
			if ok then
				return value
			end
		end
		return CoreGui
	end

	local function captureChildren(parent)
		local output = {}
		for _, child in ipairs(parent:GetChildren()) do
			output[child] = true
		end
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

	Window:GlobalSetting({
		Name = "UI Blur",
		Default = Config.Account.UI.UIBlur == true,
		Callback = function(enabled)
			Window:SetAcrylicBlurState(enabled == true)
			Config:UpdateAccount(function(account)
				account.UI.UIBlur = enabled == true
			end, false)
		end,
	})
	Window:GlobalSetting({
		Name = "Hide Private Info",
		Default = Config.Account.UI.HidePrivateInfo ~= false,
		Callback = function(hidden)
			Window:SetUserInfoState(hidden ~= true)
			Config:UpdateAccount(function(account)
				account.UI.HidePrivateInfo = hidden == true
			end, false)
		end,
	})

	for _, child in ipairs(parent:GetChildren()) do
		if not beforeGui[child] and child:IsA("ScreenGui") then
			Runtime.MacGui = child
			child.Name = "AnimeExpeditions_MacLib"
			break
		end
	end
	ResponsiveUI:MountMobileLauncher(parent, Config)

	local TabGroup = Window:TabGroup()
	local Tabs = {
		Join = TabGroup:Tab({ Name = "Join", Image = "rbxassetid://10734950309" }),
		AutoPlay = TabGroup:Tab({ Name = "Auto Play", Image = "rbxassetid://10734950309" }),
		Game = TabGroup:Tab({ Name = "Game", Image = "rbxassetid://10734950309" }),
		Webhook = TabGroup:Tab({ Name = "Webhook", Image = "rbxassetid://10734950020" }),
		Misc = TabGroup:Tab({ Name = "Misc", Image = "rbxassetid://10734950309" }),
		Priority = TabGroup:Tab({ Name = "Priority", Image = "rbxassetid://10734950020" }),
		Settings = TabGroup:Tab({ Name = "Settings", Image = "rbxassetid://10734950020" }),
	}

	local MiscPages = Tabs.Misc:SubTabGroup()
	Tabs.MiscClaims = MiscPages:SubTab({ Name = "Claims", Columns = 2 })
	Tabs.MiscUnits = MiscPages:SubTab({ Name = "Units", Columns = 2 })
	Tabs.MiscBounty = MiscPages:SubTab({ Name = "Bounty", Columns = 2 })
	Tabs.MiscPerformance = MiscPages:SubTab({ Name = "Performance", Columns = 2 })
	local AutoPlayPages = Tabs.AutoPlay:SubTabGroup()
	Tabs.AutoPlayNormal = AutoPlayPages:SubTab({ Name = "Normal", Columns = 2 })
	Tabs.AutoPlaySmart = AutoPlayPages:SubTab({ Name = "Smart", Columns = 2 })

	local Adapter = GameAdapter.new()
	local Join = JoinCoordinator.new(Runtime, Adapter)
	Runtime.Join = Join
	local Results = ResultsHub.new(Adapter)
	Runtime.Results = Results
	local Reporter = WebhookReporter.new(LocalPlayer, Adapter)
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
		Game = Adapter,
		Join = Join,
		Results = Results,
		Webhook = Reporter,
	}
	local Session = SessionManager.new(Runtime, Config)
	Context.Session = Session
	Runtime.Session = Session

	local Modules = ModuleManager.new(Context)
	Runtime.Modules = Modules
	Modules:Register(JoinStoryModule)
	Modules:Register(JoinChallengeModule)
	Modules:Register(JoinEventModule)
	Modules:Register(JoinRaidModule)
	Modules:Register(AutoPlayModule)
	Modules:Register(GameMatchModule)
	Modules:Register(GameEndModule)
	Modules:Register(WebhookModule)
	Modules:Register(MiscModule)
	Modules:Register(AutoClaimModule)
	Modules:Register(AutoSummonModule)
	Modules:Register(PerformanceModule)
	Modules:Register(AutoTraitRerollModule)
	Modules:Register(BountyModule)
	Modules:Register(JoinPriorityModule)
	Modules:Register(SettingsModule)

	local modulesOk, modulesError = Modules:LoadAll()
	if not modulesOk then
		Runtime:Shutdown("module load failure")
		error(modulesError)
	end

	local profileReady = true
	if Config.Account.AutoLoadSelected then
		local ok, err = Config:Load(Config.Account.SelectedConfig)
		if not ok then
			profileReady = false
			Config.LastLoadError = tostring(err)
			Runtime:Notify("Config load failed", tostring(err))
			Registry:Apply({})
		end
	else
		Registry:Apply({})
	end
	if profileReady then Config:ActivateProfile() end
	Registry.OnChanged = function()
		Config:ScheduleAutoSave()
	end

	if Config.Account.UI.HiddenOnExecute == true then
		Window:SetState(false)
	end
	Window.onUnloaded(function()
		Runtime:Shutdown("window unloaded", true)
	end)
	Tabs.Join:Select()
	if profileReady then
		Runtime:Notify("Loaded", string.format("Account %s | Config %s", LocalPlayer.Name, Config.Account.SelectedConfig))
	end

	return Runtime
end
