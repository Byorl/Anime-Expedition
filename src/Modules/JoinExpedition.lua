return function(Import)
	local Catalog = Import("JoinCatalog")
	local Expedition = {}

	local function replace(state, key, control, options, selected)
		if not control then
			return
		end
		local signature = table.concat(options, "\0")
		if state[key] == signature then
			return
		end
		state[key] = signature
		control:ClearOptions()
		control:InsertOptions(#options > 0 and options or { "Unavailable" })
		if selected then
			control:UpdateSelection(selected)
		end
	end

	function Expedition:_Refresh(ctx, state)
		if state.Refreshing then
			return
		end
		state.Refreshing = true
		local information = ctx.Game:Information() or {}
		state.Maps = Catalog.MapOptions(information, "Expedition")
		if not state.Maps.ByKey[state.Map] then
			state.Map = Catalog.MapKeys(information, "Expedition")[1]
		end
		replace(state, "MapSignature", state.MapControl, state.Maps.Options, state.Map and state.Maps.ByKey[state.Map])

		local levelCount = Catalog.ExpeditionLevels(information, state.Map)
		state.Levels = {}
		for level = 1, levelCount do
			table.insert(state.Levels, tostring(level))
		end
		if not table.find(state.Levels, state.Level) then
			state.Level = state.Levels[1]
		end
		replace(state, "LevelSignature", state.LevelControl, state.Levels, state.Level)
		state.Refreshing = false
	end

	return {
		Name = "JoinExpedition",
		Version = 1,
		Priority = 4,
		Dependencies = {},

		Init = function(self, ctx)
			local information = ctx.Game:Information() or {}
			local maps = Catalog.MapOptions(information, "Expedition")
			local state = {
				Alive = true,
				Enabled = false,
				Matchmaking = false,
				Delay = 1,
				Maps = maps,
				Map = Catalog.MapKeys(information, "Expedition")[1],
				Level = "1",
			}

			local section = ctx.Tabs.Join:Section({ Side = "Left" })
			section:Header({ Text = "Expedition" })
			state.MapControl = ctx.Registry:Dropdown(section, {
				Name = "Map",
				Search = true,
				Multi = false,
				Required = true,
				Options = #maps.Options > 0 and maps.Options or { "Unavailable" },
				Default = 1,
				ResolveValue = function(value)
					return state.Maps.ByKey[tostring(value)] or value
				end,
				Callback = function(value)
					state.Map = state.Maps.ByLabel[value]
						or string.match(tostring(value), "%[([^%]]+)%]$")
						or tostring(value)
					Expedition:_Refresh(ctx, state)
				end,
			}, "join.expedition.map")
			state.LevelControl = ctx.Registry:Dropdown(section, {
				Name = "Difficulty Level",
				Search = false,
				Multi = false,
				Required = true,
				Options = { "1", "2", "3" },
				Default = 1,
				Callback = function(value)
					state.Level = tostring(value)
				end,
			}, "join.expedition.level")
			section:Label({
				Text = "Difficulty levels are numeric per map (1-3). The named tier shown in game is queued alongside the level.",
			})
			section:Divider()
			section:Header({ Text = "Automation" })
			ctx.Registry:Toggle(section, {
				Name = "Auto Join",
				Default = false,
				Callback = function(value)
					state.Enabled = value == true
				end,
			}, "join.expedition.enabled")
			ctx.Registry:Toggle(section, {
				Name = "Use Matchmaking",
				Default = false,
				Callback = function(value)
					state.Matchmaking = value == true
				end,
			}, "join.expedition.matchmaking")
			ctx.Registry:Slider(section, {
				Name = "Auto Join Delay (s)",
				Default = 1,
				Minimum = 1,
				Maximum = 10,
				Precision = 0,
				Step = 1,
				Callback = function(value)
					state.Delay = value
				end,
			}, "join.expedition.delay")

			ctx:RegisterCleanup(ctx.Join:Register("Expedition", 298, function()
				if not state.Enabled or not state.Map or not state.Level then
					return nil
				end
				local info = ctx.Game:Information() or {}
				local queue = Catalog.ExpeditionQueue(info, state.Map, tonumber(state.Level))
				if not queue then
					return nil
				end
				return { Queue = queue, Matchmaking = state.Matchmaking, Delay = state.Delay }
			end))
			local worker = task.spawn(function()
				while state.Alive and ctx.Runtime.Alive do
					Expedition:_Refresh(ctx, state)
					task.wait(2)
				end
			end)
			ctx:RegisterCleanup(worker)
			ctx:RegisterCleanup(function()
				state.Alive = false
			end)
			return state
		end,

		Disable = function(self, ctx, state)
			state.Alive = false
			state.Enabled = false
		end,
	}
end
