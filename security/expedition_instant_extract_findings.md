# Expedition instant-win vulnerability — findings and reproduction

Authorized security testing against the Anime Expeditions Summer Update build
(extraction: `exports/Anime Expedition Summer Update - Extracted`).
Reproduction: `expedition_instant_extract_poc.luau` in this folder.

## Confirmed vs inferred

Confirmed from the Summer Update extraction (client-visible code):

- The per-match `GameState` replica accepts client-sent event names. The client
  binds real buttons straight to it: `Continue`, `Extract`, `PickupOrb`,
  `SetNodeQueue`, `OnNodeArrived`, `PayloadStopped` (`LocalScript/0257
  ClientGameRequests`), plus `Next`, `Restart`, `Lobby` (`LocalScript/0248
  ClientGameReplica`) and `SetYen`.
- `Extract` is the "end this run and take the rewards" action
  (`ModuleScript/2686 BottomHUD`: "Are you sure you would like to end this
  run? You will receive all of the following rewards!"). Client-side it is
  gated to Checkpoint nodes only — that gate is UI-only.
- `Restart` is the results screen "Repeat Stage" button
  (`ModuleScript/2642 GameResults` -> `Actions.GameRestart(true)` ->
  `FireServer("Restart")`) and has no visible client or network cooldown.
- Transport is `ReplicatedStorage.RemoteEvents.ReplicaSignal` with
  `(replicaId, eventName, ...)` (`ModuleScript/3339 ReplicaClient`).
  `Nodes.ArgumentGuard` is type-sanitizing only (string length, UTF-8, NaN,
  table depth) — it performs no authorization and no state validation.
  The Nodes rate limit only covers `*_RequestNODE` identifiers, not
  `ReplicaSignal`.
- Expedition queues are `Parameters.Gamemode == "Expedition"` for all four
  maps (SchoolGrounds, FlowerForest, Dressrosa "Rose Kingdom", WestCity
  "East Town"), so one code path serves every expedition and difficulty.

Inferred (server code is not serialized in the client-visible place file):

- The server's Expedition dispatcher ends the run as a successful extraction
  whenever it receives `Extract`, without verifying Checkpoint presence,
  combat, or run progress.
- The Summer 2026 event pays a flat +250 Sand Dollar per completed expedition
  (matches the video: 9,183 -> 9,433 -> 9,683 across three instant wins).

## What the reference video shows, mapped to code

| Video observation | Code path |
| --- | --- |
| Victory screen seconds after entering, 0 kills / 0 damage / 0 yen | `GameState:FireServer("Extract")` accepted at run start |
| Empty "Gained Rewards" but "+250x Sand Dollar" | no nodes cleared; flat event completion bonus |
| "Repeat Stage" -> "Teleporting... Flower Forest" -> instant win again | `GameState:FireServer("Restart")` relaunches with no cooldown |

## Root cause

The GameState replica is a client-trusted command channel. The event name is a
client-controlled string dispatched server-side with only shape sanitization.
Security-relevant state transitions (ending a run, restarting it, and the
reward payout keyed to them) trust the client's claim instead of server-owned
state (current node type, payload progress, combat statistics).

## Minimal manual reproduction (no script)

1. Queue any expedition (School Grounds, Flower Forest, Rose Kingdom, East
   Town — any difficulty) and start the run.
2. As soon as the run is active (enemies spawning), run:
   ```lua
   local Nodes = require(game:GetService("ReplicatedStorage"):WaitForChild("Nodes"))
   Nodes.GET_GAME_REPLICA:InvokeSelf():FireServer("Extract")
   ```
3. The Victory screen appears with empty stats and +250 Sand Dollar.
4. Click "Repeat Stage" (or run `:FireServer("Restart")` on the same replica)
   and repeat from step 2.

## Using the PoC script

1. Open the executor while in the Anime Expeditions lobby or inside an
   expedition.
2. Run `expedition_instant_extract_poc.luau`.
3. It detects the expedition `GameState` replica (via `GAME_REPLICA_LOADED` or
   by grabbing an already-running match), waits ~1.5 s after the run becomes
   active, sends `Extract`, waits for the results, sends `Restart`
   (Repeat Stage), and loops — on every map and difficulty, solo or in a
   party. If a relaunched run never becomes active, it sends the same
   `StartGame` request the Start button uses (`PARTY_GET_CURRENT_REPLICA:
   FireServer("StartGame")`) as a fallback.
4. It stops after `CONFIG.MAX_WINS` cycles (default 25); set
   `_G.EXPLOIT_POC_STOP = true` to stop early. Each cycle prints the map name
   and the `Extract`/`Restart` sends as evidence.

## Additional exposed surface (same channel, lower confidence)

These are client-reachable on the same replica / remotes and deserve server
review; they are not confirmed exploitable:

- `FireServer("SetYen", amount)` — the sandbox "Set Yen" binding
  (`ClientGameRequests` `Game_SetYen`). If the handler does not gate on a
  sandbox gamemode, this is direct currency injection.
- `FireServer("OnNodeArrived", cframe)` and `("SetNodeQueue", path)` — client
  reports node arrival and chooses the upcoming node path; forging these can
  steer progression (e.g. park at a Checkpoint to make Extract look
  legitimate).
- `Nodes` `_updateNode` in general: any registered node identifier is
  fireable from any client (`ReplicatedStorage.Nodes` handler fires the
  node's server Signal after type checks only).
- `CmdrFunction` / `CmdrEvent` — verify server-side admin/group checks on
  every registered command.

## Daily event-currency cap (fishing rank) — why it cannot be skipped client-side

The "+250x Sand Dollar" on each instant win is the fishing-rank bonus
`AdditionalCurrency` (`ModuleScript/3891 FishingRanks`): ranks 4-6 (Veteran /
Master / Grandmaster) grant +250 event currency per non-event win, capped per
day at `CurrencyCap` 5,000 / 7,500 / 10,000 (the FishingRankBanner text:
"Earn +250 event currency from winning any non-event gamemode, up to N per
day!"). The `[AE_CAP_RANK]` console lines print the server enforcing it; the
cap counter lives in server-owned player data, and the client never sends the
payout amount, so there is nothing to forge — the only client-visible state is
display config.

The two levers that do exist:

1. **Raise the cap via fishing rank.** Rank EXP comes from caught fish
   (RarityToExp) and the minigame result is client-reported:
   `LocalScript/0287 ClientFishingHandler` answers the Reeling stage with
   `Nodes.FISHING_RESULT:FireServer(true)` — a bare boolean (the same shape
   the legitimate `SkipMinigame` path sends). Reproduction:
   `fishing_result_trust_poc.luau` (cast -> wait for the replicated
   "Reeling" stage -> report success -> repeat). Grandmaster doubles the
   daily cap to 10,000 and fish themselves pay event currency outside the
   win-bonus cap.
2. **Farm uncapped rewards.** Expedition node rewards (Yen, MapResource,
   ExpeditionCoin, EquipmentScrap, ExpeditionFuel, Tomes, Payload/Player EXP)
   are granted per cleared node and are not part of the daily win bonus.

## Why the loop does not produce node rewards — and why that is by design

Instant-extract wins show an empty "Gained Rewards" list because node rewards
are paid per *cleared* node, and node completion (encounters, bosses, payload)
is resolved by server-simulated combat. Unlike the win/extract flow, there is
no client-sent "node complete" event to forge — the client only reports
arrival (`OnNodeArrived`), path choice (`SetNodeQueue`) and payload stops
(`PayloadStopped`), none of which complete a node. Accumulating real node
rewards requires real clears; the exploit can only shorten the loop around
them.

## v2 loop behavior (auto-start and instant mode)

`expedition_instant_extract_poc.luau` v2:

- Sends `Extract` the moment the expedition replica appears (pre-start test)
  and logs whether the server honors it before the run activates; if not, it
  falls back to the normal wait-for-active flow automatically.
- Relaunches with `Restart` (Repeat Stage) plus `StartGame` on the party
  replica every cycle — no manual clicks after the first run is started once.
- Polls at 0.05s with minimal fixed delays; `_G.EXPLOIT_POC_STOP` stops it;
  `CONFIG.MAX_WINS` defaults to 100 and can be raised.

## Rollback research — can spends be reverted by rejoining?

Harness: `rollback_research_harness.luau` (ARM mode snapshots `ItemData`
balances — Gem, TraitReroll, Gold, StatReroll — then disconnects the client
the instant a spend is detected; after rejoining, VERIFY mode compares and
reports whether the spends persisted).

Confirmed from the extraction:

- Balances are `PlayerData` replica paths `ItemData.<Name>.Amount`.
- There is no client-to-server data-write primitive: `ReplicaWrite`,
  `ReplicaSet*` remotes are server-to-client only, and the client's local
  `Set()`/`Write()` are optimistic writes gated by server-authorized
  WriteLibs.
- There is no client-triggered "reload profile from DataStore" node.
- `TESTING_RESET_DATA` (`LocalScript/0236 MountSettingsMenu`) is the settings
  "Reset ALL Data" button — an **irreversible wipe**, explicitly not a
  rollback. Do not fire it expecting data to return.
- Cmdr commands reach the server as raw text through
  `ReplicatedStorage.CmdrClient.CmdrFunction:InvokeServer(commandText,
  {Data})`. The server permission gate is its BeforeRun hook; strength
  unknown. Registered `Custom` commands include `SetItemAmount <userId>
  <item> <amount>` and `ResetExpeditionData`. The harness contains a
  net-zero probe (`CONFIG.PROBE_CMDR`) that sets Gem to its current amount —
  a block proves the gate holds, a success proves server data mutation is
  client-reachable (which would supersede rollback entirely).

Rollback hypotheses, ranked:

1. **Save-debounce race (testable with the harness).** If the server batches
   saves, spending and disconnecting inside the window loses the spends. The
   harness disconnects within ~0.1s of the first spend. If the server saves
   synchronously on PlayerRemoving (ProfileService-style), this fails —
   that is a finding too.
2. **Cmdr `SetItemAmount` reachability.** Not a rollback: a direct write.
   Probe is net-zero by design.
3. **Sell-table replay (not automated).** `UNIT_SELL_TABLE:FireServer(...)`
   and `SKIN_SELL_TABLE` accept lists of unit ids; if the server credits
   currency per list entry but deduplicates removals differently, a list
   containing the same id repeatedly could pay multiple times for one unit.
   Test manually with a trash unit before trusting it.
4. **Session-lock steal on fast rejoin.** If the persistence library
   discards a save when a new server steals the session lock, a
   spend-then-instant-rejoin could roll back. Same harness experiment as
   (1) but rejoining into a second client; only worth testing if (1) shows
   partial persistence.

## Remediation (data integrity additions)

8. Serialize spends and saves: apply currency/item mutations transactionally
   with the save queue, or force a save immediately after any
   premium-currency mutation.
9. Ensure the Cmdr BeforeRun hook denies every `Custom` command for normal
   players (`SetItemAmount`, `ResetExpeditionData`, `ResetDataKey`, the
   `Summer*` debug commands) and add per-command group checks.
10. Deduplicate and validate ids in list-based remotes (`UNIT_SELL_TABLE`,
    `SKIN_SELL_TABLE`, `UNIT_FEED`) server-side: one removal per unique id,
    currency credited strictly from removed items.

## Remediation (original findings, updated)

1. Make run termination server-authoritative: only honor `Extract` when
   server-owned state says the party is at a Checkpoint node with a
   completed encounter history. Reject otherwise (and log).
2. Rate limit and cooldown `Restart`/`Next`/`Lobby` per party server-side;
   reject when the game is active. Treat `StartGame` during an active run
   the same way.
3. Server-validate fishing: the `FISHING_RESULT` boolean must only be
   accepted inside a server-initiated reel minigame for that player, with a
   server-side bite timer and per-cast cooldown; better, resolve the reel
   server-side like the rest of combat.
4. Gate `SetYen` (and similar debug affordances) to a sandbox-only gamemode
   flag checked on the server.
5. Validate `OnNodeArrived`/`SetNodeQueue` against server-simulated
   progression (distance traveled, node graph adjacency), or move the
   progression state machine fully server-side.
6. Add server-side anomaly telemetry: win-with-zero-combat-stats, extraction
   latency below a floor, repeat-cycle cadence, catch results arriving
   without a minigame — all trivially detectable.
7. Re-run both PoCs after patching; the regression tests are "Extract at
   wave 1 must be rejected" and "`FISHING_RESULT(true)` outside a server
   minigame must be rejected".
