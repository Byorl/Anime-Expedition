local factories = {
	AutomationCatalog = rbxmk.loadFile("src/Core/AutomationCatalog.lua")(),
	JoinCatalog = rbxmk.loadFile("src/Core/JoinCatalog.lua")(),
}
local cache = {}
local function Import(name)
	if cache[name] then return cache[name] end
	cache[name] = factories[name](Import)
	return cache[name]
end

local catalog = Import("JoinCatalog")
local mapData = {
	Story = {
		KingsTomb = {ProgressionIndex = 1, ActProgression = {"Act 1", "Act 2"}, Difficulties = {"Easy", "Hard"}},
	},
	Infinite = {KingsTomb = {Difficulties = {"Hard"}}},
	Mastery = {KingsTomb = {ActProgression = {"Act 1"}, Difficulties = {"Nightmare"}}},
	Raid = {SpiritCity = {ProgressionIndex = 1, ActProgression = {"Act 1", "Act 2"}, Difficulties = {"Easy", "Hard", "Nightmare"}}},
	VillainInvasion = {VillainInvasion = {ActProgression = {"Act 1", "Act 2", "Act 3", "Crow"}, Difficulties = {"Hard"}, OrderedFactions = {"Death", "Tartaros", "Sword", "Dawn"}}},
}
local maps = {MapData = mapData, PreviewInfo = {KingsTomb = {DisplayName = "King's Tomb"}}}
function maps:GetOrderedMaps(mode)
	local output = {}
	for key in pairs(self.MapData[mode] or {}) do table.insert(output, key) end
	return output
end
function maps:GetMapData(mode, map) return self.MapData[mode] and self.MapData[mode][map] end
function maps:HasMapUnlocked() return true end
function maps:HasActUnlocked() return true end

local information = {
	Maps = maps,
	ChallengeInfo = {
		Info = {Regular = {Amount = 3, RefreshTime = 1800}, Daily = {Amount = 1, RefreshTime = 86400}, Weekly = {Amount = 1, RefreshTime = 604800}},
		IsChallengeAvailable = function(_, clearHistory, dailyHistory, challengeType, index) return clearHistory[index] == nil end,
	},
	StageDrops = {
		GetDrops = function(_, queue)
			if queue.ChallengeType == "Regular" and tonumber(queue.ChallengeIndex) == 1 then return {{Asset = "Gem"}, {Asset = "Ban"}} end
			return {{Asset = "Gold"}}
		end,
	},
	Items = {Gem = {DisplayName = "Gems"}, Gold = {DisplayName = "Gold"}},
	Units = {Ban = {DisplayName = "Ban"}},
}

local mapOptions = catalog.MapOptions(information, "Story")
assert(mapOptions.ByKey.KingsTomb == "King's Tomb [KingsTomb]", "story map labels did not preserve their live keys")
local stages = catalog.Stages(information, "KingsTomb")
assert(table.find(stages, "Act 2") and table.find(stages, "Infinite") and table.find(stages, "Mastery"), "story stages did not merge live acts and modes")
local storyQueue = catalog.StoryQueue(information, "KingsTomb", "Infinite", "Hard")
assert(storyQueue.Gamemode == "Infinite" and storyQueue.ActName == nil, "infinite stage produced invalid queue data")
assert(catalog.ChallengeAmount(information, "Regular") == 3, "challenge count was not read from live information")

local challengeData = {Regular = {{MapName = "KingsTomb", ActName = "Act 1", Difficulty = "Hard"}}}
local drops = catalog.ChallengeDrops(information, challengeData)
assert(drops.ByKey.Gem and drops.ByKey.Ban, "challenge reward catalog omitted live drops")
assert(catalog.ChallengeHasDrop(information, "Regular", 1, "Ban"), "challenge reward filter rejected a present drop")
assert(not catalog.ChallengeHasDrop(information, "Daily", 1, "Ban"), "challenge reward filter accepted an absent drop")
local playerData = {ChallengeData = {ClearHistory = {Regular = {}}, DailyClearHistory = {Regular = {}}}}
assert(catalog.ChallengeAvailable(information, playerData, "Regular", 1), "available challenge was rejected")

print("Join catalog tests passed")
