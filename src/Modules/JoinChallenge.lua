return function(Import)
	local Catalog = Import("JoinCatalog")
	local Challenge = {}

	local function selectedTypes(value)
		local output = {}
		for key, selected in pairs(type(value) == "table" and value or {}) do
			if type(key) == "number" then
				output[tostring(selected)] = true
			elseif selected == true then
				output[tostring(key)] = true
			end
		end
		return output
	end

	local function selectedList(value)
		local output = {}
		for key, selected in pairs(type(value) == "table" and value or {}) do
			if type(key) == "number" then
				table.insert(output, tostring(selected))
			elseif selected == true then
				table.insert(output, tostring(key))
			end
		end
		table.sort(output)
		return output
	end

	local function selectedIndexes(value)
		local output = {}
		for key, selected in pairs(type(value) == "table" and value or {}) do
			local raw = type(key) == "number" and selected or selected == true and key or nil
			local index = tonumber(raw)
			if index and index >= 1 then output[tostring(math.floor(index))] = true end
		end
		return output
	end

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

	function Challenge:_Refresh(ctx, state)
		if state.Refreshing then
			return
		end
		state.Refreshing = true
		local information = ctx.Game:Information() or {}
		state.Types = Catalog.ChallengeTypes(information)
		local valid = {}
		for _, value in ipairs(state.Types) do
			valid[value] = true
		end
		for value in pairs(state.SelectedTypes) do
			if not valid[value] then
				state.SelectedTypes[value] = nil
			end
		end
		if not next(state.SelectedTypes) and state.Types[1] then
			state.SelectedTypes[state.Types[1]] = true
		end
		replace(state, "TypeSignature", state.TypeControl, state.Types, selectedList(state.SelectedTypes))

		local amount = 0
		for value in pairs(state.SelectedTypes) do
			amount = math.max(amount, Catalog.ChallengeAmount(information, value))
		end
		state.IndexOptions = {}
		for index = 1, amount do
			table.insert(state.IndexOptions, tostring(index))
		end
		local validIndexes = {}
		for _, index in ipairs(state.IndexOptions) do validIndexes[index] = true end
		for index in pairs(state.SelectedIndexes) do
			if not validIndexes[index] then state.SelectedIndexes[index] = nil end
		end
		replace(state, "IndexSignature", state.IndexControl, state.IndexOptions, selectedList(state.SelectedIndexes))

		local challengeData = ctx.Game:State("ChallengeData")
		state.Drops = Catalog.ChallengeDrops(information, challengeData)
		for asset in pairs(state.SelectedDrops) do
			if not state.Drops.ByKey[asset] then
				state.SelectedDrops[asset] = nil
			end
		end
		local selectedDropLabels = {}
		for asset in pairs(state.SelectedDrops) do
			if state.Drops.ByKey[asset] then
				table.insert(selectedDropLabels, state.Drops.ByKey[asset])
			end
		end
		table.sort(selectedDropLabels)
		local dropOptions = {}
		for _, option in ipairs(state.Drops.Options) do
			if option ~= "Any drop" then
				table.insert(dropOptions, option)
			end
		end
		replace(state, "DropSignature", state.DropControl, dropOptions, selectedDropLabels)
		state.Refreshing = false
	end

	local function candidate(ctx, state)
		local information = ctx.Game:Information() or {}
		local playerData = ctx.Game:PlayerData()
		local challengeData = ctx.Game:State("ChallengeData")
		if type(playerData) ~= "table" or type(challengeData) ~= "table" then
			return nil
		end
		for _, challengeType in ipairs(state.Types) do
			if state.SelectedTypes[challengeType] then
				local amount = Catalog.ChallengeAmount(information, challengeType)
				for index = 1, amount do
					if
						(challengeType ~= "Regular" or not next(state.SelectedIndexes)
							or state.SelectedIndexes[tostring(index)] == true)
						and Catalog.ChallengeAvailable(information, playerData, challengeType, index)
						and Catalog.ChallengeHasSelectedDrop(information, challengeType, index, state.SelectedDrops)
					then
						local queue = Catalog.ChallengeQueue(challengeData, challengeType, index)
						if queue and queue.MapName and queue.ActName and queue.Difficulty then
							return queue
						end
					end
				end
			end
		end
		return nil
	end

	return {
		Name = "JoinChallenge",
		Version = 2,
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
				SelectedTypes = types[1] and { [types[1]] = true } or {},
				SelectedIndexes = {},
				SelectedDrops = {},
				LastLobbyKey = nil,
				LastLobbyAttemptAt = 0,
			}
			local amount = types[1] and Catalog.ChallengeAmount(information, types[1]) or 0
			state.IndexOptions = {}
			for index = 1, amount do
				table.insert(state.IndexOptions, tostring(index))
			end
			state.Drops = Catalog.ChallengeDrops(information, ctx.Game:State("ChallengeData"))

			local section = ctx.Tabs.Join:Section({ Side = "Left" })
			section:Header({ Text = "Challenge" })
			state.TypeControl = ctx.Registry:Dropdown(section, {
				Name = "Challenge Type",
				Search = true,
				Multi = true,
				Required = true,
				Options = #types > 0 and types or { "Unavailable" },
				Default = types[1] and { types[1] } or {},
				Callback = function(value)
					state.SelectedTypes = selectedTypes(value)
					Challenge:_Refresh(ctx, state)
				end,
			}, "join.challenge.types")
			state.IndexControl = ctx.Registry:Dropdown(section, {
				Name = "Regular Challenge # (blank = all)",
				Search = true,
				Multi = true,
				Required = false,
				Options = #state.IndexOptions > 0 and state.IndexOptions or { "Unavailable" },
				Default = {},
				Callback = function(value)
					state.SelectedIndexes = selectedIndexes(value)
				end,
			}, "join.challenge.index")
			state.DropControl = ctx.Registry:Dropdown(section, {
				Name = "Only Join If It Drops",
				Search = true,
				Multi = true,
				Required = false,
				Options = (function()
					local output = {}
					for _, option in ipairs(state.Drops.Options) do
						if option ~= "Any drop" then
							table.insert(output, option)
						end
					end
					return output
				end)(),
				Default = {},
				ResolveValue = function(value)
					return state.Drops.ByKey[tostring(value)] or value
				end,
				Callback = function(value)
					state.SelectedDrops = {}
					for label, selected in pairs(type(value) == "table" and value or {}) do
						if selected == true then
							local asset = state.Drops.ByLabel[label] or string.match(tostring(label), "%[([^%]]+)%]$")
							if asset then
								state.SelectedDrops[asset] = true
							end
						end
					end
				end,
			}, "join.challenge.drop")
			section:Divider()
			section:Header({ Text = "Automation" })
			ctx.Registry:Toggle(section, {
				Name = "Back to Lobby on Refresh",
				Default = false,
				Callback = function(value)
					state.BackToLobby = value == true
				end,
			}, "join.challenge.back_to_lobby")
			ctx.Registry:Toggle(section, {
				Name = "Auto Join",
				Default = false,
				Callback = function(value)
					state.Enabled = value == true
					if not value then
						state.LastLobbyKey = nil
					end
				end,
			}, "join.challenge.enabled")
			ctx.Registry:Toggle(section, {
				Name = "Use Matchmaking",
				Default = false,
				Callback = function(value)
					state.Matchmaking = value == true
				end,
			}, "join.challenge.matchmaking")
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
			}, "join.challenge.delay")
			Challenge:_Refresh(ctx, state)
			ctx:RegisterCleanup(ctx.Join:Register("Challenge", 400, function()
				if not state.Enabled then
					return nil
				end
				local queue = candidate(ctx, state)
				if not queue then
					return nil
				end
				return { Queue = queue, Matchmaking = state.Matchmaking, Delay = state.Delay }
			end))
			local worker = task.spawn(function()
				while state.Alive and ctx.Runtime.Alive do
					Challenge:_Refresh(ctx, state)
					if state.Enabled and state.BackToLobby then
						local queue = candidate(ctx, state)
						if not queue then
							state.LastLobbyKey = nil
						elseif ctx.Game:IsInGame() then
							local key = table.concat({ queue.ChallengeType or "", queue.ChallengeIndex or "" }, "|")
							if state.LastLobbyKey ~= key and os.clock() - state.LastLobbyAttemptAt >= 5 then
								state.LastLobbyAttemptAt = os.clock()
								local ok, err = ctx.Game:ReturnToLobby()
								if ok then
									state.LastLobbyKey = key
									ctx.Runtime:Notify("Challenge", "A selected challenge refreshed; returning to the lobby.")
								else
									ctx.Runtime:Notify("Challenge", "Return to lobby failed: " .. tostring(err))
								end
							end
						end
					end
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
