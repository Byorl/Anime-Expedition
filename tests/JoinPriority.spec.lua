local Priority = rbxmk.loadFile("src/Modules/JoinPriority.lua")()()

local controls = {}
local section = {}
function section:Header() end
function section:Label() end
function section:Divider() end

local registry = {}
function registry:Toggle(_, settings, flag)
	controls[flag] = settings
	return {}
end
function registry:Slider(_, settings, flag)
	controls[flag] = settings
	return {}
end

local enabled = false
local priorities = {}
local context = {
	Tabs = {Priority = {Section = function() return section end}},
	Registry = registry,
	Join = {
		Modes = function() return {"Story", "Future Mode"} end,
		SetPriorityEnabled = function(_, value) enabled = value end,
		SetPriority = function(_, name, value) priorities[name] = value end,
	},
}

local state = Priority:Init(context)
assert(#state.Modes == 7, "registered future join mode was not auto-discovered")
for _, name in ipairs({"story", "raid", "expedition", "challenge", "event", "bounty", "future_mode"}) do
	local control = controls["join_priority." .. name]
	assert(control, "priority control is missing for " .. name)
	assert(control.Minimum == 1 and control.Maximum == 6 and control.Step == 1 and control.Precision == 0,
		"priority control has an invalid integer range for " .. name)
end
controls["join_priority.enabled"].Callback(true)
controls["join_priority.challenge"].Callback(6)
assert(enabled == true and priorities.Challenge == 6, "priority callbacks did not update the coordinator")

print("Join priority tests passed")
