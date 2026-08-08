return function(Import)
	local Build = Import("Build")
	local Provider = {}
	local traceback = debug and debug.traceback or function(message) return tostring(message) end

	local function replaceOne(source, old, new, label)
		local first, last = string.find(source, old, 1, true)
		assert(first, "MacLib layout patch failed at " .. label)
		return string.sub(source, 1, first - 1) .. new .. string.sub(source, last + 1)
	end

	function Provider.PatchSource(source)
		source = string.gsub(source, "\r\n", "\n")
		source = replaceOne(source,
			"slider.Parent = section\n\n\t\t\t\t\tlocal sliderName",
			"slider.Parent = section\n\t\t\t\t\tslider.AutomaticSize = Enum.AutomaticSize.None\n\t\t\t\t\tslider.Size = UDim2.new(1, 0, 0, 58)\n\n\t\t\t\t\tlocal sliderName",
			"slider frame")
		source = replaceOne(source,
			"sliderName.Parent = slider\n\n\t\t\t\t\tlocal sliderElements",
			"sliderName.Parent = slider\n\t\t\t\t\tsliderName.AnchorPoint = Vector2.zero\n\t\t\t\t\tsliderName.Position = UDim2.fromOffset(0, 5)\n\n\t\t\t\t\tlocal sliderElements",
			"slider label")
		source = replaceOne(source,
			"sliderElements.Size = UDim2.fromScale(1, 1)\n\n\t\t\t\t\tlocal sliderValue",
			"sliderElements.Size = UDim2.new(1, 0, 0, 32)\n\t\t\t\t\tsliderElements.Position = UDim2.new(1, 0, 0, 23)\n\n\t\t\t\t\tlocal sliderValue",
			"slider controls")
		source = replaceOne(source,
			"local newBarWidth = (totalWidth - (padding + sliderValueWidth + sliderNameWidth + 20)) / baseUIScale.Scale",
			"local newBarWidth = math.max(48, (totalWidth - (padding + sliderValueWidth + 4)) / baseUIScale.Scale)",
			"slider width")
		source = replaceOne(source,
			"function SliderFunctions:UpdateName(Name)\n\t\t\t\t\t\tsliderName = Name",
			"function SliderFunctions:UpdateName(Name)\n\t\t\t\t\t\tsliderName.Text = Name",
			"slider name setter")
		return source
	end

	function Provider.Load()
		local source, lastError
		for attempt = 1, 3 do
			local ok, result = pcall(function() return game:HttpGet(Build.MacLibUrl) end)
			if ok and type(result) == "string" and #result > 10000 then source = result; break end
			lastError = ok and ("response was only " .. tostring(type(result) == "string" and #result or 0) .. " bytes") or result
			if attempt < 3 then task.wait(attempt * 0.2) end
		end
		assert(source, "Unable to download pinned MacLib source after 3 attempts: " .. tostring(lastError))
		source = Provider.PatchSource(source)
		local chunk, compileError = loadstring(source, "@MacLib")
		assert(chunk, "MacLib compile failed: " .. tostring(compileError))
		local ok, library = xpcall(chunk, traceback)
		assert(ok and type(library) == "table", "MacLib initialization failed: " .. tostring(library))
		return library
	end

	return Provider
end
