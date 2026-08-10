return function(Import)
	local Util = Import("Util")
	local GuessUnit = {}

	local EVENT_ID = "GuessUnitEvent"
	local RESET_INTERVAL = 86400
	local RESULT_TIMEOUT = 6
	local RETRY_INTERVAL = 30
	local MODE_ORDER = {"Hard", "Normal"}

	local function selectedModes(value)
		local selected = {}
		for key, enabled in pairs(type(value) == "table" and value or {}) do
			local mode = type(key) == "number" and enabled or key
			if (type(key) == "number" or enabled == true) and (mode == "Normal" or mode == "Hard") then
				selected[mode] = true
			end
		end
		return selected
	end

	local function playerData(ctx)
		if type(ctx.Game.StateDeep) == "function" then
			local ok, value = pcall(ctx.Game.StateDeep, ctx.Game, "PlayerData", 8)
			if ok and type(value) == "table" then return value end
		end
		local value = ctx.Game:PlayerData()
		return type(value) == "table" and value or nil
	end

	local function historyEntry(data, mode)
		local eventData = type(data) == "table" and data.EventData or nil
		local guessData = type(eventData) == "table" and eventData[EVENT_ID] or nil
		local history = type(guessData) == "table" and guessData.ClearHistory or nil
		local entry = type(history) == "table" and history[mode] or nil
		return type(entry) == "table" and entry or nil
	end

	local function todayStart(now)
		now = tonumber(now) or os.time()
		return now - (now % RESET_INTERVAL)
	end

	function GuessUnit:IsAvailable(data, mode, now)
		local entry = historyEntry(data, mode)
		return entry == nil or (tonumber(entry.ClearTime) or 0) < todayStart(now)
	end

	function GuessUnit:_Status(state, message)
		state.Status = tostring(message or "Idle.")
		if state.StatusLabel then
			Util.SafeCall("guess unit status", state.StatusLabel.UpdateName, state.StatusLabel, state.Status)
		end
	end

	function GuessUnit:_Summary(state, data)
		local lines = {}
		for _, mode in ipairs({"Normal", "Hard"}) do
			local entry = historyEntry(data, mode)
			if self:IsAvailable(data, mode) then
				table.insert(lines, mode .. ": Available")
			elseif entry and entry.IsVictory == true then
				table.insert(lines, mode .. ": Completed today")
			else
				table.insert(lines, mode .. ": Failed today (paid retry skipped)")
			end
		end
		local text = table.concat(lines, "\n")
		state.DailyText = text
		if state.DailyLabel then
			Util.SafeCall("guess unit daily state", state.DailyLabel.UpdateName, state.DailyLabel, text)
		end
	end

	function GuessUnit:_WaitForResult(ctx, state, mode, generation)
		local deadline = os.clock() + RESULT_TIMEOUT
		repeat
			task.wait(0.1)
			if not state.Alive or state.Generation ~= generation or not state.Enabled then return false, "stopped" end
			local data = playerData(ctx)
			if data and not self:IsAvailable(data, mode) then
				local entry = historyEntry(data, mode)
				self:_Summary(state, data)
				if entry and entry.IsVictory == true then return true end
				return false, "the game recorded a failed attempt"
			end
		until os.clock() >= deadline
		return false, "the server did not confirm the result"
	end

	function GuessUnit:_Complete(ctx, state, mode, generation)
		state.LastAttempt[mode] = os.clock()
		self:_Status(state, "Completing Guess That Unit - " .. mode .. "...")
		local ok, err = ctx.Game:Action("SendEventRequest", EVENT_ID, "GameResult", mode, true)
		if not ok then return false, tostring(err) end
		return self:_WaitForResult(ctx, state, mode, generation)
	end

	function GuessUnit:_Cycle(ctx, state, generation)
		local data = playerData(ctx)
		if not data then
			self:_Status(state, "Waiting for player data...")
			return
		end
		self:_Summary(state, data)
		local hasSelection = false
		local pending = false
		for _, mode in ipairs(MODE_ORDER) do
			if state.Selected[mode] then
				hasSelection = true
				if self:IsAvailable(data, mode) then
					pending = true
					local lastAttempt = tonumber(state.LastAttempt[mode]) or -math.huge
					if os.clock() - lastAttempt >= RETRY_INTERVAL then
						local ok, err = self:_Complete(ctx, state, mode, generation)
						if not ok and err ~= "stopped" then
							self:_Status(state, mode .. " could not be completed: " .. tostring(err))
						end
						return
					end
				end
			end
		end
		if not hasSelection then
			self:_Status(state, "Select Normal, Hard, or both.")
		elseif pending then
			self:_Status(state, "Waiting before retrying an unconfirmed result...")
		else
			self:_Status(state, "Selected difficulties are complete for today.")
		end
	end

	function GuessUnit:_Start(ctx, state)
		state.Generation = state.Generation + 1
		local generation = state.Generation
		state.Alive = true
		local worker = task.spawn(function()
			while state.Alive and state.Generation == generation and ctx.Runtime.Alive do
				if state.Enabled then
					local ok, err = xpcall(function() self:_Cycle(ctx, state, generation) end, Util.Traceback)
					if not ok then self:_Status(state, "Guess That Unit error: " .. tostring(err)) end
					task.wait(0.5)
				else
					task.wait(0.1)
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
		Name = "GuessUnit",
		Version = 1,
		Priority = 15,
		Dependencies = {"Misc"},

		Init = function(self, ctx)
			local state = {
				Alive = false,
				Generation = 0,
				Enabled = false,
				Selected = {Normal = true, Hard = true},
				LastAttempt = {},
				Status = "Idle.",
			}
			local automation = ctx.Tabs.MiscMinigame:Section({Side = "Left"})
			local daily = ctx.Tabs.MiscMinigame:Section({Side = "Right"})
			automation:Header({Text = "Guess That Unit"})
			state.StatusLabel = automation:Label({Text = "Idle."})
			ctx.Registry:Toggle(automation, {
				Name = "Auto Complete Guess That Unit",
				Default = false,
				Callback = function(value)
					state.Enabled = value == true
					if not state.Enabled then GuessUnit:_Status(state, "Idle.") end
				end,
			}, "guess_unit.enabled")
			automation:Header({Text = "Difficulties"})
			ctx.Registry:Dropdown(automation, {
				Name = "Normal / Hard",
				Search = true,
				Multi = true,
				Required = false,
				Options = {"Normal", "Hard"},
				Default = {"Normal", "Hard"},
				Callback = function(value) state.Selected = selectedModes(value) end,
			}, "guess_unit.difficulties")
			automation:Paragraph({Header = "How it works", Body = "Completes selected free daily modes from replicated event state. Hard is tried first because it also clears Normal. Paid Gold retries are never used."})
			daily:Header({Text = "Daily State"})
			state.DailyLabel = daily:Label({Text = "Waiting for player data..."})
			return state
		end,

		Enable = function(self, ctx, state) GuessUnit:_Start(ctx, state) end,
		Disable = function(self, ctx, state)
			state.Alive = false
			state.Enabled = false
			state.Generation = state.Generation + 1
		end,
	}
end
