return function()
	local Catalog = {}

	local function text(value, fallback)
		if value == nil or tostring(value) == "" then return fallback end
		return tostring(value)
	end

	local function assetInformation(information, asset)
		if type(information) ~= "table" then return nil end
		for _, collectionName in ipairs({"Units", "Items", "Assets"}) do
			local collection = information[collectionName]
			if type(collection) == "table" and type(collection[asset]) == "table" then
				return collection[asset]
			end
		end
		return nil
	end

	function Catalog.UnitName(information, unit)
		if type(unit) ~= "table" then return "Unknown" end
		local asset = unit.Asset
		local info = assetInformation(information, asset)
		return text(info and (info.DisplayName or info.Name), text(asset, "Unknown"))
	end

	function Catalog.UnitRarity(information, unit)
		if type(unit) ~= "table" then return "Unknown" end
		local info = assetInformation(information, unit.Asset)
		return text(info and info.Rarity, text(unit.Rarity, "Unknown"))
	end

	function Catalog.TraitName(information, trait)
		if trait == nil or trait == "" or trait == "None" then return "None" end
		local traits = type(information) == "table" and information.Traits or nil
		local data = type(traits) == "table" and traits.TraitData or nil
		local info = type(data) == "table" and data[trait] or nil
		return text(type(info) == "table" and (info.DisplayName or info.Name), tostring(trait))
	end

	function Catalog.OwnedAmount(playerData, information, asset)
		if type(playerData) ~= "table" or asset == nil then return 0 end
		local dataKey = "ItemData"
		local info = assetInformation(information, asset)
		if type(info) == "table" and type(information.AssetTypes) == "table" then
			local assetType = information.AssetTypes[info.Type]
			if type(assetType) == "table" and assetType.DataKey then dataKey = assetType.DataKey end
		end
		local collection = playerData[dataKey]
		local entry = type(collection) == "table" and collection[asset] or nil
		if type(entry) == "number" then return entry end
		if type(entry) == "table" then return tonumber(entry.Amount or entry.Value or entry.Count) or 0 end
		return 0
	end

	function Catalog.Banners(bannerData, information)
		local result = {Options = {}, ByLabel = {}, ByKey = {}, Entries = {}}
		local globalStyles = type(information) == "table" and information.BannerInfo or nil
		globalStyles = type(globalStyles) == "table" and globalStyles.Styling or nil
		for rawKey, banner in pairs(type(bannerData) == "table" and bannerData or {}) do
			if type(banner) == "table" then
				local info = type(banner.BannerInfo) == "table" and banner.BannerInfo or {}
				if info.Hidden ~= true then
					local key = tostring(rawKey)
					local style = type(globalStyles) == "table" and globalStyles[rawKey] or nil
					if type(style) ~= "table" then style = info.Styling end
					local name = text(type(style) == "table" and style.Name, text(info.DisplayName, key))
					local label = string.format("%s [%s]", name, key)
					table.insert(result.Entries, {
						Key = key,
						Label = label,
						LayoutOrder = tonumber((type(style) == "table" and style.LayoutOrder) or info.LayoutOrder) or math.huge,
						Info = info,
					})
				end
			end
		end
		table.sort(result.Entries, function(a, b)
			if a.LayoutOrder ~= b.LayoutOrder then return a.LayoutOrder < b.LayoutOrder end
			return string.lower(a.Label) < string.lower(b.Label)
		end)
		for _, entry in ipairs(result.Entries) do
			table.insert(result.Options, entry.Label)
			result.ByLabel[entry.Label] = entry.Key
			result.ByKey[entry.Key] = entry.Label
		end
		return result
	end

	function Catalog.Units(playerData, information)
		local result = {Options = {}, ByLabel = {}, ByKey = {}, Entries = {}}
		local units = type(playerData) == "table" and playerData.UnitData or nil
		for rawId, unit in pairs(type(units) == "table" and units or {}) do
			if type(unit) == "table" then
				local id = tostring(rawId)
				local name = Catalog.UnitName(information, unit)
				local trait = Catalog.TraitName(information, unit.Trait)
				local level = math.max(1, math.floor(tonumber(unit.Level) or 1))
				local label = string.format("%s | Lv %d | %s [#%s]", name, level, trait, id)
				table.insert(result.Entries, {Key = id, Label = label, Name = name, Level = level, Trait = trait})
			end
		end
		table.sort(result.Entries, function(a, b)
			local left, right = string.lower(a.Name), string.lower(b.Name)
			if left ~= right then return left < right end
			if a.Level ~= b.Level then return a.Level > b.Level end
			return a.Key < b.Key
		end)
		for _, entry in ipairs(result.Entries) do
			table.insert(result.Options, entry.Label)
			result.ByLabel[entry.Label] = entry.Key
			result.ByKey[entry.Key] = entry.Label
		end
		return result
	end

	function Catalog.Traits(information)
		local result = {Options = {}, ByLabel = {}, ByKey = {}, Entries = {}}
		local traits = type(information) == "table" and information.Traits or nil
		local data = type(traits) == "table" and traits.TraitData or nil
		for rawKey, info in pairs(type(data) == "table" and data or {}) do
			if type(info) == "table" then
				local key = tostring(rawKey)
				table.insert(result.Entries, {
					Key = key,
					Label = text(info.DisplayName or info.Name, key),
					Chance = tonumber(info.Chance) or math.huge,
					Rarity = text(info.Rarity, "Rare"),
				})
			end
		end
		table.sort(result.Entries, function(a, b)
			if a.Chance ~= b.Chance then return a.Chance < b.Chance end
			return string.lower(a.Label) < string.lower(b.Label)
		end)
		local used = {}
		for _, entry in ipairs(result.Entries) do
			local label = entry.Label
			if used[string.lower(label)] then label = string.format("%s [%s]", label, entry.Key) end
			used[string.lower(label)] = true
			table.insert(result.Options, label)
			result.ByLabel[label] = entry.Key
			result.ByKey[entry.Key] = label
		end
		return result
	end

	function Catalog.Rarities(information)
		local source = type(information) == "table" and information.OrderedRarities or nil
		local values = {}
		if type(source) == "table" then
			for key, value in pairs(source) do
				if type(key) == "number" then table.insert(values, tostring(value)) end
			end
		end
		if #values == 0 then values = {"Rare", "Epic", "Legendary", "Mythic", "Exclusive", "Secret"} end
		local output = {"None"}
		for index = #values, 1, -1 do
			if values[index] ~= "Secret" then table.insert(output, values[index]) end
		end
		return output
	end

	function Catalog.ExtractBracketKey(value, marker)
		if type(value) ~= "string" then return value end
		marker = marker or ""
		return string.match(value, "%[" .. marker .. "([^%]]+)%]%s*$") or value
	end

	return Catalog
end
