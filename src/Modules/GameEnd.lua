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
		if state.LeaveMatches > 0 and runs >= state.LeaveMatches then
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
		Version = 1,
		Priority = 8,
		Dependencies = {},

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
			}
			local section = ctx.Tabs.Game:Section({ Side = "Right" })
			section:Header({ Text = "End of Match" })
			ctx.Registry:Toggle(section, {
				Name = "Auto Next Stage",
				Default = false,
				Callback = function(value)
					state.AutoNext = value == true
				end,
			}, "game.end.auto_next")
			ctx.Registry:Toggle(section, {
				Name = "Auto Replay",
				Default = false,
				Callback = function(value)
					state.AutoReplay = value == true
				end,
			}, "game.end.auto_replay")
			ctx.Registry:Toggle(section, {
				Name = "Auto Leave",
				Default = false,
				Callback = function(value)
					state.AutoLeave = value == true
				end,
			}, "game.end.auto_leave")
			ctx.Registry:Toggle(section, {
				Name = "Auto Next/Replay/Leave",
				Default = false,
				Callback = function(value)
					state.Smart = value == true
				end,
			}, "game.end.smart")
			ctx.Registry:Slider(section, {
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
			ctx.Registry:Slider(section, {
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
			ctx.Registry:Toggle(section, {
				Name = "Auto Lobby on Loss",
				Default = false,
				Callback = function(value)
					state.LobbyLoss = value == true
				end,
			}, "game.end.lobby_loss")
			ctx.Registry:Toggle(section, {
				Name = "Return to Lobby After Time",
				Default = false,
				Callback = function(value)
					state.ReturnAfter = value == true
					if not value then
						state.TimeReturned = false
					end
				end,
			}, "game.end.return_after")
			ctx.Registry:Slider(section, {
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

			ctx:RegisterCleanup(ctx.Results:Subscribe("GameEnd", function(result, runs)
				local action = choose(ctx, state, result, runs)
				if not action then
					return
				end
				local worker = task.delay(1, function()
					if not state.Alive or not ctx.Runtime.Alive then
						return
					end
					local ok, err = ctx.Game:GameAction(action)
					if not ok then
						ctx.Runtime:Notify("End of Match", tostring(action) .. " failed: " .. tostring(err))
					end
				end)
				ctx:RegisterCleanup(worker)
			end))
			local timer = task.spawn(function()
				while state.Alive and ctx.Runtime.Alive do
					local gameState = ctx.Game:State("GameState")
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
