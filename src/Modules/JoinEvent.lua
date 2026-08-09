return function(Import)
	local Catalog = Import("JoinCatalog")
	local AutomationCatalog = Import("AutomationCatalog")
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

	function Event:_Refresh(ctx, state)
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

	local function eventQueue(ctx, state)
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
		Version = 1,
		Priority = 5,
		Dependencies = {},

		Init = function(self, ctx)
			local information = ctx.Game:Information() or {}
			local maps = Catalog.MapKeys(information, "VillainInvasion")
			local state = {
				Alive = true,
				Enabled = false,
				Matchmaking = false,
				Delay = 1,
				Relics = 0,
				Draining = false,
				Map = maps[1],
			}
			state.Acts = Catalog.Acts(information, "VillainInvasion", state.Map)
			state.Act = state.Acts[1]
			for _, act in ipairs(state.Acts) do
				if act ~= "Crow" then
					state.Act = act
					break
				end
			end
			local section = ctx.Tabs.Join:Section({ Side = "Right" })
			section:Header({ Text = "Event" })
			state.ActControl = ctx.Registry:Dropdown(section, {
				Name = "Act",
				Search = true,
				Multi = false,
				Required = true,
				Options = #state.Acts > 0 and state.Acts or { "Unavailable" },
				Default = 1,
				Callback = function(value)
					state.Act = tostring(value)
					state.Draining = false
				end,
			}, "join.event.act")
			ctx.Registry:Slider(section, {
				Name = "Farm Crow at Relics (0=off)",
				Default = 0,
				Minimum = 0,
				Maximum = 200,
				Precision = 0,
				Callback = function(value)
					state.Relics = math.floor(value)
					if state.Relics <= 0 then
						state.Draining = false
					end
				end,
			}, "join.event.crow_relics")
			section:Header({ Text = "How it works" })
			section:Label({
				Text = "Farms the selected act until the relic target is reached, runs Crow until relics reach 0, then returns to the selected act. No lobby return is needed.",
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
				if not state.Enabled or not state.Map or not state.Act then
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
					Event:_Refresh(ctx, state)
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
