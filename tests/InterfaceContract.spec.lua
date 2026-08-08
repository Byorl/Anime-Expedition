local Build = rbxmk.loadFile("src/Build.lua")()()
assert(Build.Version == "1.7.0", "interface release version is wrong")
assert(Build.MacLibUrl == "https://raw.githubusercontent.com/Byorl/Maclib/a923f62aaad79a9dae59093187360f940a2ac02f/src/maclib.lua", "interface is not pinned to the tested Byorl Maclib revision")

local mainSource = fs.read("src/Main.lua", "bin")
for _, name in ipairs({"JoinStory", "JoinChallenge", "JoinEvent", "JoinRaid", "GameMatch", "GameEnd", "WebhookDelivery", "WebhookPings", "MiscClaims", "MiscUnits", "MiscPerformance", "SettingsConfigs", "SettingsAppearance"}) do
	assert(string.find(mainSource, "Tabs." .. name, 1, true), "missing subtab " .. name)
end

local settingsSource = fs.read("src/Modules/Settings.lua", "bin")
assert(string.find(settingsSource, 'DisplayMethod = "LiteralPercent"', 1, true), "UI size does not use literal percentages")
assert(string.find(settingsSource, "Step = 1", 1, true), "UI size does not use whole-percent steps")

print("Interface contract tests passed")
