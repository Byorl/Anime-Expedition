local Hub = ...
local Library = Hub.Core.Library

local MODULE_ID = "PlaceAnywhere"

local function restoreHooks(runtime)
	if runtime.OriginalIsPlacementAllowed and runtime.UnitUtils then
		pcall(function()
			runtime.UnitUtils.IsPlacementAllowed = runtime.OriginalIsPlacementAllowed
		end)
	end
	if runtime.Actions and runtime.HadActionsHook then
		pcall(function()
			if runtime.OriginalActionsIsPlacementAllowed ~= nil then
				rawset(runtime.Actions, "IsPlacementAllowed", runtime.OriginalActionsIsPlacementAllowed)
			end
		end)
	end
	runtime.OriginalIsPlacementAllowed = nil
	runtime.OriginalActionsIsPlacementAllowed = nil
	runtime.HadActionsHook = false
	runtime.UnitUtils = nil
	runtime.Actions = nil
end

local function applyHooks(runtime)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local UnitUtils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UnitUtils"))
	local Actions = require(ReplicatedStorage:WaitForChild("FusionPackage"):WaitForChild("Actions"))

	runtime.UnitUtils = UnitUtils
	runtime.Actions = Actions
	runtime.OriginalIsPlacementAllowed = UnitUtils.IsPlacementAllowed

	UnitUtils.IsPlacementAllowed = function(...)
		return true
	end

	runtime.HadActionsHook = false
	pcall(function()
		runtime.OriginalActionsIsPlacementAllowed = rawget(Actions, "IsPlacementAllowed")
		rawset(Actions, "IsPlacementAllowed", function(...)
			return true
		end)
		runtime.HadActionsHook = true
	end)
end

return {
	Id = MODULE_ID,
	Name = "Place Anywhere",
	Description = "Forces client placement checks to always allow.",
	Defaults = {
		Enabled = false,
	},

	OnEnable = function(_state, runtime, hub)
		restoreHooks(runtime)
		applyHooks(runtime)
		Library.Notify(hub.Window, "Place Anywhere", "Enabled")
	end,

	OnDisable = function(_state, runtime, hub)
		restoreHooks(runtime)
		Library.Notify(hub.Window, "Place Anywhere", "Disabled")
	end,

	OnDestroy = function(_state, runtime)
		restoreHooks(runtime)
	end,

	BuildUi = function(state, _window, tabs, hub)
		local tab = tabs.Misc
		local section = tab:Section({ Side = "Right" })
		section:Header({ Name = "Place Anywhere" })
		section:Paragraph({
			Header = "Client placement unlock",
			Body = "Bypasses UnitUtils.IsPlacementAllowed on the client. The server can still reject invalid spots.",
		})

		hub.UI:BindToggle(section, {
			Name = "Place Anywhere",
			Default = state.Enabled == true,
			Flag = MODULE_ID .. ".Enabled",
		})
	end,
}
