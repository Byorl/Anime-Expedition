return function(Import)
	local Util = Import("Util")
	local Scanner = Import("RewardScanner")
	local HttpService = game:GetService("HttpService")
	local AutoClaim = {}

	local TICK_INTERVAL = 0.5
	local RETRY_INTERVAL = 8
	local MAX_INDIVIDUAL_CLAIMS = 20

	local function sortedSignature(values, formatter)
		local output = {}
		for _, value in ipairs(values) do table.insert(output, formatter and formatter(value) or tostring(value)) end
		table.sort(output)
		return table.concat(output, "|")
	end

	local function readCodeCache(ctx)
		local path = ctx.Config.AccountFolder .. "/codes.json"
		local cache = ctx.FileSystem:ReadJson(path, {})
		if type(cache) ~= "table" or type(cache.Results) ~= "table" then cache = {Schema = 1, Results = {}} end
		cache.Schema = 1
		cache.UserId = ctx.Player.UserId
		return path, cache
	end

	local function describeCodeResult(result)
		if result == true then return "Accepted", "true" end
		if result == false then return "Rejected", "false" end
		if type(result) == "table" then
			local message = tostring(result.Message or result.Error or result.Status or "response table")
			local lower = string.lower(message)
			if result.Success == true then return "Accepted", message end
			if string.find(lower, "already", 1, true) then return "AlreadyRedeemed", message end
			if result.Success == false or result.Error then return "Rejected", message end
			local ok, json = pcall(HttpService.JSONEncode, HttpService, result)
			return "Attempted", ok and json or message
		end
		local message = tostring(result)
		local lower = string.lower(message)
		if string.find(lower, "already", 1, true) then return "AlreadyRedeemed", message end
		if string.find(lower, "invalid", 1, true) or string.find(lower, "expired", 1, true) then return "Rejected", message end
		if string.find(lower, "success", 1, true) or string.find(lower, "redeem", 1, true) then return "Accepted", message end
		return "Attempted", message
	end

	local function mergedCodes(ctx)
		local output = {}
		local information = ctx.Game:Information()
		local static = type(information) == "table" and information.Codes or nil
		static = type(static) == "table" and (static.Codes or static) or {}
		for code, info in pairs(static) do output[code] = info end
		local live = ctx.Game:State("Codes")
		live = type(live) == "table" and (live.Codes or live) or {}
		for code, info in pairs(live) do output[code] = info end
		return output
	end

	local function explicitGroupClaimState(playerData)
		if type(playerData) ~= "table" then return nil end
		for _, key in ipairs({"GroupRewardsClaimed", "GroupRewardClaimed"}) do
			if type(playerData[key]) == "boolean" then return playerData[key] end
		end
		if type(playerData.GroupRewards) == "table" and type(playerData.GroupRewards.Claimed) == "boolean" then
			return playerData.GroupRewards.Claimed
		end
		return nil
	end

	local function eventQuestCategories(information)
		local categories = {}
		for eventId, event in pairs(type(information.Events) == "table" and information.Events or {}) do
			if type(event) == "table" then
				if type(event.QuestCategories) == "table" then
					for _, category in ipairs(event.QuestCategories) do categories[category] = true end
				end
				if event.DataKey then categories[event.DataKey] = true
				else categories[eventId] = true end
			end
		end
		return categories
	end

	function AutoClaim:_Report(ctx, state, action, err)
		local now = os.clock()
		if now - (state.LastErrors[action] or 0) < 15 then return end
		state.LastErrors[action] = now
		Util.Warn(string.format("AutoClaim action '%s' failed: %s", action, tostring(err)))
	end

	function AutoClaim:_Fire(ctx, state, action, node, ...)
		local ok, err = ctx.Game:Fire(node, ...)
		if not ok then self:_Report(ctx, state, action, err) end
		return ok
	end

	function AutoClaim:_Once(ctx, state, key, signature, callback)
		if signature == nil or signature == "" then state.LastClaims[key] = nil return end
		local previous = state.LastClaims[key]
		local now = os.clock()
		if previous and previous.Signature == signature and now - previous.At < RETRY_INTERVAL then return end
		state.LastClaims[key] = {Signature = signature, At = now}
		local ok, err = xpcall(callback, Util.Traceback)
		if not ok then self:_Report(ctx, state, key, err) end
	end

	function AutoClaim:_RedeemNextCode(ctx, state)
		if state.CodeBusy or not state.Values.Codes then return end
		local now = workspace:GetServerTimeNow()
		local candidate, candidateInfo
		for code, info in pairs(mergedCodes(ctx)) do
			info = type(info) == "table" and info or {}
			local starts = tonumber(info.ActiveFrom) or -math.huge
			local expires = tonumber(info.ActiveUntil) or math.huge
			local cached = state.CodeCache.Results[string.lower(tostring(code))]
			local releaseKey = tonumber(info.ActiveUntil) or 0
			local sameRelease = type(cached) == "table"
				and cached.Status ~= "RequestFailed"
				and tonumber(cached.ActiveUntil) == releaseKey
			if starts <= now and now <= expires and not sameRelease then
				candidate, candidateInfo = tostring(code), info
				break
			end
		end
		if not candidate then return end
		state.CodeBusy = true
		local generation = state.Generation
		task.spawn(function()
			local ok, response = ctx.Game:Request("CLAIM_CODE", 5, candidate)
			if not state.Alive or state.Generation ~= generation then return end
			local status, detail
			if ok then status, detail = describeCodeResult(response)
			else status, detail = "RequestFailed", tostring(response) end
			state.CodeCache.Results[string.lower(candidate)] = {
				Code = candidate,
				Status = status,
				Detail = string.sub(detail, 1, 300),
				CheckedAt = os.time(),
				ActiveUntil = tonumber(candidateInfo.ActiveUntil) or 0,
			}
			local writeOk, writeError = ctx.FileSystem:WriteJson(state.CodeCachePath, state.CodeCache)
			if not writeOk then self:_Report(ctx, state, "codes cache", writeError) end
			state.CodeBusy = false
		end)
	end

	function AutoClaim:_Scan(ctx, state)
		local playerData = ctx.Game:PlayerData()
		if type(playerData) ~= "table" then return end
		local information = ctx.Game:Information() or {}

		if state.Values.Quests then
			local claims, categories = Scanner.Quests(playerData, false)
			local signature = sortedSignature(claims, function(v) return tostring(v.Category) .. "/" .. tostring(v.Quest) end)
				.. ":" .. sortedSignature(categories)
			self:_Once(ctx, state, "quests", signature, function()
				if #claims > 0 then self:_Fire(ctx, state, "quests", "QUEST_CLAIM_ALL") end
				if #categories > 0 then self:_Fire(ctx, state, "quest categories", "QUEST_CLAIM_ALL_CATEGORIES") end
			end)
		end

		if state.Values.Achievements then
			local claims, categories = Scanner.Quests(playerData, true)
			local signature = sortedSignature(claims, function(v) return tostring(v.Category) .. "/" .. tostring(v.Quest) end)
				.. ":" .. sortedSignature(categories)
			self:_Once(ctx, state, "achievements", signature, function()
				for index, claim in ipairs(claims) do
					if index > MAX_INDIVIDUAL_CLAIMS then break end
					self:_Fire(ctx, state, "achievement", "QUEST_CLAIM", claim.Category, claim.Quest)
				end
				for index, category in ipairs(categories) do
					if index > MAX_INDIVIDUAL_CLAIMS then break end
					self:_Fire(ctx, state, "achievement category", "QUEST_CLAIM_CATEGORY", category)
				end
			end)
		end

		if state.Values.Calendars then
			local claims = Scanner.Calendars(playerData)
			self:_Once(ctx, state, "calendars", sortedSignature(claims, function(v)
				return tostring(v.Calendar) .. "/" .. tostring(v.Day)
			end), function()
				for index, claim in ipairs(claims) do
					if index > MAX_INDIVIDUAL_CLAIMS then break end
					self:_Fire(ctx, state, "calendar", "CLAIM_CALENDAR", claim.Calendar, claim.Day)
				end
			end)
		end

		if state.Values.Battlepass then
			local claims = Scanner.Battlepasses(playerData)
			self:_Once(ctx, state, "battlepass", sortedSignature(claims), function()
				for _, dataKey in ipairs(claims) do
					self:_Fire(ctx, state, "battlepass", "CLAIM_ALL_BATTLEPASS_REWARDS", dataKey)
				end
			end)
		end

		if state.Values.LevelMilestones then
			local claims = Scanner.LevelMilestones(playerData, information.LevelMilestones)
			self:_Once(ctx, state, "level milestones", sortedSignature(claims), function()
				for index, level in ipairs(claims) do
					if index > MAX_INDIVIDUAL_CLAIMS then break end
					self:_Fire(ctx, state, "level milestone", "CLAIM_LEVEL_MILESTONE", level)
				end
			end)
		end

		if state.Values.Index then
			local signature = Scanner.HasIndexRewards(playerData) and "claimable" or ""
			self:_Once(ctx, state, "index", signature, function()
				self:_Fire(ctx, state, "index", "INDEX_CLAIM_ALL")
			end)
		end

		if state.Values.Expeditions then
			local buildings, milestones = Scanner.Expeditions(playerData)
			local expeditionCategories = {Expedition_Weekly = true}
			local milestoneInfo = type(information.Expeditions) == "table" and information.Expeditions.Milestones or nil
			if type(milestoneInfo) == "table" and milestoneInfo.QuestCategory then
				expeditionCategories[milestoneInfo.QuestCategory] = true
			end
			local expeditionQuests = state.Values.Quests and {} or Scanner.QuestCategories(playerData, expeditionCategories)
			local expeditionSignature = sortedSignature(buildings) .. (milestones and ":milestones" or "")
				.. sortedSignature(expeditionQuests, function(v) return tostring(v.Category) .. "/" .. tostring(v.Quest) end)
			self:_Once(ctx, state, "expeditions", expeditionSignature, function()
				for _, building in ipairs(buildings) do
					self:_Fire(ctx, state, "expedition building", "EXPEDITION_BUILDING_COLLECT", building)
				end
				if milestones then self:_Fire(ctx, state, "expedition milestones", "QUESTBOARD_CLAIM_ALL_MILESTONES") end
				local seenCategories = {}
				for _, claim in ipairs(expeditionQuests) do
					if not seenCategories[claim.Category] then
						seenCategories[claim.Category] = true
						self:_Fire(ctx, state, "expedition quests", "QUEST_CLAIM_ALL_CATEGORY", claim.Category)
					end
				end
			end)
		end

		if state.Values.Events then
			local villain = Scanner.VillainHunt(playerData, information.Events)
			local sessionData = ctx.Game:State("SessionData")
			local preRelease = Scanner.PreRelease(sessionData)
			local eventQuests = state.Values.Quests and {} or Scanner.QuestCategories(playerData, eventQuestCategories(information))
			local eventSignature = (villain and "villain" or "") .. sortedSignature(preRelease)
				.. sortedSignature(eventQuests, function(v) return tostring(v.Category) .. "/" .. tostring(v.Quest) end)
			self:_Once(ctx, state, "events", eventSignature, function()
				if villain then self:_Fire(ctx, state, "villain hunt", "VILLAIN_HUNT_CLAIM_MILESTONES") end
				for _, index in ipairs(preRelease) do
					self:_Fire(ctx, state, "pre-release milestone", "PRE_RELEASE_CLAIM_MILESTONE", index)
				end
				local seenCategories = {}
				for _, claim in ipairs(eventQuests) do
					if not seenCategories[claim.Category] then
						seenCategories[claim.Category] = true
						self:_Fire(ctx, state, "event quests", "QUEST_CLAIM_ALL_CATEGORY", claim.Category)
					end
				end
			end)
		end

		if state.Values.Tournaments then
			local tournamentData = ctx.Game:State("TournamentData")
			local claims = Scanner.Tournaments(playerData, tournamentData)
			self:_Once(ctx, state, "tournaments", sortedSignature(claims, function(v)
				return tostring(v.Tournament) .. "/" .. tostring(v.Season)
			end), function()
				for _, claim in ipairs(claims) do
					self:_Fire(ctx, state, "tournament", "TOURNAMENT_CLAIM_SEASON_REWARD", claim.Tournament, claim.Season)
				end
			end)
		end

		if state.Values.GroupRewards and not state.GroupAttempted then
			local claimed = explicitGroupClaimState(playerData)
			local groupId = tonumber(information.GroupId)
			if not state.GroupMembershipChecked then
				state.GroupMembershipChecked = true
				state.InGroup = false
				if groupId then pcall(function() state.InGroup = ctx.Player:IsInGroup(groupId) end) end
			end
			if claimed ~= true and state.InGroup then
				state.GroupAttempted = true
				self:_Fire(ctx, state, "group rewards", "GROUP_REWARDS_CLAIM")
			end
		end

		self:_RedeemNextCode(ctx, state)
	end

	function AutoClaim:_Start(ctx, state)
		state.Generation = state.Generation + 1
		local generation = state.Generation
		state.Alive = true
		ctx:RegisterCleanup(function()
			if state.Generation == generation then state.Alive = false end
		end)
		task.spawn(function()
			while state.Alive and state.Generation == generation and ctx.Runtime.Alive do
				local ok, err = xpcall(function() self:_Scan(ctx, state) end, Util.Traceback)
				if not ok then self:_Report(ctx, state, "scheduler", err) end
				task.wait(TICK_INTERVAL)
			end
		end)
	end

	return {
		Name = "AutoClaim",
		Version = 1,
		Priority = 11,
		Dependencies = {"Misc"},

		Init = function(self, ctx)
			local state = {
				Alive = false,
				Generation = 0,
				Values = {},
				LastClaims = {},
				LastErrors = {},
				CodeBusy = false,
				GroupAttempted = false,
				GroupMembershipChecked = false,
				InGroup = false,
			}
			state.CodeCachePath, state.CodeCache = readCodeCache(ctx)
			local section = ctx.Tabs.Misc:Section({Side = "Left"})
			section:Header({Text = "Auto Claim"})
			local controls = {
				{"Auto Claim Quests", "Quests", "auto_claim.quests"},
				{"Auto Claim Achievements", "Achievements", "auto_claim.achievements"},
				{"Auto Claim Battlepass", "Battlepass", "auto_claim.battlepass"},
				{"Auto Claim Calendars", "Calendars", "auto_claim.calendars"},
				{"Auto Claim Index", "Index", "auto_claim.index"},
				{"Auto Claim Level Milestones", "LevelMilestones", "auto_claim.level_milestones"},
				{"Auto Claim Events", "Events", "auto_claim.events"},
				{"Auto Claim Expeditions", "Expeditions", "auto_claim.expeditions"},
				{"Auto Claim Tournaments", "Tournaments", "auto_claim.tournaments"},
				{"Auto Claim Group Rewards", "GroupRewards", "auto_claim.group_rewards"},
				{"Auto Redeem Codes", "Codes", "auto_claim.codes"},
			}
			for _, definition in ipairs(controls) do
				local label, valueKey, flag = definition[1], definition[2], definition[3]
				ctx.Registry:Toggle(section, {
					Name = label,
					Default = false,
					Callback = function(value)
						state.Values[valueKey] = value == true
						if not value then
							table.clear(state.LastClaims)
							if valueKey == "GroupRewards" then
								state.GroupAttempted = false
								state.GroupMembershipChecked = false
							end
						end
					end,
				}, flag)
			end
			return state
		end,

		Enable = function(self, ctx, state)
			if not ctx.Game.Ready then error("game adapter is unavailable:\n" .. tostring(ctx.Game.Error)) end
			self:_Start(ctx, state)
		end,

		Disable = function(self, ctx, state)
			state.Alive = false
			state.Generation = state.Generation + 1
			state.CodeBusy = false
			table.clear(state.LastClaims)
		end,
	}
end
