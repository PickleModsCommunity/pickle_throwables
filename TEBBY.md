# TEBBY.md - pickle_throwables

## Overview

`pickle_throwables` is a FiveM resource that lets players pick up, hold, throw, kick, drop, and hand off throwable objects (footballs, basketballs, baseballs, soccer balls) in GTA V. It is multi-framework (ESX, QBCore, or standalone) and uses `ox_lib` for UI. Items can be dispensed via usable inventory items or via a server command (`/spawnthrowable`) when command-spawning mode is enabled.

---

## Code design

**Architecture — client/server split with a bridge layer**

- **`config.lua`** (shared) — defines all throwable types, render/catch distances, and the command-spawning toggle. Loaded by both client and server via `shared_scripts`.
- **`core/shared.lua`** (shared) — tiny utility functions (`v3`, `GetRandomInt`) available everywhere.
- **`core/client.lua`** (client) — model-loading helpers (`ModelRequest`, `CreateProp`, `CreateVeh`, `CreateNPC`), `PlayAnim`, and the `ShowInteractText` wrapper around `ox_lib`'s `lib.showTextUI`.
- **`modules/throwables/client.lua`** — the bulk of the gameplay logic: holding, throwing, kicking, dropping, catching, giving, and the main render-loop thread.
- **`modules/throwables/server.lua`** — authoritative state: `Throwables` (in-flight objects) and `Carrying` (which player holds which object). All item addition/removal and all object hand-offs go through server callbacks.
- **`bridge/<framework>/client.lua` / `server.lua`** — thin adapters. Loaded conditionally by checking `GetResourceState`. The standalone bridge only prints a warning; it does not stub functions, so unsupported frameworks will crash at any bridge function call.
- **`locales/`** — translation loader (`locale.lua`) and per-language tables (`translations/*.lua`). `_L(key, ...)` returns `ERR_TRANSLATE_<key>_404` if a key is missing.

**Main gameplay flow**

1. Player uses an inventory item (or `/spawnthrowable`) → server `RegisterUsableItem` / `RegisterCommand` → `GiveObject(source, data)` sets `Carrying[source]` and fires `pickle_throwables:giveObject` to that client.
2. Client receives event → `HoldThrowable(throwType)` → spawns a prop attached to the player's right-hand bone and enters a `while holdingBall` loop.
3. Inside the loop, player can:
   - **[E] Throw** — plays throw anim, detaches prop, calls `pickle_throwables:throwObject` server event (which moves ownership to the `Throwables` table and broadcasts `setObjectData` to all clients).
   - **[G] Drop/Kick** — detaches and applies low physics; also fires `pickle_throwables:throwObject`.
   - **[H] Handoff / Inventory** — calls `giveObject` (to a nearby player) or `storeObject` (back to inventory) server callbacks.
4. All clients' main render thread watches `Throwables`, renders interaction UI when within `Config.CatchRadius`, and lets players catch (`pickle_throwables:catchObject` callback) or kick in-flight objects.
5. Server callbacks (`catchObject`, `storeObject`, `giveObject`) are the only places that mutate `Carrying` and `Throwables`, ensuring one authoritative state.

**Throwing power** — an integer 1–10, controlled by scroll-up/scroll-down (controls 181/180). Multiplied by `(cfg.maxThrowingPower / 10)` to get the final velocity applied via `SetEntityVelocity`.

**Network entity lifecycle** — the throwing player creates the prop locally (client-authoritative entity), immediately calls `ObjToNet` to get a network ID, and broadcasts that ID via `pickle_throwables:throwObject`. Other clients call `NetToObj` on that ID. The server deletes the entity (via `NetworkGetEntityFromNetworkId`) when it is caught or stored.

---

## Important files

| Path | Why it matters |
|------|---------------|
| `fxmanifest.lua` | Resource manifest; defines load order and which scripts are shared/client/server. |
| `config.lua` | All user-editable settings: throwable definitions (model, item, maxThrowingPower), distances, command-spawning toggle. |
| `core/shared.lua` | Shared utility functions available to all contexts. |
| `core/client.lua` | Model-loading helpers and the `ShowInteractText` wrapper (ox_lib UI). |
| `modules/throwables/client.lua` | All client gameplay: hold loop, throw/kick/drop/catch/give logic, render thread. |
| `modules/throwables/server.lua` | Authoritative object state (`Throwables`, `Carrying`), all callbacks, item registration. |
| `bridge/esx/client.lua` | ESX client bridge: `ServerCallback`, `ShowNotification`, `GetPlayersInArea`, `CanAccessGroup`. |
| `bridge/esx/server.lua` | ESX server bridge: `RegisterCallback`, `RegisterUsableItem`, `AddItem`, `RemoveItem`, `Search`, `GetIdentifier`. |
| `bridge/qb/client.lua` | QBCore client bridge (mirrors ESX client). |
| `bridge/qb/server.lua` | QBCore server bridge (mirrors ESX server). |
| `bridge/standalone/client.lua` | Standalone stub — only prints a warning; no functions are defined. |
| `bridge/standalone/server.lua` | Standalone stub — only prints a warning; no functions are defined. |
| `locales/locale.lua` | `_L()` helper; returns `ERR_TRANSLATE_<key>_404` for missing keys. |
| `locales/translations/en.lua` | English locale strings (the only three UI strings). |
| `locales/translations/de.lua` | German locale strings. |
| `_INSTALL/Items/ox_inventory.lua` | Item definitions for ox_inventory. |
| `_INSTALL/Items/qbcore.lua` | Item definitions for QBCore shared items. |
| `_INSTALL/Items/esx_limit.sql` / `esx_weight.sql` | SQL item inserts for ESX. |

---

## Intended behaviors

- **Standalone bridge prints a warning, not an error.** `bridge/standalone/client.lua` and `bridge/standalone/server.lua` only `print(...)` and return nothing. Any call to `RegisterCallback`, `AddItem`, `RemoveItem`, `RegisterUsableItem`, etc. will be a nil-call crash on a truly standalone server unless the operator fills in these functions manually. This is intentional — the resource is not designed to run frameworkless out of the box; the print is the operator's cue to implement the bridge.
- **`Config.CommandSpawnCheck` always returns `true` by default.** This is the intended open default; servers that enable `Config.CommandSpawning` are expected to override `Config.CommandSpawnCheck` with their own permission logic.
- **Commented-out kick animation code** in `modules/throwables/client.lua` (lines around `PerformPhysics(v.throwType, prop, "kick")`). The `FreezeEntityPosition` / `PlayAnim` / `ClearPedTasks` block for kicking is commented out intentionally — the animation conflicted with physics and was left disabled by the author. The kick still applies velocity via `PerformPhysics` with `action = "kick"` (uses `dir.z * 1.75`); only the visual animation is suppressed.
- **QBCore bank balance stubs.** In `bridge/qb/server.lua`, `Search`, `AddItem`, and `RemoveItem` for `"bank"` all fall back to `"cash"`. Comment lines say "If anyone knows how to get bank balance for QBCore, let me know." This is a known limitation, not a bug.
- **`throwObject` server event requires `Carrying[source]`** — if a player fires `pickle_throwables:throwObject` without first being in `Carrying` (e.g. exploiting), the event returns immediately. This is an intentional lightweight anti-exploit guard.
- **Prop creation is client-authoritative.** The throwing client creates the GTA entity locally before telling the server. This is normal for FiveM throwable/prop resources and is not a synchronisation bug — the net ID is immediately shared.

---

## Common issues & fixes

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Locale strings show as `ERR_TRANSLATE_<key>_404` | `Config.Language` doesn't match a key in `locales/translations/`. | Set `Config.Language = "en"` (or `"de"`) in `config.lua`, or add a matching translation file. |
| Items are not usable / throwable never activates | Item not registered in the inventory resource. | Import the correct file from `_INSTALL/Items/` for your inventory (ox_inventory, QBCore, or ESX SQL). |
| `attempt to call a nil value` on `RegisterCallback` / `AddItem` etc. | Neither ESX nor QBCore is running, so the standalone stub loaded and defined nothing. | Either start a supported framework or manually implement the bridge functions in `bridge/standalone/server.lua` and `bridge/standalone/client.lua`. |
| `/spawnthrowable` command not available | `Config.CommandSpawning = false` (the default). | Set `Config.CommandSpawning = true` in `config.lua`. |
| Throwable object invisible or desynced for other players | The net ID broadcast (`setObjectData`) arrived before other clients streamed in the entity. | This can happen on high-latency connections; `Config.RenderDistance` controls when clients try to resolve the net ID. Lowering it can mask the issue but is not a full fix — it is a known FiveM entity streaming race. |
| Object stays in world after resource restart | `onResourceStop` deletes all entries in `Throwables` client-side, but only for the client that processes the event. If the throwing client disconnected, the entity may linger. | Restart the resource or have a server-side cleanup on `playerDropped` if this is a recurring problem. |
| `maxThrowingPower` has no effect | The model hash (backtick literal, e.g. `` `p_ld_am_ball_01` ``) must resolve correctly in Lua 5.4 with FiveM's hash literals. If the model can't be found (`IsModelInCdimage` returns false), `CreateProp` returns nil silently. | Verify the model name against the GTA V model list and ensure the DLC containing the model is loaded. |
| Kick animation not playing | Intentionally commented out (see Intended behaviors). | Only affects visuals; physics still apply. Re-enable the commented block in `modules/throwables/client.lua` if desired and test for animation conflicts. |

---

## Conventions

- **Lua 5.4** — `fxmanifest.lua` sets `lua54 'yes'`. Safe-navigation (`?.`) and other Lua 5.4 syntax is used (e.g. `closest?.player`).
- **`Config` global table** — all config lives in `Config` (shared). Never split config between client and server files.
- **`_L(key, ...)` for all UI strings** — no hardcoded English strings in module files; everything goes through the locale helper.
- **Bridge pattern** — framework-specific calls must only appear inside `bridge/<framework>/`. Module code calls generic functions (`RegisterCallback`, `AddItem`, `RemoveItem`, `RegisterUsableItem`, `ServerCallback`, `ShowNotification`). Adding a new framework means creating `bridge/<name>/client.lua` and `bridge/<name>/server.lua` with the same guards (`if GetResourceState(...) ~= 'started' then return end`).
- **Module glob loading** — `fxmanifest.lua` uses `modules/**/client.lua`, `modules/**/server.lua`, and `modules/**/shared.lua`. New modules must live under `modules/<name>/` and follow this naming.
- **No `shared.lua` in throwables module** — the throwables module has no shared file; shared utilities live in `core/shared.lua` and `config.lua`.
- **Snake_case keys** — all `Config.Throwables` keys and locale keys use snake_case (e.g. `throwable_interact`, `throwable_list_alt`).
- **`Carrying` table is the authority** — server-side, `Carrying[source]` being set means a player currently holds an object. Any server callback that mutates object state must check `Carrying[source]` first.
- **Event naming convention** — all networked events are prefixed with `pickle_throwables:` (e.g. `pickle_throwables:throwObject`, `pickle_throwables:catchObject`).
