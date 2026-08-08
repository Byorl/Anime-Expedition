return function()
	return {
		Name = "Settings",
		Priority = 20,

		Init = function(self, ctx)
			local left = ctx.Tabs.Settings:Section({Side = "Left"})
			local right = ctx.Tabs.Settings:Section({Side = "Right"})

			left:Header({Text = "Configs"})
			local names = ctx.Config:List()
			local selected = ctx.Config.Account.SelectedConfig
			local configDropdown = left:Dropdown({
				Name = "Configs",
				Search = true,
				Multi = false,
				Required = true,
				Options = names,
				Default = table.find(names, selected) or 1,
				Callback = function(value)
					if value then ctx.Config:SetSelected(value) end
				end,
			})

			left:Header({Text = "Config Name"})
			local pendingName = ""
			local nameInput = left:Input({
				Name = "Config Name",
				Placeholder = "Enter a global config name",
				AcceptedCharacters = "All",
				Default = "",
				onChanged = function(value) pendingName = value end,
				Callback = function(value) pendingName = value end,
			})

			local function notifyResult(action, ok, message)
				ctx.Runtime:Notify(ok and action or (action .. " failed"), message or "Unknown error")
			end

			local function refresh(selection)
				local updated = ctx.Config:List()
				local wanted = selection or ctx.Config.Account.SelectedConfig or updated[1]
				configDropdown:ClearOptions()
				configDropdown:InsertOptions(updated)
				if wanted then configDropdown:UpdateSelection(wanted) end
			end

			left:Button({
				Name = "Create",
				Callback = function()
					local clean = ctx.Config:SanitizeName(pendingName)
					local ok, err = ctx.Config:Create(clean)
					if ok then
						refresh(clean)
						nameInput:UpdateText("")
						pendingName = ""
					end
					notifyResult("Create config", ok, ok and ("Created global config " .. clean) or err)
				end,
			})
			left:Button({
				Name = "Delete",
				Callback = function()
					local target = ctx.Config.Account.SelectedConfig
					ctx.Window:Dialog({
						Title = "Delete config",
						Description = "Delete global config '" .. tostring(target) .. "'?",
						Buttons = {
							{
								Name = "Delete",
								Callback = function()
									local ok, err = ctx.Config:Delete(target)
									if ok then
										refresh(ctx.Config.Account.SelectedConfig)
										ctx.Config:Load(ctx.Config.Account.SelectedConfig)
									end
									notifyResult("Delete config", ok, ok and ("Deleted " .. target) or err)
								end,
							},
							{Name = "Cancel"},
						},
					})
				end,
			})
			left:Button({
				Name = "Load",
				Callback = function()
					local target = ctx.Config.Account.SelectedConfig
					local ok, err = ctx.Config:Load(target)
					notifyResult("Load config", ok, ok and ("Loaded " .. target) or err)
				end,
			})
			left:Button({
				Name = "Save",
				Callback = function()
					local target = ctx.Config.Account.SelectedConfig
					local ok, err = ctx.Config:Save(target)
					notifyResult("Save config", ok, ok and ("Saved " .. target) or err)
				end,
			})
			left:Toggle({
				Name = "Auto Load Selected",
				Default = ctx.Config.Account.AutoLoadSelected == true,
				Callback = function(value)
					ctx.Config.Account.AutoLoadSelected = value == true
					ctx.Config:SaveAccount()
				end,
			})
			left:Toggle({
				Name = "Auto Save Settings",
				Default = ctx.Config.Account.AutoSave == true,
				Callback = function(value)
					ctx.Config.Account.AutoSave = value == true
					ctx.Config:SaveAccount()
					if value then ctx.Config:ScheduleAutoSave() end
				end,
			})

			right:Header({Text = "Appearance"})
			ctx.Registry:Keybind(right, {
				Name = "UI Hide / Show Key",
				Default = Enum.KeyCode.RightShift,
				Blacklist = {Enum.KeyCode.Unknown},
				Callback = function() end,
				onBinded = function(bind) ctx.Window:SetKeybind(bind) end,
			}, "settings.ui_keybind")
			ctx.Registry:Slider(right, {
				Name = "UI Size",
				Default = 100,
				Minimum = 70,
				Maximum = 140,
				DisplayMethod = "Percent",
				Precision = 0,
				Callback = function(value) ctx.Window:SetScale(value / 100) end,
			}, "settings.ui_scale")

			return {Refresh = refresh}
		end,
	}
end
