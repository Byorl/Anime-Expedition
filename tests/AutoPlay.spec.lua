task = task or {}
task.spawn = task.spawn or function()
	return {}
end
task.wait = task.wait or function() end

local localPlayer = { UserId = 42 }
local services = {
	Players = { LocalPlayer = localPlayer },
	ReplicatedStorage = {
		FindFirstChild = function()
			return nil
		end,
	},
	CollectionService = {
		GetTagged = function()
			return {}
		end,
	},
	HttpService = {
		GenerateGUID = function()
			return "00000000-0000-0000-0000-000000000001"
		end,
	},
	Workspace = {},
}
game = {
	GetService = function(_, name)
		return assert(services[name], "unknown service " .. tostring(name))
	end,
}

local Planner = rbxmk.loadFile("src/Core/AutoPlayPlanner.lua")()()
local information = {
	Units = {
		Farm = {
			DisplayName = "Farm Unit",
			PlacementLimit = 2,
			UpgradeInfo = {
				[0] = { Cost = 100, HitboxType = "Farm", Farm = 100 },
				[1] = { Cost = 200, Farm = 200 },
				[2] = { Cost = 400, Farm = 400 },
			},
		},
		Damage = {
			DisplayName = "Damage Unit",
			UpgradeInfo = {
				[0] = { Cost = 150, HitboxType = "Circle" },
				[1] = { Cost = 175 },
				[2] = { Cost = 350 },
			},
		},
	},
}
local playerData = {
	UnitData = {
		u1 = { Asset = "Farm", Level = 50 },
		u2 = { Asset = "Damage", Level = 50 },
	},
}
local hotbar = { Slots = { ["1"] = { ID = "u1" }, ["2"] = { ID = "u2" } } }
local slots = Planner.Slots(hotbar, playerData, information, 6)
assert(#slots == 2 and slots[1].Farm == true, "equipped farm unit discovery failed")
assert(slots[1].PlacementCost == 100 and slots[1].MaxUpgrade == 2, "unit costs or upgrade cap are wrong")

local limitedInformation = {
	Units = { Farm = { PlacementLimit = 2, UpgradeInfo = { [0] = { Cost = 100 } } } },
	Traits = { TraitData = { Unbound = { PlacementLimit = 1 } } },
}
local limitedPlayer = { UnitData = { limited = { Asset = "Farm", Trait = "Unbound" } } }
local traitLimited = Planner.Slots({ Slots = { ["1"] = { ID = "limited" } } }, limitedPlayer, limitedInformation, 1)
assert(traitLimited[1].PlacementLimit == 1, "trait placement limit was ignored")
local traitless = Planner.Slots(
	{ Slots = { ["1"] = { ID = "limited" } } },
	limitedPlayer,
	limitedInformation,
	1,
	{ Traitless = true }
)
assert(traitless[1].PlacementLimit == 2, "traitless modifier did not remove the trait placement limit")
local equippedLimit = Planner.Slots(
	{ Slots = { ["1"] = { ID = "limited", PlacementLimit = 3 } } },
	limitedPlayer,
	limitedInformation,
	1
)
assert(equippedLimit[1].PlacementLimit == 3, "equipped placement override was not authoritative")

local units = {
	a = { ID = "g1", UnitID = "u1", Owner = localPlayer, Upgrade = 1, MaxUpgrade = 2, UnitData = { Asset = "Farm" } },
	b = { ID = "g2", UnitID = "u2", Owner = localPlayer, Upgrade = 0, MaxUpgrade = 2, UnitData = { Asset = "Damage" } },
}
local placed = Planner.Placed(slots, units, localPlayer)
assert(#placed[1] == 1 and #placed[2] == 1, "placed units were not reconciled to equipped slots")
units.phantom = {
	ID = "phantom",
	UnitID = "u1",
	Owner = localPlayer,
	Upgrade = 0,
	MaxUpgrade = 2,
	IsPhantom = true,
}
placed = Planner.Placed(slots, units, localPlayer)
assert(#placed[1] == 1, "phantom previews were mistaken for placed units")
local placement, missing = Planner.NextPlacement(slots, placed, { 2, 1 })
assert(
	missing == true and placement.Slot.Index == 1 and placement.Count == 1,
	"deleted or missing placement detection failed"
)
local authoritative = Planner.NextPlacement(slots, placed, { 2, 2 }, { Farm = 2, Damage = 1 })
assert(
	authoritative and authoritative.Slot.Index == 2 and authoritative.Count == 1,
	"authoritative placement counts did not stop a capped unit"
)
assert(
	Planner.TotalPlacementCount(slots, placed, { Farm = 2, Damage = 1 }) == 3,
	"authoritative total placement count is wrong"
)
local globalCapped, globalMissing = Planner.NextPlacement(slots, placed, { 20, 20 }, nil, 2)
assert(globalCapped == nil and globalMissing == false, "match-wide placement cap was ignored")
local blockedPlacement, blockedMissing = Planner.NextPlacement(
	slots,
	{ [1] = {}, [2] = {} },
	{ 1, 1 },
	nil,
	nil,
	{ [1] = 100 },
	50
)
assert(
	blockedMissing == true and blockedPlacement and blockedPlacement.Slot.Index == 2,
	"an obstructed cheap slot starved later normal placement slots"
)
local expiredPlacement = Planner.NextPlacement(
	slots,
	{ [1] = {}, [2] = {} },
	{ 1, 1 },
	nil,
	nil,
	{ [1] = 49 },
	50
)
assert(expiredPlacement and expiredPlacement.Slot.Index == 1, "expired placement backoff did not recover")
local farmUpgrade = Planner.NextUpgrade(slots, placed, { 20, 20 }, { 1, 10 }, true, true, 1000)
assert(farmUpgrade and farmUpgrade.Slot.Index == 1, "farm-first upgrade selection failed")
local priorityUpgrade = Planner.NextUpgrade(slots, placed, { 20, 20 }, { 1, 10 }, true, false, 1000)
assert(priorityUpgrade and priorityUpgrade.Slot.Index == 2, "configured upgrade priority failed")
local lowestCost = Planner.NextUpgrade(slots, placed, { 20, 20 }, { 0, 0 }, false, false, 1000)
assert(lowestCost and lowestCost.Slot.Index == 2, "lowest-cost upgrade selection failed")
local capped = Planner.NextUpgrade(slots, placed, { 1, 0 }, { 10, 10 }, true, false, 1000)
assert(capped == nil, "configured or intrinsic upgrade caps were ignored")
units.a.Unupgradeable = true
local upgradeablePlaced = Planner.Placed(slots, units, localPlayer)
local upgradeable = Planner.NextUpgrade(slots, upgradeablePlaced, { 20, 20 }, { 1, 1 }, false, false, 1000)
assert(upgradeable and upgradeable.Slot.Index == 2, "server-unupgradeable units were retried")
local backedOffUpgrade = Planner.NextUpgrade(
	slots,
	placed,
	{ 20, 20 },
	{ 1, 1 },
	false,
	false,
	1000,
	{ g2 = 100 },
	50
)
assert(backedOffUpgrade and backedOffUpgrade.Slot.Index == 1, "rejected upgrades starved other normal units")
assert(
	Planner.RoundReset({ Wave = 20, Time = 300, Total = 6 }, { Wave = 1, Time = 2, Total = 0 }),
	"seamless replay was not detected"
)
assert(
	Planner.RoundReset({ Wave = 20, Time = 300, Total = 1 }, { Wave = 20, Time = 300, Total = 0 }),
	"full unit removal was not detected"
)
assert(
	not Planner.RoundReset({ Wave = 20, Time = 300, Total = 6 }, { Wave = 21, Time = 305, Total = 5 }),
	"normal match progress was mistaken for a replay"
)

local path = { Vector3.new(0, 0, 0), Vector3.new(0, 0, 100) }
local actOnePath = { Vector3.new(1000, 0, 0), Vector3.new(1000, 0, 100) }
local actTwoPath = { Vector3.new(2000, 0, 0), Vector3.new(2000, 0, 100) }
local actThreePath = { Vector3.new(3000, 0, 0), Vector3.new(3000, 0, 100) }
local multiActMap = { Paths = { [1] = actOnePath, [2] = actTwoPath, [3] = actThreePath } }
assert(#Planner.ActivePaths(multiActMap, {}) == 0, "multi-act maps guessed a route before enemies spawned")
local playerSelectedPaths = Planner.ActivePaths(multiActMap, {}, { Vector3.new(2990, 0, 50) })
assert(
	#playerSelectedPaths == 1 and playerSelectedPaths[1] == actThreePath,
	"player proximity did not immediately identify Act 3"
)
local enemySelectedPaths = Planner.ActivePaths(multiActMap, {}, {
	Vector3.new(2010, 0, 20),
	Vector3.new(1995, 0, 70),
})
assert(
	#enemySelectedPaths == 1 and enemySelectedPaths[1] == actTwoPath,
	"rendered enemy positions did not identify their active route"
)
local activeActPaths = Planner.ActivePaths(multiActMap, {
	enemy = { Data = { PathIndex = 3 }, WaypointIndex = 2 },
})
assert(#activeActPaths == 1 and activeActPaths[1] == actThreePath, "live enemy PathIndex did not select Act 3")
local mixedActPaths = Planner.ActivePaths(multiActMap, {
	a = { PathIndex = 2 },
	b = { Data = { PathIndex = 3 } },
})
assert(
	#mixedActPaths == 2
		and (mixedActPaths[1] == actTwoPath or mixedActPaths[2] == actTwoPath)
		and (mixedActPaths[1] == actThreePath or mixedActPaths[2] == actThreePath),
	"simultaneously active enemy routes were not retained"
)
local nearSpawn = Planner.SamplePath(path, 1)
local nearBase = Planner.SamplePath(path, 99)
assert(
	math.abs(nearSpawn.Z - 1) < 0.01 and math.abs(nearBase.Z - 99) < 0.01,
	"path percentages are reversed or inaccurate"
)
assert(
	Planner.Candidate(path, 50, 6, 1, 0) ~= Planner.Candidate(path, 50, 6, 2, 0),
	"placement spacing did not produce unique positions"
)
local bounded = Planner.Candidate(path, 50, 20, 1, 9999)
local center = Planner.SamplePath(path, 50)
assert(
	Vector3.new(bounded.Position.X - center.X, 0, bounded.Position.Z - center.Z).Magnitude <= 23,
	"placement retries can escape too far from the selected path"
)

local factories = {
	AutomationCatalog = rbxmk.loadFile("src/Core/AutomationCatalog.lua")(),
	AutoPlayPlanner = function()
		return Planner
	end,
	SmartAutoPlayPlanner = rbxmk.loadFile("src/Core/SmartAutoPlayPlanner.lua")(),
	MatchTelemetry = rbxmk.loadFile("src/Core/MatchTelemetry.lua")(),
	JoinCatalog = rbxmk.loadFile("src/Core/JoinCatalog.lua")(),
	AutoPlay = rbxmk.loadFile("src/Modules/AutoPlay.lua")(),
}
local function Import(name)
	return factories[name](Import)
end
local controls, sections = {}, {}
local section = {}
function section:Header() end
function section:Paragraph() end
function section:Label()
	return { UpdateName = function() end }
end
local registry = {}
local function add(settings, flag)
	controls[flag] = { Settings = settings }
	return controls[flag]
end
function registry:Toggle(_, settings, flag)
	return add(settings, flag)
end
function registry:Slider(_, settings, flag)
	return add(settings, flag)
end
function registry:Dropdown(_, settings, flag)
	return add(settings, flag)
end
local function page(name)
	return {
		Section = function(_, settings)
			table.insert(sections, { Page = name, Side = settings.Side })
			return section
		end,
	}
end
local context = {
	Tabs = {
		AutoPlayNormal = page("Normal"),
		AutoPlaySmart = page("Smart"),
	},
	Registry = registry,
	Runtime = { Alive = false, Generation = 1, Notify = function() end },
	FileSystem = { Root = "TestData", WriteJson = function() return true end },
	Player = { UserId = 1, Name = "Tester" },
	Build = { Version = "test" },
	RegisterCleanup = function() end,
}
local module = Import("AutoPlay")
local ok, state = pcall(module.Init, module, context)
assert(ok, "Auto Play UI initialization failed: " .. tostring(state))
assert(
	#sections == 6
		and sections[1].Page == "Normal"
		and sections[1].Side == "Left"
		and sections[3].Side == "Right"
		and sections[5].Page == "Smart",
	"Auto Play sections are not split correctly"
)
assert(
	controls["auto_play.spacing"].Settings.Minimum == 1 and controls["auto_play.spacing"].Settings.Maximum == 20,
	"spacing range is wrong"
)
assert(
	controls["auto_play.path_position"].Settings.Minimum == 1
		and controls["auto_play.path_position"].Settings.Maximum == 99,
	"path position range is wrong"
)
assert(
	controls["auto_play.path_position"].Settings.DisplayMethod == "LiteralPercent",
	"path position is not displayed as a percentage"
)
for index = 1, 6 do
	assert(controls["auto_play.priority_" .. index].Settings.Maximum == 10, "priority range is wrong")
	assert(controls["auto_play.max_place_" .. index].Settings.Maximum == 20, "placement cap range is wrong")
	assert(controls["auto_play.max_upgrade_" .. index].Settings.Maximum == 20, "upgrade cap range is wrong")
end
assert(controls["auto_play.smart.enabled"], "Smart Auto Play toggle is missing")
assert(controls["auto_play.smart.strategy"].Settings.Search == true, "Smart strategy dropdown is not searchable")
assert(not controls["auto_play.smart.reserve"], "Smart yen reserve should not require manual tuning")
assert(not controls["auto_play.smart.spacing"], "Smart placement spacing should not require manual tuning")

local source = fs.read("src/Modules/AutoPlay.lua", "bin")
assert(string.find(source, "Planning: Match complete", 1, true), "Smart planner does not stop its status at match completion")
assert(string.find(source, "Planning: Saving for deployment", 1, true), "Smart planner saving status is missing")
assert(string.find(source, "MapDisplayName", 1, true), "Smart planner does not resolve friendly map names")
assert(
	string.find(source, "GameTime", 1, true) and string.find(source, "LastTotal", 1, true),
	"seamless replay reset detection is missing"
)
assert(
	string.find(source, "PlaceRetries", 1, true) and string.find(source, "pendingComplete", 1, true),
	"placement confirmation and retry tracking are missing"
)
assert(
	string.find(source, "current.PlacementCap", 1, true)
		and string.find(source, "state.BlockedUpgrades", 1, true),
	"normal Auto Play does not enforce the global cap or back off rejected upgrades"
)
assert(string.find(source, 'GamePlayerAction("PlaceGameUnit"', 1, true), "placement request is missing")
assert(string.find(source, 'GamePlayerAction("UpgradeGameUnit"', 1, true), "upgrade request is missing")
assert(
	string.find(source, "updateSmartVisualization(state, decision, resolved)", 1, true)
		and string.find(source, "place(ctx, state, current, decision, resolved)", 1, true),
	"Smart preview and placement do not share the exact validated CFrame"
)
assert(
	string.find(source, "candidate = findPlacement(state, snapshot", 1, true)
		and string.find(source, "RecordRetry = false", 1, true),
	"normal placement preview does not use the validated placement search"
)
assert(
	string.find(source, "tonumber(choice.Spacing) or state.Spacing", 1, true),
	"normal placement spacing is not enforced by the real placement search"
)
assert(
	string.find(source, 'CollectionService:GetTagged(tag)', 1, true)
		and string.find(source, 'environment:FindFirstChild("Path")', 1, true)
		and string.find(source, "not isOverPath(surface)", 1, true),
	"placement search does not use tagged surfaces while excluding the enemy road"
)
assert(
	string.find(source, "state.BlockedSlots[decision.Slot.Index]", 1, true),
	"one obstructed slot can still stall the complete Smart planner"
)
assert(
	string.find(source, "slot.BoundingHeight", 1, true)
		and string.find(source, "size.Y", 1, true),
	"placement CFrames do not include the unit bounding-box center height"
)
assert(
	string.find(source, 'Workspace:FindFirstChild("Map")', 1, true)
		and string.find(source, "Enum.RaycastFilterType.Include", 1, true),
	"placement projection is not restricted to active map geometry"
)
assert(string.find(source, "state.UnitUtils.IsPlacementAllowed", 1, true), "game placement validation is missing")
assert(
	string.find(source, 'map:FindFirstChild("Enviornment")', 1, true)
		and string.find(source, 'map:FindFirstChild("Environment")', 1, true),
	"live and exported map path layouts are not supported"
)
assert(
	string.find(source, "math.clamp(combatRange * 0.48, 4, 10)", 1, true)
		and string.find(source, ").Magnitude <= (maxPathDistance or 22)", 1, true),
	"smart combat placement is not bounded by usable unit range around the selected path"
)
assert(
	string.find(source, "SmartPlanner.RouteCoverage", 1, true)
		and string.find(source, "SmartPlanner.ReconcilePlacement", 1, true),
	"resolved placement candidates are not ranked and reported by real route coverage"
)
assert(Planner.RouteVote(0, 0.8, 0.79) < 0, "reverse route movement was not detected")
assert(Planner.RouteVote(0, 0.2, 0.21) > 0, "forward route movement was not detected")
assert(Planner.RouteVote(3, 0.2, 0.20001) == 3, "route jitter changed the learned direction")
assert(Planner.RouteVote(-11, 0.8, 0.7) == -11, "enemy replacement jump corrupted route direction")

print("Auto Play tests passed")
