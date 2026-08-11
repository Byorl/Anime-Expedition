return function()
	local function disconnectAll(state)
		for _, connection in ipairs(state.Connections) do
			if connection and type(connection.Disconnect) == "function" then
				pcall(connection.Disconnect, connection)
			end
		end
		table.clear(state.Connections)
	end

	local function closeRewardPrompt(ctx, state, promptId)
		promptId = promptId ~= nil and tostring(promptId) or nil
		if not promptId or promptId == "" then return end
		if not state.DisableRewardPopups and not (state.FastSummon and promptId == "SummonAnimation") then return end
		if state.ClosingPrompts[promptId] then return end
		state.ClosingPrompts[promptId] = true
		ctx.Game:FireLocal("PROMPT_CLOSE", promptId)
		ctx.Game:Fire("PROMPT_CLOSED", promptId)
		task.delay(0.15, function()
			state.ClosingPrompts[promptId] = nil
		end)
	end

	local function applyRewardSuppression(ctx, state)
		local actions = ctx.Game.Actions
		if type(actions) ~= "table" then return end
		local current = actions.PromptObtainedRewards
		if state.DisableRewardPopups then
			if not state.PromptActionOverride then
				if type(current) ~= "function" then return end
				state.OriginalPromptAction = current
				state.PromptActionOverride = function()
					return nil
				end
			end
			if current ~= state.PromptActionOverride then
				pcall(function()
					actions.PromptObtainedRewards = state.PromptActionOverride
				end)
			end
		elseif state.PromptActionOverride and current == state.PromptActionOverride then
			pcall(function()
				actions.PromptObtainedRewards = state.OriginalPromptAction
			end)
		end
	end

	return {
		Name = "Misc",
		Version = 3,
		Priority = 10,
		Dependencies = {},

		Init = function(self, ctx)
			local state = {
				Alive = false,
				FastSummon = false,
				DisableRewardPopups = true,
				OriginalFastSummon = false,
				OriginalPromptAction = nil,
				PromptActionOverride = nil,
				Connections = {},
				ClosingPrompts = {},
			}
			local function isActive()
				return ctx.Runtime.Modules.Loaded.Misc ~= nil
			end
			local function applyFastSummon()
				if not isActive() then return end
				local wanted = state.FastSummon and true or state.OriginalFastSummon == true
				local ok, err = ctx.Game:ChangeSetting("FastSummon", wanted)
				if not ok then ctx.Runtime:Notify("Fast Summon", tostring(err)) end
				if state.FastSummon then closeRewardPrompt(ctx, state, "SummonAnimation") end
			end

			local session = ctx.Tabs.MiscClaims:Section({Side = "Right"})
			session:Header({Text = "Session"})
			session:Toggle({
				Name = "Auto Execute",
				Default = ctx.Config.Account.Session.AutoExecute == true,
				Callback = function(value)
					if not isActive() then return end
					local active = ctx.Session:SetAutoExecute(value)
					if value and not active then ctx.Runtime:Notify("Auto Execute", "Unable to queue this executor.") end
				end,
			})
			ctx.Registry:Toggle(session, {
				Name = "Auto Reconnect",
				Default = false,
				Callback = function(value)
					if not isActive() then return end
					ctx.Session:SetAutoReconnect(value)
				end,
			}, "misc.auto_reconnect")

			local summoning = ctx.Tabs.MiscUnits:Section({Side = "Left"})
			summoning:Header({Text = "Summoning"})
			ctx.Registry:Toggle(summoning, {
				Name = "Fast Summon",
				Default = false,
				Callback = function(value)
					state.FastSummon = value == true
					applyFastSummon()
				end,
			}, "misc.fast_summon")
			ctx.Registry:Toggle(summoning, {
				Name = "Hide Obtained Rewards",
				Default = true,
				Callback = function(value)
					state.DisableRewardPopups = value == true
					applyRewardSuppression(ctx, state)
				end,
			}, "misc.disable_reward_popups")
			summoning:Paragraph({
				Header = "Popup behavior",
				Body = "Fast Summon skips summon animations. Hide Obtained Rewards blocks the game-wide reward screen from opening for any source.",
			})
			return state
		end,

		Enable = function(self, ctx, state)
			state.Alive = true
			applyRewardSuppression(ctx, state)
			local settingOk, original = ctx.Game:InvokeSelf("GET_SETTING_VALUE", "FastSummon")
			state.OriginalFastSummon = settingOk and original == true or false
			for _, nodeName in ipairs({"PROMPT_OBTAINED_REWARDS", "PROMPT_OBTAINED_REWARD_SLOTS"}) do
				local connection, err = ctx.Game:Connect(nodeName, function(_, _, promptId)
					closeRewardPrompt(ctx, state, promptId)
				end)
				if connection then
					table.insert(state.Connections, connection)
				else
					ctx.Runtime:Notify("Reward Popups", tostring(err))
				end
			end
			ctx.Session:SetAutoExecute(ctx.Config.Account.Session.AutoExecute == true)
			ctx.Session:SetAutoReconnect(ctx.Registry:Get("misc.auto_reconnect") == true)
			local ok, err = ctx.Game:ChangeSetting(
				"FastSummon",
				state.FastSummon and true or state.OriginalFastSummon
			)
			if not ok then ctx.Runtime:Notify("Fast Summon", tostring(err)) end
		end,

		Disable = function(self, ctx, state)
			state.Alive = false
			disconnectAll(state)
			table.clear(state.ClosingPrompts)
			state.DisableRewardPopups = false
			applyRewardSuppression(ctx, state)
			ctx.Session:SetAutoReconnect(false)
			ctx.Game:ChangeSetting("FastSummon", state.OriginalFastSummon == true)
		end,
	}
end
