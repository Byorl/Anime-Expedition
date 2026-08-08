local files, folders = {}, {}
FAIL_PRIMARY = nil

isfile = function(path) return files[path] ~= nil end
readfile = function(path) if files[path] == nil then error("missing") end return files[path] end
writefile = function(path, data)
	if FAIL_PRIMARY == path then
		FAIL_PRIMARY = nil
		files[path] = "CORRUPTED_PARTIAL_WRITE"
		error("simulated write failure")
	end
	files[path] = data
end
delfile = function(path) files[path] = nil end
isfolder = function(path) return folders[path] == true end
makefolder = function(path) folders[path] = true end
listfiles = function() return {} end

local HttpService = {}
function HttpService:JSONEncode(value) return "VALID:" .. tostring(value.Revision) end
function HttpService:JSONDecode(raw)
	local revision = tonumber(string.match(raw, "^VALID:(%d+)$"))
	if not revision then error("invalid JSON") end
	return {Revision = revision}
end
game = {GetService = function(_, name) assert(name == "HttpService") return HttpService end}

local cache = {}
local factories = {
	Util = rbxmk.loadFile("src/Core/Util.lua")(),
	FileSystem = rbxmk.loadFile("src/Core/FileSystem.lua")(),
}
local function Import(name)
	if cache[name] then return cache[name] end
	cache[name] = factories[name](Import)
	return cache[name]
end

local store = Import("FileSystem").new("Test")
assert(store.Available, "mock executor filesystem was not detected")
local path = "Test/config.json"

local ok, err = store:WriteJson(path, {Revision = 1})
assert(ok, err)
assert(files[path] == "VALID:1" and files[path .. ".tmp"] == nil, "initial transaction did not commit cleanly")

ok, err = store:WriteJson(path, {Revision = 2})
assert(ok, err)
assert(files[path] == "VALID:2" and files[path .. ".bak"] == "VALID:1", "backup was not preserved")

files[path] = "CORRUPTED"
local recovered, source = store:ReadJsonDetailed(path)
assert(recovered.Revision == 1 and source == path .. ".bak", "backup recovery failed")
assert(files[path] == "VALID:1", "recovery did not repair primary")

files[path] = "CORRUPTED"
files[path .. ".tmp"] = "VALID:3"
recovered, source = store:ReadJsonDetailed(path)
assert(recovered.Revision == 3 and source == path .. ".tmp", "interrupted temp recovery failed")

files[path .. ".tmp"] = nil
FAIL_PRIMARY = path
ok, err = store:WriteJson(path, {Revision = 4})
assert(not ok and string.find(err, "backup restored", 1, true), "failed write did not report rollback")
assert(files[path] == "VALID:3", "failed write did not restore last good primary")

print("FileSystem tests passed")
