
local REPOSITORY = "https://jexvral.xyz/game/ap/"
local traceback = debug and debug.traceback or function(message) return tostring(message) end

local function fetch(path, cacheBuster)
	local url = REPOSITORY .. path
	if cacheBuster then url = url .. "?v=" .. tostring(cacheBuster) end
	local lastError
	for attempt = 1, 4 do
		local ok, body = pcall(function() return game:HttpGet(url) end)
		if ok and type(body) == "string" and #body > 0 then return body end
		lastError = ok and "empty/non-text response" or tostring(body)
		if attempt < 4 then task.wait(0.2 * attempt) end
	end
	error(string.format("HTTP fetch failed for '%s' after 4 attempts: %s", path, tostring(lastError)), 0)
end

local manifestSource = fetch("manifest.lua", os.time())
local manifestChunk, manifestCompileError = loadstring(manifestSource, "@Anime-Expedition/manifest.lua")
assert(manifestChunk, "Manifest compile failed:\n" .. tostring(manifestCompileError))
local manifestOk, manifest = xpcall(manifestChunk, traceback)
assert(manifestOk, "Manifest execution failed:\n" .. tostring(manifest))
assert(type(manifest) == "table", "Manifest must return a table")
assert(type(manifest.Entry) == "string", "Manifest Entry must be a module name")
assert(type(manifest.Modules) == "table", "Manifest Modules must be a table")

local jobs = {}
for name, path in pairs(manifest.Modules) do
	assert(type(name) == "string" and type(path) == "string", "Manifest module entries must map names to paths")
	table.insert(jobs, {Name = name, Path = path})
end
table.sort(jobs, function(a, b) return a.Name < b.Name end)

local sourceByPath, fetchErrors = {}, {}
local nextJob, completed = 1, 0
local workerCount = math.min(6, #jobs)
for _ = 1, workerCount do
	task.spawn(function()
		while true do
			local index = nextJob
			nextJob = nextJob + 1
			local job = jobs[index]
			if not job then return end
			local ok, sourceOrError = pcall(fetch, job.Path, manifest.Version)
			if ok then sourceByPath[job.Path] = sourceOrError
			else fetchErrors[job.Name] = tostring(sourceOrError) end
			completed = completed + 1
		end
	end)
end

local deadline = os.clock() + 25
while completed < #jobs and os.clock() < deadline do task.wait() end
if completed < #jobs then
	local pending = {}
	for _, job in ipairs(jobs) do
		if not sourceByPath[job.Path] and not fetchErrors[job.Name] then table.insert(pending, job.Name) end
	end
	error("Module download timed out after 25 seconds. Pending: " .. table.concat(pending, ", "), 0)
end
if next(fetchErrors) then
	local messages = {}
	for _, job in ipairs(jobs) do
		if fetchErrors[job.Name] then table.insert(messages, job.Name .. ": " .. fetchErrors[job.Name]) end
	end
	error("One or more modules failed to download:\n" .. table.concat(messages, "\n"), 0)
end

local loaded, loading, importStack = {}, {}, {}
local function Import(name)
	if loaded[name] ~= nil then return loaded[name] end
	if loading[name] then
		local chain = table.clone(importStack)
		table.insert(chain, tostring(name))
		error("Circular source import: " .. table.concat(chain, " -> "), 0)
	end
	local path = manifest.Modules[name]
	if type(path) ~= "string" then error("Unknown Anime Expedition source module: " .. tostring(name), 0) end

	loading[name] = true
	table.insert(importStack, name)
	local source = sourceByPath[path]
	if not source then error("Prefetched source is missing for module '" .. name .. "' at " .. path, 0) end
	local chunk, compileError = loadstring(source, "@Anime-Expedition/" .. path)
	if not chunk then
		loading[name] = nil
		table.remove(importStack)
		error(string.format("Module '%s' compile failed (%s):\n%s", name, path, tostring(compileError)), 0)
	end
	local chunkOk, factory = xpcall(chunk, traceback)
	if not chunkOk then
		loading[name] = nil
		table.remove(importStack)
		error(string.format("Module '%s' chunk failed (%s):\n%s", name, path, tostring(factory)), 0)
	end
	local result = factory
	if type(factory) == "function" then
		local factoryOk, factoryResult = xpcall(function() return factory(Import) end, traceback)
		if not factoryOk then
			loading[name] = nil
			table.remove(importStack)
			error(string.format("Module '%s' factory failed (%s):\n%s", name, path, tostring(factoryResult)), 0)
		end
		result = factoryResult
	end
	loading[name] = nil
	table.remove(importStack)
	loaded[name] = result
	return result
end

local Environment = (getgenv and getgenv()) or _G
Environment.__ANIME_EXPEDITIONS_IMPORT = Import
Environment.__ANIME_EXPEDITIONS_MANIFEST = manifest

return Import(manifest.Entry)
