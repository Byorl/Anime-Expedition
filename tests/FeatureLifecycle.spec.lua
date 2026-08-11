task = task or {}
task.wait = task.wait or function() end
task.spawn = task.spawn or function(callback) callback() end
task.defer = task.defer or function(callback) callback() end
task.delay = task.delay or function(_, callback) callback() end

local function signal()
	return {Connect = function(_, callback)
		return {Disconnect = function() end, Callback = callback}
	end}
end
local services = {
	HttpService = {JSONEncode = function() return "{}" end},
	CollectionService = {
		GetInstanceAddedSignal = function() return signal() end,
		GetTagged = function() return {} end,
	},
	Lighting = {GetDescendants = function() return {} end, DescendantAdded = signal()},
	RunService = {},
	Workspace = {
		GetDescendants = function() return {} end,
		FindFirstChildOfClass = function() return nil end,
		DescendantAdded = signal(),
	},
}
game = {GetService = function(_, name) return assert(services[name], "unknown service " .. tostring(name)) end}
workspace = services.Workspace

local cache = {}
local factories = {
	Util = rbxmk.loadFile("src/Core/Util.lua")(),
	RewardScanner = rbxmk.loadFile("src/Core/RewardScanner.lua")(),
	AutomationCatalog = rbxmk.loadFile("src/Core/AutomationCatalog.lua")(),
	AutoClaim = rbxmk.loadFile("src/Modules/AutoClaim.lua")(),
	AutoSummon = rbxmk.loadFile("src/Modules/AutoSummon.lua")(),
	Performance = rbxmk.loadFile("src/Modules/Performance.lua")(),
	Misc = rbxmk.loadFile("src/Modules/Misc.lua")(),
	AutoTraitReroll = rbxmk.loadFile("src/Modules/AutoTraitReroll.lua")(),
}
local function Import(name)
	if cache[name] then return cache[name] end
	cache[name] = factories[name](Import)
	return cache[name]
end

local autoClaim = Import("AutoClaim")
local cleanup
local autoState = {Generation = 0, Alive = false, LastErrors = {}}
local autoContext = {
	Game = {Ready = true},
	Runtime = {Alive = false},
	RegisterCleanup = function(_, callback) cleanup = callback end,
}
local autoOk, autoError = pcall(autoClaim.Enable, autoClaim, autoContext, autoState)
assert(autoOk, "AutoClaim Enable lifecycle binding failed: " .. tostring(autoError))
assert(autoState.Generation == 1 and type(cleanup) == "function", "AutoClaim scheduler did not initialize")
cleanup()

local callbacks, controls = {}, {}
local section = {Header = function() end, Paragraph = function() end}
function section:Toggle(settings) return {Settings = settings} end
function section:Label(settings) return {UpdateName = function() end, Settings = settings} end
function section:Button(settings) return {Settings = settings} end
local registry = {}
function registry:Get() return false end
function registry:Toggle(_, settings, flag)
	callbacks[flag] = settings.Callback
	local control = {UpdateState = function(_, value) settings.Callback(value) end}
	controls[flag] = control
	return control
end
function registry:Dropdown(_, settings, flag)
	callbacks[flag] = settings.Callback
	local control = {
		UpdateSelection = function(_, value) settings.Callback(value) end,
		ClearOptions = function() end,
		InsertOptions = function() end,
		Settings = settings,
	}
	controls[flag] = control
	return control
end
local claimContext = {
	Tabs = {MiscClaims = {Section = function() return section end}},
	Registry = registry,
	Config = {AccountFolder = "accounts/test"},
	FileSystem = {
		ReadJson = function(_, _, fallback) return fallback end,
		WriteJson = function() return true end,
	},
	Player = {UserId = 1, IsInGroup = function() return false end},
}
local claimState = autoClaim.Init(autoClaim, claimContext)
assert(controls["auto_claim.dragon_balls"], "Auto Claim Dragon Balls toggle was not registered")
callbacks["auto_claim.dragon_balls"](true)
assert(claimState.Values.DragonBalls == true, "Auto Claim Dragon Balls toggle did not update module state")
local performanceContext = {
	Tabs = {
		MiscClaims = {Section = function() return section end},
		MiscUnits = {Section = function() return section end},
		MiscBounty = {Section = function() return section end},
		MiscPerformance = {Section = function() return section end},
	},
	Registry = registry,
	Runtime = {Notify = function() end},
}
local performance = Import("Performance")
local performanceState = performance.Init(performance, performanceContext)
assert(performanceState.RenderingControl == controls["performance.disable_3d_rendering"], "rendering control was bound to the wrong toggle")
callbacks["performance.delete_enemies"](true)
callbacks["performance.delete_enemies"](false)
callbacks["performance.fps_boost"](true)
callbacks["performance.fps_boost"](false)
local disableOk, disableError = pcall(performance.Disable, performance, performanceContext, performanceState)
assert(disableOk, "Performance Disable lifecycle binding failed: " .. tostring(disableError))

local promptCallbacks, settingCalls, localPromptCloses, serverPromptCloses, disconnected = {}, {}, {}, {}, 0
local directRewardPrompts = 0
local promptActions = {
	PromptObtainedRewards = function()
		directRewardPrompts = directRewardPrompts + 1
	end,
}
local miscContext = {
	Tabs = performanceContext.Tabs,
	Registry = registry,
	Runtime = {Modules = {Loaded = {Misc = true}}, Notify = function() end},
	Config = {Account = {Session = {AutoExecute = false}, UI = {HiddenOnLoad = false}}},
	Session = {SetAutoExecute = function() end, SetAutoReconnect = function() end},
	Game = {
		Actions = promptActions,
		InvokeSelf = function(_, name, key)
			assert(name == "GET_SETTING_VALUE" and key == "FastSummon", "wrong Fast Summon setting lookup")
			return true, false
		end,
		ChangeSetting = function(_, name, value)
			table.insert(settingCalls, {name, value})
			return true
		end,
		Connect = function(_, name, callback)
			promptCallbacks[name] = callback
			return {Disconnect = function() disconnected = disconnected + 1 end}
		end,
		FireLocal = function(_, name, id)
			table.insert(localPromptCloses, {name, id})
			return true
		end,
		Fire = function(_, name, id)
			table.insert(serverPromptCloses, {name, id})
			return true
		end,
	},
}
local misc = Import("Misc")
local miscState = misc.Init(misc, miscContext)
misc.Enable(misc, miscContext, miscState)
promptActions.PromptObtainedRewards({}, true)
assert(directRewardPrompts == 0, "direct Obtained Rewards actions were not blocked before mounting")
callbacks["misc.fast_summon"](true)
promptCallbacks.PROMPT_OBTAINED_REWARDS({}, true, "SummonAnimation")
callbacks["misc.disable_reward_popups"](true)
promptCallbacks.PROMPT_OBTAINED_REWARD_SLOTS({}, true, "DailyReward")
assert(settingCalls[#settingCalls][2] == true, "Fast Summon did not enable the native game setting")
local closedSummon, closedDaily, acknowledgedDaily = false, false, false
for _, entry in ipairs(localPromptCloses) do
	if entry[1] == "PROMPT_CLOSE" and entry[2] == "SummonAnimation" then closedSummon = true end
	if entry[1] == "PROMPT_CLOSE" and entry[2] == "DailyReward" then closedDaily = true end
end
for _, entry in ipairs(serverPromptCloses) do
	if entry[1] == "PROMPT_CLOSED" and entry[2] == "DailyReward" then acknowledgedDaily = true end
end
assert(
	closedSummon and closedDaily,
	"summon or generic obtained reward prompts were not dismissed"
)
assert(
	acknowledgedDaily,
	"dismissed reward prompts were not acknowledged to the game"
)
misc.Disable(misc, miscContext, miscState)
assert(disconnected == 2 and settingCalls[#settingCalls][2] == false, "Misc unload did not restore prompt state")
promptActions.PromptObtainedRewards({}, true)
assert(directRewardPrompts == 1, "Misc unload did not restore the game's Obtained Rewards action")

local featureInformation = {
	BannerInfo = {Styling = {Standard = {Name = "Standard"}}},
	OrderedRarities = {"Rare", "Epic", "Legendary", "Mythic", "Exclusive", "Secret"},
	Units = {Ban = {DisplayName = "Ban", Rarity = "Legendary"}},
	Traits = {TraitData = {Unbound = {DisplayName = "Unbound", Chance = 0.1}}},
}
local featureData = {UnitData = {u1 = {Asset = "Ban", Level = 1}}, ItemData = {}}
local featureContext = {
	Tabs = performanceContext.Tabs,
	Registry = registry,
	Runtime = {Alive = false},
	Game = {
		State = function(_, name)
			if name == "BannerData" then return {Standard = {BannerInfo = {Cost = 50}}} end
		end,
		Information = function() return featureInformation end,
		PlayerData = function() return featureData end,
	},
}
local summonState = Import("AutoSummon").Init(Import("AutoSummon"), featureContext)
assert(summonState.SelectedBannerKey == "Standard", "Auto Summon did not bind its live banner catalog")
assert(controls["auto_summon.banner"].Settings.Search == true, "banner dropdown search is disabled")
local traitState = Import("AutoTraitReroll").Init(Import("AutoTraitReroll"), featureContext)
assert(traitState.SelectedUnitId == "u1", "Auto Reroll did not bind its live unit catalog")
assert(controls["auto_trait.unit"].Settings.Search == true, "unit dropdown search is disabled")
assert(controls["auto_trait.stop_traits"].Settings.Search == true, "trait dropdown search is disabled")

print("Feature lifecycle tests passed")
