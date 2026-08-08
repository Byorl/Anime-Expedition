return function(Import)
	local Catalog = Import("JoinCatalog")
	local Challenge = {}

	local function selectedTypes(value)
		local output = {}
		for key, selected in pairs(type(value) == "table" and value or {}) do
			if type(key) == "number" then output[tostring(selected)] = true
			elseif selected == true then output[tostring(key)] = true end
		end
		return output
	end

	local function selectionText(selected)
		if type(selected) ~= "table" then return tostring(selected or "") end
		local values = {}
		for key, value in pairs(selected) do
			if type(key) == "number" then table.insert(values, tostring(value))
			elseif value == true then table.insert(values, tostring(key)) end
		end
		table.sort(values)
		return table.concat(values, "\0")
	end

	local function replace(state, key, control, options, selected)
		if not control then return end
		local signature = table.concat(options, "\0") .. "\1" .. selectionText(selected)
		if state[key] == signature then return end
		state[key] = signature
		control:ClearOptions()
		control:InsertOptions(#options > 0 and options or {"Unavailable"})
		if selected then control:UpdateSelection(selected) end
	end

	function Challenge:_Refresh(ctx, state)
		if state.Refreshing then return end
		state.Refreshing = true
		local information = ctx.Game:Information() or {}
		state.Types = Catalog.ChallengeTypes(information)
		local valid = {}
		for _, value in ipairs(state.Types) do valid[value] = true end
		for value in pairs(state.SelectedTypes) do if not valid[value] then state.SelectedTypes[value] = nil end end
		if not next(state.SelectedTypes) and state.Types[1] then state.SelectedTypes[state.Types[1]] = true end
		replace(state, "TypeSignature", state.TypeControl, state.Types, state.SelectedTypes)

		local amount = 0
		for value in pairs(state.SelectedTypes) do amount = math.max(amount, Catalog.ChallengeAmount(information, value)) end
		state.IndexOptions = {"All"}
		for index = 1, amount do table.insert(state.IndexOptions, tostring(index)) end
		if state.Index ~= "All" and not table.find(state.IndexOptions, state.Index) then state.Index = "All" end
		replace(state, "IndexSignature", state.IndexControl, state.IndexOptions, state.Index)

		local challengeData = ctx.Game:State("ChallengeData")
		state.Drops = Catalog.ChallengeDrops(information, challengeData)
		if state.Drop and not state.Drops.ByKey[state.Drop] then state.Drop = nil end
		replace(state, "DropSignature", state.DropControl, state.Drops.Options, state.Drop and state.Drops.ByKey[state.Drop] or "Any drop")
		state.Refreshing = false
	end

	local function candidate(ctx, state)
		local information = ctx.Game:Information() or {}
		local playerData = ctx.Game:PlayerData()
		local challengeData = ctx.Game:State("ChallengeData")
		if type(playerData) ~= "table" or type(challengeData) ~= "table" then return nil end
		for _, challengeType in ipairs(state.Types) do
			if state.SelectedTypes[challengeType] then
				local amount = Catalog.ChallengeAmount(information, challengeType)
				for index = 1, amount do
					if (state.Index == "All" or challengeType ~= "Regular" or tonumber(state.Index) == index)
						and Catalog.ChallengeAvailable(information, playerData, challengeType, index)
						and Catalog.ChallengeHasDrop(information, challengeType, index, state.Drop) then
						local queue = Catalog.ChallengeQueue(challengeData, challengeType, index)
						if queue and queue.MapName and queue.ActName and queue.Difficulty then return queue end
					end
				end
			end
		end
		return nil
	end

	return {
		Name = "JoinChallenge",
		Version = 1,
		Priority = 4,
		Dependencies = {},

		Init = function(self, ctx)
			local information = ctx.Game:Information() or {}
			local types = Catalog.ChallengeTypes(information)
			local state = {
				Alive = true,
				Enabled = false,
				Matchmaking = false,
				Delay = 1,
				BackToLobby = false,
				Types = types,
				SelectedTypes = types[1] and {[types[1]] = true} or {},
				Index = "All",
				Drop = nil,
				LastLobbyKey = nil,
			}
			local amount = types[1] and Catalog.ChallengeAmount(information, types[1]) or 0
			state.IndexOptions = {"All"}
			for index = 1, amount do table.insert(state.IndexOptions, tostring(index)) end
			state.Drops = Catalog.ChallengeDrops(information, ctx.Game:State("ChallengeData"))

			local section = ctx.Tabs.Join:Section({Side = "Left"})
			section:Header({Text = "Challenge"})
			section:Header({Text = "Challenge Type"})
			state.TypeControl = ctx.Registry:Dropdown(section, {
				Name = "Regular, Daily, Weekly", Search = true, Multi = true, Required = true,
				Options = #types > 0 and types or {"Unavailable"}, Default = types[1] and {types[1]} or {},
				Callback = function(value) state.SelectedTypes = selectedTypes(value) Challenge:_Refresh(ctx, state) end,
			}, "join.challenge.types")
			section:Header({Text = "Regular Challenge # (blank = all)"})
			state.IndexControl = ctx.Registry:Dropdown(section, {
				Name = "All", Search = true, Multi = false, Required = true,
				Options = state.IndexOptions, Default = 1, Callback = function(value) state.Index = tostring(value or "All") end,
			}, "join.challenge.index")
			section:Header({Text = "Only Join If It Drops"})
			state.DropControl = ctx.Registry:Dropdown(section, {
				Name = "Any drop", Search = true, Multi = false, Required = true,
				Options = state.Drops.Options, Default = 1,
				ResolveValue = function(value) return state.Drops.ByKey[tostring(value)] or value end,
				Callback = function(value) state.Drop = state.Drops.ByLabel[value] or string.match(tostring(value), "%[([^%]]+)%]$") end,
			}, "join.challenge.drop")
			ctx.Registry:Toggle(section, {Name = "Back to Lobby on Refresh", Default = false, Callback = function(value) state.BackToLobby = value == true end}, "join.challenge.back_to_lobby")
			ctx.Registry:Toggle(section, {Name = "Auto Join", Default = false, Callback = function(value) state.Enabled = value == true if not value then state.LastLobbyKey = nil end end}, "join.challenge.enabled")
			ctx.Registry:Toggle(section, {Name = "Use Matchmaking", Default = false, Callback = function(value) state.Matchmaking = value == true end}, "join.challenge.matchmaking")
			ctx.Registry:Slider(section, {Name = "Auto Join Delay (s)", Default = 1, Minimum = 0, Maximum = 30, Precision = 1, Callback = function(value) state.Delay = value end}, "join.challenge.delay")
			ctx:RegisterCleanup(ctx.Join:Register("Challenge", 400, function()
				if not state.Enabled then return nil end
				local queue = candidate(ctx, state)
				if not queue then return nil end
				return {Queue = queue, Matchmaking = state.Matchmaking, Delay = state.Delay}
			end))
			local worker = task.spawn(function()
				while state.Alive and ctx.Runtime.Alive do
					Challenge:_Refresh(ctx, state)
					if state.Enabled and state.BackToLobby and ctx.Game:IsInGame() then
						local queue = candidate(ctx, state)
						if queue then
							local key = table.concat({queue.ChallengeType or "", queue.ChallengeIndex or ""}, "|")
							if state.LastLobbyKey ~= key then
								state.LastLobbyKey = key
								local ok, err = ctx.Game:ReturnToLobby()
								if not ok then ctx.Runtime:Notify("Challenge", "Return to lobby failed: " .. tostring(err)) end
							end
						else state.LastLobbyKey = nil end
					end
					task.wait(2)
				end
			end)
			ctx:RegisterCleanup(worker)
			ctx:RegisterCleanup(function() state.Alive = false end)
			return state
		end,

		Disable = function(self, ctx, state) state.Alive = false state.Enabled = false end,
	}
end
