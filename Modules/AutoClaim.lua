local function resolveHub(...)
	local viaVarargs = ...
	if typeof(viaVarargs) == "table" and viaVarargs.Core ~= nil then
		return viaVarargs
	end
	local env = (getgenv and getgenv()) or shared or _G
	return env.__AEHubLoading
end

local Hub = resolveHub(...)
assert(Hub and Hub.Core and Hub.Core.Library, "[AEHub] Hub context missing while loading AutoClaim")
local Library = Hub.Core.Library

local MODULE_ID = "AutoClaim"
local TARGET_PLACE_ID = 84515722934860
local TRACK_PATH = Library.TrackFolder .. "/AutoClaim.json"

local CATEGORY_KEYS = {
	"Quests",
	"Achievements",
	"Calendar",
	"Battlepass",
	"LevelMilestones",
	"ExpeditionBoard",
	"ExpeditionBuildings",
	"GroupRewards",
	"Tournament",
	"AfkMilestones",
	"VillainHunt",
	"PromoCodes",
}

local DEFAULTS = {
	Enabled = false,
	PollInterval = 1,
	ClaimCooldown = 2,
	Quests = false,
	Achievements = false,
	Calendar = false,
	Battlepass = false,
	LevelMilestones = false,
	ExpeditionBoard = false,
	ExpeditionBuildings = false,
	GroupRewards = false,
	Tournament = false,
	AfkMilestones = false,
	VillainHunt = false,
	PromoCodes = false,
}

local function anyCategoryEnabled(state)
	for _, key in CATEGORY_KEYS do
		if state[key] == true then
			return true
		end
	end
	-- Back-compat for older configs that used Index
	if state.Index == true then
		return true
	end
	return false
end

local function syncPowerFromCategories(state, hub)
	local shouldRun = anyCategoryEnabled(state)
	state.Enabled = shouldRun
	if hub and hub.Config then
		hub.Config.Values[MODULE_ID .. ".Enabled"] = shouldRun
	end
	if not hub or not hub.Modules then
		return
	end
	local module = hub.Modules:Get(MODULE_ID)
	if not module then
		return
	end
	if shouldRun and not module.Enabled then
		hub.Modules:Enable(MODULE_ID)
	elseif not shouldRun and module.Enabled then
		hub.Modules:Disable(MODULE_ID)
	end
end

local function loadTrack(runtime)
	local track = {
		RedeemedCodes = {},
		GroupRewardsClaimed = false,
		TournamentBlockedUntil = {},
	}

	local saved = Library.ReadJson(TRACK_PATH, nil)
	if typeof(saved) == "table" then
		if typeof(saved.RedeemedCodes) == "table" then
			track.RedeemedCodes = saved.RedeemedCodes
		end
		if saved.GroupRewardsClaimed == true then
			track.GroupRewardsClaimed = true
		end
		if typeof(saved.TournamentBlockedUntil) == "table" then
			track.TournamentBlockedUntil = saved.TournamentBlockedUntil
		end
	end

	runtime.Track = track
	return track
end

local function saveTrack(runtime)
	if typeof(runtime.Track) ~= "table" then
		return
	end
	Library.WriteJson(TRACK_PATH, runtime.Track)
end

local function stopRuntime(runtime)
	runtime.Running = false
	if typeof(runtime.Cleanup) == "function" then
		pcall(function()
			runtime:Cleanup()
		end)
	else
		if runtime.BootThread then
			pcall(task.cancel, runtime.BootThread)
			runtime.BootThread = nil
		end
		if runtime.PollThread then
			pcall(task.cancel, runtime.PollThread)
			runtime.PollThread = nil
		end
		if runtime.ChangeConnection then
			pcall(function()
				runtime.ChangeConnection:Disconnect()
			end)
			runtime.ChangeConnection = nil
		end
	end
	runtime.Pending = {}
	runtime.Replica = nil
	runtime.Nodes = nil
	runtime.Information = nil
	runtime.Dependencies = nil
	runtime.Actions = nil
	runtime.Peek = nil
	runtime.LocalPlayer = nil
	runtime.Scan = nil
end

local function createController(state, runtime)
	local Nodes = runtime.Nodes
	local Information = runtime.Information
	local Dependencies = runtime.Dependencies
	local Actions = runtime.Actions
	local peek = runtime.Peek
	local LocalPlayer = runtime.LocalPlayer
	local track = runtime.Track
	local pending = runtime.Pending

	local function canFire(key)
		local cooldown = tonumber(state.ClaimCooldown) or DEFAULTS.ClaimCooldown
		local now = os.clock()
		if pending[key] and now - pending[key] < cooldown then
			return false
		end
		pending[key] = now
		return true
	end

	local function fireNode(nodeName, key, ...)
		if not canFire(key) then
			return false
		end
		local args = table.pack(...)
		local ok, err = pcall(function()
			Nodes[nodeName]:FireServer(table.unpack(args, 1, args.n))
		end)
		if ok then
			print(("[AEHub:AutoClaim] %s | %s"):format(nodeName, key))
		else
			warn(("[AEHub:AutoClaim] Failed %s | %s | %s"):format(nodeName, key, tostring(err)))
		end
		return ok
	end

	local function getData()
		return runtime.Replica and runtime.Replica.Data or {}
	end

	local function getSessionData()
		local ok, session = pcall(function()
			return peek(Dependencies.SessionData)
		end)
		if ok and typeof(session) == "table" then
			return session
		end
		return {}
	end

	local function tableLength(t)
		if typeof(t) ~= "table" then
			return 0
		end
		local n = 0
		for _ in t do
			n = n + 1
		end
		return n
	end

	local function normalizeCode(code)
		return string.lower((tostring(code):gsub("%s+", "")))
	end

	local function isCodeRedeemed(code)
		local key = normalizeCode(code)
		if track.RedeemedCodes[key] == true then
			return true
		end

		local data = getData()
		for _, bucket in { data.RedeemedCodes, data.ClaimedCodes, data.UsedCodes, data.Codes } do
			if typeof(bucket) == "table" then
				if bucket[key] == true or bucket[code] == true then
					return true
				end
				if typeof(bucket[key]) == "table" or typeof(bucket[code]) == "table" then
					return true
				end
			end
		end
		return false
	end

	local function markCodeRedeemed(code)
		local key = normalizeCode(code)
		if track.RedeemedCodes[key] == true then
			return
		end
		track.RedeemedCodes[key] = true
		saveTrack(runtime)
	end

	local function isCodeCurrentlyValid(codeInfo)
		if typeof(codeInfo) ~= "table" then
			return false
		end
		local now = workspace:GetServerTimeNow()
		local activeFrom = tonumber(codeInfo.ActiveFrom) or 0
		local activeUntil = tonumber(codeInfo.ActiveUntil)
		if now < activeFrom then
			return false
		end
		if activeUntil and now > activeUntil then
			return false
		end
		return true
	end

	local function prerequisitesMet(category, questName, quests)
		local questInfo = Information.Quests:GetQuestInfo(category, questName)
		if not questInfo or typeof(questInfo.Prerequisites) ~= "table" then
			return true
		end
		for _, prerequisite in questInfo.Prerequisites do
			local questState = quests[prerequisite]
			if not (typeof(questState) == "table" and questState.Claimed == true) then
				return false
			end
		end
		return true
	end

	local function isQuestClaimable(category, questName, questState, quests)
		if questState.Completed ~= true or questState.Claimed == true then
			return false
		end
		local categoryInfo = Information.Quests:GetCategoryInfo(category)
		if categoryInfo and categoryInfo.Claimable == false then
			return false
		end
		local questInfo = Information.Quests:GetQuestInfo(category, questName)
		if questInfo and questInfo.ClaimAllowed == false then
			return false
		end
		return prerequisitesMet(category, questName, quests)
	end

	local function claimQuests(data)
		if state.Quests ~= true then
			return
		end
		local questData = data.QuestData
		if typeof(questData) ~= "table" then
			return
		end
		for category, categoryData in questData do
			if typeof(categoryData) == "table" and typeof(categoryData.Quests) == "table" then
				for questName, questState in categoryData.Quests do
					if typeof(questState) == "table" and isQuestClaimable(category, questName, questState, categoryData.Quests) then
						fireNode("QUEST_CLAIM", "quest:" .. category .. ":" .. questName, category, questName)
					end
				end
			end
		end
	end

	local function claimIndex(data)
		if state.Achievements ~= true and state.Index ~= true then
			return
		end
		local indexData = data.Index
		if typeof(indexData) ~= "table" then
			return
		end
		local hasClaimable = false
		for _, categoryData in indexData do
			if typeof(categoryData) == "table" then
				for _, entry in categoryData do
					if typeof(entry) == "table" and entry.Obtained == true and entry.Claimed ~= true then
						hasClaimable = true
						break
					end
				end
			end
			if hasClaimable then
				break
			end
		end
		if hasClaimable then
			fireNode("INDEX_CLAIM_ALL", "index:all")
		end
	end

	local function claimCalendars(data)
		if state.Calendar ~= true then
			return
		end
		local calendarData = data.CalendarData
		if typeof(calendarData) ~= "table" then
			return
		end
		for calendarId, calendar in calendarData do
			if typeof(calendar) == "table" and typeof(calendar.Rewards) == "table" then
				for dayKey, rewardState in calendar.Rewards do
					if rewardState == false then
						local day = tonumber(dayKey)
						if day then
							fireNode("CLAIM_CALENDAR", "calendar:" .. tostring(calendarId) .. ":" .. tostring(day), calendarId, day)
						end
					end
				end
			end
		end
	end

	local function battlepassHasClaimable(bpData)
		if typeof(bpData) ~= "table" then
			return false
		end
		local level = tonumber(bpData.Level) or 0
		if level <= 0 then
			return false
		end
		local claimed = typeof(bpData.Claimed) == "table" and bpData.Claimed or {}
		local free = typeof(claimed.Free) == "table" and claimed.Free or {}
		local premium = typeof(claimed.Premium) == "table" and claimed.Premium or {}
		for n = 1, level do
			local key = tostring(n)
			if free[key] ~= true then
				return true
			end
			if bpData.Premium == true and premium[key] ~= true then
				return true
			end
		end
		return false
	end

	local function claimBattlepasses(data)
		if state.Battlepass ~= true then
			return
		end
		local battlepassData = typeof(data.BattlepassData) == "table" and data.BattlepassData or {}
		local keys = {}
		local currentSeason = Information.Battlepass and Information.Battlepass.CurrentSeason
		if typeof(currentSeason) == "string" then
			keys[currentSeason] = true
		end
		if Information.Battlepass and typeof(Information.Battlepass.Battlepasses) == "table" then
			for seasonName in Information.Battlepass.Battlepasses do
				keys[seasonName] = true
			end
		end
		for seasonName in battlepassData do
			keys[seasonName] = true
		end
		for dataKey in keys do
			if battlepassHasClaimable(battlepassData[dataKey]) then
				fireNode("CLAIM_ALL_BATTLEPASS_REWARDS", "battlepass:" .. tostring(dataKey), dataKey)
			end
		end
	end

	local function claimLevelMilestones(data)
		if state.LevelMilestones ~= true then
			return
		end
		local playerLevel = tonumber(data.Level) or 0
		local milestoneInfo = Information.LevelMilestones
		if not milestoneInfo then
			return
		end
		local every = tonumber(milestoneInfo.MilestoneEvery) or 5
		local maxCount = tonumber(milestoneInfo.MaxMilestoneCount) or 50
		local claimed = data.LevelMilestones and data.LevelMilestones.Claimed
		if typeof(claimed) ~= "table" then
			claimed = {}
		end
		local hasClaimable = false
		for index = 1, maxCount do
			local requiredLevel = index * every
			if playerLevel >= requiredLevel then
				local key = "Level" .. tostring(requiredLevel)
				if claimed[key] ~= true then
					hasClaimable = true
					break
				end
			end
		end
		if hasClaimable then
			fireNode("CLAIM_LEVEL_MILESTONE", "levelmilestones:all")
		end
	end

	local function claimExpeditionQuestBoard(data)
		if state.ExpeditionBoard ~= true then
			return
		end
		local buildings = data.ExpeditionData and data.ExpeditionData.Buildings
		if typeof(buildings) ~= "table" then
			return
		end
		local questBoard = buildings.QuestBoard
		if typeof(questBoard) ~= "table" then
			return
		end
		local currentMilestone = tonumber(questBoard.Milestone) or 0
		if currentMilestone <= 0 then
			return
		end
		local claimedMilestones = typeof(questBoard.ClaimedMilestones) == "table" and questBoard.ClaimedMilestones or {}
		local maxLevel = 10
		if Information.Expeditions and Information.Expeditions.Milestones then
			maxLevel = tonumber(Information.Expeditions.Milestones.MilestoneMaxLevel) or 10
		end
		local hasClaimable = false
		for n = 1, math.min(currentMilestone, maxLevel) do
			if claimedMilestones["Milestone" .. tostring(n)] ~= true then
				hasClaimable = true
				break
			end
		end
		if hasClaimable then
			fireNode("QUESTBOARD_CLAIM_ALL_MILESTONES", "expedition:questboard:all")
		end
	end

	local function claimExpeditionBuildingRewards(data)
		if state.ExpeditionBuildings ~= true then
			return
		end
		local buildings = data.ExpeditionData and data.ExpeditionData.Buildings
		if typeof(buildings) ~= "table" then
			return
		end
		for buildingName, buildingData in buildings do
			if typeof(buildingData) == "table" and tableLength(buildingData.Rewards) > 0 then
				fireNode("EXPEDITION_BUILDING_COLLECT", "expedition:collect:" .. tostring(buildingName), buildingName)
			end
		end
	end

	local function playerInGroup()
		local groupId = Information.GroupId
		if typeof(groupId) ~= "number" then
			return false
		end
		local ok, result = pcall(function()
			return Information:IsInGroup(LocalPlayer, groupId)
		end)
		if ok and result == true then
			return true
		end
		local ok2, result2 = pcall(function()
			return LocalPlayer:IsInGroup(groupId)
		end)
		return ok2 and result2 == true
	end

	local function claimGroupRewards(data)
		if state.GroupRewards ~= true then
			return
		end
		if track.GroupRewardsClaimed == true then
			return
		end
		if data.ClaimedGroupRewards == true or data.GroupRewardsClaimed == true then
			track.GroupRewardsClaimed = true
			saveTrack(runtime)
			return
		end
		if not playerInGroup() then
			return
		end
		if fireNode("GROUP_REWARDS_CLAIM", "group:rewards") then
			track.GroupRewardsClaimed = true
			saveTrack(runtime)
		end
	end

	local function getLiveTournamentData()
		local ok, live = pcall(function()
			return peek(Dependencies.TournamentData)
		end)
		if ok and typeof(live) == "table" then
			return live
		end
		return {}
	end

	local function isTournamentSeasonEnded(tournamentId, season)
		local live = getLiveTournamentData()[tournamentId]
		if typeof(live) ~= "table" then
			return false
		end
		local currentSeason = tonumber(live.Season) or 1
		local endsAt = tonumber(live.EndsAt)
		local now = workspace:GetServerTimeNow()
		if season < currentSeason then
			return true
		end
		if season > currentSeason then
			return false
		end
		if not endsAt then
			return false
		end
		return endsAt <= now
	end

	local function claimTournamentRewards(data)
		if state.Tournament ~= true then
			return
		end
		local activeBrackets = data.TournamentData and data.TournamentData.ActiveBrackets
		if typeof(activeBrackets) ~= "table" then
			return
		end
		local now = workspace:GetServerTimeNow()
		local liveTournaments = getLiveTournamentData()
		for tournamentId, seasons in activeBrackets do
			if typeof(seasons) == "table" then
				local live = liveTournaments[tournamentId]
				for seasonKey, bracket in seasons do
					if typeof(bracket) == "table" then
						local highestScore = tonumber(bracket.HighestScore) or 0
						local rewardClaimed = bracket.RewardClaimed == true
						local season = tonumber(seasonKey)
						local blockKey = tostring(tournamentId) .. ":" .. tostring(season)
						local blockedUntil = tonumber(track.TournamentBlockedUntil[blockKey]) or 0
						if season and highestScore > 0 and not rewardClaimed and now >= blockedUntil then
							if isTournamentSeasonEnded(tournamentId, season) then
								fireNode("TOURNAMENT_CLAIM_SEASON_REWARD", "tournament:" .. blockKey, tournamentId, season)
							elseif typeof(live) == "table" and tonumber(live.EndsAt) then
								track.TournamentBlockedUntil[blockKey] = tonumber(live.EndsAt)
								saveTrack(runtime)
							else
								track.TournamentBlockedUntil[blockKey] = now + 300
								saveTrack(runtime)
							end
						end
					end
				end
			end
		end
	end

	local function getPreReleaseTotalTime(data)
		local eventData = data.EventData and data.EventData.PreRelease
		local totalTime = 0
		if typeof(eventData) == "table" then
			totalTime = tonumber(eventData.TotalTime) or 0
		end
		local session = getSessionData()
		local chamber = session.PreReleaseChamber
		if typeof(chamber) == "table" then
			local startTime = tonumber(chamber.StartTime)
			if startTime then
				totalTime = totalTime + math.max(workspace:GetServerTimeNow() - startTime, 0)
			end
		end
		return totalTime
	end

	local function hasEarlyAccessPlus(data)
		local titles = data.Titles or data.TitleData
		if typeof(titles) == "table" and titles.EarlyAccessPlusTitle then
			return true
		end
		local ok, titleData = pcall(function()
			return peek(Dependencies.TitleData)
		end)
		if ok and typeof(titleData) == "table" and titleData.EarlyAccessPlusTitle then
			return true
		end
		return false
	end

	local function claimAfkMilestones(data)
		if state.AfkMilestones ~= true then
			return
		end
		local eventInfo = Information.Events and Information.Events.PreRelease
		if not eventInfo or typeof(eventInfo.Milestones) ~= "table" then
			return
		end
		local eventData = data.EventData and data.EventData.PreRelease
		if typeof(eventData) ~= "table" then
			eventData = {}
		end
		local claimed = typeof(eventData.ClaimedMilestones) == "table" and eventData.ClaimedMilestones or {}
		local totalTime = getPreReleaseTotalTime(data)
		local earlyAccessPlus = hasEarlyAccessPlus(data)
		for index, milestone in eventInfo.Milestones do
			if typeof(milestone) == "table" then
				local requiredTime = tonumber(milestone.Time) or 0
				local claimedKey = tostring(index)
				local alreadyClaimed = claimed[claimedKey] == true or claimed[index] == true
				local unlocked = earlyAccessPlus or totalTime >= requiredTime
				if unlocked and not alreadyClaimed then
					fireNode("PRE_RELEASE_CLAIM_MILESTONE", "afk:milestone:" .. claimedKey, index)
				end
			end
		end
	end

	local function getVillainHuntProgress(data)
		local eventData = data.EventData and data.EventData.VillainHunt
		if typeof(eventData) == "table" then
			local totalClears = tonumber(eventData.TotalClears)
			if totalClears then
				return totalClears
			end
		end
		local trackCounter = data.TrackCounter and data.TrackCounter.VillainHunt
		if typeof(trackCounter) == "table" then
			local expiresAt = tonumber(trackCounter.ExpiresAt) or 0
			if expiresAt >= workspace:GetServerTimeNow() then
				return tonumber(trackCounter.Count) or 0
			end
		end
		return 0
	end

	local function claimVillainHuntMilestones(data)
		if state.VillainHunt ~= true then
			return
		end
		local eventInfo = Information.Events and Information.Events.VillainHunt
		if not eventInfo or typeof(eventInfo.Milestones) ~= "table" then
			return
		end
		local eventData = data.EventData and data.EventData.VillainHunt
		if typeof(eventData) ~= "table" then
			eventData = {}
		end
		local claimed = typeof(eventData.ClaimedMilestones) == "table" and eventData.ClaimedMilestones or {}
		local progress = getVillainHuntProgress(data)
		local hasClaimable = false
		for threshold in eventInfo.Milestones do
			local need = tonumber(threshold)
			if need and progress >= need then
				local key = tostring(need)
				if claimed[key] ~= true and claimed[need] ~= true then
					hasClaimable = true
					break
				end
			end
		end
		if not hasClaimable or not canFire("villainhunt:milestones") then
			return
		end
		local claimedOk = false
		if pcall(function()
			Actions.VillainHunt_ClaimMilestones()
		end) then
			claimedOk = true
		elseif pcall(function()
			Nodes.VILLAIN_HUNT_CLAIM_MILESTONES:FireServer()
		end) then
			claimedOk = true
		end
		if claimedOk then
			print("[AEHub:AutoClaim] VillainHunt milestones")
		end
	end

	local function claimPromoCodes()
		if state.PromoCodes ~= true then
			return
		end
		local codes = Information.Codes and Information.Codes.Codes
		if typeof(codes) ~= "table" then
			return
		end
		for codeName, codeInfo in codes do
			if typeof(codeName) == "string" and isCodeCurrentlyValid(codeInfo) and not isCodeRedeemed(codeName) then
				local key = "code:" .. normalizeCode(codeName)
				if canFire(key) then
					local ok, result = pcall(function()
						local request = Nodes.CLAIM_CODE:Request(codeName)
						if typeof(request) == "table" and typeof(request.Timeout) == "function" then
							request:Timeout(5)
						end
						if typeof(request) == "table" and typeof(request.Wait) == "function" then
							return request:Wait()
						end
						return request
					end)

					local success = false
					local already = false
					if ok then
						if result == true or result == "Success" or result == "success" then
							success = true
						elseif typeof(result) == "table" then
							if result.Success == true or result.success == true or result.Ok == true or result[1] == true then
								success = true
							end
							local message = tostring(result.Message or result.Error or result[1] or "")
							local lower = string.lower(message)
							if string.find(lower, "already", 1, true)
								or string.find(lower, "redeemed", 1, true)
								or string.find(lower, "claimed", 1, true)
							then
								already = true
							end
						elseif typeof(result) == "string" then
							local lower = string.lower(result)
							if string.find(lower, "success", 1, true) then
								success = true
							elseif string.find(lower, "already", 1, true)
								or string.find(lower, "redeemed", 1, true)
								or string.find(lower, "claimed", 1, true)
							then
								already = true
							end
						end
					end

					if success or already then
						markCodeRedeemed(codeName)
						print(("[AEHub:AutoClaim] CLAIM_CODE | %s"):format(codeName))
					else
						warn(("[AEHub:AutoClaim] Code failed | %s | %s"):format(codeName, tostring(result)))
					end
				end
			end
		end
	end

	return function()
		if not runtime.Running or not runtime.Replica then
			return
		end
		local data = getData()
		claimQuests(data)
		claimIndex(data)
		claimCalendars(data)
		claimBattlepasses(data)
		claimLevelMilestones(data)
		claimExpeditionQuestBoard(data)
		claimExpeditionBuildingRewards(data)
		claimGroupRewards(data)
		claimTournamentRewards(data)
		claimAfkMilestones(data)
		claimVillainHuntMilestones(data)
		claimPromoCodes()
	end
end

return {
	Id = MODULE_ID,
	Name = "Auto Claim",
	Description = "Claims every claimable reward type when available.",
	Defaults = DEFAULTS,

	OnEnable = function(state, runtime, hub)
		if game.PlaceId ~= TARGET_PLACE_ID then
			Library.Notify(hub.Window, "Auto Claim", "Wrong place. Module stays idle here.")
			return
		end

		stopRuntime(runtime)
		runtime.Running = true
		runtime.Pending = {}
		loadTrack(runtime)

		local bootThread = task.spawn(function()
			local ReplicatedStorage = game:GetService("ReplicatedStorage")
			local Players = game:GetService("Players")
			runtime.LocalPlayer = Players.LocalPlayer

			if hub and typeof(hub.IsCurrent) == "function" and not hub:IsCurrent() then
				runtime.Running = false
				return
			end

			local okRequire, errRequire = pcall(function()
				runtime.Nodes = require(ReplicatedStorage:WaitForChild("Nodes", 15))
				runtime.Information = require(ReplicatedStorage:WaitForChild("Shared", 15):WaitForChild("Information", 15))
				local FusionPackage = ReplicatedStorage:WaitForChild("FusionPackage", 15)
				local Fusion = require(FusionPackage:WaitForChild("Fusion", 15))
				runtime.Dependencies = require(FusionPackage:WaitForChild("Dependencies", 15))
				runtime.Actions = require(FusionPackage:WaitForChild("Actions", 15))
				runtime.Peek = Fusion.peek
			end)
			if not okRequire then
				warn("[AEHub:AutoClaim] Require failed: " .. tostring(errRequire))
				runtime.Running = false
				return
			end

			local replica
			while runtime.Running and not replica do
				if hub and typeof(hub.IsCurrent) == "function" and not hub:IsCurrent() then
					runtime.Running = false
					return
				end
				local ok, result = pcall(function()
					return runtime.Nodes.GET_PLAYER_REPLICA:InvokeSelf()
				end)
				if ok then
					replica = result
				end
				if not replica then
					task.wait(0.25)
				end
			end
			if not runtime.Running then
				return
			end
			runtime.Replica = replica

			while runtime.Running and not next(runtime.Information.Quests.Categories) do
				task.wait(0.25)
			end
			if not runtime.Running then
				return
			end

			local scanAndClaim = createController(state, runtime)
			runtime.Scan = scanAndClaim

			if typeof(runtime.Replica.OnChange) == "function" then
				local conn = runtime.Replica:OnChange(function(_action, path)
					if not runtime.Running then
						return
					end
					if hub and typeof(hub.IsCurrent) == "function" and not hub:IsCurrent() then
						return
					end
					if typeof(path) == "table" then
						local root = path[1]
						if root == "QuestData"
							or root == "Index"
							or root == "CalendarData"
							or root == "BattlepassData"
							or root == "LevelMilestones"
							or root == "Level"
							or root == "ExpeditionData"
							or root == "EventData"
							or root == "TournamentData"
							or root == "TrackCounter"
							or root == "Titles"
							or root == "RedeemedCodes"
							or root == "ClaimedCodes"
							or root == "UsedCodes"
							or root == "Codes"
						then
							task.defer(scanAndClaim)
						end
					end
				end)
				runtime.ChangeConnection = conn
				if typeof(runtime.TrackConnection) == "function" then
					runtime:TrackConnection(conn)
				end
			end

			scanAndClaim()
			local pollThread = task.spawn(function()
				while runtime.Running do
					local interval = tonumber(state.PollInterval) or DEFAULTS.PollInterval
					task.wait(math.max(interval, 0.25))
					if not runtime.Running then
						break
					end
					if hub and typeof(hub.IsCurrent) == "function" and not hub:IsCurrent() then
						break
					end
					if game.PlaceId ~= TARGET_PLACE_ID then
						break
					end
					scanAndClaim()
				end
			end)
			runtime.PollThread = pollThread
			if typeof(runtime.TrackThread) == "function" then
				runtime:TrackThread(pollThread)
			end

			Library.Notify(hub.Window, "Auto Claim", "Enabled")
			print(("[AEHub:AutoClaim] Active on place %s"):format(tostring(TARGET_PLACE_ID)))
		end)

		runtime.BootThread = bootThread
		if typeof(runtime.TrackThread) == "function" then
			runtime:TrackThread(bootThread)
		end
	end,

	OnDisable = function(_state, runtime, hub)
		stopRuntime(runtime)
		Library.Notify(hub.Window, "Auto Claim", "Disabled")
	end,

	OnDestroy = function(_state, runtime)
		stopRuntime(runtime)
	end,

	AfterApplyState = function(state, hub)
		if state.Index == true and state.Achievements ~= true then
			state.Achievements = true
		end
		state.Enabled = anyCategoryEnabled(state)
		if hub and hub.Config then
			hub.Config.Values[MODULE_ID .. ".Enabled"] = state.Enabled
			hub.Config.Values[MODULE_ID .. ".Achievements"] = state.Achievements == true
		end
	end,

	OnConfigChanged = function(state, key, _value, hub)
		if key == "PollInterval" or key == "ClaimCooldown" or key == "Enabled" then
			return
		end
		syncPowerFromCategories(state, hub)
	end,

	BuildUi = function(state, _window, tabs, hub)
		local tab = tabs.Misc
		local left = tab:Section({ Side = "Left" })

		left:Header({ Text = "Auto Claim" })

		local categories = {
			{ "Quests", "Quests" },
			{ "Achievements", "Achievements" },
			{ "Calendar", "Calendar" },
			{ "Battlepass", "Battlepass" },
			{ "LevelMilestones", "Level Milestones" },
			{ "ExpeditionBoard", "Expedition Board" },
			{ "ExpeditionBuildings", "Expedition Buildings" },
			{ "GroupRewards", "Group Rewards" },
			{ "Tournament", "Tournament" },
			{ "AfkMilestones", "AFK Milestones" },
			{ "VillainHunt", "Villain Hunt" },
			{ "PromoCodes", "Promo Codes" },
		}

		for _, entry in categories do
			local key, label = entry[1], entry[2]
			hub.UI:BindToggle(left, {
				Name = label,
				Default = state[key] == true,
				Flag = MODULE_ID .. "." .. key,
			})
		end

		hub.UI:BindSlider(left, {
			Name = "Poll Interval",
			Default = tonumber(state.PollInterval) or 1,
			Minimum = 0.25,
			Maximum = 10,
			Precision = 2,
			DisplayMethod = "Round",
			Flag = MODULE_ID .. ".PollInterval",
		})

		hub.UI:BindSlider(left, {
			Name = "Claim Cooldown",
			Default = tonumber(state.ClaimCooldown) or 2,
			Minimum = 0.5,
			Maximum = 10,
			Precision = 2,
			DisplayMethod = "Round",
			Flag = MODULE_ID .. ".ClaimCooldown",
		})
	end,
}
