task = task or {}
task.wait = task.wait or function() end
task.spawn = task.spawn or function(callback) callback() return nil end
local deferred = {}
task.defer = function(callback) table.insert(deferred, callback) return callback end

local factories = {
	Util = rbxmk.loadFile("src/Core/Util.lua")(),
	AutomationCatalog = rbxmk.loadFile("src/Core/AutomationCatalog.lua")(),
	JoinCatalog = rbxmk.loadFile("src/Core/JoinCatalog.lua")(),
	BountyCatalog = rbxmk.loadFile("src/Core/BountyCatalog.lua")(),
	Bounty = rbxmk.loadFile("src/Modules/Bounty.lua")(),
}
local cache = {}
local function Import(name)
	if not cache[name] then cache[name] = factories[name](Import) end
	return cache[name]
end

local maps = {
	MapData = {Infinite = {FlowerForest = {Difficulties = {"Hard"}}}},
	PreviewInfo = {FlowerForest = {DisplayName = "Flower Forest"}},
	GamemodeTypes = {Infinite = {}},
}
function maps:GetMapData(mode, map) return self.MapData[mode] and self.MapData[mode][map] end
local information = {
	Maps = maps,
	Quests = {Quests = {BountyBoard = {WaveBounty = {
		Rarity = "Mythic",
		Objectives = {Wave = {Type = "ClearWave", Goal = 60, Gamemode = "Infinite", MapName = "FlowerForest", Difficulty = "Hard"}},
	}}}},
	BannerInfo = {Styling = {Standard = {Name = "Standard"}}},
}
local questData = {BountyBoard = {ClaimedAmount = 2, QuestOrder = {"WaveBounty"}, Quests = {
	WaveBounty = {Completed = false, Claimed = false, ObjectiveProgress = {Wave = 5}},
}}}
local bannerData = {Standard = {BannerInfo = {Currency = "Gem", Cost = 50}}}

local controls, callbacks, providers, buttons = {}, {}, {}, {}
local function control(settings)
	return {
		Settings = settings,
		ClearOptions = function() end,
		InsertOptions = function() end,
		UpdateSelection = function() end,
		UpdateState = function() end,
		UpdateValue = function() end,
	}
end
local section = {}
function section:Header() end
function section:Divider() end
function section:Label(settings)
	return {Settings = settings, UpdateName = function(self, value) self.Value = value end}
end
function section:Button(settings)
	local created = control(settings)
	buttons[settings.Name] = created
	return created
end
local registry = {}
for _, kind in ipairs({"Dropdown", "Toggle", "Slider"}) do
	registry[kind] = function(_, _, settings, flag)
		controls[flag] = control(settings)
		callbacks[flag] = settings.Callback
		return controls[flag]
	end
end
function registry:Get() return false end
local context = {
	Tabs = {MiscBounty = {Section = function() return section end}},
	Registry = registry,
	Runtime = {Alive = false, Notify = function() end},
	Game = {
		Information = function() return information end,
		State = function(_, name) if name == "QuestData" then return {BountyBoard = {Quests = {}}} elseif name == "BannerData" then return bannerData elseif name == "ChallengeData" then return {} end end,
		GameData = function() return nil end,
		PlayerData = function() return {ItemData = {Gold = 10000, Gem = 10000}, QuestData = questData} end,
		IsInGame = function() return false end,
		IsMatchEnded = function() return false end,
	},
	Join = {Register = function(_, name, _, provider) providers[name] = provider return function() providers[name] = nil end end},
	Results = {Revision = 0, DeliveryState = function() return true end},
	RegisterCleanup = function() end,
}
local module = Import("Bounty")
local ok, state = pcall(module.Init, module, context)
assert(ok, "Bounty failed to initialize: " .. tostring(state))
assert(#state.Entries == 0, "Bounty performed live data reads before module initialization completed")
buttons["Refresh Banners"].Settings.Callback()
deferred[#deferred]()
assert(#state.Entries == 1 and state.Entries[1].Key == "WaveBounty", "Bounty did not prefer populated player quest data")
assert(string.find(state.BoardLabel.Value, "1 bounty(s)", 1, true), "Bounty board did not render populated player quest data")
for _, flag in ipairs({"bounty.keep_rarities", "bounty.keep_types", "bounty.avoid_types", "bounty.banners"}) do
	assert(controls[flag].Settings.Search == true and controls[flag].Settings.Multi == true, flag .. " is not a searchable multi-select")
end
assert(controls["bounty.stack_count"].Settings.Minimum == 2 and controls["bounty.stack_count"].Settings.Maximum == 5, "stack slider range is wrong")
assert(controls["bounty.delay"].Settings.Minimum == 1 and controls["bounty.delay"].Settings.Maximum == 10 and controls["bounty.delay"].Settings.Step == 1, "join delay is not whole seconds")
callbacks["bounty.auto_join"](true)
local candidate = providers.Bounty()
assert(candidate and candidate.Queue.Gamemode == "Infinite" and candidate.Queue.MapName == "FlowerForest", "Bounty join provider did not build the objective queue")
assert(candidate.Delay == 1 and candidate.Matchmaking == false, "Bounty join settings were not forwarded")

print("Bounty feature tests passed")
