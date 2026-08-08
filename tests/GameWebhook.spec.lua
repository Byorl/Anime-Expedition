task = task or {}
task.wait = task.wait or function() end
task.spawn = task.spawn or function() return {} end
task.delay = task.delay or function() return {} end

DateTime = DateTime or {now = function() return {ToIsoDate = function() return "2026-08-08T00:00:00Z" end} end}
game = game or {GetService = function(_, name)
	if name == "HttpService" then return {JSONEncode = function() return "{}" end} end
	return {}
end}

local factories = {
	Util = rbxmk.loadFile("src/Core/Util.lua")(),
	AutomationCatalog = rbxmk.loadFile("src/Core/AutomationCatalog.lua")(),
	JoinCatalog = rbxmk.loadFile("src/Core/JoinCatalog.lua")(),
	ResultsHub = rbxmk.loadFile("src/Core/ResultsHub.lua")(),
	WebhookReporter = rbxmk.loadFile("src/Core/WebhookReporter.lua")(),
	GameMatch = rbxmk.loadFile("src/Modules/GameMatch.lua")(),
	GameEnd = rbxmk.loadFile("src/Modules/GameEnd.lua")(),
	Webhook = rbxmk.loadFile("src/Modules/Webhook.lua")(),
}
local cache = {}
local function Import(name)
	if cache[name] then return cache[name] end
	cache[name] = factories[name](Import)
	return cache[name]
end

local resultCallback
local disconnected = false
local ResultsHub = Import("ResultsHub")
local hub = ResultsHub.new({Connect = function(_, name, callback)
	assert(name == "SET_END_PARAMETERS", "results hub used the wrong event")
	resultCallback = callback
	return {Disconnect = function() disconnected = true end}
end})
local receivedRuns
local unsubscribe = hub:Subscribe("test", function(_, runs) receivedRuns = runs end)
resultCallback({Victory = true})
assert(receivedRuns == 1 and hub.Runs == 1, "results hub did not count or dispatch the match")
unsubscribe()
resultCallback({Victory = true})
assert(receivedRuns == 1 and hub.Runs == 2, "results hub unsubscribe failed")
hub:Destroy()
assert(disconnected == true, "results hub did not disconnect")

local information = {
	OrderedRarities = {"Rare", "Epic", "Legendary", "Mythic", "Exclusive", "Secret"},
	Units = {Ban = {DisplayName = "Ban", Type = "Unit", Rarity = "Legendary"}},
	Items = {
		Gem = {DisplayName = "Gem", Type = "Item", Rarity = "Mythic"},
		Gold = {DisplayName = "Gold", Type = "Item"},
		TraitReroll = {DisplayName = "Trait Crystal", Type = "Item"},
		EquipmentReroll = {DisplayName = "Equipment Reroll", Type = "Item"},
	},
	Assets = {Relic = {DisplayName = "Relic", Type = "Equipment", Rarity = "Mythic"}},
	AssetTypes = {Item = {DataKey = "ItemData"}, Equipment = {DataKey = "EquipmentData"}},
	Traits = {TraitData = {Unbound = {DisplayName = "Unbound"}}},
	Maps = {PreviewInfo = {SpiritCity = {DisplayName = "Spirit City", PreviewImage = "rbxassetid://12345"}}, GamemodeTypes = {Raid = {NextAllowed = true}}},
	StageDrops = {Entries = {{Asset = "Gem"}, {Asset = "Relic"}}, GetDrops = function() return {{Asset = "Gem"}, {Asset = "Relic"}} end},
}
function information:GetAssetType(asset)
	local info = self.Units[asset] or self.Items[asset] or self.Assets[asset]
	return info and info.Type
end
local playerData = {
	Level = 143,
	ItemData = {Gem = 34685, Gold = 229051, TraitReroll = 67, EquipmentReroll = 539},
	EquipmentData = {Relic = 2},
	UnitData = {unit1 = {Asset = "Ban", Level = 50, Trait = "Unbound"}},
	Settings = {},
}
local adapter = {
	Information = function() return information end,
	PlayerData = function() return playerData end,
	State = function(_, name) if name == "ChallengeData" then return {Regular = {{}}} end return nil end,
	IsInGame = function() return false end,
	ChangeSetting = function() return true end,
}
local Reporter = Import("WebhookReporter")
local reporter = Reporter.new({Name = "Tester"}, adapter)
local result = {
	Victory = true,
	HasNextStage = true,
	RestartDisabled = false,
	Rewards = {{Asset = "Gem", Amount = 125}, {Asset = "Relic", Amount = 1}},
	EquippedUnits = {[1] = {UnitID = "unit1"}},
	MapName = "SpiritCity",
	ActName = "Act 3",
	Gamemode = "Raid",
	Difficulty = "Hard",
	TotalTime = 370,
}
local payload = reporter:MatchPayload({PingDrops = {}, EquipmentRarity = "Mythic", MentionEveryone = true, DiscordUserId = "<@938129321>"}, result, 4)
assert(payload.content == "@everyone <@938129321>", "webhook mentions were not generated")
assert(payload.embeds[1].footer.text == "discord.gg/V3WcdHpd3J", "webhook footer is wrong")
assert(string.find(payload.embeds[1].fields[4].value, "Spirit City - Act 3 - Raid", 1, true), "webhook map data is missing")
assert(string.find(payload.embeds[1].fields[4].value, "Time: 06:10", 1, true), "webhook time is missing")
assert(string.find(payload.embeds[1].fields[2].value, "[50] - Ban (Unbound)", 1, true), "webhook unit data is missing")
local noEquipment = {Rewards = {{Asset = "Gem", Amount = 1}}}
local mentions = reporter:Mentions({PingDrops = {}, EquipmentRarity = "Mythic", MentionEveryone = true, DiscordUserId = "938129321"}, noEquipment, information)
assert(mentions == "", "item rarity incorrectly triggered an equipment rarity ping")

local controls = {}
local callbacks = {}
local section = {}
function section:Header() end
function section:Button(settings) return {Settings = settings} end
local function addControl(settings, flag)
	controls[flag] = {Settings = settings, ClearOptions = function() end, InsertOptions = function() end, UpdateSelection = function() end}
	callbacks[flag] = settings.Callback or settings.onChanged
	return controls[flag]
end
local registry = {}
function registry:Toggle(_, settings, flag) return addControl(settings, flag) end
function registry:Slider(_, settings, flag) return addControl(settings, flag) end
function registry:Dropdown(_, settings, flag) return addControl(settings, flag) end
function registry:Input(_, settings, flag) return addControl(settings, flag) end
local subscriptions = {}
local context = {
	Tabs = {
		Game = {Section = function() return section end},
		Webhook = {Section = function() return section end},
	},
	Registry = registry,
	Runtime = {Alive = false, Notify = function() end},
	Game = adapter,
	Results = {StartedAt = os.clock(), Subscribe = function(_, name, callback) subscriptions[name] = callback return function() end end},
	Webhook = reporter,
	RegisterCleanup = function() end,
}

for _, name in ipairs({"GameMatch", "GameEnd", "Webhook"}) do
	local module = Import(name)
	local ok, err = pcall(module.Init, module, context)
	assert(ok, name .. " failed to initialize: " .. tostring(err))
end
assert(controls["game.match.start_delay"].Settings.Minimum == 0 and controls["game.match.start_delay"].Settings.Maximum == 10, "auto start delay range is wrong")
assert(controls["game.match.leave_wave"].Settings.Maximum == 500, "leave wave range is wrong")
assert(controls["game.end.leave_matches"].Settings.Maximum == 100, "match limit range is wrong")
assert(controls["game.end.hours"].Settings.Minimum == 1 and controls["game.end.hours"].Settings.Maximum == 12, "lobby timer range is wrong")
assert(controls["webhook.ping_drops"].Settings.Multi == true and controls["webhook.ping_drops"].Settings.Search == true, "webhook drop selection is not searchable multi-select")
assert(controls["webhook.equipment_rarity"].Settings.Search == true, "webhook rarity selection is not searchable")

print("Game and webhook tests passed")
