local Planner = rbxmk.loadFile("src/Core/AutoPlayPlanner.lua")()()
local SmartFactory = rbxmk.loadFile("src/Core/SmartAutoPlayPlanner.lua")()
local Smart = SmartFactory(function(name)
	assert(name == "AutoPlayPlanner", "unexpected smart planner dependency")
	return Planner
end)

local path = {
	Vector3.new(0, 0, 0),
	Vector3.new(0, 0, 40),
	Vector3.new(20, 0, 60),
	Vector3.new(20, 0, 100),
}
local enemy = {
	Health = 10000,
	MaxHealth = 10000,
	WaypointIndex = 3,
	PathProgress = 0.8,
	Speed = 2,
	DefaultSpeed = 1,
	Shield = 5,
	Type = "Boss 5",
	Modifiers = { "Sprinter", "Shielded" },
}
local easy = Smart.Context({
	Wave = 10,
	MaxWave = 15,
	BaseHealth = 3,
	BaseMaxHealth = 3,
	Parameters = { Gamemode = "Story", MapName = "Kingdom", ActName = "Act 1", Difficulty = "Easy" },
}, { enemy }, path)
local hard = Smart.Context({
	Wave = 10,
	MaxWave = 15,
	BaseHealth = 3,
	BaseMaxHealth = 3,
	Parameters = { Gamemode = "Story", MapName = "Kingdom", ActName = "Act 5", Difficulty = "Hard" },
}, { enemy }, path)
assert(hard.Pressure > easy.Pressure, "difficulty and act do not increase smart risk")
assert(hard.Emergency and hard.Boss, "live boss pressure was not recognized")
assert(string.find(hard.Scenario, "Act 5", 1, true), "scenario identity is incomplete")
local nested = Smart.Context({
	Data = {
		QueueData = {
			GameMode = "Raid",
			Map = { Name = "Spirit City" },
			Stage = { DisplayName = "Act 3" },
			DifficultyName = "Hard",
		},
	},
	CurrentWave = 6,
	TotalWaves = 15,
}, {}, path)
assert(nested.Mode == "Raid" and nested.Map == "Spirit City", "nested scenario data was not normalized")
assert(nested.Act == "Act 3" and nested.Difficulty == "Hard", "nested act and difficulty were not normalized")
assert(nested.Wave == 6 and nested.MaxWave == 15, "alternate wave fields were not normalized")
local liveRoute = Smart.Context({
	Wave = 4,
	MaxWave = 15,
	BaseHealth = 3,
	BaseMaxHealth = 3,
}, {}, path, { 0.21, 0.84 })
assert(liveRoute.BacklineEnemies == 1 and liveRoute.MaxProgress == 0.84, "rendered enemy route progress was ignored")
local calibratingRoute = Smart.Context({
	Wave = 1,
	MaxWave = 15,
	BaseHealth = 3,
	BaseMaxHealth = 3,
}, { enemy }, path, { 0.96 }, false)
assert(
	calibratingRoute.BacklineEnemies == 0 and calibratingRoute.MaxProgress == 0,
	"unoriented path data created a false backline emergency"
)
local earlyCrowd = {}
for index = 1, 100 do
	earlyCrowd[index] = {
		Health = 1000,
		MaxHealth = 1000,
		Progress = 0.1,
		Speed = 1,
		DefaultSpeed = 1,
	}
end
local measuredCrowd = Smart.Context({
	Wave = 4,
	MaxWave = 15,
	BaseHealth = 3,
	BaseMaxHealth = 3,
	Parameters = { Difficulty = "Hard", ActName = "Act 3" },
}, earlyCrowd, path)
assert(not measuredCrowd.Emergency, "healthy enemies near spawn created a permanent false emergency")

local modifierInformation = {
	GameModifiers = {
		List = {
			Speedy = { DisplayName = "Speedy", DefaultValue = 50 },
		},
	},
	EnemyModifiers = {
		List = {
			Splitter = {
				DisplayName = "Splitter",
				SummonHealthPercent = 33,
				SummonEnemies = { { Amount = 3 } },
			},
			Stunner = { DisplayName = "Stunner", Interval = 15, StunDuration = 5, StunCount = 3 },
		},
	},
}
local modifierAware = Smart.Context(
	{
		Wave = 3,
		MaxWave = 15,
		BaseHealth = 3,
		BaseMaxHealth = 3,
		Parameters = { Difficulty = "Hard" },
	},
	{ { Health = 100, MaxHealth = 100, Progress = 0.2, Modifiers = { "Splitter", "Stunner" } } },
	path,
	nil,
	true,
	{ GameModifiers = { Speedy = 15 } },
	modifierInformation
)
assert(math.abs(modifierAware.ModifierSpeed - 1.15) < 0.001, "live Speedy percentage was not applied")
assert(modifierAware.ModifierSpawn > 1.9, "Splitter child pressure was not modeled")
assert(modifierAware.ModifierStunRisk > 0 and modifierAware.ModifierRedundancy >= 2, "Stunner redundancy was ignored")
assert(
	string.find(modifierAware.ModifierSummary, "Splitter", 1, true)
		and string.find(modifierAware.ModifierSummary, "Speedy", 1, true),
	"active modifiers are not exposed to the live planner"
)

local information = {
	Units = {
		Farm = {
			DisplayName = "Farm",
			PlacementLimit = 3,
			UpgradeInfo = {
				[0] = { Cost = 100, Farm = 100, HitboxType = "Farm" },
				[1] = { Cost = 200, Farm = 250, HitboxType = "Farm" },
			},
		},
		Damage = {
			DisplayName = "Damage",
			PlacementLimit = 4,
			UpgradeInfo = {
				[0] = { Cost = 100, Damage = 500, SPA = 1, Range = 25, HitboxType = "Circle", HitboxSize = 12 },
				[1] = { Cost = 200, Damage = 1100, SPA = 1, Range = 28, HitboxType = "Circle", HitboxSize = 14 },
			},
		},
	},
}
local slots = Planner.Slots(
	{ Slots = { ["1"] = { ID = "farm" }, ["2"] = { ID = "damage" } } },
	{ UnitData = { farm = { Asset = "Farm" }, damage = { Asset = "Damage" } } },
	information,
	6
)
local snapshot = {
	GameState = {
		Wave = 10,
		MaxWave = 15,
		BaseHealth = 3,
		BaseMaxHealth = 3,
		Parameters = { Gamemode = "Story", MapName = "Kingdom", ActName = "Act 5", Difficulty = "Hard" },
	},
	Enemies = { enemy },
	Slots = slots,
	Placed = { [1] = {}, [2] = {} },
	Yen = 1000,
	Path = path,
	Paths = { path },
}
local unresolved = Smart.Decide({
	GameState = snapshot.GameState,
	Enemies = {},
	Slots = slots,
	Placed = { [1] = {}, [2] = {} },
	Yen = 1000,
	Paths = {},
}, { Strategy = "Win" })
assert(
	unresolved.Kind == "Wait" and string.find(unresolved.Reason, "active act route", 1, true),
	"Smart planner guessed when a multi-act route was unresolved"
)
local win = Smart.Decide(snapshot, {
	Strategy = "Win",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
})
assert(win.Kind == "Place" and win.Slot.Index == 2, "Win strategy seeded a farm during a late boss emergency")
local skipBlockedFarm = Smart.Decide(snapshot, {
	Strategy = "Win",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
	BlockedSlots = { [1] = true },
})
assert(
	skipBlockedFarm.Kind == "Place" and skipBlockedFarm.Slot.Index == 2,
	"a temporarily obstructed slot stalled every other placement"
)
assert(win.Path == path and win.Percent >= 1 and win.Percent <= 99, "adaptive placement did not return a map position")
assert(win.Context.ReservePercent == 0, "automatic reserve did not release yen during an emergency")

snapshot.Placed = {
	[1] = {
		{
			GameUnitID = "farm-placed",
			Upgrade = 0,
			MaxUpgrade = 1,
			NextCost = 200,
			Farm = true,
			Data = {},
		},
	},
	[2] = {},
}
snapshot.PlacementCounts = { Farm = 1 }
local deployBeforeFarmUpgrade = Smart.Decide(snapshot, {
	Strategy = "Win",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
})
assert(
	deployBeforeFarmUpgrade.Kind == "Place" and deployBeforeFarmUpgrade.Slot.Index == 2,
	"Win strategy upgraded a farm before deploying every combat slot"
)
information.Units.Damage.UpgradeInfo[0].Cost = 500
snapshot.Yen = 250
local saveForDeployment = Smart.Decide(snapshot, {
	Strategy = "Win",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
})
assert(
	saveForDeployment.Kind == "Wait"
		and saveForDeployment.Preview
		and saveForDeployment.Preview.Slot.Index == 2,
	"Win strategy spent deployment savings on an affordable farm upgrade"
)
information.Units.Damage.UpgradeInfo[0].Cost = 100
snapshot.Placed = { [1] = {}, [2] = {} }
snapshot.PlacementCounts = nil
snapshot.Yen = 1000

snapshot.GameState = {
	Wave = 1,
	MaxWave = 20,
	BaseHealth = 3,
	BaseMaxHealth = 3,
	Parameters = { Gamemode = "Story", MapName = "Kingdom", ActName = "Act 1", Difficulty = "Easy" },
}
snapshot.Enemies = {}
local economy = Smart.Decide(snapshot, {
	Strategy = "Economy",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
})
assert(economy.Kind == "Place" and economy.Slot.Index == 1, "Economy strategy did not take a profitable early farm")
snapshot.Enemies = { enemy }
snapshot.LiveProgress = { 0.96 }
snapshot.RouteConfident = false
local safeOpening = Smart.Decide(snapshot, {
	Strategy = "Win",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
})
assert(
	safeOpening.Kind == "Place" and safeOpening.Slot.Index == 1,
	"route calibration abandoned the profitable farm opening"
)
snapshot.Enemies = {}
snapshot.LiveProgress = nil
snapshot.RouteConfident = nil
slots[2].BoundingSize = 12
local noEconomy = Smart.Decide(snapshot, {
	Strategy = "Economy",
	AdaptivePlacement = true,
	SmartEconomy = false,
	ReactToEnemies = true,
})
assert(noEconomy.Kind == "Place" and noEconomy.Slot.Index == 2, "disabling smart economy did not exclude farm actions")
assert(noEconomy.Spacing == 11, "unit model footprint did not determine automatic placement spacing")

snapshot.Yen = 100
local reserved = Smart.Decide(snapshot, {
	Strategy = "Balanced",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
})
assert(reserved.Kind == "Wait", "automatic yen reserve was not applied in a safe wave")
assert(reserved.Context.ReservePercent > 0, "automatic yen reserve was not exposed")
assert(tonumber(reserved.Context.Spacing), "automatic placement spacing was not exposed")
assert(reserved.Preview and reserved.Preview.Kind == "Place", "waiting did not retain a placement preview")
assert(reserved.Context.Yen == 100 and reserved.Context.NextCost > 0, "planner affordability diagnostics are missing")
snapshot.Yen = 1220
local affordable = Smart.Decide(snapshot, {
	Strategy = "Balanced",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
})
assert(affordable.Kind == "Place", "an affordable placement remained stuck waiting")

snapshot.GameState = {
	Wave = 3,
	MaxWave = 15,
	BaseHealth = 3,
	BaseMaxHealth = 3,
	Parameters = { Gamemode = "Trial", Difficulty = "Normal" },
}
snapshot.Placed = {
	[1] = {
		{ GameUnitID = "farm-one", Upgrade = 0, MaxUpgrade = 1, NextCost = 200, Farm = true, CFrame = CFrame.new(12, 0, 50), Data = {} },
	},
	[2] = {
		{ GameUnitID = "damage-one", Upgrade = 0, MaxUpgrade = 1, NextCost = 200, CFrame = CFrame.new(6, 0, 30), Data = {} },
		{ GameUnitID = "damage-two", Upgrade = 0, MaxUpgrade = 1, NextCost = 200, CFrame = CFrame.new(14, 0, 70), Data = {} },
	},
}
snapshot.PlacementCounts = { Farm = 1, Damage = 2 }
snapshot.Yen = 1000
slots[1].PlacementLimit = 3
local expandProfitableFarm = Smart.Decide(snapshot, {
	Strategy = "Win",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
})
assert(
	expandProfitableFarm.Kind == "Place"
		and expandProfitableFarm.Slot.Index == 1
		and expandProfitableFarm.Cap >= 2,
	"smart economy treated one profitable farm as complete despite a larger intrinsic cap"
)

snapshot.Placed = { [1] = {}, [2] = {} }
snapshot.PlacementCounts = nil
snapshot.Yen = 1000
snapshot.PlacementCap = 0
local capped = Smart.Decide(snapshot, {
	Strategy = "Win",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
})
assert(capped.Kind == "Wait", "global placement cap was ignored")
snapshot.PlacementCap = nil
snapshot.Yen = 10000
snapshot.PlacementCounts = { Farm = 1 }
slots[1].PlacementLimit = 1
local authoritativeCap = Smart.Decide(snapshot, {
	Strategy = "Economy",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
})
assert(
	authoritativeCap.Kind == "Place" and authoritativeCap.Slot.Index == 2,
	"Smart Auto Play retried an asset whose authoritative placement count reached its cap"
)

local valueInformation = {
	Units = {
		Core = {
			PlacementLimit = 1,
			UpgradeInfo = {
				[0] = { Cost = 100, Damage = 500, SPA = 1, Range = 25, HitboxType = "Circle", HitboxSize = 12 },
				[1] = { Cost = 700, Damage = 2000, SPA = 1, Range = 32, HitboxType = "Circle", HitboxSize = 16 },
			},
		},
		Weak = {
			PlacementLimit = 3,
			UpgradeInfo = { [0] = { Cost = 50, Damage = 1, SPA = 2, Range = 8 } },
		},
	},
}
local valueSlots = Planner.Slots(
	{ Slots = { ["1"] = { ID = "core" }, ["2"] = { ID = "weak" } } },
	{ UnitData = { core = { Asset = "Core" }, weak = { Asset = "Weak" } } },
	valueInformation,
	6
)
local valueSnapshot = {
	GameState = {
		Wave = 5,
		MaxWave = 15,
		BaseHealth = 3,
		BaseMaxHealth = 3,
		Parameters = { Difficulty = "Normal" },
	},
	Enemies = {},
	LiveProgress = {},
	Slots = valueSlots,
	Placed = {
		[1] = { { GameUnitID = "core", Upgrade = 0, MaxUpgrade = 1, NextCost = 700, Data = {} } },
		[2] = {},
	},
	PlacementCounts = { Core = 1 },
	Yen = 100,
	Path = path,
	Paths = { path },
}
local saveForValue = Smart.Decide(valueSnapshot, {
	Strategy = "Win",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
})
assert(saveForValue.Kind == "Wait" and saveForValue.Cost == 700, "planner saved for the cheapest action instead of the best combat value")
valueSnapshot.Yen = 1000
local upgradeForValue = Smart.Decide(valueSnapshot, {
	Strategy = "Win",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
})
assert(upgradeForValue.Kind == "Upgrade" and upgradeForValue.Slot.Index == 1, "an unnecessary weak placement beat a valuable upgrade")

local bossInformation = {
	Units = {
		Core = {
			PlacementLimit = 1,
			UpgradeInfo = {
				[0] = { Cost = 100, Damage = 500, SPA = 1, Range = 25 },
				[1] = { Cost = 1000, Damage = 5500, SPA = 1, Range = 25 },
			},
		},
		Backup = {
			PlacementLimit = 1,
			UpgradeInfo = {
				[0] = { Cost = 100, Damage = 100, SPA = 1, Range = 25 },
				[1] = { Cost = 200, Damage = 300, SPA = 1, Range = 25 },
			},
		},
	},
}
local bossSlots = Planner.Slots(
	{ Slots = { ["1"] = { ID = "core" }, ["2"] = { ID = "backup" } } },
	{ UnitData = { core = { Asset = "Core" }, backup = { Asset = "Backup" } } },
	bossInformation,
	6
)
local bossFallback = Smart.Decide({
	GameState = {
		Wave = 15,
		MaxWave = 15,
		BaseHealth = 3,
		BaseMaxHealth = 3,
		Parameters = { Gamemode = "Trial", Difficulty = "Hard" },
	},
	Enemies = { { Boss = true, Health = 100000, MaxHealth = 100000, Progress = 0.3 } },
	Slots = bossSlots,
	Placed = {
		[1] = { { GameUnitID = "core", Upgrade = 0, MaxUpgrade = 1, NextCost = 1000, CFrame = CFrame.new(5, 0, 30), Data = {} } },
		[2] = { { GameUnitID = "backup", Upgrade = 0, MaxUpgrade = 1, NextCost = 200, CFrame = CFrame.new(10, 0, 40), Data = {} } },
	},
	PlacementCounts = { Core = 1, Backup = 1 },
	PlacementCap = 2,
	Yen = 300,
	Path = path,
	Paths = { path },
}, {
	Strategy = "Win",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
})
assert(
	bossFallback.Kind == "Upgrade" and bossFallback.Slot.Index == 2,
	"final-boss planning hoarded yen instead of buying an affordable combat upgrade"
)

local source = fs.read("src/Modules/AutoPlay.lua", "bin")
assert(string.find(source, "if state.SmartEnabled then", 1, true), "Smart mode does not override Normal mode")
assert(
	string.find(source, "state.SmartEnabled and 0.1 or 0.25", 1, true),
	"Smart planner does not use the fast decision cycle"
)
assert(
	string.find(source, "pendingComplete(state, current)", 1, true),
	"Smart actions are not serialized by confirmation"
)
local plannerSource = fs.read("src/Core/SmartAutoPlayPlanner.lua", "bin")
assert(string.find(plannerSource, "tacticalTarget", 1, true), "combat placements are not distributed tactically")
assert(
	string.find(plannerSource, "combatPlaced < requiredCombat", 1, true),
	"Smart mode does not establish a defensive baseline before value planning"
)
assert(string.find(plannerSource, "BacklineEnemies", 1, true), "Smart mode does not react to actual enemy route progress")
assert(string.find(plannerSource, "paybackWaves", 1, true), "farm upgrades ignore their remaining-wave payback")
assert(string.find(plannerSource, "fastFarmWindow", 1, true), "fast-payback farms cannot expand during the early economy window")
assert(string.find(source, "RouteVote", 1, true), "active route direction is not learned from live enemy movement")
assert(string.find(source, "RouteConfident", 1, true), "unoriented routes can still trigger false leak pressure")
assert(string.find(source, "enrichSlotStats", 1, true), "profile-adjusted unit stats are not loaded")
assert(string.find(plannerSource, "defenseCoverage", 1, true), "placed-unit route coverage is not re-evaluated")
assert(string.find(plannerSource, "MarginalCoverage", 1, true), "new placements ignore already covered path sections")

print("Smart Auto Play tests passed")
