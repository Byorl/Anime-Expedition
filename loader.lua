-- Public loader for https://github.com/Byorl/Anime-Expedition
-- Every code module is fetched from GitHub. Only persistent user configs use disk.

local REPOSITORY = "https://raw.githubusercontent.com/Byorl/Anime-Expedition/main/"

local function fetch(path, cacheBuster)
	local url = REPOSITORY .. path
	if cacheBuster then
		url = url .. "?v=" .. tostring(cacheBuster)
	end
	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	assert(ok and type(body) == "string" and #body > 0, "Failed to fetch " .. url .. ": " .. tostring(body))
	return body
end

local manifestSource = fetch("manifest.lua", os.time())
local manifestChunk, manifestError = loadstring(manifestSource, "@Anime-Expedition/manifest.lua")
assert(manifestChunk, manifestError)
local manifest = manifestChunk()
assert(type(manifest) == "table" and type(manifest.Modules) == "table", "Invalid Anime Expedition manifest")

local loaded = {}
local loading = {}

local function Import(name)
	if loaded[name] ~= nil then
		return loaded[name]
	end
	assert(not loading[name], "Circular module dependency while loading " .. tostring(name))
	local path = manifest.Modules[name]
	assert(type(path) == "string", "Unknown Anime Expedition module: " .. tostring(name))

	loading[name] = true
	local source = fetch(path, manifest.Version)
	local chunk, compileError = loadstring(source, "@Anime-Expedition/" .. path)
	if not chunk then
		loading[name] = nil
		error(compileError)
	end
	local ok, factory = pcall(chunk)
	if not ok then
		loading[name] = nil
		error(factory)
	end
	local result = factory
	if type(factory) == "function" then
		local factoryOk, factoryResult = pcall(factory, Import)
		if not factoryOk then
			loading[name] = nil
			error(factoryResult)
		end
		result = factoryResult
	end
	loading[name] = nil
	loaded[name] = result
	return result
end

local Environment = (getgenv and getgenv()) or _G
Environment.__ANIME_EXPEDITIONS_IMPORT = Import
Environment.__ANIME_EXPEDITIONS_MANIFEST = manifest

return Import(manifest.Entry)
