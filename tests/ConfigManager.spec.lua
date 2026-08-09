task = task or {delay = function(_, callback) callback() end, wait = function() end}

local files = {}
local function clone(value)
	if type(value) ~= "table" then return value end
	local output = {}
	for key, child in pairs(value) do output[clone(key)] = clone(child) end
	return output
end

local store = {Available = true}
function store:EnsureFolder() return true end
function store:List(folder)
	local output = {}
	for path in pairs(files) do
		if string.sub(path, 1, #folder + 1) == folder .. "/" then table.insert(output, path) end
	end
	return output
end
function store:ReadJson(path, fallback) return files[path] and clone(files[path]) or clone(fallback) end
function store:ReadJsonDetailed(path) return files[path] and clone(files[path]) or nil, files[path] and path or "missing" end
function store:WriteJson(path, value) files[path] = clone(value); return true end
function store:Delete(path) files[path] = nil; return true end

local currentValues = { ["misc.auto_reconnect"] = false }
local registry = {OwnerVersions = {Misc = 1}}
function registry:Snapshot() return clone(currentValues) end
function registry:SnapshotModules() return {Misc = {Version = 1, Values = clone(currentValues)}} end
function registry:ApplyAtomic(values) currentValues = clone(values); return true end

local cache = {}
local factories = {
	Build = rbxmk.loadFile("src/Build.lua")(),
	Util = rbxmk.loadFile("src/Core/Util.lua")(),
	ConfigManager = rbxmk.loadFile("src/Core/ConfigManager.lua")(),
}
local function Import(name)
	if cache[name] then return cache[name] end
	cache[name] = factories[name](Import)
	return cache[name]
end

local ConfigManager = Import("ConfigManager")
local first = ConfigManager.new(store, registry, {UserId = 100, Name = "First"})
local initOk, initError = first:Initialize()
assert(initOk, initError)
assert(first.Account.Schema == 3 and first.Account.SelectedConfig == "main", "schema 3/main initialization failed")
assert(
	type(first.Account.UI.MobileLauncher) == "table"
		and first.Account.UI.MobileLauncher.X == 0.96
		and first.Account.UI.MobileLauncher.Y == 0.86,
	"mobile launcher account defaults failed"
)
assert(first:ResolveName("MAIN") == "main", "case-insensitive lookup failed")

local createOk, createError = first:Create("Work")
assert(createOk, createError)
local collisionOk = first:Create("work")
assert(not collisionOk, "case-insensitive collision was accepted")
assert(first.Duplicate == nil and first.Rename == nil and first.SetLocked == nil and first.GetMetadata == nil,
	"removed config operations are still exposed")

local loadOk, loaded = first:Load("Work")
assert(loadOk, loaded)
local workPath = first:_ConfigPath("Work")
files[workPath].Revision = files[workPath].Revision + 1
local conflictOk, conflictError = first:Save("Work")
assert(not conflictOk and string.find(conflictError, "changed on disk", 1, true), "revision conflict was not detected")

loadOk, loaded = first:Load("Work")
assert(loadOk, loaded)

local phantomBackup = first.ConfigFolder .. "/Work.bak.json"
files[phantomBackup] = clone(files[workPath])
local visibleConfigs = first:List()
assert(files[phantomBackup] == nil and not table.find(visibleConfigs, "Work.bak"), "backup sidecar appeared as a config")

local second = ConfigManager.new(store, registry, {UserId = 200, Name = "Second"})
initOk, initError = second:Initialize()
assert(initOk, initError)
local deleteOk, deleteError = second:Delete("Work")
assert(deleteOk, deleteError)

files[first:_ConfigPath("Legacy")] = {
	Schema = 2,
	Name = "Legacy",
	Revision = 1,
	Locked = true,
	LockedByUserId = 999,
	Values = {
		["misc.auto_reconnect"] = true,
		["settings.ui_scale"] = 140,
	},
}
loadOk, loaded = first:Load("Legacy")
assert(loadOk, loaded)
assert(loaded.Locked == nil and loaded.LockedByUserId == nil, "legacy lock metadata was not removed")
assert(currentValues["misc.auto_reconnect"] == true, "schema 2 feature value was not migrated")
assert(currentValues["settings.ui_scale"] == nil, "legacy global UI scale was not removed")

local guardedPath = first:_ConfigPath("Guarded")
files[guardedPath] = {
	Schema = 3,
	Name = "Guarded",
	Revision = 7,
	Modules = {Misc = {Version = 1, Values = {["misc.auto_reconnect"] = true}}},
}
currentValues = {["misc.auto_reconnect"] = false}
local guarded = ConfigManager.new(store, registry, {UserId = 300, Name = "GuardedUser"})
initOk, initError = guarded:Initialize()
assert(initOk, initError)
guarded.Account.SelectedConfig = "Guarded"
guarded.Account.AutoSave = true
guarded:ScheduleAutoSave()
guarded:Flush()
assert(files[guardedPath].Modules.Misc.Values["misc.auto_reconnect"] == true,
	"startup defaults overwrote a profile before it was loaded")
loadOk, loaded = guarded:Load("Guarded")
assert(loadOk, loaded)
guarded:ActivateProfile()
assert(currentValues["misc.auto_reconnect"] == true, "guarded profile did not load")
currentValues["misc.auto_reconnect"] = false
guarded:ScheduleAutoSave()
guarded:Flush()
assert(files[guardedPath].Modules.Misc.Values["misc.auto_reconnect"] == false,
	"autosave did not resume after profile activation")

print("ConfigManager tests passed")
