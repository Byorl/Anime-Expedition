return function()
	return {
		Name = "Misc",
		Version = 1,
		Priority = 10,
		Dependencies = {},

		Init = function(self, ctx)
			local function isActive()
				return ctx.Runtime.Modules.Loaded.Misc ~= nil
			end

			local session = ctx.Tabs.Misc:Section({Side = "Right"})
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
			session:Toggle({
				Name = "Hide UI on Execute",
				Default = ctx.Config.Account.UI.HiddenOnExecute == true,
				Callback = function(value)
					if not isActive() then return end
					ctx.Config:UpdateAccount(function(account)
						account.UI.HiddenOnExecute = value == true
					end, false)
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
		end,

		Enable = function(self, ctx)
			ctx.Session:SetAutoExecute(ctx.Config.Account.Session.AutoExecute == true)
			ctx.Session:SetAutoReconnect(ctx.Registry:Get("misc.auto_reconnect") == true)
		end,

		Disable = function(self, ctx)
			ctx.Session:SetAutoReconnect(false)
		end,
	}
end
