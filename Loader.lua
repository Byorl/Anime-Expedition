--[[
	Anime Expedition Hub — Loader

	GitHub:
	  loadstring(game:HttpGet("https://raw.githubusercontent.com/Byorl/Anime-Expedition/main/Loader.lua"))()

	Local:
	  loadstring(readfile("Loader.lua"))()
]]

local env = (getgenv and getgenv()) or shared or _G

local DEFAULT_BASE_URL = "https://raw.githubusercontent.com/Byorl/Anime-Expedition/main/"

local function log(msg)
	print("[AEHub] " .. tostring(msg))
end

local function hardKillPrevious()
	local previous = env.AEHub
	if typeof(previous) == "table" and typeof(previous.Unload) == "function" then
		pcall(function()
			previous:Unload()
		end)
	end

	env.AEHub = nil
	env.__AEHubInstance = nil
	env.__AEHubLoading = nil
	env.__AE_AutoClaimRunning = nil
	env.__AE_PlaceAnywhereRunning = nil
	env.__AE_AutoClaimTrack = nil

	pcall(function()
		for _, child in game:GetService("CoreGui"):GetChildren() do
			local name = child.Name
			if name == "MaclibGui" or name == "MacLib" or name == "AEHub" or child:GetAttribute("AEHub") == true then
				child:Destroy()
			end
		end
	end)
	pcall(function()
		local player = game:GetService("Players").LocalPlayer
		if player and player:FindFirstChild("PlayerGui") then
			for _, child in player.PlayerGui:GetChildren() do
				local name = child.Name
				if name == "MaclibGui" or name == "MacLib" or name == "AEHub" or child:GetAttribute("AEHub") == true then
					child:Destroy()
				end
			end
		end
	end)
end

log("Booting...")
hardKillPrevious()
task.wait()

if typeof(env.AEHubBaseUrl) ~= "string" or env.AEHubBaseUrl == "" then
	env.AEHubBaseUrl = DEFAULT_BASE_URL
end

local Hub = {
	Alive = true,
	Generation = (tonumber(env.__AEHubGeneration) or 0) + 1,
	Core = {},
	Window = nil,
	Config = nil,
	Modules = nil,
	UI = nil,
}

env.__AEHubGeneration = Hub.Generation
env.__AEHubLoading = Hub

local function detectRoot()
	if typeof(env.AEHubRoot) == "string" and env.AEHubRoot ~= "" then
		return env.AEHubRoot
	end
	if typeof(isfile) == "function" then
		local ok, exists = pcall(isfile, "Loader.lua")
		if ok and exists then
			return "."
		end
		ok, exists = pcall(isfile, "Core/Library.lua")
		if ok and exists then
			return "."
		end
	end
	return "."
end

local function joinPath(root, rel)
	if root == "." or root == "" then
		return rel
	end
	return root .. "/" .. rel
end

local function httpGet(url)
	local ok, result = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and typeof(result) == "string" and #result > 0 then
		return result
	end
	return nil, result
end

local function fetchSource(rel)
	local root = detectRoot()
	local localPath = joinPath(root, rel)

	if typeof(isfile) == "function" and typeof(readfile) == "function" then
		local okExists, exists = pcall(isfile, localPath)
		if okExists and exists then
			local okRead, contents = pcall(readfile, localPath)
			if okRead and typeof(contents) == "string" and #contents > 0 then
				return contents, "file:" .. localPath
			end
		end
	end

	local base = env.AEHubBaseUrl
	if typeof(base) ~= "string" or base == "" then
		base = DEFAULT_BASE_URL
	end
	if not string.match(base, "/$") then
		base = base .. "/"
	end

	local url = base .. rel
	log("Downloading " .. rel)
	local body, err = httpGet(url)
	if not body then
		error("[AEHub] Failed to download '" .. rel .. "' from " .. url .. " | " .. tostring(err))
	end
	return body, "http:" .. url
end

local function loadChunk(rel)
	log("Loading " .. rel)
	local source, origin = fetchSource(rel)
	local chunk, err = loadstring(source)
	if not chunk then
		error("[AEHub] Compile failed for " .. rel .. " (" .. tostring(origin) .. "): " .. tostring(err))
	end

	env.__AEHubLoading = Hub
	local ok, result = pcall(chunk, Hub)
	if not ok then
		error("[AEHub] Runtime failed for " .. rel .. ": " .. tostring(result))
	end
	return result
end

function Hub:IsCurrent()
	return self.Alive == true and self.Generation == env.__AEHubGeneration
end

local okBoot, bootErr = xpcall(function()
	Hub.Core.Library = loadChunk("Core/Library.lua")
	Hub.Core.Config = loadChunk("Core/Config.lua")
	Hub.Core.ModuleManager = loadChunk("Core/ModuleManager.lua")
	Hub.Core.UI = loadChunk("Core/UI.lua")

	local Library = Hub.Core.Library
	pcall(Library.EnsureFolders)

	Hub.Config = Hub.Core.Config.new(Hub)
	Hub.Modules = Hub.Core.ModuleManager.new(Hub)
	Hub.UI = Hub.Core.UI.new(Hub)

	local PlaceAnywhere = loadChunk("Modules/PlaceAnywhere.lua")
	local AutoClaim = loadChunk("Modules/AutoClaim.lua")
	Hub.Modules:Register(PlaceAnywhere)
	Hub.Modules:Register(AutoClaim)

	Hub.Config:SeedDefaults(Hub.Modules:ExportValues())

	function Hub:Unload(fromWindow)
		if not self.Alive and fromWindow then
			return
		end
		self.Alive = false

		if self.Modules then
			pcall(function()
				self.Modules:DestroyAll()
			end)
		end

		if self.UI and not fromWindow then
			pcall(function()
				self.UI:Destroy()
			end)
		elseif fromWindow then
			pcall(Library.DestroyUiInstances)
		end

		self.Window = nil
		self.UI = nil
		self.Modules = nil
		self.Config = nil

		if env.AEHub == self then
			env.AEHub = nil
		end
		env.__AEHubInstance = nil
		env.__AEHubLoading = nil
		log("Fully unloaded")
	end

	env.AEHub = Hub
	env.__AEHubInstance = Hub

	log("Building UI...")
	Hub.UI:Build()
	log("UI ready")

	if Hub.Config.Prefs.AutoLoad ~= false then
		local loadedOk, loaded = pcall(function()
			return Hub.Config:TryAutoLoad()
		end)
		if loadedOk and loaded then
			Library.Notify(Hub.Window, "AEHub", "Loaded your last config")
		else
			pcall(function()
				Hub.Config:SyncUiFromValues(false)
			end)
		end
	else
		pcall(function()
			Hub.Config:SyncUiFromValues(false)
		end)
	end

	if Hub.UI then
		pcall(function()
			Hub.UI:_refreshConfigDropdown()
		end)
	end

	Library.Notify(Hub.Window, "AEHub", "Ready · RightControl toggles UI")
	log("v" .. Library.Version .. " started")
end, function(err)
	return tostring(err) .. "\n" .. tostring(debug.traceback and debug.traceback() or "")
end)

env.__AEHubLoading = nil

if not okBoot then
	warn("[AEHub] FATAL: " .. tostring(bootErr))
	pcall(function()
		if Hub and Hub.Unload then
			Hub:Unload()
		end
	end)
	return nil
end

return Hub
