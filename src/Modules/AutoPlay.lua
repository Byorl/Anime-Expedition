return function(Import)
	local Planner = Import("AutoPlayPlanner")
	local SmartPlanner = Import("SmartAutoPlayPlanner")
	local MatchTelemetry = Import("MatchTelemetry")
	local JoinCatalog = Import("JoinCatalog")
	local AutoPlay = {}
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local CollectionService = game:GetService("CollectionService")
	local Workspace = game:GetService("Workspace")
	local colors = {
		Color3.fromRGB(75, 170, 255),
		Color3.fromRGB(183, 110, 255),
		Color3.fromRGB(255, 190, 70),
		Color3.fromRGB(75, 220, 145),
		Color3.fromRGB(255, 105, 135),
		Color3.fromRGB(90, 220, 225),
	}

	local function loadHelper(name)
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local instance = shared and shared:FindFirstChild(name)
		if not instance then
			return nil
		end
		local ok, result = pcall(require, instance)
		return ok and type(result) == "table" and result or nil
	end

	local function notify(ctx, state, key, message)
		local now = os.clock()
		if now - (state.LastErrors[key] or 0) < 5 then
			return
		end
		state.LastErrors[key] = now
		ctx.Runtime:Notify("Auto Play", tostring(message))
	end

	local function longestPath(paths)
		local selected, selectedLength
		for _, path in ipairs(paths) do
			local length = 0
			for index = 2, #path do
				length = length + (path[index] - path[index - 1]).Magnitude
			end
			if #path >= 2 and (not selectedLength or length > selectedLength) then
				selected, selectedLength = path, length
			end
		end
		return selected
	end

	local function fallbackPath()
		local paths = {}
		local function collect(container)
			if not container then
				return
			end
			local groups = container.Name == "Paths" and container:GetChildren() or { container }
			for _, group in ipairs(groups) do
				local nodes = {}
				if group:IsA("BasePart") and tonumber(group.Name) then
					table.insert(nodes, group)
				end
				for _, descendant in ipairs(group:GetDescendants()) do
					if descendant:IsA("BasePart") and tonumber(descendant.Name) then
						table.insert(nodes, descendant)
					end
				end
				table.sort(nodes, function(a, b)
					return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
				end)
				local path = {}
				for _, node in ipairs(nodes) do
					table.insert(path, node.Position)
				end
				if #path >= 2 then
					table.insert(paths, path)
				end
			end
		end
		for _, tagged in ipairs(CollectionService:GetTagged("Path")) do
			collect(tagged)
		end
		local map = Workspace:FindFirstChild("Map")
		if map then
			collect(map:FindFirstChild("Paths"))
			local environment = map:FindFirstChild("Enviornment") or map:FindFirstChild("Environment")
			collect(environment and environment:FindFirstChild("Path"))
		end
		return longestPath(paths)
	end

	local function routeReferencePositions()
		local positions = {}
		for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
			if #positions >= 12 then
				break
			end
			local ok, position = pcall(function()
				if enemy:IsA("BasePart") then
					return enemy.Position
				end
				if enemy:IsA("Model") then
					return enemy:GetPivot().Position
				end
			end)
			if ok and typeof(position) == "Vector3" then
				table.insert(positions, position)
			end
		end
		if #positions == 0 then
			local character = Players.LocalPlayer and Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				table.insert(positions, root.Position)
			end
		end
		return positions
	end

	local function renderedEnemyTelemetry()
		local result = {}
		for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
			local ok, data = pcall(function()
				local pivot = enemy:IsA("BasePart") and enemy.CFrame or enemy:GetPivot()
				local attributes = enemy:GetAttributes()
				return {
					ID = attributes.EnemyID or attributes.ID or attributes.UUID or enemy.Name,
					Name = enemy.Name,
					CFrame = pivot,
					Attributes = attributes,
				}
			end)
			if ok then table.insert(result, data) end
			if #result >= 140 then break end
		end
		return result
	end

	local function playerCFrame()
		local character = Players.LocalPlayer and Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		return root and root.CFrame or nil
	end

	local function reversePath(path)
		local reversed = {}
		for index = #path, 1, -1 do
			table.insert(reversed, path[index])
		end
		return reversed
	end

	local function pathSignature(path)
		if type(path) ~= "table" or #path < 2 then
			return ""
		end
		local first, last = path[1], path[#path]
		return string.format(
			"%.0f:%.0f:%.0f|%.0f:%.0f:%.0f|%d",
			first.X,
			first.Y,
			first.Z,
			last.X,
			last.Y,
			last.Z,
			#path
		)
	end

	local function orientedRoute(state, paths)
		local progress = {}
		local signature = paths[1] and pathSignature(paths[1]) or ""
		if signature ~= state.RouteSignature then
			state.RouteSignature = signature
			state.RouteVote = 0
			state.RouteReverse = false
			state.RouteConfident = false
			state.EnemyTracks = {}
		end
		local seen = {}
		for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
			local ok, position = pcall(function()
				return enemy:IsA("BasePart") and enemy.Position or enemy:GetPivot().Position
			end)
			if ok and typeof(position) == "Vector3" then
				local best, distance = nil, math.huge
				for _, path in ipairs(paths) do
					local candidate, candidateDistance = Planner.NearestProgress(path, position)
					if candidate and candidateDistance < distance then
						best, distance = candidate, candidateDistance
					end
				end
				if best and distance <= 20 then
					seen[enemy] = true
					local previous = state.EnemyTracks[enemy]
					if previous and previous.Signature == signature then
						state.RouteVote = Planner.RouteVote(state.RouteVote, previous.Progress, best)
					end
					state.EnemyTracks[enemy] = { Progress = best, Signature = signature }
					table.insert(progress, best)
				end
			end
		end
		for enemy in pairs(state.EnemyTracks) do
			if not seen[enemy] then
				state.EnemyTracks[enemy] = nil
			end
		end
		if math.abs(state.RouteVote) >= 1 then
			state.RouteReverse = state.RouteVote < 0
			state.RouteConfident = true
		end
		local oriented = {}
		for _, path in ipairs(paths) do
			table.insert(oriented, state.RouteReverse and reversePath(path) or path)
		end
		if not state.RouteConfident then
			return oriented, {}
		end
		if state.RouteReverse then
			for index, value in ipairs(progress) do
				progress[index] = 1 - value
			end
		end
		return oriented, progress
	end

	local function enrichPlacedCFrames(placed)
		local byID = {}
		for _, entries in pairs(placed) do
			for _, unit in ipairs(entries) do
				if unit.GameUnitID ~= nil then
					byID[tostring(unit.GameUnitID)] = unit
				end
			end
		end
		for _, model in ipairs(CollectionService:GetTagged("Unit")) do
			local ok, id, cframe = pcall(function()
				local value = model:GetAttribute("GameUnitID") or model:GetAttribute("ID")
				if value == nil then
					for _, descendant in ipairs(model:GetDescendants()) do
						value = descendant:GetAttribute("GameUnitID")
						if value ~= nil then
							break
						end
					end
				end
				value = value or model:GetAttribute("UnitID")
				return value, model:IsA("Model") and model:GetPivot() or model.CFrame
			end)
			local unit = ok and id ~= nil and byID[tostring(id)] or nil
			if unit and typeof(cframe) == "CFrame" then
				unit.CFrame = cframe
			end
		end
	end

	local function pathGeometry()
		local map = Workspace:FindFirstChild("Map")
		local environment = map and (map:FindFirstChild("Enviornment") or map:FindFirstChild("Environment"))
		return environment and environment:FindFirstChild("Path")
	end

	local function isPathSurface(instance)
		local geometry = pathGeometry()
		return geometry and instance and (instance == geometry or instance:IsDescendantOf(geometry)) or false
	end

	local function isOverPath(position)
		local geometry = pathGeometry()
		if not geometry then
			return false
		end
		local parts = geometry:IsA("BasePart") and { geometry } or geometry:GetDescendants()
		for _, part in ipairs(parts) do
			if part:IsA("BasePart") then
				local localPoint = part.CFrame:PointToObjectSpace(position)
				if
					math.abs(localPoint.X) <= part.Size.X / 2 + 0.5
					and math.abs(localPoint.Z) <= part.Size.Z / 2 + 0.5
					and math.abs(localPoint.Y - part.Size.Y / 2) <= 4
				then
					return true
				end
			end
		end
		return false
	end

	local function groundCFrame(slot, candidate)
		local map = Workspace:FindFirstChild("Map")
		if not map then
			return nil
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { map }
		local result =
			Workspace:Raycast(candidate.Position + Vector3.new(0, 100, 0), Vector3.new(0, -300, 0), params)
		if not result then
			return nil
		end
		if isPathSurface(result.Instance) then
			return nil
		end
		local position = result.Position + Vector3.new(0, (slot.BoundingHeight or 4) / 2, 0)
		local look = Vector3.new(candidate.LookVector.X, 0, candidate.LookVector.Z)
		if look.Magnitude <= 0 then
			look = Vector3.new(0, 0, -1)
		end
		return CFrame.lookAt(position, position + look.Unit), result.Instance
	end

	local function isAllowed(state, asset, cframe)
		if not state.UnitUtils or type(state.UnitUtils.IsPlacementAllowed) ~= "function" then
			return false
		end
		local ok, result = pcall(state.UnitUtils.IsPlacementAllowed, state.UnitUtils, asset, cframe)
		return ok and result == true
	end

	local function enrichSlotFootprints(state, slots)
		for _, slot in ipairs(slots) do
			local key = tostring(slot.Asset)
			local cached = state.BoundingSizes[key]
			local cachedHeight = state.BoundingHeights[key]
			if cached == nil or cachedHeight == nil then
				cached = 6
				cachedHeight = 4
				if state.UnitUtils and type(state.UnitUtils.GetUnitBoundingBoxSize) == "function" then
					local ok, size = pcall(state.UnitUtils.GetUnitBoundingBoxSize, state.UnitUtils, slot.Asset)
					if ok and typeof(size) == "Vector3" then
						cached = math.max(2, size.X, size.Z)
						cachedHeight = math.max(1, size.Y)
					end
				end
				state.BoundingSizes[key] = cached
				state.BoundingHeights[key] = cachedHeight
			end
			slot.BoundingSize = cached
			slot.BoundingHeight = cachedHeight
		end
	end

	local function enrichSlotStats(state, slots, gameModifiers)
		if not state.UnitUtils or type(state.UnitUtils.GetCalculatedStats) ~= "function" then
			return
		end
		for _, slot in ipairs(slots) do
			local profile = type(slot.Profile) == "table" and slot.Profile or {}
			local parameters = {
				Level = profile.Level,
				Trait = type(gameModifiers) == "table" and gameModifiers.Traitless and nil or profile.Trait,
				Ascension = profile.Ascension,
				StatPotential = profile.StatPotential,
				Equipment = type(profile.EquipmentData) == "table" and profile.EquipmentData or {},
				GameModifiers = gameModifiers,
			}
			local calculated = {}
			for index, raw in pairs(type(slot.Info and slot.Info.UpgradeInfo) == "table" and slot.Info.UpgradeInfo or {}) do
				local ok, stats = pcall(state.UnitUtils.GetCalculatedStats, state.UnitUtils, raw, parameters)
				if ok and type(stats) == "table" then
					calculated[index] = stats
				end
			end
			slot.CalculatedUpgradeInfo = calculated
		end
	end

	local function placementOrdinal(snapshot, choice)
		if choice.Ordinal then
			return choice.Ordinal
		end
		local ordinal = choice.Count + 1
		for _, slot in ipairs(snapshot.Slots) do
			if slot.Index >= choice.Slot.Index then
				break
			end
			ordinal = ordinal + Planner.PlacementCount(slot, snapshot.Placed, snapshot.PlacementCounts)
		end
		return ordinal
	end

	local function pathSideCandidate(path, percent, ordinal, attempt, spacing)
		local point, tangent = Planner.SamplePath(path, percent)
		if not point or not tangent or tangent.Magnitude <= 0 then
			return nil
		end
		local forward = Vector3.new(tangent.X, 0, tangent.Z)
		if forward.Magnitude <= 0 then
			return nil
		end
		forward = forward.Unit
		local side = Vector3.new(-forward.Z, 0, forward.X)
		local distances = { -4, 4, -6, 6, -8, 8, -10, 10, -12, 12, -15, 15, -18, 18, -21, 21 }
		local lateral = distances[attempt % #distances + 1]
		local forwardOffset = ((math.max(1, ordinal) - 1) % 3 - 1) * math.max(2, tonumber(spacing) or 2)
		local position = point + side * lateral + forward * forwardOffset
		return CFrame.lookAt(position, position + forward)
	end

	local function overlapsReservation(slot, cframe, reservations, spacing)
		for _, reservation in ipairs(type(reservations) == "table" and reservations or {}) do
			local other = reservation.CFrame
			if typeof(other) == "CFrame" then
				local delta = cframe.Position - other.Position
				local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
				local clearance = math.max(
					((tonumber(slot.BoundingSize) or 6) + (tonumber(reservation.Size) or 6)) / 2 + 0.5,
					tonumber(spacing) or 0
				)
				if horizontal < clearance then
					return true
				end
			end
		end
		return false
	end

	local function taggedPlacementCFrame(state, slot, pathPoint, tangent, reservations, spacing, maxPathDistance)
		local placementType = type(slot.Info) == "table" and slot.Info.PlacementType or nil
		local tag = placementType == "Ground" and "GroundPlacement" or "HillPlacement"
		local map = Workspace:FindFirstChild("Map")
		local footprint = math.max(2, tonumber(slot.BoundingSize) or 6)
		local parts = {}
		for _, tagged in ipairs(CollectionService:GetTagged(tag)) do
			local descendants = tagged:IsA("BasePart") and { tagged } or tagged:GetDescendants()
			for _, part in ipairs(descendants) do
				if
					part:IsA("BasePart")
					and map
					and part:IsDescendantOf(map)
					and not isPathSurface(part)
				then
					table.insert(parts, part)
				end
			end
		end
		local look = Vector3.new(tangent.X, 0, tangent.Z)
		if look.Magnitude <= 0 then
			look = Vector3.new(0, 0, -1)
		end
		look = look.Unit
		local side = Vector3.new(-look.Z, 0, look.X)
		local offsets = placementType == "Ground"
			and { -7, 7, -9, 9, -12, 12, -15, 15, -18, 18, -22, 22, -26, 26 }
			or { -10, 10, -15, 15, -20, 20, -25, 25, -30, 30, -36, 36, -42, 42 }
		for _, offset in ipairs(offsets) do
			local target = pathPoint + side * offset
			for _, part in ipairs(parts) do
				local localPoint = part.CFrame:PointToObjectSpace(target)
				local inset = footprint / 2 + 0.25
				if
					math.abs(localPoint.X) <= math.max(0, part.Size.X / 2 - inset)
					and math.abs(localPoint.Z) <= math.max(0, part.Size.Z / 2 - inset)
				then
					local surface = part.CFrame:PointToWorldSpace(Vector3.new(localPoint.X, part.Size.Y / 2, localPoint.Z))
					local pathDelta = surface - pathPoint
					local pathDistance = Vector3.new(pathDelta.X, 0, pathDelta.Z).Magnitude
					if not isOverPath(surface) and (not maxPathDistance or pathDistance <= maxPathDistance) then
						local position = surface + Vector3.new(0, (slot.BoundingHeight or 4) / 2, 0)
						local cframe = CFrame.lookAt(position, position + look)
						if
							not overlapsReservation(slot, cframe, reservations, spacing)
							and isAllowed(state, slot.Asset, cframe)
						then
							return cframe
						end
					end
				end
			end
		end
		return nil
	end

	local function findPlacement(state, snapshot, choice, options)
		options = type(options) == "table" and options or {}
		local path = choice.Path or snapshot.Path
		if not path then
			return nil, "No active map path was found."
		end
		local ordinal = placementOrdinal(snapshot, choice)
		local start = tonumber(options.Start)
		if start == nil then
			start = state.PlaceRetries[choice.Slot.Index] or 0
		end
		local recordRetry = options.RecordRetry ~= false
		local spacing = tonumber(choice.Spacing) or state.Spacing
		local combatRange = type(choice.Stats) == "table" and tonumber(choice.Stats.Range) or nil
		local maxPathDistance = choice.Role ~= "Farm" and combatRange
			and math.clamp(combatRange * 0.62, 5, 15)
			or nil
		local reservations = options.Reserved
		if reservations == nil then
			reservations = {}
			for _, entries in pairs(snapshot.Placed) do
				for _, unit in ipairs(entries) do
					if typeof(unit.CFrame) == "CFrame" then
						table.insert(reservations, { CFrame = unit.CFrame, Size = unit.BoundingSize })
					end
				end
			end
		end
		local shifts = { 0, -10, 10, -20, 20, -30, 30 }
		local distances = 16
		for _, shift in ipairs(shifts) do
			local percent = math.clamp((choice.Percent or state.PathPosition) + shift, 8, 92)
			local pathPoint, tangent = Planner.SamplePath(path, percent)
			local candidate = pathPoint
				and tangent
				and taggedPlacementCFrame(
					state,
					choice.Slot,
					pathPoint,
					tangent,
					reservations,
					spacing,
					maxPathDistance
				)
			if candidate then
				return candidate
			end
		end
		for offset = 0, 47 do
			local attempt = start + offset
			local percent = math.clamp(
				(choice.Percent or state.PathPosition)
					+ shifts[math.floor(attempt / distances) % #shifts + 1],
				8,
				92
			)
			local candidate = pathSideCandidate(path, percent, ordinal, attempt, spacing)
			if candidate then
				local pathPoint = Planner.SamplePath(path, percent)
				candidate = groundCFrame(choice.Slot, candidate)
				local closeToPath = candidate
					and pathPoint
					and Vector3.new(
						candidate.Position.X - pathPoint.X,
						0,
						candidate.Position.Z - pathPoint.Z
					).Magnitude <= (maxPathDistance or 22)
				if
					closeToPath
					and not overlapsReservation(choice.Slot, candidate, reservations, spacing)
					and isAllowed(state, choice.Slot.Asset, candidate)
				then
					if recordRetry then
						state.PlaceRetries[choice.Slot.Index] = attempt
					end
					return candidate
				end
			end
		end
		if recordRetry then
			state.PlaceRetries[choice.Slot.Index] = (start + 48) % (#shifts * distances)
		end
		return nil, "No valid placement point was found yet; another area will be tried."
	end

	local function destroyMarkers(state)
		for key, marker in pairs(state.Markers) do
			if marker.Part then
				marker.Part:Destroy()
			end
			state.Markers[key] = nil
		end
		if state.VisualFolder then
			state.VisualFolder:Destroy()
			state.VisualFolder = nil
		end
	end

	local function marker(state, key)
		local current = state.Markers[key]
		if current and current.Part and current.Part.Parent then
			return current
		end
		if not state.VisualFolder then
			local folder = Instance.new("Folder")
			folder.Name = "AnimeExpeditionsAutoPlayVisualization_" .. tostring(state.Generation)
			folder.Parent = Workspace
			state.VisualFolder = folder
		end
		local part = Instance.new("Part")
		part.Name = "Placement_" .. key
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Shape = Enum.PartType.Cylinder
		part.Transparency = 0.48
		part.Parent = state.VisualFolder
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Label"
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.Size = UDim2.fromOffset(180, 34)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
		billboard.Parent = part
		local label = Instance.new("TextLabel")
		label.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
		label.BackgroundTransparency = 0.2
		label.BorderSizePixel = 0
		label.Font = Enum.Font.GothamMedium
		label.Size = UDim2.fromScale(1, 1)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextSize = 12
		label.TextStrokeTransparency = 0.7
		label.Parent = billboard
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = label
		current = { Part = part, Label = label }
		state.Markers[key] = current
		return current
	end

	local function updateVisualization(state, snapshot)
		if not state.Visualize or not snapshot.Path then
			destroyMarkers(state)
			return
		end
		local wanted = {}
		local reservations = {}
		for _, entries in pairs(snapshot.Placed) do
			for _, unit in ipairs(entries) do
				if typeof(unit.CFrame) == "CFrame" then
					table.insert(reservations, { CFrame = unit.CFrame, Size = unit.BoundingSize })
				end
			end
		end
		local ordinal = 0
		for _, slot in ipairs(snapshot.Slots) do
			local cap = Planner.PlaceCap(slot, snapshot.MaxPlace[slot.Index])
			local placed = Planner.PlacementCount(slot, snapshot.Placed, snapshot.PlacementCounts)
			for index = 1, cap do
				ordinal = ordinal + 1
				local key = tostring(slot.Index) .. "_" .. tostring(index)
				local observed = snapshot.Placed[slot.Index] or {}
				local candidate = index <= #observed and typeof(observed[index].CFrame) == "CFrame"
					and observed[index].CFrame
					or nil
				if not candidate and index > placed then
					candidate = findPlacement(state, snapshot, {
						Slot = slot,
						Count = placed,
						Cap = cap,
						Ordinal = ordinal,
						Percent = state.PathPosition,
					}, {
						RecordRetry = false,
						Start = (state.PlaceRetries[slot.Index] or 0) + math.max(0, index - placed - 1) * 8,
						Reserved = reservations,
					})
					if candidate then
						table.insert(reservations, { CFrame = candidate, Size = slot.BoundingSize })
					end
				end
				if candidate then
					wanted[key] = true
					local current = marker(state, key)
					if current then
						local color = index <= placed and Color3.fromRGB(75, 235, 130) or colors[slot.Index]
						current.Part.Color = color
						current.Part.Size = Vector3.new(
							0.16,
							math.max(2.5, state.Spacing * 0.7),
							math.max(2.5, state.Spacing * 0.7)
						)
						current.Part.CFrame = candidate * CFrame.Angles(0, 0, math.pi / 2)
						current.Label.Text =
							string.format("Slot %d | %s | %d/%d", slot.Index, slot.Name, index, cap)
					end
				end
			end
		end
		for key, current in pairs(state.Markers) do
			if not wanted[key] then
				current.Part:Destroy()
				state.Markers[key] = nil
			end
		end
	end

	local function snapshot(ctx, state)
		local gameState, gameSource = ctx.Game:GameData()
		if type(gameState) ~= "table" or ctx.Game:IsMatchEnded(gameState) then
			state.MatchDetected = false
			return nil
		end
		if ctx.Game:IsMatchActive(gameState) then
			state.MatchDetected = true
		end
		if not state.MatchDetected then
			return nil
		end
		local hotbar = ctx.Game:HotbarData()
		local playerData = ctx.Game:PlayerData()
		local information = ctx.Game:Information() or {}
		local gameModifiers = ctx.Game:StateDeep("GameModifiers", 3) or {}
		local slots = Planner.Slots(hotbar, playerData, information, 6, gameModifiers)
		enrichSlotFootprints(state, slots)
		enrichSlotStats(state, slots, gameModifiers)
		local gameUnits = ctx.Game:StateDeep("GameUnits", 4)
		local placed = Planner.Placed(slots, gameUnits, Players.LocalPlayer)
		enrichPlacedCFrames(placed)
		local playerState, playerSource = ctx.Game:GamePlayerData()
		local mapState = ctx.Game:StateDeep("MapState", 5)
		local enemies = ctx.Game:StateDeep("GameEnemies", 4) or {}
		local paths = Planner.ActivePaths(mapState, enemies, routeReferencePositions())
		local path = paths[1]
		local mapStateHasPaths = type(mapState) == "table"
			and (next(type(mapState.Paths) == "table" and mapState.Paths or {}) ~= nil
				or next(type(mapState.ReversePaths) == "table" and mapState.ReversePaths or {}) ~= nil)
		if not path and not mapStateHasPaths then
			path = fallbackPath()
			if path then
				paths = { path }
			end
		end
		local liveProgress
		paths, liveProgress = orientedRoute(state, paths)
		path = paths[1]
		return {
			GameState = gameState,
			ModifierState = { GameModifiers = gameModifiers, MapState = mapState },
			Information = information,
			Slots = slots,
			Placed = placed,
			Yen = math.max(0, tonumber(type(playerState) == "table" and playerState.Yen) or 0),
			PlayerState = playerState,
			PlayerCFrame = playerCFrame(),
			Path = path,
			Paths = paths,
			Enemies = enemies,
			RenderedEnemies = renderedEnemyTelemetry(),
			LiveProgress = liveProgress,
			RouteConfident = state.RouteConfident,
			RouteReverse = state.RouteReverse,
			PlacementCounts = type(playerState) == "table" and playerState.PlacementCounts or {},
			PlacementCap = tonumber(
				type(playerState) == "table" and playerState.TotalUnitPlacementCap
					or gameState.GlobalUnitPlacementCap
					or gameState.TotalPlacementCap
					or (type(information) == "table" and information.DefaultTotalPlacementCap)
			),
			MaxPlace = state.MaxPlace,
			MaxUpgrade = state.MaxUpgrade,
			GameStateSource = gameSource,
			PlayerStateSource = playerSource,
		}
	end

	local function resetRound(state)
		state.Pending = nil
		state.PlaceRetries = {}
		state.BlockedSlots = {}
		state.BlockedUpgrades = {}
		state.SmartHistory = {}
		state.RouteSignature = nil
		state.RouteVote = 0
		state.RouteReverse = false
		state.RouteConfident = false
		state.EnemyTracks = {}
		state.UpgradeRetries = {}
		state.NextActionAt = os.clock() + 0.5
		state.VisualDirty = true
	end

	local function reconcileRound(state, current)
		local total = Planner.TotalPlacementCount(current.Slots, current.Placed, current.PlacementCounts)
		local wave = tonumber(current.GameState.Wave)
		local elapsed = tonumber(current.GameState.GameTime or current.GameState.Time)
		local reset = Planner.RoundReset(
			{ Wave = state.LastWave, Time = state.LastTime, Total = state.LastTotal },
			{ Wave = wave, Time = elapsed, Total = total }
		)
		if reset then
			if state.Telemetry then state.Telemetry:Finalize("Seamless retry") end
			resetRound(state)
		end
		state.LastWave, state.LastTime, state.LastTotal = wave, elapsed, total
		return reset
	end

	local function findUnit(current, gameUnitID)
		for _, entries in pairs(current.Placed) do
			for _, unit in ipairs(entries) do
				if tostring(unit.GameUnitID) == tostring(gameUnitID) then
					return unit
				end
			end
		end
	end

	local function pendingComplete(state, current)
		local pending = state.Pending
		if not pending then
			return true
		end
		if pending.Kind == "Place" then
			local slot
			for _, candidate in ipairs(current.Slots) do
				if candidate.Index == pending.Slot then
					slot = candidate
					break
				end
			end
			if slot and Planner.PlacementCount(slot, current.Placed, current.PlacementCounts) > pending.Before then
				if state.Telemetry then state.Telemetry:Event("ActionConfirmed", pending) end
				state.PlaceRetries[pending.Slot] = 0
				state.BlockedSlots[pending.Slot] = nil
				state.Pending = nil
				state.VisualDirty = true
				return true
			end
		else
			local unit = findUnit(current, pending.GameUnitID)
			if unit and unit.Upgrade > pending.Before then
				if state.Telemetry then state.Telemetry:Event("ActionConfirmed", pending) end
				state.UpgradeRetries[tostring(pending.GameUnitID)] = 0
				state.BlockedUpgrades[tostring(pending.GameUnitID)] = nil
				state.Pending = nil
				return true
			end
		end
		if os.clock() - pending.Started < 1.6 then
			return false
		end
		if pending.Kind == "Place" then
			state.PlaceRetries[pending.Slot] = (state.PlaceRetries[pending.Slot] or 0) + 1
			state.BlockedSlots[pending.Slot] = os.clock() + 1.25
		else
			local key = tostring(pending.GameUnitID)
			state.UpgradeRetries[key] = (state.UpgradeRetries[key] or 0) + 1
			state.BlockedUpgrades[key] = os.clock() + 1.5
		end
		if state.Telemetry then state.Telemetry:Event("ActionTimedOut", pending) end
		state.Pending = nil
		state.NextActionAt = os.clock() + 0.65
		return true
	end

	local function place(ctx, state, current, choice, resolvedCFrame)
		local cframe, err = resolvedCFrame, nil
		if not cframe then
			cframe, err = findPlacement(state, current, choice)
		end
		if not cframe then
			if state.Telemetry then state.Telemetry:Event("PlacementRejected", { Slot = choice.Slot.Index, Error = err }) end
			notify(ctx, state, "placement", err)
			state.BlockedSlots[choice.Slot.Index] = os.clock() + 1.25
			state.NextActionAt = os.clock() + 0.15
			return false
		end
		local ok, fireError = ctx.Game:GamePlayerAction("PlaceGameUnit", choice.Slot.Index, cframe)
		if not ok then
			if state.Telemetry then state.Telemetry:Event("ActionFailed", { Kind = "Place", Slot = choice.Slot.Index, Error = fireError, Position = cframe }) end
			notify(ctx, state, "place_fire", fireError)
			state.BlockedSlots[choice.Slot.Index] = os.clock() + 1.25
			return false
		end
		state.Pending = {
			Kind = "Place",
			Slot = choice.Slot.Index,
			Asset = choice.Slot.Asset,
			Before = choice.Count,
			Started = os.clock(),
		}
		if state.Telemetry then state.Telemetry:Event("ActionAttempt", { Kind = "Place", Slot = choice.Slot.Index, Asset = choice.Slot.Asset, Position = cframe, Before = choice.Count }) end
		state.BlockedSlots[choice.Slot.Index] = nil
		state.NextActionAt = os.clock() + 0.35
		return true
	end

	local function upgrade(ctx, state, choice)
		if choice.Unit.GameUnitID == nil then
			if state.Telemetry then state.Telemetry:Event("ActionFailed", { Kind = "Upgrade", Error = "Missing game unit ID" }) end
			notify(ctx, state, "upgrade_id", "A placed unit did not expose its game unit ID.")
			return false
		end
		local ok, err = ctx.Game:GamePlayerAction("UpgradeGameUnit", choice.Unit.GameUnitID)
		if not ok then
			if state.Telemetry then state.Telemetry:Event("ActionFailed", { Kind = "Upgrade", GameUnitID = choice.Unit.GameUnitID, Error = err }) end
			notify(ctx, state, "upgrade_fire", err)
			state.BlockedUpgrades[tostring(choice.Unit.GameUnitID)] = os.clock() + 1.5
			return false
		end
		state.Pending = {
			Kind = "Upgrade",
			GameUnitID = choice.Unit.GameUnitID,
			Before = choice.Unit.Upgrade,
			Started = os.clock(),
		}
		if state.Telemetry then state.Telemetry:Event("ActionAttempt", { Kind = "Upgrade", GameUnitID = choice.Unit.GameUnitID, Before = choice.Unit.Upgrade, Slot = choice.Slot and choice.Slot.Index }) end
		state.NextActionAt = os.clock() + 0.3
		return true
	end

	local function act(ctx, state, current)
		if not state.Enabled or os.clock() < state.NextActionAt or not pendingComplete(state, current) then
			return
		end
		local now = os.clock()
		local placement, missing = Planner.NextPlacement(
			current.Slots,
			current.Placed,
			state.MaxPlace,
			current.PlacementCounts,
			current.PlacementCap,
			state.BlockedSlots,
			now
		)
		local upgradeChoice = Planner.NextUpgrade(
			current.Slots,
			current.Placed,
			state.MaxUpgrade,
			state.Priority,
			state.UsePriority,
			state.FarmFirst,
			current.Yen,
			state.BlockedUpgrades,
			now
		)
		local placementAffordable = placement and placement.Cost <= current.Yen
		if state.PlaceFirst and missing then
			if placementAffordable then
				place(ctx, state, current, placement)
			end
			return
		end
		if state.FarmFirst and upgradeChoice and upgradeChoice.Farm then
			upgrade(ctx, state, upgradeChoice)
			return
		end
		if placementAffordable and upgradeChoice then
			if placement.Cost <= upgradeChoice.Cost then
				place(ctx, state, current, placement)
			else
				upgrade(ctx, state, upgradeChoice)
			end
		elseif placementAffordable then
			place(ctx, state, current, placement)
		elseif upgradeChoice then
			upgrade(ctx, state, upgradeChoice)
		end
	end

	local function smartStatus(decision)
		if decision.Kind == "Place" then
			return "Planning: Deploying " .. tostring(decision.Slot and decision.Slot.Name or "unit")
		elseif decision.Kind == "Upgrade" then
			return "Planning: Upgrading " .. tostring(decision.Slot and decision.Slot.Name or "unit")
		elseif decision.Preview and decision.Preview.Kind == "Place" then
			return "Planning: Saving for deployment"
		elseif decision.Preview and decision.Preview.Kind == "Upgrade" then
			return "Planning: Saving for upgrade"
		end
		local reason = string.lower(tostring(decision.Reason or ""))
		if string.find(reason, "cap", 1, true) then
			return "Planning: Placement cap reached"
		elseif string.find(reason, "yen", 1, true) or string.find(reason, "save", 1, true) then
			return "Planning: Saving Yen"
		end
		return "Planning: Monitoring"
	end

	local function updateSmartLabels(state, decision)
		local context = decision.Context or {}
		local status = smartStatus(decision)
		if state.SmartStatusText ~= status and state.SmartStatusLabel then
			state.SmartStatusText = status
			state.SmartStatusLabel:UpdateName(status)
		end
		local scenario = "Scenario: " .. tostring(context.Scenario or "Waiting for match data")
		if state.SmartScenarioText ~= scenario and state.SmartScenarioLabel then
			state.SmartScenarioText = scenario
			state.SmartScenarioLabel:UpdateName(scenario)
		end
		local routeState = context.RouteConfident == false
			and " | Calibrating route"
			or (tonumber(context.BacklineEnemies) or 0) > 0
			and string.format(" | Backline: %d", tonumber(context.BacklineEnemies) or 0)
			or context.RecentLeak and " | Recovering coverage"
			or string.format(" | Coverage: %d%%", math.floor((tonumber(context.RouteCoverage) or 0) * 100 + 0.5))
		local threat = string.format(
			"Threat: %d%% | Enemies: %d | Wave: %d/%d%s%s%s%s",
			math.floor((tonumber(context.Pressure) or 0) * 100 + 0.5),
			tonumber(context.EnemyCount) or 0,
			tonumber(context.Wave) or 0,
			tonumber(context.MaxWave) or 0,
			context.Boss and " | Boss detected" or "",
			routeState,
			context.ModifierSummary and context.ModifierSummary ~= "None"
				and " | Modifiers: " .. context.ModifierSummary
				or "",
			context.ResistanceSummary and context.ResistanceSummary ~= "None"
				and " | Matchups: " .. context.ResistanceSummary
				or ""
		)
		if state.SmartThreatText ~= threat and state.SmartThreatLabel then
			state.SmartThreatText = threat
			state.SmartThreatLabel:UpdateName(threat)
		end
		local automation = string.format(
			"Automatic: Yen %d | Next %d | Reserve %d%% | Spacing %s",
			math.floor(tonumber(context.Yen) or 0),
			math.floor(tonumber(context.NextCost or decision.Cost) or 0),
			math.floor(tonumber(context.ReservePercent) or 0),
			context.Spacing and tostring(context.Spacing) or "Planning"
		)
		if state.SmartAutomationText ~= automation and state.SmartAutomationLabel then
			state.SmartAutomationText = automation
			state.SmartAutomationLabel:UpdateName(automation)
		end
		local reason = state.ShowSmartDecisions and ("Decision: " .. tostring(decision.Reason))
			or "Decision details are hidden."
		if state.SmartDecisionText ~= reason and state.SmartDecisionLabel then
			state.SmartDecisionText = reason
			state.SmartDecisionLabel:UpdateName(reason)
		end
	end

	local function updateSmartCompleteLabels(state, result)
		local outcome = type(result) == "table" and result.Victory == true and "Victory" or "Defeat"
		local labels = {
			{ "SmartStatusText", "SmartStatusLabel", "Planning: Match complete" },
			{ "SmartThreatText", "SmartThreatLabel", "Threat: Match complete" },
			{ "SmartAutomationText", "SmartAutomationLabel", "Automatic: Suspended until the next match" },
			{ "SmartDecisionText", "SmartDecisionLabel", "Decision: " .. outcome .. "; no further actions" },
		}
		for _, entry in ipairs(labels) do
			if state[entry[1]] ~= entry[3] and state[entry[2]] then
				state[entry[1]] = entry[3]
				state[entry[2]]:UpdateName(entry[3])
			end
		end
	end

	local function updateSmartWaitingLabels(state)
		local labels = {
			{ "SmartStatusText", "SmartStatusLabel", "Planning: Armed and waiting" },
			{ "SmartScenarioText", "SmartScenarioLabel", "Scenario: Waiting for match to start" },
			{ "SmartThreatText", "SmartThreatLabel", "Threat: Waiting for active match" },
			{ "SmartAutomationText", "SmartAutomationLabel", "Automatic: Waiting for active match" },
			{ "SmartDecisionText", "SmartDecisionLabel", "Decision: No actions before the match starts" },
		}
		for _, entry in ipairs(labels) do
			if state[entry[1]] ~= entry[3] and state[entry[2]] then
				state[entry[1]] = entry[3]
				state[entry[2]]:UpdateName(entry[3])
			end
		end
	end

	local function updateSmartVisualization(state, decision, candidate)
		local visual = decision and (decision.Kind == "Place" and decision or decision.Preview) or nil
		if not state.SmartVisualize or not visual or visual.Kind ~= "Place" or not candidate then
			destroyMarkers(state)
			return
		end
		local current = marker(state, "smart_next")
		current.Part.Color = decision.Kind == "Place" and Color3.fromRGB(75, 235, 130) or Color3.fromRGB(255, 190, 70)
		current.Part.Size = Vector3.new(0.16, math.max(3, visual.Spacing), math.max(3, visual.Spacing))
		current.Part.CFrame = candidate * CFrame.Angles(0, 0, math.pi / 2)
		current.Label.Text = string.format(
			decision.Kind == "Place" and "Next | Slot %d | %s" or "Planned | Slot %d | %s",
			visual.Slot.Index,
			visual.Slot.Name
		)
		for key, value in pairs(state.Markers) do
			if key ~= "smart_next" then
				value.Part:Destroy()
				state.Markers[key] = nil
			end
		end
	end

	local function smartAct(ctx, state, current)
		if not state.SmartEnabled or os.clock() < state.NextActionAt or not pendingComplete(state, current) then
			return
		end
		local blockedSlots = {}
		for index, expiresAt in pairs(state.BlockedSlots) do
			if expiresAt > os.clock() then
				blockedSlots[index] = true
			else
				state.BlockedSlots[index] = nil
			end
		end
		local decision = SmartPlanner.Decide(current, {
			Strategy = state.Strategy,
			AdaptivePlacement = state.AdaptivePlacement,
			SmartEconomy = state.SmartEconomy,
			ReactToEnemies = state.ReactToEnemies,
			BlockedSlots = blockedSlots,
			History = state.SmartHistory,
		})
		local context = decision.Context or {}
		local displayMap = JoinCatalog.MapDisplayName(ctx.Game:Information() or {}, context.Map)
		context.Scenario = string.format(
			"%s | %s | %s | %s",
			tostring(context.Mode or "Unknown"),
			tostring(displayMap or context.Map or "Unknown"),
			tostring(context.Act or "Unknown"),
			tostring(context.Difficulty or "Unknown")
		)
		state.LastSmartDecision = decision
		updateSmartLabels(state, decision)
		local visual = decision.Kind == "Place" and decision or decision.Preview
		local resolved, placementError
		if visual and visual.Kind == "Place" then
			resolved, placementError = findPlacement(state, current, visual)
		end
		updateSmartVisualization(state, decision, resolved)
		if state.Telemetry then state.Telemetry:Decision(decision, resolved) end
		if decision.Kind == "Place" then
			if resolved then
				place(ctx, state, current, decision, resolved)
			else
				state.BlockedSlots[decision.Slot.Index] = os.clock() + 1.25
				notify(ctx, state, "placement", placementError)
			end
		elseif decision.Kind == "Upgrade" then
			upgrade(ctx, state, decision)
		else
			state.NextActionAt = os.clock() + 0.15
		end
	end

	local function run(ctx, state)
		while state.Alive and ctx.Runtime.Alive do
			local ok, err = xpcall(function()
				if not state.Enabled and not state.Visualize and not state.SmartEnabled then
					state.LastWave, state.LastTime, state.LastTotal = nil, nil, nil
					if state.VisualFolder then
						destroyMarkers(state)
					end
					return
				end
				local result = ctx.Results and select(1, ctx.Results:Snapshot()) or nil
				if type(result) == "table" then
					if state.Telemetry and state.Telemetry.Active then
						local outcome = result.Victory == true and "Victory" or "Defeat"
						local saved, path, telemetryError = state.Telemetry:Finalize(outcome, result)
						if saved == false then notify(ctx, state, "telemetry_write", telemetryError) end
						state.LastTelemetryPath = path
						if state.TelemetryStatusLabel then state.TelemetryStatusLabel:UpdateName(state.Telemetry:Status()) end
					end
					state.Pending = nil
					state.NextActionAt = math.huge
					if state.SmartEnabled then
						updateSmartCompleteLabels(state, result)
					end
					destroyMarkers(state)
					return
				elseif state.NextActionAt == math.huge then
					state.NextActionAt = 0
				end
				local current = snapshot(ctx, state)
				if not current then
					state.Pending = nil
					state.LastWave, state.LastTime, state.LastTotal = nil, nil, nil
					if state.SmartEnabled then
						updateSmartWaitingLabels(state)
					end
					destroyMarkers(state)
					return
				end
				reconcileRound(state, current)
				if state.RecordTelemetry and state.SmartEnabled and state.Telemetry then
					state.Telemetry:Capture(current)
					if state.TelemetryStatusLabel then state.TelemetryStatusLabel:UpdateName(state.Telemetry:Status()) end
				end
				if state.SmartEnabled then
					smartAct(ctx, state, current)
				elseif state.Visualize and (state.VisualDirty or os.clock() - state.LastVisual >= 1) then
					state.LastVisual = os.clock()
					state.VisualDirty = false
					updateVisualization(state, current)
				elseif not state.Visualize and state.VisualFolder then
					destroyMarkers(state)
				end
				if not state.SmartEnabled then
					act(ctx, state, current)
				end
			end, debug.traceback)
			if not ok then
				notify(ctx, state, "worker", err)
			end
			task.wait(state.SmartEnabled and 0.1 or 0.25)
		end
	end

	local function slider(registry, section, state, collection, index, name, maximum, default, flag)
		return registry:Slider(section, {
			Name = name,
			Default = default,
			Minimum = 0,
			Maximum = maximum,
			Precision = 0,
			Step = 1,
			Callback = function(value)
				collection[index] = math.floor(value)
				state.VisualDirty = true
			end,
		}, flag)
	end

	return {
		Name = "AutoPlay",
		Version = 17,
		Priority = 9,
		Dependencies = {},

		Init = function(self, ctx)
			local state = {
				Alive = false,
				Enabled = false,
				FarmFirst = false,
				PlaceFirst = false,
				Visualize = false,
				SmartEnabled = false,
				Strategy = "Win",
				AdaptivePlacement = true,
				SmartEconomy = true,
				ReactToEnemies = true,
				SmartVisualize = true,
				ShowSmartDecisions = true,
				RecordTelemetry = false,
				UsePriority = false,
				Spacing = 6,
				PathPosition = 50,
				Priority = { 6, 5, 4, 3, 2, 1 },
				MaxPlace = { 1, 1, 1, 1, 1, 1 },
				MaxUpgrade = { 20, 20, 20, 20, 20, 20 },
				Pending = nil,
				PlaceRetries = {},
				BlockedSlots = {},
				BlockedUpgrades = {},
				UpgradeRetries = {},
				Markers = {},
				BoundingSizes = {},
				BoundingHeights = {},
				SmartHistory = {},
				RouteSignature = nil,
				RouteVote = 0,
				RouteReverse = false,
				RouteConfident = false,
				EnemyTracks = {},
				LastErrors = {},
				LastVisual = 0,
				VisualDirty = true,
				NextActionAt = 0,
				MatchDetected = false,
				Generation = ctx.Runtime.Generation,
				UnitUtils = loadHelper("UnitUtils"),
				Telemetry = MatchTelemetry.new(ctx.FileSystem, ctx.Player, ctx.Build),
			}
			local automation = ctx.Tabs.AutoPlayNormal:Section({ Side = "Left" })
			automation:Header({ Text = "Auto Play" })
			ctx.Registry:Toggle(automation, {
				Name = "Auto Play",
				Default = false,
				Callback = function(value)
					state.Enabled = value == true
				end,
			}, "auto_play.enabled")
			ctx.Registry:Toggle(automation, {
				Name = "Farm Units First",
				Default = false,
				Callback = function(value)
					state.FarmFirst = value == true
				end,
			}, "auto_play.farm_first")
			ctx.Registry:Toggle(automation, {
				Name = "Place Units First",
				Default = false,
				Callback = function(value)
					state.PlaceFirst = value == true
				end,
			}, "auto_play.place_first")
			ctx.Registry:Toggle(automation, {
				Name = "Visualize Placement",
				Default = false,
				Callback = function(value)
					state.Visualize = value == true
					state.VisualDirty = true
					if not value and not state.SmartEnabled then
						destroyMarkers(state)
					end
				end,
			}, "auto_play.visualize")
			ctx.Registry:Slider(automation, {
				Name = "Spacing",
				Default = 6,
				Minimum = 1,
				Maximum = 20,
				Precision = 0,
				Step = 1,
				Callback = function(value)
					state.Spacing = math.floor(value)
					state.VisualDirty = true
				end,
			}, "auto_play.spacing")
			ctx.Registry:Slider(automation, {
				Name = "Path Position",
				Default = 50,
				Minimum = 1,
				Maximum = 99,
				DisplayMethod = "LiteralPercent",
				Precision = 0,
				Step = 1,
				Callback = function(value)
					state.PathPosition = math.floor(value)
					state.VisualDirty = true
				end,
			}, "auto_play.path_position")
			automation:Paragraph({ Header = "Path Position", Body = "99 = near base, 1 = near enemy spawn." })

			local priorities = ctx.Tabs.AutoPlayNormal:Section({ Side = "Left" })
			priorities:Header({ Text = "Upgrade Priority" })
			ctx.Registry:Toggle(priorities, {
				Name = "Use Upgrade Priority",
				Default = false,
				Callback = function(value)
					state.UsePriority = value == true
				end,
			}, "auto_play.use_priority")
			for index = 1, 6 do
				slider(
					ctx.Registry,
					priorities,
					state,
					state.Priority,
					index,
					"Slot " .. index .. " Priority",
					10,
					7 - index,
					"auto_play.priority_" .. index
				)
			end
			priorities:Paragraph({
				Header = "How it works",
				Body = "Higher = upgraded first. 0 = never upgrade that slot.",
			})

			local placements = ctx.Tabs.AutoPlayNormal:Section({ Side = "Right" })
			placements:Header({ Text = "Placement Limits" })
			for index = 1, 6 do
				slider(
					ctx.Registry,
					placements,
					state,
					state.MaxPlace,
					index,
					"Slot " .. index .. " Max Place",
					20,
					1,
					"auto_play.max_place_" .. index
				)
			end

			local upgrades = ctx.Tabs.AutoPlayNormal:Section({ Side = "Right" })
			upgrades:Header({ Text = "Upgrade Limits" })
			for index = 1, 6 do
				slider(
					ctx.Registry,
					upgrades,
					state,
					state.MaxUpgrade,
					index,
					"Slot " .. index .. " Max Upgrade",
					20,
					20,
					"auto_play.max_upgrade_" .. index
				)
			end

			local smart = ctx.Tabs.AutoPlaySmart:Section({ Side = "Left" })
			smart:Header({ Text = "Smart Auto Play" })
			state.SmartStatusLabel = smart:Label({ Text = "Planning: Idle" })
			ctx.Registry:Toggle(smart, {
				Name = "Smart Auto Play",
				Default = false,
				Callback = function(value)
					state.SmartEnabled = value == true
					if not value and state.Telemetry and state.Telemetry.Active then
						state.LastTelemetryPath = select(2, state.Telemetry:Finalize("Smart Auto Play disabled"))
					end
					if not state.Pending then
						state.NextActionAt = 0
					end
					state.LastSmartDecision = nil
					destroyMarkers(state)
					if not value and state.SmartStatusLabel then
						state.SmartStatusText = "Planning: Idle"
						state.SmartStatusLabel:UpdateName(state.SmartStatusText)
					end
				end,
			}, "auto_play.smart.enabled")
			ctx.Registry:Dropdown(smart, {
				Name = "Strategy",
				Search = true,
				Multi = false,
				Required = true,
				Options = { "Win", "Balanced", "Economy", "Rush", "Boss" },
				Default = 1,
				Callback = function(value)
					state.Strategy = tostring(value or "Win")
				end,
			}, "auto_play.smart.strategy")
			ctx.Registry:Toggle(smart, {
				Name = "Adaptive Placement",
				Default = true,
				Callback = function(value)
					state.AdaptivePlacement = value == true
				end,
			}, "auto_play.smart.adaptive_placement")
			ctx.Registry:Toggle(smart, {
				Name = "Smart Economy",
				Default = true,
				Callback = function(value)
					state.SmartEconomy = value == true
				end,
			}, "auto_play.smart.economy")
			ctx.Registry:Toggle(smart, {
				Name = "React to Current Enemies",
				Default = true,
				Callback = function(value)
					state.ReactToEnemies = value == true
				end,
			}, "auto_play.smart.react_to_enemies")
			ctx.Registry:Toggle(smart, {
				Name = "Visualize Smart Placement",
				Default = true,
				Callback = function(value)
					state.SmartVisualize = value == true
					if not value then
						destroyMarkers(state)
					end
				end,
			}, "auto_play.smart.visualize")
			ctx.Registry:Toggle(smart, {
				Name = "Show Smart Decisions",
				Default = true,
				Callback = function(value)
					state.ShowSmartDecisions = value == true
					state.SmartDecisionText = nil
				end,
			}, "auto_play.smart.show_decisions")
			ctx.Registry:Toggle(smart, {
				Name = "Record Match Telemetry",
				Default = false,
				Callback = function(value)
					state.RecordTelemetry = value == true
					state.Telemetry:SetEnabled(state.RecordTelemetry)
					if state.TelemetryStatusLabel then state.TelemetryStatusLabel:UpdateName(state.Telemetry:Status()) end
				end,
			}, "auto_play.smart.record_telemetry")
			state.TelemetryStatusLabel = smart:Label({ Text = "Telemetry: Off" })
			smart:Paragraph({
				Header = "Match telemetry",
				Body = "Records routes, enemies, positions, loadout, placements, upgrades, Yen, modifiers, decisions and results to AnimeExpeditionsHubData/telemetry/matches/<userid>.",
			})

			local live = ctx.Tabs.AutoPlaySmart:Section({ Side = "Right" })
			live:Header({ Text = "Live Planner" })
			state.SmartScenarioLabel = live:Label({ Text = "Scenario: Waiting for match to start" })
			state.SmartThreatLabel = live:Label({ Text = "Threat: Waiting for active match" })
			state.SmartAutomationLabel = live:Label({ Text = "Automatic: Waiting for active match" })
			state.SmartDecisionLabel = live:Label({ Text = "Decision: No actions before the match starts" })
			live:Paragraph({
				Header = "How it works",
				Body = "Smart mode ignores every Normal setting. It recalculates placement, upgrades, economy and risk from the live map, mode, act, difficulty, wave and enemies before every confirmed action.",
			})
			ctx:RegisterCleanup(function()
				state.Alive = false
				if state.Telemetry then state.Telemetry:Finalize("Script unloaded") end
				destroyMarkers(state)
			end)
			return state
		end,

		Enable = function(self, ctx, state)
			state.Alive = true
			local worker = task.spawn(function()
				run(ctx, state)
			end)
			ctx:RegisterCleanup(worker)
		end,

		Disable = function(self, ctx, state)
			state.Alive = false
			state.Enabled = false
			state.SmartEnabled = false
			state.Pending = nil
			if state.Telemetry then state.Telemetry:Finalize("Module disabled") end
			destroyMarkers(state)
		end,
	}
end
