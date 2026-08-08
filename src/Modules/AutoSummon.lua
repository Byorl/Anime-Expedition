return function(Import)
	local Util = Import("Util")
	local Catalog = Import("AutomationCatalog")
	local AutoSummon = {}

	local IDLE_INTERVAL = 0.1
	local RESULT_TIMEOUT = 5

	function AutoSummon:_Status(state, message)
		state.Status = tostring(message or "Idle.")
		if state.StatusLabel then
			Util.SafeCall("auto summon status", state.StatusLabel.UpdateName, state.StatusLabel, state.Status)
		end
	end

	function AutoSummon:_Stop(state, message)
		state.Enabled = false
		state.SuppressIdleOnce = true
		self:_Status(state, message)
		if state.Toggle then task.defer(function() state.Toggle:UpdateState(false) end) end
	end

	function AutoSummon:_Refresh(ctx, state, preserveKey)
		local banners = ctx.Game:State("BannerData")
		state.Banners = Catalog.Banners(banners, ctx.Game:Information() or {})
		local options = state.Banners.Options
		local shown = #options > 0 and options or {"No banners available"}
		if state.BannerDropdown then
			state.BannerDropdown:ClearOptions()
			state.BannerDropdown:InsertOptions(shown)
		end
		local wanted = tostring(preserveKey or state.SelectedBannerKey or "")
		if not state.Banners.ByKey[wanted] then
			wanted = state.Banners.Entries[1] and state.Banners.Entries[1].Key or nil
		end
		state.SelectedBannerKey = wanted
		if state.BannerDropdown and wanted then
			state.BannerDropdown:UpdateSelection(state.Banners.ByKey[wanted])
		end
		if #options == 0 then self:_Status(state, "No banners are currently available.") end
		return wanted
	end

	local function findUnit(units, known)
		for id, unit in pairs(type(units) == "table" and units or {}) do
			if not known[tostring(id)] and type(unit) == "table" then return unit end
		end
		return nil
	end

	function AutoSummon:_SummonOnce(ctx, state, generation)
		local bannerData = ctx.Game:State("BannerData")
		local current = type(bannerData) == "table" and bannerData[state.SelectedBannerKey] or nil
		if type(current) ~= "table" or type(current.BannerInfo) ~= "table" or current.BannerInfo.Hidden == true then
			self:_Stop(state, "Selected banner is no longer available.")
			return
		end

		local information = ctx.Game:Information() or {}
		local playerData = ctx.Game:PlayerData()
		if type(playerData) ~= "table" then self:_Status(state, "Waiting for player data...") task.wait(0.5) return end
		local info = current.BannerInfo
		local currency = tostring(info.Currency or "Gem")
		local price = math.max(0, tonumber(info.Cost) or 0)
		local beforeCurrency = Catalog.OwnedAmount(playerData, information, currency)
		-- The game can discount BannerInfo.Cost through a live session boost. A
		-- positive balance is allowed through to the server so this client does
		-- not incorrectly block a discounted summon.
		if price > 0 and beforeCurrency <= 0 then
			self:_Status(state, string.format("Waiting for %s.", currency))
			task.wait(1)
			return
		end

		local known = {}
		for id in pairs(type(playerData.UnitData) == "table" and playerData.UnitData or {}) do known[tostring(id)] = true end
		self:_Status(state, "Summoning...")
		local fired, fireError = ctx.Game:Fire("BANNER_SUMMON", state.SelectedBannerKey, 1)
		if not fired then self:_Status(state, "Summon failed: " .. tostring(fireError)) task.wait(1) return end

		local deadline = os.clock() + RESULT_TIMEOUT
		local currencyChangedAt
		repeat
			task.wait(0.05)
			if not state.Alive or state.Generation ~= generation or not state.Enabled then return end
			local latest = ctx.Game:PlayerData()
			if type(latest) == "table" then
				local unit = findUnit(latest.UnitData, known)
				if unit then
					local name = Catalog.UnitName(information, unit)
					local rarity = Catalog.UnitRarity(information, unit)
					self:_Status(state, string.format("Summoned %s (%s).", name, rarity))
					if state.StopSecret and rarity == "Secret" then
						self:_Stop(state, "Stopped: summoned " .. name .. " (Secret).")
					elseif state.StopRarity and state.StopRarity ~= "None" and rarity == state.StopRarity then
						self:_Stop(state, string.format("Stopped: summoned %s (%s).", name, rarity))
					end
					return
				end
				local afterCurrency = Catalog.OwnedAmount(latest, information, currency)
				if afterCurrency < beforeCurrency then
					currencyChangedAt = currencyChangedAt or os.clock()
				end
				if currencyChangedAt and os.clock() - currencyChangedAt >= 1 then
					-- Auto-sell can remove a result before UnitData replicates it. The
					-- currency change still proves the server accepted this one summon.
					-- A grace period first prevents currency replication winning a race
					-- against the unit result and hiding its rarity stop condition.
					self:_Status(state, "Summoned; result was auto-sold or unavailable.")
					return
				end
			end
		until os.clock() >= deadline
		self:_Status(state, "No summon result received; retrying slowly.")
		task.wait(1)
	end

	function AutoSummon:_Start(ctx, state)
		state.Generation = state.Generation + 1
		local generation = state.Generation
		state.Alive = true
		local worker = task.spawn(function()
			while state.Alive and state.Generation == generation and ctx.Runtime.Alive do
				if state.Enabled then
					local ok, err = xpcall(function() self:_SummonOnce(ctx, state, generation) end, Util.Traceback)
					if not ok then self:_Status(state, "Auto Summon error: " .. tostring(err)) task.wait(1) end
				else
					task.wait(IDLE_INTERVAL)
				end
			end
		end)
		if worker then ctx:RegisterCleanup(worker) end
		ctx:RegisterCleanup(function()
			state.Alive = false
			state.Generation = state.Generation + 1
		end)
	end

	return {
		Name = "AutoSummon",
		Version = 1,
		Priority = 12,
		Dependencies = {"Misc"},

		Init = function(self, ctx)
			local state = {
				Alive = false,
				Generation = 0,
				Enabled = false,
				StopSecret = false,
				StopRarity = "None",
				Status = "Idle.",
				Banners = Catalog.Banners(ctx.Game:State("BannerData"), ctx.Game:Information() or {}),
			}
			local section = ctx.Tabs.Misc:Section({Side = "Left"})
			section:Header({Text = "Auto Summon"})
			section:Header({Text = "Status"})
			state.StatusLabel = section:Label({Text = "Idle."})
			state.Toggle = ctx.Registry:Toggle(section, {
				Name = "Auto Summon",
				Default = false,
				Callback = function(value)
					state.Enabled = value == true
					if not value then
						if state.SuppressIdleOnce then state.SuppressIdleOnce = false
						else AutoSummon:_Status(state, "Idle.") end
					end
				end,
			}, "auto_summon.enabled")

			local options = #state.Banners.Options > 0 and state.Banners.Options or {"No banners available"}
			local first = state.Banners.Entries[1]
			state.SelectedBannerKey = first and first.Key or nil
			state.BannerDropdown = ctx.Registry:Dropdown(section, {
				Name = "Banner Selection",
				Search = true,
				Multi = false,
				Required = true,
				Options = options,
				Default = 1,
				ResolveValue = function(value)
					local key = Catalog.ExtractBracketKey(value)
					return state.Banners.ByKey[tostring(key)] or value
				end,
				Callback = function(value)
					state.SelectedBannerKey = state.Banners.ByLabel[value] or Catalog.ExtractBracketKey(value)
				end,
			}, "auto_summon.banner")
			section:Button({
				Name = "Refresh Banners",
				Callback = function() AutoSummon:_Refresh(ctx, state, state.SelectedBannerKey) end,
			})
			section:Header({Text = "Ping / Stop Rarity"})
			local rarities = Catalog.Rarities(ctx.Game:Information() or {})
			ctx.Registry:Dropdown(section, {
				Name = "Rarity to stop summoning on",
				Search = true,
				Multi = false,
				Required = true,
				Options = rarities,
				Default = 1,
				Callback = function(value) state.StopRarity = tostring(value or "None") end,
			}, "auto_summon.stop_rarity")
			ctx.Registry:Toggle(section, {
				Name = "Stop Summoning on Secret",
				Default = false,
				Callback = function(value) state.StopSecret = value == true end,
			}, "auto_summon.stop_secret")
			return state
		end,

		Enable = function(self, ctx, state) AutoSummon:_Start(ctx, state) end,
		Disable = function(self, ctx, state)
			state.Alive = false
			state.Enabled = false
			state.Generation = state.Generation + 1
		end,
	}
end
