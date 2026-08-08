return function(Import)
	local Build = Import("Build")
	local Provider = {}

	function Provider.Load()
		local ok, source = pcall(function() return game:HttpGet(Build.MacLibUrl) end)
		assert(ok and type(source) == "string" and #source > 10000, "Unable to download MacLib from GitHub")
		local chunk, compileError = loadstring(source, "@MacLib")
		assert(chunk, compileError)
		return chunk()
	end

	return Provider
end
