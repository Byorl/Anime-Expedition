return function(Import)
	local Util = Import("Util")
	local ControlRegistry = {}
	ControlRegistry.__index = ControlRegistry

	function ControlRegistry.new()
		return setmetatable({
			Entries = {},
			Values = {},
			OwnerActive = {},
			OwnerVersions = {},
			Applying = false,
			TransactionDepth = 0,
			ApplyGeneration = 0,
			OnChanged = nil,
		}, ControlRegistry)
	end

	function ControlRegistry:Scope(owner)
		assert(type(owner) == "string" and owner ~= "", "registry scope requires a module name")
		local root = self
		local scope = {Owner = owner}
		function scope:Toggle(section, settings, flag) return root:Toggle(section, settings, flag, owner) end
		function scope:Slider(section, settings, flag) return root:Slider(section, settings, flag, owner) end
		function scope:Input(section, settings, flag) return root:Input(section, settings, flag, owner) end
		function scope:Dropdown(section, settings, flag) return root:Dropdown(section, settings, flag, owner) end
		function scope:Keybind(section, settings, flag) return root:Keybind(section, settings, flag, owner) end
		function scope:Colorpicker(section, settings, flag) return root:Colorpicker(section, settings, flag, owner) end
		function scope:Get(flag) return root:Get(flag) end
		function scope:Snapshot() return root:SnapshotOwner(owner) end
		return scope
	end

	function ControlRegistry:SetOwnerActive(owner, active)
		self.OwnerActive[owner] = active == true
	end

	function ControlRegistry:SetOwnerVersion(owner, version)
		self.OwnerVersions[owner] = tonumber(version) or 1
	end

	function ControlRegistry:_CanDispatch(owner)
		return owner == nil or self.OwnerActive[owner] ~= false
	end

	function ControlRegistry:_Changed(flag, value, owner)
		if not self:_CanDispatch(owner) then return end
		self.Values[flag] = Util.Clone(value)
		if not self.Applying and self.OnChanged then
			Util.SafeCall("control changed " .. flag, self.OnChanged, flag, Util.Clone(value), owner)
		end
	end

	function ControlRegistry:_Register(flag, kind, control, defaultValue, apply, owner)
		assert(type(flag) == "string" and flag ~= "", "stateful controls require a unique flag")
		assert(self.Entries[flag] == nil, "duplicate control flag: " .. flag)
		self.Entries[flag] = {
			Flag = flag,
			Kind = kind,
			Owner = owner,
			Control = control,
			Default = Util.Clone(defaultValue),
			Apply = apply,
		}
		if owner and self.OwnerActive[owner] == nil then self.OwnerActive[owner] = true end
		self.Values[flag] = Util.Clone(defaultValue)
		return control
	end

	function ControlRegistry:Toggle(section, settings, flag, owner)
		local original = settings.Callback
		local copied = Util.Clone(settings)
		copied.Callback = function(value)
			if not self:_CanDispatch(owner) then return end
			self:_Changed(flag, value == true, owner)
			Util.SafeCall(flag .. " callback", original, value == true)
		end
		local control = section:Toggle(copied, flag)
		return self:_Register(flag, "Toggle", control, copied.Default == true, function(value)
			control:UpdateState(value == true)
		end, owner)
	end

	function ControlRegistry:Slider(section, settings, flag, owner)
		local original = settings.Callback
		local complete = settings.onInputComplete
		local copied = Util.Clone(settings)
		copied.Callback = function(value)
			if not self:_CanDispatch(owner) then return end
			local number = tonumber(value) or copied.Default or 0
			self:_Changed(flag, number, owner)
			Util.SafeCall(flag .. " callback", original, number)
		end
		copied.onInputComplete = function(value)
			if not self:_CanDispatch(owner) then return end
			Util.SafeCall(flag .. " input complete", complete, tonumber(value) or value)
		end
		local control = section:Slider(copied, flag)
		return self:_Register(flag, "Slider", control, tonumber(copied.Default) or 0, function(value)
			local number = tonumber(value) or tonumber(copied.Default) or 0
			number = math.clamp(number, copied.Minimum or -math.huge, copied.Maximum or math.huge)
			control:UpdateValue(number)
		end, owner)
	end

	function ControlRegistry:Input(section, settings, flag, owner)
		local originalChanged = settings.onChanged
		local originalCommitted = settings.Callback
		local copied = Util.Clone(settings)
		local function changed(value)
			if not self:_CanDispatch(owner) then return end
			value = tostring(value or "")
			self:_Changed(flag, value, owner)
			Util.SafeCall(flag .. " changed", originalChanged, value)
		end
		copied.onChanged = changed
		copied.Callback = function(value)
			changed(value)
			if self:_CanDispatch(owner) then
				Util.SafeCall(flag .. " committed", originalCommitted, tostring(value or ""))
			end
		end
		local control = section:Input(copied, flag)
		local default = tostring(copied.Default or "")
		return self:_Register(flag, "Input", control, default, function(value)
			control:UpdateText(tostring(value or ""))
		end, owner)
	end

	function ControlRegistry:Dropdown(section, settings, flag, owner)
		local original = settings.Callback
		local copied = Util.Clone(settings)
		copied.Callback = function(value)
			if not self:_CanDispatch(owner) then return end
			local stored = value
			if copied.Multi and type(value) == "table" then
				stored = {}
				for key, state in pairs(value) do
					if type(key) == "number" then table.insert(stored, state)
					elseif state == true then table.insert(stored, key) end
				end
				table.sort(stored, function(a, b) return tostring(a) < tostring(b) end)
			end
			self:_Changed(flag, Util.Clone(stored), owner)
			Util.SafeCall(flag .. " callback", original, value)
		end
		local control = section:Dropdown(copied, flag)
		local default
		if copied.Multi then default = Util.Clone(copied.Default or {})
		elseif type(copied.Default) == "number" and copied.Options then default = copied.Options[copied.Default]
		else default = copied.Default end
		return self:_Register(flag, "Dropdown", control, default, function(value)
			if value ~= nil then control:UpdateSelection(Util.Clone(value)) end
		end, owner)
	end

	function ControlRegistry:Keybind(section, settings, flag, owner)
		local pressed = settings.Callback
		local rebound = settings.onBinded
		local copied = Util.Clone(settings)
		copied.Callback = function(bind)
			if self:_CanDispatch(owner) then Util.SafeCall(flag .. " pressed", pressed, bind) end
		end
		copied.onBinded = function(bind)
			if not self:_CanDispatch(owner) then return end
			self:_Changed(flag, bind and bind.Name or nil, owner)
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
		end, owner)
	end

	function ControlRegistry:Colorpicker(section, settings, flag, owner)
		local original = settings.Callback
		local copied = Util.Clone(settings)
		copied.Callback = function(color, alpha)
			if not self:_CanDispatch(owner) then return end
			local value = {R = color.R, G = color.G, B = color.B, A = alpha}
			self:_Changed(flag, value, owner)
			Util.SafeCall(flag .. " callback", original, color, alpha)
		end
		local control = section:Colorpicker(copied, flag)
		local defaultColor = copied.Default or Color3.new(1, 1, 1)
		local default = {R = defaultColor.R, G = defaultColor.G, B = defaultColor.B, A = copied.Alpha}
		return self:_Register(flag, "Colorpicker", control, default, function(value)
			if type(value) ~= "table" then return end
			control:SetColor(Color3.new(tonumber(value.R) or 1, tonumber(value.G) or 1, tonumber(value.B) or 1))
			if value.A ~= nil then control:SetAlpha(tonumber(value.A) or 0) end
		end, owner)
	end

	function ControlRegistry:Snapshot()
		local output = {}
		for _, flag in ipairs(Util.SortedKeys(self.Entries)) do output[flag] = Util.Clone(self.Values[flag]) end
		return output
	end

	function ControlRegistry:SnapshotOwner(owner)
		local output = {}
		for _, flag in ipairs(Util.SortedKeys(self.Entries)) do
			if self.Entries[flag].Owner == owner then output[flag] = Util.Clone(self.Values[flag]) end
		end
		return output
	end

	function ControlRegistry:SnapshotModules()
		local modules = {}
		for _, flag in ipairs(Util.SortedKeys(self.Entries)) do
			local entry = self.Entries[flag]
			local owner = entry.Owner or string.match(flag, "^([^.]+)") or "Core"
			modules[owner] = modules[owner] or {Version = self.OwnerVersions[owner] or 1, Values = {}}
			modules[owner].Values[flag] = Util.Clone(self.Values[flag])
		end
		return modules
	end

	function ControlRegistry:BeginApply()
		self.TransactionDepth = self.TransactionDepth + 1
		self.ApplyGeneration = self.ApplyGeneration + 1
		self.Applying = true
		return self.ApplyGeneration
	end

	function ControlRegistry:EndApply()
		self.TransactionDepth = math.max(0, self.TransactionDepth - 1)
		self.Applying = self.TransactionDepth > 0
	end

	function ControlRegistry:_ApplyEntries(values, owner)
		values = type(values) == "table" and values or {}
		local errors = {}
		for _, flag in ipairs(Util.SortedKeys(self.Entries)) do
			local entry = self.Entries[flag]
			if owner == nil or entry.Owner == owner then
				local value = values[flag]
				if value == nil then value = Util.Clone(entry.Default) end
				self.Values[flag] = Util.Clone(value)
				local ok, err = xpcall(function() entry.Apply(Util.Clone(value)) end, Util.Traceback)
				if not ok then table.insert(errors, string.format("%s (%s): %s", flag, entry.Kind, tostring(err))) end
			end
		end
		return #errors == 0, table.concat(errors, "\n")
	end

	function ControlRegistry:ApplyAtomic(values)
		self:BeginApply()
		local ok, err = self:_ApplyEntries(values)
		-- MacLib's input/config setters may dispatch on a deferred task. Holding the
		-- transaction through two scheduler turns prevents a half-loaded autosave.
		task.wait()
		task.wait()
		self:EndApply()
		return ok, err
	end

	function ControlRegistry:Apply(values)
		return self:ApplyAtomic(values)
	end

	function ControlRegistry:ReapplyOwner(owner)
		self:BeginApply()
		local ok, err = self:_ApplyEntries(self.Values, owner)
		self:EndApply()
		return ok, err
	end

	function ControlRegistry:Get(flag)
		return Util.Clone(self.Values[flag])
	end

	return ControlRegistry
end
