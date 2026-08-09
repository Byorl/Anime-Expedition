return function()
	local GameEnd = {}

	local function canNext(ctx, result)
		if result.Victory ~= true or result.HasNextStage ~= true then
			return false
		end
		local information = ctx.Game:Information() or {}
		local maps = type(information) == "table" and information.Maps or nil
		local types = type(maps) == "table" and maps.GamemodeTypes or nil
		local kind = type(types) == "table" and types[result.Gamemode] or nil
		return type(kind) ~= "table" or kind.NextAllowed == true
	end

	local function choose(ctx, state, result, runs)
		local leaveMatches = tonumber(state.LeaveMatches) or 0
		if leaveMatches > 0 and runs >= leaveMatches then
			return "Lobby"
		end
		if state.LobbyLoss and result.Victory ~= true then
			return "Lobby"
		end
		local nextAllowed = canNext(ctx, result)
		local replayAllowed = result.RestartDisabled ~= true
		if state.Smart then
			if nextAllowed then
				return "Next"
			end
			if replayAllowed then
				return "Restart"
			end
			return "Lobby"
		end
		if state.AutoNext and nextAllowed then
			return "Next"
		end
		if state.AutoReplay and replayAllowed then
			return "Restart"
		end
		if state.AutoLeave then
			return "Lobby"
		end
		return nil
	end

	return {
		Name = "GameEnd",
		Version = 3,
		Priority = 8,
		Dependencies = {},
		Choose = choose,

		Init = function(self, ctx)
			local state = {
				Alive = true,
				AutoNext = false,
				AutoReplay = false,
				AutoLeave = false,
				Smart = false,
				LeaveWave = 0,
				LeftAtWave = false,
				LeaveMatches = 0,
				LobbyLoss = false,
				ReturnAfter = false,
				Hours = 1,
				TimeReturned = false,
				EndRevision = 0,
				EndAction = nil,
				EndAttempts = 0,
				NextEndActionAt = 0,
				DeliveryTimeoutRevision = 0,
			}
			local actions = ctx.Tabs.Game:Section({ Side = "Right" })
			actions:Header({ Text = "Match Actions" })
			ctx.Registry:Toggle(actions, {
				Name = "Auto Next Stage",
				Default = false,
				Callback = function(value)
					state.AutoNext = value == true
				end,
			}, "game.end.auto_next")
			ctx.Registry:Toggle(actions, {
				Name = "Auto Replay",
				Default = false,
				Callback = function(value)
					state.AutoReplay = value == true
				end,
			}, "game.end.auto_replay")
			ctx.Registry:Toggle(actions, {
				Name = "Auto Leave",
				Default = false,
				Callback = function(value)
					state.AutoLeave = value == true
				end,
			}, "game.end.auto_leave")
			ctx.Registry:Toggle(actions, {
				Name = "Auto Next/Replay/Leave",
				Default = false,
				Callback = function(value)
					state.Smart = value == true
				end,
			}, "game.end.smart")
			local conditions = ctx.Tabs.Game:Section({ Side = "Right" })
			conditions:Header({ Text = "Exit Conditions" })
			ctx.Registry:Slider(conditions, {
				Name = "Leave at Wave (0=off)",
				Default = 0,
				Minimum = 0,
				Maximum = 500,
				Precision = 0,
				Step = 1,
				Callback = function(value)
					state.LeaveWave = value
					if value <= 0 then
						state.LeftAtWave = false
					end
				end,
			}, "game.match.leave_wave")
			ctx.Registry:Slider(conditions, {
				Name = "Leave After X Matches (0=off)",
				Default = 0,
				Minimum = 0,
				Maximum = 100,
				Precision = 0,
				Step = 1,
				Callback = function(value)
					state.LeaveMatches = value
				end,
			}, "game.end.leave_matches")
			ctx.Registry:Toggle(conditions, {
				Name = "Auto Lobby on Loss",
				Default = false,
				Callback = function(value)
					state.LobbyLoss = value == true
				end,
			}, "game.end.lobby_loss")
			local timerSection = ctx.Tabs.Game:Section({ Side = "Right" })
			timerSection:Header({ Text = "Timed Return" })
			ctx.Registry:Toggle(timerSection, {
				Name = "Return to Lobby After Time",
				Default = false,
				Callback = function(value)
					state.ReturnAfter = value == true
					if not value then
						state.TimeReturned = false
					end
				end,
			}, "game.end.return_after")
			ctx.Registry:Slider(timerSection, {
				Name = "After (hours)",
				Default = 1,
				Minimum = 1,
				Maximum = 12,
				Precision = 0,
				Step = 1,
				Callback = function(value)
					state.Hours = value
				end,
			}, "game.end.hours")

			local timer = task.spawn(function()
				while state.Alive and ctx.Runtime.Alive do
					local result, runs, revision, resultReady = ctx.Results:Snapshot()
					local deliveryReady, pendingDeliveries, deliveryTimedOut =
						ctx.Results:DeliveryState(revision, 15)
					if deliveryTimedOut and state.DeliveryTimeoutRevision ~= revision then
						state.DeliveryTimeoutRevision = revision
						ctx.Runtime:Notify(
							"End of Match",
							"Continuing after delivery timed out: " .. table.concat(pendingDeliveries, ", ")
						)
					end
					local action = resultReady and deliveryReady and choose(ctx, state, result, runs) or nil
					if not action then
						state.EndRevision = revision or 0
						state.EndAction = nil
						state.EndAttempts = 0
					elseif state.EndRevision ~= revision or state.EndAction ~= action then
						state.EndRevision = revision
						state.EndAction = action
						state.EndAttempts = 0
						state.NextEndActionAt = os.clock()
					end
					if action and os.clock() >= state.NextEndActionAt then
						state.EndAttempts = state.EndAttempts + 1
						local ok, err = ctx.Game:GameAction(action)
						state.NextEndActionAt = os.clock() + (state.EndAttempts < 8 and 0.85 or 4)
						if not ok then
							ctx.Runtime:Notify("End of Match", tostring(action) .. " failed: " .. tostring(err))
						elseif state.EndAttempts == 8 then
							ctx.Runtime:Notify(
								"End of Match",
								tostring(action) .. " was sent repeatedly; waiting for the game to accept it."
							)
						end
					end
					local gameState = ctx.Game:GameData()
					local inGame = type(gameState) == "table" and type(gameState.Parameters) == "table"
					if not inGame then
						state.LeftAtWave = false
					elseif
						state.LeaveWave > 0
						and not state.LeftAtWave
						and (tonumber(gameState.Wave) or 0) >= state.LeaveWave
					then
						state.LeftAtWave = true
						local ok, err = ctx.Game:ReturnToLobby()
						if not ok then
							state.LeftAtWave = false
							ctx.Runtime:Notify("Leave at Wave", tostring(err))
						end
					end
					if
						state.ReturnAfter
						and not state.TimeReturned
						and os.clock() - ctx.Results.StartedAt >= state.Hours * 3600
						and ctx.Game:IsInGame()
					then
						state.TimeReturned = true
						local ok, err = ctx.Game:ReturnToLobby()
						if not ok then
							state.TimeReturned = false
							ctx.Runtime:Notify("Return to Lobby", tostring(err))
						end
					end
					task.wait(0.25)
				end
			end)
			ctx:RegisterCleanup(timer)
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
