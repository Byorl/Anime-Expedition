local Build = rbxmk.loadFile("src/Build.lua")()()
assert(Build.Version == "1.29.7", "interface release version is wrong")
local Manifest = rbxmk.loadFile("manifest.lua")()
assert(Manifest.Version == Build.Version, "manifest and interface versions differ")
assert(
	Build.MacLibUrl
		== "https://raw.githubusercontent.com/Byorl/Maclib/7a99c23bde4eee7d19b054462b17985d06a74ae5/src/maclib.lua",
	"interface is not pinned to the tested Byorl Maclib revision"
)

local mainSource = fs.read("src/Main.lua", "bin")
local uiManagerSource = fs.read("src/Core/UIManager.lua", "bin")
local configManagerSource = fs.read("src/Core/ConfigManager.lua", "bin")
local gameAdapterSource = fs.read("src/Core/GameAdapter.lua", "bin")
local loaderSource = fs.read("loader.lua", "bin")
local miscSource = fs.read("src/Modules/Misc.lua", "bin")
assert(string.find(mainSource, "MountMobileLauncher", 1, true), "mobile launcher is not mounted")
assert(string.find(uiManagerSource, "AnimeExpeditions_MobileLauncher", 1, true), "mobile launcher UI is missing")
assert(string.find(uiManagerSource, "not UserInputService.TouchEnabled", 1, true), "mobile launcher is not keyed directly to touch support")
assert(string.find(uiManagerSource, "screen.Parent = parent", 1, true), "mobile launcher ScreenGui is never mounted")
assert(string.find(uiManagerSource, "self.Window:SetState", 1, true), "mobile launcher cannot toggle the window")
assert(string.find(uiManagerSource, "InputChanged", 1, true), "mobile launcher is not draggable")
assert(string.find(uiManagerSource, "account.UI.MobileLauncher", 1, true), "mobile launcher position is not saved")
assert(string.find(configManagerSource, "MobileLauncher", 1, true), "mobile launcher account default is missing")
assert(string.find(configManagerSource, "HiddenOnLoad", 1, true), "hide-on-load account default is missing")
assert(string.find(mainSource, "Config.Account.UI.HiddenOnLoad", 1, true), "hide-on-load is not applied after startup")
assert(string.find(gameAdapterSource, 'waitForChild(replicatedStorage, "Nodes", deadline)', 1, true), "game adapter does not wait for Nodes replication")
assert(string.find(gameAdapterSource, 'waitForChild(fusionInstance, "State", deadline)', 1, true), "game adapter has no Fusion State fallback")
assert(string.find(gameAdapterSource, "self.FusionPeek(value)", 1, true), "game adapter does not use the validated Fusion peek function")
assert(string.find(mainSource, "if not Adapter.Ready then", 1, true), "game binding startup failures are not reported before feature loading")
assert(string.find(loaderSource, "game:IsLoaded()", 1, true), "loader does not wait for Roblox startup")
assert(string.find(miscSource, 'ctx.Tabs.MiscClaims:Section', 1, true), "reward popup control is not in a general Misc area")
assert(string.find(miscSource, 'ctx.Game:FireLocal("PROMPT_CLOSE_ALL")', 1, true), "reward popup suppression does not close unkeyed prompts")
assert(string.find(miscSource, "task.delay(0.05, dismiss)", 1, true), "reward popup suppression does not run after the game mounts its prompt")
assert(string.find(mainSource, "local profileReady = true", 1, true), "failed config loads are not save-locked")
assert(string.find(configManagerSource, "post-load verification failed", 1, true), "config load verification is missing")
local bountySource = fs.read("src/Modules/Bounty.lua", "bin")
assert(not string.find(bountySource, 'InvokeSelf("GET_PLAYER_REPLICA")', 1, true), "Bounty startup still uses a blocking replica lookup")
assert(string.find(bountySource, "local worker = task.defer", 1, true), "Bounty live reads are not deferred until after module startup")
local joinPosition = assert(string.find(mainSource, "Join = TabGroup:Tab", 1, true), "Join tab is missing")
local autoPlayPosition = assert(string.find(mainSource, "AutoPlay = TabGroup:Tab", 1, true), "Auto Play tab is missing")
local gamePosition = assert(string.find(mainSource, "Game = TabGroup:Tab", 1, true), "Game tab is missing")
local miscPosition = assert(string.find(mainSource, "Misc = TabGroup:Tab", 1, true), "Misc tab is missing")
local priorityPosition = assert(string.find(mainSource, "Priority = TabGroup:Tab", 1, true), "Priority tab is missing")
local settingsPosition = assert(string.find(mainSource, "Settings = TabGroup:Tab", 1, true), "Settings tab is missing")
assert(joinPosition < autoPlayPosition and autoPlayPosition < gamePosition, "Auto Play is not between Join and Game")
assert(miscPosition < priorityPosition and priorityPosition < settingsPosition, "Priority is not between Misc and Settings")
for _, name in ipairs({ "MiscClaims", "MiscUnits", "MiscBounty", "MiscMinigame", "MiscPerformance" }) do
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
assert(splitSubtabs == 7, "Misc and Auto Play subtabs should keep split sections")

local gameMatchSource = fs.read("src/Modules/GameMatch.lua", "bin")
local gameEndSource = fs.read("src/Modules/GameEnd.lua", "bin")
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
assert(string.find(autoPlaySource, "Record Match Telemetry", 1, true), "match telemetry toggle is missing")
assert(string.find(autoPlaySource, "auto_play.smart.record_telemetry", 1, true), "match telemetry is not configurable")

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
assert(string.find(settingsSource, 'Name = "Hide UI on Load"', 1, true), "Settings is missing Hide UI on Load")

print("Interface contract tests passed")
