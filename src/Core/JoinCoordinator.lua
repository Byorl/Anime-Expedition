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
			LastStatus = nil,
			PriorityEnabled = false,
			Priorities = {},
		}, JoinCoordinator)
		self.Worker = task.spawn(function() self:_Run() end)
		return self
	end

	function JoinCoordinator:SetPriorityEnabled(enabled)
		self.PriorityEnabled = enabled == true
		self.PendingKey = nil
	end

	function JoinCoordinator:SetSuspended(suspended)
		self.Suspended = suspended == true
		self.PendingKey = nil
		self.PendingSince = 0
	end

	function JoinCoordinator:SetPriority(name, priority)
		if type(name) ~= "string" or name == "" then return false end
		self.Priorities[name] = math.clamp(math.floor((tonumber(priority) or 1) + 0.5), 1, 6)
		self.PendingKey = nil
		return true
	end

	function JoinCoordinator:Modes()
		local modes = {}
		for name in pairs(self.Providers) do table.insert(modes, name) end
		table.sort(modes, function(a, b)
			local left = self.Providers[a] and self.Providers[a].Priority or 0
			local right = self.Providers[b] and self.Providers[b].Priority or 0
			return left == right and a < b or left > right
		end)
		return modes
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

	function JoinCoordinator:_NotifyStatus(message)
		message = tostring(message)
		if message == self.LastStatus then return end
		self.LastStatus = message
		if self.Runtime and self.Runtime.Notify then self.Runtime:Notify("Auto Join", message) end
	end

	function JoinCoordinator:_Candidate()
		if self.Suspended or self.Runtime and self.Runtime.Registry and self.Runtime.Registry.Applying then return nil end
		local candidates = {}
		for _, provider in pairs(self.Providers) do
			local ok, candidate = xpcall(provider.Callback, Util.Traceback)
			if not ok then self:_NotifyError(provider.Name .. " catalog failed: " .. tostring(candidate))
			elseif type(candidate) == "table" and type(candidate.Queue) == "table" then
				candidate.Provider = provider.Name
				candidate.FallbackPriority = tonumber(candidate.Priority) or provider.Priority
				candidate.Priority = self.PriorityEnabled
					and (tonumber(self.Priorities[provider.Name]) or 1)
					or candidate.FallbackPriority
				table.insert(candidates, candidate)
			end
		end
		table.sort(candidates, function(a, b)
			if a.Priority ~= b.Priority then return a.Priority > b.Priority end
			if a.FallbackPriority ~= b.FallbackPriority then return a.FallbackPriority > b.FallbackPriority end
			return a.Provider < b.Provider
		end)
		return candidates[1]
	end

	function JoinCoordinator:SelectedProvider()
		local candidate = self:_Candidate()
		return candidate and candidate.Provider or nil, candidate
	end

	function JoinCoordinator:ShouldInterrupt(providerName, currentGamemode)
		local selectedProvider, candidate = self:SelectedProvider()
		if selectedProvider ~= providerName then
			return false, candidate
		end
		if type(currentGamemode) ~= "string" or currentGamemode == "" then
			return false, candidate
		end
		local targetGamemode = type(candidate.Queue) == "table" and candidate.Queue.Gamemode or providerName
		if string.lower(currentGamemode) == string.lower(tostring(targetGamemode or providerName)) then
			return false, candidate
		end
		return true, candidate
	end

	function JoinCoordinator:_Run()
		while self.Alive and self.Runtime.Alive do
			local applying = self.Suspended or self.Runtime.Registry and self.Runtime.Registry.Applying
			local candidate = applying and nil or self:_Candidate()
			if applying then
				self.PendingKey = nil
				task.wait(0.1)
			elseif self.Game:IsInGame() then
				self.PendingKey = nil
				self.OwnMatchmaking = false
				task.wait(0.25)
			elseif not candidate then
				self.PendingKey = nil
				self.LastStatus = nil
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
					self:_NotifyStatus(candidate.Provider .. " selected; joining after " .. tostring(math.max(0, tonumber(candidate.Delay) or 0)) .. " seconds.")
				end

				local delay = math.max(0, tonumber(candidate.Delay) or 0)
				local retryAfter = candidate.Matchmaking and 15 or 12
				if os.clock() - self.PendingSince >= delay and (self.LastAttemptKey ~= key or os.clock() - self.LastAttemptAt >= retryAfter) then
					local ok, err = self.Game:Join(candidate.Queue, candidate.Matchmaking == true, 5)
					self.LastAttemptKey, self.LastAttemptAt = key, os.clock()
					if ok then
						self.OwnMatchmaking = candidate.Matchmaking == true
						self:_NotifyStatus(candidate.Provider .. " launch requested successfully.")
					else self:_NotifyError(candidate.Provider .. " join failed: " .. tostring(err)) end
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
