return function(Import)
	local Util = Import("Util")
	local Catalog = Import("AutomationCatalog")
	local AutoTrait = {}

	local function unitById(playerData, wanted)
		for id, unit in pairs(type(playerData) == "table" and type(playerData.UnitData) == "table" and playerData.UnitData or {}) do
			if tostring(id) == tostring(wanted) then return unit end
		end
		return nil
	end

	function AutoTrait:_Status(state, message)
		state.Status = tostring(message or "Idle.")
		if state.StatusLabel then
			Util.SafeCall("auto trait status", state.StatusLabel.UpdateName, state.StatusLabel, state.Status)
		end
	end

	function AutoTrait:_Stop(state, message)
		state.Enabled = false
		state.SuppressIdleOnce = true
		self:_Status(state, message)
		if state.Toggle then task.defer(function() state.Toggle:UpdateState(false) end) end
	end

	function AutoTrait:_RefreshUnits(ctx, state, preserveId)
		state.Units = Catalog.Units(ctx.Game:PlayerData(), ctx.Game:Information() or {})
		local options = #state.Units.Options > 0 and state.Units.Options or {"No units available"}
		if state.UnitDropdown then
			state.UnitDropdown:ClearOptions()
			state.UnitDropdown:InsertOptions(options)
		end
		local wanted = tostring(preserveId or state.SelectedUnitId or "")
		if not state.Units.ByKey[wanted] then wanted = state.Units.Entries[1] and state.Units.Entries[1].Key or nil end
		state.SelectedUnitId = wanted
		if state.UnitDropdown and wanted then state.UnitDropdown:UpdateSelection(state.Units.ByKey[wanted]) end
		if not wanted then self:_Status(state, "No units are available.") end
		return wanted
	end

	local function selectedTraitKeys(selection, catalog)
		local output = {}
		for key, value in pairs(type(selection) == "table" and selection or {}) do
			local label
			if type(key) == "number" then label = value elseif value == true then label = key end
			if label ~= nil then
				local trait = catalog.ByLabel[label] or Catalog.ExtractBracketKey(label)
				if trait then output[tostring(trait)] = true end
			end
		end
		return output
	end

	function AutoTrait:_RerollOnce(ctx, state, generation)
		local information = ctx.Game:Information() or {}
		local playerData = ctx.Game:PlayerData()
		if type(playerData) ~= "table" then self:_Status(state, "Waiting for player data...") task.wait(0.5) return end
		local unit = unitById(playerData, state.SelectedUnitId)
		if type(unit) ~= "table" then self:_Stop(state, "Selected unit is no longer available.") return end
		local currentTrait = tostring(unit.Trait or "None")
		if state.StopTraits[currentTrait] then
			self:_Stop(state, "Stopped: unit already has " .. Catalog.TraitName(information, currentTrait) .. ".")
			return
		end

		local traitInfo = type(information.Traits) == "table" and information.Traits or {}
		local rerollItem = tostring(traitInfo.RerollItem or "TraitReroll")
		local price = math.max(1, math.floor(tonumber(traitInfo.ItemsPerRoll) or 1))
		local owned = Catalog.OwnedAmount(playerData, information, rerollItem)
		if owned < price then
			self:_Status(state, string.format("Waiting for %s (%d/%d).", rerollItem, owned, price))
			task.wait(1)
			return
		end

		local beforeRolls = tonumber(unit.TraitRollAmount) or 0
		local beforeTrait = currentTrait
		self:_Status(state, "Rerolling " .. Catalog.UnitName(information, unit) .. "...")
		-- true confirms replacing any game-filtered trait. The module checks its
		-- own stop list immediately before every request, so a selected trait is
		-- never intentionally rolled away.
		local fired, fireError = ctx.Game:Fire("ROLL_UNIT_TRAIT", state.SelectedUnitId, true)
		if not fired then self:_Status(state, "Trait reroll failed: " .. tostring(fireError)) task.wait(1) return end

		local deadline = os.clock() + 3
		repeat
			task.wait(0.04)
			if not state.Alive or state.Generation ~= generation or not state.Enabled then return end
			local latestData = ctx.Game:PlayerData()
			local latest = unitById(latestData, state.SelectedUnitId)
			if type(latest) ~= "table" then self:_Stop(state, "Selected unit is no longer available.") return end
			local rolls = tonumber(latest.TraitRollAmount) or 0
			local trait = tostring(latest.Trait or "None")
			if rolls > beforeRolls or trait ~= beforeTrait then
				local display = Catalog.TraitName(information, trait)
				self:_Status(state, "Rolled " .. display .. ".")
				local now = os.clock()
				if now - (state.LastUnitRefresh or 0) >= 0.5 or state.StopTraits[trait] then
					state.LastUnitRefresh = now
					self:_RefreshUnits(ctx, state, state.SelectedUnitId)
					self:_Status(state, "Rolled " .. display .. ".")
				end
				if state.StopTraits[trait] then self:_Stop(state, "Stopped on " .. display .. ".") end
				return
			end
		until os.clock() >= deadline
		self:_Status(state, "No reroll result received; retrying slowly.")
		task.wait(1)
	end

	function AutoTrait:_Start(ctx, state)
		state.Generation = state.Generation + 1
		local generation = state.Generation
		state.Alive = true
		local worker = task.spawn(function()
			while state.Alive and state.Generation == generation and ctx.Runtime.Alive do
				if state.Enabled then
					local ok, err = xpcall(function() self:_RerollOnce(ctx, state, generation) end, Util.Traceback)
					if not ok then self:_Status(state, "Auto Reroll error: " .. tostring(err)) task.wait(1) end
				else
					task.wait(0.1)
				end
			end
		end)
		if worker then ctx:RegisterCleanup(worker) end
		ctx:RegisterCleanup(function()
			state.Alive = false
			state.Generation = state.Generation + 1
		end)
	end

	return {
		Name = "AutoTraitReroll",
		Version = 1,
		Priority = 13,
		Dependencies = {"Misc"},

		Init = function(self, ctx)
			local information = ctx.Game:Information() or {}
			local state = {
				Alive = false,
				Generation = 0,
				Enabled = false,
				StopTraits = {},
				Status = "Idle.",
				Units = Catalog.Units(ctx.Game:PlayerData(), information),
				Traits = Catalog.Traits(information),
			}
			local section = ctx.Tabs.Misc:Section({Side = "Right"})
			section:Header({Text = "Auto Reroll Trait"})
			section:Header({Text = "Unit"})
			local unitOptions = #state.Units.Options > 0 and state.Units.Options or {"No units available"}
			local first = state.Units.Entries[1]
			state.SelectedUnitId = first and first.Key or nil
			state.UnitDropdown = ctx.Registry:Dropdown(section, {
				Name = "Unit",
				Search = true,
				Multi = false,
				Required = true,
				Options = unitOptions,
				Default = 1,
				ResolveValue = function(value)
					local id = Catalog.ExtractBracketKey(value, "#")
					return state.Units.ByKey[tostring(id)] or value
				end,
				Callback = function(value)
					state.SelectedUnitId = state.Units.ByLabel[value] or Catalog.ExtractBracketKey(value, "#")
				end,
			}, "auto_trait.unit")
			section:Button({Name = "Refresh Units", Callback = function()
				AutoTrait:_RefreshUnits(ctx, state, state.SelectedUnitId)
			end})
			section:Header({Text = "Stop on Traits"})
			local traitOptions = #state.Traits.Options > 0 and state.Traits.Options or {"No traits available"}
			ctx.Registry:Dropdown(section, {
				Name = "Traits to stop on",
				Search = true,
				Multi = true,
				Required = false,
				Options = traitOptions,
				Default = {},
				ResolveValue = function(value)
					local key = state.Traits.ByLabel[value] or Catalog.ExtractBracketKey(value)
					return state.Traits.ByKey[tostring(key)] or value
				end,
				Callback = function(value) state.StopTraits = selectedTraitKeys(value, state.Traits) end,
			}, "auto_trait.stop_traits")
			state.Toggle = ctx.Registry:Toggle(section, {
				Name = "Auto Reroll Trait",
				Default = false,
				Callback = function(value)
					state.Enabled = value == true
					if not value then
						if state.SuppressIdleOnce then state.SuppressIdleOnce = false
						else AutoTrait:_Status(state, "Idle.") end
					end
				end,
			}, "auto_trait.enabled")
			state.StatusLabel = section:Label({Text = "Idle."})
			return state
		end,

		Enable = function(self, ctx, state) AutoTrait:_Start(ctx, state) end,
		Disable = function(self, ctx, state)
			state.Alive = false
			state.Enabled = false
			state.Generation = state.Generation + 1
		end,
	}
end
