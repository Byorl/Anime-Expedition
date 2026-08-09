return function(Import)
	local Util = Import("Util")
	local Catalog = Import("AutomationCatalog")
	local BountyCatalog = Import("BountyCatalog")
	local Bounty = {}

	local function selected(value, resolver)
		local output = {}
		for key, enabled in pairs(type(value) == "table" and value or {}) do
			local item = type(key) == "number" and enabled or enabled == true and key or nil
			if item ~= nil then
				item = resolver and resolver(item) or item
				if item ~= nil and tostring(item) ~= "" then output[tostring(item)] = true end
			end
		end
		return output
	end

	local function selectedList(value, resolver)
		local output = {}
		for key in pairs(type(value) == "table" and value or {}) do
			local item = resolver and resolver(key) or key
			if item ~= nil then table.insert(output, tostring(item)) end
		end
		table.sort(output)
		return output
	end

	local function replace(state, signatureKey, control, options, selection)
		if not control then return end
		local signature = table.concat(options, "\0")
		if state[signatureKey] == signature then return end
		local restoreIdentity = Util.ElevateIdentity()
		local ok, err = xpcall(function()
			control:ClearOptions()
			control:InsertOptions(#options > 0 and options or {"Unavailable"})
			if selection and #selection > 0 then control:UpdateSelection(selection) end
		end, Util.Traceback)
		restoreIdentity()
		if ok then
			state[signatureKey] = signature
		else
			Util.Warn("bounty dropdown refresh: " .. tostring(err))
		end
	end

	local function updateLabel(label, text, name)
		if label and label[name or "_Never"] ~= text then
			label[name or "_Never"] = text
			Util.SafeCall("bounty label", label.UpdateName, label, text)
		end
	end

	function Bounty:_Status(state, message)
		message = tostring(message or "Idle.")
		if state.Status == message then return end
		state.Status = message
		if state.StatusLabel then Util.SafeCall("bounty status", state.StatusLabel.UpdateName, state.StatusLabel, message) end
	end

	function Bounty:_QuestData(ctx)
		local deepState
		if type(ctx.Game.StateDeep) == "function" then
			local ok, result = pcall(ctx.Game.StateDeep, ctx.Game, "QuestData", 6)
			if ok then deepState = result end
		end
		local shallowState = ctx.Game:State("QuestData")
		local playerData = ctx.Game:PlayerData()
		local current = BountyCatalog.ResolveQuestData(deepState, shallowState, playerData)
		local category = BountyCatalog.Category(current)
		if next(type(category.Quests) == "table" and category.Quests or {}) ~= nil then return current end
		local deepPlayer
		if type(ctx.Game.StateDeep) == "function" then
			local ok, result = pcall(ctx.Game.StateDeep, ctx.Game, "PlayerData", 8)
			if ok then deepPlayer = result end
		end
		return BountyCatalog.ResolveQuestData(current, deepPlayer)
	end

	function Bounty:_Read(ctx, state)
		local information = ctx.Game:Information() or {}
		local questData = self:_QuestData(ctx)
		local gameData
		if type(ctx.Game.StateDeep) == "function" then
			local ok, result = pcall(ctx.Game.StateDeep, ctx.Game, "GameState", 6)
			if ok then gameData = result end
		end
		local thisMap, boardText, entries = BountyCatalog.BoardText(information, questData, gameData)
		state.Entries = entries
		state.Information = information
		state.QuestData = questData
		state.GameData = gameData
		local present = {}
		for _, entry in ipairs(entries) do present[entry.Key] = entry end
		if state.PendingRerollKey and not present[state.PendingRerollKey] then state.PendingRerollKey = nil end
		if state.PendingClaimKey and (not present[state.PendingClaimKey] or present[state.PendingClaimKey].Claimed) then state.PendingClaimKey = nil end
		updateLabel(state.ThisMapLabel, thisMap, "_BountyText")
		updateLabel(state.BoardLabel, boardText, "_BountyText")
		local rarities, types = BountyCatalog.Options(entries, information)
		replace(state, "RaritySignature", state.RarityControl, rarities, selectedList(state.KeepRarities))
		replace(state, "KeepTypeSignature", state.KeepTypeControl, types, selectedList(state.KeepTypes))
		replace(state, "AvoidTypeSignature", state.AvoidTypeControl, types, selectedList(state.AvoidTypes))
		local banners = Catalog.Banners(ctx.Game:State("BannerData"), information)
		state.BannerCatalog = banners
		for key in pairs(state.Banners) do if not banners.ByKey[key] then state.Banners[key] = nil end end
		local selectedLabels = selectedList(state.Banners, function(key) return banners.ByKey[key] end)
		replace(state, "BannerSignature", state.BannerControl, banners.Options, selectedLabels)
		return entries
	end

	local function claimCandidate(entries)
		for _, entry in ipairs(type(entries) == "table" and entries or {}) do
			if entry.Completed and not entry.Claimed then return entry end
		end
		return nil
	end

	function Bounty:_Claim(ctx, state)
		if not state.AutoClaim or os.clock() - state.LastClaimAt < 1 then return false end
		local entry = claimCandidate(state.Entries)
		if not entry then return false end
		if state.PendingClaimKey == entry.Key and os.clock() - state.PendingClaimAt < 5 then return true end
		state.LastClaimAt = os.clock()
		state.PendingClaimKey = entry.Key
		state.PendingClaimAt = os.clock()
		self:_Status(state, "Claiming " .. entry.Name .. "...")
		local ok, err = ctx.Game:Fire("QUEST_CLAIM", "BountyBoard", entry.Key)
		if not ok then state.PendingClaimKey = nil self:_Status(state, "Claim failed: " .. tostring(err)) end
		return true
	end

	local function rerollCandidate(state)
		local eligible = {}
		for _, entry in ipairs(state.Entries) do
			if not entry.Completed and not entry.Claimed and BountyCatalog.Keep(entry, state.KeepRarities, state.KeepTypes, state.AvoidTypes) then
				table.insert(eligible, entry)
			end
		end
		local stack = state.StackEnabled and BountyCatalog.StackTarget(eligible) or nil
		local stackIncomplete = stack and stack.Count < state.StackCount
		for _, entry in ipairs(state.Entries) do
			if not entry.Completed and not entry.Claimed then
				local keep, reason = BountyCatalog.Keep(entry, state.KeepRarities, state.KeepTypes, state.AvoidTypes)
				if not keep then return entry, reason end
				if stackIncomplete and not BountyCatalog.HasTarget(entry, stack.Target) then
					return entry, "does not match the active stack"
				end
			end
		end
		return nil
	end

	function Bounty:_Reroll(ctx, state)
		if not state.AutoReroll or ctx.Game:IsInGame() or os.clock() - state.LastRerollAt < 1.25 then return false end
		local entry, reason = rerollCandidate(state)
		if not entry then return false end
		if state.PendingRerollKey == entry.Key and os.clock() - state.PendingRerollAt < 6 then return true end
		local playerData = ctx.Game:PlayerData()
		local gold = Catalog.OwnedAmount(playerData, state.Information, "Gold")
		if gold < 1000 then self:_Status(state, "Waiting for 1,000 Gold to reroll.") return true end
		state.LastRerollAt = os.clock()
		state.PendingRerollKey = entry.Key
		state.PendingRerollAt = os.clock()
		self:_Status(state, string.format("Rerolling %s (%s)...", entry.Rarity, reason))
		local ok, err = ctx.Game:Fire("BOUNTY_BOARD_REROLL_QUEST", entry.Key, entry.Rarity == "Mythic")
		if not ok then state.PendingRerollKey = nil self:_Status(state, "Reroll failed: " .. tostring(err)) end
		return true
	end

	local function summonRemaining(entries)
		local remaining = 0
		for _, entry in ipairs(type(entries) == "table" and entries or {}) do
			if not entry.Completed and not entry.Claimed then
				for _, objective in ipairs(entry.Objectives) do
					if objective.Type == "Summon" and not objective.Completed then
						remaining = remaining + math.max(0, objective.Goal - objective.Progress)
					end
				end
			end
		end
		return remaining
	end

	function Bounty:_Summon(ctx, state)
		if not state.AutoSummon or ctx.Game:IsInGame() or os.clock() - state.LastSummonAt < 0.75 then return false end
		local remaining = summonRemaining(state.Entries)
		if remaining <= 0 then return false end
		if state.PendingSummonRemaining and remaining >= state.PendingSummonRemaining and os.clock() - state.PendingSummonAt < 4 then return true end
		state.PendingSummonRemaining = nil
		if ctx.Registry:Get("auto_summon.enabled") == true then
			self:_Status(state, "Waiting: Auto Summon currently controls summoning.")
			return true
		end
		local choices = selectedList(state.Banners)
		if #choices == 0 then self:_Status(state, "Select at least one bounty banner.") return true end
		state.BannerCursor = state.BannerCursor % #choices + 1
		local key = choices[state.BannerCursor]
		local bannerData = ctx.Game:State("BannerData")
		local current = type(bannerData) == "table" and bannerData[key] or nil
		local info = type(current) == "table" and current.BannerInfo or nil
		if type(info) ~= "table" or info.Hidden == true then return false end
		local playerData = ctx.Game:PlayerData()
		local currency = tostring(info.Currency or "Gem")
		local cost = math.max(1, tonumber(info.Cost) or 1)
		local owned = Catalog.OwnedAmount(playerData, state.Information, currency)
		local amount = math.min(50, remaining, math.floor(owned / cost))
		if amount < 1 then self:_Status(state, "Waiting for " .. currency .. " to summon.") return true end
		state.LastSummonAt = os.clock()
		state.PendingSummonRemaining = remaining
		state.PendingSummonAt = os.clock()
		self:_Status(state, string.format("Summoning %d for bounty progress...", amount))
		local ok, err = ctx.Game:Fire("BANNER_SUMMON", key, amount)
		if not ok then state.PendingSummonRemaining = nil self:_Status(state, "Bounty summon failed: " .. tostring(err)) end
		return true
	end

	local function completionSnapshot(entries, queue)
		local output = {}
		for _, entry in ipairs(type(entries) == "table" and entries or {}) do
			for _, objective in ipairs(entry.Objectives) do
				if BountyCatalog.MatchesQueue(objective, queue) then
					output[entry.Key .. "|" .. objective.Key] = objective.Completed == true
				end
			end
		end
		return output
	end

	function Bounty:_AutoLeave(ctx, state)
		if not state.AutoLeave or not ctx.Game:IsInGame() then
			state.MapCompletion = nil
			state.PendingLeave = false
			return false
		end
		local queue = BountyCatalog.CurrentQueue(state.GameData)
		if not queue then return false end
		local current = completionSnapshot(state.Entries, queue)
		if not state.MapCompletion then state.MapCompletion = current return false end
		for key, complete in pairs(current) do
			if complete and state.MapCompletion[key] == false then state.PendingLeave = true end
		end
		state.MapCompletion = current
		if not state.PendingLeave or os.clock() - state.LastLeaveAt < 5 then return false end
		if ctx.Game:IsMatchEnded(state.GameData) then
			local ready = ctx.Results:DeliveryState(ctx.Results.Revision, 15, 1.25)
			if not ready then self:_Status(state, "Bounty complete; waiting for webhook delivery...") return true end
		end
		state.LastLeaveAt = os.clock()
		self:_Status(state, "Bounty objective complete; returning to the lobby...")
		local ok, err = ctx.Game:ReturnToLobby()
		if ok then state.PendingLeave = false else self:_Status(state, "Bounty leave failed: " .. tostring(err)) end
		return true
	end

	function Bounty:_Tick(ctx, state)
		if os.clock() - state.LastRefreshAt >= 0.75 then
			state.LastRefreshAt = os.clock()
			self:_Read(ctx, state)
		end
		if self:_AutoLeave(ctx, state) then return end
		if self:_Claim(ctx, state) then return end
		if self:_Reroll(ctx, state) then return end
		if self:_Summon(ctx, state) then return end
		if state.AutoReroll or state.AutoClaim or state.AutoSummon or state.JoinEnabled or state.AutoLeave then
			self:_Status(state, "Monitoring bounties.")
		else self:_Status(state, "Idle.") end
	end

	return {
		Name = "Bounty",
		Version = 2,
		Priority = 18,
		Dependencies = {},

		Init = function(self, ctx)
			local state = {
				Alive = true,
				Status = "Idle.",
				Entries = {},
				KeepRarities = {},
				KeepTypes = {},
				AvoidTypes = {},
				Banners = {},
				BannerCatalog = {Options = {}, ByKey = {}, ByLabel = {}},
				BannerCursor = 0,
				AutoReroll = false,
				AutoClaim = false,
				AutoSummon = false,
				StackEnabled = false,
				StackCount = 2,
				JoinEnabled = false,
				AutoLeave = false,
				Matchmaking = false,
				Delay = 1,
				LastRefreshAt = -math.huge,
				LastClaimAt = -math.huge,
				LastRerollAt = -math.huge,
				LastSummonAt = -math.huge,
				LastLeaveAt = -math.huge,
				PendingRerollAt = -math.huge,
				PendingClaimAt = -math.huge,
				PendingSummonAt = -math.huge,
			}
			local reroll = ctx.Tabs.MiscBounty:Section({Side = "Left"})
			local summon = ctx.Tabs.MiscBounty:Section({Side = "Left"})
			local travel = ctx.Tabs.MiscBounty:Section({Side = "Right"})
			local board = ctx.Tabs.MiscBounty:Section({Side = "Right"})
			reroll:Header({Text = "Bounty Automation"})
			reroll:Header({Text = "Status"})
			state.StatusLabel = reroll:Label({Text = "Idle."})
			ctx.Registry:Toggle(reroll, {Name = "Auto Reroll Bounty", Default = false, Callback = function(value) state.AutoReroll = value == true end}, "bounty.auto_reroll")
			reroll:Header({Text = "Keep Rarities"})
			state.RarityControl = ctx.Registry:Dropdown(reroll, {
				Name = "Rarity", Search = true, Multi = true, Required = false,
				Options = {"Mythic", "Legendary", "Epic", "Rare"}, Default = {},
				Callback = function(value) state.KeepRarities = selected(value) end,
			}, "bounty.keep_rarities")
			reroll:Header({Text = "Keep Types"})
			state.KeepTypeControl = ctx.Registry:Dropdown(reroll, {
				Name = "What types to keep", Search = true, Multi = true, Required = false,
				Options = {"Infinite Waves", "Story Clears", "Raid Clears", "Challenge Clears", "Summons", "Boss Takedowns"}, Default = {},
				Callback = function(value) state.KeepTypes = selected(value) end,
			}, "bounty.keep_types")
			reroll:Header({Text = "Avoid Types"})
			state.AvoidTypeControl = ctx.Registry:Dropdown(reroll, {
				Name = "What types to reroll", Search = true, Multi = true, Required = false,
				Options = {"Infinite Waves", "Story Clears", "Raid Clears", "Challenge Clears", "Summons", "Boss Takedowns"}, Default = {},
				Callback = function(value) state.AvoidTypes = selected(value) end,
			}, "bounty.avoid_types")
			ctx.Registry:Toggle(reroll, {Name = "Stack Bounties on One Map", Default = false, Callback = function(value) state.StackEnabled = value == true end}, "bounty.stack")
			ctx.Registry:Slider(reroll, {
				Name = "Bounties to Stack", Default = 2, Minimum = 2, Maximum = 5, Precision = 0, Step = 1,
				Callback = function(value) state.StackCount = math.floor(tonumber(value) or 2) end,
			}, "bounty.stack_count")
			ctx.Registry:Toggle(reroll, {Name = "Auto Claim Bounty", Default = false, Callback = function(value) state.AutoClaim = value == true end}, "bounty.auto_claim")

			summon:Header({Text = "Bounty Summoning"})
			ctx.Registry:Toggle(summon, {Name = "Auto Summon Bounty", Default = false, Callback = function(value) state.AutoSummon = value == true end}, "bounty.auto_summon")
			state.BannerControl = ctx.Registry:Dropdown(summon, {
				Name = "Banner", Search = true, Multi = true, Required = false, Options = {"No banners available"}, Default = {},
				ResolveValue = function(value)
					local key = Catalog.ExtractBracketKey(value)
					return state.BannerCatalog.ByKey[tostring(key)] or value
				end,
				Callback = function(value)
					state.Banners = selected(value, function(label)
						return state.BannerCatalog.ByLabel[tostring(label)] or Catalog.ExtractBracketKey(label)
					end)
				end,
			}, "bounty.banners")
			summon:Button({Name = "Refresh Banners", Callback = function()
				state.LastRefreshAt = -math.huge
				task.defer(function()
					local ok, err = xpcall(function() Bounty:_Read(ctx, state) end, Util.Traceback)
					if not ok then Bounty:_Status(state, "Bounty refresh failed: " .. tostring(err)) end
				end)
			end})

			travel:Header({Text = "Bounty Travel"})
			ctx.Registry:Toggle(travel, {Name = "Auto Join Bounty Map", Default = false, Callback = function(value) state.JoinEnabled = value == true end}, "bounty.auto_join")
			ctx.Registry:Toggle(travel, {Name = "Auto Leave Bounty Map", Default = false, Callback = function(value) state.AutoLeave = value == true if not value then state.PendingLeave = false state.MapCompletion = nil end end}, "bounty.auto_leave")
			ctx.Registry:Toggle(travel, {Name = "Use Matchmaking", Default = false, Callback = function(value) state.Matchmaking = value == true end}, "bounty.matchmaking")
			ctx.Registry:Slider(travel, {
				Name = "Auto Join Delay (s)", Default = 1, Minimum = 1, Maximum = 10, Precision = 0, Step = 1,
				Callback = function(value) state.Delay = math.floor(tonumber(value) or 1) end,
			}, "bounty.delay")

			board:Header({Text = "This Map"})
			state.ThisMapLabel = board:Label({Text = "Not currently in a bounty map."})
			board:Divider()
			board:Header({Text = "Board"})
			state.BoardLabel = board:Label({Text = "Claims used today: 0/10\n0 bounty(s)"})
			ctx:RegisterCleanup(ctx.Join:Register("Bounty", 100, function()
				if not state.JoinEnabled then return nil end
				local information = ctx.Game:Information() or {}
				local playerData = ctx.Game:PlayerData()
				if type(playerData) ~= "table" then return nil end
				local entries = BountyCatalog.Entries(information, Bounty:_QuestData(ctx))
				if state.AutoClaim and claimCandidate(entries) then return nil end
				if state.AutoReroll then
					local currentEntries = state.Entries
					state.Entries = entries
					local needsReroll = rerollCandidate(state) ~= nil
					state.Entries = currentEntries
					if needsReroll then return nil end
				end
				if state.AutoSummon and summonRemaining(entries) > 0 then return nil end
				local stack = state.StackEnabled and BountyCatalog.StackTarget(entries) or nil
				local target = stack and stack.Count >= 2 and stack.Target or nil
				local candidate = BountyCatalog.JoinCandidate(information, playerData, ctx.Game:State("ChallengeData"), entries, target)
				if not candidate and target then
					candidate = BountyCatalog.JoinCandidate(information, playerData, ctx.Game:State("ChallengeData"), entries)
				end
				if not candidate then return nil end
				return {Queue = candidate.Queue, Matchmaking = state.Matchmaking, Delay = state.Delay}
			end))
			local worker = task.defer(function()
				while state.Alive and ctx.Runtime.Alive do
					local ok, err = xpcall(function() Bounty:_Tick(ctx, state) end, Util.Traceback)
					if not ok then Bounty:_Status(state, "Bounty error: " .. tostring(err)) task.wait(1) end
					task.wait(0.2)
				end
			end)
			ctx:RegisterCleanup(worker)
			ctx:RegisterCleanup(function() state.Alive = false end)
			return state
		end,

		Disable = function(self, ctx, state)
			state.Alive = false
			state.AutoReroll = false
			state.AutoClaim = false
			state.AutoSummon = false
			state.JoinEnabled = false
			state.AutoLeave = false
		end,
	}
end
