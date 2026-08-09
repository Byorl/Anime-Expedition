return function(Import)
	local Catalog = Import("AutomationCatalog")
	local JoinCatalog = Import("JoinCatalog")
	local Webhook = {}

	local function selectedAssets(value, drops)
		local output = {}
		for label, selected in pairs(type(value) == "table" and value or {}) do
			if selected == true then
				local asset = drops.ByLabel[label] or string.match(tostring(label), "%[([^%]]+)%]$")
				if asset then
					output[asset] = true
				end
			end
		end
		return output
	end

	local function refreshDrops(ctx, state)
		local drops = JoinCatalog.ChallengeDrops(ctx.Game:Information() or {}, ctx.Game:State("ChallengeData"))
		local options = {}
		for _, option in ipairs(drops.Options) do
			if option ~= "Any drop" then
				table.insert(options, option)
			end
		end
		local labels = {}
		for asset in pairs(state.PingDrops) do
			if drops.ByKey[asset] then
				table.insert(labels, drops.ByKey[asset])
			end
		end
		table.sort(labels)
		local signature = table.concat(options, "\0")
		state.Drops = drops
		if signature == state.DropSignature or not state.DropControl then
			return
		end
		state.DropSignature = signature
		state.RefreshingDrops = true
		state.DropControl:ClearOptions()
		state.DropControl:InsertOptions(options)
		state.DropControl:UpdateSelection(labels)
		state.RefreshingDrops = false
	end

	local function bountyEntries(ctx)
		local questData = ctx.Game:State("QuestData")
		local category = type(questData) == "table" and questData.BountyBoard or nil
		return type(category) == "table" and category.Quests or {}
	end

	local function bountyInfo(ctx, key)
		local information = ctx.Game:Information() or {}
		local quests = type(information.Quests) == "table" and information.Quests.Quests or nil
		local category = type(quests) == "table" and quests.BountyBoard or nil
		return type(category) == "table" and category[key] or nil
	end

	return {
		Name = "Webhook",
		Version = 4,
		Priority = 9,
		Dependencies = {},

		Init = function(self, ctx)
			local drops = JoinCatalog.ChallengeDrops(ctx.Game:Information() or {}, ctx.Game:State("ChallengeData"))
			local options = {}
			for _, option in ipairs(drops.Options) do
				if option ~= "Any drop" then
					table.insert(options, option)
				end
			end
			local state = {
				Alive = true,
				SendMatch = false,
				SendBounty = false,
				Url = "",
				MentionEveryone = false,
				DiscordUserId = "",
				PingDrops = {},
				EquipmentRarity = "None",
				Drops = drops,
				SeenBounties = {},
			}
			local delivery = ctx.Tabs.Webhook:Section({ Side = "Left" })
			delivery:Header({ Text = "Delivery" })
			ctx.Registry:Toggle(delivery, {
				Name = "Send On Match End",
				Default = false,
				Callback = function(value)
					state.SendMatch = value == true
				end,
			}, "webhook.send_match")
			ctx.Registry:Toggle(delivery, {
				Name = "Send Bounty Webhook",
				Default = false,
				Callback = function(value)
					state.SendBounty = value == true
				end,
			}, "webhook.send_bounty")
			local destination = ctx.Tabs.Webhook:Section({ Side = "Left" })
			destination:Header({ Text = "Webhook Destination" })
			ctx.Registry:Input(destination, {
				Name = "Webhook",
				Placeholder = "https://discord.com/api/webhooks/...",
				Default = "",
				onChanged = function(value)
					state.Url = tostring(value)
				end,
			}, "webhook.url")
			destination:Button({
				Name = "Send Test",
				Callback = function()
					local ok, err = ctx.Webhook:Post(state.Url, ctx.Webhook:TestPayload())
					if ok then
						ctx.Runtime:Notify("Webhook", "Test webhook sent.")
					else
						ctx.Runtime:Notify("Webhook", tostring(err))
					end
				end,
			})

			local mentions = ctx.Tabs.Webhook:Section({ Side = "Right" })
			mentions:Header({ Text = "Mentions" })
			ctx.Registry:Toggle(mentions, {
				Name = "Mention Everyone",
				Default = false,
				Callback = function(value)
					state.MentionEveryone = value == true
				end,
			}, "webhook.mention_everyone")
			ctx.Registry:Input(mentions, {
				Name = "Discord User ID",
				Placeholder = "938129321 or <@938129321>",
				Default = "",
				onChanged = function(value)
					state.DiscordUserId = tostring(value)
				end,
			}, "webhook.discord_user_id")
			local alerts = ctx.Tabs.Webhook:Section({ Side = "Right" })
			alerts:Header({ Text = "Drop Alerts" })
			state.DropControl = ctx.Registry:Dropdown(alerts, {
				Name = "Ping on Drop",
				Search = true,
				Multi = true,
				Required = false,
				Options = options,
				Default = {},
				ResolveValue = function(value)
					return state.Drops.ByKey[tostring(value)] or value
				end,
				Callback = function(value)
					if not state.RefreshingDrops then
						state.PingDrops = selectedAssets(value, state.Drops)
					end
				end,
			}, "webhook.ping_drops")
			local rarities = Catalog.AllRarities(ctx.Game:Information() or {})
			ctx.Registry:Dropdown(alerts, {
				Name = "Ping on Equipment Rarity",
				Search = true,
				Multi = false,
				Required = true,
				Options = rarities,
				Default = 1,
				Callback = function(value)
					state.EquipmentRarity = tostring(value or "None")
				end,
			}, "webhook.equipment_rarity")

			ctx:RegisterCleanup(ctx.Results:Subscribe("Webhook", function(result, runs, revision, complete)
				complete = complete or ctx.Results:BeginDelivery("Webhook", revision)
				if not state.SendMatch or state.Url == "" then
					complete(false)
					return
				end
				local payloadOk, payload = xpcall(function()
					return ctx.Webhook:MatchPayload(state, result, runs)
				end, debug.traceback)
				if not payloadOk then
					complete(false)
					ctx.Runtime:Notify("Webhook", "Payload creation failed: " .. tostring(payload))
					return
				end
				task.spawn(function()
					local requestOk, ok, err = xpcall(function()
						return ctx.Webhook:Post(state.Url, payload)
					end, debug.traceback)
					complete(requestOk and ok == true)
					if not requestOk then
						ctx.Runtime:Notify("Webhook", "Delivery failed: " .. tostring(ok))
					elseif not ok then
						ctx.Runtime:Notify("Webhook", tostring(err))
					end
				end)
			end, true))

			for key, entry in pairs(bountyEntries(ctx)) do
				state.SeenBounties[tostring(key)] = type(entry) == "table" and entry.Completed == true
			end
			local worker = task.spawn(function()
				local lastRefresh = 0
				while state.Alive and ctx.Runtime.Alive do
					if os.clock() - lastRefresh >= 10 then
						lastRefresh = os.clock()
						refreshDrops(ctx, state)
					end
					local entries = bountyEntries(ctx)
					for key, entry in pairs(entries) do
						key = tostring(key)
						local completed = type(entry) == "table" and entry.Completed == true
						if state.SendBounty and completed and state.SeenBounties[key] ~= true and state.Url ~= "" then
							local info = bountyInfo(ctx, key) or entry
							local name = type(info) == "table" and (info.DisplayName or info.Name) or key
							local ok, err = ctx.Webhook:Post(state.Url, ctx.Webhook:BountyPayload(name, info))
							if not ok then
								ctx.Runtime:Notify("Bounty Webhook", tostring(err))
							end
						end
						state.SeenBounties[key] = completed
					end
					task.wait(1)
				end
			end)
			ctx:RegisterCleanup(worker)
			ctx:RegisterCleanup(function()
				state.Alive = false
			end)
			return state
		end,

		Disable = function(self, ctx, state)
			state.Alive = false
		end,
	}
end
