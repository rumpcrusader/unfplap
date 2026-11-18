# Idle act offer

`offer/service.gd` (Node, world scope) owns the idle act offer: the one-second scene scan, the
standing gate behind it, the typed offer the act key would start, the footstool block, the
"Make love" hint beside the game's prompt row and the live Agreement offer. It answers what the act
key could start here and never starts anything. The act key's press, the hotkey and the Agreement
auto-start stay in the entry until they move here.

## Scope

This contract covers:

- the idle scan, its cadence and the standing cone target;
- the standing gate's reuse window and its footstool block;
- the typed playable offer, the blocked variant and the `offer_target()` query;
- the hint unit in the game's prompt row, its HUD fallback and the blocked toasts;
- the `OFFER ...` and `OFFER blocked ...` log lines and the offer's four idle perf chunks.

It does not cover the act start, the Proactive request pacing (`docs/initiation.md`), the
Negotiation exchange (`docs/negotiation.md`), the standing reach rule (`docs/stool.md`) or the
scene rows behind the gate (`docs/scene_gate.md`).

## Ownership

| Member | What it owns |
|---|---|
| `tick(delta)` | the `OFFER_SCAN_S` cadence, the scan it triggers and the hint that follows |
| `scan()` | one full scan: the live Agreement, the bed-side and already-lying rows, the standing cone |
| `current()` | the playable `PoseOffer` the act key would start, or null |
| `blocked()` | the standing offer with its blocked record, or null |
| `offer_target()` | the current offer's pony, read without a rescan |
| `clear_current()` | drop the playable offer after a start or a formed Agreement |
| `hide_hint()` | drop both offers and take the hint away while an act owns the frame |
| `apply_settings()` | drop the resolved prompt row so the act key's cap is rebuilt |
| `on_world(host)` | the world entry: reset the old scan, warm the two offerable assets |
| `reset()` | the world close: no offer, no gate verdict, no one-shot flag, no hint row |

The scan runs one second apart because the cone geometry and the gate are cheap enough to keep
live and expensive enough not to pay per frame. The gate behind it is the expensive half: its
verdict is reused while the same mare stays the cone target and refreshed every `GATE_REFRESH_S`,
so a reused verdict can only hold the hint back, never start or block an act. The live Agreement is
checked first: it is already a yes, so the rump fan and the policy snapshot do not rediscover it.

An offer of either kind keeps its logged key, and no offer at all clears both keys, so the same
offer logs again when it comes back. The blocked note has one toast per world: `_last_blocked_key`
dedupes the log line and `_stool_hint_toast_shown` the toast.

## Internal API

```gdscript
const OFFER := preload("res://mods/unfplap/offer/service.gd")

const OFFER_HINT := "Make love"
const OFFER_SCAN_S := 1.0
const GATE_REFRESH_S := 2.0
const NEEDS_STOOL_HINT := "Needs a footstool"

func tick(delta: float) -> void
func scan() -> void
func offer_target() -> Node
func current() -> POSE_OFFER
func blocked() -> POSE_OFFER
func clear_current() -> void
func hide_hint() -> void
func apply_settings() -> void
func on_world(_host: Node) -> void
func reset() -> void
func agreement_offer(handle: NEGOTIATION.AGREEMENT.Handle) -> POSE_OFFER
```

The entry ticks it first in the idle branch, before `initiation.tick()`, `negotiation.tick()` and
the Anon-offer watch, so the Proactive cuddle check reads the frame's scan. `try_start()` calls
`scan()` before it answers a press, so a press never waits for the cadence.

`offer_target()` reads the current scan result and never rescans: the loop owns the cadence, and a
press is the only immediate rescan. The invalidation rules are the entry's: a world enter and a
world close call `reset()`, an act start and a formed Agreement call `clear_current()`, and an act
live in the frame calls `hide_hint()`.

## Data ownership

Nothing is persisted. The scan result, the gate verdict with its footstool pair, the two logged
keys, the one-shot toast flag and the resolved hints node and prompt row live for one world and are
cleared by `reset()`.

## Lifecycle

- Scope: world
- Constructed by: `main._ready()`
- Begin: `on_world()`
- End: `reset()`/world close
- Idempotent: yes

## Settings

No setting is declared here. The hint's key cap comes from `controls.act_key` through
`ACT_KEYS.label()`, read when a hint unit is built and never per frame; the entry calls
`apply_settings()` on every settings edit, which drops the resolved row so the next frame rebuilds
it with the new label.

## Controls and debug

The act key is the only control. On the standing blocked note the key starts nothing and shows the
recorded toast; a press otherwise hands the current offer to the entry's start path.

**Enable debug** on prints one `OFFER pony=<name> pose=<pose> source=<source> bed=<bed> pending=<bool>`
line per change of the offer and one
`OFFER blocked pony=<name> reason=needs_stool gap=<m|n/a> need=<n> have=<n>` line per blocked target.
**Enable debug** + **Print perf logs** adds the `offer_scan`, `offer_cone`, `offer_gate` and
`entry_hint` idle chunks; see `docs/perf.md`.

## Host boundary

| Callback | Type | Contract |
|---|---|---|
| `runtime_for` | `Callable(pony: Node) -> Node` | a pony's live runtime, or null; the registry is the entry's until `ponies` owns it |
| `act_target` | `Callable(pony: Variant) -> bool` | the adult act-target capability of `eligibility` |
| `negotiation` | `Node` | the Negotiation service; only its public `handle()` read is used |
| `hud` | `Node` | the desktop HUD, set once the player rig arrives; `show_prompt`/`hide_prompt`/`toast` |

A missing callable reads as "no runtime" and "not a target", so an unbound service scans nothing.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | hud | `hud/service.gd` | the prompt row unit and the HUD fallback |
| service | negotiation | `negotiation/service.gd` | the live Agreement offer |
| service | poses | `poses/service.gd` | the warmed authored pose assets |
| service | settings | `settings/service.gd` | the act key's cap label |
| service | world | `world/service.gd` | player, camera, mares, headset and pause |
| shared | act_keys | `shared/act_keys.gd` | the act key's key cap label |
| shared | log | `shared/log.gd` | the offer lines and the idle offer chunks |
| shared | pose_catalog | `shared/pose_catalog.gd` | the two offerable pose ids |
| shared | pose_offer | `shared/pose_offer.gd` | the typed act offer |
| shared | pose_specs | `shared/pose_specs.gd` | the two offerable assets |
| shared | rump_cone | `shared/rump_cone.gd` | the standing offer zone |

## Tests

- `tests/offer/test_offer.gd`: the one-second cadence, the cone target choice with a nearer
  stallion and a mare outside the fan, `offer_target()` as a pure read, the standing gate's reuse
  window, the footstool block with its one log line and its one toast, the hint unit in the game's
  prompt row with the act key's cap, the HUD fallback, the live Agreement offer and the offer
  cleared while an act is live.
- `tests/poses/test_pose_offer.gd`: the typed offer's fields and the entry's start outcomes.
- `tests/initiation/test_initiation_api.gd`: the Proactive service against the offer facade.

## Related docs

- `docs/scene_gate.md` — the scene rows the standing gate runs.
- `docs/stool.md` — the reach rule and the footstool block.
- `docs/hud.md` — the prompt row style and the HUD fallback.
- `docs/perf.md` — the `offer_*` and `entry_hint` idle chunks.
- `docs/poses.md` — the authored assets warmed at world ready.
