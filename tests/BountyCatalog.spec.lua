local factories = {
	AutomationCatalog = rbxmk.loadFile("src/Core/AutomationCatalog.lua")(),
	JoinCatalog = rbxmk.loadFile("src/Core/JoinCatalog.lua")(),
	BountyCatalog = rbxmk.loadFile("src/Core/BountyCatalog.lua")(),
}
local cache = {}
local function Import(name)
	if not cache[name] then cache[name] = factories[name](Import) end
	return cache[name]
end
local Catalog = Import("BountyCatalog")

local maps = {
	MapData = {
		Infinite = {FlowerForest = {Difficulties = {"Hard"}}},
		Story = {FairyKingForest = {ActProgression = {"Act 1"}, Difficulties = {"Hard"}}},
		Raid = {SpiritCity = {ActProgression = {"Act 1"}, Difficulties = {"Hard"}}},
	},
	PreviewInfo = {
		FlowerForest = {DisplayName = "Flower Forest"},
		FairyKingForest = {DisplayName = "Fairy King Forest"},
		SpiritCity = {DisplayName = "Spirit City"},
	},
	GamemodeTypes = {
		Infinite = {},
		Story = {},
		Raid = {},
	},
}
function maps:GetMapData(mode, map) return self.MapData[mode] and self.MapData[mode][map] end
function maps:GetOrderedMaps(mode)
	local output = {}
	for key in pairs(self.MapData[mode] or {}) do table.insert(output, key) end
	return output
end

local information = {
	Maps = maps,
	Quests = {Quests = {BountyBoard = {
		BountyA = {
			DisplayName = "Mythic Stack",
			Rarity = "Mythic",
			Objectives = {
				Waves = {Type = "ClearWave", Goal = 60, Conditions = {
					{ValueName = "Gamemode", Value = "Infinite"},
					{ValueName = "MapName", Value = "FlowerForest"},
					{ValueName = "Difficulty", Value = "Hard"},
				}},
				Challenge = {Type = "FinishMap", Goal = 2, Conditions = {
					{ValueName = "Gamemode", Value = "Challenge"},
				}},
			},
		},
		BountyB = {
			Rarity = "Legendary",
			Objectives = {
				Waves = {Type = "ClearWave", Goal = 40, Gamemode = "Infinite", MapName = "FlowerForest", Difficulty = "Hard"},
			},
		},
		BountyC = {
			Rarity = "Legendary",
			Objectives = {
				Summon = {Type = "Summon", Goal = 50},
				Story = {Type = "FinishMap", Goal = 1, Gamemode = "Story", MapName = "FairyKingForest", ActName = "Act 1", Difficulty = "Hard"},
			},
		},
	}}},
	ChallengeInfo = {Info = {}},
}
local questData = {BountyBoard = {
	ClaimedAmount = 3,
	QuestOrder = {"BountyA", "BountyB", "BountyC"},
	Quests = {
		BountyA = {Completed = false, Claimed = false, ObjectiveProgress = {Waves = 12, Challenge = 2}},
		BountyB = {Completed = false, Claimed = false, ObjectiveProgress = {Waves = 0}},
		BountyC = {Completed = false, Claimed = false, ObjectiveProgress = {Summon = 10, Story = 0}},
	},
}}
local entries = Catalog.Entries(information, questData)
assert(#entries == 3 and entries[1].Key == "BountyA", "board order was not preserved")
assert(entries[1].Objectives[1].Completed == true or entries[1].Objectives[2].Completed == true, "objective progress was not read")

local rarities, types = Catalog.Options(entries)
assert(rarities[1] == "Mythic", "bounty rarities are not ordered rarest first")
assert(table.find(types, "Infinite Waves") and table.find(types, "Challenge Clears") and table.find(types, "Summons"), "bounty types were not discovered")

local keep, reason = Catalog.Keep(entries[3], {"Legendary"}, {"Story Clears"}, {"Summons"})
assert(keep == false and string.find(reason, "avoided", 1, true), "avoid types do not override keep filters")
assert(Catalog.Keep(entries[1], {"Mythic", "Legendary"}, {"Infinite Waves"}, {}) == true, "multi rarity/type filters rejected a valid bounty")

local stack = Catalog.StackTarget(entries)
assert(stack and stack.Count == 2 and stack.Target.MapName == "FlowerForest", "stack target did not group board quests by map")
local queue = Catalog.QueueForObjective(information, {}, {}, entries[1].Objectives[2])
if queue == nil or queue.Gamemode ~= "Infinite" then queue = Catalog.QueueForObjective(information, {}, {}, entries[1].Objectives[1]) end
assert(queue and queue.Gamemode == "Infinite" and queue.MapName == "FlowerForest", "infinite bounty queue was not built")

local thisMap, board = Catalog.BoardText(information, questData, {Parameters = {Gamemode = "Infinite", MapName = "FlowerForest", Difficulty = "Hard"}})
assert(string.find(thisMap, "Flower Forest", 1, true), "friendly map name is missing")
assert(string.find(board, "Claims used today: 3/10", 1, true), "daily claim progress is missing")
assert(string.find(board, "Stacked on Infinite / Flower Forest - 2 bounty(s)", 1, true), "stack summary is missing")
assert(string.find(board, "[x] Challenge - 2/2", 1, true), "completed objective marker is missing")
local nestedQueue = Catalog.CurrentQueue({Session = {QueueData = {Gamemode = "Infinite", MapName = "FlowerForest", Difficulty = "Hard"}}})
assert(nestedQueue and nestedQueue.MapName == "FlowerForest", "nested live queue data was not detected")

print("Bounty catalog tests passed")
