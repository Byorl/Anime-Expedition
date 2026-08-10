return function(Import)
	local Planner = Import("AutoPlayPlanner")
	local Smart = {}

	local strategyWeights = {
		Win = { Damage = 1.3, Economy = 0.85, Coverage = 1.2, Reserve = 1 },
		Balanced = { Damage = 1, Economy = 1, Coverage = 1, Reserve = 1 },
		Economy = { Damage = 0.8, Economy = 1.65, Coverage = 0.9, Reserve = 1.15 },
		Rush = { Damage = 1.45, Economy = 0.45, Coverage = 1.05, Reserve = 0.5 },
		Boss = { Damage = 1.5, Economy = 0.55, Coverage = 0.85, Reserve = 1.25 },
	}

	local function number(value, fallback)
		local result = tonumber(value)
		if result == nil then
			return fallback
		end
		return result
	end

	local function indexed(values, index)
		if type(values) ~= "table" then
			return nil
		end
		return values[index] or values[tostring(index)]
	end

	local function clamp(value, minimum, maximum)
		return math.max(minimum, math.min(maximum, value))
	end

	local function copy(values)
		local output = {}
		for key, value in pairs(values) do
			output[key] = value
		end
		return output
	end

	local function lower(value)
		return string.lower(tostring(value or ""))
	end

	local function hasText(value, text)
		return string.find(lower(value), lower(text), 1, true) ~= nil
	end

	local function readable(value)
		if type(value) ~= "table" then
			return value
		end
		for _, key in ipairs({ "DisplayName", "Name", "Modifier", "ModifierName", "Key", "ID", "Id", "Asset", "Value" }) do
			if type(value[key]) ~= "table" and value[key] ~= nil then
				return value[key]
			end
		end
		return nil
	end

	local function findValue(root, names, depth, seen)
		if type(root) ~= "table" or depth < 0 then
			return nil
		end
		seen = seen or {}
		if seen[root] then
			return nil
		end
		seen[root] = true
		for _, name in ipairs(names) do
			local wanted = lower(name)
			for key, value in pairs(root) do
				if lower(key) == wanted then
					local result = readable(value)
					if result ~= nil and tostring(result) ~= "" then
						return result
					end
				end
			end
		end
		if depth == 0 then
			return nil
		end
		for _, key in ipairs({ "Parameters", "QueueData", "StageData", "MapData", "MatchData", "Data" }) do
			local result = findValue(root[key], names, depth - 1, seen)
			if result ~= nil then
				return result
			end
		end
		for _, value in pairs(root) do
			if type(value) == "table" then
				local result = findValue(value, names, depth - 1, seen)
				if result ~= nil then
					return result
				end
			end
		end
		return nil
	end

	local function difficultyFactor(value)
		local key = lower(value)
		if string.find(key, "nightmare", 1, true) then
			return 1.65
		elseif string.find(key, "hard", 1, true) then
			return 1.32
		elseif string.find(key, "normal", 1, true) then
			return 1
		elseif string.find(key, "easy", 1, true) then
			return 0.78
		end
		return 1.1
	end

	local function tableCount(values)
		local count = 0
		for _ in pairs(type(values) == "table" and values or {}) do
			count = count + 1
		end
		return count
	end

	local function modifierCount(modifiers)
		if type(modifiers) ~= "table" then
			return 0, false
		end
		local count, dangerous = 0, false
		for key, value in pairs(modifiers) do
			local name = type(key) == "number" and value or key
			count = count + 1
			if
				hasText(name, "boss")
				or hasText(name, "sprinter")
				or hasText(name, "tank")
				or hasText(name, "shield")
				or hasText(name, "regen")
				or hasText(name, "split")
				or hasText(name, "stun")
			then
				dangerous = true
			end
		end
		return count, dangerous
	end

	local function modifierValue(value, fallback)
		if type(value) == "table" then
			return number(value.Value or value.Amount or value.Percent or value.DefaultValue, fallback)
		end
		return number(value, fallback)
	end

	local function collectModifiers(values, output)
		if type(values) ~= "table" then
			return
		end
		local directName = values.Modifier or values.ModifierName or values.Name
		if directName ~= nil and type(directName) ~= "table" then
			output[tostring(directName)] = values
			return
		end
		for key, value in pairs(values) do
			local name = type(key) == "number" and readable(value) or key
			if name ~= nil and value ~= false then
				output[tostring(name)] = value
			end
		end
	end

	local function collectModifierContainers(root, output, depth, seen)
		if type(root) ~= "table" or depth < 0 then
			return
		end
		seen = seen or {}
		if seen[root] then
			return
		end
		seen[root] = true
		for key, value in pairs(root) do
			if type(value) == "table" then
				if hasText(key, "modifier") then
					collectModifiers(value, output)
				elseif depth > 0 then
					collectModifierContainers(value, output, depth - 1, seen)
				end
			end
		end
	end

	local function modifierProfile(gameState, enemies, modifierState, information)
		local active = {}
		if type(modifierState) == "table" and type(modifierState.GameModifiers) == "table" then
			collectModifiers(modifierState.GameModifiers, active)
			collectModifierContainers(modifierState.MapState, active, 4)
		else
			collectModifiers(modifierState, active)
		end
		collectModifierContainers(gameState, active, 4)
		for _, enemy in pairs(type(enemies) == "table" and enemies or {}) do
			if type(enemy) == "table" then
				collectModifiers(enemy.Modifiers, active)
			end
		end
		local gameDefinitions = type(information) == "table"
			and type(information.GameModifiers) == "table"
			and (information.GameModifiers.List or information.GameModifiers)
			or {}
		local enemyDefinitions = type(information) == "table"
			and type(information.EnemyModifiers) == "table"
			and (information.EnemyModifiers.List or information.EnemyModifiers)
			or {}
		local profile = {
			Names = {},
			SpeedMultiplier = 1,
			SpawnMultiplier = 1,
			PressureBonus = 0,
			CoverageBoost = 0,
			Redundancy = 0,
			StunRisk = 0,
			NoFarms = false,
		}
		for name, activeValue in pairs(active) do
			local gameDefinition = type(gameDefinitions) == "table" and gameDefinitions[name] or nil
			local enemyDefinition = type(enemyDefinitions) == "table" and enemyDefinitions[name] or nil
			local definition = type(enemyDefinition) == "table" and enemyDefinition
				or type(gameDefinition) == "table" and gameDefinition
				or {}
			local key = lower(name)
			table.insert(profile.Names, tostring(definition.DisplayName or name))
			local speedPercent = number(definition.SpeedMulti, 0)
			if hasText(key, "speedy") then
				speedPercent = modifierValue(activeValue, number(definition.DefaultValue, 0))
			end
			if speedPercent > 0 then
				profile.SpeedMultiplier = profile.SpeedMultiplier * (1 + speedPercent / 100)
				profile.CoverageBoost = profile.CoverageBoost + clamp(speedPercent / 250, 0.04, 0.24)
			end
			local summons = type(definition.SummonEnemies) == "table" and definition.SummonEnemies or {}
			local summonAmount = 0
			for _, summon in pairs(summons) do
				summonAmount = summonAmount + math.max(0, number(type(summon) == "table" and summon.Amount, 0))
			end
			if summonAmount > 0 or hasText(key, "split") or hasText(key, "summon") then
				local healthPercent = number(definition.SummonHealthPercent, hasText(key, "split") and 33 or 20)
				local effective = math.max(1, summonAmount) * math.max(0.05, healthPercent / 100)
				profile.SpawnMultiplier = math.max(profile.SpawnMultiplier, 1 + effective)
				profile.CoverageBoost = profile.CoverageBoost + clamp(effective * 0.12, 0.08, 0.3)
				profile.PressureBonus = profile.PressureBonus + clamp(effective * 0.08, 0.05, 0.24)
			end
			local stunDuration = number(definition.StunDuration, 0)
			local interval = math.max(1, number(definition.Interval, 15))
			local stunCount = math.max(0, number(definition.StunCount, 0))
			if stunDuration > 0 and (stunCount > 0 or hasText(key, "stun")) then
				profile.StunRisk = math.max(profile.StunRisk, clamp(stunDuration / interval * math.max(1, stunCount) / 3, 0.1, 0.8))
				profile.Redundancy = math.max(profile.Redundancy, math.max(1, math.ceil(stunCount / 2)))
				profile.CoverageBoost = profile.CoverageBoost + profile.StunRisk * 0.2
				profile.PressureBonus = profile.PressureBonus + profile.StunRisk * 0.12
			end
			if hasText(key, "nofarm") or hasText(key, "no farm") then
				profile.NoFarms = activeValue ~= false
			end
			if hasText(key, "bosswaves") or hasText(key, "boss waves") then
				profile.BossWaves = activeValue ~= false
			end
		end
		table.sort(profile.Names)
		profile.CoverageBoost = clamp(profile.CoverageBoost, 0, 0.38)
		profile.PressureBonus = clamp(profile.PressureBonus, 0, 0.36)
		profile.Summary = #profile.Names > 0 and table.concat(profile.Names, ", ") or "None"
		return profile
	end

	local function pathProgress(enemy, path)
		local direct = tonumber(enemy.Progress or enemy.PathPercentage)
		if direct then
			return direct > 1 and clamp(direct / 100, 0, 1) or clamp(direct, 0, 1)
		end
		local waypoint = math.max(1, math.floor(number(enemy.WaypointIndex, 1)))
		local segment = clamp(number(enemy.PathProgress, 0), 0, 1)
		local points = type(path) == "table" and #path or 0
		if points >= 2 then
			return clamp((waypoint - 1 + segment) / (points - 1), 0, 1)
		end
		return clamp(segment, 0, 1)
	end

	function Smart.Context(gameState, enemies, path, liveProgress, routeConfident, modifierState, information)
		gameState = type(gameState) == "table" and gameState or {}
		local modifiers = modifierProfile(gameState, enemies, modifierState, information)
		local routeReady = routeConfident ~= false
		local difficulty = findValue(gameState, { "Difficulty", "DifficultyName" }, 4) or "Unknown"
		local mode = findValue(gameState, { "Gamemode", "GameMode", "Mode" }, 4) or "Unknown"
		local map = findValue(gameState, { "MapName", "MapID", "MapId", "Map" }, 4) or "Unknown"
		local act = findValue(gameState, { "ActName", "StageName", "Act", "Stage" }, 4) or "Unknown"
		local wave = math.max(0, math.floor(number(findValue(gameState, { "Wave", "CurrentWave" }, 3), 0)))
		local maxWave = math.max(
			wave,
			math.floor(number(findValue(gameState, { "MaxWave", "TotalWaves", "WaveCount" }, 3), wave + 15))
		)
		local remainingWaves = math.max(0, maxWave - wave)
		local baseHealth = math.max(0, number(gameState.BaseHealth, 1))
		local baseMax = math.max(baseHealth, number(gameState.BaseMaxHealth or gameState.MaxBaseHealth, baseHealth))
		local healthRatio = baseMax > 0 and baseHealth / baseMax or 0
		local enemyCount, totalHealth, totalMaxHealth = 0, 0, 0
		local maxProgress, speedPressure, shieldPressure, specialPressure = 0, 0, 0, 0
		local backlineEnemies, progressTotal = 0, 0
		local boss = false
		for _, enemy in pairs(type(enemies) == "table" and enemies or {}) do
			if type(enemy) == "table" and enemy.Finished ~= true then
				enemyCount = enemyCount + 1
				local health = math.max(0, number(enemy.Health, number(enemy.CurrentHealth, 0)))
				local maximum = math.max(health, number(enemy.MaxHealth, health))
				totalHealth = totalHealth + health
				totalMaxHealth = totalMaxHealth + maximum
				local progress = routeReady and pathProgress(enemy, path) or 0
				maxProgress = math.max(maxProgress, progress)
				progressTotal = progressTotal + progress
				backlineEnemies = backlineEnemies + (progress >= 0.72 and 1 or 0)
				local speed = number(enemy.Speed, number(enemy.DefaultSpeed, 1))
				local defaultSpeed = math.max(0.01, number(enemy.DefaultSpeed, speed))
				speedPressure = speedPressure + math.max(0, speed / defaultSpeed - 1)
				shieldPressure = shieldPressure + math.max(0, number(enemy.Shield, number(enemy.Shields, 0)))
				local modifiers, dangerous = modifierCount(enemy.Modifiers)
				specialPressure = specialPressure + modifiers * 0.03 + (dangerous and 0.12 or 0)
				local enemyType = enemy.Type or enemy.Asset or enemy.Name
				boss = boss or enemy.Boss == true or hasText(enemyType, "boss")
			end
		end
		if routeReady and type(liveProgress) == "table" and #liveProgress > 0 then
			maxProgress, progressTotal, backlineEnemies = 0, 0, 0
			for _, progress in ipairs(liveProgress) do
				progress = clamp(number(progress, 0), 0, 1)
				maxProgress = math.max(maxProgress, progress)
				progressTotal = progressTotal + progress
				backlineEnemies = backlineEnemies + (progress >= 0.72 and 1 or 0)
			end
		end
		local countPressure = clamp(enemyCount * modifiers.SpawnMultiplier / 100, 0, 1)
		local progressPressure = maxProgress ^ 1.7
		local averageProgress = progressTotal / math.max(
			1,
			type(liveProgress) == "table" and #liveProgress > 0 and #liveProgress or enemyCount
		)
		local basePressure = 1 - clamp(healthRatio, 0, 1)
		local scenarioFactor = difficultyFactor(difficulty)
		local actNumber = tonumber(string.match(tostring(act), "%d+") or "") or 1
		scenarioFactor = scenarioFactor * (1 + math.max(0, actNumber - 1) * 0.04)
		boss = boss or modifiers.BossWaves == true
		local pressure = (
			progressPressure * 0.5
			+ averageProgress ^ 1.35 * 0.12
			+ countPressure * 0.1
			+ clamp(speedPressure / math.max(1, enemyCount) + modifiers.SpeedMultiplier - 1, 0, 1) * 0.09
			+ clamp(shieldPressure / math.max(1, enemyCount * 5), 0, 1) * 0.05
			+ clamp(specialPressure, 0, 0.22)
			+ basePressure * 0.45
			+ (boss and 0.15 or 0)
			+ modifiers.PressureBonus
		) * scenarioFactor
		return {
			Difficulty = tostring(difficulty),
			Mode = tostring(mode),
			Map = tostring(map),
			Act = tostring(act),
			Wave = wave,
			MaxWave = maxWave,
			RemainingWaves = remainingWaves,
			EnemyCount = enemyCount,
			TotalHealth = totalHealth,
			MaxProgress = maxProgress,
			AverageProgress = averageProgress,
			BacklineEnemies = backlineEnemies,
			RouteConfident = routeReady,
			BaseHealth = baseHealth,
			BaseMaxHealth = baseMax,
			HealthRatio = healthRatio,
			Boss = boss,
			Modifiers = modifiers.Names,
			ModifierSummary = modifiers.Summary,
			ModifierCoverageBoost = modifiers.CoverageBoost,
			ModifierRedundancy = modifiers.Redundancy,
			ModifierStunRisk = modifiers.StunRisk,
			ModifierSpeed = modifiers.SpeedMultiplier,
			ModifierSpawn = modifiers.SpawnMultiplier,
			NoFarms = modifiers.NoFarms,
			Pressure = clamp(pressure, 0, 1.5),
			Emergency = pressure >= 0.78 or healthRatio <= 0.4,
			Scenario = string.format("%s | %s | %s | %s", mode, map, act, difficulty),
		}
	end

	local function updateHistory(context, history, now)
		if type(history) ~= "table" then
			context.RecentLeak = context.BacklineEnemies > 0
			context.CalmFor = 0
			return
		end
		now = number(now, os.clock())
		if history.BaseHealth and context.BaseHealth < history.BaseHealth then
			history.LastHealthLossAt = now
		end
		if context.BacklineEnemies > 0 or context.MaxProgress >= 0.78 then
			history.LastBacklineAt = now
		end
		local lastDanger = math.max(number(history.LastHealthLossAt, -math.huge), number(history.LastBacklineAt, -math.huge))
		context.RecentLeak = now - lastDanger <= 10
		context.CalmFor = lastDanger > -math.huge and math.max(0, now - lastDanger) or 30
		history.BaseHealth = context.BaseHealth
		history.Wave = context.Wave
		history.UpdatedAt = now
	end

	local function statSet(raw, fallback)
		raw = type(raw) == "table" and raw or {}
		fallback = type(fallback) == "table" and fallback or {}
		local damage = math.max(0, number(raw.Damage or raw.AttackDamage, number(fallback.Damage or fallback.AttackDamage, 0)))
		local spa = math.max(
			0.05,
			number(raw.SPA or raw.Cooldown or raw.AttackCooldown, number(fallback.SPA or fallback.Cooldown or fallback.AttackCooldown, 1))
		)
		local ticks = math.max(1, number(raw.Ticks or raw.SkillTicks, number(fallback.Ticks or fallback.SkillTicks, 1)))
		return {
			Damage = damage,
			SPA = spa,
			Ticks = ticks,
			Range = math.max(1, number(raw.Range or raw.AttackRange, number(fallback.Range or fallback.AttackRange, 10))),
			HitboxSize = math.max(0, number(raw.HitboxSize, number(fallback.HitboxSize, 0))),
			HitboxType = raw.HitboxType or fallback.HitboxType or "Single",
			Farm = math.max(0, number(raw.Farm, number(fallback.Farm, 0))),
			Cost = math.max(0, number(raw.Cost, number(fallback.Cost, math.huge))),
			CritChance = math.max(0, number(raw.CritChance, number(fallback.CritChance, 0))),
			CritDamage = math.max(0, number(raw.CritDamage, number(fallback.CritDamage, 0))),
			StatusCount = tableCount(raw.StatusEffects or fallback.StatusEffects),
			AbilityCount = tableCount(raw.Abilities or fallback.Abilities),
			Buff = math.max(0, number(raw.Buff or raw.BuffBonusDamage, number(fallback.Buff, 0))),
		}
	end

	local function applyTrait(stats, trait)
		if type(trait) ~= "table" then
			return stats
		end
		local output = copy(stats)
		output.Damage = output.Damage * math.max(0, 1 + number(trait.Damage, 0) / 100)
		output.SPA = math.max(0.05, output.SPA * math.max(0.05, 1 + number(trait.SPA, 0) / 100))
		output.Range = math.max(1, output.Range * math.max(0.05, 1 + number(trait.Range, 0) / 100))
		output.Farm = output.Farm * math.max(0, 1 + number(trait.Farm, 0) / 100)
		output.Cost = output.Cost * math.max(0.05, 1 + number(trait.Cost, 0) / 100)
		output.CritChance = output.CritChance + number(trait.CritChance, 0)
		output.CritDamage = output.CritDamage + number(trait.CritDamage, 0)
		return output
	end

	local function slotStats(slot, info)
		return applyTrait(statSet(info), slot.TraitInfo)
	end

	local function upgradeStats(slot, index)
		local calculated = indexed(slot.CalculatedUpgradeInfo, index)
		if type(calculated) == "table" and next(calculated) then
			return statSet(calculated)
		end
		return slotStats(slot, indexed(slot.Info and slot.Info.UpgradeInfo, index))
	end

	function Smart.Role(slot, stats)
		stats = stats or upgradeStats(slot, 0)
		if slot.Farm or stats.Farm > 0 then
			return "Farm"
		end
		if stats.Damage <= 0 and (stats.Buff > 0 or stats.StatusCount > 0 or stats.AbilityCount > 0) then
			return "Support"
		end
		if hasText(stats.HitboxType, "circle") or hasText(stats.HitboxType, "radial") or stats.HitboxSize >= 10 then
			return "Area Damage"
		end
		if hasText(stats.HitboxType, "line") or hasText(stats.HitboxType, "cone") then
			return "Lane Damage"
		end
		return "Damage"
	end

	local function combatPower(stats, context)
		local crit = 1 + clamp(stats.CritChance, 0, 100) / 100 * math.max(0, stats.CritDamage - 100) / 100
		local aoe = 1
		if hasText(stats.HitboxType, "circle") or hasText(stats.HitboxType, "radial") then
			aoe = 1.25 + clamp(stats.HitboxSize / 50, 0, 0.65)
		elseif hasText(stats.HitboxType, "line") or hasText(stats.HitboxType, "cone") then
			aoe = 1.18 + clamp(stats.HitboxSize / 70, 0, 0.4)
		end
		if context.Boss then
			aoe = 1 + (aoe - 1) * 0.35
		elseif number(context.ModifierSpawn, 1) > 1 then
			local crowd = number(context.ModifierSpawn, 1) - 1
			if hasText(stats.HitboxType, "circle") or hasText(stats.HitboxType, "radial") then
				aoe = aoe * (1 + clamp(crowd * 0.25, 0.1, 0.55))
			elseif hasText(stats.HitboxType, "line") or hasText(stats.HitboxType, "cone") then
				aoe = aoe * (1 + clamp(crowd * 0.18, 0.08, 0.4))
			end
		end
		local utility = 1 + stats.StatusCount * 0.1 + stats.AbilityCount * 0.035 + stats.Buff * 0.01
		local direct = stats.Damage * stats.Ticks / stats.SPA * crit * aoe * utility
		local support = stats.Buff * 100 + stats.StatusCount * 45 + stats.AbilityCount * 25
		return direct + support
	end

	local function coverage(path, cframe, range)
		if type(path) ~= "table" or #path < 2 or not cframe then
			return 0
		end
		local hits, total = 0, 0
		for percent = 4, 96, 4 do
			local point = Planner.SamplePath(path, percent)
			if point then
				total = total + 1
				local flat = Vector3.new(point.X - cframe.Position.X, 0, point.Z - cframe.Position.Z)
				if flat.Magnitude <= range then
					hits = hits + 1
				end
			end
		end
		return total > 0 and hits / total or 0
	end

	local function unitPosition(unit)
		local value = unit.CFrame
		if typeof(value) == "CFrame" then
			return value.Position
		end
		if typeof(value) == "Vector3" then
			return value
		end
		local data = type(unit.Data) == "table" and unit.Data or {}
		for _, key in ipairs({ "CFrame", "UnitCFrame", "Pivot", "Position" }) do
			value = data[key]
			if typeof(value) == "CFrame" then
				return value.Position
			elseif typeof(value) == "Vector3" then
				return value
			end
		end
		return nil
	end

	local function currentUnitStats(slot, unit)
		local upgrades = type(slot.Info and slot.Info.UpgradeInfo) == "table" and slot.Info.UpgradeInfo or {}
		local info = indexed(upgrades, unit.Upgrade) or indexed(upgrades, 0) or {}
		local data = type(unit.Data) == "table" and unit.Data or {}
		return type(data.CurrentStats) == "table" and next(data.CurrentStats) and statSet(data.CurrentStats, info)
			or upgradeStats(slot, unit.Upgrade)
	end

	local function pointCovered(snapshot, path, point)
		for _, slot in ipairs(snapshot.Slots) do
			for _, unit in ipairs(snapshot.Placed[slot.Index] or {}) do
				local stats = currentUnitStats(slot, unit)
				if Smart.Role(slot, stats) ~= "Farm" then
					local position = unitPosition(unit)
					if position then
						local flat = Vector3.new(point.X - position.X, 0, point.Z - position.Z)
						if flat.Magnitude <= stats.Range then
							return true
						end
					end
				end
			end
		end
		return false
	end

	local function defenseCoverage(snapshot)
		local path = snapshot.Path
		if type(path) ~= "table" or #path < 2 then
			return 0
		end
		local covered = 0
		for _, percent in ipairs({ 16, 32, 48, 64, 80, 92 }) do
			local point = Planner.SamplePath(path, percent)
			if point and pointCovered(snapshot, path, point) then
				covered = covered + 1
			end
		end
		return covered / 6
	end

	local function placementPercentages(role, context, strategy)
		if role == "Farm" then
			return { 50, 35, 65 }
		end
		if strategy == "Boss" or context.Boss then
			return { 70, 80, 60, 50, 40, 30, 20, 90 }
		end
		return { 20, 30, 40, 50, 60, 70, 80, 90 }
	end

	local function tacticalTarget(role, ordinal, context)
		if role == "Farm" then
			return 50
		end
		if context.BacklineEnemies > 0 then
			return 86
		end
		if context.RecentLeak then
			return 76
		end
		local targets = { 48, 58, 38, 66, 30, 72 }
		local combatOrdinal = math.max(1, ordinal - 1)
		local target = targets[(combatOrdinal - 1) % #targets + 1]
		if number(context.ModifierSpeed, 1) > 1 then
			target = math.min(82, target + clamp((context.ModifierSpeed - 1) * 35, 4, 14))
		end
		if context.Emergency then
			target = math.min(84, target + 10)
		end
		return target
	end

	local function smartCap(slot, role, strategy, context, stats)
		local intrinsic = slot.PlacementLimit
		if intrinsic == math.huge then
			intrinsic = role == "Farm" and 3 or 6
		end
		local desired
		if role == "Farm" then
			if context.NoFarms then
				return 0
			end
			desired = 1
			local placementPayback = stats.Farm > 0 and stats.Cost / stats.Farm or math.huge
			if placementPayback <= context.RemainingWaves * 0.72 then
				desired = context.RemainingWaves >= 8 and 3 or 2
				if context.Pressure >= 0.62 and strategy ~= "Economy" then
					desired = math.min(desired, 2)
				end
			end
		elseif role == "Support" then
			desired = 1
		else
			desired = context.RemainingWaves <= 6 and 2 or 3
			if context.Emergency or strategy == "Rush" or strategy == "Boss" then
				desired = desired + 1
			end
			desired = desired + math.max(0, math.floor(number(context.ModifierRedundancy, 0)))
		end
		return math.max(0, math.min(math.floor(intrinsic), desired))
	end

	local function automaticSpacing(slot, context)
		local footprint = tonumber(slot.BoundingSize)
		local spacing = footprint and footprint * 0.8 + 1.5 or 6
		if Smart.Role(slot) == "Farm" then
			spacing = math.max(spacing, 5)
		end
		if context.Emergency then
			spacing = spacing * 0.9
		end
		return clamp(math.floor(spacing + 0.5), 2, 18)
	end

	local function automaticReserve(context, strategy)
		if context.Emergency or context.Boss or context.RemainingWaves <= 2 then
			return 0
		end
		local base = ({ Win = 12, Balanced = 14, Economy = 22, Rush = 5, Boss = 18 })[strategy] or 12
		local waveProgress = context.MaxWave > 0 and context.Wave / context.MaxWave or 0
		local reserve = base - context.Pressure * 24 - waveProgress * 8
		if context.EnemyCount == 0 and context.RemainingWaves > 5 then
			reserve = reserve + 3
		end
		return clamp(math.floor(reserve + 0.5), 0, 28)
	end

	local function bestPlacement(slot, snapshot, ordinal, context, strategy, spacing)
		local base = upgradeStats(slot, 0)
		local role = Smart.Role(slot, base)
		local target = tacticalTarget(role, ordinal, context)
		local best
		for _, path in ipairs(snapshot.Paths) do
			for _, percent in ipairs(placementPercentages(role, context, strategy)) do
				local cframe = Planner.Candidate(path, percent, spacing, ordinal, 0)
				if cframe then
					local covered = coverage(path, cframe, base.Range)
					local _, pathDistance = Planner.NearestProgress(path, cframe.Position)
					local rangeRatio = clamp(pathDistance / math.max(1, base.Range), 0, 2)
					local rangeUtilization = rangeRatio < 1 and math.sqrt(math.max(0, 1 - rangeRatio * rangeRatio)) or 0
					local marginal, samples = 0, 0
					for sample = 4, 96, 4 do
						local point = Planner.SamplePath(path, sample)
						if point then
							samples = samples + 1
							local flat = Vector3.new(point.X - cframe.Position.X, 0, point.Z - cframe.Position.Z)
							if flat.Magnitude <= base.Range and not pointCovered(snapshot, path, point) then
								marginal = marginal + 1
							end
						end
					end
					marginal = marginal / math.max(1, samples)
					local intersection = 0
					for _, other in ipairs(snapshot.Paths) do
						if other ~= path then
							intersection = intersection + coverage(other, cframe, base.Range)
						end
					end
					local tactical = 1 - math.min(1, math.abs(percent - target) / 60)
					local separation = 1
					if context.ModifierStunRisk > 0 then
						local nearest = math.huge
						for _, entries in pairs(snapshot.Placed) do
							for _, unit in ipairs(entries) do
								local position = unitPosition(unit)
								if position then
									local delta = cframe.Position - position
									nearest = math.min(nearest, Vector3.new(delta.X, 0, delta.Z).Magnitude)
								end
							end
						end
						if nearest < math.huge then
							separation = clamp(nearest / math.max(10, base.Range * 0.75), 0.2, 1)
						end
					end
					local score = covered
						+ marginal * 1.7
						+ intersection * 0.7
						+ tactical * 0.45
						+ rangeUtilization * 0.8
						+ separation * context.ModifierStunRisk * 0.65
					if role ~= "Farm" and rangeRatio > 0.72 then
						score = score * 0.3
					end
					if role == "Farm" then
						score = 1
					end
					if not best or score > best.Coverage then
						best = {
							Path = path,
							Percent = percent,
							CFrame = cframe,
							Coverage = score,
							RouteCoverage = covered,
							MarginalCoverage = marginal,
							RangeUtilization = rangeUtilization,
							Stats = base,
							Role = role,
						}
					end
				end
			end
		end
		return best
	end

	local function placementChoices(snapshot, context, strategy, options)
		local choices = {}
		local ordinal = Planner.TotalPlacementCount(snapshot.Slots, snapshot.Placed, snapshot.PlacementCounts)
		local globalCap = tonumber(snapshot.PlacementCap)
		if globalCap and ordinal >= globalCap then
			return choices
		end
		for _, slot in ipairs(snapshot.Slots) do
			local base = upgradeStats(slot, 0)
			local role = Smart.Role(slot, base)
			local current = Planner.PlacementCount(slot, snapshot.Placed, snapshot.PlacementCounts)
			local cap = smartCap(slot, role, strategy, context, base)
			local spacing = automaticSpacing(slot, context)
			if current < cap and base.Cost < math.huge and not (options.BlockedSlots and options.BlockedSlots[slot.Index]) then
				local location
				if options.AdaptivePlacement == false then
					local path = snapshot.Paths[1]
					local cframe = path and Planner.Candidate(path, 50, spacing, ordinal + 1, 0)
					if cframe then
						location = {
							Path = path,
							Percent = 50,
							CFrame = cframe,
							Coverage = 1,
							RouteCoverage = 1,
							MarginalCoverage = 1,
							Stats = base,
							Role = role,
						}
					end
				else
					location = bestPlacement(slot, snapshot, ordinal + 1, context, strategy, spacing)
				end
				if location then
					local power = combatPower(base, context)
					local economy = base.Farm * math.max(1, context.RemainingWaves)
					local weights = strategyWeights[strategy]
					local waveProgress = context.MaxWave > 0 and context.Wave / context.MaxWave or 0
					local score = (
						power
							* weights.Damage
							* (0.45 + location.RouteCoverage * 0.7 + location.MarginalCoverage * 1.35)
						+ economy * weights.Economy
						+ (role == "Support" and power * 0.35 or 0)
					) / math.max(1, base.Cost)
					score = score / (1 + current * (0.7 + waveProgress * 0.55))
					if current == 0 then
						score = score * 1.12
					end
					if context.Emergency and role ~= "Farm" then
						score = score * (1.35 + context.Pressure * 0.4)
					elseif context.Pressure > 0.45 and role == "Farm" then
						score = score * 0.22
					end
					if role == "Farm" and (base.Farm <= 0 or base.Cost / math.max(1, base.Farm) > context.RemainingWaves * 0.7) then
						score = score * 0.05
					end
					if options.SmartEconomy == false and role == "Farm" then
						score = 0
					end
					table.insert(choices, {
						Kind = "Place",
						Slot = slot,
						Cost = base.Cost,
						Count = current,
						Cap = cap,
						Path = location.Path,
						Percent = location.Percent,
						Spacing = spacing,
						Ordinal = ordinal + 1,
						Score = score,
						Role = role,
						Stats = base,
						PaybackWaves = role == "Farm" and base.Cost / math.max(1, base.Farm) or math.huge,
						RangeUtilization = location.RangeUtilization,
						Reason = role == "Farm"
							and string.format("deploy %s with %.1f-wave payback", slot.Name, base.Cost / math.max(1, base.Farm))
							or string.format(
								"deploy %s for %.0f DPS, %.0f range and %.0f%% route coverage%s",
								slot.Name,
								power,
								base.Range,
								location.RouteCoverage * 100,
								current > 0 and string.format(" (%d/%d)", current + 1, cap) or ""
							),
					})
				end
			end
		end
		return choices
	end

	local function unitStats(slot, unit)
		local upgrades = type(slot.Info and slot.Info.UpgradeInfo) == "table" and slot.Info.UpgradeInfo or {}
		local currentInfo = indexed(upgrades, unit.Upgrade) or indexed(upgrades, 0) or {}
		local nextInfo = indexed(upgrades, unit.Upgrade + 1) or currentInfo
		local data = type(unit.Data) == "table" and unit.Data or {}
		local current = type(data.CurrentStats) == "table"
				and next(data.CurrentStats)
				and statSet(data.CurrentStats, currentInfo)
			or upgradeStats(slot, unit.Upgrade)
		local nextStats = type(data.NextStats) == "table" and next(data.NextStats) and statSet(data.NextStats, nextInfo)
			or upgradeStats(slot, unit.Upgrade + 1)
		if nextStats.Cost == math.huge then
			nextStats.Cost = number(unit.NextCost, math.huge)
		end
		return current, nextStats
	end

	local function deployedProgress(snapshot, unit)
		local position = unitPosition(unit)
		if not position then
			return nil
		end
		local best, distance = nil, math.huge
		for _, path in ipairs(type(snapshot.Paths) == "table" and snapshot.Paths or {}) do
			local progress, currentDistance = Planner.NearestProgress(path, position)
			if progress and currentDistance < distance then
				best, distance = progress, currentDistance
			end
		end
		return distance <= 35 and best or nil
	end

	local function upgradeChoices(snapshot, context, strategy)
		local choices = {}
		local weights = strategyWeights[strategy]
		for _, slot in ipairs(snapshot.Slots) do
			for _, unit in ipairs(snapshot.Placed[slot.Index] or {}) do
				if unit.Upgrade < unit.MaxUpgrade then
					local current, nextStats = unitStats(slot, unit)
					local cost = nextStats.Cost
					if cost < math.huge then
						local role = Smart.Role(slot, nextStats)
						local positionProgress = deployedProgress(snapshot, unit)
						local damageGain = math.max(0, combatPower(nextStats, context) - combatPower(current, context))
						local rangeGain = math.max(0, nextStats.Range - current.Range)
						local economyGain = math.max(0, nextStats.Farm - current.Farm)
							* math.max(1, context.RemainingWaves)
						local utilityGain = rangeGain * math.max(1, combatPower(nextStats, context) * 0.025)
						local score = (
							damageGain * weights.Damage
							+ utilityGain * weights.Coverage
							+ economyGain * weights.Economy
						) / math.max(1, cost)
						if score <= 0 then
							score = (combatPower(nextStats, context) * 0.025 + 0.01) / math.max(1, cost)
						end
						local paybackWaves = economyGain > 0 and cost / math.max(0.01, nextStats.Farm - current.Farm) or math.huge
						if role == "Farm" and paybackWaves > context.RemainingWaves * 0.72 then
							score = score * 0.05
						elseif role == "Farm" and context.Emergency then
							score = score * 0.12
						elseif role == "Farm" and context.Pressure < 0.38 and paybackWaves <= context.RemainingWaves * 0.6 then
							score = score * 1.5
						elseif context.Emergency and role ~= "Farm" then
							score = score * (1.45 + context.Pressure * 0.35)
						end
						if role ~= "Farm" and positionProgress then
							if context.RecentLeak and positionProgress >= 0.62 then
								score = score * 1.4
							elseif context.CalmFor >= 10 and positionProgress >= 0.76 then
								score = score * 0.42
							elseif positionProgress >= 0.28 and positionProgress <= 0.7 then
								score = score * 1.12
							end
						end
						table.insert(choices, {
							Kind = "Upgrade",
							Slot = slot,
							Unit = unit,
							Cost = cost,
							Score = score,
							Role = role,
							PaybackWaves = paybackWaves,
							Reason = role == "Farm"
								and string.format("upgrade %s with %.1f waves to repay the cost", slot.Name, paybackWaves)
								or string.format(
									"upgrade %s for %.0f more combat value and %.1f more range",
									slot.Name,
									damageGain,
									rangeGain
								),
						})
					end
				end
			end
		end
		return choices
	end

	local function compare(a, b)
		if a.Score ~= b.Score then
			return a.Score > b.Score
		end
		if a.Cost ~= b.Cost then
			return a.Cost < b.Cost
		end
		return a.Slot.Index < b.Slot.Index
	end

	function Smart.Decide(snapshot, options)
		options = type(options) == "table" and options or {}
		local strategy = strategyWeights[options.Strategy] and options.Strategy or "Win"
		local context = Smart.Context(
			snapshot.GameState,
			snapshot.Enemies,
			snapshot.Path,
			snapshot.LiveProgress,
			snapshot.RouteConfident,
			snapshot.ModifierState or snapshot.GameModifiers,
			snapshot.Information
		)
		updateHistory(context, options.History, options.Now)
		if options.ReactToEnemies == false then
			context.Pressure = 0.25
			context.Emergency = false
			context.Boss = false
		end
		if type(snapshot.Paths) ~= "table" or #snapshot.Paths == 0 then
			context.ReservePercent = 100
			context.Yen = math.max(0, number(snapshot.Yen, 0))
			context.Spendable = 0
			return {
				Kind = "Wait",
				Cost = 0,
				Score = 0,
				Context = copy(context),
				Strategy = strategy,
				Reason = "waiting for a live enemy to identify the active act route",
			}
		end
		local placements = placementChoices(snapshot, context, strategy, options)
		local deployment = {}
		local farmSeed = {}
		local farmExpansion = {}
		local combatPlaced = 0
		local routeCoverage = defenseCoverage(snapshot)
		context.RouteCoverage = routeCoverage
		if strategy ~= "Economy" then
			for _, slot in ipairs(snapshot.Slots) do
				local role = Smart.Role(slot, upgradeStats(slot, 0))
				if role ~= "Farm" then
					combatPlaced = combatPlaced
						+ Planner.PlacementCount(slot, snapshot.Placed, snapshot.PlacementCounts)
				end
			end
			for _, placement in ipairs(placements) do
				if placement.Role ~= "Farm" then
					table.insert(deployment, placement)
				elseif placement.Role == "Farm" and options.SmartEconomy ~= false then
					if placement.Count == 0 then
						table.insert(farmSeed, placement)
					else
						table.insert(farmExpansion, placement)
					end
				end
			end
		end
		local requiredCombat = 1
		if context.Wave >= 2 or context.Pressure >= 0.28 then
			requiredCombat = 2
		end
		if context.Wave >= 4 or context.RecentLeak or context.Pressure >= 0.5 then
			requiredCombat = 3
		end
		if context.Wave >= 8 or context.Pressure >= 0.8 then
			requiredCombat = 4
		end
		requiredCombat = requiredCombat + math.max(0, math.floor(number(context.ModifierRedundancy, 0)))
		local coverageGoal = (context.Wave >= 4 and 0.66 or context.Wave >= 2 and 0.5 or 0.32)
			+ number(context.ModifierCoverageBoost, 0)
		coverageGoal = clamp(coverageGoal, 0.32, 0.94)
		if context.RecentLeak then
			coverageGoal = 0.82
		end
		local upgrades = upgradeChoices(snapshot, context, strategy)
		table.sort(deployment, compare)
		table.sort(farmSeed, compare)
		table.sort(farmExpansion, compare)
		table.sort(upgrades, compare)
		local needsDefense = combatPlaced < requiredCombat or routeCoverage < coverageGoal
		local worthwhileDeployment = not upgrades[1]
			or not deployment[1]
			or deployment[1].Score >= upgrades[1].Score * 0.35
		local coverageCrisis = (context.BacklineEnemies > 0 or context.RecentLeak)
			and routeCoverage < coverageGoal
		local baselineShort = combatPlaced == 0
			or context.EnemyCount > 0 and combatPlaced < math.min(requiredCombat, 2)
		local forceDeployment = #deployment > 0
			and needsDefense
			and (coverageCrisis or baselineShort or combatPlaced == 0 or worthwhileDeployment)
		local earlyFarm = context.Wave <= 2
			and context.HealthRatio >= 0.99
			and context.MaxProgress < 0.5
			and not context.RecentLeak
		local totalPlaced = Planner.TotalPlacementCount(snapshot.Slots, snapshot.Placed, snapshot.PlacementCounts)
		local placementCap = tonumber(snapshot.PlacementCap)
		local openPlacementSlots = placementCap
			and math.max(0, placementCap - totalPlaced)
			or math.huge
		local defenseSlotsNeeded = math.max(0, requiredCombat - combatPlaced)
		local farmCapacitySafe = openPlacementSlots > defenseSlotsNeeded
		local preferFarm = #farmSeed > 0
			and farmCapacitySafe
			and (earlyFarm or not context.Emergency and not context.RecentLeak)
		local bestFarmPayback = farmExpansion[1] and farmExpansion[1].PaybackWaves or math.huge
		local fastFarmWindow = farmCapacitySafe
			and combatPlaced >= math.min(requiredCombat, 2)
			and routeCoverage >= math.min(coverageGoal, 0.4)
			and context.HealthRatio >= 0.99
			and not context.RecentLeak
			and not context.Emergency
			and context.RemainingWaves >= 7
			and context.Wave <= math.max(4, math.floor(context.MaxWave * 0.45))
			and bestFarmPayback <= math.min(2.25, context.RemainingWaves * 0.25)
		local expandFarm = #farmExpansion > 0
			and farmCapacitySafe
			and combatPlaced >= math.min(requiredCombat, 2)
			and routeCoverage >= math.min(coverageGoal, 0.5)
			and context.HealthRatio >= 0.99
			and (context.Pressure < 0.58 or fastFarmWindow)
			and context.RemainingWaves >= 6
		local choices = {}
		if preferFarm then
			choices = farmSeed
		elseif forceDeployment then
			choices = deployment
		elseif expandFarm then
			choices = farmExpansion
		else
			choices = placements
		end
		if not forceDeployment and not preferFarm and not expandFarm then
			for _, choice in ipairs(upgrades) do
				local suppressFarm = choice.Role == "Farm" and context.Emergency
				if not suppressFarm and (options.SmartEconomy ~= false or choice.Role ~= "Farm") then
					table.insert(choices, choice)
				end
			end
		end
		table.sort(choices, compare)
		local reservePercent = automaticReserve(context, strategy)
		context.ReservePercent = reservePercent
		context.Yen = math.max(0, number(snapshot.Yen, 0))
		local reserve = snapshot.Yen * reservePercent / 100
		if context.Emergency then
			reserve = 0
		end
		local spendable = math.max(0, snapshot.Yen - reserve)
		context.Spendable = spendable
		local best = choices[1]
		for index, choice in ipairs(choices) do
			local fallbackRatio = (context.Boss or context.RemainingWaves == 0) and 0.18 or 0.5
			local acceptableEmergencyFallback = (context.Emergency or context.Boss or context.RemainingWaves == 0)
				and best
				and choice.Score >= best.Score * fallbackRatio
			if choice.Cost <= spendable and choice.Score > 0 and (index == 1 or acceptableEmergencyFallback) then
				context.Spacing = choice.Spacing
				choice.Context = context
				choice.Strategy = strategy
				return choice
			end
		end
		context.Spacing = best and best.Spacing or nil
		context.NextCost = best and best.Cost or 0
		return {
			Kind = "Wait",
			Cost = best and best.Cost or 0,
			Score = 0,
			Context = copy(context),
			Preview = best and best.Kind == "Place" and best or nil,
			Strategy = strategy,
			Reason = best and string.format("save yen for %s", best.Reason)
				or "loadout is fully deployed and upgraded",
		}
	end

	return Smart
end
