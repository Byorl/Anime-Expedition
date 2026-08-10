return function()
	local Scanner = {}

	local function isTable(value)
		return type(value) == "table"
	end

	local function isAchievement(category, questInformation)
		local categories = isTable(questInformation) and questInformation.Categories or nil
		local info = isTable(categories) and categories[category] or nil
		if isTable(info) and type(info.IsAchievement) == "boolean" then return info.IsAchievement end
		return string.find(string.lower(tostring(category)), "achievement", 1, true) ~= nil
	end

	local function hasEntries(value)
		return isTable(value) and next(value) ~= nil
	end

	local function questInfoFor(questInformation, category, quest)
		local categories = isTable(questInformation) and questInformation.Quests or nil
		local categoryInfo = isTable(categories) and categories[category] or nil
		return isTable(categoryInfo) and categoryInfo[quest] or nil
	end

	local function questIsClaimable(questData, category, quest, entry, questInformation)
		if not isTable(entry) or entry.Completed ~= true or entry.Claimed == true then return false end
		local info = questInfoFor(questInformation, category, quest)
		if isTable(questInformation) and isTable(questInformation.Quests) and not isTable(info) then return false end
		if not isTable(info) then return true end
		if info.ClaimAllowed == false then return false end

		local categoryData = isTable(questData) and questData[category] or nil
		local categoryQuests = isTable(categoryData) and categoryData.Quests or nil
		for key, value in pairs(isTable(info.Prerequisites) and info.Prerequisites or {}) do
			local prerequisite = (type(value) == "string" or type(value) == "number") and value or key
			local prerequisiteData = isTable(categoryQuests) and categoryQuests[prerequisite] or nil
			if not isTable(prerequisiteData) or prerequisiteData.Claimed ~= true then return false end
		end
		return true
	end

	local function categoryHasRewards(questInformation, category)
		local categories = isTable(questInformation) and questInformation.Categories or nil
		local info = isTable(categories) and categories[category] or nil
		return isTable(info) and hasEntries(info.Rewards)
	end

	function Scanner.Quests(playerData, achievements, questInformation, excludedCategories)
		local claims, categoryClaims = {}, {}
		local questData = isTable(playerData) and playerData.QuestData or nil
		for category, categoryData in pairs(isTable(questData) and questData or {}) do
			if not (isTable(excludedCategories) and excludedCategories[category])
				and isAchievement(category, questInformation) == (achievements == true) and isTable(categoryData) then
				for quest, questDataEntry in pairs(isTable(categoryData.Quests) and categoryData.Quests or {}) do
					if questIsClaimable(questData, category, quest, questDataEntry, questInformation) then
						table.insert(claims, {Category = category, Quest = quest})
					end
				end
				if achievements == true and categoryData.Completed == true and categoryData.Claimed ~= true
					and categoryHasRewards(questInformation, category) then
					table.insert(categoryClaims, category)
				end
			end
		end
		return claims, categoryClaims
	end

	function Scanner.QuestCategories(playerData, categorySet, questInformation, excludedCategories)
		local claims = {}
		local questData = isTable(playerData) and playerData.QuestData or nil
		for category in pairs(isTable(categorySet) and categorySet or {}) do
			if not (isTable(excludedCategories) and excludedCategories[category]) then
				local categoryData = isTable(questData) and questData[category] or nil
				for quest, entry in pairs(isTable(categoryData) and isTable(categoryData.Quests) and categoryData.Quests or {}) do
					if questIsClaimable(questData, category, quest, entry, questInformation) then
						table.insert(claims, {Category = category, Quest = quest})
					end
				end
			end
		end
		return claims
	end

	function Scanner.DragonBalls(playerData, categorySet)
		local claims = {}
		local questData = isTable(playerData) and playerData.QuestData or nil
		for category in pairs(isTable(categorySet) and categorySet or {}) do
			local categoryData = isTable(questData) and questData[category] or nil
			local quests = isTable(categoryData) and categoryData.Quests or nil
			for quest, entry in pairs(isTable(quests) and quests or {}) do
				if isTable(entry) and entry.Completed == true and entry.Claimed ~= true then
					table.insert(claims, {Category = category, Quest = quest})
				end
			end
		end
		table.sort(claims, function(left, right)
			local leftKey = tostring(left.Category) .. "/" .. tostring(left.Quest)
			local rightKey = tostring(right.Category) .. "/" .. tostring(right.Quest)
			return leftKey < rightKey
		end)
		return claims
	end

	function Scanner.Calendars(playerData)
		local claims = {}
		local calendars = isTable(playerData) and playerData.CalendarData or nil
		for calendar, calendarData in pairs(isTable(calendars) and calendars or {}) do
			for day, claimed in pairs(isTable(calendarData) and isTable(calendarData.Rewards) and calendarData.Rewards or {}) do
				if claimed == false then table.insert(claims, {Calendar = calendar, Day = tonumber(day) or day}) end
			end
		end
		return claims
	end

	function Scanner.Battlepasses(playerData, battlepassData)
		local claims = {}
		local passes = isTable(playerData) and playerData.BattlepassData or nil
		for dataKey, pass in pairs(isTable(passes) and passes or {}) do
			if isTable(pass) then
				local live = isTable(battlepassData) and battlepassData[dataKey] or nil
				local info = isTable(live) and (live.BattlepassInfo or live) or nil
				local rewards = isTable(info) and info.Rewards or nil
				local level = math.max(tonumber(pass.Level) or 0, 0)
				local claimed = isTable(pass.Claimed) and pass.Claimed or {}
				local tracks = {}
				if isTable(claimed.Free) then table.insert(tracks, "Free") end
				if pass.Premium == true and isTable(claimed.Premium) then table.insert(tracks, "Premium") end
				local claimable = false
				for _, track in ipairs(tracks) do
					local trackClaims = claimed[track]
					for rewardLevel = 1, level do
						local reward = isTable(rewards) and (rewards[rewardLevel] or rewards[tostring(rewardLevel)]) or nil
						if isTable(reward) and reward[track] ~= nil and trackClaims[tostring(rewardLevel)] ~= true then
							claimable = true
							break
						end
					end
					if claimable then break end
				end
				if claimable then table.insert(claims, dataKey) end
			end
		end
		return claims
	end

	function Scanner.LevelMilestones(playerData, milestoneInfo)
		local claims = {}
		if not isTable(playerData) or not isTable(milestoneInfo) then return claims end
		local every = tonumber(milestoneInfo.MilestoneEvery) or 5
		local level = math.max(tonumber(playerData.Level) or 0, 0)
		local maxCount = tonumber(milestoneInfo.MaxMilestoneCount) or math.floor(level / every)
		local claimed = isTable(playerData.LevelMilestones) and isTable(playerData.LevelMilestones.Claimed)
			and playerData.LevelMilestones.Claimed or {}
		for index = 1, math.min(math.floor(level / every), maxCount) do
			local milestoneLevel = index * every
			if claimed["Level" .. tostring(milestoneLevel)] ~= true then
				local validRewards = false
				if type(milestoneInfo.GetRewardsForLevel) == "function" then
					local ok, rewards = pcall(milestoneInfo.GetRewardsForLevel, milestoneInfo, milestoneLevel)
					validRewards = ok and hasEntries(rewards)
				else
					local rewards = isTable(milestoneInfo.Rewards)
						and (milestoneInfo.Rewards[milestoneLevel] or milestoneInfo.Rewards[tostring(milestoneLevel)]) or nil
					validRewards = hasEntries(rewards)
				end
				if validRewards then table.insert(claims, milestoneLevel) end
			end
		end
		return claims
	end

	function Scanner.HasIndexRewards(playerData)
		local index = isTable(playerData) and playerData.Index or nil
		for _, category in pairs(isTable(index) and index or {}) do
			for _, entry in pairs(isTable(category) and category or {}) do
				if isTable(entry) and entry.Claimed == false then return true end
			end
		end
		return false
	end

	function Scanner.Expeditions(playerData)
		local collect, milestones = {}, false
		local expedition = isTable(playerData) and playerData.ExpeditionData or nil
		local buildings = isTable(expedition) and expedition.Buildings or nil
		for buildingName, building in pairs(isTable(buildings) and buildings or {}) do
			if isTable(building) and isTable(building.Rewards) and next(building.Rewards) ~= nil then
				table.insert(collect, buildingName)
			end
		end
		local board = isTable(buildings) and buildings.QuestBoard or nil
		if isTable(board) then
			local claimed = isTable(board.ClaimedMilestones) and board.ClaimedMilestones or {}
			for index = 1, math.max(tonumber(board.Milestone) or 0, 0) do
				if claimed["Milestone" .. tostring(index)] ~= true then milestones = true break end
			end
		end
		return collect, milestones
	end

	function Scanner.VillainHunt(playerData, eventInfo)
		local events = isTable(playerData) and playerData.EventData or nil
		local data = isTable(events) and events.VillainHunt or nil
		local info = isTable(eventInfo) and eventInfo.VillainHunt or nil
		if not isTable(data) or not isTable(info) then return false end
		local progress = tonumber(data.TotalClears) or 0
		local claimed = isTable(data.ClaimedMilestones) and data.ClaimedMilestones or {}
		for threshold in pairs(isTable(info.Milestones) and info.Milestones or {}) do
			local amount = tonumber(threshold)
			if amount and amount <= progress and claimed[tostring(threshold)] ~= true then return true end
		end
		return false
	end

	function Scanner.PreRelease(sessionData)
		local claims = {}
		local chamber = isTable(sessionData) and sessionData.PreReleaseChamber or nil
		local info = isTable(chamber) and chamber.Info or nil
		local data = isTable(chamber) and chamber.PlayerData or nil
		local totalTime = isTable(data) and tonumber(data.TotalTime) or 0
		local startTime = isTable(chamber) and tonumber(chamber.StartTime) or nil
		local elapsed = totalTime + (startTime and math.max(workspace:GetServerTimeNow() - startTime, 0) or 0)
		local claimed = isTable(data) and isTable(data.ClaimedMilestones) and data.ClaimedMilestones or {}
		for index, milestone in ipairs(isTable(info) and isTable(info.Milestones) and info.Milestones or {}) do
			if elapsed >= (tonumber(milestone.Time) or math.huge) and claimed[tostring(index)] ~= true then
				table.insert(claims, index)
			end
		end
		return claims
	end

	function Scanner.Tournaments(playerData, tournamentData)
		local claims = {}
		local playerTournaments = isTable(playerData) and playerData.TournamentData or nil
		local brackets = isTable(playerTournaments) and playerTournaments.ActiveBrackets or nil
		for tournamentId, tournament in pairs(isTable(tournamentData) and tournamentData or {}) do
			local season = isTable(tournament) and tonumber(tournament.Season) or nil
			local tournamentBrackets = isTable(brackets) and brackets[tournamentId] or nil
			local bracket = season and isTable(tournamentBrackets) and tournamentBrackets[tostring(season)] or nil
			if isTable(bracket) and (tonumber(bracket.HighestScore) or 0) > 0 and bracket.RewardClaimed ~= true then
				table.insert(claims, {Tournament = tournamentId, Season = season})
			end
		end
		return claims
	end

	return Scanner
end
