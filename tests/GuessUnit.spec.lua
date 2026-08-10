task = task or {}
local activeRuntime
task.wait = function()
	if activeRuntime then activeRuntime.Alive = false end
end
task.spawn = function(callback)
	callback()
	return {Kind = "thread"}
end

local Util = rbxmk.loadFile("src/Core/Util.lua")()(function() end)
local factory = rbxmk.loadFile("src/Modules/GuessUnit.lua")()
local module = factory(function(name)
	if name == "Util" then return Util end
	error("unexpected import " .. tostring(name))
end)

local callbacks = {}
local controls = {}
local section = {}
function section:Header() end
function section:Paragraph() end
function section:Label(settings)
	return {Text = settings.Text, UpdateName = function(self, value) self.Text = value end}
end
local registry = {}
function registry:Toggle(_, settings, flag)
	callbacks[flag] = settings.Callback
	controls[flag] = {Settings = settings}
	return controls[flag]
end
function registry:Dropdown(_, settings, flag)
	callbacks[flag] = settings.Callback
	controls[flag] = {Settings = settings}
	return controls[flag]
end

local playerData = {EventData = {GuessUnitEvent = {ClearHistory = {}}}}
local actions = {}
local runtime = {Alive = false}
activeRuntime = runtime
local cleanup = {}
local context = {
	Tabs = {MiscMinigame = {Section = function() return section end}},
	Registry = registry,
	Runtime = runtime,
	RegisterCleanup = function(_, value) table.insert(cleanup, value) end,
	Game = {
		StateDeep = function(_, name)
			assert(name == "PlayerData", "Guess Unit read the wrong replicated state")
			return playerData
		end,
		PlayerData = function() return playerData end,
		Action = function(_, action, eventId, request, difficulty, victory)
			table.insert(actions, {action, eventId, request, difficulty, victory})
			playerData.EventData.GuessUnitEvent.ClearHistory[difficulty] = {
				ClearTime = os.time(),
				IsVictory = true,
			}
			return true
		end,
	},
}

local state = module.Init(module, context)
assert(controls["guess_unit.enabled"], "Guess That Unit toggle was not registered")
assert(controls["guess_unit.difficulties"], "Guess That Unit difficulties were not registered")
assert(controls["guess_unit.difficulties"].Settings.Multi == true, "Guess That Unit difficulty is not multi-select")
assert(controls["guess_unit.difficulties"].Settings.Search == true, "Guess That Unit difficulty search is disabled")
callbacks["guess_unit.difficulties"]({Normal = true, Hard = true})
callbacks["guess_unit.enabled"](true)

runtime.Alive = true
module.Enable(module, context, state)
assert(#actions == 1 and actions[1][4] == "Hard", "Hard was not completed first")
assert(actions[1][1] == "SendEventRequest" and actions[1][2] == "GuessUnitEvent", "wrong event action was used")
assert(actions[1][3] == "GameResult" and actions[1][5] == true, "victory result was not submitted")

runtime.Alive = true
module.Enable(module, context, state)
assert(#actions == 2 and actions[2][4] == "Normal", "Normal was not completed after Hard")

runtime.Alive = true
module.Enable(module, context, state)
assert(#actions == 2, "completed difficulties were submitted again")
for _, action in ipairs(actions) do assert(action[3] ~= "Retry", "paid retry was used") end
assert(string.find(state.Status, "complete", 1, true), "completion status was not shown")

module.Disable(module, context, state)
assert(state.Alive == false and state.Enabled == false, "Guess Unit did not unload cleanly")
print("Guess Unit tests passed")
