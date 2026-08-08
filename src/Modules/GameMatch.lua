return function()
	local GameMatch = {}

	local function run(ctx, state)
		while state.Alive and ctx.Runtime.Alive do
			local startReady = state.AutoStart
				and state.AutoStartEnabledAt
				and os.clock() - state.AutoStartEnabledAt >= state.StartDelay
			if startReady then
				ctx.Game:RespondToVote("start game")
			end
			if state.AutoSkip then
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
		Version = 3,
		Priority = 7,
		Dependencies = {},

		Init = function(self, ctx)
			local state = {
				Alive = true,
				AutoStart = false,
				AutoSkip = false,
				AutoStartEnabledAt = nil,
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
					state.AutoStartEnabledAt = state.AutoStart and os.clock() or nil
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
