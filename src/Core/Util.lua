return function()
	local Util = {}
	Util.Traceback = debug and debug.traceback or function(message) return tostring(message) end

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
