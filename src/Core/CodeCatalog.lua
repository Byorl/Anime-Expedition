return function()
	local CodeCatalog = {}

	local WRAPPER_KEYS = {
		Codes = true,
		Data = true,
		Value = true,
		Values = true,
		State = true,
	}

	local function trim(value)
		return string.match(tostring(value or ""), "^%s*(.-)%s*$")
	end

	local function add(output, code, info)
		code = trim(code)
		if code == "" or type(info) ~= "table" then return end
		local key = string.lower(code)
		local existing = output[key]
		if not existing then
			existing = {Code = code, Info = {}}
			output[key] = existing
		end
		existing.Code = code
		for field, value in pairs(info) do
			if field ~= "Code" then existing.Info[field] = value end
		end
	end

	local function collect(value, output, likelyMap, depth, seen)
		if type(value) ~= "table" or depth <= 0 or seen[value] then return end
		seen[value] = true
		if type(value.Code) == "string" then add(output, value.Code, value) end
		if type(value.Codes) == "table" and value.Codes ~= value then
			collect(value.Codes, output, true, depth - 1, seen)
		end
		for key, child in pairs(value) do
			if type(child) == "table" then
				if likelyMap and type(key) == "string" and not WRAPPER_KEYS[key] then
					add(output, key, child)
				elseif type(child.Code) == "string" then
					add(output, child.Code, child)
				else
					collect(child, output, WRAPPER_KEYS[key] == true, depth - 1, seen)
				end
			end
		end
	end

	function CodeCatalog.Merge(sources)
		local output = {}
		for _, source in ipairs(type(sources) == "table" and sources or {}) do
			collect(source, output, type(source) == "table" and source.Codes == nil, 8, {})
		end
		return output
	end

	function CodeCatalog.ReleaseKey(info)
		info = type(info) == "table" and info or {}
		return table.concat({
			tostring(info.ActiveFrom or ""),
			tostring(info.ActiveUntil or ""),
			tostring(info.LevelRequirement or ""),
		}, ":")
	end

	function CodeCatalog.IsActive(info, now)
		info = type(info) == "table" and info or {}
		now = tonumber(now) or os.time()
		local starts = tonumber(info.ActiveFrom) or -math.huge
		local expires = tonumber(info.ActiveUntil) or math.huge
		return starts <= now and now <= expires
	end

	function CodeCatalog.IsTerminal(status)
		return status == "Accepted" or status == "AlreadyRedeemed" or status == "Rejected"
	end

	function CodeCatalog.CanAttempt(cached, releaseKey, now)
		if type(cached) ~= "table" or tostring(cached.ReleaseKey or "") ~= tostring(releaseKey or "") then
			return true
		end
		if CodeCatalog.IsTerminal(cached.Status) then return false end
		return (tonumber(cached.RetryAt) or 0) <= (tonumber(now) or os.time())
	end

	local function responseMessage(result)
		if type(result) ~= "table" then return tostring(result) end
		return tostring(result.Message or result.Error or result.Status or "response table")
	end

	function CodeCatalog.Classify(result, encode)
		if result == true then return "Accepted", "true" end
		if result == false or result == nil then return "Attempted", tostring(result) end
		local message = responseMessage(result)
		local lower = string.lower(message)
		if string.find(lower, "already", 1, true) then return "AlreadyRedeemed", message end
		if string.find(lower, "invalid", 1, true) or string.find(lower, "expired", 1, true) then
			return "Rejected", message
		end
		if string.find(lower, "unable", 1, true)
			or string.find(lower, "failed", 1, true)
			or string.find(lower, "try again", 1, true)
			or string.find(lower, "wait", 1, true)
			or string.find(lower, "cooldown", 1, true)
		then
			return "Attempted", message
		end
		if type(result) == "table" then
			if result.Success == true then return "Accepted", message end
			if result.Success == false or result.Error then return "Attempted", message end
			if type(encode) == "function" then
				local ok, encoded = pcall(encode, result)
				if ok and type(encoded) == "string" then message = encoded end
			end
			return "Attempted", message
		end
		if string.find(lower, "success", 1, true)
			or string.find(lower, "redeemed", 1, true)
			or string.find(lower, "claimed", 1, true)
		then
			return "Accepted", message
		end
		return "Attempted", message
	end

	return CodeCatalog
end
