return function(Import)
	local Util = Import("Util")
	local GameAdapter = {}
	GameAdapter.__index = GameAdapter

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

	function GameAdapter.new()
		local self = setmetatable({
			Ready = false,
			RespondedVotes = setmetatable({}, { __mode = "k" }),
			LocalPlayer = game:GetService("Players").LocalPlayer,
		}, GameAdapter)
		local replicatedStorage = game:GetService("ReplicatedStorage")
		local fusionPackage = replicatedStorage:FindFirstChild("FusionPackage")
		local shared = replicatedStorage:FindFirstChild("Shared")
		local nodes, nodesError = loadModule(replicatedStorage:FindFirstChild("Nodes"), "ReplicatedStorage.Nodes")
		local dependencies, dependenciesError =
			loadModule(fusionPackage and fusionPackage:FindFirstChild("Dependencies"), "FusionPackage.Dependencies")
		local fusion, fusionError =
			loadModule(fusionPackage and fusionPackage:FindFirstChild("Fusion"), "FusionPackage.Fusion")
		if not nodes or not dependencies or not fusion or type(fusion.peek) ~= "function" then
			self.Error = table.concat({
				nodesError or "",
				dependenciesError or "",
				fusionError or (fusion and "Fusion.peek is unavailable" or ""),
			}, "\n")
			return self
		end
		self.Nodes = nodes
		self.Dependencies = dependencies
		self.Fusion = fusion
		self.ReplicaClient =
			select(1, loadModule(shared and shared:FindFirstChild("ReplicaClient"), "Shared.ReplicaClient"))
		self.Ready = true
		return self
	end

	function GameAdapter:Peek(value)
		if not self.Ready then
			return nil, self.Error
		end
		local ok, result = xpcall(function()
			return self.Fusion.peek(value)
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

	function GameAdapter:PlayerData()
		local data, err = self:State("PlayerData")
		if type(data) == "table" then
			return data
		end
		return nil, err or "PlayerData has not replicated yet"
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
		local ok, replica = self:InvokeSelf("GET_GAME_REPLICA")
		return ok and type(replica) == "table" and type(replica.FireServer) == "function"
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
		if type(gameState) ~= "table" or type(gameState.Parameters) ~= "table" or gameState.GameEnded == true then
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
		if status == "ended" or status == "completed" or status == "results" then
			return false
		end
		return gameState.Active == true
			or gameState.WavesEnabled == true
			or wave > 0
			or elapsed > 0
			or enemies > 0
			or status == "active"
			or status == "playing"
			or status == "started"
	end

	function GameAdapter:IsMatchActive(gameState)
		return GameAdapter.MatchActive(gameState)
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
