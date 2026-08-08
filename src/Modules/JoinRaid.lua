return function(Import)
	local Catalog = Import("JoinCatalog")
	local Raid = {}

	local function replace(state, key, control, options, selected)
		if not control then return end
		local signature = table.concat(options, "\0") .. "\1" .. tostring(selected or "")
		if state[key] == signature then return end
		state[key] = signature
		control:ClearOptions()
		control:InsertOptions(#options > 0 and options or {"Unavailable"})
		if selected then control:UpdateSelection(selected) end
	end

	function Raid:_Refresh(ctx, state)
		if state.Refreshing then return end
		state.Refreshing = true
		local information = ctx.Game:Information() or {}
		state.Maps = Catalog.MapOptions(information, "Raid")
		if not state.Maps.ByKey[state.Map] then state.Map = Catalog.MapKeys(information, "Raid")[1] end
		replace(state, "MapSignature", state.MapControl, state.Maps.Options, state.Map and state.Maps.ByKey[state.Map])
		state.Acts = Catalog.Acts(information, "Raid", state.Map)
		if not table.find(state.Acts, state.Act) then state.Act = state.Acts[1] end
		replace(state, "ActSignature", state.ActControl, state.Acts, state.Act)
		state.Difficulties = Catalog.Difficulties(information, "Raid", state.Map)
		if not table.find(state.Difficulties, state.Difficulty) then state.Difficulty = state.Difficulties[1] end
		replace(state, "DifficultySignature", state.DifficultyControl, state.Difficulties, state.Difficulty)
		state.Refreshing = false
	end

	return {
		Name = "JoinRaid",
		Version = 1,
		Priority = 6,
		Dependencies = {},

		Init = function(self, ctx)
			local information = ctx.Game:Information() or {}
			local maps = Catalog.MapOptions(information, "Raid")
			local state = {Alive = true, Enabled = false, Matchmaking = false, Delay = 1, Maps = maps, Map = Catalog.MapKeys(information, "Raid")[1]}
			state.Acts = Catalog.Acts(information, "Raid", state.Map)
			state.Act = state.Acts[1]
			state.Difficulties = Catalog.Difficulties(information, "Raid", state.Map)
			state.Difficulty = state.Difficulties[1]
			local section = ctx.Tabs.Join:Section({Side = "Right"})
			section:Header({Text = "Raid"})
			section:Header({Text = "Map"})
			state.MapControl = ctx.Registry:Dropdown(section, {
				Name = state.Map and maps.ByKey[state.Map] or "No raid maps", Search = true, Multi = false, Required = true,
				Options = #maps.Options > 0 and maps.Options or {"Unavailable"}, Default = 1,
				ResolveValue = function(value) return state.Maps.ByKey[tostring(value)] or value end,
				Callback = function(value) state.Map = state.Maps.ByLabel[value] or string.match(tostring(value), "%[([^%]]+)%]$") or tostring(value) Raid:_Refresh(ctx, state) end,
			}, "join.raid.map")
			section:Header({Text = "Act"})
			state.ActControl = ctx.Registry:Dropdown(section, {Name = state.Act or "No acts", Search = true, Multi = false, Required = true, Options = #state.Acts > 0 and state.Acts or {"Unavailable"}, Default = 1, Callback = function(value) state.Act = tostring(value) end}, "join.raid.act")
			section:Header({Text = "Difficulty"})
			state.DifficultyControl = ctx.Registry:Dropdown(section, {Name = state.Difficulty or "No difficulties", Search = true, Multi = false, Required = true, Options = #state.Difficulties > 0 and state.Difficulties or {"Unavailable"}, Default = 1, Callback = function(value) state.Difficulty = tostring(value) end}, "join.raid.difficulty")
			ctx.Registry:Toggle(section, {Name = "Auto Join", Default = false, Callback = function(value) state.Enabled = value == true end}, "join.raid.enabled")
			ctx.Registry:Toggle(section, {Name = "Use Matchmaking", Default = false, Callback = function(value) state.Matchmaking = value == true end}, "join.raid.matchmaking")
			ctx.Registry:Slider(section, {Name = "Auto Join Delay (s)", Default = 1, Minimum = 0, Maximum = 30, Precision = 1, Callback = function(value) state.Delay = value end}, "join.raid.delay")
			ctx:RegisterCleanup(ctx.Join:Register("Raid", 200, function()
				if not state.Enabled or not state.Map or not state.Act or not state.Difficulty then return nil end
				local queue = {Gamemode = "Raid", MapName = state.Map, ActName = state.Act, Difficulty = state.Difficulty}
				if not Catalog.QueueUnlocked(ctx.Game:Information() or {}, ctx.Game:PlayerData(), queue) then return nil end
				return {Queue = queue, Matchmaking = state.Matchmaking, Delay = state.Delay}
			end))
			local worker = task.spawn(function() while state.Alive and ctx.Runtime.Alive do Raid:_Refresh(ctx, state) task.wait(2) end end)
			ctx:RegisterCleanup(worker)
			ctx:RegisterCleanup(function() state.Alive = false end)
			return state
		end,

		Disable = function(self, ctx, state) state.Alive = false state.Enabled = false end,
	}
end
