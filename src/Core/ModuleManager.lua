return function(Import)
	local Janitor = Import("Janitor")
	local Util = Import("Util")
	local ModuleManager = {}
	ModuleManager.__index = ModuleManager

	function ModuleManager.new(context)
		return setmetatable({Definitions = {}, Loaded = {}, Dormant = {}, Order = {}, Context = context}, ModuleManager)
	end

	function ModuleManager:Register(definition)
		assert(type(definition) == "table" and type(definition.Name) == "string", "invalid module")
		assert(self.Definitions[definition.Name] == nil, "duplicate module " .. definition.Name)
		self.Definitions[definition.Name] = definition
		return definition
	end

	function ModuleManager:Load(name)
		if self.Loaded[name] then return true, self.Loaded[name].Result end
		local definition = self.Definitions[name]
		if not definition then return false, "unknown module " .. tostring(name) end
		for _, dependency in ipairs(definition.Dependencies or {}) do
			local ok, err = self:Load(dependency)
			if not ok then return false, err end
		end

		local dormant = self.Dormant[name]
		if dormant then
			dormant.Janitor = Janitor.new()
			dormant.Context.ModuleJanitor = dormant.Janitor
			self.Dormant[name] = nil
			self.Loaded[name] = dormant
			table.insert(self.Order, name)
			if definition.Enable then
				Util.SafeCall("enable module " .. name, definition.Enable, definition, dormant.Context, dormant.Result)
			end
			return true, dormant.Result
		end

		local state = {Janitor = Janitor.new(), Definition = definition}
		local moduleContext = setmetatable({ModuleJanitor = state.Janitor}, {__index = self.Context})
		state.Context = moduleContext
		local ok, result = pcall(definition.Init, definition, moduleContext)
		if not ok then
			state.Janitor:Cleanup()
			return false, result
		end
		state.Result = result
		self.Loaded[name] = state
		table.insert(self.Order, name)
		if definition.Enable then
			Util.SafeCall("enable module " .. name, definition.Enable, definition, moduleContext, result)
		end
		return true, result
	end

	function ModuleManager:Unload(name)
		local state = self.Loaded[name]
		if not state then return true end
		for loadedName, loadedState in pairs(self.Loaded) do
			if loadedName ~= name and table.find(loadedState.Definition.Dependencies or {}, name) then
				self:Unload(loadedName)
			end
		end
		local definition = state.Definition
		if definition.Disable then
			Util.SafeCall("disable module " .. name, definition.Disable, definition, state.Context, state.Result)
		end
		state.Janitor:Cleanup()
		self.Loaded[name] = nil
		self.Dormant[name] = state
		local position = table.find(self.Order, name)
		if position then table.remove(self.Order, position) end
		return true
	end

	function ModuleManager:LoadAll()
		local names = Util.SortedKeys(self.Definitions)
		table.sort(names, function(a, b)
			local left = self.Definitions[a].Priority or 100
			local right = self.Definitions[b].Priority or 100
			return left == right and a < b or left < right
		end)
		for _, name in ipairs(names) do
			local ok, err = self:Load(name)
			if not ok then return false, name .. ": " .. tostring(err) end
		end
		return true
	end

	function ModuleManager:UnloadAll()
		for index = #self.Order, 1, -1 do self:Unload(self.Order[index]) end
	end

	function ModuleManager:DestroyAll()
		for index = #self.Order, 1, -1 do
			local name = self.Order[index]
			local state = self.Loaded[name]
			if state then
				local definition = state.Definition
				if definition.Disable then Util.SafeCall("disable module " .. name, definition.Disable, definition, state.Context, state.Result) end
				if definition.Unload then Util.SafeCall("unload module " .. name, definition.Unload, definition, state.Context, state.Result) end
				state.Janitor:Cleanup()
				self.Loaded[name] = nil
			end
		end
		for name, state in pairs(self.Dormant) do
			local definition = state.Definition
			if definition.Unload then Util.SafeCall("unload dormant module " .. name, definition.Unload, definition, state.Context, state.Result) end
			state.Janitor:Cleanup()
			self.Dormant[name] = nil
		end
		table.clear(self.Order)
	end

	return ModuleManager
end
