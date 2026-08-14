return function(Import)
	local Util = Import("Util")
	local GameAdapter = {}
	GameAdapter.__index = GameAdapter
	local DEFAULT_STARTUP_TIMEOUT = 20

	local function waitForChild(parent, name, deadline)
		if not parent then return nil end
		local child = parent:FindFirstChild(name)
		if child then return child end
		local remaining = deadline - os.clock()
		if remaining <= 0 then return nil end
		return parent:WaitForChild(name, remaining)
	end

	local function loadModule(instance, label)
		if not instance then
			return nil, label .. " was not found"
		end
		local ok, result = xpcall(function()
			return require(instance)
		end, Util.Traceback)
		if not ok then
			return nil, label .. " failed to load:\n" .. tostring(result)
		end
		if type(result) ~= "table" then
			return nil, label .. " returned " .. type(result)
		end
		return result
	end

	function GameAdapter.new(timeout)
		local self = setmetatable({
			Ready = false,
			RespondedVotes = setmetatable({}, { __mode = "k" }),
			LocalPlayer = game:GetService("Players").LocalPlayer,
		}, GameAdapter)
		local startupTimeout = math.max(tonumber(timeout) or DEFAULT_STARTUP_TIMEOUT, 0)
		local deadline = os.clock() + startupTimeout
		local replicatedStorage = game:GetService("ReplicatedStorage")
		local fusionPackage = waitForChild(replicatedStorage, "FusionPackage", deadline)
		local shared = waitForChild(replicatedStorage, "Shared", deadline)
		local nodesInstance = waitForChild(replicatedStorage, "Nodes", deadline)
		local dependenciesInstance = waitForChild(fusionPackage, "Dependencies", deadline)
		local fusionInstance = waitForChild(fusionPackage, "Fusion", deadline)
		local actionsInstance = waitForChild(fusionPackage, "Actions", deadline)
		local stateInstance = waitForChild(fusionPackage, "State", deadline)
		local nodes, nodesError = loadModule(nodesInstance, "ReplicatedStorage.Nodes")
		local dependencies, dependenciesError =
			loadModule(dependenciesInstance, "FusionPackage.Dependencies")
		local fusion, fusionError =
			loadModule(fusionInstance, "FusionPackage.Fusion")
		local actions, actionsError = loadModule(actionsInstance, "FusionPackage.Actions")
		local stateLibrary, stateError = loadModule(stateInstance, "FusionPackage.State")
		local fusionPeek = type(fusion) == "table" and fusion.peek or nil
		local peekError
		if type(fusionPeek) ~= "function" and fusionInstance then
			local stateInstance = waitForChild(fusionInstance, "State", deadline)
			local peekInstance = waitForChild(stateInstance, "peek", deadline)
			if peekInstance then
				local ok, result = xpcall(function() return require(peekInstance) end, Util.Traceback)
				if ok and type(result) == "function" then
					fusionPeek = result
				else
					peekError = ok and "Fusion State.peek returned " .. type(result)
						or "Fusion State.peek failed to load:\n" .. tostring(result)
				end
			else
				peekError = "Fusion State.peek was not replicated before the startup timeout"
			end
		end
		if not nodes or not dependencies or not fusion or not actions or type(fusionPeek) ~= "function" then
			local errors = {}
			for _, message in ipairs({nodesError, dependenciesError, fusionError, actionsError, peekError}) do
				if type(message) == "string" and message ~= "" then table.insert(errors, message) end
			end
			if type(fusionPeek) ~= "function" and not peekError then
				table.insert(errors, "Fusion.peek is unavailable")
			end
			self.Error = "game bindings were not ready within "
				.. tostring(startupTimeout)
				.. " seconds:\n"
				.. table.concat(errors, "\n")
			return self
		end
		self.Nodes = nodes
		self.Dependencies = dependencies
		self.Fusion = fusion
		self.FusionPeek = fusionPeek
		self.Actions = actions
		self.StateLibrary = stateLibrary
		self.ResultStateError = stateError
		self.ReplicaClient =
			select(1, loadModule(shared and shared:FindFirstChild("ReplicaClient"), "Shared.ReplicaClient"))
		self.Ready = true
		return self
	end

	function GameAdapter:ResultData()
		if not self.Ready then
			return nil, self.Error
		end
		if self.ResultState == nil then
			if type(self.StateLibrary) ~= "table" or type(self.Fusion.scoped) ~= "function" then
				return nil, self.ResultStateError or "Fusion ResultData access is unavailable"
			end
			local scope
			local ok, stateOrError = xpcall(function()
				scope = self.Fusion.scoped(self.Fusion, self.StateLibrary)
				if type(scope) ~= "table" or type(scope.GetState) ~= "function" then
					error("Fusion state scope does not expose GetState")
				end
				return scope:GetState("ResultData")
			end, Util.Traceback)
			if not ok then
				if scope and type(scope.doCleanup) == "function" then
					pcall(scope.doCleanup, scope)
				end
				self.ResultStateError = tostring(stateOrError)
				return nil, self.ResultStateError
			end
			self.ResultScope = scope
			self.ResultState = stateOrError
		end
		local result = self:DeepPeek(self.ResultState, 8)
		if type(result) ~= "table" then
			return nil, "ResultData is empty"
		end
		return result
	end

	function GameAdapter:Destroy()
		local scope = self.ResultScope
		self.ResultScope = nil
		self.ResultState = nil
		if scope and type(scope.doCleanup) == "function" then
			pcall(scope.doCleanup, scope)
		end
	end

	function GameAdapter:Peek(value)
		if not self.Ready then
			return nil, self.Error
		end
		local ok, result = xpcall(function()
			return self.FusionPeek(value)
		end, Util.Traceback)
		if not ok then
			return nil, tostring(result)
		end
		return result
	end

	function GameAdapter:State(name)
		if not self.Ready then
			return nil, self.Error
		end
		local state = self.Dependencies[name]
		if state == nil then
			return nil, "unknown replicated state '" .. tostring(name) .. "'"
		end
		return self:Peek(state)
	end

	function GameAdapter:DeepPeek(value, depth, seen)
		depth = tonumber(depth) or 4
		seen = seen or {}
		local peeked = self:Peek(value)
		if peeked ~= nil then
			value = peeked
		end
		if type(value) ~= "table" or depth <= 0 then
			return value
		end
		if seen[value] then
			return seen[value]
		end
		local output = {}
		seen[value] = output
		for key, child in pairs(value) do
			output[key] = self:DeepPeek(child, depth - 1, seen)
		end
		return output
	end

	function GameAdapter:StateDeep(name, depth)
		if not self.Ready then
			return nil, self.Error
		end
		local state = self.Dependencies[name]
		if state == nil then
			return nil, "unknown replicated state '" .. tostring(name) .. "'"
		end
		return self:DeepPeek(state, depth)
	end

	function GameAdapter:PlayerData()
		local data, err = self:State("PlayerData")
		if type(data) == "table" then
			return data
		end
		return nil, err or "PlayerData has not replicated yet"
	end

	function GameAdapter:GameData()
		local ok, replica = self:InvokeSelf("GET_GAME_REPLICA")
		if ok and type(replica) == "table" and type(replica.Data) == "table" then
			return replica.Data, "replica"
		end
		local data, err = self:StateDeep("GameState", 5)
		if type(data) == "table" then
			return data, "state"
		end
		return nil, err or replica or "GameState has not replicated yet"
	end

	function GameAdapter:CurrentGamemode()
		local ok, data = xpcall(function()
			return self:GameData()
		end, Util.Traceback)
		if not ok or type(data) ~= "table" then
			data = self:StateDeep("GameState", 5)
		end
		if type(data) ~= "table" then
			return nil
		end
		local parameters = type(data.Parameters) == "table" and data.Parameters or nil
		local gamemode = parameters and parameters.Gamemode or data.Gamemode
		if type(gamemode) ~= "string" or gamemode == "" then
			return nil
		end
		return gamemode
	end

	function GameAdapter:GamePlayerData()
		local ok, replica = self:InvokeSelf("GET_GAME_PLAYER_REPLICA")
		if ok and type(replica) == "table" and type(replica.Data) == "table" then
			return replica.Data, "replica"
		end
		local data, err = self:StateDeep("GamePlayerState", 4)
		if type(data) == "table" then
			return data, "state"
		end
		return nil, err or replica or "GamePlayerState has not replicated yet"
	end

	function GameAdapter:HotbarData()
		local ok, replica = self:InvokeSelf("GET_HOTBAR_REPLICA")
		if ok and type(replica) == "table" and type(replica.Data) == "table" then
			return replica.Data, "replica"
		end
		local data, err = self:StateDeep("HotbarState", 4)
		if type(data) == "table" then
			return data, "state"
		end
		return nil, err or replica or "HotbarState has not replicated yet"
	end

	function GameAdapter:Information()
		if not self.Ready then
			return nil, self.Error
		end
		return self.Dependencies.Information
	end

	function GameAdapter:InvokeSelf(nodeName, ...)
		if not self.Ready then
			return false, self.Error
		end
		local node = self.Nodes[nodeName]
		if type(node) ~= "table" or type(node.InvokeSelf) ~= "function" then
			return false, "local node '" .. tostring(nodeName) .. "' is unavailable"
		end
		local arguments = table.pack(...)
		local results = table.pack(xpcall(function()
			return node:InvokeSelf(table.unpack(arguments, 1, arguments.n))
		end, Util.Traceback))
		if not results[1] then
			return false, tostring(results[2])
		end
		return true, table.unpack(results, 2, results.n)
	end

	function GameAdapter:Connect(nodeName, callback)
		if not self.Ready then
			return nil, self.Error
		end
		local node = self.Nodes[nodeName]
		if type(node) ~= "table" or type(node.Connect) ~= "function" then
			return nil, "network node '" .. tostring(nodeName) .. "' is unavailable or cannot be observed"
		end
		local ok, connection = xpcall(function()
			return node:Connect(callback)
		end, Util.Traceback)
		if not ok then
			return nil, tostring(connection)
		end
		return connection
	end

	function GameAdapter:Fire(nodeName, ...)
		if not self.Ready then
			return false, self.Error
		end
		local node = self.Nodes[nodeName]
		if type(node) ~= "table" or type(node.FireServer) ~= "function" then
			return false, "network node '" .. tostring(nodeName) .. "' is unavailable or is not a server event"
		end
		local arguments = table.pack(...)
		local ok, err = xpcall(function()
			node:FireServer(table.unpack(arguments, 1, arguments.n))
		end, Util.Traceback)
		if not ok then
			return false, tostring(err)
		end
		return true
	end

	function GameAdapter:Action(actionName, ...)
		if not self.Ready then
			return false, self.Error
		end
		local action = type(self.Actions) == "table" and rawget(self.Actions, actionName) or nil
		if type(action) ~= "function" then
			return false, "bound game action '" .. tostring(actionName) .. "' is unavailable"
		end
		local arguments = table.pack(...)
		local results = table.pack(xpcall(function()
			return action(table.unpack(arguments, 1, arguments.n))
		end, Util.Traceback))
		if not results[1] then
			return false, tostring(results[2])
		end
		return true, table.unpack(results, 2, results.n)
	end

	function GameAdapter:FireLocal(nodeName, ...)
		if not self.Ready then
			return false, self.Error
		end
		local node = self.Nodes[nodeName]
		local method = type(node) == "table" and (node.FireSelf or node.Fire) or nil
		if type(method) ~= "function" then
			return false, "local node '" .. tostring(nodeName) .. "' is unavailable or cannot be fired"
		end
		local arguments = table.pack(...)
		local ok, err = xpcall(function()
			method(node, table.unpack(arguments, 1, arguments.n))
		end, Util.Traceback)
		if not ok then
			return false, tostring(err)
		end
		return true
	end

	function GameAdapter:Request(nodeName, timeout, ...)
		if not self.Ready then
			return false, self.Error
		end
		local node = self.Nodes[nodeName]
		if type(node) ~= "table" or type(node.Request) ~= "function" then
			return false, "network node '" .. tostring(nodeName) .. "' is unavailable or is not a request node"
		end
		local arguments = table.pack(...)
		local results = table.pack(xpcall(function()
			local request = node:Request(table.unpack(arguments, 1, arguments.n))
			if type(request) ~= "table" or type(request.Wait) ~= "function" then
				error("request node '" .. tostring(nodeName) .. "' returned an invalid request object")
			end
			if type(request.Timeout) == "function" then
				request:Timeout(tonumber(timeout) or 5)
			end
			return request:Wait()
		end, Util.Traceback))
		if not results[1] then
			return false, tostring(results[2])
		end
		return true, table.unpack(results, 2, results.n)
	end

	function GameAdapter:IsInGame()
		if not self.Ready or type(self.Dependencies) ~= "table" then
			return false
		end
		local gameState = self.Dependencies.GameState
		if gameState == nil then
			return false
		end
		local value = self:Peek(gameState)
		if type(value) == "table" then
			return next(value) ~= nil
		end
		return value ~= nil and value ~= false
	end

	function GameAdapter:LeaveMatchmaking()
		local ok, response = self:Request("REQUEST_LEAVE_MATCHMAKING", 5)
		if not ok then
			return false, response
		end
		if response == false then
			return false, "the game rejected the matchmaking leave request"
		end
		return true
	end

	function GameAdapter:Join(queueData, matchmaking, timeout)
		if type(queueData) ~= "table" then
			return false, "queue data is invalid"
		end
		if matchmaking then
			local session = self:State("SessionData")
			if type(session) == "table" and (session.Matchmaking == true or session.MatchmakingFound == true) then
				return true
			end
			local ok, response = self:Request("REQUEST_ENTER_MATCHMAKING", timeout or 5, queueData)
			if not ok then
				return false, response
			end
			if response == false then
				return false, "the game rejected the matchmaking request"
			end
			return true
		end

		local replicaOk, replica = self:InvokeSelf("GET_PARTY_DATA_REPLICA")
		if not replicaOk then
			return false, replica
		end
		if type(replica) ~= "table" or type(replica.FireServer) ~= "function" then
			local createOk, response = self:Request("PARTY_CREATE", timeout or 5, queueData)
			if not createOk then
				return false, response
			end
			if response == false then
				return false, "the game rejected the party creation request"
			end
			local waitOk
			waitOk, replica = self:InvokeSelf("WAIT_FOR_PARTY_REPLICA")
			if not waitOk then
				return false, replica
			end
		end
		if type(replica) ~= "table" or type(replica.FireServer) ~= "function" then
			return false, "party replica did not become available"
		end
		local ok, err = xpcall(function()
			replica:FireServer("SetQueueData", queueData)
			replica:FireServer("StartGame")
		end, Util.Traceback)
		if not ok then
			return false, tostring(err)
		end
		return true
	end

	function GameAdapter:ReturnToLobby()
		local ok, replica = self:InvokeSelf("GET_GAME_REPLICA")
		if not ok then
			return false, replica
		end
		if type(replica) ~= "table" or type(replica.FireServer) ~= "function" then
			return false, "game replica is unavailable"
		end
		local fired, err = xpcall(function()
			replica:FireServer("Lobby")
		end, Util.Traceback)
		if not fired then
			return false, tostring(err)
		end
		return true
	end

	function GameAdapter:GameAction(action, ...)
		local ok, replica = self:InvokeSelf("GET_GAME_REPLICA")
		if not ok then
			return false, replica
		end
		if type(replica) ~= "table" or type(replica.FireServer) ~= "function" then
			return false, "game replica is unavailable"
		end
		local arguments = table.pack(...)
		local fired, err = xpcall(function()
			replica:FireServer(tostring(action), table.unpack(arguments, 1, arguments.n))
		end, Util.Traceback)
		if not fired then
			return false, tostring(err)
		end
		return true
	end

	function GameAdapter:GamePlayerAction(action, ...)
		local ok, replica = self:InvokeSelf("GET_GAME_PLAYER_REPLICA")
		if not ok then
			return false, replica
		end
		if type(replica) ~= "table" or type(replica.FireServer) ~= "function" then
			return false, "game player replica is unavailable"
		end
		local arguments = table.pack(...)
		local fired, err = xpcall(function()
			replica:FireServer(tostring(action), table.unpack(arguments, 1, arguments.n))
		end, Util.Traceback)
		if not fired then
			return false, tostring(err)
		end
		return true
	end

	function GameAdapter:ChangeSetting(name, value)
		return self:Fire("CLIENT_CHANGE_SETTING", tostring(name), value)
	end

	function GameAdapter.MatchActive(gameState)
		if type(gameState) ~= "table" or GameAdapter.MatchEnded(gameState) then
			return false
		end
		local wave = math.max(tonumber(gameState.Wave) or 0, tonumber(gameState.CurrentWave) or 0)
		local elapsed = math.max(
			tonumber(gameState.SessionTime) or 0,
			tonumber(gameState.GameTime) or 0,
			tonumber(gameState.Time) or 0
		)
		local enemies = tonumber(gameState.EnemyCount) or 0
		local status = string.lower(tostring(gameState.Status or gameState.GameStatus or ""))
		return gameState.Active == true
			or gameState.WavesEnabled == true
			or wave > 0
			or elapsed > 0
			or enemies > 0
			or status == "active"
			or status == "playing"
			or status == "started"
	end

	function GameAdapter.MatchEnded(gameState)
		if type(gameState) ~= "table" then
			return false
		end
		local status = string.lower(tostring(gameState.Status or gameState.GameStatus or ""))
		return gameState.GameEnded == true or status == "ended" or status == "completed" or status == "results"
	end

	function GameAdapter:IsMatchActive(gameState)
		if type(gameState) ~= "table" then
			gameState = self:GameData()
		end
		if GameAdapter.MatchEnded(gameState) then
			return false
		end
		if GameAdapter.MatchActive(gameState) then
			return true
		end
		local replicaClient = self.ReplicaClient
		if type(replicaClient) == "table" and type(replicaClient.Test) == "function" then
			local ok, registry = pcall(replicaClient.Test)
			local prompts = ok
					and type(registry) == "table"
					and type(registry.TokenReplicas) == "table"
					and registry.TokenReplicas.VotePrompt
				or nil
			for replica in pairs(type(prompts) == "table" and prompts or {}) do
				local data = type(replica) == "table" and replica.Data or nil
				local parameters = type(data) == "table" and data.Parameters or nil
				local title = string.lower(tostring(type(parameters) == "table" and parameters.Title or ""))
				if string.find(title, "skip", 1, true) then
					return true
				end
			end
		end
		local enemies = self:State("GameEnemies")
		if type(enemies) == "table" and next(enemies) ~= nil then
			return true
		end
		local folder = game:GetService("Workspace"):FindFirstChild("Enemies")
		return folder ~= nil and #folder:GetChildren() > 0
	end

	function GameAdapter:IsMatchEnded(gameState)
		return GameAdapter.MatchEnded(gameState)
	end

	local function hasLocalResponse(data, player)
		local responses = type(data) == "table" and data.Responses or nil
		if type(responses) ~= "table" or not player then
			return false
		end
		if responses[player] ~= nil or responses[player.UserId] ~= nil or responses[tostring(player.UserId)] ~= nil then
			return true
		end
		local players = type(data.Players) == "table" and data.Players or {}
		for index, entry in pairs(players) do
			if entry == player and responses[index] ~= nil then
				return true
			end
		end
		for key, value in pairs(responses) do
			if key == player or tostring(key) == player.Name or tostring(key) == tostring(player.UserId) then
				return true
			end
			if type(value) == "table" then
				local identity = value.Player or value.UserId or value.PlayerId or value.Name
				if
					identity == player
					or tostring(identity) == player.Name
					or tostring(identity) == tostring(player.UserId)
				then
					return true
				end
			end
		end
		return false
	end

	function GameAdapter:RespondToVote(kind)
		local replicaClient = self.ReplicaClient
		if type(replicaClient) ~= "table" or type(replicaClient.Test) ~= "function" then
			return false, "vote prompt registry is unavailable"
		end
		local wanted = string.lower(tostring(kind or ""))
		self.RespondedVotes = self.RespondedVotes or setmetatable({}, { __mode = "k" })
		local ok, registry = xpcall(function()
			return replicaClient.Test()
		end, Util.Traceback)
		if not ok then
			return false, tostring(registry)
		end
		local prompts = type(registry) == "table"
				and type(registry.TokenReplicas) == "table"
				and registry.TokenReplicas.VotePrompt
			or nil
		for replica in pairs(type(prompts) == "table" and prompts or {}) do
			local data = type(replica) == "table" and replica.Data or nil
			local parameters = type(data) == "table" and data.Parameters or nil
			local title = string.lower(tostring(type(parameters) == "table" and parameters.Title or ""))
			if string.find(title, wanted, 1, true) and type(replica.FireServer) == "function" then
				local signature = title .. ":" .. tostring(type(parameters) == "table" and parameters.EndTime or "")
				if self.RespondedVotes[replica] == signature or hasLocalResponse(data, self.LocalPlayer) then
					self.RespondedVotes[replica] = signature
					return true, false
				end
				local fired, fireError = xpcall(function()
					replica:FireServer("Response", true)
				end, Util.Traceback)
				if not fired then
					return false, tostring(fireError)
				end
				self.RespondedVotes[replica] = signature
				return true, true
			end
		end
		return true, false
	end

	return GameAdapter
end
