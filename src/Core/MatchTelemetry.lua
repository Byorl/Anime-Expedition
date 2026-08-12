return function()
	local HttpService = game:GetService("HttpService")
	local MatchTelemetry = {}
	MatchTelemetry.__index = MatchTelemetry

	local function finite(value)
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
	end

	local function rounded(value)
		return finite(value) and math.floor(value * 1000 + 0.5) / 1000 or nil
	end

	local function valueKind(value)
		local ok, kind = pcall(typeof, value)
		return ok and kind or type(value)
	end

	local function vector(value)
		local kind = valueKind(value)
		if kind == "Vector3" then
			return { rounded(value.X), rounded(value.Y), rounded(value.Z) }
		elseif kind == "CFrame" then
			local position = value.Position
			return { rounded(position.X), rounded(position.Y), rounded(position.Z) }
		end
		return nil
	end

	local function position(value)
		if type(value) ~= "table" then
			return vector(value)
		end
		for _, key in ipairs({ "CFrame", "Position", "WorldPosition", "Location", "Pos" }) do
			local found = vector(value[key])
			if found then return found end
		end
		return nil
	end

	local function safe(value, depth, budget, seen)
		local kind = valueKind(value)
		if kind == "nil" or kind == "function" or kind == "thread" then return nil end
		if kind == "string" or kind == "boolean" then return value end
		if kind == "number" then return rounded(value) end
		if kind == "Vector3" then return { Type = "Vector3", Value = vector(value) } end
		if kind == "CFrame" then
			local components = { value:GetComponents() }
			for index, component in ipairs(components) do components[index] = rounded(component) end
			return { Type = "CFrame", Components = components }
		end
		if kind == "Color3" then
			return { Type = "Color3", Value = { rounded(value.R), rounded(value.G), rounded(value.B) } }
		end
		if kind == "EnumItem" then return tostring(value) end
		if kind == "Instance" then
			local ok, fullName = pcall(value.GetFullName, value)
			return { Type = "Instance", ClassName = value.ClassName, Name = value.Name, Path = ok and fullName or value.Name }
		end
		if kind ~= "table" or depth <= 0 or budget.Count >= budget.Max or seen[value] then return nil end
		seen[value] = true
		local count, maximum, array = 0, 0, true
		for key in pairs(value) do
			count = count + 1
			if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then array = false else maximum = math.max(maximum, key) end
		end
		if maximum ~= count then array = false end
		local result = {}
		local emitted = 0
		if array then
			for index = 1, math.min(count, 200) do
				budget.Count = budget.Count + 1
				result[index] = safe(value[index], depth - 1, budget, seen)
				emitted = emitted + 1
				if budget.Count >= budget.Max then break end
			end
		else
			local keys = {}
			for key in pairs(value) do table.insert(keys, key) end
			table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
			for _, key in ipairs(keys) do
				if emitted >= 160 or budget.Count >= budget.Max then break end
				local converted = safe(value[key], depth - 1, budget, seen)
				if converted ~= nil then
					result[tostring(key)] = converted
					budget.Count = budget.Count + 1
					emitted = emitted + 1
				end
			end
		end
		seen[value] = nil
		return result
	end

	local function copy(value, depth, maximum)
		return safe(value, depth or 4, { Count = 0, Max = maximum or 4000 }, {})
	end

	local function compactEnemy(key, enemy)
		if type(enemy) ~= "table" then return nil end
		return {
			Id = tostring(enemy.ID or enemy.Id or enemy.UUID or enemy.EnemyID or key),
			Name = tostring(enemy.DisplayName or enemy.Name or enemy.Asset or enemy.Enemy or "Unknown"),
			Position = position(enemy),
			Health = rounded(tonumber(enemy.Health or enemy.HP)),
			MaxHealth = rounded(tonumber(enemy.MaxHealth or enemy.MaxHP)),
			Shield = rounded(tonumber(enemy.Shield or enemy.ShieldHealth)),
			Progress = rounded(tonumber(enemy.Progress or enemy.PathProgress or enemy.DistanceProgress)),
			Waypoint = rounded(tonumber(enemy.WaypointIndex or enemy.Waypoint or enemy.NodeIndex)),
			Speed = rounded(tonumber(enemy.Speed or enemy.MoveSpeed)),
			Modifiers = copy(enemy.Modifiers or enemy.ModifierData or enemy.EnemyModifiers, 3, 100),
			Resistances = copy(enemy.Resistances or enemy.Resistance or enemy.DamageResistances, 3, 100),
			Type = enemy.Type or enemy.EnemyType,
		}
	end

	local function compactEnemies(enemies, maximum)
		local result = {}
		for key, enemy in pairs(type(enemies) == "table" and enemies or {}) do
			local converted = compactEnemy(key, enemy)
			if converted then table.insert(result, converted) end
			if #result >= (maximum or 48) then break end
		end
		return result
	end

	local function compactRenderedEnemies(enemies, maximum)
		local result = {}
		for key, enemy in pairs(type(enemies) == "table" and enemies or {}) do
			if type(enemy) == "table" then
				table.insert(result, {
					Id = tostring(enemy.ID or enemy.Id or enemy.UUID or enemy.EnemyID or key),
					Name = tostring(enemy.DisplayName or enemy.Name or enemy.Asset or enemy.Enemy or "Unknown"),
					Position = position(enemy),
				})
			end
			if #result >= (maximum or 48) then break end
		end
		return result
	end

	local function compactEnemySummary(enemies)
		local count, health, maximumHealth, shields = 0, 0, 0, 0
		local modifiers, resistances = {}, {}
		for _, enemy in pairs(type(enemies) == "table" and enemies or {}) do
			if type(enemy) == "table" then
				count = count + 1
				health = health + math.max(0, tonumber(enemy.Health or enemy.HP) or 0)
				maximumHealth = maximumHealth + math.max(0, tonumber(enemy.MaxHealth or enemy.MaxHP) or 0)
				shields = shields + math.max(0, tonumber(enemy.Shield or enemy.ShieldHealth) or 0)
				for key, value in pairs(type(enemy.Modifiers or enemy.ModifierData or enemy.EnemyModifiers) == "table"
					and (enemy.Modifiers or enemy.ModifierData or enemy.EnemyModifiers) or {}) do
					local name = type(key) == "number" and tostring(value) or tostring(key)
					modifiers[name] = (modifiers[name] or 0) + 1
				end
				for key, value in pairs(type(enemy.Resistances or enemy.Resistance or enemy.DamageResistances) == "table"
					and (enemy.Resistances or enemy.Resistance or enemy.DamageResistances) or {}) do
					local amount = tonumber(value)
					if amount then
						local entry = resistances[tostring(key)] or { Count = 0, Sum = 0 }
						entry.Count = entry.Count + 1
						entry.Sum = entry.Sum + amount
						resistances[tostring(key)] = entry
					end
				end
			end
		end
		local averages = {}
		for key, entry in pairs(resistances) do averages[key] = rounded(entry.Sum / math.max(1, entry.Count)) end
		return {
			Count = count,
			Health = rounded(health),
			MaxHealth = rounded(maximumHealth),
			Shields = rounded(shields),
			Modifiers = modifiers,
			AverageResistances = averages,
		}
	end

	local function compactSlots(slots)
		local result = {}
		for _, slot in ipairs(type(slots) == "table" and slots or {}) do
			table.insert(result, {
				Index = slot.Index,
				Name = slot.Name,
				Asset = slot.Asset,
				UnitID = slot.UnitID,
				Trait = copy(slot.Trait, 2, 80),
				PlacementType = type(slot.Info) == "table" and slot.Info.PlacementType or nil,
				PlacementLimit = slot.PlacementLimit,
				MaxUpgrade = slot.MaxUpgrade,
				Cost = slot.Cost,
				Farm = slot.Farm,
				Damage = slot.Damage,
				SPA = slot.SPA,
				Range = slot.Range,
				Element = slot.Element,
				BoundingSize = slot.BoundingSize,
			})
		end
		return result
	end

	local function compactPlaced(placed)
		local result = {}
		for slot, entries in pairs(type(placed) == "table" and placed or {}) do
			for _, unit in ipairs(type(entries) == "table" and entries or {}) do
				table.insert(result, {
					Slot = tonumber(slot) or slot,
					GameUnitID = unit.GameUnitID,
					Name = unit.Name or unit.DisplayName or unit.Asset,
					Asset = unit.Asset,
					Position = position(unit),
					Upgrade = unit.Upgrade,
					MaxUpgrade = unit.MaxUpgrade,
					Cost = unit.Cost,
					Farm = unit.Farm,
					Damage = unit.Damage,
					SPA = unit.SPA,
					Range = unit.Range,
					Element = unit.Element,
					Priority = unit.Priority,
				})
				if #result >= 120 then return result end
			end
		end
		return result
	end

	local function compactPaths(paths)
		local result = {}
		for _, path in ipairs(type(paths) == "table" and paths or {}) do
			local route = {}
			for _, point in ipairs(type(path) == "table" and path or {}) do
				local converted = vector(point)
				if converted then table.insert(route, converted) end
				if #route >= 600 then break end
			end
			if #route > 0 then table.insert(result, route) end
			if #result >= 12 then break end
		end
		return result
	end

	local decisionContextKeys = {
		"Scenario", "Mode", "Map", "Act", "Difficulty", "Wave", "MaxWave", "RemainingWaves",
		"Yen", "Spendable", "NextCost", "ReservePercent", "Spacing", "BaseHealth", "BaseMaxHealth",
		"HealthRatio", "EnemyCount", "TotalHealth", "MaxProgress", "AverageProgress", "BacklineEnemies",
		"Pressure", "Emergency", "RecentLeak", "CalmFor", "RouteConfident", "RouteCoverage", "Boss",
		"ModifierSummary", "ModifierDamagePressure", "ModifierCoverageBoost", "ModifierRedundancy",
		"ModifierStunRisk", "ModifierSpeed", "ModifierSpawn", "NoFarms", "ResistanceSummary",
	}

	local function compactContext(context)
		local result = {}
		for _, key in ipairs(decisionContextKeys) do
			local value = type(context) == "table" and context[key] or nil
			if value ~= nil then result[key] = copy(value, 3, 180) end
		end
		return result
	end

	local function compactDecision(decision)
		if type(decision) ~= "table" then return nil end
		local slot = decision.Slot or type(decision.Preview) == "table" and decision.Preview.Slot
		local stats = decision.Stats or type(decision.Preview) == "table" and decision.Preview.Stats
		local preview = type(decision.Preview) == "table" and decision.Preview or nil
		return {
			Kind = decision.Kind,
			Reason = decision.Reason,
			Cost = rounded(tonumber(decision.Cost)),
			Score = rounded(tonumber(decision.Score)),
			Role = decision.Role or preview and preview.Role,
			Slot = slot and { Index = slot.Index, Name = slot.Name, Asset = slot.Asset },
			GameUnitID = decision.Unit and decision.Unit.GameUnitID,
			Count = decision.Count or preview and preview.Count,
			Cap = decision.Cap or preview and preview.Cap,
			Percent = decision.Percent or preview and preview.Percent,
			Spacing = decision.Spacing or preview and preview.Spacing,
			CombatPower = rounded(tonumber(decision.CombatPower)),
			CombatGain = rounded(tonumber(decision.CombatGain)),
			CurrentPower = rounded(tonumber(decision.CurrentPower)),
			NextPower = rounded(tonumber(decision.NextPower)),
			RangeUptime = rounded(tonumber(decision.RangeUptime)),
			MarginalCoverage = rounded(tonumber(decision.MarginalCoverage)),
			PaybackWaves = rounded(tonumber(decision.PaybackWaves)),
			CompletesFarm = decision.CompletesFarm,
			Stats = stats and {
				Cost = rounded(tonumber(stats.Cost)), Damage = rounded(tonumber(stats.Damage)),
				SPA = rounded(tonumber(stats.SPA)), Range = rounded(tonumber(stats.Range)),
				Farm = rounded(tonumber(stats.Farm)), Element = stats.Element, Archetype = stats.Archetype,
				HitboxType = stats.HitboxType, HitboxSize = rounded(tonumber(stats.HitboxSize)),
			} or nil,
			Context = compactContext(decision.Context),
		}
	end

	local function scenario(snapshot)
		local state = type(snapshot) == "table" and snapshot.GameState or {}
		local parameters = type(state.Parameters) == "table" and state.Parameters or {}
		local function label(value)
			if type(value) == "table" then value = value.DisplayName or value.Name or value.ID or value.Id end
			return value ~= nil and tostring(value) or nil
		end
		return {
			Mode = label(parameters.Gamemode or parameters.GameMode or state.Gamemode or state.GameMode),
			Map = label(parameters.MapName or parameters.Map or state.MapName or state.Map),
			Act = label(parameters.ActName or parameters.Stage or state.ActName or state.Stage),
			Difficulty = label(parameters.Difficulty or parameters.DifficultyName or state.Difficulty),
		}
	end

	local function pathSignature(paths)
		local parts = {}
		for _, path in ipairs(paths) do
			local first, last = path[1], path[#path]
			table.insert(parts, string.format("%d:%s:%s", #path, table.concat(first or {}, ","), table.concat(last or {}, ",")))
		end
		return table.concat(parts, "|")
	end

	function MatchTelemetry.new(fileSystem, player, build)
		return setmetatable({
			FileSystem = fileSystem,
			Player = player,
			Build = build,
			Enabled = false,
			Active = nil,
			SampleInterval = 1,
			MaxSamples = 1200,
			LastSampleAt = 0,
			LastDecisionKey = nil,
			LastDecisionAt = 0,
			WriteBusy = false,
			WriteQueued = false,
			LastPath = nil,
		}, MatchTelemetry)
	end

	function MatchTelemetry:SetEnabled(enabled)
		self.Enabled = enabled == true
		if not self.Enabled and self.Active then self:Finalize("Recording disabled") end
	end

	function MatchTelemetry:_begin(snapshot)
		if not self.Enabled or self.Active then return end
		local now = os.time()
		local userId = tonumber(self.Player and self.Player.UserId) or 0
		local guidOk, guidValue = pcall(HttpService.GenerateGUID, HttpService, false)
		local guid = guidOk and tostring(guidValue):gsub("%-", ""):sub(1, 10) or tostring(math.floor(os.clock() * 1000))
		local folder = string.format("%s/telemetry/matches/%d", tostring(self.FileSystem.Root), userId)
		self.LastPath = string.format("%s/match_%d_%s.json", folder, now, guid)
		local paths = compactPaths(snapshot.Paths)
		self.Active = {
			Schema = 3,
			RecorderVersion = "1.2",
			HubVersion = self.Build and self.Build.Version or nil,
			StartedAt = now,
			EndedAt = nil,
			DurationSeconds = nil,
			User = { UserId = userId, UserName = self.Player and self.Player.Name or nil },
			Server = { PlaceId = game.PlaceId, JobId = game.JobId },
			Scenario = scenario(snapshot),
			Route = {
				Paths = paths,
				Reverse = snapshot.RouteReverse == true,
				Confident = snapshot.RouteConfident == true,
			},
			Loadout = compactSlots(snapshot.Slots),
			InitialState = {
				GameParameters = copy(type(snapshot.GameState) == "table" and snapshot.GameState.Parameters, 4, 500),
				GameModifiers = copy(type(snapshot.ModifierState) == "table" and snapshot.ModifierState.GameModifiers, 4, 500),
			},
			Limits = { SampleInterval = self.SampleInterval, MaxSamples = self.MaxSamples, MaxEnemiesPerSample = 48 },
			Samples = {},
			RouteRevisions = {},
			Events = {},
			DroppedSamples = 0,
			Outcome = "In progress",
		}
		self.StartClock = os.clock()
		self.LastSampleAt = 0
		self.LastDecisionKey = nil
		self.LastDecisionAt = 0
		self.LastRouteSignature = pathSignature(paths)
		self:Event("MatchStarted", { Scenario = self.Active.Scenario })
	end

	function MatchTelemetry:Capture(snapshot, force)
		if not self.Enabled or type(snapshot) ~= "table" then return false end
		self:_begin(snapshot)
		if not self.Active then return false end
		local now = os.clock()
		if not force and now - self.LastSampleAt < self.SampleInterval then return false end
		self.LastSampleAt = now
		if #self.Active.Samples >= self.MaxSamples then
			self.Active.DroppedSamples = self.Active.DroppedSamples + 1
			return false
		end
		local gameState = type(snapshot.GameState) == "table" and snapshot.GameState or {}
		local paths = compactPaths(snapshot.Paths)
		local signature = pathSignature(paths)
		if signature ~= self.LastRouteSignature then
			self.LastRouteSignature = signature
			table.insert(self.Active.RouteRevisions, {
				At = rounded(now - self.StartClock),
				Paths = paths,
				Reverse = snapshot.RouteReverse == true,
				Confident = snapshot.RouteConfident == true,
			})
		end
		table.insert(self.Active.Samples, {
			At = rounded(now - self.StartClock),
			Wave = tonumber(gameState.Wave or gameState.CurrentWave),
			MaxWave = tonumber(gameState.MaxWave or gameState.TotalWaves),
			GameTime = rounded(tonumber(gameState.GameTime or gameState.Time)),
			BaseHealth = rounded(tonumber(gameState.BaseHealth or gameState.Health)),
			Yen = rounded(tonumber(snapshot.Yen)) or 0,
			PlayerPosition = vector(snapshot.PlayerCFrame),
			PlacementCap = snapshot.PlacementCap,
			PlacementCounts = copy(snapshot.PlacementCounts, 2, 120),
			Route = { Reverse = snapshot.RouteReverse == true, Confident = snapshot.RouteConfident == true },
			LiveProgress = copy(snapshot.LiveProgress, 2, 300),
			EnemySummary = compactEnemySummary(snapshot.Enemies),
			Enemies = compactEnemies(snapshot.Enemies, 48),
			RenderedEnemies = compactRenderedEnemies(snapshot.RenderedEnemies, 48),
			Placed = compactPlaced(snapshot.Placed),
			GameState = {
				Gamemode = gameState.Gamemode or gameState.GameMode,
				Difficulty = gameState.Difficulty,
				MapName = gameState.MapName,
				ActName = gameState.ActName or gameState.StageName,
			},
			Modifiers = copy(type(snapshot.ModifierState) == "table" and snapshot.ModifierState.GameModifiers, 4, 500),
		})
		if #self.Active.Samples % 30 == 0 then self:RequestFlush() end
		return true
	end

	function MatchTelemetry:Event(kind, payload)
		if not self.Active then return end
		local events = self.Active.Events
		if #events >= 6000 then return end
		table.insert(events, { At = rounded(os.clock() - self.StartClock), Kind = tostring(kind), Data = copy(payload, 5, 1800) })
	end

	function MatchTelemetry:Decision(decision, resolvedCFrame)
		if not self.Active or type(decision) ~= "table" then return end
		local slot = decision.Slot and decision.Slot.Index or decision.Preview and decision.Preview.Slot and decision.Preview.Slot.Index
		local key = table.concat({ tostring(decision.Kind), tostring(decision.Reason), tostring(slot), tostring(decision.Cost) }, "|")
		local now = os.clock()
		if key == self.LastDecisionKey and now - self.LastDecisionAt < 2 then return end
		self.LastDecisionKey, self.LastDecisionAt = key, now
		self:Event("PlannerDecision", { Decision = compactDecision(decision), ResolvedPlacement = resolvedCFrame })
	end

	function MatchTelemetry:Flush()
		if not self.Active or not self.LastPath then return true end
		if self.WriteBusy then
			self.WriteQueued = true
			return true
		end
		self.WriteBusy = true
		local ok, err = self.FileSystem:WriteJson(self.LastPath, self.Active)
		self.WriteBusy = false
		self.LastError = ok and nil or err
		return ok, err
	end

	function MatchTelemetry:RequestFlush()
		if self.WriteBusy or not self.Active then
			self.WriteQueued = self.Active ~= nil
			return
		end
		self.WriteBusy = true
		task.spawn(function()
			repeat
				self.WriteQueued = false
				local ok, err = self.FileSystem:WriteJson(self.LastPath, self.Active)
				self.LastError = ok and nil or err
			until not self.WriteQueued
			self.WriteBusy = false
		end)
	end

	function MatchTelemetry:Finalize(outcome, result)
		if not self.Active then return true, self.LastPath end
		local deadline = os.clock() + 3
		while self.WriteBusy and os.clock() < deadline do task.wait() end
		self:Event("MatchEnded", { Outcome = outcome, Result = result })
		self.Active.Outcome = tostring(outcome or "Ended")
		self.Active.Result = copy(result, 5, 3000)
		self.Active.EndedAt = os.time()
		self.Active.DurationSeconds = rounded(os.clock() - self.StartClock)
		local path = self.LastPath
		local ok, err = self:Flush()
		self.Active = nil
		self.WriteQueued = false
		self.LastSavedPath = ok and path or nil
		return ok, path, err
	end

	function MatchTelemetry:Status()
		if self.LastError then return "Telemetry error: " .. tostring(self.LastError) end
		if self.Active then return "Telemetry: Recording" end
		if self.Enabled and self.LastSavedPath then
			return "Telemetry saved: " .. tostring(self.LastSavedPath):match("[^/\\]+$")
		end
		if self.Enabled then return "Telemetry: Waiting for match" end
		return "Telemetry: Off"
	end

	return MatchTelemetry
end
