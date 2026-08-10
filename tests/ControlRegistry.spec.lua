task = task or {wait = function() end, defer = function(callback) callback() end}

local cache = {}
local factories = {
	Util = rbxmk.loadFile("src/Core/Util.lua")(),
	ControlRegistry = rbxmk.loadFile("src/Core/ControlRegistry.lua")(),
}
local function Import(name)
	if cache[name] then return cache[name] end
	cache[name] = factories[name](Import)
	return cache[name]
end

local ControlRegistry = Import("ControlRegistry")
local registry = ControlRegistry.new()
registry:SetOwnerActive("Test", true)
local scope = registry:Scope("Test")
local callbacks, changes = 0, 0
registry.OnChanged = function() changes = changes + 1 end

local section = {}
function section:Toggle(settings)
	local state = settings.Default == true
	return {
		UpdateState = function(_, value) state = value == true; settings.Callback(value) end,
		GetState = function() return state end,
	}
end
function section:Slider(settings)
	local value = settings.Default
	return {UpdateValue = function(_, updated) value = updated end, GetValue = function() return value end}
end
function section:Input(settings)
	local value = settings.Default
	return {
		UpdateText = function(_, updated) value = updated; settings.onChanged(updated) end,
		GetInput = function() return value end,
	}
end
function section:Dropdown(settings)
	local selected
	return {
		UpdateSelection = function(_, value) selected = value; settings.Callback(value) end,
		GetOptions = function()
			local output = {}
			for _, option in ipairs(settings.Options or {}) do
				local enabled = option == selected
				if type(selected) == "table" then
					enabled = selected[option] == true
					if not enabled then
						for _, item in ipairs(selected) do
							if item == option then enabled = true break end
						end
					end
				end
				output[option] = enabled
			end
			return output
		end,
	}
end

local toggle = scope:Toggle(section, {Default = true, Callback = function() callbacks = callbacks + 1 end}, "test.toggle")
local slider = scope:Slider(section, {Default = 50, Minimum = 0, Maximum = 100, Step = 1, Callback = function() callbacks = callbacks + 1 end}, "test.slider")
scope:Input(section, {Default = "abc", onChanged = function() callbacks = callbacks + 1 end}, "test.input")
local dropdown = scope:Dropdown(section, {
	Options = {"Current [unit-1]"},
	Default = 1,
	ResolveValue = function(value)
		if value == "Old [unit-1]" then return "Current [unit-1]" end
		return value
	end,
	Callback = function() callbacks = callbacks + 1 end,
}, "test.dropdown")
scope:Dropdown(section, {
	Options = {"Normal", "Hard"},
	Default = {},
	Multi = true,
	Callback = function() callbacks = callbacks + 1 end,
}, "test.multi_dropdown")

local applyOk, applyError = registry:ApplyAtomic({
	["test.toggle"] = false,
	["test.slider"] = 0,
	["test.input"] = "",
	["test.dropdown"] = "Old [unit-1]",
	["test.multi_dropdown"] = {"Normal", "Hard"},
})
assert(applyOk, applyError)
assert(registry:Get("test.toggle") == false, "saved false was not applied")
assert(registry:Get("test.slider") == 0, "saved zero was not applied")
assert(registry:Get("test.input") == "", "saved empty string was not applied")
assert(changes == 0, "atomic apply leaked autosave change callbacks")
assert(registry:Get("test.dropdown") == "Current [unit-1]", "dynamic dropdown identity was not resolved")
assert(callbacks == 5, "atomic apply did not restore live feature callbacks")
local verifyOk, verifyError = registry:VerifyApplied()
assert(verifyOk, verifyError)
dropdown.GetOptions = function() return {} end
local pendingOk, pendingError, pendingWarning = registry:VerifyApplied()
assert(pendingOk and pendingError == "" and string.find(pendingWarning, "test.dropdown", 1, true),
	"temporarily unavailable dropdown caused a full config rejection")

toggle:UpdateState(true)
assert(registry:Get("test.toggle") == true and changes == 1, "user change was not recorded")
registry:SetOwnerActive("Test", false)
toggle:UpdateState(false)
assert(registry:Get("test.toggle") == true and changes == 1, "dormant module callback changed state")

print("ControlRegistry tests passed")
