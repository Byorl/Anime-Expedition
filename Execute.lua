--[[
	Safe entry point — use THIS so errors are readable.

	loadstring(game:HttpGet("https://raw.githubusercontent.com/Byorl/Anime-Expedition/main/Execute.lua"))()
]]

local env = (getgenv and getgenv()) or shared or _G
local BASE = (typeof(env.AEHubBaseUrl) == "string" and env.AEHubBaseUrl ~= "" and env.AEHubBaseUrl)
	or "https://raw.githubusercontent.com/Byorl/Anime-Expedition/main/"

if not string.match(BASE, "/$") then
	BASE = BASE .. "/"
end

local function fail(msg, extra)
	warn("========== AEHub EXECUTE FAILED ==========")
	warn(tostring(msg))
	if extra then
		warn(tostring(extra))
	end
	warn("==========================================")
	return nil
end

print("[AEHub] Execute: downloading Loader.lua from " .. BASE .. "Loader.lua")

local okGet, source = pcall(function()
	return game:HttpGet(BASE .. "Loader.lua")
end)

if not okGet then
	return fail("HttpGet threw an error while downloading Loader.lua", source)
end

if typeof(source) ~= "string" then
	return fail("HttpGet did not return a string", typeof(source))
end

if #source < 50 then
	return fail("Loader.lua download too small (" .. tostring(#source) .. " bytes) — wrong URL or empty file?", source)
end

if string.find(source, "404", 1, true) and #source < 2000 and not string.find(source, "AEHub", 1, true) then
	return fail("Looks like a 404 page, not Loader.lua. Is the repo public? Is the path correct?", string.sub(source, 1, 300))
end

print("[AEHub] Execute: got " .. tostring(#source) .. " bytes — compiling Loader.lua")

local chunk, compileErr = loadstring(source, "@AEHub/Loader.lua")
if typeof(chunk) ~= "function" then
	-- Some executors reject the 2nd loadstring arg
	chunk, compileErr = loadstring(source)
end

if typeof(chunk) ~= "function" then
	return fail(
		"loadstring returned nil (this is the classic 'attempt to call a nil value' on line 1)",
		"Compile error: " .. tostring(compileErr) .. "\nFirst 300 chars:\n" .. string.sub(source, 1, 300)
	)
end

print("[AEHub] Execute: running Loader.lua")
local okRun, result = xpcall(chunk, function(err)
	local tb = ""
	pcall(function()
		tb = debug.traceback(tostring(err), 2)
	end)
	return tb ~= "" and tb or tostring(err)
end)

if not okRun then
	return fail("Loader.lua crashed", result)
end

print("[AEHub] Execute: finished OK")
return result
