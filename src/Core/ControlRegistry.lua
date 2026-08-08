return function(Import)
	local Util = Import("Util")
	local ControlRegistry = {}
	ControlRegistry.__index = ControlRegistry

	function ControlRegistry.new()
		return setmetatable({Entries = {}, Values = {}, Applying = false, OnChanged = nil}, ControlRegistry)
	end

	function ControlRegistry:_Changed(flag, value)
		self.Values[flag] = Util.Clone(value)
		if not self.Applying and self.OnChanged then
			Util.SafeCall("control changed " .. flag, self.OnChanged, flag, Util.Clone(value))
		end
	end

	function ControlRegistry:_Register(flag, kind, control, defaultValue, apply)
		assert(type(flag) == "string" and flag ~= "", "stateful controls require a unique flag")
		assert(self.Entries[flag] == nil, "duplicate control flag: " .. flag)
		self.Entries[flag] = {
			Flag = flag,
			Kind = kind,
			Control = control,
			Default = Util.Clone(defaultValue),
			Apply = apply,
		}
		self.Values[flag] = Util.Clone(defaultValue)
		return control
	end

	function ControlRegistry:Toggle(section, settings, flag)
		local original = settings.Callback
		local copied = Util.Clone(settings)
		copied.Callback = function(value)
			self:_Changed(flag, value == true)
			Util.SafeCall(flag .. " callback", original, value == true)
		end
		local control = section:Toggle(copied, flag)
		return self:_Register(flag, "Toggle", control, copied.Default == true, function(value)
			control:UpdateState(value == true)
		end)
	end

	function ControlRegistry:Slider(section, settings, flag)
		local original = settings.Callback
		local complete = settings.onInputComplete
		local copied = Util.Clone(settings)
		copied.Callback = function(value)
			local number = tonumber(value) or copied.Default or 0
			self:_Changed(flag, number)
			Util.SafeCall(flag .. " callback", original, number)
		end
		copied.onInputComplete = function(value)
			Util.SafeCall(flag .. " input complete", complete, tonumber(value) or value)
		end
		local control = section:Slider(copied, flag)
		return self:_Register(flag, "Slider", control, tonumber(copied.Default) or 0, function(value)
			local number = tonumber(value) or tonumber(copied.Default) or 0
			number = math.clamp(number, copied.Minimum or -math.huge, copied.Maximum or math.huge)
			control:UpdateValue(number)
		end)
	end

	function ControlRegistry:Input(section, settings, flag)
		local originalChanged = settings.onChanged
		local originalCommitted = settings.Callback
		local copied = Util.Clone(settings)
		local function changed(value)
			value = tostring(value or "")
			self:_Changed(flag, value)
			Util.SafeCall(flag .. " changed", originalChanged, value)
		end
		copied.onChanged = changed
		copied.Callback = function(value)
			changed(value)
			Util.SafeCall(flag .. " committed", originalCommitted, tostring(value or ""))
		end
		local control = section:Input(copied, flag)
		local default = tostring(copied.Default or "")
		return self:_Register(flag, "Input", control, default, function(value)
			control:UpdateText(tostring(value or ""))
		end)
	end

	function ControlRegistry:Dropdown(section, settings, flag)
		local original = settings.Callback
		local copied = Util.Clone(settings)
		copied.Callback = function(value)
			local stored = value
			if copied.Multi and type(value) == "table" then
				stored = {}
				for key, state in pairs(value) do
					if type(key) == "number" then
						table.insert(stored, state)
					elseif state == true then
						table.insert(stored, key)
					end
				end
				table.sort(stored, function(a, b) return tostring(a) < tostring(b) end)
			end
			self:_Changed(flag, Util.Clone(stored))
			Util.SafeCall(flag .. " callback", original, value)
		end
		local control = section:Dropdown(copied, flag)
		local default
		if copied.Multi then
			default = Util.Clone(copied.Default or {})
		elseif type(copied.Default) == "number" and copied.Options then
			default = copied.Options[copied.Default]
		else
			default = copied.Default
		end
		return self:_Register(flag, "Dropdown", control, default, function(value)
			if value ~= nil then control:UpdateSelection(Util.Clone(value)) end
		end)
	end

	function ControlRegistry:Keybind(section, settings, flag)
		local pressed = settings.Callback
		local rebound = settings.onBinded
		local copied = Util.Clone(settings)
		copied.Callback = function(bind) Util.SafeCall(flag .. " pressed", pressed, bind) end
		copied.onBinded = function(bind)
			self:_Changed(flag, bind and bind.Name or nil)
			Util.SafeCall(flag .. " rebound", rebound, bind)
		end
		local control = section:Keybind(copied, flag)
		local default = copied.Default or Enum.KeyCode.RightShift
		return self:_Register(flag, "Keybind", control, default.Name, function(value)
			local bind = typeof(value) == "EnumItem" and value or Enum.KeyCode[tostring(value)]
			bind = bind or default
			control:Bind(bind)
			self.Values[flag] = bind.Name
			Util.SafeCall(flag .. " applied", rebound, bind)
		end)
	end

	function ControlRegistry:Colorpicker(section, settings, flag)
		local original = settings.Callback
		local copied = Util.Clone(settings)
		copied.Callback = function(color, alpha)
			local value = {R = color.R, G = color.G, B = color.B, A = alpha}
			self:_Changed(flag, value)
			Util.SafeCall(flag .. " callback", original, color, alpha)
		end
		local control = section:Colorpicker(copied, flag)
		local defaultColor = copied.Default or Color3.new(1, 1, 1)
		local default = {R = defaultColor.R, G = defaultColor.G, B = defaultColor.B, A = copied.Alpha}
		return self:_Register(flag, "Colorpicker", control, default, function(value)
			if type(value) ~= "table" then return end
			control:SetColor(Color3.new(tonumber(value.R) or 1, tonumber(value.G) or 1, tonumber(value.B) or 1))
			if value.A ~= nil then control:SetAlpha(tonumber(value.A) or 0) end
		end)
	end

	function ControlRegistry:Snapshot()
		local output = {}
		for _, flag in ipairs(Util.SortedKeys(self.Entries)) do
			output[flag] = Util.Clone(self.Values[flag])
		end
		return output
	end

	function ControlRegistry:Apply(values)
		values = type(values) == "table" and values or {}
		self.Applying = true
		for _, flag in ipairs(Util.SortedKeys(self.Entries)) do
			local entry = self.Entries[flag]
			local value = values[flag]
			if value == nil then value = Util.Clone(entry.Default) end
			self.Values[flag] = Util.Clone(value)
			Util.SafeCall("apply " .. flag, entry.Apply, Util.Clone(value))
		end
		self.Applying = false
	end

	function ControlRegistry:Get(flag)
		return Util.Clone(self.Values[flag])
	end

	return ControlRegistry
end
