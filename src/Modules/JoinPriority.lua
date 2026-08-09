return function()
	local modes = {
		{Name = "Story", Default = 6},
		{Name = "Raid", Default = 5},
		{Name = "Expedition", Default = 4},
		{Name = "Challenge", Default = 3},
		{Name = "Event", Default = 2},
		{Name = "Bounty", Default = 1},
	}

	local function flagName(name)
		local value = string.lower(tostring(name))
		value = string.gsub(value, "[^%w]+", "_")
		value = string.gsub(value, "^_+", "")
		value = string.gsub(value, "_+$", "")
		return "join_priority." .. value
	end

	return {
		Name = "JoinPriority",
		Version = 1,
		Priority = 19,
		Dependencies = {},

		Init = function(self, ctx)
			local discovered = {}
			for _, entry in ipairs(modes) do discovered[string.lower(entry.Name)] = true end
			for _, name in ipairs(ctx.Join:Modes()) do
				local key = string.lower(tostring(name))
				if not discovered[key] then
					discovered[key] = true
					table.insert(modes, {Name = tostring(name), Default = 1})
				end
			end

			local section = ctx.Tabs.Priority:Section({Side = "Left"})
			section:Header({Text = "How it works"})
			section:Label({
				Text = "Turn on Auto Join Priority, then set each gamemode's number. When several Auto Joins are on, the highest number is tried first. Off = Story > Raid > Challenge order.",
			})
			section:Divider()
			ctx.Registry:Toggle(section, {
				Name = "Auto Join Priority",
				Default = false,
				Callback = function(value)
					ctx.Join:SetPriorityEnabled(value == true)
				end,
			}, "join_priority.enabled")
			section:Divider()

			local values = {}
			for _, entry in ipairs(modes) do
				local modeName = entry.Name
				values[modeName] = entry.Default
				ctx.Join:SetPriority(modeName, entry.Default)
				ctx.Registry:Slider(section, {
					Name = modeName .. " Priority",
					Default = entry.Default,
					Minimum = 1,
					Maximum = 6,
					Precision = 0,
					Step = 1,
					Callback = function(value)
						values[modeName] = math.floor(tonumber(value) or 1)
						ctx.Join:SetPriority(modeName, values[modeName])
					end,
				}, flagName(modeName))
			end
			return {Values = values, Modes = modes}
		end,

		Disable = function(self, ctx)
			ctx.Join:SetPriorityEnabled(false)
		end,
	}
end
