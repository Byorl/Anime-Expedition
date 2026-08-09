task = task or {}
task.wait = task.wait or function() end
task.spawn = task.spawn or function()
	return {}
end
task.delay = task.delay or function()
	return {}
end

DateTime = DateTime or {
	now = function()
		return {
			ToIsoDate = function()
				return "2026-08-08T00:00:00Z"
			end,
		}
	end,
}
game = game
	or {
		GetService = function(_, name)
			if name == "HttpService" then
				return {
					JSONEncode = function()
						return "{}"
					end,
				}
			end
			return {}
		end,
	}

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
	if cache[name] then
		return cache[name]
	end
	cache[name] = factories[name](Import)
	return cache[name]
end

local nodeCallbacks = {}
local disconnects = 0
local ResultsHub = Import("ResultsHub")
local hub = ResultsHub.new({
	Connect = function(_, name, callback)
		nodeCallbacks[name] = callback
		return {
			Disconnect = function()
				disconnects = disconnects + 1
			end,
		}
	end,
})
local receivedRuns
local unsubscribe = hub:Subscribe("test", function(_, runs)
	receivedRuns = runs
end)
local deliveryDone, preReserved
local unsubscribeProbe = hub:Subscribe("probe", function(_, _, resultRevision)
	preReserved = not hub:DeliveryState(resultRevision, 15)
end)
local unsubscribeDelivery = hub:Subscribe("Webhook", function(_, _, _, complete)
	deliveryDone = complete
end, true)
nodeCallbacks.SET_END_PARAMETERS({ Victory = true })
assert(receivedRuns == 1 and hub.Runs == 1, "results hub did not count or dispatch the match")
local deliveryReady, pendingDeliveries = hub:DeliveryState(1, 15)
assert(
	preReserved and not deliveryReady and pendingDeliveries[1] == "Webhook",
	"webhook delivery was not reserved before result subscribers ran"
)
deliveryDone(true)
assert(not hub:DeliveryState(1, 15, 1.25), "successful webhook delivery had no settling window")
assert(hub:DeliveryState(1, 15), "completed webhook delivery continued blocking end actions")
local current, runs, revision, visible = hub:Snapshot()
assert(current.Victory == true and runs == 1 and revision == 1 and not visible, "result snapshot is incorrect")
nodeCallbacks.SHOW_END_SCREEN()
current, runs, revision, visible = hub:Snapshot()
assert(current.Victory == true and visible, "visible result screen was not tracked")
unsubscribe()
unsubscribeProbe()
unsubscribeDelivery()
nodeCallbacks.SET_END_PARAMETERS({ Victory = true })
assert(receivedRuns == 1 and hub.Runs == 2, "results hub unsubscribe failed")
nodeCallbacks.HIDE_END_SCREEN()
assert(hub:Snapshot() == nil, "hidden result screen was not cleared")
hub:Destroy()
assert(disconnects == 3, "results hub did not disconnect every result event")

local information = {
	OrderedRarities = { "Rare", "Epic", "Legendary", "Mythic", "Exclusive", "Secret" },
	Units = { Ban = { DisplayName = "Ban", Type = "Unit", Rarity = "Legendary" } },
	Items = {
		Gem = { DisplayName = "Gem", Type = "Item", Rarity = "Mythic" },
		Gold = { DisplayName = "Gold", Type = "Item" },
		TraitReroll = { DisplayName = "Trait Crystal", Type = "Item" },
		EquipmentReroll = { DisplayName = "Equipment Reroll", Type = "Item" },
	},
	Assets = { Relic = { DisplayName = "Relic", Type = "Equipment", Rarity = "Mythic" } },
	AssetTypes = { Item = { DataKey = "ItemData" }, Equipment = { DataKey = "EquipmentData" } },
	Traits = { TraitData = { Unbound = { DisplayName = "Unbound" } } },
	Maps = {
		PreviewInfo = { SpiritCity = { DisplayName = "Spirit City", PreviewImage = "rbxassetid://12345" } },
		GamemodeTypes = { Raid = { NextAllowed = true } },
	},
	StageDrops = {
		Entries = { { Asset = "Gem" }, { Asset = "Relic" } },
		GetDrops = function()
			return { { Asset = "Gem" }, { Asset = "Relic" } }
		end,
	},
}
function information:GetAssetType(asset)
	local info = self.Units[asset] or self.Items[asset] or self.Assets[asset]
	return info and info.Type
end
local playerData = {
	Level = 143,
	ItemData = { Gem = 34685, Gold = 229051, TraitReroll = 67, EquipmentReroll = 539 },
	EquipmentData = { Relic = 2 },
	UnitData = { unit1 = { Asset = "Ban", Level = 50, Trait = "Unbound" } },
	Settings = {},
}
local adapter = {
	Information = function()
		return information
	end,
	PlayerData = function()
		return playerData
	end,
	HotbarData = function()
		return { Slots = { [1] = { ID = "unit1" } } }
	end,
	State = function(_, name)
		if name == "ChallengeData" then
			return { Regular = { {} } }
		end
		return nil
	end,
	IsInGame = function()
		return false
	end,
	ChangeSetting = function()
		return true
	end,
}
local Reporter = Import("WebhookReporter")
local reporter = Reporter.new({ Name = "Tester" }, adapter)
local result = {
	Victory = true,
	HasNextStage = true,
	RestartDisabled = false,
	Rewards = { { Asset = "Gem", Amount = 125 }, { Asset = "Relic", Amount = 1 } },
	EquippedUnits = { [1] = { UnitID = "unit1" } },
	MapName = "SpiritCity",
	ActName = "Act 3",
	Gamemode = "Raid",
	Difficulty = "Hard",
	TotalTime = 370,
}
local payload = reporter:MatchPayload(
	{ PingDrops = {}, EquipmentRarity = "Mythic", MentionEveryone = true, DiscordUserId = "<@938129321>" },
	result,
	4
)
assert(payload.content == "@everyone <@938129321>", "webhook mentions were not generated")
assert(payload.embeds[1].footer.text == "discord.gg/V3WcdHpd3J", "webhook footer is wrong")
assert(string.find(payload.embeds[1].description, "Spirit City - Act 3 - Raid", 1, true), "webhook map data is missing")
assert(string.find(payload.embeds[1].description, "**Time:** 06:10", 1, true), "webhook time is missing")
assert(string.find(payload.embeds[1].description, "[50] - Ban (Unbound)", 1, true), "webhook unit data is missing")
assert(payload.embeds[1].thumbnail.url, "webhook map thumbnail is missing")
local liveResult = {
	Victory = true,
	Rewards = { Gem = { Amount = 125 } },
	GainedUnitExp = { [1] = { UnitID = "unit1" } },
	MapName = "SpiritCity",
	ActName = "Act 3",
	Gamemode = "Raid",
	Difficulty = "Hard",
	TotalTime = 370,
}
local livePayload = reporter:MatchPayload(
	{ PingDrops = {}, EquipmentRarity = "None", MentionEveryone = false, DiscordUserId = "" },
	liveResult,
	1
)
assert(string.find(livePayload.embeds[1].description, "[50] - Ban (Unbound)", 1, true), "live result units were not resolved")
assert(string.find(livePayload.embeds[1].description, "+[125] Gem", 1, true), "dictionary rewards were not resolved")
local noEquipment = { Rewards = { { Asset = "Gem", Amount = 1 } } }
local mentions = reporter:Mentions(
	{ PingDrops = {}, EquipmentRarity = "Mythic", MentionEveryone = true, DiscordUserId = "938129321" },
	noEquipment,
	information
)
assert(mentions == "", "item rarity incorrectly triggered an equipment rarity ping")

local controls = {}
local callbacks = {}
local section = {}
function section:Header() end
function section:Button(settings)
	return { Settings = settings }
end
local function addControl(settings, flag)
	controls[flag] = {
		Settings = settings,
		ClearOptions = function() end,
		InsertOptions = function() end,
		UpdateSelection = function() end,
	}
	callbacks[flag] = settings.Callback or settings.onChanged
	return controls[flag]
end
local registry = {}
function registry:Toggle(_, settings, flag)
	return addControl(settings, flag)
end
function registry:Slider(_, settings, flag)
	return addControl(settings, flag)
end
function registry:Dropdown(_, settings, flag)
	return addControl(settings, flag)
end
function registry:Input(_, settings, flag)
	return addControl(settings, flag)
end
local subscriptions = {}
local context = {
	Tabs = {
		Game = {
			Section = function()
				return section
			end,
		},
		Webhook = {
			Section = function()
				return section
			end,
		},
	},
	Registry = registry,
	Runtime = { Alive = false, Notify = function() end },
	Game = adapter,
	Results = {
		StartedAt = os.clock(),
		Subscribe = function(_, name, callback)
			subscriptions[name] = callback
			return function() end
		end,
	},
	Webhook = reporter,
	RegisterCleanup = function() end,
}

for _, name in ipairs({ "GameMatch", "GameEnd", "Webhook" }) do
	local module = Import(name)
	local ok, err = pcall(module.Init, module, context)
	assert(ok, name .. " failed to initialize: " .. tostring(err))
end
local GameEnd = Import("GameEnd")
assert(GameEnd.Choose(context, { AutoReplay = true }, result, 1) == "Restart", "Auto Replay action is wrong")
assert(GameEnd.Choose(context, { AutoLeave = true }, result, 1) == "Lobby", "Auto Leave action is wrong")
assert(GameEnd.Choose(context, { AutoNext = true }, result, 1) == "Next", "Auto Next action is wrong")
assert(
	GameEnd.Choose(context, { Smart = true }, { Victory = false, RestartDisabled = false }, 1) == "Restart",
	"smart end action did not fall back to replay"
)
assert(
	GameEnd.Choose(context, { Smart = true }, { Victory = false, RestartDisabled = true }, 1) == "Lobby",
	"smart end action did not fall back to leave"
)
assert(
	controls["game.match.start_delay"].Settings.Minimum == 0
		and controls["game.match.start_delay"].Settings.Maximum == 10,
	"auto start delay range is wrong"
)
assert(controls["game.match.leave_wave"].Settings.Maximum == 500, "leave wave range is wrong")
assert(controls["game.end.leave_matches"].Settings.Maximum == 100, "match limit range is wrong")
assert(
	controls["game.end.hours"].Settings.Minimum == 1 and controls["game.end.hours"].Settings.Maximum == 12,
	"lobby timer range is wrong"
)
assert(
	controls["webhook.ping_drops"].Settings.Multi == true and controls["webhook.ping_drops"].Settings.Search == true,
	"webhook drop selection is not searchable multi-select"
)
assert(controls["webhook.equipment_rarity"].Settings.Search == true, "webhook rarity selection is not searchable")
local webhookSource = fs.read("src/Modules/Webhook.lua", "bin")
assert(not string.find(webhookSource, "task.delay(0.5", 1, true), "match webhooks still have an artificial delivery delay")
assert(
	string.find(webhookSource, "ctx.Webhook:MatchPayload(state, result, runs)", 1, true),
	"match data is not captured before asynchronous delivery"
)
assert(
	string.find(webhookSource, 'BeginDelivery("Webhook", revision)', 1, true)
		and string.find(webhookSource, "complete(requestOk and ok == true)", 1, true)
		and string.find(webhookSource, "end, true))", 1, true),
	"match webhook delivery is not acknowledged"
)

local gameEndSource = fs.read("src/Modules/GameEnd.lua", "bin")
assert(string.find(gameEndSource, "ctx.Results:Snapshot()", 1, true), "end actions do not poll the live result screen")
assert(
	string.find(gameEndSource, "state.EndAttempts = state.EndAttempts + 1", 1, true),
	"end actions are not retried until accepted"
)
assert(
	string.find(gameEndSource, "ctx.Results:DeliveryState(revision, 15, 1.25)", 1, true),
	"end actions do not wait for webhook delivery and its settling window"
)

print("Game and webhook tests passed")
