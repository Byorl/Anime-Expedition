--!nocheck
--[[
	Rollback research harness (PoC)
	Authorized security testing - Anime Expeditions (Summer Update build).

	Question
	--------
	Can client-triggered actions make the server discard session spends (gems,
	trait rerolls) so that a rejoin restores the pre-spend balances?

	What the extraction says (confirmed):
	  - Balances live in the PlayerData replica under ItemData.<Name>.Amount
	    (readable client-side via Nodes.GET_DATA_VALUE, e.g. "Gem",
	    "TraitReroll", "Gold", "StatReroll").
	  - There is NO client-to-server data-write primitive: ReplicaWrite /
	    ReplicaSet* remotes are server-to-client only, and the client's local
	    Set()/Write() calls are optimistic writes gated by server-authorized
	    WriteLibs.
	  - There is NO client-triggered "reload profile from DataStore" node.
	    The only reset primitive is TESTING_RESET_DATA (the settings menu
	    "Reset ALL Data" button) which is an IRREVERSIBLE WIPE, not a
	    rollback - never fire it expecting data to come back.
	  - Therefore a true rollback can only come from server save timing, which
	    is not client-visible. The one testable race: if the server debounces
	    saves, spending and disconnecting within the debounce window loses the
	    spends. This harness maximizes that window by disconnecting the instant
	    a spend is detected.

	Modes (auto-selected):
	  ARM    - no snapshot file: snapshot balances, then watch. The moment any
	           tracked balance changes (your spend), it disconnects the client
	           immediately. Then rejoin and run again.
	  VERIFY - snapshot file found: compares current balances against the
	           snapshot and reports whether the spends persisted.

	Optional probe (CONFIG.PROBE_CMDR):
	  Sends the Cmdr command "setitemamount <yourUserId> Gem <currentAmount>"
	  through the raw CmdrFunction remote. A server-side permission check
	  should block it; if it is not blocked, setting the CURRENT amount is
	  net-zero and only proves reachability (which would supersede rollback
	  entirely, e.g. setting amounts directly). The console reply is the
	  evidence.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CONFIG = {
	TRACKED_ITEMS = { "Gem", "TraitReroll", "Gold", "StatReroll" },
	SNAPSHOT_FILE = "ae_rollback_snapshot.txt",
	SPEND_TIMEOUT = 600, -- ARM mode: stop watching after this many seconds
	LINGER_AFTER_SPEND = 0, -- extra seconds before disconnect (0 = instant)
	PROBE_CMDR = false, -- set true to test Cmdr reachability (net-zero probe)
}

local Nodes = require(ReplicatedStorage:WaitForChild("Nodes"))
local localPlayer = Players.LocalPlayer

local function log(message: string)
	print(("[Rollback %05.1f] %s"):format(os.clock(), message))
end

local function readBalances()
	local out = {}
	for _, itemName in CONFIG.TRACKED_ITEMS do
		local ok, value = pcall(function()
			return Nodes.GET_DATA_VALUE:InvokeSelf({ "ItemData", itemName, "Amount" })
		end)
		out[itemName] = (ok and type(value) == "number") and value or nil
	end
	return out
end

local function serializeBalances(balances, stamp)
	local parts = { ("time=%s"):format(stamp or os.time()) }
	for _, itemName in CONFIG.TRACKED_ITEMS do
		table.insert(parts, ("%s=%s"):format(itemName, tostring(balances[itemName] or "nil")))
	end
	return table.concat(parts, ";")
end

local function parseBalances(text)
	local out = {}
	for key, value in string.gmatch(text, "([A-Za-z]+)=([%w%d%.]+)") do
		out[key] = tonumber(value)
	end
	return out
end

local function fileWrite(fileName, content)
	local ok = pcall(function()
		writefile(fileName, content)
	end)
	return ok
end

local function fileRead(fileName)
	local ok, content = pcall(function()
		return readfile(fileName)
	end)
	if ok and type(content) == "string" and #content > 0 then
		return content
	end
	return nil
end

local snapshotText = fileRead(CONFIG.SNAPSHOT_FILE)

if CONFIG.PROBE_CMDR then
	local balances = readBalances()
	local current = balances.Gem
	if current then
		-- Net-zero probe: set Gem to its current amount. Success proves the
		-- command is reachable; failure text proves it is permission-gated.
		local ok, response = pcall(function()
			local CmdrFunction = ReplicatedStorage:WaitForChild("CmdrClient"):WaitForChild("CmdrFunction")
			return CmdrFunction:InvokeServer(
				("setitemamount %d Gem %d"):format(localPlayer.UserId, current),
				{ Data = {} }
			)
		end)
		log(("Cmdr probe result: ok=%s response=%s"):format(tostring(ok), tostring(response)))
	else
		log("Cmdr probe skipped: Gem balance unreadable")
	end
end

if snapshotText == nil then
	-- ARM MODE
	local before = readBalances()
	log("ARMED. Tracked balances: " .. serializeBalances(before))
	log("Spend anything now (gems, trait rerolls, banners). The client disconnects on the first balance change.")
	fileWrite(CONFIG.SNAPSHOT_FILE, serializeBalances(before, os.time()))

	local baseline = table.clone(before)
	local deadline = os.clock() + CONFIG.SPEND_TIMEOUT
	while os.clock() < deadline do
		if _G.AE_ROLLBACK_LEAVE == true then
			log("manual leave flag set")
			break
		end
		local now = readBalances()
		for _, itemName in CONFIG.TRACKED_ITEMS do
			if now[itemName] ~= nil and baseline[itemName] ~= nil and now[itemName] ~= baseline[itemName] then
				log(("spend detected: %s %s -> %s"):format(
					itemName,
					tostring(baseline[itemName]),
					tostring(now[itemName])
				))
				if CONFIG.LINGER_AFTER_SPEND > 0 then
					task.wait(CONFIG.LINGER_AFTER_SPEND)
				end
				log("disconnecting now to hit the save window")
				localPlayer:Kick("rollback race test - rejoin and run VERIFY")
				return
			end
		end
		task.wait(0.1)
	end
	log("no spend detected before timeout; snapshot stays armed for the next run")
	return
end

-- VERIFY MODE
local before = parseBalances(snapshotText)
local now = readBalances()
log("VERIFY against snapshot: " .. snapshotText)

local restored = true
for _, itemName in CONFIG.TRACKED_ITEMS do
	local was = before[itemName]
	local is = now[itemName]
	if was ~= nil and is ~= nil then
		if is == was then
			log(("%-12s %d -> %d  (rolled back / unchanged)"):format(itemName, was, is))
		else
			log(("%-12s %d -> %d  (spend PERSISTED)"):format(itemName, was, is))
			restored = false
		end
	else
		log(("%-12s unreadable (before=%s now=%s)"):format(itemName, tostring(was), tostring(is)))
	end
end

if restored then
	log("RESULT: balances match the pre-spend snapshot - rollback RACE CONFIRMED (spends did not persist)")
else
	log("RESULT: at least one spend persisted - the server saves on leave; this race does not apply")
end

pcall(function()
	delfile(CONFIG.SNAPSHOT_FILE)
end)
log("snapshot cleared; run ARM mode again for another experiment")
