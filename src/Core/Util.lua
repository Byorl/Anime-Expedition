return function()
	local Util = {}
	Util.Traceback = debug and debug.traceback or function(message)
		return tostring(message)
	end

	function Util.Warn(message)
		warn("[Anime Expeditions] " .. tostring(message))
	end

	function Util.SafeCall(label, callback, ...)
		if type(callback) ~= "function" then
			return true
		end
		local arguments = table.pack(...)
		local results = table.pack(xpcall(function()
			return callback(table.unpack(arguments, 1, arguments.n))
		end, Util.Traceback))
		if not results[1] then
			Util.Warn(label .. ": " .. tostring(results[2]))
		end
		return table.unpack(results, 1, results.n)
	end

	function Util.ElevateIdentity()
		local environment = (getgenv and getgenv()) or _G
		local setter = rawget(environment, "setthreadidentity")
			or rawget(environment, "set_thread_identity")
			or rawget(environment, "setidentity")
		local getter = rawget(environment, "getthreadidentity")
			or rawget(environment, "get_thread_identity")
			or rawget(environment, "getidentity")
		local synTable = rawget(environment, "syn")
		if not setter and type(synTable) == "table" then
			setter = synTable.set_thread_identity
		end
		if not getter and type(synTable) == "table" then
			getter = synTable.get_thread_identity
		end
		if type(setter) ~= "function" then
			return function() end
		end
		local hadPrevious, previous = false, nil
		if type(getter) == "function" then
			hadPrevious, previous = pcall(getter)
		end
		local elevated = pcall(setter, 8)
		if not elevated then
			pcall(setter, 7)
		end
		return function()
			if hadPrevious then
				pcall(setter, previous)
			end
		end
	end

	function Util.Clone(value, seen)
		if type(value) ~= "table" then
			return value
		end
		seen = seen or {}
		if seen[value] then
			return seen[value]
		end
		local output = {}
		seen[value] = output
		for key, child in pairs(value) do
			output[Util.Clone(key, seen)] = Util.Clone(child, seen)
		end
		return output
	end

	function Util.SortedKeys(dictionary)
		local keys = {}
		for key in pairs(dictionary) do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return string.lower(tostring(a)) < string.lower(tostring(b))
		end)
		return keys
	end

	return Util
end
