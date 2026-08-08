# Anime Expedition

GitHub-loaded MacLib framework for Anime Expeditions. Code is split into real remote modules; the loader prefetches them with a bounded worker pool and initializes them from the repository manifest.

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
    GameAdapter.lua
    Janitor.lua
    MacLibProvider.lua
    ModuleManager.lua
    SessionManager.lua
    UIManager.lua
    Util.lua
    RewardScanner.lua
  Modules/
    AutoClaim.lua
    Misc.lua
    Performance.lua
    Settings.lua
```

`manifest.lua` is the single source of truth for module names and paths. Each module returns a factory and imports dependencies through the loader-provided `Import` function. Imports are cached for one runtime and circular dependencies are rejected.

## Config model

- Global configs: `AnimeExpeditionsHubData/configs/global`
- Per-account state: `AnimeExpeditionsHubData/accounts/<UserId>/state.json`
- All accounts can select globally created configs.
- Schema 3 separates per-account UI/session preferences from globally selectable feature profiles.
- Config metadata records `Revision`, `SavedAt`, creator, last-saving account and optional lock ownership.
- `main` is created automatically when no configs exist.
- Deletion is blocked when only one config remains.
- Configs can be duplicated, renamed and locked; names collide case-insensitively.
- Auto Save covers every stateful element registered through `ControlRegistry`.
- Config loads run as transactions, hold autosave callbacks until deferred MacLib setters settle, and roll back on failure.
- Writes use verified `.tmp.json` and `.bak.json` sidecars (compatible with executor extension allowlists) and repair the primary JSON automatically after corruption/interruption.
- Dirty autosaves are flushed before re-execution and teleport, while Auto Save off still requires the Save button.

## Runtime modules

Feature modules support `Init`, `Enable`, `Disable`, and `Unload`, plus dependency-aware loading. The manager validates the complete dependency graph, reports cycle paths and lifecycle tracebacks, rolls back failed starts, scopes registered controls to their owning module, and unloads in reverse dependency order.

```lua
local runtime = getgenv().__ANIME_EXPEDITIONS_RUNTIME
runtime.Modules:Unload("Misc")
runtime.Modules:Load("Misc")
```

Re-execution shuts down the previous runtime, disconnects tracked events, disables MacLib's old global key listener, destroys the previous UI, and then creates the new runtime.

## Misc automation

- `AutoClaim` reads the same replicated state used by the game's calendar, quest, battlepass, index, milestone, expedition, event and tournament UIs before sending a claim.
- Claim signatures and bounded retries stop an unchanged reward from being spammed while still recovering from a dropped event.
- Codes are discovered from both static and live-synced game information, filtered by their active window, requested serially and cached per account.
- `Performance` owns Delete Enemies, FPS Boost and Disable 3D Rendering. Enemy visuals are selected by the game's `Enemy` CollectionService tag; all listeners are disconnected on toggle-off, unload and re-execution.
- FPS Boost keeps original properties in a weak-key table and restores surviving instances when disabled, avoiding strong references to destroyed map content.

## Responsive UI

- Desktop starts at a smaller 800x600 base with a 90% default scale.
- Mobile uses a compact 620x465 base with a separate 62% preference and an automatic viewport-fit cap, including orientation changes.
- Scale writes are coalesced through one render-step writer with damped/capped changes to prevent slider feedback jitter.
- Desktop and mobile scale preferences are stored independently per account.
- MacLib global settings default to UI Blur off and Hide Private Info on.
- The official MacLib source is pinned to the tested `9.Maclib` release instead of a mutable latest-release URL.

## Session behavior

- Auto Execute queues the GitHub loader URL, not a local script.
- A per-teleport guard prevents duplicate queued executions.
- Disabling Auto Execute after it was queued is respected through per-account state.
- Auto Reconnect retries place `84515722934860` with bounded backoff.
- Hide UI on Execute is applied after the selected config is restored.
