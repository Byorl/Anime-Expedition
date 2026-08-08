local Util = rbxmk.loadFile("src/Core/Util.lua")()()
local Adapter = rbxmk.loadFile("src/Core/GameAdapter.lua")()(function(name)
	assert(name == "Util", "unexpected adapter dependency")
	return Util
end)

local parameters = { Gamemode = "Story" }
assert(Adapter.MatchActive({ Parameters = parameters }) == false, "pre-match state was detected as active")
assert(Adapter.MatchActive({ Parameters = parameters, Wave = 1 }) == true, "wave did not activate match detection")
assert(
	Adapter.MatchActive({ Parameters = parameters, SessionTime = 8 }) == true,
	"timer did not activate match detection"
)
assert(
	Adapter.MatchActive({ Parameters = parameters, EnemyCount = 13 }) == true,
	"enemies did not activate match detection"
)
assert(Adapter.MatchActive({ Parameters = parameters, WavesEnabled = true }) == true, "wave state was ignored")
assert(
	Adapter.MatchActive({ Parameters = parameters, Wave = 1, EndTime = 100 }) == true,
	"active timer ended the match"
)
assert(
	Adapter.MatchActive({ Parameters = parameters, Wave = 1, GameEnded = true }) == false,
	"ended match stayed active"
)
assert(
	Adapter.MatchActive({ Parameters = parameters, Wave = 1, Status = "Completed" }) == false,
	"results stayed active"
)

local player = { Name = "Tester", UserId = 123 }
local calls = 0
local prompt = {
	Data = { Parameters = { Title = "Skip Wave?" }, Responses = {}, Players = { player } },
	FireServer = function(_, action, response)
		assert(action == "Response" and response == true, "vote response is malformed")
		calls = calls + 1
	end,
}
local adapter = setmetatable({
	ReplicaClient = {
		Test = function()
			return { TokenReplicas = { VotePrompt = { [prompt] = true } } }
		end,
	},
	RespondedVotes = setmetatable({}, { __mode = "k" }),
	LocalPlayer = player,
}, Adapter)
local firstOk, firstResponded = adapter:RespondToVote("skip")
local secondOk, secondResponded = adapter:RespondToVote("skip")
assert(firstOk and firstResponded and secondOk and not secondResponded, "vote response state is incorrect")
assert(calls == 1, "the same vote prompt was answered more than once")

print("Match detection tests passed")
