task = task or {}
task.wait = task.wait or function() end
task.spawn = task.spawn or function(callback) callback() end
task.defer = task.defer or function(callback) callback() end

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
local section = {Header = function() end}
function section:Label(settings) return {UpdateName = function() end, Settings = settings} end
function section:Button(settings) return {Settings = settings} end
local registry = {}
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
local performanceContext = {
	Tabs = {Misc = {Section = function() return section end}},
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
