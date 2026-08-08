return function()
	local Scanner = {}

	local function isTable(value)
		return type(value) == "table"
	end

	local function isAchievement(category)
		return string.find(string.lower(tostring(category)), "achievement", 1, true) ~= nil
	end

	function Scanner.Quests(playerData, achievements)
		local claims, categoryClaims = {}, {}
		local questData = isTable(playerData) and playerData.QuestData or nil
		for category, categoryData in pairs(isTable(questData) and questData or {}) do
			if isAchievement(category) == (achievements == true) and isTable(categoryData) then
				for quest, questDataEntry in pairs(isTable(categoryData.Quests) and categoryData.Quests or {}) do
					if isTable(questDataEntry) and questDataEntry.Completed == true and questDataEntry.Claimed ~= true then
						table.insert(claims, {Category = category, Quest = quest})
					end
				end
				if categoryData.Completed == true and categoryData.Claimed ~= true then
					table.insert(categoryClaims, category)
				end
			end
		end
		return claims, categoryClaims
	end

	function Scanner.QuestCategories(playerData, categorySet)
		local claims = {}
		local questData = isTable(playerData) and playerData.QuestData or nil
		for category in pairs(isTable(categorySet) and categorySet or {}) do
			local categoryData = isTable(questData) and questData[category] or nil
			for quest, entry in pairs(isTable(categoryData) and isTable(categoryData.Quests) and categoryData.Quests or {}) do
				if isTable(entry) and entry.Completed == true and entry.Claimed ~= true then
					table.insert(claims, {Category = category, Quest = quest})
				end
			end
		end
		return claims
	end

	function Scanner.Calendars(playerData)
		local claims = {}
		local calendars = isTable(playerData) and playerData.CalendarData or nil
		for calendar, calendarData in pairs(isTable(calendars) and calendars or {}) do
			for day, claimed in pairs(isTable(calendarData) and isTable(calendarData.Rewards) and calendarData.Rewards or {}) do
				-- The extracted calendar processor uses false for unlocked/unclaimed and nil for locked.
				if claimed == false then table.insert(claims, {Calendar = calendar, Day = tonumber(day) or day}) end
			end
		end
		return claims
	end

	function Scanner.Battlepasses(playerData)
		local claims = {}
		local passes = isTable(playerData) and playerData.BattlepassData or nil
		for dataKey, pass in pairs(isTable(passes) and passes or {}) do
			if isTable(pass) then
				local level = math.max(tonumber(pass.Level) or 0, 0)
				local claimed = isTable(pass.Claimed) and pass.Claimed or {}
				local tracks = {"Free"}
				if pass.Premium == true then table.insert(tracks, "Premium") end
				local claimable = false
				for _, track in ipairs(tracks) do
					local trackClaims = isTable(claimed[track]) and claimed[track] or {}
					for rewardLevel = 1, level do
						if trackClaims[tostring(rewardLevel)] ~= true then claimable = true break end
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
			if claimed["Level" .. tostring(milestoneLevel)] ~= true then table.insert(claims, milestoneLevel) end
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
