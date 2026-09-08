return function(Import)
	local Util = Import("Util")
	local CollectionService = game:GetService("CollectionService")
	local AutoFishing = {}

	local SAND_DOLLAR = "SummerCurrency"

	local function number(value, fallback)
		return tonumber(value) or fallback
	end

	local function jitter(seconds)
		local spread = math.max(0.1, seconds * 0.2)
		return math.max(0.2, seconds + (math.random() * 2 - 1) * spread)
	end

	local function webhookUrl(ctx)
		local modules = ctx.Runtime and ctx.Runtime.Modules or nil
		local loaded = type(modules) == "table" and modules.Loaded or nil
		local webhookState = type(loaded) == "table" and loaded["Webhook"] and loaded["Webhook"].Result or nil
		if type(webhookState) == "table" and type(webhookState.Url) == "string" and webhookState.Url ~= "" then
			return webhookState.Url
		end
		return nil
	end

	local function rankPayload(player, rank, rankName)
		return {
			username = "Anime Expedition",
			embeds = {{
				title = "Fishing Rank Up",
				description = ("User: ||%s||\n\nRank %d - %s"):format(tostring(player.Name), rank, tostring(rankName)),
				color = 3447003,
				footer = { text = "discord.gg/V3WcdHpd3J" },
				timestamp = DateTime.now():ToIsoDate(),
			}},
		}
	end

	function AutoFishing:_Status(state, message)
		state.Status = tostring(message or "Idle.")
		if state.StatusLabel then
			Util.SafeCall("auto fishing status", state.StatusLabel.UpdateName, state.StatusLabel, "Status: " .. state.Status)
		end
	end

	function AutoFishing:_StatsLine(ctx, state)
		local playerData = ctx.Game:PlayerData()
		if type(playerData) ~= "table" then
			return "Rank ? | ? catches | ? Sand Dollar"
		end
		local rank = number(playerData.Rank, 1)
		local information = ctx.Game:Information() or {}
		local ranks = type(information.FishingRodInfo) == "table" and information.FishingRodInfo.FishingRanks or nil
		local rankName = "Beginner"
		if type(ranks) == "table" and type(ranks.Ranks) == "table" and type(ranks.Ranks[rank]) == "table" then
			rankName = tostring(ranks.Ranks[rank].DisplayName or rankName)
		end
		return string.format(
			"Rank %d %s | %d catch(es) | Sand Dollar %s (+%s)",
			rank,
			rankName,
			state.Catches,
			tostring(number(ctx.Game:ItemAmount(SAND_DOLLAR), 0)),
			tostring(math.max(0, number(ctx.Game:ItemAmount(SAND_DOLLAR), 0) - number(state.StartSandDollars, 0)))
		)
	end

	function AutoFishing:_RefreshStats(ctx, state)
		if state.StatsLabel then
			Util.SafeCall("auto fishing stats", state.StatsLabel.UpdateName, state.StatsLabel, AutoFishing:_StatsLine(ctx, state))
		end
		local playerData = ctx.Game:PlayerData()
		local rank = type(playerData) == "table" and number(playerData.Rank, nil) or nil
		if rank ~= nil and state.StartRank ~= nil and rank > state.StartRank then
			state.StartRank = rank
			local information = ctx.Game:Information() or {}
			local ranks = type(information.FishingRodInfo) == "table" and information.FishingRodInfo.FishingRanks or nil
			local rankName = type(ranks) == "table" and type(ranks.Ranks) == "table"
				and type(ranks.Ranks[rank]) == "table" and tostring(ranks.Ranks[rank].DisplayName or rank) or tostring(rank)
			self:_Status(state, "Rank up: " .. rankName .. ".")
			local url = webhookUrl(ctx)
			if url then
				task.spawn(function()
					ctx.Webhook:Post(url, rankPayload(ctx.Player, rank, rankName))
				end)
			end
		elseif rank ~= nil and state.StartRank == nil then
			state.StartRank = rank
		end
	end

	local function equippedRodId(playerData)
		local rods = type(playerData) == "table" and playerData.FishingRodData or nil
		if type(rods) ~= "table" then return nil end
		for rodId, rod in pairs(rods) do
			if type(rod) == "table" and rod.Equipped then return rodId end
		end
		return nil
	end

	local function waterPosition(character, maxRange)
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return nil end
		local nearest, nearestDistance = nil, maxRange
		for _, part in ipairs(CollectionService:GetTagged("Water")) do
			if part:IsA("BasePart") then
				local distance = (part.Position - root.Position).Magnitude
				if distance < nearestDistance then
					nearest = part.Position
					nearestDistance = distance
				end
			end
		end
		return nearest
	end

	function AutoFishing:_CastOnce(ctx, state)
		local character = ctx.Player.Character
		local water = waterPosition(character, state.WaterRange)
		if not water then
			self:_Status(state, "No water nearby; move closer to fish.")
			task.wait(2)
			return
		end
		if not equippedRodId(ctx.Game:PlayerData()) then
			local ok = ctx.Game:Request("FISH_EQUIP", 3)
			if not ok then
				self:_Status(state, "No fishing rod equipped; equip one and retry.")
				task.wait(2)
				return
			end
			task.wait(0.5)
		end

		local hold = 0.3 + math.random() * 0.25
		local fired, err = ctx.Game:Fire("FISH_CAST_REEL", water, hold)
		if not fired then
			self:_Status(state, "Cast failed: " .. tostring(err))
			task.wait(1)
			return
		end

		-- The server times the bite and replicates the Reeling stage; the
		-- legitimate client then plays the reel minigame and reports the
		-- result. Reporting success directly mirrors the game's own
		-- SkipMinigame path.
		local deadline = os.clock() + 30
		while state.Alive and state.Enabled and os.clock() < deadline do
			if state.Stage == "Reeling" then break end
			if state.Stage == "Idle" and os.clock() - (state.LastStageChange or 0) > 8 and state.CycleStarted and os.clock() - state.CycleStarted > 8 then
				break
			end
			task.wait(0.05)
		end
		if not state.Alive or not state.Enabled then return end
		if state.Stage ~= "Reeling" then
			self:_Status(state, "No bite; recasting.")
			return
		end

		ctx.Game:Fire("FISHING_RESULT", true)
		state.Catches = state.Catches + 1
		self:_Status(state, "Catch #" .. tostring(state.Catches) .. ".")
	end

	function AutoFishing:_Start(ctx, state)
		state.Generation = state.Generation + 1
		local generation = state.Generation
		state.Alive = true
		local playerData = ctx.Game:PlayerData()
		state.StartRank = type(playerData) == "table" and number(playerData.Rank, nil) or nil
		state.StartSandDollars = ctx.Game:ItemAmount(SAND_DOLLAR)
		local worker = task.spawn(function()
			while state.Alive and state.Generation == generation and ctx.Runtime.Alive do
				if not state.Enabled then
					task.wait(0.1)
				elseif ctx.Game:IsInGame() then
					self:_Status(state, "Pausing during a match.")
					task.wait(1)
				else
					local ok, err = xpcall(function() self:_CastOnce(ctx, state) end, Util.Traceback)
					if not ok then
						self:_Status(state, "Auto Fishing error: " .. tostring(err))
						task.wait(1)
					end
					self:_RefreshStats(ctx, state)
					task.wait(jitter(number(state.CastDelay, 2)))
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
		Name = "AutoFishing",
		Version = 1,
		Priority = 14,
		Dependencies = {"Misc"},

		Init = function(self, ctx)
			local available = ctx.Game:HasNode("FISH_CAST_REEL")
				and ctx.Game:HasNode("FISHING_RESULT")
				and ctx.Game:HasNode("FISHING_STATE_CHANGED")
			local state = {
				Alive = false,
				Generation = 0,
				Enabled = false,
				Available = available == true,
				CastDelay = 2,
				WaterRange = 80,
				Catches = 0,
				StartRank = nil,
				StartSandDollars = 0,
				Stage = "Idle",
				LastStageChange = os.clock(),
				Status = available and "Idle." or "Unavailable on this server.",
			}

			local section = ctx.Tabs.MiscMinigame:Section({ Side = "Left" })
			section:Header({ Text = "Auto Fishing" })
			if not state.Available then
				section:Label({ Text = "This server build does not expose the fishing system." })
				return state
			end

			ctx.Game:Connect("FISHING_STATE_CHANGED", function(_, path, value)
				if type(path) == "table" and path[2] == "Stage" then
					state.Stage = tostring(value or "Idle")
					state.LastStageChange = os.clock()
				end
			end)

			state.Toggle = ctx.Registry:Toggle(section, {
				Name = "Auto Fish",
				Default = false,
				Callback = function(value)
					state.Enabled = value == true
					if value then
						state.CycleStarted = os.clock()
						if not state.Alive then AutoFishing:_Start(ctx, state) end
					elseif not state.SuppressIdleOnce then
						self:_Status(state, "Idle.")
					end
				end,
			}, "auto_fishing.enabled")
			ctx.Registry:Slider(section, {
				Name = "Cast Delay (s)",
				Default = 2,
				Minimum = 1,
				Maximum = 10,
				Precision = 1,
				Step = 1,
				Callback = function(value)
					state.CastDelay = value
				end,
			}, "auto_fishing.cast_delay")
			state.StatusLabel = section:Label({ Text = "Status: " .. state.Status })
			state.StatsLabel = section:Label({ Text = AutoFishing:_StatsLine(ctx, state) })
			section:Label({ Text = "Requires a fishing rod; climbs rank (raises the daily win-bonus cap) and earns event currency." })
			return state
		end,

		Enable = function(self, ctx, state)
			if not state.Available then return end
			if not ctx.Game.Ready then error("game adapter is unavailable:\n" .. tostring(ctx.Game.Error)) end
			AutoFishing:_Start(ctx, state)
		end,

		Disable = function(self, ctx, state)
			state.Alive = false
			state.Enabled = false
			state.Generation = state.Generation + 1
		end,
	}
end
