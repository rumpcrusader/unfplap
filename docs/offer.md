# Idle act offer

`offer/service.gd` (Node, world scope) owns the idle act offer and the start it leads to: the fan
sensor and the scene fingerprint that trigger it, the standing fan candidates behind it, the typed
offer the act key would start, the footstool block, the "Make love" hint beside the game's prompt
row, the live Agreement offer, the act key's one press and the Agreement auto-start. It answers what
the act key could start here and it starts that act.

## Scope

This contract covers:

- the per-frame fan sensor, its transitions and the standing fan candidates;
- the single-call business checks the `reconsider()` pass and the Agreement readiness run;
- the typed playable offer, the blocked variant and the `offer_target()` query;
- the hint unit in the game's prompt row, its HUD fallback and the blocked toasts;
- the act key's entry, the typed start path, the hotkey attempt and its Agreement exact match;
- the live Agreement start, its wait/start/fail answer and the auto-start clock with its guards;
- the `OFFER ...`, `OFFER blocked ...`, `hotkey ...` and `agreement ...` log lines and the offer's
  perf chunks.

It does not cover the runtime's start sequence (`docs/runtime.md`), the Proactive request pacing
(`docs/initiation.md`), the Negotiation exchange and the Agreement package
(`docs/negotiation.md`), the standing reach rule (`docs/stool.md`) or the scene rows behind the
gate (`docs/scene_gate.md`).

## Ownership

| Member | What it owns |
|---|---|
| `tick(delta)` | the fan sensor read, the hint that follows it and the Agreement auto-start clock |
| `reconsider()` | one full evaluation: the live Agreement, the bed-side and already-lying candidates, the standing fan |
| `current()` | the playable `PoseOffer` the act key would start, or null |
| `blocked()` | the standing offer with its blocked record, or null |
| `offer_target()` | the current offer's pony, read without a re-evaluation |
| `try_start()` | the act key's one entry: the act-live guard, the forced sensor read and the press |
| `start_pose_offer(offer)` | the one typed start path: blocked, Agreement trigger or hotkey attempt |
| `agreement_offer(handle)` | the live Agreement as the act key's typed offer |
| `clear_current()` | drop the playable offer after a start or a formed Agreement |
| `hide_hint()` | drop both offers and take the hint away while an act owns the frame |
| `apply_settings()` | drop the resolved prompt row and forget the sensor's senses |
| `on_world(host)` | the world entry: close the old world, then warm the two offerable assets |
| `on_world_closed()` | the world enter and close: no offer, no sensor, no one-shot flag, no hint row |

The sensor reads the fan every idle frame. A squared eye-to-body distance rejects the mares out of
reach before the rump math, and the standing fan and the AnonPony lying candidate are collected in
distance or facing order. The player's seat is read once a frame; a change is the bed branch's
trigger. The sensor reports a transition when the candidate set, the lying candidate or the current
target's scene fingerprint changes. The fingerprint is sampled at `SENSOR_POLL_S`
(`offer/fan_sensor.gd`) and covers the runtime state, posture, held, seated, sleeping, aftercare,
cuddle, affection, conversation, the navigator owner, the player's press guards, the inventory and
the player form.

`reconsider()` then runs one pass: the live Agreement, the bed-side and already-lying candidates,
and the standing fan candidates nearest first. There is no cached gate verdict and no row list: the
standing candidate's stool pair is read once, the small scene checks (`available`,
`pose_supported`, `player_ready`, `navigator_allows`, `posture_allows`) are one call each, and
`PONIES.act_target()` and `PONIES.relationship_ok()` are the eligibility reads. The composite
`hotkey_ready()` stays the press's path. A live Agreement is checked first: it is already a yes, so
the rump fan and the scene pass do not rediscover it.

An offer of either kind keeps its logged key, and no offer at all clears both keys, so the same
offer logs again when it comes back. The blocked note has one toast per world: `_last_blocked_key`
dedupes the log line and `_stool_hint_toast_shown` the toast.

## The start path

`try_start()` is the act key's only entry. A live act takes the press and nothing else runs; a
paused tree or a loose cursor refuses it before any read. A press otherwise forces a sensor read and
a fresh `reconsider()`, so it never starts a stale offer. No offer means no attempt: the
`hotkey no context pose` line and the "There is nothing to start here." toast. A blocked offer shows
its recorded toast and starts nothing.

`start_pose_offer(offer)` is the one typed start path. The offer carries its pose, source, bed and
trigger, so it never names a pose. It dispatches:

- `trigger == "agreement"` → the live Agreement start;
- anything else → the hotkey attempt.

**The hotkey attempt** is `runtime.gate.start_hotkey()`: the scene gate's `hotkey_ready()` (the
small scene checks plus Base clearance), with no policy snapshot, no offer cooldown and no buck. A
live Agreement's exact `(pose, source, bed)` match starts immediately and skips the presentation;
any other live Agreement or negotiation is interrupted with `Interrupted(hotkey)` and the immediate
attempt still runs. A started attempt clears the hint; a blocked one keeps it.

**The live Agreement start** is `runtime.gate.start_agreement(handle)`: only the scene-only rows with
the frozen pose capability. `AGREEMENT_WAIT` keeps the hint and the Agreement for the next press.
A started or failed attempt clears the hint and hands the result to the Negotiation service
(`report(handle, started)`), which closes the Agreement as `Started` or `StartFailed`. The offer
restates the runtime's three answers as `AGREEMENT_WAIT`/`AGREEMENT_STARTED` because a service
never preloads the runtime; `tests/offer/test_start.gd` fails if the two ever disagree.

**The Agreement auto-start** consumes a live Agreement with no key press. The readiness clock
runs in the common idle frame, before the handle read, so a handle that appears between polls is
consumed on the next one, `AGREEMENT_START_S` later at most. A live act holds it and does not
advance the clock; an open menu panel, a paused tree or a loose desktop cursor holds it after the
clock was consumed. The Negotiation service's `ready_offer()` decides whether the live scene
accepts it. A private Agreement takes a fresh privacy sample (the cuddle rule for a cuddle option)
immediately before it starts and is cancelled with the `privacy` reason when the sample is now
public; a public one never samples. The steady 0.5 s privacy sample in the Negotiation tick is the
path that cancels a private Agreement between auto-start polls.

## Triggers

| Trigger | Detection | Action |
|---|---|---|
| Enter or leave a standing fan | the sensor's per-frame loop | `reconsider()` |
| A lying mare in front for AnonPony | the sensor's lying candidate | `reconsider()` |
| The current target's scene state | the fingerprint at `SENSOR_POLL_S` | `reconsider()` |
| The player sits or stands at a bed | the seat read once per frame | `reconsider()` |
| A settings edit | `shared/settings_change.gd` | `apply_settings()` drops the row and resets the sensor |
| A world enter or close | `on_world()`/`on_world_closed()` | the sensor reset |
| A body swap or a new runtime | a new instance id | a new sense; the attach warm |
| An act starts | the entry stops ticking the offer and calls `hide_hint()` | the sensor is idle |
| The act key | `try_start()` | a forced sensor read and `reconsider()` |
| A live Agreement becomes ready | the 0.25 s auto-start clock | `ready_offer()` |

## Internal API

```gdscript
const OFFER := preload("res://mods/unfplap/offer/service.gd")

const OFFER_HINT := "Make love"
const NEEDS_STOOL_HINT := "Needs a footstool"
const AGREEMENT_START_S := 0.25
const AGREEMENT_WAIT := 0
const AGREEMENT_STARTED := 1

func tick(delta: float) -> void
func reconsider() -> void
func offer_target() -> Node
func current() -> POSE_OFFER
func blocked() -> POSE_OFFER
func try_start() -> bool
func start_pose_offer(offer: POSE_OFFER) -> bool
func agreement_offer(handle: NEGOTIATION.AGREEMENT.Handle) -> POSE_OFFER
func clear_current() -> void
func hide_hint() -> void
func apply_settings() -> void
func on_world(_host: Node) -> void
func on_world_closed() -> void
```

The entry ticks the offer first in the idle branch, before `initiation.tick()` and
`negotiation.tick()`, so the Proactive cuddle check reads the frame's offer and the hints are
current for the frame. The Agreement auto-start clock runs inside that one call, so it reads the
live Agreement as the previous frame's `negotiation.tick()` left it.

`offer_target()` reads the current offer and never re-evaluates: the sensor owns the transitions,
and a press is the only forced read. The invalidation rules are the entry's: a world enter and a
world close call `on_world_closed()`, an act start and a formed Agreement call `clear_current()`,
and an act live in the frame calls `hide_hint()`.

## Data ownership

Nothing is persisted. The sensor's per-mare senses and candidate list, the offer and its footstool
pair, the two logged keys, the one-shot toast flag, the player's last seat, the resolved hints node
and prompt row and the auto-start clock live for one world; `on_world_closed()` clears all but the
clock, which is a frame timer that self-corrects on the next poll.

## Lifecycle

- Scope: world
- Constructed by: the entry's service list (`_build_services()`)
- Begin: `on_world(host)`
- End: `on_world_closed()` on a world enter or close
- Idempotent: yes

## Settings

No setting is declared here. The hint's key cap comes from `controls.act_key` through
`ACT_KEYS.label()`, read when a hint unit is built and never per frame. The settings change
notification calls `apply_settings()` on every edit, which drops the resolved row and forgets the
sensor's senses, so the next idle frame rebuilds the row with the new label and re-evaluates the
offer with the new values.

## Controls and debug

The act key is the only control. On the standing blocked note the key starts nothing and shows the
recorded toast; a press otherwise forces a sensor read and starts the current offer through the one
typed start path. The Agreement needs no key at all: it auto-starts when it is ready.

**Enable debug** on prints one `OFFER pony=<name> pose=<pose> source=<source> bed=<bed> pending=<bool>`
line per change of the offer and one
`OFFER blocked pony=<name> reason=needs_stool gap=<m|n/a> need=<n> have=<n>` line per blocked target.
The start path adds `hotkey no context pose`, `hotkey exact match id=<id> pose=<pose>`,
`hotkey interrupt agreement|negotiation id=<id>`,
`hotkey immediate id=<id> pose=<pose> source=<source>`,
`hotkey start blocked id=<id> pose=<pose> source=<source>`,
`agreement start id=<id> pose=<pose> skip_presentation=<bool> result=<n>`,
`agreement start waiting pose=<pose> source=<source>`,
`agreement auto-start id=<id> pose=<pose>`, `agreement auto-start privacy lost pony=<name>` and
`agreement auto-start pony=<name> pose=<pose>`.
**Enable debug** + **Print perf logs** adds the `offer_sensor` chunk (every idle frame),
`offer_reconsider` (one transition, wrapping the `offer_agreement` and `offer_stool` children) and
`entry_hint` to the profiler's block.

## Host boundary

| Callback | Type | Contract |
|---|---|---|
| `negotiation` | `negotiation/service.gd` | the Negotiation service; only its public `handle()`, `ready_offer()`, `is_locked()`, `hotkey_handle()`, `interrupt_for_hotkey()`, `cancel()` and `report()` reads are used |
| `privacy` | `privacy/service.gd` | the live visibility provider, sampled fresh before a private Agreement auto-starts |
| `hud` | `Node` | the desktop HUD, bound at construction; `show_prompt`/`hide_prompt` (toasts go through `HUD.toast()`) |

`_ready()` joins the settings change notification and `_exit_tree()` leaves it, so an edit reaches
`apply_settings()` with no entry path. The live runtime, act-target and act-running reads are the
preloaded `PONIES` facade; a missing registry reads as no runtime, no act target and no act, so an
unbound service reads no fan and starts nothing. A missing privacy provider reads as public, so a
private Agreement does not start on a stale answer.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | hud | `hud/service.gd` | the prompt row unit, the HUD fallback and the toasts |
| service | negotiation | `negotiation/service.gd` | the live Agreement offer, the exact match and the start report |
| service | ponies | `ponies/service.gd` | the live runtime, the act-target rule and the act-running gate |
| service | poses | `poses/service.gd` | the warmed authored pose assets |
| service | privacy | `privacy/service.gd` | the fresh sample before a private Agreement auto-starts |
| service | settings | `settings/service.gd` | the act key's cap label |
| service | world | `world/service.gd` | player, camera, mares, headset, menu panel and pause |
| service | world | `world/game.gd` | the seated couch partner and the player's seat |
| shared | act_keys | `shared/act_keys.gd` | the act key's key cap label |
| shared | log | `shared/log.gd` | log sink |
| shared | perf | `shared/perf.gd` | one profiler |
| shared | pony_id | `shared/pony_id.gd` | the mare id in the start log lines |
| shared | pose_catalog | `shared/pose_catalog.gd` | the two offerable pose ids |
| shared | pose_offer | `shared/pose_offer.gd` | the typed act offer |
| shared | pose_options | `shared/pose_options.gd` | the exact option a hotkey match names |
| shared | pose_specs | `shared/pose_specs.gd` | the two offerable assets |
| shared | rump_cone | `shared/rump_cone.gd` | standing offer zone |
| shared | settings_change | `shared/settings_change.gd` | the settings change notification |

### Used by

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | input | `offer.try_start()` | the act key's press |
| service | initiation | `offer.offer_target()` | the cuddle offer's target check |

## Tests

- `tests/offer/test_fan_sensor.gd`: the fan boundary and half-plane, the candidate distance order,
  the lying candidate, a state change inside the fan against a far mare's silence, the reset and
  the act-inert state.
- `tests/offer/test_offer.gd`: the fan transition on the same frame, the nearest act target in the
  fan with a nearer non-target, walking out and back, the scene fingerprint's no-op frames,
  `offer_target()` as a pure read, the footstool block with its one log line and its one toast, the
  hint unit in the game's prompt row with the act key's cap, the HUD fallback, the live Agreement
  offer through `ready_offer()` and the offer cleared while an act is live.
- `tests/offer/test_start.gd`: the act key's act-live guard, the empty-scene toast, the blocked
  toast, the hotkey attempt and its exact match, the Agreement wait/start/fail answers and the
  report, the interrupted negotiation, the auto-start clock with its act and menu guards, the fresh
  private and cuddle samples, and the agreement between the offer's and the runtime's answers.
- `tests/poses/test_pose_offer.gd`: the typed offer's fields and validity.
- `tests/test_input.gd`: the act key's route into `try_start()`.
- `tests/initiation/test_initiation_api.gd`: the Proactive cuddle gate reading the offer's current
  target on a non-forced read.

## Related docs

- `docs/runtime.md` — the start sequence both start paths share and the Agreement answers.
- `docs/scene_gate.md` — the scene rows the standing gate and the starts run.
- `docs/stool.md` — the reach rule and the footstool block.
- `docs/hud.md` — the prompt row style and the HUD fallback.
- `docs/negotiation.md` — the Agreement package, its close reasons and the start report.
- `docs/input.md` — the act key and the input shield.
- `docs/poses.md` — the authored assets warmed at world ready.
