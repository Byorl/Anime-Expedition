return function(Import)
	local Util = Import("Util")
	local HttpService = game:GetService("HttpService")
	local FileSystem = {}
	FileSystem.__index = FileSystem

	function FileSystem.new(root)
		local self = setmetatable({Root = root}, FileSystem)
		self.Available = type(isfile) == "function"
			and type(readfile) == "function"
			and type(writefile) == "function"
			and type(isfolder) == "function"
			and type(makefolder) == "function"
			and type(listfiles) == "function"
		return self
	end

	function FileSystem:EnsureFolder(path)
		if not self.Available then return false, "executor filesystem APIs are unavailable" end
		local current = ""
		for segment in string.gmatch(path, "[^/\\]+") do
			current = current == "" and segment or (current .. "/" .. segment)
			if not isfolder(current) then
				local ok, err = pcall(makefolder, current)
				if not ok and not isfolder(current) then return false, err end
			end
		end
		return true
	end

	function FileSystem:Read(path)
		if not self.Available or not isfile(path) then return nil end
		local ok, data = pcall(readfile, path)
		return ok and data or nil
	end

	function FileSystem:Write(path, data)
		if not self.Available then return false, "executor filesystem APIs are unavailable" end
		local folder = string.match(path, "^(.*)[/\\][^/\\]+$")
		if folder then
			local ok, err = self:EnsureFolder(folder)
			if not ok then return false, err end
		end
		if isfile(path) then
			local old = self:Read(path)
			if old then pcall(writefile, path .. ".bak", old) end
		end
		local ok, err = pcall(writefile, path, data)
		return ok, err
	end

	function FileSystem:Delete(path)
		if type(delfile) ~= "function" then return false, "delfile is unavailable" end
		if not isfile(path) then return true end
		local ok, err = pcall(delfile, path)
		return ok, err
	end

	function FileSystem:List(path)
		if not self.Available or not isfolder(path) then return {} end
		local ok, files = pcall(listfiles, path)
		return ok and files or {}
	end

	function FileSystem:ReadJson(path, fallback)
		local raw = self:Read(path)
		if not raw then return Util.Clone(fallback) end
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(decoded) == "table" then return decoded end
		local backup = self:Read(path .. ".bak")
		if backup then
			local backupOk, backupDecoded = pcall(HttpService.JSONDecode, HttpService, backup)
			if backupOk and type(backupDecoded) == "table" then return backupDecoded end
		end
		return Util.Clone(fallback)
	end

	function FileSystem:WriteJson(path, value)
		local ok, encoded = pcall(HttpService.JSONEncode, HttpService, value)
		if not ok then return false, "JSON encode failed: " .. tostring(encoded) end
		return self:Write(path, encoded)
	end

	return FileSystem
end
