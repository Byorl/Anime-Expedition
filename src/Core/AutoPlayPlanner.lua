return function()
	local Planner = {}

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

	local function unitInfo(information, asset)
		if type(information) ~= "table" or asset == nil then
			return nil
		end
		if type(information.GetAsset) == "function" then
			local ok, result = pcall(information.GetAsset, information, asset)
			if ok and type(result) == "table" then
				return result
			end
		end
		for _, collection in ipairs({ information.Units, information.Assets }) do
			if type(collection) == "table" and type(collection[asset]) == "table" then
				return collection[asset]
			end
		end
		return nil
	end

	local function maxUpgrade(info)
		if type(info) ~= "table" then
			return 0
		end
		local explicit = tonumber(info.MaxUpgrade)
		if explicit then
			return math.max(0, math.floor(explicit))
		end
		local highest = 0
		for key in pairs(type(info.UpgradeInfo) == "table" and info.UpgradeInfo or {}) do
			local current = tonumber(key)
			if current and current > highest then
				highest = current
			end
		end
		return highest
	end

	local function placementLimit(slot, profile, info, information, gameModifiers)
		if type(profile) == "table" and profile.IsHelper == true then
			return math.huge
		end
		local equipped = type(slot) == "table" and tonumber(slot.PlacementLimit) or nil
		if equipped ~= nil then
			return math.max(0, math.floor(equipped))
		end
		local limit = type(info) == "table" and tonumber(info.PlacementLimit) or nil
		limit = limit == nil and math.huge or math.max(0, math.floor(limit))
		if type(gameModifiers) == "table" and gameModifiers.Traitless then
			return limit
		end
		local traitKey = profile and profile.Trait
		local traits = information and information.Traits
		local traitData = type(traits) == "table" and traits.TraitData or nil
		local trait = type(traitData) == "table" and traitData[traitKey] or nil
		local traitLimit = type(trait) == "table" and tonumber(trait.PlacementLimit) or nil
		if traitLimit ~= nil then
			limit = math.min(limit, math.max(0, math.floor(traitLimit)))
		end
		return limit
	end

	local function traitInfo(profile, information)
		local key = type(profile) == "table" and profile.Trait or nil
		local traits = type(information) == "table" and information.Traits or nil
		local values = type(traits) == "table" and (traits.TraitData or traits) or nil
		return key ~= nil and type(values) == "table" and values[key] or nil
	end

	function Planner.Slots(hotbarState, playerData, information, count, gameModifiers)
		local output = {}
		local slots = type(hotbarState) == "table" and hotbarState.Slots or nil
		local units = type(playerData) == "table" and playerData.UnitData or nil
		for index = 1, count or 6 do
			local raw = type(slots) == "table" and (slots[tostring(index)] or slots[index]) or nil
			if type(raw) == "table" then
				local id = raw.ID or raw.UnitID
				local profile = type(raw.Data) == "table" and raw.Data or (type(units) == "table" and units[id])
				local asset = raw.Asset or (type(profile) == "table" and profile.Asset)
				if asset then
					local info = unitInfo(information, asset) or {}
					local upgrades = type(info.UpgradeInfo) == "table" and info.UpgradeInfo or {}
					local base = indexed(upgrades, 0) or {}
					table.insert(output, {
						Index = index,
						ID = id,
						Asset = asset,
						Name = info.DisplayName or info.Name or tostring(asset),
						Profile = profile,
						Info = info,
						TraitInfo = traitInfo(profile, information),
						PlacementCost = number(base.Cost, number(info.Cost, 0)),
						PlacementLimit = placementLimit(raw, profile, info, information, gameModifiers),
						MaxUpgrade = maxUpgrade(info),
						Farm = base.HitboxType == "Farm" or info.HitboxType == "Farm" or number(base.Farm, 0) > 0,
					})
				end
			end
		end
		return output
	end

	local function ownedBy(data, player)
		if type(data) ~= "table" then
			return false
		end
		local owner = data.Owner
		if owner == nil or player == nil or owner == player then
			return true
		end
		local leftOk, left = pcall(function()
			return owner.UserId
		end)
		local rightOk, right = pcall(function()
			return player.UserId
		end)
		left = leftOk and left or nil
		right = rightOk and right or nil
		return left ~= nil and left == right
	end

	local function entry(data, key, slot)
		local upgrade = math.max(0, math.floor(number(data.Upgrade, 0)))
		local upgrades = type(slot.Info.UpgradeInfo) == "table" and slot.Info.UpgradeInfo or {}
		local nextInfo = indexed(upgrades, upgrade + 1) or {}
		local nextStats = type(data.NextStats) == "table" and data.NextStats or {}
		local actualMax = number(data.MaxUpgrade, slot.MaxUpgrade)
		return {
			Key = key,
			GameUnitID = data.ID or data.GameUnitID or (type(key) ~= "userdata" and key or nil),
			UnitID = data.UnitID or data.ProfileUnitID,
			Asset = (type(data.UnitData) == "table" and data.UnitData.Asset) or data.Asset or slot.Asset,
			Upgrade = upgrade,
			MaxUpgrade = math.max(0, math.floor(actualMax)),
			NextCost = number(nextStats.Cost, number(nextInfo.Cost, math.huge)),
			Farm = slot.Farm or (type(data.CurrentStats) == "table" and number(data.CurrentStats.Farm, 0) > 0),
			Unupgradeable = data.Unupgradeable == true or data.IsUnupgradeable == true,
			BoundingSize = slot.BoundingSize,
			CFrame = data.CFrame or data.UnitCFrame or data.Pivot or data.Position,
			Data = data,
		}
	end

	function Planner.Placed(slots, gameUnits, player)
		local grouped, byID, byAsset = {}, {}, {}
		for _, slot in ipairs(slots) do
			grouped[slot.Index] = {}
			if slot.ID ~= nil then
				byID[tostring(slot.ID)] = slot
			end
			byAsset[tostring(slot.Asset)] = byAsset[tostring(slot.Asset)] or {}
			table.insert(byAsset[tostring(slot.Asset)], slot)
		end
		for key, data in pairs(type(gameUnits) == "table" and gameUnits or {}) do
			if type(data) == "table" and data.IsPhantom ~= true and ownedBy(data, player) then
				local profileID = data.UnitID or data.ProfileUnitID
				local slot = profileID ~= nil and byID[tostring(profileID)] or nil
				local asset = (type(data.UnitData) == "table" and data.UnitData.Asset) or data.Asset
				if not slot and asset ~= nil then
					local candidates = byAsset[tostring(asset)] or {}
					table.sort(candidates, function(a, b)
						return #grouped[a.Index] == #grouped[b.Index] and a.Index < b.Index
							or #grouped[a.Index] < #grouped[b.Index]
					end)
					slot = candidates[1]
				end
				if slot then
					table.insert(grouped[slot.Index], entry(data, key, slot))
				end
			end
		end
		return grouped
	end

	function Planner.PlacementCount(slot, placed, placementCounts)
		local observed = #(type(placed) == "table" and placed[slot.Index] or {})
		local authoritative = 0
		if type(placementCounts) == "table" then
			authoritative = number(placementCounts[slot.Asset], number(placementCounts[tostring(slot.Asset)], 0))
		end
		return math.max(observed, math.max(0, math.floor(authoritative)))
	end

	function Planner.TotalPlacementCount(slots, placed, placementCounts)
		local total, assets = 0, {}
		for _, slot in ipairs(slots) do
			local asset = tostring(slot.Asset)
			if not assets[asset] then
				assets[asset] = true
				total = total + Planner.PlacementCount(slot, placed, placementCounts)
			end
		end
		return total
	end

	function Planner.PlaceCap(slot, configured)
		local cap = math.max(0, math.floor(number(configured, 0)))
		if slot.PlacementLimit < math.huge then
			cap = math.min(cap, slot.PlacementLimit)
		end
		return cap
	end

	function Planner.NextPlacement(slots, placed, caps, placementCounts, totalCap, blockedSlots, now)
		if tonumber(totalCap) and Planner.TotalPlacementCount(slots, placed, placementCounts) >= tonumber(totalCap) then
			return nil, false
		end
		local choices = {}
		local missing = false
		now = tonumber(now) or 0
		for _, slot in ipairs(slots) do
			local cap = Planner.PlaceCap(slot, caps[slot.Index])
			local current = Planner.PlacementCount(slot, placed, placementCounts)
			if current < cap then
				missing = true
				local blockedUntil = type(blockedSlots) == "table" and tonumber(blockedSlots[slot.Index]) or nil
				if not blockedUntil or blockedUntil <= now then
					table.insert(choices, { Slot = slot, Cost = slot.PlacementCost, Count = current, Cap = cap })
				end
			end
		end
		table.sort(choices, function(a, b)
			return a.Cost == b.Cost and a.Slot.Index < b.Slot.Index or a.Cost < b.Cost
		end)
		return choices[1], missing
	end

	function Planner.NextUpgrade(slots, placed, caps, priorities, usePriority, farmFirst, yen, blockedUpgrades, now)
		local choices = {}
		now = tonumber(now) or 0
		for _, slot in ipairs(slots) do
			local priority = math.max(0, math.floor(number(priorities[slot.Index], 0)))
			if not usePriority or priority > 0 then
				for _, unit in ipairs(placed[slot.Index] or {}) do
					local configured = math.max(0, math.floor(number(caps[slot.Index], 0)))
					local maximum = math.min(configured, unit.MaxUpgrade)
					local key = tostring(unit.GameUnitID)
					local blockedUntil = type(blockedUpgrades) == "table" and tonumber(blockedUpgrades[key]) or nil
					if unit.Upgrade < maximum and not unit.Unupgradeable and (not blockedUntil or blockedUntil <= now) then
						table.insert(
							choices,
							{ Slot = slot, Unit = unit, Cost = unit.NextCost, Priority = priority, Farm = unit.Farm }
						)
					end
				end
			end
		end
		table.sort(choices, function(a, b)
			if farmFirst and a.Farm ~= b.Farm then
				return a.Farm
			end
			if usePriority and a.Priority ~= b.Priority then
				return a.Priority > b.Priority
			end
			if a.Cost ~= b.Cost then
				return a.Cost < b.Cost
			end
			if a.Slot.Index ~= b.Slot.Index then
				return a.Slot.Index < b.Slot.Index
			end
			return tostring(a.Unit.GameUnitID) < tostring(b.Unit.GameUnitID)
		end)
		for _, choice in ipairs(choices) do
			if choice.Cost <= yen then
				return choice
			end
		end
		return nil
	end

	function Planner.RoundReset(previous, current)
		previous = type(previous) == "table" and previous or {}
		current = type(current) == "table" and current or {}
		return previous.Wave and current.Wave and current.Wave < previous.Wave
			or previous.Time and current.Time and current.Time < previous.Time - 1
			or previous.Total and previous.Total > 0 and current.Total == 0
			or false
	end

	local function pathLength(path)
		local total = 0
		for index = 2, #path do
			total = total + (path[index] - path[index - 1]).Magnitude
		end
		return total
	end

	local function nestedPathIndex(value, depth, seen)
		if type(value) ~= "table" or depth <= 0 or seen[value] then
			return nil
		end
		seen[value] = true
		local direct = value.PathIndex or value.PathID or value.PathId
		if direct ~= nil and type(direct) ~= "table" then
			return direct
		end
		for _, child in pairs(value) do
			if type(child) == "table" then
				local found = nestedPathIndex(child, depth - 1, seen)
				if found ~= nil then
					return found
				end
			end
		end
		return nil
	end

	local function normalizePathIndex(value)
		if type(value) == "number" then
			return tostring(math.abs(value)), value < 0
		end
		if type(value) ~= "string" then
			return nil
		end
		local reverse = string.find(value, "REVERSE_", 1, true) == 1
		local stripped = reverse and string.sub(value, 9) or value
		local numeric = tonumber(stripped)
		return numeric and tostring(math.abs(numeric)) or stripped, reverse or (numeric and numeric < 0) or false
	end

	local function pointSegmentDistance(point, first, second)
		local origin = Vector3.new(first.X, 0, first.Z)
		local direction = Vector3.new(second.X - first.X, 0, second.Z - first.Z)
		local target = Vector3.new(point.X, 0, point.Z)
		local lengthSquared = direction:Dot(direction)
		if lengthSquared <= 0 then
			return (target - origin).Magnitude
		end
		local alpha = math.clamp((target - origin):Dot(direction) / lengthSquared, 0, 1)
		return (target - (origin + direction * alpha)).Magnitude
	end

	local function pathReferenceDistance(path, references)
		local total = 0
		for _, reference in ipairs(references) do
			local nearest = math.huge
			for index = 2, #path do
				nearest = math.min(nearest, pointSegmentDistance(reference, path[index - 1], path[index]))
			end
			total = total + nearest
		end
		return total / math.max(1, #references)
	end

	function Planner.ActivePaths(mapState, enemies, referencePositions)
		local output = {}
		local requested = {}
		local hasReference = false
		for _, enemy in pairs(type(enemies) == "table" and enemies or {}) do
			if type(enemy) == "table" and enemy.Finished ~= true then
				local key, reverse = normalizePathIndex(nestedPathIndex(enemy, 4, {}))
				if key then
					hasReference = true
					requested[(reverse and "R:" or "P:") .. key] = true
				end
			end
		end
		local disabled = type(mapState) == "table" and mapState.DisabledPaths or nil
		local candidates = {}
		local function collect(paths, reverse)
			for key, path in pairs(type(paths) == "table" and paths or {}) do
				local normalized = normalizePathIndex(key)
				local disabledPath = type(disabled) == "table" and (disabled[key] or disabled[tostring(key)])
				if type(path) == "table" and #path >= 2 and not disabledPath then
					table.insert(candidates, {
						Path = path,
						Token = (reverse and "R:" or "P:") .. tostring(normalized),
					})
				end
			end
		end
		collect(type(mapState) == "table" and mapState.Paths or nil, false)
		collect(type(mapState) == "table" and mapState.ReversePaths or nil, true)
		if not hasReference and #candidates > 1 then
			local references = {}
			for _, position in ipairs(type(referencePositions) == "table" and referencePositions or {}) do
				if typeof(position) == "Vector3" then
					table.insert(references, position)
				end
			end
			if #references == 0 then
				return output
			end
			for _, candidate in ipairs(candidates) do
				candidate.Distance = pathReferenceDistance(candidate.Path, references)
			end
			table.sort(candidates, function(a, b)
				if a.Distance ~= b.Distance then
					return a.Distance < b.Distance
				end
				return pathLength(a.Path) > pathLength(b.Path)
			end)
			return { candidates[1].Path }
		end
		for _, candidate in ipairs(candidates) do
			if not hasReference or requested[candidate.Token] then
				table.insert(output, candidate.Path)
			end
		end
		table.sort(output, function(a, b)
			return pathLength(a) > pathLength(b)
		end)
		return output
	end

	function Planner.SelectPath(mapState, enemies, referencePositions)
		local paths = Planner.ActivePaths(mapState, enemies, referencePositions)
		local selected = paths[1]
		return selected, selected and pathLength(selected) or 0
	end

	function Planner.SamplePath(path, percent)
		if type(path) ~= "table" or #path < 2 then
			return nil
		end
		local total = pathLength(path)
		if total <= 0 then
			return path[1], path[2] - path[1], total
		end
		local target = total * math.clamp(number(percent, 50), 1, 99) / 100
		local traversed = 0
		for index = 2, #path do
			local first, second = path[index - 1], path[index]
			local segment = (second - first).Magnitude
			if target <= traversed + segment then
				local alpha = segment > 0 and (target - traversed) / segment or 0
				return first:Lerp(second, alpha), second - first, total
			end
			traversed = traversed + segment
		end
		return path[#path], path[#path] - path[#path - 1], total
	end

	function Planner.NearestProgress(path, position)
		if type(path) ~= "table" or #path < 2 or typeof(position) ~= "Vector3" then
			return nil, math.huge
		end
		local total = pathLength(path)
		if total <= 0 then
			return 0, (position - path[1]).Magnitude
		end
		local traversed = 0
		local bestDistance = math.huge
		local bestProgress = 0
		for index = 2, #path do
			local first = path[index - 1]
			local second = path[index]
			local direction = second - first
			local lengthSquared = direction:Dot(direction)
			local alpha = lengthSquared > 0 and math.clamp((position - first):Dot(direction) / lengthSquared, 0, 1) or 0
			local nearest = first + direction * alpha
			local distance = (position - nearest).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				bestProgress = (traversed + direction.Magnitude * alpha) / total
			end
			traversed = traversed + direction.Magnitude
		end
		return math.clamp(bestProgress, 0, 1), bestDistance
	end

	function Planner.RouteVote(vote, previous, current)
		vote = number(vote, 0)
		previous = tonumber(previous)
		current = tonumber(current)
		if previous == nil or current == nil then
			return vote
		end
		local delta = current - previous
		if math.abs(delta) < 0.0002 or math.abs(delta) > 0.08 then
			return vote
		end
		return math.clamp(vote + delta * 160, -12, 12)
	end

	function Planner.Candidate(path, percent, spacing, ordinal, attempt)
		local point, tangent = Planner.SamplePath(path, percent)
		if not point or not tangent or tangent.Magnitude <= 0 then
			return nil
		end
		local distance = math.min(7, math.max(1, number(spacing, 6)))
		local sequence = math.max(1, math.floor(number(ordinal, 1)))
		local retry = math.max(0, math.floor(number(attempt, 0))) % 24
		local forward = Vector3.new(tangent.X, 0, tangent.Z).Unit
		local side = Vector3.new(-forward.Z, 0, forward.X)
		local lane = ((sequence - 1) % 5) - 2
		local row = math.floor((sequence - 1) / 5)
		local retryRadius = math.min(8, math.ceil(retry / 8) * distance * 0.55)
		local retryAngle = math.rad((retry % 8) * 45)
		local offset = side * lane * distance + forward * row * distance
		if retry > 0 then
			offset = offset + Vector3.new(math.cos(retryAngle), 0, math.sin(retryAngle)) * retryRadius
		end
		local position = point + offset
		return CFrame.lookAt(position, position + forward)
	end

	return Planner
end
