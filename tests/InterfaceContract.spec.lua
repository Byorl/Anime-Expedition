local Build = rbxmk.loadFile("src/Build.lua")()()
assert(Build.Version == "1.24.1", "interface release version is wrong")
assert(
	Build.MacLibUrl
		== "https://raw.githubusercontent.com/Byorl/Maclib/883f45caaf4af75c59b8fc2d843f47a25d68bc91/src/maclib.lua",
	"interface is not pinned to the tested Byorl Maclib revision"
)

local mainSource = fs.read("src/Main.lua", "bin")
local joinPosition = assert(string.find(mainSource, "Join = TabGroup:Tab", 1, true), "Join tab is missing")
local autoPlayPosition = assert(string.find(mainSource, "AutoPlay = TabGroup:Tab", 1, true), "Auto Play tab is missing")
local gamePosition = assert(string.find(mainSource, "Game = TabGroup:Tab", 1, true), "Game tab is missing")
local miscPosition = assert(string.find(mainSource, "Misc = TabGroup:Tab", 1, true), "Misc tab is missing")
local priorityPosition = assert(string.find(mainSource, "Priority = TabGroup:Tab", 1, true), "Priority tab is missing")
local settingsPosition = assert(string.find(mainSource, "Settings = TabGroup:Tab", 1, true), "Settings tab is missing")
assert(joinPosition < autoPlayPosition and autoPlayPosition < gamePosition, "Auto Play is not between Join and Game")
assert(miscPosition < priorityPosition and priorityPosition < settingsPosition, "Priority is not between Misc and Settings")
for _, name in ipairs({ "MiscClaims", "MiscUnits", "MiscPerformance" }) do
	assert(string.find(mainSource, "Tabs." .. name, 1, true), "missing subtab " .. name)
end
for _, name in ipairs({ "AutoPlayNormal", "AutoPlaySmart" }) do
	assert(string.find(mainSource, "Tabs." .. name, 1, true), "missing Auto Play subtab " .. name)
end
assert(not string.find(mainSource, "Tabs.Join:SubTabGroup()", 1, true), "Join should use one split page")
assert(not string.find(mainSource, "Tabs.Game:SubTabGroup()", 1, true), "Game should use one split page")
local splitSubtabs = 0
for _ in string.gmatch(mainSource, "Columns = 2") do
	splitSubtabs = splitSubtabs + 1
end
assert(splitSubtabs == 5, "Misc and Auto Play subtabs should keep split sections")

local gameMatchSource = fs.read("src/Modules/GameMatch.lua", "bin")
local gameEndSource = fs.read("src/Modules/GameEnd.lua", "bin")
local gameAdapterSource = fs.read("src/Core/GameAdapter.lua", "bin")
local autoPlaySource = fs.read("src/Modules/AutoPlay.lua", "bin")
assert(not string.find(gameMatchSource, "Leave at Wave (0=off)", 1, true), "Leave at Wave is still in Match")
assert(string.find(gameEndSource, "Leave at Wave (0=off)", 1, true), "Leave at Wave is missing from End of Match")
assert(string.find(gameMatchSource, 'RespondToVote("start game")', 1, true), "Auto Start does not accept start votes")
assert(string.find(gameMatchSource, 'RespondToVote("skip")', 1, true), "Auto Skip does not accept skip votes")
assert(string.find(gameMatchSource, "Prevent AFK Chamber", 1, true), "AFK prevention control is missing")
assert(string.find(gameMatchSource, "SendMouseMoveEvent", 1, true), "AFK prevention does not refresh input activity")
assert(
	string.find(gameAdapterSource, 'FireServer("Response", true)', 1, true),
	"vote prompts are not accepted directly"
)
assert(
	string.find(autoPlaySource, "ctx.Game:IsMatchActive(gameState)", 1, true)
		and string.find(autoPlaySource, "state.MatchDetected = true", 1, true),
	"Auto Play lacks live match detection"
)
assert(
	string.find(autoPlaySource, "Scenario: Waiting for match to start", 1, true),
	"Smart Auto Play has no pre-match planner state"
)

local organizedSections = {
	["src/Modules/GameMatch.lua"] = { "Match Automation", "AFK Chamber" },
	["src/Modules/GameEnd.lua"] = { "Match Actions", "Exit Conditions", "Timed Return" },
	["src/Modules/Webhook.lua"] = { "Delivery", "Webhook Destination", "Mentions", "Drop Alerts" },
	["src/Modules/Settings.lua"] = {
		"Configs",
		"Create Config",
		"Config Actions",
		"Config Behavior",
		"Runtime",
		"Appearance",
	},
}
for path, names in pairs(organizedSections) do
	local source = fs.read(path, "bin")
	for _, name in ipairs(names) do
		assert(string.find(source, name, 1, true), path .. " is missing section " .. name)
	end
end

local settingsSource = fs.read("src/Modules/Settings.lua", "bin")
assert(
	string.find(settingsSource, 'DisplayMethod = "LiteralPercent"', 1, true),
	"UI size does not use literal percentages"
)
assert(string.find(settingsSource, "Step = 1", 1, true), "UI size does not use whole-percent steps")

print("Interface contract tests passed")
