return function()
	--[[
		WaveIndex: normalizes the wave scripts every map ships to the client
		(Maps.<Gamemode>.<Map>.Waves / HordeWaves / TempestHordeWaves) into a
		per-wave forecast schedule for the smart planner.

		Known spawn-group shape (verified against the Summer Update extraction):
		  { Type = "Basic 1" | "Elite 2" | "Boss 1" | ..., Count = n,
		    Shield = n?, Path = 1|2?, Modifiers = { "Stunner", ... }? }
		Wave tables come in two shapes:
		  flat:   waves[n] = { group, group, ... }
		  batched: waves[n] = { { group, ... }, { group, ... } }   (per side/batch)
		Both are flattened; the batched shape's batches are aggregated because
		spawn side semantics are server-side, but explicit Path fields on groups
		are preserved for lane weighting.

		The schedule is a planning prior: server-side rolls and difficulty
		scaling can deviate. The planner keeps the live snapshot authoritative.
	]]
	local WaveIndex = {}

	local TIER_WEIGHT = { Basic = 1, Flying = 1.2, Elite = 3, Boss = 9 }
	local MECHANIC_WEIGHT = {
		Stunner = 1.5,
		Burrowing = 1.4,
		Stationary = 0.5,
		Shield = 1.2,
		HealAndCleanseOnWet = 2.2,
		WetAura = 1.3,
		WetGrenadier = 1.2,
	}
	local DEFAULT_MECHANIC_WEIGHT = 1.2

	local function tierOf(enemyType)
		return string.match(tostring(enemyType or ""), "^(%a+)%s*%d*") or tostring(enemyType or "Basic")
	end

	local function isGroup(value)
		return type(value) == "table" and type(value.Type) == "string" and type(value.Count) ~= "table"
	end

	local function mechanicWeight(modifiers)
		local weight = 1
		for _, name in ipairs(type(modifiers) == "table" and modifiers or {}) do
			weight = math.max(weight, MECHANIC_WEIGHT[name] or DEFAULT_MECHANIC_WEIGHT)
		end
		return weight
	end

	local function normalizeWave(index, rawWave)
		local groups = {}
		local laneCounts = {}
		local bossCount, eliteCount, basicCount = 0, 0, 0
		local shieldTotal = 0
		local threat = 0
		local mechanics = {}

		local function addGroup(group)
			local count = math.max(0, math.floor(tonumber(group.Count) or 0))
			if count <= 0 then return end
			local tier = tierOf(group.Type)
			local tierWeight = TIER_WEIGHT[tier] or 1.5
			local shield = math.max(0, tonumber(group.Shield) or 0)
			local weight = mechanicWeight(group.Modifiers)

			threat = threat + count * tierWeight * weight + count * shield * 0.35
			if tier == "Boss" then bossCount = bossCount + count end
			if tier == "Elite" then eliteCount = eliteCount + count end
			if tier == "Basic" or tier == "Flying" then basicCount = basicCount + count end
			shieldTotal = shieldTotal + shield * count

			local lane = tonumber(group.Path)
			if lane then
				laneCounts[lane] = (laneCounts[lane] or 0) + count * tierWeight
			end
			for _, name in ipairs(type(group.Modifiers) == "table" and group.Modifiers or {}) do
				if type(name) == "string" then mechanics[name] = true end
			end
			table.insert(groups, {
				Type = group.Type,
				Tier = tier,
				Count = count,
				Shield = shield,
				Path = lane,
				Modifiers = type(group.Modifiers) == "table" and group.Modifiers or nil,
			})
		end

		if isGroup(rawWave) then
			addGroup(rawWave)
		else
			for _, entry in ipairs(type(rawWave) == "table" and rawWave or {}) do
				if isGroup(entry) then
					addGroup(entry)
				elseif type(entry) == "table" then
					for _, group in ipairs(entry) do
						if isGroup(group) then addGroup(group) end
					end
				end
			end
		end

		local mechanicList = {}
		for name in pairs(mechanics) do table.insert(mechanicList, name) end
		table.sort(mechanicList)

		return {
			Index = index,
			Groups = groups,
			Threat = threat,
			Boss = bossCount > 0,
			BossCount = bossCount,
			EliteCount = eliteCount,
			BasicCount = basicCount,
			ShieldTotal = shieldTotal,
			Mechanics = mechanicList,
			LaneCounts = laneCounts,
			TotalEnemies = basicCount + eliteCount + bossCount,
		}
	end

	local function normalizeWaveTable(source)
		local waves = {}
		if type(source) ~= "table" then return waves end
		for index, rawWave in pairs(source) do
			local numericIndex = tonumber(index)
			if numericIndex and type(rawWave) == "table" then
				table.insert(waves, normalizeWave(math.floor(numericIndex), rawWave))
			end
		end
		table.sort(waves, function(a, b) return a.Index < b.Index end)
		return waves
	end

	local function resolveMapData(information, gamemode, mapName)
		local maps = type(information) == "table" and information.Maps or nil
		if type(maps) ~= "table" then return nil end
		if type(maps.GetMapData) == "function" then
			local ok, data = pcall(maps.GetMapData, maps, gamemode, mapName)
			if ok and type(data) == "table" then return data end
		end
		local byGamemode = type(maps.MapData) == "table" and maps.MapData[gamemode] or nil
		if type(byGamemode) == "table" then
			return byGamemode[mapName] or byGamemode[tostring(mapName)]
		end
		return nil
	end

	local function highestWaveIndex(waves)
		local highest = 0
		for _, wave in ipairs(waves) do
			highest = math.max(highest, wave.Index)
		end
		return highest
	end

	-- Builds (and describes) the schedule for one map. Returns nil when the
	-- map does not ship wave data; the planner then behaves exactly as before.
	function WaveIndex.ForMap(information, gamemode, mapName)
		if type(gamemode) ~= "string" or type(mapName) ~= "string" then return nil end
		local data = resolveMapData(information, gamemode, mapName)
		if type(data) ~= "table" or type(data.Waves) ~= "table" then return nil end

		local waves = normalizeWaveTable(data.Waves)
		if #waves == 0 then return nil end

		local horde = nil
		if data.HordeWaves ~= nil or tonumber(data.HordeInterval) ~= nil then
			horde = {
				Interval = math.max(1, math.floor(tonumber(data.HordeInterval) or 20)),
				WarnWaves = math.max(1, math.floor(tonumber(data.HordeWarnWaves) or 5)),
				DurationWaves = math.max(1, math.floor(tonumber(data.StormDurationWaves) or 5)),
				Waves = normalizeWaveTable(data.HordeWaves),
				TempestWaves = normalizeWaveTable(data.TempestHordeWaves),
			}
		end

		return {
			Key = gamemode .. "|" .. mapName,
			Gamemode = gamemode,
			MapName = mapName,
			Waves = waves,
			TotalWaves = highestWaveIndex(waves),
			Horde = horde,
			EnemyTypes = type(data.EnemyTypes) == "table" and data.EnemyTypes or nil,
		}
	end

	-- Forecast for the planner: distances from the current wave to the next
	-- notable event, plus a per-lane weight for upcoming threat. All fields
	-- are nil/1 when the schedule is unknown, so the planner is unchanged.
	function WaveIndex.Forecast(schedule, currentWave, pathCount)
		local forecast = {
			Known = false,
			NextBossIn = nil,
			NextShieldIn = nil,
			NextHordeIn = nil,
			ThreatRamp = 1,
			BossSoon = false,
			ShieldSoon = false,
			LaneWeight = nil,
		}
		if type(schedule) ~= "table" or type(schedule.Waves) ~= "table" then
			return forecast
		end
		forecast.Known = true
		currentWave = math.max(0, math.floor(tonumber(currentWave) or 0))

		local upcomingThreat, currentThreat = 0, 0
		for offset = 0, 3 do
			local wave = schedule.Waves[currentWave + offset]
			if wave then
				if offset == 0 then currentThreat = wave.Threat end
				if offset >= 1 then
					upcomingThreat = upcomingThreat + wave.Threat
					if forecast.NextBossIn == nil and wave.Boss then
						forecast.NextBossIn = offset
					end
					if forecast.NextShieldIn == nil and wave.ShieldTotal > 0 then
						forecast.NextShieldIn = offset
					end
				end
			end
		end
		forecast.ThreatRamp = upcomingThreat / math.max(1, currentThreat)
		forecast.BossSoon = forecast.NextBossIn ~= nil and forecast.NextBossIn <= 2
		forecast.ShieldSoon = forecast.NextShieldIn ~= nil and forecast.NextShieldIn <= 1

		local horde = schedule.Horde
		if horde then
			local phase = currentWave % horde.Interval
			forecast.NextHordeIn = phase == 0 and 0 or (horde.Interval - phase)
		end

		-- Lane weighting from explicit Path fields over the next three waves.
		if type(pathCount) == "number" and pathCount > 1 then
			local laneThreat, total = {}, 0
			for lane = 1, pathCount do laneThreat[lane] = 0 end
			for offset = 1, 3 do
				local wave = schedule.Waves[currentWave + offset]
				if wave then
					for lane, threat in pairs(wave.LaneCounts) do
						local laneNumber = tonumber(lane)
						if laneNumber and laneThreat[laneNumber] then
							laneThreat[laneNumber] = laneThreat[laneNumber] + threat
							total = total + threat
						end
					end
				end
			end
			if total > 0 then
				local weights, diverged = {}, false
				local average = total / pathCount
				for lane = 1, pathCount do
					weights[lane] = laneThreat[lane] > 0
						and math.clamp((laneThreat[lane] / math.max(1, average)) * 0.5 + 0.75, 0.7, 1.4)
						or 1
					if math.abs(weights[lane] - 1) > 0.15 then diverged = true end
				end
				if diverged then forecast.LaneWeight = weights end
			end
		end

		return forecast
	end

	return WaveIndex
end
