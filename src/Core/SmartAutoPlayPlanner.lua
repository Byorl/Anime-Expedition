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
			then
				dangerous = true
			end
		end
		return count, dangerous
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

	function Smart.Context(gameState, enemies, path)
		gameState = type(gameState) == "table" and gameState or {}
		local parameters = type(gameState.Parameters) == "table" and gameState.Parameters or {}
		local difficulty = parameters.Difficulty or gameState.Difficulty or "Unknown"
		local mode = parameters.Gamemode or parameters.GameMode or parameters.Mode or "Unknown"
		local map = parameters.MapName or parameters.Map or parameters.MapID or gameState.MapName or "Unknown"
		local act = parameters.ActName or parameters.Act or parameters.Stage or gameState.ActName or "Unknown"
		local wave = math.max(0, math.floor(number(gameState.Wave, 0)))
		local maxWave = math.max(wave, math.floor(number(gameState.MaxWave or gameState.TotalWaves, wave + 15)))
		local remainingWaves = math.max(0, maxWave - wave)
		local baseHealth = math.max(0, number(gameState.BaseHealth, 1))
		local baseMax = math.max(baseHealth, number(gameState.BaseMaxHealth or gameState.MaxBaseHealth, baseHealth))
		local healthRatio = baseMax > 0 and baseHealth / baseMax or 0
		local enemyCount, totalHealth, totalMaxHealth = 0, 0, 0
		local maxProgress, speedPressure, shieldPressure, specialPressure = 0, 0, 0, 0
		local boss = false
		for _, enemy in pairs(type(enemies) == "table" and enemies or {}) do
			if type(enemy) == "table" and enemy.Finished ~= true then
				enemyCount = enemyCount + 1
				local health = math.max(0, number(enemy.Health, number(enemy.CurrentHealth, 0)))
				local maximum = math.max(health, number(enemy.MaxHealth, health))
				totalHealth = totalHealth + health
				totalMaxHealth = totalMaxHealth + maximum
				maxProgress = math.max(maxProgress, pathProgress(enemy, path))
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
		local healthPressure = totalMaxHealth > 0 and totalHealth / totalMaxHealth or 0
		local countPressure = clamp(enemyCount / 20, 0, 1)
		local progressPressure = maxProgress ^ 1.7
		local basePressure = 1 - clamp(healthRatio, 0, 1)
		local scenarioFactor = difficultyFactor(difficulty)
		local actNumber = tonumber(string.match(tostring(act), "%d+")) or 1
		scenarioFactor = scenarioFactor * (1 + math.max(0, actNumber - 1) * 0.04)
		local pressure = (
			progressPressure * 0.42
			+ countPressure * 0.16
			+ healthPressure * 0.12
			+ clamp(speedPressure / math.max(1, enemyCount), 0, 1) * 0.08
			+ clamp(shieldPressure / math.max(1, enemyCount * 5), 0, 1) * 0.07
			+ clamp(specialPressure, 0, 0.3)
			+ basePressure * 0.3
			+ (boss and 0.18 or 0)
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
			Boss = boss,
			Pressure = clamp(pressure, 0, 1.5),
			Emergency = pressure >= 0.72 or healthRatio <= 0.4,
			Scenario = string.format("%s | %s | %s | %s", mode, map, act, difficulty),
		}
	end

	local function statSet(raw, fallback)
		raw = type(raw) == "table" and raw or {}
		fallback = type(fallback) == "table" and fallback or {}
		local damage = math.max(0, number(raw.Damage, number(fallback.Damage, 0)))
		local spa = math.max(0.05, number(raw.SPA or raw.Cooldown, number(fallback.SPA or fallback.Cooldown, 1)))
		local ticks = math.max(1, number(raw.Ticks or raw.SkillTicks, number(fallback.Ticks or fallback.SkillTicks, 1)))
		return {
			Damage = damage,
			SPA = spa,
			Ticks = ticks,
			Range = math.max(1, number(raw.Range, number(fallback.Range, 10))),
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

	function Smart.Role(slot, stats)
		stats = stats or slotStats(slot, indexed(slot.Info and slot.Info.UpgradeInfo, 0))
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

	local function placementPercentages(role, context, strategy)
		if role == "Farm" then
			return { 50, 35, 65 }
		end
		if context.Emergency or strategy == "Win" and context.Pressure >= 0.5 then
			return { 82, 72, 90, 62, 52, 42, 32, 22 }
		end
		if strategy == "Boss" or context.Boss then
			return { 78, 68, 88, 58, 48, 38, 28, 18 }
		end
		return { 48, 38, 58, 28, 68, 18, 78, 88 }
	end

	local function smartCap(slot, role, strategy)
		local intrinsic = slot.PlacementLimit
		if intrinsic == math.huge then
			intrinsic = role == "Farm" and 3 or 6
		end
		local desired = role == "Farm" and 2 or 4
		if strategy == "Rush" then
			desired = role == "Farm" and 1 or 5
		elseif strategy == "Economy" and role == "Farm" then
			desired = 3
		elseif strategy == "Boss" and role ~= "Farm" then
			desired = 5
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

	local function bestPlacement(slot, paths, ordinal, context, strategy, spacing)
		local base = slotStats(slot, indexed(slot.Info and slot.Info.UpgradeInfo, 0))
		local role = Smart.Role(slot, base)
		local best
		for _, path in ipairs(paths) do
			for _, percent in ipairs(placementPercentages(role, context, strategy)) do
				local cframe = Planner.Candidate(path, percent, spacing, ordinal, 0)
				if cframe then
					local covered = coverage(path, cframe, base.Range)
					local intersection = 0
					for _, other in ipairs(paths) do
						if other ~= path then
							intersection = intersection + coverage(other, cframe, base.Range)
						end
					end
					local score = covered + intersection * 0.7
					if role == "Farm" then
						score = 1
					elseif context.Emergency then
						score = score + percent / 100 * 0.35
					end
					if not best or score > best.Coverage then
						best = {
							Path = path,
							Percent = percent,
							CFrame = cframe,
							Coverage = score,
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
		local choices, ordinal = {}, 0
		for _, entries in pairs(snapshot.Placed) do
			ordinal = ordinal + #entries
		end
		local globalCap = tonumber(snapshot.PlacementCap)
		if globalCap and ordinal >= globalCap then
			return choices
		end
		for _, slot in ipairs(snapshot.Slots) do
			local base = slotStats(slot, indexed(slot.Info and slot.Info.UpgradeInfo, 0))
			local role = Smart.Role(slot, base)
			local current = #(snapshot.Placed[slot.Index] or {})
			local cap = smartCap(slot, role, strategy)
			local spacing = automaticSpacing(slot, context)
			if current < cap and base.Cost < math.huge then
				local location
				if options.AdaptivePlacement == false then
					local path = snapshot.Paths[1]
					local cframe = path and Planner.Candidate(path, 50, spacing, ordinal + 1, 0)
					if cframe then
						location =
							{ Path = path, Percent = 50, CFrame = cframe, Coverage = 1, Stats = base, Role = role }
					end
				else
					location = bestPlacement(slot, snapshot.Paths, ordinal + 1, context, strategy, spacing)
				end
				if location then
					local power = combatPower(base, context)
					local economy = base.Farm * math.max(1, context.RemainingWaves)
					local weights = strategyWeights[strategy]
					local score = (
						power * weights.Damage * (0.55 + location.Coverage * weights.Coverage)
						+ economy * weights.Economy
						+ (role == "Support" and power * 0.35 or 0)
					) / math.max(1, base.Cost)
					score = score / (1 + current * 0.14)
					if context.Emergency and role ~= "Farm" then
						score = score * (1.35 + context.Pressure * 0.4)
					elseif context.Pressure > 0.45 and role == "Farm" then
						score = score * 0.22
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
						Reason = string.format("place %s at %d%% for path coverage", slot.Name, location.Percent),
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
			or slotStats(slot, currentInfo)
		local nextStats = type(data.NextStats) == "table" and next(data.NextStats) and statSet(data.NextStats, nextInfo)
			or slotStats(slot, nextInfo)
		if nextStats.Cost == math.huge then
			nextStats.Cost = number(unit.NextCost, math.huge)
		end
		return current, nextStats
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
						if role == "Farm" and context.RemainingWaves <= 3 then
							score = score * 0.08
						elseif role == "Farm" and context.Pressure >= 0.5 then
							score = score * 0.2
						elseif context.Emergency and role ~= "Farm" then
							score = score * (1.45 + context.Pressure * 0.35)
						end
						table.insert(choices, {
							Kind = "Upgrade",
							Slot = slot,
							Unit = unit,
							Cost = cost,
							Score = score,
							Role = role,
							Reason = string.format("upgrade %s for the best value per yen", slot.Name),
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
		local context = Smart.Context(snapshot.GameState, snapshot.Enemies, snapshot.Path)
		if options.ReactToEnemies == false then
			context.Pressure = 0.25
			context.Emergency = false
			context.Boss = false
		end
		local choices = placementChoices(snapshot, context, strategy, options)
		for _, choice in ipairs(upgradeChoices(snapshot, context, strategy)) do
			if options.SmartEconomy ~= false or choice.Role ~= "Farm" then
				table.insert(choices, choice)
			end
		end
		table.sort(choices, compare)
		local reservePercent = automaticReserve(context, strategy)
		context.ReservePercent = reservePercent
		local reserve = snapshot.Yen * reservePercent / 100
		if context.Emergency then
			reserve = 0
		end
		local spendable = math.max(0, snapshot.Yen - reserve)
		for _, choice in ipairs(choices) do
			if choice.Cost <= spendable and choice.Score > 0 then
				context.Spacing = choice.Spacing
				choice.Context = context
				choice.Strategy = strategy
				return choice
			end
		end
		local cheapest
		for _, choice in ipairs(choices) do
			if not cheapest or choice.Cost < cheapest.Cost then
				cheapest = choice
			end
		end
		context.Spacing = cheapest and cheapest.Spacing or nil
		return {
			Kind = "Wait",
			Cost = cheapest and cheapest.Cost or 0,
			Score = 0,
			Context = copy(context),
			Strategy = strategy,
			Reason = cheapest and string.format("save yen for %s", cheapest.Reason)
				or "loadout is fully deployed and upgraded",
		}
	end

	return Smart
end
