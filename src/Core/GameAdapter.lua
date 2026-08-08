return function(Import)
	local Util = Import("Util")
	local GameAdapter = {}
	GameAdapter.__index = GameAdapter

	local function loadModule(instance, label)
		if not instance then return nil, label .. " was not found" end
		local ok, result = xpcall(function() return require(instance) end, Util.Traceback)
		if not ok then return nil, label .. " failed to load:\n" .. tostring(result) end
		if type(result) ~= "table" then return nil, label .. " returned " .. type(result) end
		return result
	end

	function GameAdapter.new()
		local self = setmetatable({Ready = false}, GameAdapter)
		local replicatedStorage = game:GetService("ReplicatedStorage")
		local fusionPackage = replicatedStorage:FindFirstChild("FusionPackage")
		local nodes, nodesError = loadModule(replicatedStorage:FindFirstChild("Nodes"), "ReplicatedStorage.Nodes")
		local dependencies, dependenciesError = loadModule(
			fusionPackage and fusionPackage:FindFirstChild("Dependencies"),
			"FusionPackage.Dependencies"
		)
		local fusion, fusionError = loadModule(fusionPackage and fusionPackage:FindFirstChild("Fusion"), "FusionPackage.Fusion")
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
		self.Ready = true
		return self
	end

	function GameAdapter:Peek(value)
		if not self.Ready then return nil, self.Error end
		local ok, result = xpcall(function() return self.Fusion.peek(value) end, Util.Traceback)
		if not ok then return nil, tostring(result) end
		return result
	end

	function GameAdapter:State(name)
		if not self.Ready then return nil, self.Error end
		local state = self.Dependencies[name]
		if state == nil then return nil, "unknown replicated state '" .. tostring(name) .. "'" end
		return self:Peek(state)
	end

	function GameAdapter:PlayerData()
		local data, err = self:State("PlayerData")
		if type(data) == "table" then return data end
		return nil, err or "PlayerData has not replicated yet"
	end

	function GameAdapter:Information()
		if not self.Ready then return nil, self.Error end
		return self.Dependencies.Information
	end

	function GameAdapter:Fire(nodeName, ...)
		if not self.Ready then return false, self.Error end
		local node = self.Nodes[nodeName]
		if type(node) ~= "table" or type(node.FireServer) ~= "function" then
			return false, "network node '" .. tostring(nodeName) .. "' is unavailable or is not a server event"
		end
		local arguments = table.pack(...)
		local ok, err = xpcall(function()
			node:FireServer(table.unpack(arguments, 1, arguments.n))
		end, Util.Traceback)
		if not ok then return false, tostring(err) end
		return true
	end

	function GameAdapter:Request(nodeName, timeout, ...)
		if not self.Ready then return false, self.Error end
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
			if type(request.Timeout) == "function" then request:Timeout(tonumber(timeout) or 5) end
			return request:Wait()
		end, Util.Traceback))
		if not results[1] then return false, tostring(results[2]) end
		return true, table.unpack(results, 2, results.n)
	end

	return GameAdapter
end
