return function()
	local GameMatch = {}

	local function run(ctx, state)
		while state.Alive and ctx.Runtime.Alive do
			local gameState = ctx.Game:State("GameState")
			local inGame = type(gameState) == "table" and type(gameState.Parameters) == "table"
			local active = inGame and ctx.Game:IsMatchActive(gameState)
			if inGame and not state.WasInGame then
				state.GameStartedAt = os.clock()
			end
			if not inGame then
				state.GameStartedAt = nil
			end
			state.WasInGame = inGame

			local canStart = inGame and not active and gameState.GameEnded ~= true
			local startReady = state.AutoStart
				and canStart
				and state.GameStartedAt
				and os.clock() - state.GameStartedAt >= state.StartDelay
			if startReady then
				ctx.Game:RespondToVote("start game")
			end
			if state.AutoSkip and active then
				ctx.Game:RespondToVote("skip")
			end

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
		Version = 2,
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
			}
			local automation = ctx.Tabs.Game:Section({ Side = "Left" })
			automation:Header({ Text = "Match Automation" })
			ctx.Registry:Toggle(automation, {
				Name = "Auto Start",
				Default = false,
				Callback = function(value)
					state.AutoStart = value == true
				end,
			}, "game.match.auto_start")
			ctx.Registry:Toggle(automation, {
				Name = "Auto Skip Waves",
				Default = false,
				Callback = function(value)
					state.AutoSkip = value == true
				end,
			}, "game.match.auto_skip")
			ctx.Registry:Slider(automation, {
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
			local afk = ctx.Tabs.Game:Section({ Side = "Left" })
			afk:Header({ Text = "AFK Chamber" })
			ctx.Registry:Toggle(afk, {
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
		end,
	}
end
