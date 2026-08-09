local Util = rbxmk.loadFile("src/Core/Util.lua")()()
local Coordinator = rbxmk.loadFile("src/Core/JoinCoordinator.lua")()(function(name)
	assert(name == "Util", "unexpected coordinator dependency")
	return Util
end)

local deferred
task = {
	spawn = function(callback)
		deferred = callback
		return {}
	end,
	wait = function() end,
}

local function run(inGame)
	local joins, waits = 0, 0
	local runtime = { Alive = true, Notify = function() end }
	local gameAdapter = {
		IsInGame = function()
			return inGame
		end,
		Join = function(_, queue)
			assert(queue.Gamemode == "Story", "coordinator changed the queue payload")
			joins = joins + 1
			return true
		end,
		LeaveMatchmaking = function()
			return true
		end,
	}
	local coordinator = Coordinator.new(runtime, gameAdapter)
	coordinator:Register("Story", 100, function()
		return { Queue = { Gamemode = "Story", MapName = "Dressrosa", ActName = "Act 1", Difficulty = "Normal" }, Delay = 0 }
	end)
	task.wait = function()
		waits = waits + 1
		if joins > 0 or waits >= 3 then runtime.Alive = false end
	end
	deferred()
	return joins
end

assert(run(false) == 1, "lobby candidate never reached the join adapter")
assert(run(true) == 0, "join adapter ran while an active game was present")

local available = true
local rankingRuntime = {Alive = false, Notify = function() end}
local ranking = Coordinator.new(rankingRuntime, {})
ranking:Register("Story", 600, function()
	return {Queue = {Gamemode = "Story"}}
end)
ranking:Register("Challenge", 400, function()
	return available and {Queue = {Gamemode = "Challenge"}} or nil
end)
assert(ranking:_Candidate().Provider == "Story", "fallback order did not prefer Story")
local shouldInterrupt = ranking:ShouldInterrupt("Challenge", "Story")
assert(not shouldInterrupt, "challenge refresh bypassed the fallback provider order")
ranking:SetPriority("Story", 1)
ranking:SetPriority("Challenge", 6)
ranking:SetPriorityEnabled(true)
assert(ranking:_Candidate().Provider == "Challenge", "custom priority did not prefer Challenge")
shouldInterrupt = ranking:ShouldInterrupt("Challenge", "Story")
assert(shouldInterrupt, "selected challenge did not interrupt a lower-priority story match")
shouldInterrupt = ranking:ShouldInterrupt("Challenge", "Challenge")
assert(not shouldInterrupt, "challenge refresh attempted to leave an active challenge")
shouldInterrupt = ranking:ShouldInterrupt("Challenge", nil)
assert(not shouldInterrupt, "unknown current gamemode did not fail safe")
available = false
assert(ranking:_Candidate().Provider == "Story", "unavailable high-priority mode blocked a fallback candidate")

print("Join coordinator tests passed")
