return function()
	return {
		Name = "Misc",
		Priority = 10,

		Init = function(self, ctx)
			local function isActive()
				return ctx.Runtime.Modules.Loaded.Misc ~= nil
			end

			local profile = ctx.Tabs.Misc:Section({Side = "Left"})
			profile:Header({Text = "Extracted Game Profile"})
			profile:Label({Text = "Place ID: " .. tostring(ctx.Build.PlaceId)})
			profile:Label({Text = "Instances: 58,602"})
			profile:Label({Text = "Scripts: 3,400"})
			profile:Label({Text = "Network remotes: 21"})
			profile:Label({Text = "Bindables: 8"})
			profile:SubLabel({Text = "Profile generated from the supplied RBXL extraction."})

			local session = ctx.Tabs.Misc:Section({Side = "Right"})
			session:Header({Text = "Session"})
			ctx.Registry:Toggle(session, {
				Name = "Auto Execute",
				Default = false,
				Callback = function(value)
					if not isActive() then return end
					local active = ctx.Session:SetAutoExecute(value)
					if value and not active then ctx.Runtime:Notify("Auto Execute", "Unable to queue this executor.") end
				end,
			}, "misc.auto_execute")
			ctx.Registry:Toggle(session, {
				Name = "Hide UI on Execute",
				Default = false,
				Callback = function() end,
			}, "misc.hide_ui_on_execute")
			ctx.Registry:Toggle(session, {
				Name = "Auto Reconnect",
				Default = false,
				Callback = function(value)
					if not isActive() then return end
					ctx.Session:SetAutoReconnect(value)
				end,
			}, "misc.auto_reconnect")
		end,

		Enable = function(self, ctx)
			ctx.Session:SetAutoExecute(ctx.Registry:Get("misc.auto_execute") == true)
			ctx.Session:SetAutoReconnect(ctx.Registry:Get("misc.auto_reconnect") == true)
		end,

		Disable = function(self, ctx)
			ctx.Session:SetAutoExecute(false)
			ctx.Session:SetAutoReconnect(false)
		end,
	}
end
