local Build = rbxmk.loadFile("src/Build.lua")()()
assert(Build.Version == "1.7.1", "interface release version is wrong")
assert(
	Build.MacLibUrl
		== "https://raw.githubusercontent.com/Byorl/Maclib/bc2a01d6c074bf3930c3ddaa4791887e63ea9782/src/maclib.lua",
	"interface is not pinned to the tested Byorl Maclib revision"
)

local mainSource = fs.read("src/Main.lua", "bin")
for _, name in ipairs({ "MiscClaims", "MiscUnits", "MiscPerformance" }) do
	assert(string.find(mainSource, "Tabs." .. name, 1, true), "missing subtab " .. name)
end
assert(not string.find(mainSource, "Tabs.Join:SubTabGroup()", 1, true), "Join should use one split page")
assert(not string.find(mainSource, "Tabs.Game:SubTabGroup()", 1, true), "Game should use one split page")
local splitSubtabs = 0
for _ in string.gmatch(mainSource, "Columns = 2") do
	splitSubtabs = splitSubtabs + 1
end
assert(splitSubtabs == 3, "Misc subtabs should keep split sections")

local gameMatchSource = fs.read("src/Modules/GameMatch.lua", "bin")
local gameEndSource = fs.read("src/Modules/GameEnd.lua", "bin")
assert(not string.find(gameMatchSource, "Leave at Wave (0=off)", 1, true), "Leave at Wave is still in Match")
assert(string.find(gameEndSource, "Leave at Wave (0=off)", 1, true), "Leave at Wave is missing from End of Match")

local settingsSource = fs.read("src/Modules/Settings.lua", "bin")
assert(
	string.find(settingsSource, 'DisplayMethod = "LiteralPercent"', 1, true),
	"UI size does not use literal percentages"
)
assert(string.find(settingsSource, "Step = 1", 1, true), "UI size does not use whole-percent steps")

print("Interface contract tests passed")
