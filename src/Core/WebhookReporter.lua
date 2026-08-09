return function(Import)
	local Catalog = Import("AutomationCatalog")
	local WebhookReporter = {}
	WebhookReporter.__index = WebhookReporter
	local HttpService = game:GetService("HttpService")

	local function executorRequest()
		local environment = (getgenv and getgenv()) or _G
		if type(environment.request) == "function" then return environment.request end
		if type(environment.http_request) == "function" then return environment.http_request end
		if type(environment.syn) == "table" and type(environment.syn.request) == "function" then return environment.syn.request end
		if type(environment.fluxus) == "table" and type(environment.fluxus.request) == "function" then return environment.fluxus.request end
		return nil
	end

	local function validUrl(url)
		url = tostring(url or "")
		return string.match(url, "^https://discord%.com/api/webhooks/%d+/[%w_%-]+")
			or string.match(url, "^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+")
			or string.match(url, "^https://canary%.discord%.com/api/webhooks/%d+/[%w_%-]+")
			or string.match(url, "^https://ptb%.discord%.com/api/webhooks/%d+/[%w_%-]+")
	end

	local function formatNumber(value)
		local text = tostring(math.floor(tonumber(value) or 0))
		local sign, digits = string.match(text, "^([%-]?)(%d+)$")
		if not digits then return text end
		local output = digits
		while true do
			local replaced, count = string.gsub(output, "^(%d+)(%d%d%d)", "%1,%2")
			output = replaced
			if count == 0 then break end
		end
		return sign .. output
	end

	local function formatTime(seconds)
		seconds = math.max(0, math.floor(tonumber(seconds) or 0))
		return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
	end

	local function truncate(value, limit)
		value = tostring(value or "")
		if #value <= limit then return value end
		return string.sub(value, 1, limit - 3) .. "..."
	end

	local function mapName(information, result)
		local maps = type(information) == "table" and information.Maps or nil
		local preview = type(maps) == "table" and maps.PreviewInfo or nil
		local info = type(preview) == "table" and preview[result.MapName] or nil
		return tostring(type(info) == "table" and (info.DisplayName or info.Name) or result.MapName or "Unknown Map")
	end

	local function imageUrl(information, result)
		local maps = type(information) == "table" and information.Maps or nil
		local preview = type(maps) == "table" and maps.PreviewInfo or nil
		local info = type(preview) == "table" and preview[result.MapName] or nil
		local source = type(info) == "table" and (info.PreviewImage or info.PreviewArt) or nil
		local assetId = source and string.match(tostring(source), "(%d+)") or nil
		if not assetId then return nil end
		return "https://www.roblox.com/asset-thumbnail/image?assetId=" .. assetId .. "&width=768&height=432&format=png"
	end

	local function firstPopulated(...)
		local values = table.pack(...)
		for index = 1, values.n do
			local candidate = values[index]
			if type(candidate) == "table" and next(candidate) then
				return candidate
			end
		end
		return {}
	end

	local function rewardEntries(result)
		result = type(result) == "table" and result or {}
		local source = firstPopulated(result.Rewards, result.GainedRewards, result.RewardData, result.Drops)
		local output = {}
		for key, reward in pairs(type(source) == "table" and source or {}) do
			if type(reward) == "table" then
				local asset = reward.Asset or reward.Item or reward.ID or reward.Id
				if asset == nil and type(key) ~= "number" then
					asset = key
				end
				if asset ~= nil then
					table.insert(output, {
						Asset = asset,
						Amount = tonumber(reward.Amount or reward.Quantity or reward.Count or reward.Value) or 1,
						Data = reward.Data or reward,
					})
				end
			elseif type(key) ~= "number" and tonumber(reward) then
				table.insert(output, { Asset = key, Amount = tonumber(reward) })
			end
		end
		return output
	end

	local function rewardLines(information, playerData, result)
		local totals, order = {}, {}
		for _, reward in ipairs(rewardEntries(result)) do
			if type(reward) == "table" and reward.Asset then
				local asset = tostring(reward.Asset)
				if not totals[asset] then totals[asset] = 0 table.insert(order, asset) end
				totals[asset] = totals[asset] + (tonumber(reward.Amount) or 1)
			end
		end
		local output = {}
		for _, asset in ipairs(order) do
			local total = Catalog.OwnedAmount(playerData, information, asset)
			if asset == "PlayerEXP" then total = tonumber(playerData.Exp) or 0 end
			if asset == "UnitEXP" then total = 0 end
			table.insert(output, string.format("+[%s] %s - Total: [%s]", formatNumber(totals[asset]), Catalog.AssetName(information, asset), formatNumber(total)))
		end
		return #output > 0 and table.concat(output, "\n") or "No rewards"
	end

	local function unitLines(information, playerData, result, hotbar)
		local equipped = firstPopulated(
			result.GainedUnitExp,
			result.EquippedUnits,
			type(hotbar) == "table" and hotbar.Slots or nil,
			hotbar
		)
		local slots = {}
		for slot in pairs(equipped) do table.insert(slots, slot) end
		table.sort(slots, function(a, b) return (tonumber(a) or math.huge) < (tonumber(b) or math.huge) end)
		local units = type(playerData) == "table" and (playerData.UnitData or playerData.Units) or nil
		local output = {}
		local seen = {}
		for _, slot in ipairs(slots) do
			local entry = equipped[slot]
			local id = type(entry) == "table"
				and (entry.UnitID or entry.ProfileUnitID or entry.ID or entry.Id)
				or entry
			local unit = type(units) == "table" and (units[id] or units[tostring(id)]) or nil
			if type(unit) ~= "table" and type(entry) == "table" then
				unit = entry.UnitData or entry.Profile or entry.Unit
			end
			if type(unit) ~= "table" and type(entry) == "table" and entry.Asset then
				unit = entry
			end
			if type(unit) == "table" then
				local name = Catalog.UnitName(information, unit)
				local trait = Catalog.TraitName(information, unit.Trait)
				local suffix = trait ~= "None" and " (" .. trait .. ")" or ""
				local signature = tostring(id or unit.Asset or name)
				if not seen[signature] then
					seen[signature] = true
					table.insert(output, string.format("[%d] - %s%s", math.max(1, math.floor(tonumber(unit.Level) or 1)), name, suffix))
				end
			end
		end
		return #output > 0 and table.concat(output, "\n") or "No equipped unit data"
	end

	local function playerStats(information, playerData)
		local entries = {
			{"Gold", "Gold"},
			{"Gems", "Gem"},
			{"Trait Crystal", "TraitReroll"},
			{"Equipment Reroll", "EquipmentReroll"},
		}
		local output = {}
		for _, entry in ipairs(entries) do
			table.insert(output, entry[1] .. ": " .. formatNumber(Catalog.OwnedAmount(playerData, information, entry[2])))
		end
		return table.concat(output, "\n")
	end

	function WebhookReporter.new(player, gameAdapter)
		return setmetatable({Player = player, Game = gameAdapter}, WebhookReporter)
	end

	function WebhookReporter:Post(url, payload)
		if not validUrl(url) then return false, "Enter a valid Discord webhook URL." end
		local request = executorRequest()
		if not request then return false, "This executor does not provide an HTTP request function." end
		local ok, response = pcall(request, {
			Url = tostring(url),
			Method = "POST",
			Headers = {["Content-Type"] = "application/json"},
			Body = HttpService:JSONEncode(payload),
		})
		if not ok then return false, "HTTP request failed: " .. tostring(response) end
		local status = tonumber(type(response) == "table" and (response.StatusCode or response.Status)) or 0
		if status < 200 or status >= 300 then return false, "Discord returned HTTP " .. tostring(status) end
		return true
	end

	function WebhookReporter:Mentions(state, result, information)
		local filtered = next(state.PingDrops) ~= nil or state.EquipmentRarity ~= "None"
		local matched = not filtered
		for _, reward in ipairs(rewardEntries(result)) do
			if type(reward) == "table" and state.PingDrops[tostring(reward.Asset)] then matched = true end
			if type(reward) == "table" and state.EquipmentRarity ~= "None"
				and Catalog.AssetType(information, reward.Asset) == "Equipment"
				and Catalog.AssetRarity(information, reward.Asset, reward.Data) == state.EquipmentRarity then matched = true end
		end
		if not matched then return "", {parse = {}, users = {}} end
		local parts, users = {}, {}
		if state.MentionEveryone then table.insert(parts, "@everyone") end
		local userId = string.match(tostring(state.DiscordUserId or ""), "(%d+)")
		if userId then table.insert(parts, "<@" .. userId .. ">") table.insert(users, userId) end
		return table.concat(parts, " "), {parse = state.MentionEveryone and {"everyone"} or {}, users = users}
	end

	function WebhookReporter:MatchPayload(state, result, runs)
		local information = self.Game:Information() or {}
		local playerData = self.Game:PlayerData() or {}
		local hotbar = type(self.Game.HotbarData) == "function" and self.Game:HotbarData() or {}
		local mentions, allowed = self:Mentions(state, result, information)
		local map = mapName(information, result)
		local mapLine = string.format("%s - %s - %s\n**Difficulty:** %s\n**Result:** %s\n**Time:** %s\n**Runs:** %d",
			map, tostring(result.ActName or "Unknown Act"), tostring(result.Gamemode or "Unknown"),
			tostring(result.Difficulty or "Unknown"), result.Victory == true and "Victory" or "Defeat",
			formatTime(result.TotalTime), tonumber(runs) or 1)
		local description = table.concat({
			"**User:** ||" .. tostring(self.Player.Name) .. "||",
			"**Level:** " .. formatNumber(playerData.Level),
			"",
			"**Player Stats**",
			playerStats(information, playerData),
			"",
			"**Units**",
			unitLines(information, playerData, result, hotbar),
			"",
			"**Rewards**",
			rewardLines(information, playerData, result),
			"",
			"**Map**",
			mapLine,
		}, "\n")
		local embed = {
			title = "Anime Expedition",
			description = truncate(description, 4096),
			color = result.Victory == true and 5763719 or 15548997,
			footer = {text = "discord.gg/V3WcdHpd3J"},
			timestamp = DateTime.now():ToIsoDate(),
		}
		local image = imageUrl(information, result)
		if image then embed.thumbnail = {url = image} end
		return {username = "Anime Expedition", content = mentions, allowed_mentions = allowed, embeds = {embed}}
	end

	function WebhookReporter:TestPayload()
		return {
			username = "Anime Expedition",
			embeds = {{title = "Webhook Test", description = "Your Anime Expedition webhook is working.", color = 5763719, footer = {text = "discord.gg/V3WcdHpd3J"}, timestamp = DateTime.now():ToIsoDate()}},
		}
	end

	function WebhookReporter:BountyPayload(questName, questData)
		local rarity = type(questData) == "table" and (questData.Rarity or questData.Tier) or nil
		return {
			username = "Anime Expedition",
			embeds = {{title = "Bounty Completed", description = "User: ||" .. tostring(self.Player.Name) .. "||\n\nBounty: " .. tostring(questName) .. "\nRarity: " .. tostring(rarity or "Unknown"), color = 16766720, footer = {text = "discord.gg/V3WcdHpd3J"}, timestamp = DateTime.now():ToIsoDate()}},
		}
	end

	return WebhookReporter
end
