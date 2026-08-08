# Anime Expedition

GitHub-loaded MacLib framework for Anime Expeditions. Code is split into real remote modules; the loader downloads the manifest and every module from this repository at execution time.

## Loadstring

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Byorl/Anime-Expedition/main/loader.lua"))()
```

No local code file is required. Local filesystem access is used only for persistent user configs because those must survive between executions.

## Module tree

```text
loader.lua
manifest.lua
src/
  Build.lua
  Main.lua
  Core/
    ConfigManager.lua
    ControlRegistry.lua
    FileSystem.lua
    Janitor.lua
    MacLibProvider.lua
    ModuleManager.lua
    SessionManager.lua
    Util.lua
  Modules/
    Misc.lua
    Settings.lua
```

`manifest.lua` is the single source of truth for module names and paths. Each module returns a factory and imports dependencies through the loader-provided `Import` function. Imports are cached for one runtime and circular dependencies are rejected.

## Config model

- Global configs: `AnimeExpeditionsHubData/configs/global`
- Per-account state: `AnimeExpeditionsHubData/accounts/<UserId>/state.json`
- All accounts can select globally created configs.
- Config metadata records the creator and last-saving account.
- `main` is created automatically when no configs exist.
- Deletion is blocked when only one config remains.
- Auto Save covers every stateful element registered through `ControlRegistry`.
- Config loads call MacLib setters and feature callbacks, restoring visual and live state together.

## Runtime modules

Feature modules support `Init`, `Enable`, `Disable`, and `Unload`, plus dependency-aware loading. Normal unload deactivates a module and cleans its tracked resources without duplicating its UI when it is reloaded.

```lua
local runtime = getgenv().__ANIME_EXPEDITIONS_RUNTIME
runtime.Modules:Unload("Misc")
runtime.Modules:Load("Misc")
```

Re-execution shuts down the previous runtime, disconnects tracked events, disables MacLib's old global key listener, destroys the previous UI, and then creates the new runtime.

## Session behavior

- Auto Execute queues the GitHub loader URL, not a local script.
- A per-teleport guard prevents duplicate queued executions.
- Disabling Auto Execute after it was queued is respected through per-account state.
- Auto Reconnect retries place `84515722934860` with bounded backoff.
- Hide UI on Execute is applied after the selected config is restored.
