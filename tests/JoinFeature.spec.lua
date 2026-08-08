task = task or {}
task.wait = task.wait or function() end
task.spawn = task.spawn or function(callback)
	callback()
	return nil
end

local factories = {
	AutomationCatalog = rbxmk.loadFile("src/Core/AutomationCatalog.lua")(),
	JoinCatalog = rbxmk.loadFile("src/Core/JoinCatalog.lua")(),
	JoinStory = rbxmk.loadFile("src/Modules/JoinStory.lua")(),
	JoinChallenge = rbxmk.loadFile("src/Modules/JoinChallenge.lua")(),
	JoinEvent = rbxmk.loadFile("src/Modules/JoinEvent.lua")(),
	JoinRaid = rbxmk.loadFile("src/Modules/JoinRaid.lua")(),
}
local cache = {}
local function Import(name)
	if cache[name] then
		return cache[name]
	end
	cache[name] = factories[name](Import)
	return cache[name]
end

local mapData = {
	Story = { KingsTomb = { ActProgression = { "Act 1", "Act 2" }, Difficulties = { "Easy", "Hard" } } },
	Infinite = { KingsTomb = { Difficulties = { "Hard" } } },
	Mastery = { KingsTomb = { ActProgression = { "Act 1" }, Difficulties = { "Hard" } } },
	Raid = { SpiritCity = { ActProgression = { "Act 1", "Act 2" }, Difficulties = { "Easy", "Hard", "Nightmare" } } },
	VillainInvasion = {
		VillainInvasion = {
			ActProgression = { "Act 1", "Act 2", "Act 3", "Crow" },
			Difficulties = { "Hard" },
			OrderedFactions = { "Death", "Tartaros", "Sword", "Dawn" },
		},
	},
}
local maps = { MapData = mapData, PreviewInfo = {}, GamemodeTypes = {} }
function maps:GetOrderedMaps(mode)
	local output = {}
	for key in pairs(self.MapData[mode] or {}) do
		table.insert(output, key)
	end
	return output
end
function maps:GetMapData(mode, map)
	return self.MapData[mode] and self.MapData[mode][map]
end
function maps:HasMapUnlocked()
	return true
end
function maps:HasActUnlocked()
	return true
end

local information = {
	Maps = maps,
	ChallengeInfo = {
		Info = {
			Regular = { Amount = 1, RefreshTime = 1800 },
			Daily = { Amount = 1, RefreshTime = 86400 },
			Weekly = { Amount = 1, RefreshTime = 604800 },
		},
		IsChallengeAvailable = function()
			return true
		end,
	},
	StageDrops = {
		GetDrops = function()
			return { { Asset = "Gem" } }
		end,
	},
	Items = { Gem = { DisplayName = "Gems" } },
}
local playerData =
	{ CompletedMaps = {}, ChallengeData = { ClearHistory = {}, DailyClearHistory = {} }, ItemData = { CrowRelic = 0 } }
local challengeData = {
	Regular = { { MapName = "KingsTomb", ActName = "Act 1", Difficulty = "Hard" } },
	Daily = { { MapName = "KingsTomb", ActName = "Act 1", Difficulty = "Hard" } },
	Weekly = { { MapName = "KingsTomb", ActName = "Act 1", Difficulty = "Hard" } },
}

local callbacks, controls, providers = {}, {}, {}
local section = {}
function section:Header() end
function section:Divider() end
function section:Label(settings)
	return { Settings = settings }
end
local function control(settings)
	return {
		Settings = settings,
		ClearCount = 0,
		ClearOptions = function(self)
			self.ClearCount = self.ClearCount + 1
		end,
		InsertOptions = function() end,
		UpdateSelection = function() end,
		UpdateState = function() end,
		UpdateValue = function() end,
	}
end
local registry = {}
function registry:Dropdown(_, settings, flag)
	callbacks[flag] = settings.Callback
	controls[flag] = control(settings)
	return controls[flag]
end
function registry:Toggle(_, settings, flag)
	callbacks[flag] = settings.Callback
	controls[flag] = control(settings)
	return controls[flag]
end
function registry:Slider(_, settings, flag)
	callbacks[flag] = settings.Callback
	controls[flag] = control(settings)
	return controls[flag]
end
local joinTab = {
	Section = function()
		return section
	end,
}
local context = {
	Tabs = { Join = joinTab },
	Registry = registry,
	Runtime = { Alive = false, Notify = function() end },
	Game = {
		Information = function()
			return information
		end,
		PlayerData = function()
			return playerData
		end,
		State = function(_, name)
			if name == "ChallengeData" then
				return challengeData
			end
		end,
		IsInGame = function()
			return false
		end,
	},
	Join = {
		Register = function(_, name, priority, provider)
			providers[name] = provider
			return function()
				providers[name] = nil
			end
		end,
	},
	RegisterCleanup = function() end,
}

for _, name in ipairs({ "JoinStory", "JoinChallenge", "JoinEvent", "JoinRaid" }) do
	local module = Import(name)
	local ok, state = pcall(module.Init, module, context)
	assert(ok, name .. " failed to initialize: " .. tostring(state))
end

for flag, current in pairs(controls) do
	if
		string.find(flag, "map")
		or string.find(flag, "act")
		or string.find(flag, "stage")
		or string.find(flag, "difficulty")
		or string.find(flag, "types")
		or string.find(flag, "drop")
	then
		assert(current.Settings.Search == true, flag .. " is not searchable")
	end
end
assert(controls["join.challenge.types"].Settings.Multi == true, "challenge types are not multi-select")
assert(controls["join.challenge.drop"].Settings.Multi == true, "challenge drops are not multi-select")
assert(controls["join.event.crow_relics"].Settings.Maximum == 200, "Crow relic limit is not 200")
for _, flag in ipairs({ "join.story.delay", "join.challenge.delay", "join.event.delay", "join.raid.delay" }) do
	assert(controls[flag].Settings.Minimum == 1, flag .. " minimum is not one second")
	assert(controls[flag].Settings.Maximum == 10, flag .. " maximum is not ten seconds")
	assert(
		controls[flag].Settings.Precision == 0 and controls[flag].Settings.Step == 1,
		flag .. " is not integer stepped"
	)
end
local typeRefreshes = controls["join.challenge.types"].ClearCount
callbacks["join.challenge.types"]({ Daily = true })
assert(controls["join.challenge.types"].ClearCount == typeRefreshes, "challenge selection rebuilt its dropdown")
callbacks["join.story.enabled"](true)
callbacks["join.challenge.enabled"](true)
callbacks["join.event.enabled"](true)
callbacks["join.raid.enabled"](true)
assert(providers.Story().Queue.Gamemode == "Story", "story provider produced invalid queue data")
assert(
	providers.Challenge().Queue.Gamemode == "Challenge" and providers.Challenge().Queue.ChallengeType == "Daily",
	"challenge multi-selection produced invalid queue data"
)
assert(providers.Event().Queue.Gamemode == "VillainInvasion", "event provider produced invalid queue data")
assert(providers.Raid().Queue.Gamemode == "Raid", "raid provider produced invalid queue data")

print("Join feature tests passed")
