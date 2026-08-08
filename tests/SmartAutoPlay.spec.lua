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
local win = Smart.Decide(snapshot, {
	Strategy = "Win",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
})
assert(win.Kind == "Place" and win.Slot.Index == 2, "Win strategy did not prioritize combat under pressure")
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

print("Smart Auto Play tests passed")
