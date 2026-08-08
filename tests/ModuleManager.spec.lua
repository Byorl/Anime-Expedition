local cache = {}
local factories = {
	Util = rbxmk.loadFile("src/Core/Util.lua")(),
	Janitor = rbxmk.loadFile("src/Core/Janitor.lua")(),
	ModuleManager = rbxmk.loadFile("src/Core/ModuleManager.lua")(),
}

local function Import(name)
	if cache[name] then return cache[name] end
	local value = factories[name](Import)
	cache[name] = value
	return value
end

local ModuleManager = Import("ModuleManager")

local registry = {
	Active = {},
	Versions = {},
	SetOwnerVersion = function(self, name, version) self.Versions[name] = version end,
	SetOwnerActive = function(self, name, active) self.Active[name] = active end,
	Scope = function(self) return self end,
	ReapplyOwner = function() return true end,
}

local events = {}
local manager = ModuleManager.new({Registry = registry})
manager:Register({
	Name = "Feature",
	Version = 2,
	Dependencies = {"Core"},
	Init = function() table.insert(events, "init-feature") end,
	Enable = function() table.insert(events, "enable-feature") end,
	Disable = function() table.insert(events, "disable-feature") end,
})
manager:Register({
	Name = "Core",
	Dependencies = {},
	Init = function() table.insert(events, "init-core") end,
	Enable = function() table.insert(events, "enable-core") end,
	Disable = function() table.insert(events, "disable-core") end,
})

local loaded, loadError = manager:LoadAll()
assert(loaded, loadError)
assert(table.concat(events, ",") == "init-core,enable-core,init-feature,enable-feature", "dependency load order is wrong")
assert(registry.Versions.Feature == 2, "module version was not registered")

manager:UnloadAll()
assert(table.concat(events, ",") == "init-core,enable-core,init-feature,enable-feature,disable-feature,disable-core", "reverse unload order is wrong")
assert(registry.Active.Core == false and registry.Active.Feature == false, "module scopes were not disabled")

local cycle = ModuleManager.new({Registry = registry})
cycle:Register({Name = "A", Dependencies = {"B"}})
cycle:Register({Name = "B", Dependencies = {"C"}})
cycle:Register({Name = "C", Dependencies = {"A"}})
local cycleOk, cycleError = cycle:ValidateGraph()
assert(not cycleOk and string.find(cycleError, "A -> B -> C -> A", 1, true), "cycle path was not reported")

local failing = ModuleManager.new({Registry = registry})
failing:Register({Name = "Broken", Init = function() error("intentional failure") end})
local failureOk, failureError = failing:LoadAll()
assert(not failureOk, "broken module unexpectedly loaded")
assert(string.find(failureError, "module 'Broken' failed during Init", 1, true), "lifecycle stage missing from error")
assert(string.find(failureError, "intentional failure", 1, true), "root cause missing from error")

print("ModuleManager tests passed")
