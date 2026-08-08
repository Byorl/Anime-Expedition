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
	ReservePercent = 10,
	Spacing = 6,
})
assert(win.Kind == "Place" and win.Slot.Index == 2, "Win strategy did not prioritize combat under pressure")
assert(win.Path == path and win.Percent >= 1 and win.Percent <= 99, "adaptive placement did not return a map position")

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
	ReservePercent = 0,
	Spacing = 6,
})
assert(economy.Kind == "Place" and economy.Slot.Index == 1, "Economy strategy did not take a profitable early farm")
local noEconomy = Smart.Decide(snapshot, {
	Strategy = "Economy",
	AdaptivePlacement = true,
	SmartEconomy = false,
	ReactToEnemies = true,
	ReservePercent = 0,
	Spacing = 6,
})
assert(noEconomy.Kind == "Place" and noEconomy.Slot.Index == 2, "disabling smart economy did not exclude farm actions")

snapshot.Yen = 100
local reserved = Smart.Decide(snapshot, {
	Strategy = "Balanced",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
	ReservePercent = 50,
	Spacing = 6,
})
assert(reserved.Kind == "Wait", "emergency reserve was not respected in a safe wave")
snapshot.Yen = 1000
snapshot.PlacementCap = 0
local capped = Smart.Decide(snapshot, {
	Strategy = "Win",
	AdaptivePlacement = true,
	SmartEconomy = true,
	ReactToEnemies = true,
	ReservePercent = 0,
	Spacing = 6,
})
assert(capped.Kind == "Wait", "global placement cap was ignored")

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
