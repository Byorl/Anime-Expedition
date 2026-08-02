local Hub = ...
local Library = Hub.Core.Library

local ModuleManager = {}
ModuleManager.__index = ModuleManager

function ModuleManager.new(hub)
	local self = setmetatable({}, ModuleManager)
	self.Hub = hub
	self.Modules = {}
	self.Order = {}
	return self
end

function ModuleManager:Register(moduleDefinition)
	assert(typeof(moduleDefinition) == "table", "Module definition must be a table")
	assert(typeof(moduleDefinition.Id) == "string", "Module needs an Id")

	local defaults = Library.DeepCopy(moduleDefinition.Defaults or {})
	if defaults.Enabled == nil then
		defaults.Enabled = false
	end

	self.Modules[moduleDefinition.Id] = {
		Definition = moduleDefinition,
		State = defaults,
		Enabled = false,
		Runtime = {},
	}
	table.insert(self.Order, moduleDefinition.Id)
end

function ModuleManager:Get(id)
	return self.Modules[id]
end

function ModuleManager:GetState(id)
	local module = self.Modules[id]
	return module and module.State or nil
end

function ModuleManager:OnFlagChanged(flag, value)
	local moduleId, key = string.match(tostring(flag), "^([%w_]+)%.(.+)$")
	if not moduleId or not key then
		return
	end

	local module = self.Modules[moduleId]
	if not module then
		return
	end

	module.State[key] = value

	if key == "Enabled" then
		if value == true then
			self:Enable(moduleId)
		else
			self:Disable(moduleId)
		end
	elseif module.Enabled and typeof(module.Definition.OnConfigChanged) == "function" then
		pcall(module.Definition.OnConfigChanged, module.State, key, value, self.Hub)
	end
end

function ModuleManager:ApplyValues(values)
	if typeof(values) ~= "table" then
		return
	end

	for _, moduleId in self.Order do
		local module = self.Modules[moduleId]
		if module then
			for key in module.State do
				local flag = moduleId .. "." .. key
				if values[flag] ~= nil then
					module.State[key] = Library.DeepCopy(values[flag])
				end
			end
			-- Also accept unknown flags from configs (e.g. migrated keys)
			local prefix = moduleId .. "."
			for flag, value in values do
				if string.sub(flag, 1, #prefix) == prefix then
					local key = string.sub(flag, #prefix + 1)
					if module.State[key] == nil then
						module.State[key] = Library.DeepCopy(value)
					end
				end
			end
			if typeof(module.Definition.AfterApplyState) == "function" then
				pcall(module.Definition.AfterApplyState, module.State, self.Hub)
			end
		end
	end

	for _, moduleId in self.Order do
		local module = self.Modules[moduleId]
		if module then
			if module.State.Enabled == true then
				if module.Enabled then
					self:Disable(moduleId)
				end
				self:Enable(moduleId)
			else
				self:Disable(moduleId)
			end
		end
	end
end

function ModuleManager:ExportValues()
	local values = {}
	for _, moduleId in self.Order do
		local module = self.Modules[moduleId]
		if module then
			for key, value in module.State do
				values[moduleId .. "." .. key] = Library.DeepCopy(value)
			end
		end
	end
	return values
end

function ModuleManager:Enable(id)
	local module = self.Modules[id]
	if not module then
		return false
	end

	module.State.Enabled = true
	if module.Enabled then
		if typeof(module.Definition.OnConfigChanged) == "function" then
			pcall(module.Definition.OnConfigChanged, module.State, "Enabled", true, self.Hub)
		end
		return true
	end

	module.Enabled = true
	if typeof(module.Definition.OnEnable) == "function" then
		local ok, err = pcall(module.Definition.OnEnable, module.State, module.Runtime, self.Hub)
		if not ok then
			module.Enabled = false
			module.State.Enabled = false
			warn("[AEHub] Failed to enable " .. id .. ": " .. tostring(err))
			return false
		end
	end
	return true
end

function ModuleManager:Disable(id)
	local module = self.Modules[id]
	if not module then
		return false
	end

	module.State.Enabled = false
	if not module.Enabled then
		return true
	end

	module.Enabled = false
	if typeof(module.Definition.OnDisable) == "function" then
		pcall(module.Definition.OnDisable, module.State, module.Runtime, self.Hub)
	end
	return true
end

function ModuleManager:DisableAll()
	for i = #self.Order, 1, -1 do
		self:Disable(self.Order[i])
	end
end

function ModuleManager:DestroyAll()
	for i = #self.Order, 1, -1 do
		local moduleId = self.Order[i]
		local module = self.Modules[moduleId]
		if module then
			self:Disable(moduleId)
			if typeof(module.Definition.OnDestroy) == "function" then
				pcall(module.Definition.OnDestroy, module.State, module.Runtime, self.Hub)
			end
			module.Runtime = {}
		end
	end
end

function ModuleManager:BuildUi(window, tabs)
	for _, moduleId in self.Order do
		local module = self.Modules[moduleId]
		if module and typeof(module.Definition.BuildUi) == "function" then
			pcall(module.Definition.BuildUi, module.State, window, tabs, self.Hub)
		end
	end
end

return ModuleManager
