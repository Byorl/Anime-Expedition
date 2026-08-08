return function(Import)
	local Util = Import("Util")
	local JoinCoordinator = {}
	JoinCoordinator.__index = JoinCoordinator

	local function queueKey(queue)
		if type(queue) ~= "table" then return "" end
		local factions = type(queue.Factions) == "table" and table.concat(queue.Factions, ",") or ""
		return table.concat({queue.Gamemode or "", queue.MapName or "", queue.ActName or "", queue.Difficulty or "", queue.ChallengeType or "", queue.ChallengeIndex or "", factions}, "|")
	end

	function JoinCoordinator.new(runtime, gameAdapter)
		local self = setmetatable({
			Alive = true,
			Runtime = runtime,
			Game = gameAdapter,
			Providers = {},
			PendingKey = nil,
			PendingSince = 0,
			LastAttemptKey = nil,
			LastAttemptAt = 0,
			OwnMatchmaking = false,
			LastError = nil,
			LastErrorAt = 0,
		}, JoinCoordinator)
		self.Worker = task.spawn(function() self:_Run() end)
		return self
	end

	function JoinCoordinator:Register(name, priority, provider)
		assert(type(name) == "string" and name ~= "", "join provider requires a name")
		assert(type(provider) == "function", "join provider requires a callback")
		self.Providers[name] = {Name = name, Priority = tonumber(priority) or 100, Callback = provider}
		return function()
			self.Providers[name] = nil
			if self.PendingKey and string.sub(self.PendingKey, 1, #name + 1) == name .. ":" then self.PendingKey = nil end
		end
	end

	function JoinCoordinator:_NotifyError(message)
		message = tostring(message)
		if message == self.LastError and os.clock() - self.LastErrorAt < 10 then return end
		self.LastError, self.LastErrorAt = message, os.clock()
		if self.Runtime and self.Runtime.Notify then self.Runtime:Notify("Auto Join", message) else Util.Warn("Auto Join: " .. message) end
	end

	function JoinCoordinator:_Candidate()
		local candidates = {}
		for _, provider in pairs(self.Providers) do
			local ok, candidate = xpcall(provider.Callback, Util.Traceback)
			if not ok then self:_NotifyError(provider.Name .. " catalog failed: " .. tostring(candidate))
			elseif type(candidate) == "table" and type(candidate.Queue) == "table" then
				candidate.Provider = provider.Name
				candidate.Priority = tonumber(candidate.Priority) or provider.Priority
				table.insert(candidates, candidate)
			end
		end
		table.sort(candidates, function(a, b)
			if a.Priority ~= b.Priority then return a.Priority > b.Priority end
			return a.Provider < b.Provider
		end)
		return candidates[1]
	end

	function JoinCoordinator:_Run()
		while self.Alive and self.Runtime.Alive do
			local candidate = self:_Candidate()
			if not candidate then
				self.PendingKey = nil
				if self.OwnMatchmaking then
					self.Game:LeaveMatchmaking()
					self.OwnMatchmaking = false
				end
				task.wait(0.25)
			else
				local key = candidate.Provider .. ":" .. queueKey(candidate.Queue) .. ":" .. tostring(candidate.Matchmaking == true)
				if key ~= self.PendingKey then
					if self.OwnMatchmaking and self.LastAttemptKey ~= key then
						self.Game:LeaveMatchmaking()
						self.OwnMatchmaking = false
					end
					self.PendingKey = key
					self.PendingSince = os.clock()
				end

				local delay = math.max(0, tonumber(candidate.Delay) or 0)
				local retryAfter = candidate.Matchmaking and 15 or 12
				if os.clock() - self.PendingSince >= delay and (self.LastAttemptKey ~= key or os.clock() - self.LastAttemptAt >= retryAfter) then
					if not self.Game:IsInGame() then
						local ok, err = self.Game:Join(candidate.Queue, candidate.Matchmaking == true, 5)
						self.LastAttemptKey, self.LastAttemptAt = key, os.clock()
						if ok then self.OwnMatchmaking = candidate.Matchmaking == true
						else self:_NotifyError(candidate.Provider .. " join failed: " .. tostring(err)) end
					end
				end
				task.wait(0.2)
			end
		end
	end

	function JoinCoordinator:Destroy()
		if not self.Alive then return end
		self.Alive = false
		if self.OwnMatchmaking then self.Game:LeaveMatchmaking() end
		if self.Worker and type(task.cancel) == "function" then pcall(task.cancel, self.Worker) end
		table.clear(self.Providers)
	end

	return JoinCoordinator
end
