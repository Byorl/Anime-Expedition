return function(Import)
	local Catalog = Import("JoinCatalog")
	local AutomationCatalog = Import("AutomationCatalog")
	local Util = Import("Util")
	local Event = {}

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

	-- Limited events are data-driven: every entry under Information.Events
	-- that carries a QueueData table is joinable verbatim (Tidal Siege, Bingo,
	-- creator spotlights, expedition-variant events). Nothing here is
	-- hardcoded per event, so future events appear automatically.
	function Event:_RefreshEvents(ctx, state)
		local information = ctx.Game:Information() or {}
		state.Events = Catalog.Events(information)
		if not state.Events.ByKey[state.SelectedEvent] then
			state.SelectedEvent = state.Events.Entries[1] and state.Events.Entries[1].Key or nil
		end
		replace(
			state,
			"EventSignature",
			state.EventControl,
			state.Events.Options,
			state.SelectedEvent and state.Events.ByKey[state.SelectedEvent]
		)
	end

	function Event:_SelectedEntry(state)
		if not state.Events then return nil end
		for _, entry in ipairs(state.Events.Entries) do
			if entry.Key == state.SelectedEvent then return entry end
		end
		return nil
	end

	local function eventQueue(ctx, state)
		local entry = Event:_SelectedEntry(state)
		local queue = Catalog.EventQueue(entry)
		if not queue then
			return nil
		end
		-- Queue data may omit difficulty for event gamemodes that need it
		-- explicit; fall back to the map's first listed difficulty.
		if not queue.Difficulty and queue.MapName then
			local information = ctx.Game:Information() or {}
			local difficulties = Catalog.Difficulties(information, queue.Gamemode, queue.MapName)
			queue.Difficulty = difficulties[1]
		end
		if queue.Gamemode == "Expedition" and not queue.DifficultyLevel then
			queue.DifficultyLevel = 1
		end
		return queue
	end

	-- Legacy VillainInvasion drain: only offered when the server still
	-- publishes that event; otherwise the section stays hidden.
	local function villainAvailable(ctx)
		local information = ctx.Game:Information() or {}
		for _, entry in ipairs(Catalog.Events(information).Entries) do
			if entry.Key == "VillainInvasion" then
				return true
			end
		end
		-- Older servers may publish VillainInvasion through the maps catalog
		-- only; treat a non-empty map list as available there too.
		return #Catalog.MapKeys(information, "VillainInvasion") > 0
	end

	local Villain = {}

	function Villain:_Refresh(ctx, state)
		if state.Refreshing then
			return
		end
		state.Refreshing = true
		local information = ctx.Game:Information() or {}
		local maps = Catalog.MapKeys(information, "VillainInvasion")
		state.Map = maps[1]
		state.Acts = Catalog.Acts(information, "VillainInvasion", state.Map)
		if not table.find(state.Acts, state.Act) then
			state.Act = state.Acts[1]
			for _, act in ipairs(state.Acts) do
				if act ~= "Crow" then
					state.Act = act
					break
				end
			end
		end
		replace(state, "ActSignature", state.ActControl, state.Acts, state.Act)
		state.Refreshing = false
	end

	function Villain:eventQueue(ctx, state)
		local information = ctx.Game:Information() or {}
		local playerData = ctx.Game:PlayerData()
		local relics = AutomationCatalog.OwnedAmount(playerData, information, "CrowRelic")
		if state.Relics <= 0 then
			state.Draining = false
		elseif state.Draining and relics <= 0 then
			state.Draining = false
		elseif not state.Draining and relics >= state.Relics then
			state.Draining = true
		end
		local act = state.Draining and "Crow" or state.Act
		if not table.find(state.Acts, act) then
			return nil
		end
		local data = Catalog.MapData(information, "VillainInvasion", state.Map)
		local index = table.find(type(data) == "table" and data.ActProgression or {}, act)
		local faction = index and type(data.OrderedFactions) == "table" and data.OrderedFactions[index] or nil
		local difficulties = Catalog.Difficulties(information, "VillainInvasion", state.Map)
		local queue = {
			Gamemode = "VillainInvasion",
			Type = "Event",
			MapName = state.Map,
			ActName = act,
			Difficulty = difficulties[1],
			Factions = faction and { faction } or {},
		}
		if not queue.Difficulty then
			return nil
		end
		if act == "Crow" and relics <= 0 then
			return nil
		end
		return queue
	end

	return {
		Name = "JoinEvent",
		Version = 2,
		Priority = 5,
		Dependencies = {},

		Init = function(self, ctx)
			local information = ctx.Game:Information() or {}
			local section = ctx.Tabs.Join:Section({ Side = "Right" })

			local state = {
				Alive = true,
				Enabled = false,
				Matchmaking = false,
				Delay = 1,
				Events = Catalog.Events(information),
				SelectedEvent = nil,
			}
			state.SelectedEvent = state.Events.Entries[1] and state.Events.Entries[1].Key or nil

			section:Header({ Text = "Event" })
			state.EventControl = ctx.Registry:Dropdown(section, {
				Name = "Event",
				Search = true,
				Multi = false,
				Required = true,
				Options = #state.Events.Options > 0 and state.Events.Options or { "Unavailable" },
				Default = 1,
				ResolveValue = function(value)
					return state.Events.ByKey[tostring(value)] or value
				end,
				Callback = function(value)
					state.SelectedEvent = state.Events.ByLabel[value]
						or string.match(tostring(value), "%[([^%]]+)%]$")
				end,
			}, "join.event.selected")
			section:Label({
				Text = "Queues the event's own data. New events appear here automatically after game updates.",
			})
			section:Divider()
			section:Header({ Text = "Automation" })
			ctx.Registry:Toggle(section, {
				Name = "Auto Join",
				Default = false,
				Callback = function(value)
					state.Enabled = value == true
				end,
			}, "join.event.enabled")
			ctx.Registry:Toggle(section, {
				Name = "Use Matchmaking",
				Default = false,
				Callback = function(value)
					state.Matchmaking = value == true
				end,
			}, "join.event.matchmaking")
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
			}, "join.event.delay")
			ctx:RegisterCleanup(ctx.Join:Register("Event", 300, function()
				if not state.Enabled or not state.SelectedEvent then
					return nil
				end
				local queue = eventQueue(ctx, state)
				if not queue then
					return nil
				end
				return { Queue = queue, Matchmaking = state.Matchmaking, Delay = state.Delay }
			end))
			local worker = task.spawn(function()
				while state.Alive and ctx.Runtime.Alive do
					Util.SafeCall("event list refresh", Event._RefreshEvents, Event, ctx, state)
					task.wait(3)
				end
			end)
			ctx:RegisterCleanup(worker)

			-- Legacy VillainInvasion relic drain (hidden unless the event exists).
			if villainAvailable(ctx) then
				local villainState = {
					Alive = true,
					Enabled = false,
					Delay = 1,
					Relics = 0,
					Draining = false,
					Map = Catalog.MapKeys(information, "VillainInvasion")[1],
				}
				villainState.Acts = Catalog.Acts(information, "VillainInvasion", villainState.Map)
				villainState.Act = villainState.Acts[1]
				for _, act in ipairs(villainState.Acts) do
					if act ~= "Crow" then
						villainState.Act = act
						break
					end
				end
				local villainSection = ctx.Tabs.Join:Section({ Side = "Right" })
				villainSection:Header({ Text = "Villain Invasion" })
				villainState.ActControl = ctx.Registry:Dropdown(villainSection, {
					Name = "Act",
					Search = true,
					Multi = false,
					Required = true,
					Options = #villainState.Acts > 0 and villainState.Acts or { "Unavailable" },
					Default = 1,
					Callback = function(value)
						villainState.Act = tostring(value)
						villainState.Draining = false
					end,
				}, "join.villain.act")
				ctx.Registry:Slider(villainSection, {
					Name = "Farm Crow at Relics (0=off)",
					Default = 0,
					Minimum = 0,
					Maximum = 200,
					Precision = 0,
					Callback = function(value)
						villainState.Relics = math.floor(value)
						if villainState.Relics <= 0 then
							villainState.Draining = false
						end
					end,
				}, "join.villain.crow_relics")
				villainSection:Label({
					Text = "Farms the selected act until the relic target is reached, runs Crow until relics reach 0, then returns to the selected act.",
				})
				ctx.Registry:Toggle(villainSection, {
					Name = "Auto Join",
					Default = false,
					Callback = function(value)
						villainState.Enabled = value == true
					end,
				}, "join.villain.enabled")
				ctx.Registry:Slider(villainSection, {
					Name = "Auto Join Delay (s)",
					Default = 1,
					Minimum = 1,
					Maximum = 10,
					Precision = 0,
					Step = 1,
					Callback = function(value)
						villainState.Delay = value
					end,
				}, "join.villain.delay")
				ctx:RegisterCleanup(ctx.Join:Register("VillainInvasion", 299, function()
					if not villainState.Enabled or not villainState.Map or not villainState.Act then
						return nil
					end
					local queue = Villain:eventQueue(ctx, villainState)
					if not queue then
						return nil
					end
					return { Queue = queue, Matchmaking = false, Delay = villainState.Delay }
				end))
				local villainWorker = task.spawn(function()
					while villainState.Alive and ctx.Runtime.Alive do
						Util.SafeCall("villain refresh", Villain._Refresh, Villain, ctx, villainState)
						task.wait(2)
					end
				end)
				ctx:RegisterCleanup(villainWorker)
				ctx:RegisterCleanup(function()
					villainState.Alive = false
				end)
			end

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
