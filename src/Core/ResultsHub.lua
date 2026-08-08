return function(Import)
	local Util = Import("Util")
	local ResultsHub = {}
	ResultsHub.__index = ResultsHub

	function ResultsHub.new(gameAdapter)
		local self = setmetatable({Alive = true, Subscribers = {}, Runs = 0, StartedAt = os.clock()}, ResultsHub)
		local connection, err = gameAdapter:Connect("SET_END_PARAMETERS", function(result)
			if not self.Alive or type(result) ~= "table" then return end
			self.Runs = self.Runs + 1
			for name, callback in pairs(self.Subscribers) do
				local ok, callbackError = xpcall(function() callback(result, self.Runs) end, Util.Traceback)
				if not ok then Util.Warn("result subscriber " .. tostring(name) .. " failed: " .. tostring(callbackError)) end
			end
		end)
		self.Connection = connection
		self.Error = err
		return self
	end

	function ResultsHub:Subscribe(name, callback)
		assert(type(name) == "string" and name ~= "", "result subscriber requires a name")
		assert(type(callback) == "function", "result subscriber requires a callback")
		self.Subscribers[name] = callback
		return function() self.Subscribers[name] = nil end
	end

	function ResultsHub:Destroy()
		if not self.Alive then return end
		self.Alive = false
		if self.Connection and type(self.Connection.Disconnect) == "function" then pcall(self.Connection.Disconnect, self.Connection) end
		table.clear(self.Subscribers)
	end

	return ResultsHub
end
