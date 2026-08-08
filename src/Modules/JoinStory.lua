return function(Import)
	local Catalog = Import("JoinCatalog")
	local Story = {}

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

	function Story:_Refresh(ctx, state)
		if state.Refreshing then
			return
		end
		state.Refreshing = true
		local information = ctx.Game:Information() or {}
		state.Maps = Catalog.MapOptions(information, "Story")
		if not state.Maps.ByKey[state.Map] then
			state.Map = Catalog.MapKeys(information, "Story")[1]
		end
		replace(state, "MapSignature", state.MapControl, state.Maps.Options, state.Map and state.Maps.ByKey[state.Map])

		state.Stages = Catalog.Stages(information, state.Map)
		if not table.find(state.Stages, state.Stage) then
			state.Stage = state.Stages[1]
		end
		replace(state, "StageSignature", state.StageControl, state.Stages, state.Stage)

		local gamemode = state.Stage == "Infinite" and "Infinite" or state.Stage == "Mastery" and "Mastery" or "Story"
		state.Difficulties = Catalog.Difficulties(information, gamemode, state.Map)
		if not table.find(state.Difficulties, state.Difficulty) then
			state.Difficulty = state.Difficulties[1]
		end
		replace(state, "DifficultySignature", state.DifficultyControl, state.Difficulties, state.Difficulty)
		state.Refreshing = false
	end

	return {
		Name = "JoinStory",
		Version = 1,
		Priority = 3,
		Dependencies = {},

		Init = function(self, ctx)
			local information = ctx.Game:Information() or {}
			local maps = Catalog.MapOptions(information, "Story")
			local state = {
				Alive = true,
				Enabled = false,
				Matchmaking = false,
				Delay = 1,
				Maps = maps,
				Map = Catalog.MapKeys(information, "Story")[1],
			}
			state.Stages = Catalog.Stages(information, state.Map)
			state.Stage = state.Stages[1]
			state.Difficulties = Catalog.Difficulties(information, "Story", state.Map)
			state.Difficulty = state.Difficulties[1]

			local section = ctx.Tabs.Join:Section({ Side = "Left" })
			section:Header({ Text = "Story" })
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
					Story:_Refresh(ctx, state)
				end,
			}, "join.story.map")
			state.StageControl = ctx.Registry:Dropdown(section, {
				Name = "Stage",
				Search = true,
				Multi = false,
				Required = true,
				Options = #state.Stages > 0 and state.Stages or { "Unavailable" },
				Default = 1,
				Callback = function(value)
					state.Stage = tostring(value)
					Story:_Refresh(ctx, state)
				end,
			}, "join.story.stage")
			state.DifficultyControl = ctx.Registry:Dropdown(section, {
				Name = "Difficulty",
				Search = true,
				Multi = false,
				Required = true,
				Options = #state.Difficulties > 0 and state.Difficulties or { "Unavailable" },
				Default = 1,
				Callback = function(value)
					state.Difficulty = tostring(value)
				end,
			}, "join.story.difficulty")
			section:Divider()
			section:Header({ Text = "Automation" })
			ctx.Registry:Toggle(section, {
				Name = "Auto Join",
				Default = false,
				Callback = function(value)
					state.Enabled = value == true
				end,
			}, "join.story.enabled")
			ctx.Registry:Toggle(section, {
				Name = "Use Matchmaking",
				Default = false,
				Callback = function(value)
					state.Matchmaking = value == true
				end,
			}, "join.story.matchmaking")
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
			}, "join.story.delay")

			ctx:RegisterCleanup(ctx.Join:Register("Story", 100, function()
				if not state.Enabled or not state.Map or not state.Stage or not state.Difficulty then
					return nil
				end
				local info = ctx.Game:Information() or {}
				local queue = Catalog.StoryQueue(info, state.Map, state.Stage, state.Difficulty)
				local playerData = ctx.Game:PlayerData()
				if not Catalog.QueueUnlocked(info, playerData, queue) then
					return nil
				end
				return { Queue = queue, Matchmaking = state.Matchmaking, Delay = state.Delay }
			end))
			local worker = task.spawn(function()
				while state.Alive and ctx.Runtime.Alive do
					Story:_Refresh(ctx, state)
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
