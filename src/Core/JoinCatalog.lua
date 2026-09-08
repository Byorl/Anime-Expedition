return function(Import)
	local AutomationCatalog = Import("AutomationCatalog")
	local JoinCatalog = {}

	local function sortedKeys(source)
		local output = {}
		for key in pairs(type(source) == "table" and source or {}) do table.insert(output, tostring(key)) end
		table.sort(output, function(a, b) return string.lower(a) < string.lower(b) end)
		return output
	end

	local function call(object, method, ...)
		if type(object) ~= "table" or type(object[method]) ~= "function" then return nil end
		local arguments = table.pack(...)
		local ok, result = pcall(function()
			return object[method](object, table.unpack(arguments, 1, arguments.n))
		end)
		if ok then return result end
		return nil
	end

	local function unique(values)
		local output, seen = {}, {}
		for _, value in ipairs(type(values) == "table" and values or {}) do
			value = tostring(value)
			local key = string.lower(value)
			if value ~= "" and not seen[key] then seen[key] = true table.insert(output, value) end
		end
		return output
	end

	function JoinCatalog.MapKeys(information, gamemode)
		local maps = type(information) == "table" and information.Maps or nil
		local ordered = call(maps, "GetOrderedMaps", gamemode)
		if type(ordered) == "table" and #ordered > 0 then return unique(ordered) end
		local data = type(maps) == "table" and maps.MapData or nil
		return sortedKeys(type(data) == "table" and data[gamemode] or {})
	end

	function JoinCatalog.MapData(information, gamemode, mapName)
		local maps = type(information) == "table" and information.Maps or nil
		return call(maps, "GetMapData", gamemode, mapName)
	end

	function JoinCatalog.MapLabel(information, mapName)
		return string.format("%s [%s]", JoinCatalog.MapDisplayName(information, mapName), tostring(mapName))
	end

	function JoinCatalog.MapDisplayName(information, mapName)
		if mapName == nil or tostring(mapName) == "" then return "Unknown" end
		local maps = type(information) == "table" and information.Maps or nil
		local preview = type(maps) == "table" and maps.PreviewInfo or nil
		local info = type(preview) == "table" and preview[mapName] or nil
		return tostring(type(info) == "table" and (info.DisplayName or info.Name) or mapName)
	end

	function JoinCatalog.MapOptions(information, gamemode)
		local output = {Options = {}, ByLabel = {}, ByKey = {}}
		for _, key in ipairs(JoinCatalog.MapKeys(information, gamemode)) do
			local label = JoinCatalog.MapLabel(information, key)
			table.insert(output.Options, label)
			output.ByLabel[label] = key
			output.ByKey[key] = label
		end
		return output
	end

	function JoinCatalog.Acts(information, gamemode, mapName)
		local data = JoinCatalog.MapData(information, gamemode, mapName)
		local values = type(data) == "table" and data.ActProgression or nil
		local output = {}
		for _, value in ipairs(type(values) == "table" and values or {}) do table.insert(output, tostring(value)) end
		if #output == 0 and type(data) == "table" and type(data.Acts) == "table" then
			output = sortedKeys(data.Acts)
		end
		return unique(output)
	end

	function JoinCatalog.Difficulties(information, gamemode, mapName)
		local data = JoinCatalog.MapData(information, gamemode, mapName)
		local values = type(data) == "table" and data.Difficulties or nil
		local output = unique(values)
		if #output == 0 then
			local maps = type(information) == "table" and information.Maps or nil
			local types = type(maps) == "table" and maps.GamemodeTypes or nil
			local kind = type(types) == "table" and types[gamemode] or nil
			local value = type(kind) == "table" and type(kind.Config) == "table" and kind.Config.Difficulty or nil
			if value then table.insert(output, tostring(value)) end
		end
		return output
	end

	function JoinCatalog.Stages(information, mapName)
		local values = JoinCatalog.Acts(information, "Story", mapName)
		local maps = type(information) == "table" and information.Maps or nil
		local data = type(maps) == "table" and maps.MapData or nil
		if type(data) == "table" and type(data.Infinite) == "table" and data.Infinite[mapName] then table.insert(values, "Infinite") end
		if type(data) == "table" and type(data.Mastery) == "table" and data.Mastery[mapName] then table.insert(values, "Mastery") end
		return unique(values)
	end

	function JoinCatalog.StoryQueue(information, mapName, stage, difficulty)
		local gamemode, actName = "Story", stage
		if stage == "Infinite" then gamemode, actName = "Infinite", nil end
		if stage == "Mastery" then
			gamemode = "Mastery"
			actName = JoinCatalog.Acts(information, gamemode, mapName)[1]
		end
		local queue = {Gamemode = gamemode, MapName = mapName, Difficulty = difficulty}
		if actName then queue.ActName = actName end
		return queue
	end

	function JoinCatalog.ChallengeTypes(information)
		local challenge = type(information) == "table" and information.ChallengeInfo or nil
		local info = type(challenge) == "table" and challenge.Info or nil
		local entries = {}
		for key, value in pairs(type(info) == "table" and info or {}) do
			table.insert(entries, {Key = tostring(key), Refresh = tonumber(type(value) == "table" and value.RefreshTime) or math.huge})
		end
		table.sort(entries, function(a, b) return a.Refresh == b.Refresh and a.Key < b.Key or a.Refresh < b.Refresh end)
		local output = {}
		for _, entry in ipairs(entries) do table.insert(output, entry.Key) end
		return output
	end

	function JoinCatalog.ChallengeAmount(information, challengeType)
		local challenge = type(information) == "table" and information.ChallengeInfo or nil
		local info = type(challenge) == "table" and challenge.Info or nil
		return math.max(0, math.floor(tonumber(type(info) == "table" and type(info[challengeType]) == "table" and info[challengeType].Amount) or 0))
	end

	function JoinCatalog.ChallengeAvailable(information, playerData, challengeType, index, now)
		local challenge = type(information) == "table" and information.ChallengeInfo or nil
		local data = type(playerData) == "table" and playerData.ChallengeData or nil
		if type(challenge) ~= "table" or type(challenge.IsChallengeAvailable) ~= "function" then return false end
		local ok, available = pcall(challenge.IsChallengeAvailable, challenge,
			type(data) == "table" and type(data.ClearHistory) == "table" and data.ClearHistory[challengeType] or {},
			type(data) == "table" and type(data.DailyClearHistory) == "table" and data.DailyClearHistory[challengeType] or {},
			challengeType, index, now or os.time())
		return ok and available == true
	end

	local function collectAssets(value, output, seen, depth)
		if depth > 5 or type(value) ~= "table" then return end
		local asset = value.Asset or value.Item or value.Unit or value.Reward
		if type(asset) == "string" and asset ~= "" and not seen[asset] then
			seen[asset] = true
			table.insert(output, asset)
		end
		for key, child in pairs(value) do
			if type(child) == "table" and key ~= "MapInfo" and key ~= "ActInfo" then collectAssets(child, output, seen, depth + 1) end
		end
	end

	function JoinCatalog.ChallengeDrops(information, challengeData)
		local assets, seen = {}, {}
		local stageDrops = type(information) == "table" and information.StageDrops or nil
		collectAssets(type(stageDrops) == "table" and stageDrops.Entries or nil, assets, seen, 0)
		for challengeType, entries in pairs(type(challengeData) == "table" and challengeData or {}) do
			for index in pairs(type(entries) == "table" and entries or {}) do
				local drops = call(stageDrops, "GetDrops", {Gamemode = "Challenge", ChallengeType = challengeType, ChallengeIndex = index})
				collectAssets(drops, assets, seen, 0)
			end
		end
		table.sort(assets, function(a, b)
			local left = AutomationCatalog.UnitName(information, {Asset = a})
			local right = AutomationCatalog.UnitName(information, {Asset = b})
			return string.lower(left) < string.lower(right)
		end)
		local result = {Options = {"Any drop"}, ByLabel = {['Any drop'] = nil}, ByKey = {}}
		for _, asset in ipairs(assets) do
			local name = AutomationCatalog.UnitName(information, {Asset = asset})
			local label = string.format("%s [%s]", name, asset)
			table.insert(result.Options, label)
			result.ByLabel[label] = asset
			result.ByKey[asset] = label
		end
		return result
	end

	function JoinCatalog.ChallengeHasDrop(information, challengeType, index, wanted)
		if wanted == nil or wanted == "" then return true end
		local stageDrops = type(information) == "table" and information.StageDrops or nil
		local drops = call(stageDrops, "GetDrops", {Gamemode = "Challenge", ChallengeType = challengeType, ChallengeIndex = index})
		local assets = {}
		collectAssets(drops, assets, {}, 0)
		return table.find(assets, wanted) ~= nil
	end

	function JoinCatalog.ChallengeHasSelectedDrop(information, challengeType, index, wanted)
		if type(wanted) ~= "table" or next(wanted) == nil then return true end
		for asset, selected in pairs(wanted) do
			if selected == true and JoinCatalog.ChallengeHasDrop(information, challengeType, index, asset) then return true end
		end
		return false
	end

	function JoinCatalog.ChallengeQueue(challengeData, challengeType, index)
		local entries = type(challengeData) == "table" and challengeData[challengeType] or nil
		local data = type(entries) == "table" and (entries[index] or entries[tostring(index)]) or nil
		if type(data) ~= "table" then return nil end
		return {
			Gamemode = "Challenge",
			ChallengeType = challengeType,
			ChallengeIndex = tonumber(index) or index,
			MapName = data.MapName,
			ActName = data.ActName,
			Difficulty = data.Difficulty,
		}
	end

	-- Limited events are data-driven: each entry under Information.Events that
	-- carries a QueueData table can be queued verbatim (Tidal Siege, Bingo,
	-- creator spotlights, expedition-variant events like MASTRR/TrunksEVO).
	function JoinCatalog.Events(information)
		local events = type(information) == "table" and information.Events or nil
		local now = workspace:GetServerTimeNow()
		local entries = {}
		for eventId, event in pairs(type(events) == "table" and events or {}) do
			if type(event) == "table" and type(event.QueueData) == "table" and event.QueueData.Gamemode then
				local scheduled = true
				for _, schedule in ipairs(type(event.Schedule) == "table" and event.Schedule or {}) do
					local endTime = tonumber(schedule.EndTime)
					if endTime == nil or endTime > now then
						scheduled = false
						break
					end
				end
				table.insert(entries, {
					Key = tostring(eventId),
					Label = string.format("%s [%s]", tostring(event.DisplayName or eventId), tostring(eventId)),
					QueueData = event.QueueData,
					DisplayName = tostring(event.DisplayName or eventId),
					Scheduled = scheduled,
					Order = tonumber(event.LayoutOrder) or math.huge,
				})
			end
		end
		table.sort(entries, function(a, b)
			if a.Scheduled ~= b.Scheduled then return not a.Scheduled end
			if a.Order ~= b.Order then return a.Order < b.Order end
			return string.lower(a.DisplayName) < string.lower(b.DisplayName)
		end)
		local result = {Options = {}, ByLabel = {}, ByKey = {}, Entries = entries}
		for _, entry in ipairs(entries) do
			table.insert(result.Options, entry.Label)
			result.ByLabel[entry.Label] = entry.Key
			result.ByKey[entry.Key] = entry.Label
		end
		return result
	end

	function JoinCatalog.EventQueue(eventEntry)
		local entry = type(eventEntry) == "table" and eventEntry or nil
		if entry == nil then return nil end
		local queue = entry.QueueData
		if type(queue) ~= "table" or type(queue.Gamemode) ~= "string" or queue.Gamemode == "" then
			return nil
		end
		-- Copy so downstream consumers never mutate the shared information table.
		local output = {}
		for key, value in pairs(queue) do output[key] = value end
		return output
	end

	-- Expeditions queue with a numeric DifficultyLevel (1-3); the string
	-- Difficulties list on the map data ("Normal", "Hard") is presentation only.
	function JoinCatalog.ExpeditionLevels(information, mapName)
		local data = JoinCatalog.MapData(information, "Expedition", mapName)
		local difficulties = type(data) == "table" and data.Difficulties or nil
		local count = #unique(difficulties)
		if count <= 0 then count = 3 end
		return math.clamp(count, 1, 3)
	end

	function JoinCatalog.ExpeditionQueue(information, mapName, level)
		if type(mapName) ~= "string" or mapName == "" then return nil end
		local levelNumber = math.clamp(math.floor(tonumber(level) or 1), 1, JoinCatalog.ExpeditionLevels(information, mapName))
		local difficulties = unique(type(JoinCatalog.MapData(information, "Expedition", mapName)) == "table"
			and JoinCatalog.MapData(information, "Expedition", mapName).Difficulties or nil)
		return {
			Gamemode = "Expedition",
			MapName = mapName,
			Difficulty = difficulties[levelNumber] or difficulties[#difficulties] or "Hard",
			DifficultyLevel = levelNumber,
		}
	end

	function JoinCatalog.QueueUnlocked(information, playerData, queue)
		if type(queue) ~= "table" or not queue.Gamemode or not queue.MapName then return false end
		if queue.Gamemode == "Challenge" then return true end
		local maps = type(information) == "table" and information.Maps or nil
		local completed = type(playerData) == "table" and playerData.CompletedMaps or {}
		local mapData = JoinCatalog.MapData(information, queue.Gamemode, queue.MapName)
		if type(mapData) ~= "table" then return false end
		local types = type(maps) == "table" and maps.GamemodeTypes or nil
		local kind = type(types) == "table" and types[queue.Gamemode] or nil
		local requiredLevel = tonumber(type(kind) == "table" and kind.RequiredLevel)
		if requiredLevel and (tonumber(type(playerData) == "table" and playerData.Level) or 0) < requiredLevel then return false end
		if type(kind) == "table" and kind.RequiresMapProgression and call(maps, "HasMapUnlocked", completed, queue.Gamemode, queue.MapName) ~= true then return false end
		if type(kind) == "table" and kind.RequiresActProgression and queue.ActName and call(maps, "HasActUnlocked", completed, queue.Gamemode, queue.MapName, queue.ActName, queue.Difficulty) ~= true then return false end
		return true
	end

	return JoinCatalog
end
