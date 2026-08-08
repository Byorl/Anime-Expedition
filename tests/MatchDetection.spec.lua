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
assert(adapter:IsMatchActive({ Parameters = parameters }) == true, "skip prompt did not activate live detection")
local firstOk, firstResponded = adapter:RespondToVote("skip")
local secondOk, secondResponded = adapter:RespondToVote("skip")
assert(firstOk and firstResponded and secondOk and not secondResponded, "vote response state is incorrect")
assert(calls == 1, "the same vote prompt was answered more than once")

local direct = setmetatable({}, Adapter)
function direct:InvokeSelf(name)
	if name == "GET_GAME_REPLICA" then
		return true, { Data = { Wave = 6, Parameters = { Gamemode = "Story" } } }
	elseif name == "GET_HOTBAR_REPLICA" then
		return true, { Data = { Slots = { ["1"] = { ID = "u1" } } } }
	end
	return true, { Data = { Yen = 3800 } }
end
assert(direct:GameData().Wave == 6, "authoritative game replica data was not used")
assert(direct:GamePlayerData().Yen == 3800, "authoritative game player replica data was not used")
assert(direct:HotbarData().Slots["1"].ID == "u1", "authoritative hotbar replica data was not used")

local nestedAdapter = setmetatable({ Ready = true }, Adapter)
function nestedAdapter:Peek(value)
	if type(value) == "table" and value.State == true then
		return value.Value
	end
	return value
end
local deep = nestedAdapter:DeepPeek({ Unit = { State = true, Value = { UnitID = "u1", Upgrade = 2 } } }, 4)
assert(deep.Unit.UnitID == "u1" and deep.Unit.Upgrade == 2, "nested replicated unit state was not unwrapped")

print("Match detection tests passed")
