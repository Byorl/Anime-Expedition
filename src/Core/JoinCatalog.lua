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
		local maps = type(information) == "table" and information.Maps or nil
		local preview = type(maps) == "table" and maps.PreviewInfo or nil
		local info = type(preview) == "table" and preview[mapName] or nil
		local name = type(info) == "table" and (info.DisplayName or info.Name) or mapName
		return string.format("%s [%s]", tostring(name), tostring(mapName))
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

	function JoinCatalog.ChallengeQueue(challengeData, challengeType, index)
		local entries = type(challengeData) == "table" and challengeData[challengeType] or nil
		local data = type(entries) == "table" and (entries[index] or entries[tostring(index)]) or nil
		if type(data) ~= "table" then return nil end
		return {
			Gamemode = "Challenge",
			ChallengeType = challengeType,
			ChallengeIndex = tostring(index),
			MapName = data.MapName,
			ActName = data.ActName,
			Difficulty = data.Difficulty,
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
