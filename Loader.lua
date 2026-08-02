--[[
	Anime Expedition Hub — single entry point

	  loadstring(game:HttpGet("https://raw.githubusercontent.com/Byorl/Anime-Expedition/main/Loader.lua"))()

	Local:
	  loadstring(readfile("Loader.lua"))()
]]

local env = (getgenv and getgenv()) or shared or _G

local DEFAULT_BASE_URL = "https://raw.githubusercontent.com/Byorl/Anime-Expedition/main/"
local BOOT_STEP = "init"

local function log(msg)
	print("[AEHub] [" .. tostring(BOOT_STEP) .. "] " .. tostring(msg))
end

local function warnStep(msg)
	warn("[AEHub] [" .. tostring(BOOT_STEP) .. "] " .. tostring(msg))
end

local function formatError(err)
	local message = tostring(err)
	local trace = ""
	pcall(function()
		trace = debug.traceback(message, 2)
	end)
	if trace == "" or trace == message then
		return message
	end
	return trace
end

local function safeLoadstring(source, chunkName)
	local chunk, err
	if chunkName then
		chunk, err = loadstring(source, chunkName)
	end
	if typeof(chunk) ~= "function" then
		chunk, err = loadstring(source)
	end
	return chunk, err
end

local function destroyHubGuis()
	local function wipe(parent)
		if not parent then
			return
		end
		for _, child in parent:GetChildren() do
			local name = string.lower(tostring(child.Name))
			local tagged = false
			pcall(function()
				tagged = child:GetAttribute("AEHub") == true
			end)
			if tagged
				or name == "maclibgui"
				or name == "maclib"
				or name == "aehub"
				or string.find(name, "maclib", 1, true)
			then
				pcall(function()
					child:Destroy()
				end)
			end
		end
	end

	pcall(function()
		wipe(game:GetService("CoreGui"))
	end)
	pcall(function()
		local player = game:GetService("Players").LocalPlayer
		if player then
			wipe(player:FindFirstChild("PlayerGui"))
		end
	end)
end

local function cancelThread(thread)
	if thread == nil then
		return
	end
	pcall(function()
		task.cancel(thread)
	end)
	pcall(function()
		coroutine.close(thread)
	end)
end

local function disconnectConn(conn)
	if conn == nil then
		return
	end
	pcall(function()
		if typeof(conn) == "RBXScriptConnection" or (typeof(conn) == "table" and conn.Disconnect) then
			conn:Disconnect()
		elseif typeof(conn.Disconnect) == "function" then
			conn:Disconnect()
		end
	end)
end

local function nuclearUnload(hub)
	BOOT_STEP = "unload"

	if typeof(hub) == "table" then
		hub.Alive = false
	end

	-- Cancel tracked threads / connections on hub
	if typeof(hub) == "table" then
		if typeof(hub.Threads) == "table" then
			for _, thread in hub.Threads do
				cancelThread(thread)
			end
			hub.Threads = {}
		end
		if typeof(hub.Connections) == "table" then
			for _, conn in hub.Connections do
				disconnectConn(conn)
			end
			hub.Connections = {}
		end

		-- Module runtimes
		if hub.Modules and typeof(hub.Modules.DestroyAll) == "function" then
			pcall(function()
				hub.Modules:DestroyAll()
			end)
		elseif hub.Modules and typeof(hub.Modules.Modules) == "table" then
			for _, module in hub.Modules.Modules do
				if typeof(module) == "table" and typeof(module.Runtime) == "table" then
					local runtime = module.Runtime
					if runtime.Threads then
						for _, thread in runtime.Threads do
							cancelThread(thread)
						end
					end
					if runtime.Connections then
						for _, conn in runtime.Connections do
							disconnectConn(conn)
						end
					end
					cancelThread(runtime.BootThread)
					cancelThread(runtime.PollThread)
					disconnectConn(runtime.ChangeConnection)
				end
			end
		end

		if hub.UI and typeof(hub.UI.Destroy) == "function" then
			pcall(function()
				hub.UI:Destroy()
			end)
		elseif hub.Window and typeof(hub.Window.Unload) == "function" then
			pcall(function()
				hub.Window:Unload()
			end)
		end
	end

	destroyHubGuis()

	-- Restore Place Anywhere before wiping env
	pcall(function()
		local bag = env.__AE_PlaceAnywhereHooks
		if typeof(bag) == "table" then
			if bag.Watchdog then
				pcall(task.cancel, bag.Watchdog)
			end
			if bag.UnitUtils and bag.OriginalUnitUtils ~= nil then
				bag.UnitUtils.IsPlacementAllowed = bag.OriginalUnitUtils
			end
			if bag.Actions then
				if bag.OriginalActions ~= nil then
					rawset(bag.Actions, "IsPlacementAllowed", bag.OriginalActions)
				else
					rawset(bag.Actions, "IsPlacementAllowed", nil)
				end
			end
		end
	end)

	-- Wipe known env keys
	local keys = {
		"AEHub",
		"__AEHubInstance",
		"__AEHubLoading",
		"__AE_AutoClaimRunning",
		"__AE_PlaceAnywhereRunning",
		"__AE_AutoClaimTrack",
		"__AE_PlaceAnywhereHooks",
	}
	for _, key in ipairs(keys) do
		pcall(function()
			env[key] = nil
		end)
	end

	log("Nuclear unload complete")
end

local function hardKillPrevious()
	BOOT_STEP = "kill-previous"
	local previous = env.AEHub
	if typeof(previous) == "table" then
		if typeof(previous.Unload) == "function" then
			local ok, err = pcall(function()
				previous:Unload()
			end)
			if not ok then
				warnStep("Previous Unload failed: " .. tostring(err))
				nuclearUnload(previous)
			end
		else
			nuclearUnload(previous)
		end
	else
		destroyHubGuis()
	end

	env.AEHub = nil
	env.__AEHubInstance = nil
	env.__AEHubLoading = nil
	env.__AE_AutoClaimRunning = nil
	env.__AE_PlaceAnywhereRunning = nil
	env.__AE_AutoClaimTrack = nil

	-- Always restore Place Anywhere hooks on kill
	pcall(function()
		local bag = env.__AE_PlaceAnywhereHooks
		if typeof(bag) == "table" then
			if bag.Watchdog then
				pcall(task.cancel, bag.Watchdog)
			end
			if bag.UnitUtils and bag.OriginalUnitUtils ~= nil then
				bag.UnitUtils.IsPlacementAllowed = bag.OriginalUnitUtils
			end
			if bag.Actions then
				if bag.OriginalActions ~= nil then
					rawset(bag.Actions, "IsPlacementAllowed", bag.OriginalActions)
				else
					rawset(bag.Actions, "IsPlacementAllowed", nil)
				end
			end
			env.__AE_PlaceAnywhereHooks = nil
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
	Threads = {},
	Connections = {},
	_unloading = false,
}

env.__AEHubGeneration = Hub.Generation
env.__AEHubLoading = Hub

function Hub:TrackThread(thread)
	if thread == nil then
		return thread
	end
	table.insert(self.Threads, thread)
	return thread
end

function Hub:TrackConnection(conn)
	if conn == nil then
		return conn
	end
	table.insert(self.Connections, conn)
	return conn
end

function Hub:IsCurrent()
	return self.Alive == true and self.Generation == env.__AEHubGeneration
end

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
	log("Downloading " .. rel .. " ← " .. url)
	local body, err = httpGet(url)
	if not body then
		error("[AEHub] Failed to download '" .. rel .. "' from " .. url .. " | " .. tostring(err), 0)
	end
	if #body < 20 then
		error("[AEHub] Downloaded '" .. rel .. "' is suspiciously small (" .. #body .. " bytes)", 0)
	end
	if string.find(body, "404: Not Found", 1, true) and not string.find(body, "resolveHub", 1, true) then
		error("[AEHub] Got 404 for '" .. rel .. "'. URL: " .. url, 0)
	end
	return body, "http:" .. url
end

local function loadChunk(rel)
	BOOT_STEP = "load:" .. rel
	log("Loading")
	local source, origin = fetchSource(rel)
	local chunk, err = safeLoadstring(source, "@AEHub/" .. rel)
	if typeof(chunk) ~= "function" then
		error(
			"[AEHub] Compile failed for " .. rel .. " (" .. tostring(origin) .. "): " .. tostring(err)
				.. "\nFirst 200 chars:\n"
				.. string.sub(tostring(source), 1, 200),
			0
		)
	end

	env.__AEHubLoading = Hub
	local ok, result = xpcall(function()
		return chunk(Hub)
	end, formatError)
	if not ok then
		error("[AEHub] Runtime failed for " .. rel .. " (" .. tostring(origin) .. "):\n" .. tostring(result), 0)
	end
	if result == nil then
		error("[AEHub] Module '" .. rel .. "' returned nil (forgot return?)", 0)
	end
	return result
end

function Hub:Unload(fromWindow)
	if self._unloading then
		return
	end
	self._unloading = true
	BOOT_STEP = "unload"
	self.Alive = false

	log("Unload starting (fromWindow=" .. tostring(fromWindow == true) .. ")")

	-- 1) Stop modules first (hooks / loops)
	if self.Modules and typeof(self.Modules.DestroyAll) == "function" then
		local ok, err = pcall(function()
			self.Modules:DestroyAll()
		end)
		if not ok then
			warnStep("Modules:DestroyAll failed: " .. tostring(err))
		end
	end

	-- 2) Cancel hub-level threads / connections
	for _, thread in self.Threads do
		cancelThread(thread)
	end
	self.Threads = {}
	for _, conn in self.Connections do
		disconnectConn(conn)
	end
	self.Connections = {}

	-- 3) Destroy UI
	if not fromWindow then
		if self.UI and typeof(self.UI.Destroy) == "function" then
			pcall(function()
				self.UI:Destroy()
			end)
		elseif self.Window and typeof(self.Window.Unload) == "function" then
			pcall(function()
				self.Window:Unload()
			end)
		end
	end

	-- 4) Always scrub leftover GUIs
	destroyHubGuis()
	if self.Core and self.Core.Library and typeof(self.Core.Library.DestroyUiInstances) == "function" then
		pcall(self.Core.Library.DestroyUiInstances)
	end

	-- 5) Drop references
	self.Window = nil
	self.UI = nil
	self.Modules = nil
	self.Config = nil
	self.Core = nil

	if env.AEHub == self then
		env.AEHub = nil
	end
	env.__AEHubInstance = nil
	env.__AEHubLoading = nil

	log("Fully unloaded")
end

function Hub:ForceUnload()
	nuclearUnload(self)
end

env.AEHubForceUnload = function()
	nuclearUnload(env.AEHub)
	destroyHubGuis()
end

local okBoot, bootErr = xpcall(function()
	BOOT_STEP = "core"
	Hub.Core.Library = loadChunk("Core/Library.lua")
	Hub.Core.Config = loadChunk("Core/Config.lua")
	Hub.Core.ModuleManager = loadChunk("Core/ModuleManager.lua")
	Hub.Core.UI = loadChunk("Core/UI.lua")

	local Library = Hub.Core.Library
	pcall(Library.EnsureFolders)

	BOOT_STEP = "construct"
	Hub.Config = Hub.Core.Config.new(Hub)
	Hub.Modules = Hub.Core.ModuleManager.new(Hub)
	Hub.UI = Hub.Core.UI.new(Hub)

	BOOT_STEP = "modules"
	local PlaceAnywhere = loadChunk("Modules/PlaceAnywhere.lua")
	local AutoClaim = loadChunk("Modules/AutoClaim.lua")
	Hub.Modules:Register(PlaceAnywhere)
	Hub.Modules:Register(AutoClaim)
	Hub.Config:SeedDefaults(Hub.Modules:ExportValues())
	Hub.Config:EnsureMainConfig()

	env.AEHub = Hub
	env.__AEHubInstance = Hub

	BOOT_STEP = "ui-build"
	log("Building UI...")
	Hub.UI:Build()
	log("UI ready")

	BOOT_STEP = "autoload"
	local loadedOk, loadedOrErr = xpcall(function()
		return Hub.Config:TryAutoLoad()
	end, formatError)
	if not loadedOk then
		warnStep("AutoLoad crashed:\n" .. tostring(loadedOrErr))
		pcall(function()
			Hub.Config:SyncUiFromValues(false)
		end)
	elseif loadedOrErr then
		Library.Notify(Hub.Window, "Anime Expeditions", "Loaded " .. tostring(Hub.Config:GetCurrentDisplayName() or "config"))
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

	BOOT_STEP = "ready"
	Library.Notify(Hub.Window, "Anime Expeditions", "Ready")
	log("v" .. Library.Version .. " started (generation " .. tostring(Hub.Generation) .. ")")
end, formatError)

env.__AEHubLoading = nil

if not okBoot then
	warn("========== AEHub FATAL ==========")
	warn("Boot step: " .. tostring(BOOT_STEP))
	warn(tostring(bootErr))
	warn("=================================")
	pcall(function()
		Hub:ForceUnload()
	end)
	return nil
end

return Hub
