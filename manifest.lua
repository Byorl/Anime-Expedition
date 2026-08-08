return {
	Version = "1.1.0",
	Entry = "Main",
	Modules = {
		Build = "src/Build.lua",
		Util = "src/Core/Util.lua",
		Janitor = "src/Core/Janitor.lua",
		FileSystem = "src/Core/FileSystem.lua",
		ControlRegistry = "src/Core/ControlRegistry.lua",
		ConfigManager = "src/Core/ConfigManager.lua",
		SessionManager = "src/Core/SessionManager.lua",
		ModuleManager = "src/Core/ModuleManager.lua",
		MacLibProvider = "src/Core/MacLibProvider.lua",
		Misc = "src/Modules/Misc.lua",
		Settings = "src/Modules/Settings.lua",
		Main = "src/Main.lua",
	},
}
