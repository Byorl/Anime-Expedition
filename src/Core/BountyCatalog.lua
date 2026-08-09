return function(Import)
	local JoinCatalog = Import("JoinCatalog")
	local BountyCatalog = {}

	local rarityRank = {Default = 0, Rare = 1, Epic = 2, Legendary = 3, Mythic = 4}

	local function friendly(value)
		value = tostring(value or "Unknown")
		value = string.gsub(value, "_", " ")
		value = string.gsub(value, "(%l)(%u)", "%1 %2")
		return value
	end

	local function sortedKeys(source)
		local output = {}
		for key in pairs(type(source) == "table" and source or {}) do table.insert(output, tostring(key)) end
		table.sort(output, function(a, b) return string.lower(a) < string.lower(b) end)
		return output
	end

	local function get(source, key)
		if type(source) ~= "table" then return nil end
		local value = source[key]
		local numeric = tonumber(key)
		if value == nil and numeric then value = source[numeric] end
		return value
	end

	local function orderedKeys(source, order)
		local output, seen = {}, {}
		for _, key in ipairs(type(order) == "table" and order or {}) do
			key = tostring(key)
			if get(source, key) ~= nil and not seen[key] then
				seen[key] = true
				table.insert(output, key)
			end
		end
		for _, key in ipairs(sortedKeys(source)) do
			if not seen[key] then table.insert(output, key) end
		end
		return output
	end

	local function selectedSet(value)
		local output = {}
		for key, selected in pairs(type(value) == "table" and value or {}) do
			local item = type(key) == "number" and selected or selected == true and key or nil
			if item ~= nil then output[string.lower(tostring(item))] = true end
		end
		return output
	end

	local function questDataCandidate(source)
		if type(source) ~= "table" then return nil end
		if type(source.BountyBoard) == "table" then return source end
		if type(source.QuestData) == "table" and type(source.QuestData.BountyBoard) == "table" then return source.QuestData end
		if type(source.Data) == "table" then
			if type(source.Data.BountyBoard) == "table" then return source.Data end
			if type(source.Data.QuestData) == "table" and type(source.Data.QuestData.BountyBoard) == "table" then
				return source.Data.QuestData
			end
		end
		return nil
	end

	local function questDataScore(source)
		local candidate = questDataCandidate(source)
		if not candidate then return nil, -1 end
		local category = candidate.BountyBoard
		local score = 1
		for _ in pairs(type(category.Quests) == "table" and category.Quests or {}) do score = score + 100 end
		for _ in ipairs(type(category.QuestOrder) == "table" and category.QuestOrder or {}) do score = score + 10 end
		if category.ClaimedAmount ~= nil then score = score + 1 end
		return candidate, score
	end

	function BountyCatalog.ResolveQuestData(...)
		local best, bestScore = nil, -1
		for index = 1, select("#", ...) do
			local candidate, score = questDataScore(select(index, ...))
			if candidate and score > bestScore then
				best = candidate
				bestScore = score
			end
		end
		return best
	end

	local function conditionValues(objective)
		local output = {}
		for _, condition in pairs(type(objective) == "table" and type(objective.Conditions) == "table" and objective.Conditions or {}) do
			if type(condition) == "table" and condition.ValueName ~= nil then
				output[tostring(condition.ValueName)] = condition.Value
			end
		end
		return output
	end

	local function valueOf(objective, conditions, ...)
		for index = 1, select("#", ...) do
			local key = select(index, ...)
			local value = type(objective) == "table" and objective[key] or nil
			if value == nil then value = conditions[key] end
			if value ~= nil and tostring(value) ~= "" then return value end
		end
		return nil
	end

	local function numberValue(value)
		if type(value) == "number" then return value end
		if type(value) ~= "table" then return tonumber(value) end
		return tonumber(value.Progress or value.Value or value.Amount or value.Current or value.Count)
	end

	local function objectiveProgress(data, key, kind)
		local progress = type(data) == "table" and data.ObjectiveProgress or nil
		if type(progress) ~= "table" then return numberValue(progress) or 0 end
		return numberValue(get(progress, key)) or numberValue(progress[tostring(key)]) or numberValue(progress[kind]) or 0
	end

	local function objectiveLabel(kind, values)
		local gamemode = tostring(values.Gamemode or "")
		if kind == "ClearWave" and string.lower(gamemode) == "infinite" then return "Infinite Waves" end
		if kind == "FinishMap" and gamemode ~= "" then return friendly(gamemode) .. " Clears" end
		if kind == "Summon" then return "Summons" end
		if kind == "Takedowns" and string.lower(tostring(values.EnemyTypeKey or "")) == "boss" then return "Boss Takedowns" end
		return friendly(kind)
	end

	local function objectiveRecord(key, info, data)
		local conditions = conditionValues(info)
		local values = {
			Gamemode = valueOf(info, conditions, "Gamemode", "GameMode"),
			MapName = valueOf(info, conditions, "MapName", "Map"),
			ActName = valueOf(info, conditions, "ActName", "Act"),
			Difficulty = valueOf(info, conditions, "Difficulty"),
			ChallengeType = valueOf(info, conditions, "ChallengeType"),
			ChallengeIndex = valueOf(info, conditions, "ChallengeIndex", "Index"),
			EnemyTypeKey = valueOf(info, conditions, "EnemyTypeKey", "EnemyType"),
		}
		local kind = tostring(type(info) == "table" and (info.Type or info.ObjectiveType) or key)
		if kind == "ClearWave" and values.Gamemode == nil then values.Gamemode = "Infinite" end
		local goal = math.max(1, tonumber(type(info) == "table" and info.Goal) or 1)
		local progress = math.max(0, objectiveProgress(data, key, kind))
		return {
			Key = tostring(key),
			Type = kind,
			Label = objectiveLabel(kind, values),
			Description = tostring(type(info) == "table" and info.Description or ""),
			Goal = goal,
			Progress = progress,
			Completed = progress >= goal,
			Gamemode = values.Gamemode and tostring(values.Gamemode) or nil,
			MapName = values.MapName and tostring(values.MapName) or nil,
			ActName = values.ActName and tostring(values.ActName) or nil,
			Difficulty = values.Difficulty and tostring(values.Difficulty) or nil,
			ChallengeType = values.ChallengeType and tostring(values.ChallengeType) or nil,
			ChallengeIndex = tonumber(values.ChallengeIndex) or values.ChallengeIndex,
		}
	end

	function BountyCatalog.Category(questData)
		local resolved = BountyCatalog.ResolveQuestData(questData)
		return resolved and resolved.BountyBoard or {}
	end

	function BountyCatalog.HasCategory(questData)
		return BountyCatalog.ResolveQuestData(questData) ~= nil
	end

	function BountyCatalog.Definitions(information)
		local quests = type(information) == "table" and information.Quests or nil
		quests = type(quests) == "table" and quests.Quests or nil
		return type(quests) == "table" and type(quests.BountyBoard) == "table" and quests.BountyBoard or {}
	end

	function BountyCatalog.Entries(information, questData)
		local category = BountyCatalog.Category(questData)
		local live = type(category.Quests) == "table" and category.Quests or {}
		local definitions = BountyCatalog.Definitions(information)
		local output = {}
		for _, key in ipairs(orderedKeys(live, category.QuestOrder)) do
			local liveData = get(live, key)
			local definition = get(definitions, key)
			local data = type(liveData) == "table" and liveData or {}
			local info = type(definition) == "table" and definition or {}
			local objectives = {}
			for _, objectiveKey in ipairs(sortedKeys(info.Objectives)) do
				table.insert(objectives, objectiveRecord(objectiveKey, get(info.Objectives, objectiveKey), data))
			end
			if data.Completed == true then
				for _, objective in ipairs(objectives) do
					objective.Completed = true
					objective.Progress = math.max(objective.Progress, objective.Goal)
				end
			end
			local completed = data.Completed == true
			if not completed and #objectives > 0 then
				completed = true
				for _, objective in ipairs(objectives) do
					if not objective.Completed then completed = false break end
				end
			end
			table.insert(output, {
				Key = key,
				Name = tostring(info.DisplayName or info.Name or key),
				Rarity = tostring(info.Rarity or (type(info.Info) == "table" and info.Info.Rarity) or "Default"),
				Completed = completed,
				Claimed = data.Claimed == true,
				Objectives = objectives,
				Data = data,
				Info = info,
			})
		end
		return output
	end

	function BountyCatalog.Options(entries, information)
		local rarities, types, seenRarities, seenTypes = {}, {}, {}, {}
		local function add(entry)
			local rarity = tostring(entry.Rarity or "Default")
			if not seenRarities[string.lower(rarity)] then
				seenRarities[string.lower(rarity)] = true
				table.insert(rarities, rarity)
			end
			for _, objective in ipairs(type(entry.Objectives) == "table" and entry.Objectives or {}) do
				local label = tostring(objective.Label)
				if not seenTypes[string.lower(label)] then
					seenTypes[string.lower(label)] = true
					table.insert(types, label)
				end
			end
		end
		for _, entry in ipairs(type(entries) == "table" and entries or {}) do add(entry) end
		for key, info in pairs(BountyCatalog.Definitions(information)) do
			local objectives = {}
			for objectiveKey, objective in pairs(type(info) == "table" and type(info.Objectives) == "table" and info.Objectives or {}) do
				table.insert(objectives, objectiveRecord(objectiveKey, objective, {}))
			end
			add({Rarity = type(info) == "table" and (info.Rarity or (type(info.Info) == "table" and info.Info.Rarity)) or "Default", Objectives = objectives})
		end
		table.sort(rarities, function(a, b)
			local left, right = rarityRank[a] or -1, rarityRank[b] or -1
			return left == right and a < b or left > right
		end)
		table.sort(types, function(a, b) return string.lower(a) < string.lower(b) end)
		if #rarities == 0 then rarities = {"Mythic", "Legendary", "Epic", "Rare"} end
		if #types == 0 then types = {"Infinite Waves", "Story Clears", "Raid Clears", "Challenge Clears", "Summons", "Boss Takedowns"} end
		return rarities, types
	end

	function BountyCatalog.Keep(entry, keepRarities, keepTypes, avoidTypes)
		local keepRaritySet = selectedSet(keepRarities)
		local keepTypeSet = selectedSet(keepTypes)
		local avoidTypeSet = selectedSet(avoidTypes)
		local hasKeptType = next(keepTypeSet) == nil
		for _, objective in ipairs(type(entry) == "table" and entry.Objectives or {}) do
			local key = string.lower(tostring(objective.Label))
			if avoidTypeSet[key] then return false, "avoided " .. tostring(objective.Label) end
			if keepTypeSet[key] then hasKeptType = true end
		end
		if next(keepRaritySet) ~= nil and not keepRaritySet[string.lower(tostring(entry.Rarity))] then
			return false, "rarity is not selected"
		end
		if not hasKeptType then return false, "objective type is not selected" end
		return true
	end

	function BountyCatalog.Targets(entry)
		local output, seen = {}, {}
		for _, objective in ipairs(type(entry) == "table" and entry.Objectives or {}) do
			if objective.Gamemode and objective.MapName then
				local key = string.lower(objective.Gamemode .. "|" .. objective.MapName)
				if not seen[key] then
					seen[key] = true
					table.insert(output, {Key = key, Gamemode = objective.Gamemode, MapName = objective.MapName})
				end
			end
		end
		return output
	end

	function BountyCatalog.StackTarget(entries)
		local groups = {}
		for _, entry in ipairs(type(entries) == "table" and entries or {}) do
			if not entry.Completed and not entry.Claimed then
				for _, target in ipairs(BountyCatalog.Targets(entry)) do
					local group = groups[target.Key] or {Count = 0, Target = target, Score = 0}
					group.Count = group.Count + 1
					group.Score = group.Score + (rarityRank[entry.Rarity] or 0)
					groups[target.Key] = group
				end
			end
		end
		local best
		for _, group in pairs(groups) do
			if not best or group.Count > best.Count or group.Count == best.Count and group.Score > best.Score then best = group end
		end
		return best
	end

	function BountyCatalog.HasTarget(entry, target)
		if not target then return false end
		for _, current in ipairs(BountyCatalog.Targets(entry)) do
			if current.Key == target.Key then return true end
		end
		return false
	end

	local function availableChallenge(information, playerData, challengeData, objective)
		if objective.ChallengeType and objective.ChallengeIndex then
			return JoinCatalog.ChallengeQueue(challengeData, objective.ChallengeType, objective.ChallengeIndex)
		end
		for _, challengeType in ipairs(JoinCatalog.ChallengeTypes(information)) do
			if objective.ChallengeType == nil or string.lower(challengeType) == string.lower(objective.ChallengeType) then
				for index = 1, JoinCatalog.ChallengeAmount(information, challengeType) do
					if JoinCatalog.ChallengeAvailable(information, playerData, challengeType, index) then
						local queue = JoinCatalog.ChallengeQueue(challengeData, challengeType, index)
						if queue then return queue end
					end
				end
			end
		end
		return nil
	end

	function BountyCatalog.QueueForObjective(information, playerData, challengeData, objective)
		if type(objective) ~= "table" or objective.Completed then return nil end
		local gamemode = tostring(objective.Gamemode or "")
		if string.lower(gamemode) == "challenge" then
			return availableChallenge(information, playerData, challengeData, objective)
		end
		if gamemode == "" or not objective.MapName then return nil end
		local acts = JoinCatalog.Acts(information, gamemode, objective.MapName)
		local difficulties = JoinCatalog.Difficulties(information, gamemode, objective.MapName)
		local queue = {
			Gamemode = gamemode,
			MapName = objective.MapName,
			Difficulty = objective.Difficulty or difficulties[1],
		}
		if string.lower(gamemode) ~= "infinite" then queue.ActName = objective.ActName or acts[1] end
		if not queue.Difficulty then return nil end
		if string.lower(gamemode) ~= "infinite" and not queue.ActName then return nil end
		if type(JoinCatalog.MapData(information, gamemode, objective.MapName)) ~= "table" then return nil end
		return queue
	end

	function BountyCatalog.JoinCandidate(information, playerData, challengeData, entries, target)
		local ranked = {}
		for _, entry in ipairs(type(entries) == "table" and entries or {}) do
			if not entry.Completed and not entry.Claimed then
				for _, objective in ipairs(entry.Objectives) do
					local matchesTarget = not target
						or objective.Gamemode and objective.MapName
						and string.lower(objective.Gamemode .. "|" .. objective.MapName) == target.Key
					local queue = matchesTarget and BountyCatalog.QueueForObjective(information, playerData, challengeData, objective) or nil
					if queue then
						table.insert(ranked, {Queue = queue, Objective = objective, Entry = entry, Rank = rarityRank[entry.Rarity] or 0})
					end
				end
			end
		end
		table.sort(ranked, function(a, b)
			if a.Rank ~= b.Rank then return a.Rank > b.Rank end
			return a.Entry.Key < b.Entry.Key
		end)
		return ranked[1]
	end

	local function findValue(source, names, depth, seen)
		if type(source) ~= "table" or depth <= 0 then return nil end
		seen = seen or {}
		if seen[source] then return nil end
		seen[source] = true
		for _, name in ipairs(names) do
			local value = source[name]
			if value ~= nil and type(value) ~= "table" and tostring(value) ~= "" then return value end
		end
		for _, child in pairs(source) do
			local value = findValue(child, names, depth - 1, seen)
			if value ~= nil then return value end
		end
		return nil
	end

	function BountyCatalog.CurrentQueue(gameData)
		if type(gameData) ~= "table" then return nil end
		local source = type(gameData.Parameters) == "table" and gameData.Parameters or gameData
		if type(source.QueueData) == "table" then source = source.QueueData end
		local gamemode = findValue(source, {"Gamemode", "GameMode", "Mode"}, 5)
		local mapName = findValue(source, {"MapName", "MapID", "MapId", "Map"}, 5)
		if not gamemode and not mapName then return nil end
		return {
			Gamemode = gamemode and tostring(gamemode) or nil,
			MapName = mapName and tostring(mapName) or nil,
			ActName = findValue(source, {"ActName", "StageName", "Act", "Stage"}, 5),
			Difficulty = findValue(source, {"Difficulty", "DifficultyName"}, 5),
			ChallengeType = findValue(source, {"ChallengeType"}, 5),
			ChallengeIndex = findValue(source, {"ChallengeIndex"}, 5),
		}
	end

	function BountyCatalog.MatchesQueue(objective, queue)
		if type(objective) ~= "table" or type(queue) ~= "table" then return false end
		if objective.Gamemode and string.lower(tostring(objective.Gamemode)) ~= string.lower(tostring(queue.Gamemode or "")) then return false end
		if objective.MapName and string.lower(tostring(objective.MapName)) ~= string.lower(tostring(queue.MapName or "")) then return false end
		if objective.ActName and string.lower(tostring(objective.ActName)) ~= string.lower(tostring(queue.ActName or "")) then return false end
		if objective.Difficulty and string.lower(tostring(objective.Difficulty)) ~= string.lower(tostring(queue.Difficulty or "")) then return false end
		return objective.Gamemode ~= nil or objective.MapName ~= nil
	end

	function BountyCatalog.BoardText(information, questData, gameData)
		local hasCategory = BountyCatalog.HasCategory(questData)
		local category = BountyCatalog.Category(questData)
		local entries = BountyCatalog.Entries(information, questData)
		local queue = BountyCatalog.CurrentQueue(gameData)
		local thisMap = "Not currently in a bounty map."
		if queue and queue.MapName then
			local map = JoinCatalog.MapDisplayName(information, queue.MapName)
			thisMap = tostring(queue.Gamemode or "Unknown") .. " / " .. map
			local found = false
			for _, entry in ipairs(entries) do
				for _, objective in ipairs(entry.Objectives) do
					if BountyCatalog.MatchesQueue(objective, queue) then found = true break end
				end
				if found then break end
			end
			if not found then thisMap = thisMap .. "\nNo bounty objective on this map." end
		end
		local lines = {}
		if hasCategory then
			table.insert(lines, string.format("Claims used today: %d/10", math.max(0, math.floor(tonumber(category.ClaimedAmount) or 0))))
		else
			table.insert(lines, "Bounty data is still syncing...")
		end
		local stack = BountyCatalog.StackTarget(entries)
		if stack then
			table.insert(lines, string.format("Stacked on %s / %s - %d bounty(s)", stack.Target.Gamemode, JoinCatalog.MapDisplayName(information, stack.Target.MapName), stack.Count))
		end
		table.insert(lines, string.format("%d bounty(s)", #entries))
		for _, entry in ipairs(entries) do
			local objectiveNames = {}
			for _, objective in ipairs(entry.Objectives) do table.insert(objectiveNames, objective.Label) end
			table.insert(lines, string.format("- %s - %s", entry.Rarity, #objectiveNames > 0 and table.concat(objectiveNames, " + ") or entry.Name))
			for _, objective in ipairs(entry.Objectives) do
				local mark = objective.Completed and "[x]" or "[]"
				local target = objective.Label
				if objective.Gamemode then target = objective.Gamemode end
				if objective.MapName then target = target .. " / " .. JoinCatalog.MapDisplayName(information, objective.MapName) end
				table.insert(lines, string.format("  - %s %s - %d/%d", mark, target, objective.Progress, objective.Goal))
			end
		end
		return thisMap, table.concat(lines, "\n"), entries
	end

	return BountyCatalog
end
