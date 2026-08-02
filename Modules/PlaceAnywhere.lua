local function resolveHub(...)
	local viaVarargs = ...
	if typeof(viaVarargs) == "table" and viaVarargs.Core ~= nil then
		return viaVarargs
	end
	local env = (getgenv and getgenv()) or shared or _G
	return env.__AEHubLoading
end

local Hub = resolveHub(...)
assert(Hub and Hub.Core and Hub.Core.Library, "[Anime Expeditions] Hub context missing while loading PlaceAnywhere")
local Library = Hub.Core.Library

local MODULE_ID = "PlaceAnywhere"
local env = Library.GetEnv()

local function getHookBag()
	local bag = env.__AE_PlaceAnywhereHooks
	if typeof(bag) ~= "table" then
		bag = {
			Active = false,
			UnitUtils = nil,
			Actions = nil,
			OriginalUnitUtils = nil,
			OriginalActions = nil,
			UsedHookFunction = false,
			Watchdog = nil,
		}
		env.__AE_PlaceAnywhereHooks = bag
	end
	return bag
end

local function alwaysAllow()
	return true
end

local function stopWatchdog(bag)
	if bag.Watchdog then
		pcall(task.cancel, bag.Watchdog)
		bag.Watchdog = nil
	end
end

local function restoreHooks()
	local bag = getHookBag()
	stopWatchdog(bag)

	if bag.UnitUtils and bag.OriginalUnitUtils ~= nil then
		if bag.UsedHookFunction and typeof(hookfunction) == "function" then
			pcall(function()
				hookfunction(bag.UnitUtils.IsPlacementAllowed, bag.OriginalUnitUtils)
			end)
		end
		pcall(function()
			bag.UnitUtils.IsPlacementAllowed = bag.OriginalUnitUtils
		end)
	end

	if bag.Actions and bag.OriginalActions ~= nil then
		pcall(function()
			rawset(bag.Actions, "IsPlacementAllowed", bag.OriginalActions)
		end)
	elseif bag.Actions then
		-- Remove our override so Actions falls back to requiring the real module again
		pcall(function()
			rawset(bag.Actions, "IsPlacementAllowed", nil)
		end)
	end

	bag.Active = false
	bag.UnitUtils = nil
	bag.Actions = nil
	bag.OriginalUnitUtils = nil
	bag.OriginalActions = nil
	bag.UsedHookFunction = false
	env.__AE_PlaceAnywhereHooks = bag
end

local function assertHooks(bag)
	if not bag.Active or not bag.UnitUtils then
		return
	end

	-- Keep UnitUtils forced on
	if bag.UnitUtils.IsPlacementAllowed ~= alwaysAllow then
		if typeof(hookfunction) == "function" then
			pcall(function()
				hookfunction(bag.UnitUtils.IsPlacementAllowed, alwaysAllow)
			end)
		end
		bag.UnitUtils.IsPlacementAllowed = alwaysAllow
	end

	-- Keep Actions table override (metatable caches the real fn via rawset on first use)
	local current = rawget(bag.Actions, "IsPlacementAllowed")
	if current ~= alwaysAllow then
		rawset(bag.Actions, "IsPlacementAllowed", alwaysAllow)
	end
end

local function applyHooks()
	restoreHooks()

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local sharedFolder = ReplicatedStorage:WaitForChild("Shared", 10)
	local unitUtilsModule = sharedFolder and sharedFolder:WaitForChild("UnitUtils", 10)
	local fusionPackage = ReplicatedStorage:WaitForChild("FusionPackage", 10)
	local actionsModule = fusionPackage and fusionPackage:WaitForChild("Actions", 10)
	if not unitUtilsModule or not actionsModule then
		error("Missing UnitUtils or Actions")
	end

	local UnitUtils = require(unitUtilsModule)
	local Actions = require(actionsModule)

	-- Force Actions to resolve/cache the real function once, then overwrite it
	pcall(function()
		local _ = Actions.IsPlacementAllowed
	end)

	local bag = getHookBag()
	bag.UnitUtils = UnitUtils
	bag.Actions = Actions
	bag.OriginalUnitUtils = UnitUtils.IsPlacementAllowed
	bag.OriginalActions = rawget(Actions, "IsPlacementAllowed")
	bag.UsedHookFunction = false
	bag.Active = true

	if typeof(hookfunction) == "function" and typeof(bag.OriginalUnitUtils) == "function" then
		local ok = pcall(function()
			bag.OriginalUnitUtils = hookfunction(UnitUtils.IsPlacementAllowed, alwaysAllow)
			bag.UsedHookFunction = true
		end)
		if not ok then
			UnitUtils.IsPlacementAllowed = alwaysAllow
			bag.UsedHookFunction = false
		end
	else
		UnitUtils.IsPlacementAllowed = alwaysAllow
	end

	rawset(Actions, "IsPlacementAllowed", alwaysAllow)

	-- Re-assert while enabled (other scripts / game code can overwrite)
	bag.Watchdog = task.spawn(function()
		while bag.Active do
			assertHooks(bag)
			task.wait(0.25)
		end
	end)

	env.__AE_PlaceAnywhereHooks = bag
end

return {
	Id = MODULE_ID,
	Name = "Place Anywhere",
	Defaults = {
		Enabled = false,
	},

	OnEnable = function(_state, runtime, hub)
		runtime.Running = true
		stopWatchdog(getHookBag())

		local ok, err = pcall(applyHooks)
		if not ok then
			restoreHooks()
			runtime.Running = false
			warn("[Anime Expeditions:PlaceAnywhere] " .. tostring(err))
			Library.Notify(hub.Window, "Place Anywhere", "Failed")
			return
		end

		if not runtime.Running or (hub and hub.IsCurrent and not hub:IsCurrent()) then
			restoreHooks()
			return
		end

		Library.Notify(hub.Window, "Place Anywhere", "Enabled")
	end,

	OnDisable = function(_state, runtime, hub)
		runtime.Running = false
		restoreHooks()
		Library.Notify(hub.Window, "Place Anywhere", "Disabled")
	end,

	OnDestroy = function(_state, runtime)
		runtime.Running = false
		restoreHooks()
	end,

	BuildUi = function(state, _window, tabs, hub)
		local tab = tabs.Misc
		local section = tab:Section({ Side = "Right" })
		section:Header({ Text = "Place Anywhere" })

		hub.UI:BindToggle(section, {
			Name = "Place Anywhere",
			Default = state.Enabled == true,
			Flag = MODULE_ID .. ".Enabled",
		})
	end,
}
