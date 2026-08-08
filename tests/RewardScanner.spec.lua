workspace = workspace or {GetServerTimeNow = function() return 1000 end}

local Scanner = rbxmk.loadFile("src/Core/RewardScanner.lua")()()
local playerData = {
	Level = 12,
	QuestData = {
		Daily = {Quests = {A = {Completed = true, Claimed = false}, B = {Completed = false, Claimed = false}}},
		ForgeFever = {Quests = {EventQuest = {Completed = true, Claimed = false}}},
		Achievement_Kills = {Completed = true, Claimed = false, Quests = {C = {Completed = true, Claimed = false}}},
	},
	CalendarData = {DailyRewards = {Rewards = {["1"] = true, ["2"] = false, ["3"] = nil}}},
	BattlepassData = {Season1 = {Level = 2, Premium = false, Claimed = {Free = {["1"] = true}, Premium = {}}}},
	LevelMilestones = {Claimed = {Level5 = true}},
	Index = {Unit = {Foo = {Claimed = true}, Bar = {Claimed = false}}},
	ExpeditionData = {Buildings = {
		Armory = {Rewards = {{Asset = "Gold"}}},
		QuestBoard = {Milestone = 2, ClaimedMilestones = {Milestone1 = true}},
	}},
	EventData = {VillainHunt = {TotalClears = 20, ClaimedMilestones = {["10"] = true}}},
	TournamentData = {ActiveBrackets = {Release = {["3"] = {HighestScore = 10, RewardClaimed = false}}}},
}

local quests = Scanner.Quests(playerData, false)
assert(#quests == 2, "regular quest scan is wrong")
local eventQuests = Scanner.QuestCategories(playerData, {ForgeFever = true})
assert(#eventQuests == 1 and eventQuests[1].Quest == "EventQuest", "specific quest category scan is wrong")
local achievements, achievementCategories = Scanner.Quests(playerData, true)
assert(#achievements == 1 and #achievementCategories == 1, "achievement scan is wrong")
local calendars = Scanner.Calendars(playerData)
assert(#calendars == 1 and calendars[1].Day == 2, "calendar must only select false/unclaimed days")
local battlepasses = Scanner.Battlepasses(playerData)
assert(#battlepasses == 1 and battlepasses[1] == "Season1", "battlepass scan is wrong")
local levels = Scanner.LevelMilestones(playerData, {MilestoneEvery = 5, MaxMilestoneCount = 20})
assert(#levels == 1 and levels[1] == 10, "level milestone scan is wrong")
assert(Scanner.HasIndexRewards(playerData), "index reward was not detected")
local buildings, expeditionMilestones = Scanner.Expeditions(playerData)
assert(#buildings == 1 and buildings[1] == "Armory" and expeditionMilestones, "expedition scan is wrong")
assert(Scanner.VillainHunt(playerData, {VillainHunt = {Milestones = {[10] = {}, [20] = {}}}}), "event milestone was not detected")
local tournaments = Scanner.Tournaments(playerData, {Release = {Season = 3}})
assert(#tournaments == 1 and tournaments[1].Season == 3, "tournament scan is wrong")

print("RewardScanner tests passed")
