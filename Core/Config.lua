local function resolveHub(...)
	local viaVarargs = ...
	if typeof(viaVarargs) == "table" and viaVarargs.Core ~= nil then
		return viaVarargs
	end
	local env = (getgenv and getgenv()) or shared or _G
	return env.__AEHubLoading
end

local Hub = resolveHub(...)
assert(Hub and Hub.Core and Hub.Core.Library, "[AEHub] Hub context missing while loading Config")
local Library = Hub.Core.Library

local Config = {}
Config.__index = Config

local INDEX_NAME = "index.json"

local function configPath(fileName)
	return Library.ConfigsFolder .. "/" .. fileName
end

local function prefsPath(userId)
	return Library.PrefsFolder .. "/" .. tostring(userId) .. ".json"
end

function Config.new(hub)
	local self = setmetatable({}, Config)
	self.Hub = hub
	self.Index = { Configs = {} }
	self.CurrentId = nil
	self.Elements = {}
	self.Values = {}
	self.Applying = false
	self:_loadIndex()
	self:_loadUserPrefs()
	return self
end

function Config:_loadIndex()
	Library.EnsureFolders()
	self.Index = Library.ReadJson(Library.ConfigsFolder .. "/" .. INDEX_NAME, { Configs = {} })
	if typeof(self.Index.Configs) ~= "table" then
		self.Index.Configs = {}
	end
end

function Config:_saveIndex()
	return Library.WriteJson(Library.ConfigsFolder .. "/" .. INDEX_NAME, self.Index)
end

function Config:_loadUserPrefs()
	local player = Library.GetLocalPlayer()
	local userId = player and player.UserId or 0
	self.Prefs = Library.ReadJson(prefsPath(userId), {
		LastConfigId = nil,
		AutoLoad = false,
		UIScale = nil,
	})
	if typeof(self.Prefs) ~= "table" then
		self.Prefs = {
			LastConfigId = nil,
			AutoLoad = false,
			UIScale = nil,
		}
	end
end

function Config:_saveUserPrefs()
	local player = Library.GetLocalPlayer()
	local userId = player and player.UserId or 0
	return Library.WriteJson(prefsPath(userId), self.Prefs)
end

function Config:RegisterElement(flag, element, elementType)
	self.Elements[flag] = {
		Element = element,
		Type = elementType,
	}
	if element then
		pcall(function()
			element.IgnoreConfig = true
		end)
	end
end

function Config:SetValue(flag, value, opts)
	opts = opts or {}
	self.Values[flag] = Library.DeepCopy(value)

	if not opts.SkipModules and self.Hub and self.Hub.Modules and not self.Applying then
		self.Hub.Modules:OnFlagChanged(flag, value)
	end

	if not opts.SkipSettings and self.Hub and self.Hub.UI and typeof(self.Hub.UI.ApplySetting) == "function" then
		if string.sub(tostring(flag), 1, 9) == "Settings." then
			pcall(function()
				self.Hub.UI:ApplySetting(flag, value)
			end)
		end
	end

	if not opts.SkipUi and not self.Applying then
		self:ApplyToElement(flag, value, false)
	end
end

function Config:GetValue(flag, fallback)
	if self.Values[flag] == nil then
		return fallback
	end
	return self.Values[flag]
end

function Config:GetAllValues()
	return Library.DeepCopy(self.Values)
end

function Config:ApplyToElement(flag, value, fireCallback)
	local entry = self.Elements[flag]
	if not entry or not entry.Element then
		return
	end

	local element = entry.Element
	local elementType = entry.Type

	if elementType == "Toggle" then
		pcall(element.UpdateState, element, value == true)
		if fireCallback and typeof(element.Settings) == "table" and typeof(element.Settings.Callback) == "function" then
			pcall(element.Settings.Callback, value == true)
		end
	elseif elementType == "Slider" then
		pcall(element.UpdateValue, element, value)
		if fireCallback and typeof(element.Settings) == "table" and typeof(element.Settings.Callback) == "function" then
			pcall(element.Settings.Callback, value)
		end
	elseif elementType == "Input" then
		pcall(element.UpdateText, element, tostring(value or ""))
		if fireCallback and typeof(element.Settings) == "table" and typeof(element.Settings.Callback) == "function" then
			pcall(element.Settings.Callback, tostring(value or ""))
		end
	elseif elementType == "Dropdown" then
		pcall(element.UpdateSelection, element, value)
		if fireCallback and typeof(element.Settings) == "table" and typeof(element.Settings.Callback) == "function" then
			pcall(element.Settings.Callback, value)
		end
	end
end

function Config:SyncUiFromValues(fireCallbacks)
	self.Applying = true
	for flag, value in self.Values do
		self:ApplyToElement(flag, value, fireCallbacks == true)
	end
	self.Applying = false
	self:ApplyAllSettings()
end

function Config:ApplyAllSettings()
	if not self.Hub or not self.Hub.UI or typeof(self.Hub.UI.ApplySetting) ~= "function" then
		return
	end
	for flag, value in self.Values do
		if string.sub(tostring(flag), 1, 9) == "Settings." then
			pcall(function()
				self.Hub.UI:ApplySetting(flag, value)
			end)
		end
	end
end

function Config:CollectFromUi()
	for flag, entry in self.Elements do
		local element = entry.Element
		if element then
			if entry.Type == "Toggle" then
				local ok, state = pcall(function()
					if element.GetState then
						return element:GetState()
					end
					return element.State
				end)
				if ok then
					self.Values[flag] = state == true
				end
			elseif entry.Type == "Slider" then
				local ok, value = pcall(function()
					if element.GetValue then
						return element:GetValue()
					end
					return element.Value
				end)
				if ok then
					self.Values[flag] = value
				end
			elseif entry.Type == "Input" then
				local ok, text = pcall(function()
					if element.GetInput then
						return element:GetInput()
					end
					return element.Text
				end)
				if ok then
					self.Values[flag] = text
				end
			elseif entry.Type == "Dropdown" then
				local ok, value = pcall(function()
					return element.Value
				end)
				if ok then
					self.Values[flag] = value
				end
			end
		end
	end

	-- Always merge module state (covers derived flags like AutoClaim.Enabled with no UI element)
	if self.Hub and self.Hub.Modules then
		local exported = self.Hub.Modules:ExportValues()
		for flag, value in exported do
			if self.Elements[flag] == nil then
				self.Values[flag] = Library.DeepCopy(value)
			end
		end
	end

	return self:GetAllValues()
end

function Config:SeedDefaults(values)
	for flag, value in values do
		if self.Values[flag] == nil then
			self.Values[flag] = Library.DeepCopy(value)
		end
	end
end

function Config:ListConfigs()
	self:_loadIndex()
	local list = {}
	for _, entry in self.Index.Configs do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b)
		return tostring(a.Name) < tostring(b.Name)
	end)
	return list
end

function Config:GetDisplayNames()
	local names = {}
	for _, entry in self:ListConfigs() do
		local owner = entry.OwnerName or tostring(entry.OwnerUserId or "?")
		table.insert(names, ("%s  ·  %s"):format(entry.Name, owner))
	end
	return names
end

function Config:FindByDisplayName(displayName)
	for _, entry in self:ListConfigs() do
		local owner = entry.OwnerName or tostring(entry.OwnerUserId or "?")
		local label = ("%s  ·  %s"):format(entry.Name, owner)
		if label == displayName or entry.Name == displayName then
			return entry
		end
	end
	return nil
end

function Config:FindById(id)
	for _, entry in self:ListConfigs() do
		if entry.Id == id then
			return entry
		end
	end
	return nil
end

function Config:GetCurrentDisplayName()
	local entry = self:FindById(self.CurrentId)
	if not entry then
		return nil
	end
	local owner = entry.OwnerName or tostring(entry.OwnerUserId or "?")
	return ("%s  ·  %s"):format(entry.Name, owner)
end

function Config:Create(name)
	local player = Library.GetLocalPlayer()
	name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		return false, "Config name cannot be empty."
	end

	for _, entry in self:ListConfigs() do
		if entry.Name == name and entry.OwnerUserId == (player and player.UserId) then
			return false, "You already have a config with that name."
		end
	end

	self:CollectFromUi()

	local id = Library.GenerateId()
	local fileName = id .. ".json"
	local payload = {
		Meta = {
			Id = id,
			Name = name,
			OwnerUserId = player and player.UserId or 0,
			OwnerName = player and player.Name or "Unknown",
			CreatedAt = os.time(),
			UpdatedAt = os.time(),
			Version = Library.Version,
		},
		Values = self:GetAllValues(),
	}

	if not Library.WriteJson(configPath(fileName), payload) then
		return false, "Failed to write config file."
	end

	table.insert(self.Index.Configs, {
		Id = id,
		Name = name,
		OwnerUserId = payload.Meta.OwnerUserId,
		OwnerName = payload.Meta.OwnerName,
		File = fileName,
		UpdatedAt = payload.Meta.UpdatedAt,
	})
	self:_saveIndex()
	self.CurrentId = id
	self.Prefs.LastConfigId = id
	self:_saveUserPrefs()
	return true, payload.Meta
end

function Config:Save(id)
	id = id or self.CurrentId
	local entry = self:FindById(id)
	if not entry then
		return false, "No config selected. Create or Load one first."
	end

	self:CollectFromUi()
	local path = configPath(entry.File)
	local existing = Library.ReadJson(path, nil)
	if not existing then
		return false, "Config file missing."
	end

	existing.Values = self:GetAllValues()
	existing.Meta = existing.Meta or {}
	existing.Meta.UpdatedAt = os.time()
	existing.Meta.Version = Library.Version

	if not Library.WriteJson(path, existing) then
		return false, "Failed to save config."
	end

	entry.UpdatedAt = existing.Meta.UpdatedAt
	self:_saveIndex()
	self.CurrentId = entry.Id
	self.Prefs.LastConfigId = entry.Id
	self:_saveUserPrefs()
	return true, entry
end

function Config:Load(idOrDisplay, opts)
	opts = opts or {}
	local entry = typeof(idOrDisplay) == "table" and idOrDisplay
		or self:FindById(idOrDisplay)
		or self:FindByDisplayName(idOrDisplay)

	if not entry then
		return false, "Config not found."
	end

	local payload = Library.ReadJson(configPath(entry.File), nil)
	if not payload or typeof(payload.Values) ~= "table" then
		return false, "Config data is invalid."
	end

	self.Applying = true
	-- Keep any current defaults, then overlay saved values so every flag is present
	local merged = Library.DeepCopy(self.Values)
	for flag, value in payload.Values do
		merged[flag] = Library.DeepCopy(value)
	end
	self.Values = merged
	self.CurrentId = entry.Id
	self.Prefs.LastConfigId = entry.Id
	if typeof(self.Values["Settings.UIScale"]) == "number" then
		self.Prefs.UIScale = self.Values["Settings.UIScale"]
	end
	self:_saveUserPrefs()

	if self.Hub and self.Hub.Modules then
		self.Hub.Modules:ApplyValues(self.Values)
	end

	self.Applying = false
	self:SyncUiFromValues(false)
	return true, entry
end

function Config:Delete(id)
	local entry = self:FindById(id or self.CurrentId)
	if not entry then
		return false, "Config not found."
	end

	if Library.HasFileApi() and typeof(delfile) == "function" then
		pcall(delfile, configPath(entry.File))
	end

	local nextConfigs = {}
	for _, item in self.Index.Configs do
		if item.Id ~= entry.Id then
			table.insert(nextConfigs, item)
		end
	end
	self.Index.Configs = nextConfigs
	self:_saveIndex()

	if self.CurrentId == entry.Id then
		self.CurrentId = nil
	end
	if self.Prefs.LastConfigId == entry.Id then
		self.Prefs.LastConfigId = nil
		self.Prefs.AutoLoad = false
		self:_saveUserPrefs()
	end

	return true
end

function Config:SetAutoLoadConfig(idOrDisplay)
	local entry = typeof(idOrDisplay) == "table" and idOrDisplay
		or self:FindById(idOrDisplay)
		or self:FindByDisplayName(idOrDisplay)

	if not entry then
		return false, "Select a config in the dropdown first."
	end

	self.Prefs.AutoLoad = true
	self.Prefs.LastConfigId = entry.Id
	self.CurrentId = entry.Id
	self:_saveUserPrefs()
	return true, entry
end

function Config:TryAutoLoad()
	if self.Prefs.AutoLoad ~= true then
		return false
	end
	if self.Prefs.LastConfigId then
		local entry = self:FindById(self.Prefs.LastConfigId)
		if entry then
			return self:Load(entry.Id)
		end
	end
	return false
end

return Config
