return function()
	local GameMatch = {}

	local function currentSetting(ctx, name)
		local playerData = ctx.Game:PlayerData()
		local settings = type(playerData) == "table" and playerData.Settings or nil
		return type(settings) == "table" and settings[name] or nil
	end

	local function setSetting(ctx, state, name, wanted)
		local current = currentSetting(ctx, name)
		if current == wanted then
			state.SettingAttempts[name] = nil
			return true
		end
		local last = state.SettingAttempts[name]
		if last and os.clock() - last < 1 then
			return
		end
		state.SettingAttempts[name] = os.clock()
		local ok, err = ctx.Game:ChangeSetting(name, wanted)
		if not ok then
			ctx.Runtime:Notify("Game", "Could not update " .. name .. ": " .. tostring(err))
		end
		return false
	end

	local function manageSetting(ctx, state, name, enabled, wanted)
		if enabled then
			if not state.ManagedSettings[name] then
				state.ManagedSettings[name] = true
				state.OriginalSettings[name] = currentSetting(ctx, name) == true
			end
			setSetting(ctx, state, name, wanted)
		elseif state.ManagedSettings[name] then
			if setSetting(ctx, state, name, state.OriginalSettings[name] == true) then
				state.ManagedSettings[name] = nil
				state.OriginalSettings[name] = nil
			end
		end
	end

	local function run(ctx, state)
		while state.Alive and ctx.Runtime.Alive do
			local gameState = ctx.Game:State("GameState")
			local inGame = type(gameState) == "table" and type(gameState.Parameters) == "table"
			if inGame and not state.WasInGame then
				state.GameStartedAt = os.clock()
			end
			if not inGame then
				state.GameStartedAt = nil
			end
			state.WasInGame = inGame

			local canStart = inGame and gameState.EndTime == nil and gameState.GameEnded ~= true
			local startReady = state.AutoStart
				and canStart
				and state.GameStartedAt
				and os.clock() - state.GameStartedAt >= state.StartDelay
			manageSetting(ctx, state, "AutoVoteStart", state.AutoStart, startReady == true)
			manageSetting(ctx, state, "AutoSkipWaves", state.AutoSkip, true)

			local session = ctx.Game:State("SessionData")
			if
				state.LeaveAFK
				and type(session) == "table"
				and session.AFKChamber ~= nil
				and os.clock() - state.LastAFKAttempt >= 3
			then
				state.LastAFKAttempt = os.clock()
				local ok, err = ctx.Game:Fire("REQUEST_AFK_LEAVE")
				if not ok then
					ctx.Runtime:Notify("AFK Chamber", tostring(err))
				end
			end
			task.wait(0.25)
		end
	end

	return {
		Name = "GameMatch",
		Version = 1,
		Priority = 7,
		Dependencies = {},

		Init = function(self, ctx)
			local state = {
				Alive = true,
				AutoStart = false,
				AutoSkip = false,
				StartDelay = 0,
				LeaveAFK = false,
				LastAFKAttempt = 0,
				SettingAttempts = {},
				ManagedSettings = {},
				OriginalSettings = {},
			}
			local section = ctx.Tabs.Game:Section({ Side = "Left" })
			section:Header({ Text = "Match" })
			ctx.Registry:Toggle(section, {
				Name = "Auto Start",
				Default = false,
				Callback = function(value)
					state.AutoStart = value == true
				end,
			}, "game.match.auto_start")
			ctx.Registry:Toggle(section, {
				Name = "Auto Skip Waves",
				Default = false,
				Callback = function(value)
					state.AutoSkip = value == true
				end,
			}, "game.match.auto_skip")
			ctx.Registry:Slider(section, {
				Name = "Auto Start Delay (0=off)",
				Default = 0,
				Minimum = 0,
				Maximum = 10,
				Precision = 0,
				Step = 1,
				Callback = function(value)
					state.StartDelay = value
				end,
			}, "game.match.start_delay")
			ctx.Registry:Toggle(section, {
				Name = "Auto Leave AFK Chamber",
				Default = false,
				Callback = function(value)
					state.LeaveAFK = value == true
				end,
			}, "game.match.leave_afk")
			local worker = task.spawn(function()
				run(ctx, state)
			end)
			ctx:RegisterCleanup(worker)
			ctx:RegisterCleanup(function()
				state.Alive = false
			end)
			return state
		end,

		Disable = function(self, ctx, state)
			state.Alive = false
			state.AutoStart = false
			state.AutoSkip = false
			for name in pairs(state.ManagedSettings) do
				ctx.Game:ChangeSetting(name, state.OriginalSettings[name] == true)
			end
			table.clear(state.ManagedSettings)
			table.clear(state.OriginalSettings)
		end,
	}
end
