local function resolveHub(...)
	local viaVarargs = ...
	if typeof(viaVarargs) == "table" and viaVarargs.Core ~= nil then
		return viaVarargs
	end
	local env = (getgenv and getgenv()) or shared or _G
	return env.__AEHubLoading
end

local Hub = resolveHub(...)
assert(Hub and Hub.Core and Hub.Core.Library, "[AEHub] Hub context missing while loading ModuleManager")
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

	local runtime = {
		Threads = {},
		Connections = {},
	}

	function runtime:TrackThread(thread)
		if thread == nil then
			return nil
		end
		table.insert(self.Threads, thread)
		if self.Hub and typeof(self.Hub.TrackThread) == "function" then
			self.Hub:TrackThread(thread)
		end
		return thread
	end

	function runtime:TrackConnection(conn)
		if conn == nil then
			return nil
		end
		table.insert(self.Connections, conn)
		if self.Hub and typeof(self.Hub.TrackConnection) == "function" then
			self.Hub:TrackConnection(conn)
		end
		return conn
	end

	function runtime:Cleanup()
		for _, thread in self.Threads do
			pcall(function()
				task.cancel(thread)
			end)
			pcall(function()
				coroutine.close(thread)
			end)
		end
		self.Threads = {}
		for _, conn in self.Connections do
			pcall(function()
				if conn then
					conn:Disconnect()
				end
			end)
		end
		self.Connections = {}
		pcall(function()
			if self.BootThread then
				task.cancel(self.BootThread)
			end
		end)
		pcall(function()
			if self.PollThread then
				task.cancel(self.PollThread)
			end
		end)
		pcall(function()
			if self.ChangeConnection then
				self.ChangeConnection:Disconnect()
			end
		end)
		self.BootThread = nil
		self.PollThread = nil
		self.ChangeConnection = nil
	end

	runtime.Hub = self.Hub

	self.Modules[moduleDefinition.Id] = {
		Definition = moduleDefinition,
		State = defaults,
		Enabled = false,
		Runtime = runtime,
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
	elseif typeof(module.Definition.OnConfigChanged) == "function" then
		-- Always notify — modules like AutoClaim start themselves from the first category toggle
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
		if module.Runtime and typeof(module.Runtime.Cleanup) == "function" then
			pcall(function()
				module.Runtime:Cleanup()
			end)
		end
		return true
	end

	module.Enabled = false
	if typeof(module.Definition.OnDisable) == "function" then
		pcall(module.Definition.OnDisable, module.State, module.Runtime, self.Hub)
	end
	if module.Runtime and typeof(module.Runtime.Cleanup) == "function" then
		pcall(function()
			module.Runtime:Cleanup()
		end)
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
			if module.Runtime and typeof(module.Runtime.Cleanup) == "function" then
				pcall(function()
					module.Runtime:Cleanup()
				end)
			end
			module.Runtime = {
				Threads = {},
				Connections = {},
				Cleanup = function() end,
				TrackThread = function(_, thread)
					return thread
				end,
				TrackConnection = function(_, conn)
					return conn
				end,
			}
		end
	end
end

function ModuleManager:BuildUi(window, tabs)
	for _, moduleId in self.Order do
		local module = self.Modules[moduleId]
		if module and typeof(module.Definition.BuildUi) == "function" then
			local ok, err = xpcall(function()
				module.Definition.BuildUi(module.State, window, tabs, self.Hub)
			end, function(e)
				return Library.FormatError and Library.FormatError(e) or tostring(e)
			end)
			if not ok then
				warn("[AEHub] BuildUi failed for module '" .. moduleId .. "':\n" .. tostring(err))
				error("[AEHub] BuildUi failed for module '" .. moduleId .. "':\n" .. tostring(err), 0)
			end
		end
	end
end

return ModuleManager
