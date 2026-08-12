local Telemetry = rbxmk.loadFile("src/Core/MatchTelemetry.lua")()()
local writes = {}
local fileSystem = {
	Root = "TestData",
	WriteJson = function(_, path, value)
		writes[path] = value
		return true
	end,
}
local recorder = Telemetry.new(fileSystem, { UserId = 42, Name = "Tester" }, { Version = "test" })
recorder:SetEnabled(true)
local snapshot = {
	GameState = {
		Wave = 3,
		MaxWave = 15,
		GameTime = 12.5,
		BaseHealth = 3,
		Parameters = { Gamemode = "Raid", MapName = "SpiritCity", ActName = "Act 3", Difficulty = "Hard" },
	},
	ModifierState = { GameModifiers = { Speedy = 15 } },
	Slots = { { Index = 1, Name = "Farm", Asset = "Farm", PlacementLimit = 3, MaxUpgrade = 6, Cost = 750 } },
	Placed = { [1] = { { GameUnitID = "farm-1", Name = "Farm", Upgrade = 1, CFrame = CFrame.new(10, 2, 20) } } },
	Yen = 1200,
	PlayerState = { Yen = 1200, PlacementCounts = { [1] = 1 } },
	PlayerCFrame = CFrame.new(3, 2, 1),
	Paths = { { Vector3.new(0, 0, 0), Vector3.new(0, 0, 100) } },
	Enemies = { first = { ID = "e1", Name = "Enemy", Health = 100, MaxHealth = 200, Progress = 0.4 } },
	RenderedEnemies = { { ID = "e1", Name = "Enemy", CFrame = CFrame.new(0, 1, 40) } },
	LiveProgress = { 0.4 },
	RouteConfident = true,
	RouteReverse = false,
	PlacementCounts = { [1] = 1 },
	PlacementCap = 20,
}
assert(recorder:Capture(snapshot, true), "telemetry did not begin recording")
recorder:Decision({ Kind = "Place", Reason = "Farm economy", Slot = snapshot.Slots[1], Cost = 750 }, CFrame.new(5, 0, 20))
recorder:Event("ActionAttempt", { Kind = "Place", Slot = 1 })
local ok, path = recorder:Finalize("Victory", { Victory = true, Rewards = { Gold = 100 } })
assert(ok and type(path) == "string", "telemetry did not finalize")
local output = writes[path]
assert(output and output.Schema == 1 and output.Outcome == "Victory", "telemetry output metadata is invalid")
assert(output.Scenario.Mode == "Raid" and output.Scenario.Act == "Act 3", "scenario was not recorded")
assert(#output.Route.Paths == 1 and #output.Route.Paths[1] == 2, "path geometry was not recorded")
assert(#output.Samples == 1 and output.Samples[1].Yen == 1200, "economy sample was not recorded")
assert(output.Samples[1].PlayerPosition[1] == 3, "player position was not recorded")
assert(output.Samples[1].RenderedEnemies[1].Position[3] == 40, "rendered enemy position was not recorded")
assert(output.Samples[1].Placed[1].Position[1] == 10, "unit placement position was not recorded")
assert(#output.Events >= 4, "planner and action events were not recorded")
assert(recorder.Active == nil, "finished telemetry remained active")
assert(string.find(recorder:Status(), "match_", 1, true), "saved telemetry filename is not exposed")
print("Match telemetry tests passed")
