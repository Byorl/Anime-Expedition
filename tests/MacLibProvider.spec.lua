local factory = rbxmk.loadFile("src/Core/MacLibProvider.lua")()
local Provider = factory(function(name)
	assert(name == "Build", "unexpected import")
	return {MacLibUrl = ""}
end)

local source = [[return function()
					slider.Parent = section

					local sliderName = {}
					sliderName.Parent = slider

					local sliderElements = {}
					sliderElements.Size = UDim2.fromScale(1, 1)

					local sliderValue = {}
					local newBarWidth = (totalWidth - (padding + sliderValueWidth + sliderNameWidth + 20)) / baseUIScale.Scale
					function SliderFunctions:UpdateName(Name)
						sliderName = Name
					end
end]]
local patched = Provider.PatchSource(source)
assert(string.find(patched, "slider.Size = UDim2.new(1, 0, 0, 58)", 1, true), "slider row was not expanded")
assert(string.find(patched, "sliderElements.Position = UDim2.new(1, 0, 0, 23)", 1, true), "slider controls were not moved below the label")
assert(string.find(patched, "math.max(48, (totalWidth - (padding + sliderValueWidth + 4))", 1, true), "slider track did not receive a safe minimum width")
assert(not string.find(patched, "sliderNameWidth + 20", 1, true), "old overlapping slider width calculation remains")
local fileOk, actualSource = pcall(fs.read, "../../tools/vendor/Maclib/maclib.txt", "bin")
if fileOk then
	local actualPatched = Provider.PatchSource(actualSource)
	assert(string.find(actualPatched, "slider.Size = UDim2.new(1, 0, 0, 58)", 1, true), "real MacLib slider row was not expanded")
	assert(not string.find(actualPatched, "sliderNameWidth + 20", 1, true), "real MacLib retained the overlapping calculation")
end

print("MacLib provider tests passed")
