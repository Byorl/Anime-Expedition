local Catalog = rbxmk.loadFile("src/Core/AutomationCatalog.lua")()()

local information = {
	BannerInfo = {Styling = {Standard = {Name = "Standard", LayoutOrder = 1}}},
	OrderedRarities = {"Rare", "Epic", "Legendary", "Mythic", "Exclusive", "Secret"},
	Units = {
		Ban = {DisplayName = "Ban", Rarity = "Legendary", Type = "Unit"},
		Sabo = {DisplayName = "Sabo", Rarity = "Secret", Type = "Unit"},
	},
	Items = {Gem = {Type = "Item"}, TraitReroll = {Type = "Item"}},
	AssetTypes = {Item = {DataKey = "ItemData"}, Unit = {DataKey = "UnitData"}},
	Traits = {TraitData = {
		Unbound = {DisplayName = "Unbound", Chance = 0.1, Rarity = "Secret"},
		Swift = {DisplayName = "Swift", Chance = 10, Rarity = "Rare"},
		Godspeed = {DisplayName = "Godspeed", Chance = 1, Rarity = "Mythic"},
	}},
}

local banners = Catalog.Banners({
	Hidden = {BannerInfo = {Hidden = true}},
	Standard = {BannerInfo = {Cost = 50, Currency = "Gem"}},
}, information)
assert(#banners.Options == 1 and banners.ByLabel[banners.Options[1]] == "Standard", "banner catalog did not filter/map")

local playerData = {
	ItemData = {Gem = {Amount = 125}, TraitReroll = {Amount = 4}},
	UnitData = {
		["a-2"] = {Asset = "Ban", Level = 50, Trait = "Unbound"},
		["a-1"] = {Asset = "Ban", Level = 1},
	},
}
local units = Catalog.Units(playerData, information)
assert(#units.Options == 2, "unit catalog lost duplicate-looking units")
assert(string.find(units.Options[1], "Ban | Lv 50 | Unbound", 1, true), "unit label format/order is wrong")
assert(Catalog.ExtractBracketKey(units.Options[1], "#") == "a-2", "stable unit id was not recoverable")
assert(Catalog.OwnedAmount(playerData, information, "Gem") == 125, "owned item amount was wrong")

local traits = Catalog.Traits(information)
assert(traits.Options[1] == "Unbound" and traits.Options[3] == "Swift", "traits were not sorted rarest to least rare")
local rarities = Catalog.Rarities(information)
assert(rarities[1] == "None" and rarities[2] == "Exclusive" and rarities[#rarities] == "Rare", "rarity options are wrong")

print("Automation catalog tests passed")
