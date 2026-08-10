local ok, result = xpcall(function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local HttpService = game:GetService("HttpService")
	local Shared = ReplicatedStorage:WaitForChild("Shared", 15)
	assert(Shared, "ReplicatedStorage.Shared was not available after 15 seconds")
	local Information = require(Shared:WaitForChild("Information", 15))
	local UnitUtils = require(Shared:WaitForChild("UnitUtils", 15))
	assert(type(Information) == "table", "Shared.Information did not return a table")
	assert(type(Information.Units) == "table", "Information.Units is not populated")
	assert(type(Information.UnitLevelInfo) == "table", "Information.UnitLevelInfo is not populated")
	assert(type(UnitUtils.GetCalculatedStats) == "function", "UnitUtils.GetCalculatedStats is unavailable")

	local targets = {
		"Prodigy",
		"Prodigy (Rage)",
		"Cubert",
		"Bioinsect",
		"Bioinsect (Final Form)",
		"Carrot",
		"Carrot (Unleashed)",
		"The Drink",
		"The Drink (Juicebox)",
		"Vegetable",
		"Vegetable (Prince)",
	}
	local wanted = {}
	for _, name in ipairs(targets) do
		wanted[string.lower(name)] = name
	end

	local function finiteNumber(value)
		return type(value) == "number" and value == value and value > -math.huge and value < math.huge
	end

	local function primitive(value)
		local valueType = typeof(value)
		if valueType == "number" then return finiteNumber(value) and value or nil end
		if valueType == "string" or valueType == "boolean" then return value end
		return nil
	end

	local function cleanList(value)
		local output = {}
		if type(value) ~= "table" then return output end
		for key, child in pairs(value) do
			local item = primitive(child)
			if item ~= nil then
				table.insert(output, tostring(item))
			elseif type(child) == "table" then
				local name = child.Name or child.DisplayName or child.Type or key
				table.insert(output, tostring(name))
			elseif type(key) == "string" then
				table.insert(output, key)
			end
		end
		table.sort(output)
		return output
	end

	local function cleanStats(stats)
		local output = {}
		for key, value in pairs(type(stats) == "table" and stats or {}) do
			local item = primitive(value)
			if item ~= nil then output[tostring(key)] = item end
		end
		return output
	end

	local function calculate(upgrade, level, trait)
		local parameters = {
			Level = level,
			Trait = trait,
			Ascension = nil,
			StatPotential = nil,
			Equipment = {},
			TotalEquipmentMultipliers = {},
			Buffs = {},
			GameModifiers = nil,
		}
		local success, stats = pcall(UnitUtils.GetCalculatedStats, UnitUtils, upgrade, parameters)
		if not success then
			error(("stat calculation failed at level %d with trait %s: %s"):format(level, tostring(trait), tostring(stats)), 0)
		end
		return cleanStats(stats)
	end

	local found = {}
	local deadline = os.clock() + 15
	repeat
		for asset, unit in pairs(Information.Units) do
			if type(unit) == "table" then
				local displayName = tostring(unit.DisplayName or "")
				local target = wanted[string.lower(displayName)]
				if target then found[target] = {Asset = tostring(asset), Info = unit} end
			end
		end
		local count = 0
		for _ in pairs(found) do count = count + 1 end
		if count >= #targets then break end
		task.wait(0.25)
	until os.clock() >= deadline

	local levelReady, levelError = pcall(function()
		return Information.UnitLevelInfo:GetLevelDamageMulti(50)
	end)
	assert(levelReady, "UnitLevelInfo is not ready: " .. tostring(levelError))

	local report = {
		GeneratedAt = os.time(),
		PlaceId = game.PlaceId,
		JobId = game.JobId,
		Method = "Live Information.Units plus UnitUtils.GetCalculatedStats",
		Baseline = {
			Ascension = "None",
			Equipment = "None",
			GameModifiers = "None",
			StatPotential = "None",
			UnboundDynamicWaveDamage = "Excluded; Unbound adds 2% damage per wave up to 50% during a match",
		},
		Units = {},
		Missing = {},
	}

	for _, target in ipairs(targets) do
		local entry = found[target]
		if not entry then
			table.insert(report.Missing, target)
		else
			local unit = entry.Info
			local unitReport = {
				Name = target,
				Asset = entry.Asset,
				Rarity = tostring(unit.Rarity or "Unknown"),
				Element = tostring(unit.Element or "Unknown"),
				Class = tostring(unit.Class or "Unknown"),
				Archetype = tostring(unit.Archetype or "Unknown"),
				PlacementLimit = primitive(unit.PlacementLimit),
				Upgrades = {},
			}
			local upgradeIndexes = {}
			for index, upgrade in pairs(type(unit.UpgradeInfo) == "table" and unit.UpgradeInfo or {}) do
				if type(index) == "number" and type(upgrade) == "table" then table.insert(upgradeIndexes, index) end
			end
			table.sort(upgradeIndexes)
			for _, index in ipairs(upgradeIndexes) do
				local upgrade = unit.UpgradeInfo[index]
				table.insert(unitReport.Upgrades, {
					Upgrade = index,
					DisplayName = tostring(upgrade.DisplayName or upgrade.SkillName or "Unknown"),
					SkillName = tostring(upgrade.SkillName or "Unknown"),
					Cost = primitive(upgrade.Cost),
					Farm = primitive(upgrade.Farm),
					AttackType = tostring(upgrade.AttackType or upgrade.HitboxType or "Unknown"),
					HitboxType = tostring(upgrade.HitboxType or "Unknown"),
					HitboxSize = primitive(upgrade.HitboxSize),
					Ticks = primitive(upgrade.Ticks or upgrade.NumberOfAttacks),
					Passives = cleanList(upgrade.Passives),
					Abilities = cleanList(upgrade.Abilities),
					Tags = cleanList(upgrade.Tags),
					Level1 = calculate(upgrade, 1, nil),
					Level50 = calculate(upgrade, 50, nil),
					Level1Unbound = calculate(upgrade, 1, "Unbound"),
					Level50Unbound = calculate(upgrade, 50, "Unbound"),
				})
			end
			table.insert(report.Units, unitReport)
		end
	end

	local function cell(value)
		if value == nil then return "-" end
		if type(value) == "number" then
			local rounded = math.round(value * 10) / 10
			return tostring(rounded)
		end
		return tostring(value):gsub("|", "\\|")
	end

	local function trio(stats)
		return ("%s / %s / %s"):format(cell(stats.Damage), cell(stats.SPA), cell(stats.Range))
	end

	local lines = {
		"# Anime Expeditions new-unit stats",
		"",
		"Clean baselines: no ascension, equipment, stat potential, buffs, or game modifiers.",
		"",
		"Stat cells are `Damage / SPA / Range`. Unbound's dynamic +2% damage per wave (up to +50%) is not included.",
		"",
	}
	for _, unit in ipairs(report.Units) do
		table.insert(lines, "## " .. unit.Name)
		table.insert(lines, "")
		table.insert(lines, ("Internal asset: `%s` | Rarity: %s | Placement cap: %s"):format(unit.Asset, unit.Rarity, cell(unit.PlacementLimit)))
		table.insert(lines, "")
		table.insert(lines, "| Upgrade | Skill | Cost | Level 1 | Level 50 | Level 1 Unbound | Level 50 Unbound |")
		table.insert(lines, "|---:|---|---:|---|---|---|---|")
		for _, upgrade in ipairs(unit.Upgrades) do
			table.insert(lines, ("| %s | %s | %s | %s | %s | %s | %s |"):format(
				cell(upgrade.Upgrade),
				cell(upgrade.DisplayName),
				cell(upgrade.Cost),
				trio(upgrade.Level1),
				trio(upgrade.Level50),
				trio(upgrade.Level1Unbound),
				trio(upgrade.Level50Unbound)
			))
		end
		table.insert(lines, "")
	end
	if #report.Missing > 0 then
		table.insert(lines, "## Missing")
		table.insert(lines, "")
		table.insert(lines, table.concat(report.Missing, ", "))
		table.insert(lines, "")
	end

	local markdown = table.concat(lines, "\n")
	local json = HttpService:JSONEncode(report)
	local root = "AnimeExpeditionsHubData"
	local base = "AnimeExpeditionsHubData/reports"
	if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder(root) then makefolder(root) end
	if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder(base) then makefolder(base) end
	if type(writefile) == "function" then
		writefile(base .. "/new-unit-stats.json", json)
		writefile(base .. "/new-unit-stats.md", markdown)
	end
	if type(setclipboard) == "function" then pcall(setclipboard, markdown) end
	print(markdown)
	print(("[Anime Expeditions] exported %d units to %s"):format(#report.Units, base))
	return report
end, function(message)
	return (debug and debug.traceback and debug.traceback(tostring(message), 2)) or tostring(message)
end)

if not ok then
	warn("[Anime Expeditions] unit stat export failed:\n" .. tostring(result))
	error(result, 0)
end

return result
