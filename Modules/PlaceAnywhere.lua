local function resolveHub(...)
	local viaVarargs = ...
	if typeof(viaVarargs) == "table" and viaVarargs.Core ~= nil then
		return viaVarargs
	end
	local env = (getgenv and getgenv()) or shared or _G
	return env.__AEHubLoading
end

local Hub = resolveHub(...)
assert(Hub and Hub.Core and Hub.Core.Library, "[AEHub] Hub context missing while loading PlaceAnywhere")
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
	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared") or ReplicatedStorage:WaitForChild("Shared", 10)
	if not sharedFolder then
		error("Shared folder not found")
	end
	local unitUtilsModule = sharedFolder:FindFirstChild("UnitUtils") or sharedFolder:WaitForChild("UnitUtils", 10)
	if not unitUtilsModule then
		error("UnitUtils not found")
	end
	local fusionPackage = ReplicatedStorage:FindFirstChild("FusionPackage") or ReplicatedStorage:WaitForChild("FusionPackage", 10)
	if not fusionPackage then
		error("FusionPackage not found")
	end
	local actionsModule = fusionPackage:FindFirstChild("Actions") or fusionPackage:WaitForChild("Actions", 10)
	if not actionsModule then
		error("Actions not found")
	end

	local UnitUtils = require(unitUtilsModule)
	local Actions = require(actionsModule)

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
		runtime.Running = true
		if typeof(runtime.Cleanup) == "function" then
			pcall(function()
				runtime:Cleanup()
			end)
		end
		restoreHooks(runtime)

		local thread = task.spawn(function()
			local ok, err = pcall(applyHooks, runtime)
			if not runtime.Running then
				restoreHooks(runtime)
				return
			end
			if hub and typeof(hub.IsCurrent) == "function" and not hub:IsCurrent() then
				restoreHooks(runtime)
				return
			end
			if ok then
				Library.Notify(hub.Window, "Place Anywhere", "Enabled")
			else
				warn("[AEHub:PlaceAnywhere] " .. tostring(err))
				Library.Notify(hub.Window, "Place Anywhere", "Failed — check console")
			end
		end)
		runtime.BootThread = thread
		if typeof(runtime.TrackThread) == "function" then
			runtime:TrackThread(thread)
		end
	end,

	OnDisable = function(_state, runtime, hub)
		runtime.Running = false
		if typeof(runtime.Cleanup) == "function" then
			pcall(function()
				runtime:Cleanup()
			end)
		end
		restoreHooks(runtime)
		Library.Notify(hub.Window, "Place Anywhere", "Disabled")
	end,

	OnDestroy = function(_state, runtime)
		runtime.Running = false
		if typeof(runtime.Cleanup) == "function" then
			pcall(function()
				runtime:Cleanup()
			end)
		end
		restoreHooks(runtime)
	end,

	BuildUi = function(state, _window, tabs, hub)
		local tab = tabs.Misc
		local section = tab:Section({ Side = "Right" })
		section:Header({ Text = "Place Anywhere" })
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
