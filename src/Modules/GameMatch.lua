return function()
	local GameMatch = {}
	local UserInputService = game:GetService("UserInputService")
	local VirtualInputManager = game:GetService("VirtualInputManager")
	local VirtualUser = game:GetService("VirtualUser")
	local Workspace = game:GetService("Workspace")

	local function keepActive()
		local ok = pcall(function()
			local position = UserInputService:GetMouseLocation()
			VirtualInputManager:SendMouseMoveEvent(position.X + 1, position.Y, game)
			VirtualInputManager:SendMouseMoveEvent(position.X, position.Y, game)
		end)
		if ok then return true end
		return pcall(function()
			local camera = Workspace.CurrentCamera
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new(0, 0), camera and camera.CFrame or CFrame.new())
		end)
	end

	local function run(ctx, state)
		while state.Alive and ctx.Runtime.Alive do
			if state.PreventAFK and os.clock() - state.LastKeepAlive >= 60 then
				state.LastKeepAlive = os.clock()
				if not keepActive() and not state.KeepAliveWarning then
					state.KeepAliveWarning = true
					ctx.Runtime:Notify("AFK Chamber", "Your executor does not expose virtual input; use Auto Leave AFK Chamber as a fallback.")
				end
			end
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
				(state.LeaveAFK or state.PreventAFK)
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
		Version = 4,
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
				PreventAFK = false,
				LastKeepAlive = -math.huge,
				KeepAliveWarning = false,
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
				Name = "Prevent AFK Chamber",
				Default = false,
				Callback = function(value)
					state.PreventAFK = value == true
					state.LastKeepAlive = -math.huge
					state.KeepAliveWarning = false
				end,
			}, "game.match.prevent_afk")
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
