local manifest = rbxmk.loadFile("manifest.lua")()
assert(type(manifest) == "table" and type(manifest.Modules) == "table", "manifest is invalid")

for name, path in pairs(manifest.Modules) do
	local ok, result = pcall(function() return rbxmk.loadFile(path)() end)
	assert(ok, string.format("module %s failed to compile (%s): %s", tostring(name), tostring(path), tostring(result)))
	assert(result ~= nil, string.format("module %s returned nil", tostring(name)))
end

print("Manifest compile tests passed")
