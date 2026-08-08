task = task or {}
task.wait = task.wait or function() end
task.spawn = task.spawn or function(callback) callback() end
task.defer = task.defer or function(callback) callback() end

local function signal()
	return {Connect = function(_, callback)
		return {Disconnect = function() end, Callback = callback}
	end}
end
local services = {
	HttpService = {JSONEncode = function() return "{}" end},
	CollectionService = {
		GetInstanceAddedSignal = function() return signal() end,
		GetTagged = function() return {} end,
	},
	Lighting = {GetDescendants = function() return {} end, DescendantAdded = signal()},
	RunService = {},
	Workspace = {
		GetDescendants = function() return {} end,
		FindFirstChildOfClass = function() return nil end,
		DescendantAdded = signal(),
	},
}
game = {GetService = function(_, name) return assert(services[name], "unknown service " .. tostring(name)) end}
workspace = services.Workspace

local cache = {}
local factories = {
	Util = rbxmk.loadFile("src/Core/Util.lua")(),
	RewardScanner = rbxmk.loadFile("src/Core/RewardScanner.lua")(),
	AutoClaim = rbxmk.loadFile("src/Modules/AutoClaim.lua")(),
	Performance = rbxmk.loadFile("src/Modules/Performance.lua")(),
}
local function Import(name)
	if cache[name] then return cache[name] end
	cache[name] = factories[name](Import)
	return cache[name]
end

local autoClaim = Import("AutoClaim")
local cleanup
local autoState = {Generation = 0, Alive = false, LastErrors = {}}
local autoContext = {
	Game = {Ready = true},
	Runtime = {Alive = false},
	RegisterCleanup = function(_, callback) cleanup = callback end,
}
local autoOk, autoError = pcall(autoClaim.Enable, autoClaim, autoContext, autoState)
assert(autoOk, "AutoClaim Enable lifecycle binding failed: " .. tostring(autoError))
assert(autoState.Generation == 1 and type(cleanup) == "function", "AutoClaim scheduler did not initialize")
cleanup()

local callbacks, controls = {}, {}
local section = {Header = function() end}
local registry = {}
function registry:Toggle(_, settings, flag)
	callbacks[flag] = settings.Callback
	local control = {UpdateState = function(_, value) settings.Callback(value) end}
	controls[flag] = control
	return control
end
local performanceContext = {
	Tabs = {Misc = {Section = function() return section end}},
	Registry = registry,
	Runtime = {Notify = function() end},
}
local performance = Import("Performance")
local performanceState = performance.Init(performance, performanceContext)
assert(performanceState.RenderingControl == controls["performance.disable_3d_rendering"], "rendering control was bound to the wrong toggle")
callbacks["performance.delete_enemies"](true)
callbacks["performance.delete_enemies"](false)
callbacks["performance.fps_boost"](true)
callbacks["performance.fps_boost"](false)
local disableOk, disableError = pcall(performance.Disable, performance, performanceContext, performanceState)
assert(disableOk, "Performance Disable lifecycle binding failed: " .. tostring(disableError))

print("Feature lifecycle tests passed")
