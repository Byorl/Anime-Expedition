--!nocheck
--[[
	Expedition instant-extract reproduction (PoC) - v2
	Authorized security testing - Anime Expeditions (Summer Update build).

	Vulnerability (unchanged core)
	------------------------------
	The per-match GameState replica accepts client-sent event names with no
	server-side state validation. "Extract" (the client's own
	Actions.Expedition_Extract) ends a run as a SUCCESSFUL extraction; the
	Checkpoint-only UI gate is client-side. "Restart" (Repeat Stage) relaunches
	the same map/difficulty with no cooldown. Chaining them is the infinite
	instant-win loop from the reference video.

	v2 changes requested after live testing:
	  - INSTANT mode: attempts Extract the moment the expedition replica
	    appears, BEFORE the run becomes active, to test whether the server
	    honors it pre-start. Falls back to the normal wait-for-active flow
	    automatically if the pre-start attempt does not end the run.
	  - Fully automatic relaunch: after every Extract, sends Restart (Repeat
	    Stage) and then StartGame (the party replica request the Start button
	    uses). The server's own StartGame description says it "ends any
	    existing game", so it doubles as a forced relauncher.
	  - Faster polling (0.05s), minimal fixed delays.
	  - The daily "+250 event currency per non-event win" bonus is capped
	    SERVER-side per fishing rank (AE_CAP_RANK); this loop cannot bypass
	    that cap - see fishing_result_trust_poc.luau for the rank route.

	Works on every expedition (School Grounds, Flower Forest, Rose Kingdom,
	East Town) and any difficulty because all queue with
	Parameters.Gamemode == "Expedition".

	Usage: run once in the lobby. Start the FIRST run manually (or via the
	party UI) so a party exists; from then on the loop is hands-off. Stops
	after MAX_WINS or when _G.EXPLOIT_POC_STOP is true.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CONFIG = {
	MAX_WINS = 100, -- PoC safety cap; raise or remove for longer sessions
	INSTANT = true, -- attempt Extract before the run becomes active
	EXTRACT_DELAY = 0.25, -- delay after "active" before the fallback Extract
	RESTART_DELAY = 0.25, -- delay after run end before Restart/StartGame
	START_TIMEOUT = 30, -- how long to wait for a run to become active
	END_TIMEOUT = 30, -- how long to wait for a run to end after Extract
	SEND_START_GAME = true, -- fire StartGame every cycle as forced relaunch
}

local Nodes = require(ReplicatedStorage:WaitForChild("Nodes"))

-- New replicas appear on every match launch; a Restart relaunch can either
-- replace the replica or reset it in place, so track both signals. Declared
-- before the helpers that read it.
local state = { replica = nil, generation = 0 }

local running = true
local wins = 0
local lastStartGameSent = 0

local function log(message: string)
	print(("[PoC %05.1f] %s"):format(os.clock(), message))
end

local function stop()
	if running then
		running = false
		log(("stopped after %d cycle(s)"):format(wins))
	end
end

local function getGameReplica()
	local ok, replica = pcall(function()
		return Nodes.GET_GAME_REPLICA:InvokeSelf()
	end)
	if ok and replica then
		return replica
	end
	return nil
end

local function waitFor(predicate, timeout, description)
	local deadline = os.clock() + timeout
	while running and os.clock() < deadline do
		local value = predicate()
		if value then
			return value
		end
		task.wait(0.05)
	end
	if description then
		log(("timeout waiting for: %s"):format(description))
	end
	return nil
end

local function isActive(replica)
	local data = replica.Data
	return data ~= nil and data.Active == true
end

local function replicaReplaced(replica, generationAtStart)
	return state.generation > generationAtStart and state.replica ~= replica
end

local function isExpedition(replica)
	local data = replica.Data
	if data == nil or data.Parameters == nil then
		return false
	end
	return data.Parameters.Gamemode == "Expedition"
end

local function sendStartGame(force: boolean)
	if not CONFIG.SEND_START_GAME then
		return
	end
	-- Throttle the idle nudge; forced sends (inside a cycle) always go.
	if not force and os.clock() - lastStartGameSent < 2 then
		return
	end
	lastStartGameSent = os.clock()
	local ok, party = pcall(function()
		return Nodes.PARTY_GET_CURRENT_REPLICA:InvokeSelf()
	end)
	if ok and party then
		pcall(function()
			party:FireServer("StartGame")
		end)
		log("sent StartGame to party replica")
	end
end

Nodes.GAME_REPLICA_LOADED:Connect(function(replica)
	state.generation += 1
	state.replica = replica
	log(("GameState replica #%d appeared"):format(state.generation))
end)

task.spawn(function()
	local replica = getGameReplica()
	if replica and state.replica == nil then
		state.replica = replica
	end
end)

local function relaunch(replica, mapName)
	task.wait(CONFIG.RESTART_DELAY)
	pcall(function()
		replica:FireServer("Restart")
	end)
	log(("sent Restart on %s (Repeat Stage)"):format(mapName))
	sendStartGame(true)
	wins += 1
	log(("cycle %d complete"):format(wins))
end

local function runCycle(replica, generationAtStart)
	local data = replica.Data
	local mapName = (data and data.Parameters and data.Parameters.MapName) or "unknown"

	if CONFIG.INSTANT then
		-- Test whether Extract is honored before the run even starts. The run
		-- counts as ended by this attempt only if the replica is replaced
		-- before it ever activates (an ignored Extract would be followed by
		-- the normal countdown activating the run).
		pcall(function()
			replica:FireServer("Extract")
		end)
		log(("sent pre-start Extract on %s"):format(mapName))
		local outcome = waitFor(function()
			if replicaReplaced(replica, generationAtStart) then
				return "replaced"
			end
			if isActive(replica) then
				return "active"
			end
			return nil
		end, CONFIG.START_TIMEOUT, "pre-start outcome")
		if outcome == "replaced" then
			log(("pre-start Extract landed on %s - run ended without ever starting"):format(mapName))
			wins += 1
			log(("cycle %d complete"):format(wins))
			return true
		end
		log("pre-start Extract did not end the run; continuing with the active flow")
		replica = state.replica or replica
	end

	local active = waitFor(function()
		return isActive(replica)
	end, CONFIG.START_TIMEOUT, "run start")
	if not active then
		sendStartGame(true)
		active = waitFor(function()
			return isActive(replica)
		end, CONFIG.START_TIMEOUT, "run start after StartGame")
	end
	if not active then
		log("run never became active; waiting for the next replica")
		return false
	end

	task.wait(CONFIG.EXTRACT_DELAY)
	pcall(function()
		replica:FireServer("Extract")
	end)
	log(("sent Extract on %s"):format(mapName))

	waitFor(function()
		if replicaReplaced(replica, generationAtStart) then
			return "replaced"
		end
		if not isActive(replica) then
			return "ended"
		end
		return nil
	end, CONFIG.END_TIMEOUT, "run end")

	relaunch(replica, mapName)
	return true
end

log("PoC v2 loaded; watching for expedition GameState replicas")

while running and wins < CONFIG.MAX_WINS do
	if _G.EXPLOIT_POC_STOP == true then
		stop()
		break
	end

	local replica = state.replica
	local generation = state.generation
	if replica and isExpedition(replica) then
		runCycle(replica, generation)
		task.wait(CONFIG.RESTART_DELAY)
	else
		sendStartGame() -- keeps a queued party launching without input
		task.wait(0.5)
	end
end

stop()
log(("summary: %d cycle(s); daily event-currency bonus is capped server-side per fishing rank, not by this loop"):format(wins))
