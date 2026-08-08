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
local farmUpgrade = Planner.NextUpgrade(slots, placed, { 20, 20 }, { 1, 10 }, true, true, 1000)
assert(farmUpgrade and farmUpgrade.Slot.Index == 1, "farm-first upgrade selection failed")
local priorityUpgrade = Planner.NextUpgrade(slots, placed, { 20, 20 }, { 1, 10 }, true, false, 1000)
assert(priorityUpgrade and priorityUpgrade.Slot.Index == 2, "configured upgrade priority failed")
local lowestCost = Planner.NextUpgrade(slots, placed, { 20, 20 }, { 0, 0 }, false, false, 1000)
assert(lowestCost and lowestCost.Slot.Index == 2, "lowest-cost upgrade selection failed")
local capped = Planner.NextUpgrade(slots, placed, { 1, 0 }, { 10, 10 }, true, false, 1000)
assert(capped == nil, "configured or intrinsic upgrade caps were ignored")
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

local factories = {
	AutoPlayPlanner = function()
		return Planner
	end,
	SmartAutoPlayPlanner = rbxmk.loadFile("src/Core/SmartAutoPlayPlanner.lua")(),
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
assert(
	string.find(source, "GameTime", 1, true) and string.find(source, "LastTotal", 1, true),
	"seamless replay reset detection is missing"
)
assert(
	string.find(source, "PlaceRetries", 1, true) and string.find(source, "pendingComplete", 1, true),
	"placement confirmation and retry tracking are missing"
)
assert(string.find(source, 'GamePlayerAction("PlaceGameUnit"', 1, true), "placement request is missing")
assert(string.find(source, 'GamePlayerAction("UpgradeGameUnit"', 1, true), "upgrade request is missing")

print("Auto Play tests passed")
