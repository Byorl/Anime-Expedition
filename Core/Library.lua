local Hub = ...

local Library = {}

Library.Version = "1.0.0"
Library.Name = "AEHub"
Library.DataFolder = "AEHubData"
Library.ConfigsFolder = "AEHubData/Configs"
Library.PrefsFolder = "AEHubData/Prefs"
Library.TrackFolder = "AEHubData/Track"

function Library.GetEnv()
	return (getgenv and getgenv()) or shared or _G
end

function Library.GetServices()
	return {
		Players = game:GetService("Players"),
		HttpService = game:GetService("HttpService"),
		ReplicatedStorage = game:GetService("ReplicatedStorage"),
		RunService = game:GetService("RunService"),
		UserInputService = game:GetService("UserInputService"),
		CoreGui = game:GetService("CoreGui"),
	}
end

function Library.GetLocalPlayer()
	return game:GetService("Players").LocalPlayer
end

function Library.HasFileApi()
	return typeof(isfile) == "function"
		and typeof(readfile) == "function"
		and typeof(writefile) == "function"
		and typeof(makefolder) == "function"
end

function Library.EnsureFolders()
	if not Library.HasFileApi() then
		return false
	end
	pcall(makefolder, Library.DataFolder)
	pcall(makefolder, Library.ConfigsFolder)
	pcall(makefolder, Library.PrefsFolder)
	pcall(makefolder, Library.TrackFolder)
	return true
end

function Library.PathExists(path)
	return Library.HasFileApi() and isfile(path)
end

function Library.ReadJson(path, fallback)
	if not Library.PathExists(path) then
		return fallback
	end
	local ok, decoded = pcall(function()
		return game:GetService("HttpService"):JSONDecode(readfile(path))
	end)
	if ok and typeof(decoded) == "table" then
		return decoded
	end
	return fallback
end

function Library.WriteJson(path, data)
	if not Library.HasFileApi() then
		return false
	end
	Library.EnsureFolders()
	local ok, encoded = pcall(function()
		return game:GetService("HttpService"):JSONEncode(data)
	end)
	if not ok then
		return false
	end
	local writeOk = pcall(writefile, path, encoded)
	return writeOk
end

function Library.ListFiles(folder)
	if typeof(listfiles) ~= "function" then
		return {}
	end
	local ok, files = pcall(listfiles, folder)
	if ok and typeof(files) == "table" then
		return files
	end
	return {}
end

function Library.DeepCopy(value)
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, nested in value do
		copy[Library.DeepCopy(key)] = Library.DeepCopy(nested)
	end
	return copy
end

function Library.MergeDefaults(defaults, values)
	local result = Library.DeepCopy(defaults or {})
	if typeof(values) ~= "table" then
		return result
	end
	for key, value in values do
		if typeof(value) == "table" and typeof(result[key]) == "table" then
			result[key] = Library.MergeDefaults(result[key], value)
		else
			result[key] = Library.DeepCopy(value)
		end
	end
	return result
end

function Library.GenerateId()
	local HttpService = game:GetService("HttpService")
	local ok, id = pcall(function()
		return HttpService:GenerateGUID(false)
	end)
	if ok and typeof(id) == "string" then
		return id
	end
	return tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
end

function Library.Notify(window, title, description)
	if window then
		local ok = pcall(function()
			window:Notify({
				Title = title or "AEHub",
				Description = description or "",
			})
		end)
		if ok then
			return
		end
	end
	print(("[AEHub] %s: %s"):format(tostring(title), tostring(description)))
end

function Library.DestroyUiInstances()
	local targets = {}
	local function collect(parent)
		if not parent then
			return
		end
		for _, child in parent:GetChildren() do
			local name = child.Name
			if name == "MaclibGui"
				or name == "MacLib"
				or name == "AEHub"
				or child:GetAttribute("AEHub") == true
			then
				table.insert(targets, child)
			end
		end
	end

	pcall(function()
		collect(game:GetService("CoreGui"))
	end)
	pcall(function()
		local player = Library.GetLocalPlayer()
		if player then
			collect(player:FindFirstChild("PlayerGui"))
		end
	end)

	for _, instance in targets do
		pcall(function()
			instance:Destroy()
		end)
	end
end

return Library
