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

print("Join coordinator tests passed")
