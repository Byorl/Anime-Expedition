return function()
	return {
		Name = "Anime Expeditions",
		Version = "1.4.2",
		PlaceId = 84515722934860,
		Repository = "https://github.com/Byorl/Anime-Expedition",
		RawBase = "https://jexvral.xyz/game/ap/",
		LoaderUrl = "https://jexvral.xyz/game/ap/loader",
		-- Pinned official MacLib release. A mutable /latest redirect can change API
		-- behavior without this project changing or passing validation.
		MacLibUrl = "https://github.com/biggaboy212/Maclib/releases/download/9.Maclib/maclib.txt",
		DataRoot = "AnimeExpeditionsHubData",
	}
end
