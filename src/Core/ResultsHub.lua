return function(Import)
	local Util = Import("Util")
	local ResultsHub = {}
	ResultsHub.__index = ResultsHub

	function ResultsHub.new(gameAdapter)
		local self = setmetatable({
			Alive = true,
			Subscribers = {},
			Runs = 0,
			Revision = 0,
			Visible = false,
			Connections = {},
			Deliveries = {},
			StartedAt = os.clock(),
		}, ResultsHub)
		local resultConnection, resultError = gameAdapter:Connect("SET_END_PARAMETERS", function(result)
			if not self.Alive or type(result) ~= "table" then return end
			self.Runs = self.Runs + 1
			self.Revision = self.Revision + 1
			for revision in pairs(self.Deliveries) do
				if revision < self.Revision - 2 then self.Deliveries[revision] = nil end
			end
			self.Deliveries[self.Revision] = { StartedAt = os.clock(), Pending = {} }
			self.Current = result
			self.Visible = false
			self.ReadyAt = os.clock() + 3.25
			local completions = {}
			for name, subscriber in pairs(self.Subscribers) do
				if subscriber.Delivery then
					completions[name] = self:BeginDelivery(name, self.Revision)
				end
			end
			for name, subscriber in pairs(self.Subscribers) do
				local ok, callbackError = xpcall(function()
					subscriber.Callback(result, self.Runs, self.Revision, completions[name])
				end, Util.Traceback)
				if not ok and completions[name] then completions[name](false) end
				if not ok then Util.Warn("result subscriber " .. tostring(name) .. " failed: " .. tostring(callbackError)) end
			end
		end)
		local showConnection, showError = gameAdapter:Connect("SHOW_END_SCREEN", function()
			if self.Alive and self.Current then
				self.Visible = true
				self.ReadyAt = os.clock() + 0.25
			end
		end)
		local hideConnection, hideError = gameAdapter:Connect("HIDE_END_SCREEN", function()
			if self.Alive then
				self.Visible = false
				self.Current = nil
				self.ReadyAt = nil
			end
		end)
		for _, connection in pairs({ resultConnection, showConnection, hideConnection }) do
			if connection then
				table.insert(self.Connections, connection)
			end
		end
		self.Error = resultError or showError or hideError
		return self
	end

	function ResultsHub:Snapshot()
		local ready = self.Current ~= nil
			and (self.Visible == true or type(self.ReadyAt) == "number" and os.clock() >= self.ReadyAt)
		return self.Current, self.Runs, self.Revision, ready == true
	end

	function ResultsHub:Subscribe(name, callback, delivery)
		assert(type(name) == "string" and name ~= "", "result subscriber requires a name")
		assert(type(callback) == "function", "result subscriber requires a callback")
		self.Subscribers[name] = { Callback = callback, Delivery = delivery == true }
		return function() self.Subscribers[name] = nil end
	end

	function ResultsHub:BeginDelivery(name, revision)
		revision = tonumber(revision) or self.Revision
		name = tostring(name)
		local deliveries = self.Deliveries[revision]
		if not deliveries then
			deliveries = { StartedAt = os.clock(), Pending = {} }
			self.Deliveries[revision] = deliveries
		end
		deliveries.Pending[name] = (deliveries.Pending[name] or 0) + 1
		deliveries.HadDeliveries = true
		local finished = false
		return function(needsSettle)
			if finished then return end
			finished = true
			local current = self.Deliveries[revision]
			if not current then return end
			if needsSettle ~= false then current.NeedsSettle = true end
			local remaining = (current.Pending[name] or 1) - 1
			current.Pending[name] = remaining > 0 and remaining or nil
			if next(current.Pending) == nil then current.CompletedAt = os.clock() end
		end
	end

	function ResultsHub:DeliveryState(revision, timeout, settle)
		local deliveries = self.Deliveries[tonumber(revision) or self.Revision]
		if not deliveries then return true, {}, false end
		if next(deliveries.Pending) == nil then
			local settling = deliveries.HadDeliveries
				and deliveries.NeedsSettle
				and type(deliveries.CompletedAt) == "number"
				and os.clock() - deliveries.CompletedAt < (tonumber(settle) or 0)
			if settling then return false, { "Webhook finalizing" }, false end
			return true, {}, false
		end
		local names = {}
		for name in pairs(deliveries.Pending) do table.insert(names, name) end
		table.sort(names)
		local timedOut = os.clock() - deliveries.StartedAt >= (tonumber(timeout) or 15)
		return timedOut, names, timedOut
	end

	function ResultsHub:Destroy()
		if not self.Alive then return end
		self.Alive = false
		for _, connection in ipairs(self.Connections) do
			if type(connection.Disconnect) == "function" then
				pcall(connection.Disconnect, connection)
			end
		end
		table.clear(self.Connections)
		table.clear(self.Subscribers)
		table.clear(self.Deliveries)
		self.Current = nil
	end

	return ResultsHub
end
