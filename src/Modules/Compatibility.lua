return function(Import)
	local Util = Import("Util")
	local Compatibility = {}

	local function yesNo(value)
		return value and "yes" or "no"
	end

	function Compatibility:_Refresh(ctx, state)
		local game = ctx.Game
		if not game.Ready then
			self:_Set(state, "Game bindings are not ready yet.")
			return
		end
		local information = game:Information() or {}

		local surfaces = {}
		local function add(label, ok)
			table.insert(surfaces, ("%s: %s"):format(label, yesNo(ok == true)))
		end

		-- Optional network nodes; absent on servers running older builds.
		add("Fishing", game:HasNode("FISH_CAST_REEL") and game:HasNode("FISHING_RESULT"))
		add("Calendar claims", game:HasNode("CLAIM_CALENDAR"))
		add("Native settings", game:HasNode("CLIENT_CHANGE_SETTING"))
		add("Trait swap slot", game:HasNode("UNIT_SWAP_TRAIT"))
		add("Test expedition", game:HasNode("TEST_EXPEDITION"))

		-- Core bindings the script itself depends on.
		add("Match replica", game:HasNode("GET_GAME_REPLICA"))
		add("Results", game:HasNode("SET_END_PARAMETERS") or game:HasNode("SHOW_END_SCREEN"))

		-- Catalog surfaces resolved from live shared information.
		local eventCount = 0
		for _, event in pairs(type(information.Events) == "table" and information.Events or {}) do
			if type(event) == "table" and type(event.QueueData) == "table" and event.QueueData.Gamemode then
				eventCount = eventCount + 1
			end
		end
		add("Queueable events", eventCount > 0 and tostring(eventCount) or "no")
		add("Expeditions", type(information.Expeditions) == "table")
		add("Codes", type(information.Codes) == "table")
		add("Calendars", game:State("CalendarData") ~= nil)

		self:_Set(state, table.concat(surfaces, " | "))
	end

	function Compatibility:_Set(state, message)
		if state.StatusLabel then
			Util.SafeCall("compatibility status", state.StatusLabel.UpdateName, state.StatusLabel, tostring(message))
		end
	end

	return {
		Name = "Compatibility",
		Version = 1,
		Priority = 21,
		Dependencies = {"Settings"},

		Init = function(self, ctx)
			local state = { Alive = true }
			local section = ctx.Tabs.Settings:Section({ Side = "Left" })
			section:Header({ Text = "Server Compatibility" })
			state.StatusLabel = section:Label({ Text = "Checking..." })
			local worker = task.spawn(function()
				while state.Alive and ctx.Runtime.Alive do
					Compatibility:_Refresh(ctx, state)
					task.wait(5)
				end
			end)
			ctx:RegisterCleanup(worker)
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
