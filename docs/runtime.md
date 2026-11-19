# Act runtime

`runtime.gd` is the per-pony host. One Node exists per non-player pony, parented under the pony,
and it is idle outside an act: it forwards the two frame hooks and owns the lifetime, the
composition, the reparent across a body swap and the despawn release. Its own `act/` modules own
the act state, timers, clock and values (`act/session.gd`), the ordered frame schedule
(`act/tick.gd`), the frame-level presentation and its write-backs (`act/phases.gd`), the start
recipe (`act/start.gd`), its closed setup adapters (`act/setup.gd`), the scene-only Agreement and
act-key protocol (`act/agreement.gd`), the one teardown and its routes (`act/exit.gd`), the input
protocol (`act/input.gd`), the body-swap seams (`act/swap.gd`), the typed collaborator set
(`act/context.gd`), the node operations (`act/host.gd`), the view composition (`act/view.gd`) and
the idle schedule (`act/idle.gd`). It implements no system's rules and owns no system's mutable
state. The act's settings snapshot is `act/settings.gd`, the act's read composition is
`act/view.gd`, and the service contracts are indexed in `docs/README.md`.

## Lifetime

- Scope: per-pony.
- Constructed by: `ponies/service.gd` through the entry's one factory, on the body's attach hook.
- Parented under the pony; `ponies` records it in its registry and drops the record on
  `tree_exiting`.
- `_init()` builds the per-pony systems once and binds their typed hosts and callables.
- `_ready()` reads the identity, binds the pose hosts and face, starts the process and physics
  hooks at priority `100` (after locomotion, the navigator and attention), then refreshes the
  persistent anatomy controller and retries the identity read after the first frame.
- End: pony despawn, world close or mod shutdown. `_exit_tree()` releases the kiss forelegs, the
  stool, the tail tuck, the aftercare, the anatomy act and the face. A suspension reparents the
  runtime instead (see `## Body swap`), and the `_swapping_parent` flag makes that `_exit_tree()`
  a no-op.
- The audio node is the one system node created lazily because it needs the tree; the pose-scope
  tail tuck is the other system-owned child. Both are documented exceptions in the checker.

## Ownership

| Runtime owns | Detail |
|---|---|
| Lifetime | attach, `_ready`, tree parenting, despawn, world close, reparent across a body swap |
| State machine | the transition bodies and their side effects; `act/session.gd` owns `state`, the one `_set_state()` writer, the timers, the clock and the `tick`/`render` forwards; `act/tick.gd` owns the order of the frame |
| Session values | `act/session.gd` owns the pose id, source, bed, id/display, event/serial, preferences/profile/prompts and the act bookkeeping; `act/settings.gd` owns the settings snapshot and its read-throughs; the runtime keeps read-through handles (`_id`, `_snapshot`) and delegates `refresh_identity()` |
| Composition | `_build_systems()`, `_bind_act_frame()` and `_bind_pose_hosts()`, one typed field per system, one bind pass |
| Schedules | `act/tick.gd` the ordered physics and render frames and the one pose fan-out; `act/idle.gd` the idle block; `act/phases.gd` the presentation frame and its write-backs |
| Ledgers | `act/start.gd` the ordered start, its setup adapters and its partial-start abort, `act/agreement.gd` the scene-only Agreement and act-key rows, `act/exit.gd` the one exit and its cancel/afterglow/restore/stop routes, `act/swap.gd` the body-swap release and resume seams |
| View | the typed act view composed by `act/view.gd` once per phase |
| Protocol | the `act` handle: start request/answer, force stop, cancel/afterglow, the input protocol (`act/input.gd`), `live_id`, `act_view`, `prompt_note` |

The runtime never owns:

- readiness, satisfaction, scoring, tolerance, stroke placement, penetration;
- pose selection, pose math, bone placement, standing fit;
- camera shots, lean math, free look;
- hand, kiss or wing behaviour;
- body-change detection, provider policy, form effects, handover timing;
- raw input decoding, key holds, mouse mapping, auto-layer key sampling;
- audio creation, bed-soft detection, snout lookup, vocal-cache repair, voice policy;
- aftercare nodes, the satisfaction decay tween, the tail tuck, the post-act face;
- HUD strings, key caps, panel labels;
- eligibility, scene gate rules, offer scan policy;
- debug formatting and debug-only reads;
- settings declarations or per-frame settings reads.

## State machine

```text
IDLE → POSING_IN → ACTIVE → CLIMAX → AFTERGLOW → RESTORE → IDLE
```

- `IDLE`: no act; the runtime is attached, runs its idle schedule and may show the start hint.
- `POSING_IN`: the start sequence has run and the pose is building.
- `ACTIVE`: thrusting, readiness, cues, caress and the pose actions are live.
- `CLIMAX`: the pony's 5 s climax; the player may keep thrusting but it does not score.
- `AFTERGLOW`: the held post-act phase, the standing close window and normal dialogue.
- `RESTORE`: the teardown ledger runs; the runtime returns to `IDLE` at the end.

`shared/act_state.gd` is the one typed definition (`ACT_STATE.State`), aliased in the session and the
runtime as `State`. `act/session.gd` declares `state` and is its one writer, `_set_state(next)`; it
also refreshes the scene gate's live state. `runtime.state` is a read-only forward until R4. The
session's transition helpers write the state and arm its timer (`begin_pose_in`, `enter_active`,
`enter_climax`, `enter_afterglow`, `begin_restore`, `finish_restore`, `enter_idle`); the runtime
keeps the transition side effects. States change from the ordered tick:

| From | To | Trigger |
|---|---|---|
| `IDLE` | `POSING_IN` | the end of `act/start.gd:run()` |
| `POSING_IN` | `ACTIVE` | the `act/session.gd` pose-in timer |
| `ACTIVE` | `CLIMAX` | a pony climax |
| `CLIMAX` | `ACTIVE` | the session's climax timer while the player keeps going |
| `ACTIVE` / `CLIMAX` | `AFTERGLOW` | `request_afterglow()` or the act-key hold with a climax behind it |
| `AFTERGLOW` | `RESTORE` | `end_afterglow()` or a cancel |
| any live state | `RESTORE` | `cancel()` or `force_stop()` |

Breath timing: `0.9 s` base while active, `0.85 s` during climax, `1.4 s` in afterglow.

## Session

The act session is the per-pony state the runtime applies. The state, the clock, the timers and
the act's own values live in `act/session.gd`; `runtime.act` is its typed handle and the input
service reaches the protocol through `act.input`:

- state and clock: `state`, its only writer `_set_state`, `_act_seconds`, `_clock_s`,
  `_pose_in_left`, `_climax_left`, `_restore_left`, `_check_clock` and the climax progress.
  `reset_act()` clears the act's clock and timers; `tick_timers(delta)` reports the one
  transition verdict and the frame schedule applies it. `act_seconds()`, `clock_s()` and
  `climax_progress()` are the typed reads; the view and the idle schedule never read the fields.
  `idle_perf` is the cached probe gate for the idle window.
- frame handles: `ticker` (the ordered schedule), `input` (the input protocol), `start` and `view`.
  `tick(delta)` and `render(delta)` are the session's two one-line forwards to `ticker`.
- values: `pose_id` (the start identity), `source`, `bed`, `pony_id`, `display_name`,
  `event_id` and `serial` from `PONIES.allocate_serial()`, `preferences`, `act_prompts`,
  `profile`, `player_pony`, `forced_glance`;
- act bookkeeping: `aftercare_min`, `cue_gap`, `first_time`, `stopped_by_her`, `act_spoken_at`,
  `ended_early`, `cycle_heat`, `preserve_auto_shape`, and the two ownership flags `posture_owned`
  and `finalized`.

`refresh_identity()` re-reads the stable identity from the presented body, adopts its display name
through `PONIES.display_name_for()` and refreshes the scene gate; `live_id()` and the runtime's
`_id` handle read `pony_id`.

The act settings snapshot lives in `act/settings.gd`: the one `SETTINGS.ActSnapshot`, the feature
flags, the pose presentation block, the caress quality, the climax limit and mode, and the
eye-camera mode. `act/session.gd:snapshot_settings()` is the one bulk snapshot at act start and
again at the top of `apply_live_settings()`, before the `IDLE` early return. The session exposes
typed read-throughs (`snapshot`, `features`, `presentation_config`, `caress_quality`,
`max_pony_climaxes`, `climax_mode`, `eye_camera_mode`) and `_snapshot` is the runtime's handle.
No second per-frame settings read exists. A zeroed snapshot stands in until the first start or
settings edit.

The session dispatches; the owners keep the bodies. `act/view.gd` composes the act values the
owners read: the face beat and rows (`face/service.gd`), the climax line (`dialogue/service.gd`),
the summary input (`summary/service.gd`), the normal prompt note, the debug context and the render
pose write. The session's transitions call the owners: `readiness.begin_climax()`/`end_climax()`
own the climax count, mood and cue; `afterglow/service.gd` owns the phase values, the presentation
row and the close reward; `summary/service.gd` owns the score, the peak and the witness pass.
`act/context.gd` carries the live systems only.

## Composition

`_init()` runs the one construction and bind pass:

- `_build_systems()` constructs the handover, placement, wings, hands, kiss, integrations, the two
  camera controllers, the two standing body controllers, the camera session and the act audio
  owner, then binds the camera's sessions and calls `_bind_act_frame()`.
- `_bind_act_frame()` builds the act's own modules once: `act/host.gd` (the node operations, the
  log/perf sinks and the tail-tuck pair), `act/context.gd` (the typed collaborators),
  `act/settings.gd` (the settings snapshot and live apply), `act/session.gd` (the state, timers,
  clock, values, stool handle, start entry and the two frame forwards), `act/view.gd`,
  `act/idle.gd`, `act/consent.gd`, `act/impact.gd`, `act/exit.gd`, `act/input.gd`, `act/swap.gd`,
  `act/phases.gd`, `act/tick.gd`, `act/setup.gd`, `act/start.gd` and `act/agreement.gd`. The
  schedule, swap and phase modules are pointed at the exit, the session and their siblings, and
  `act/session.gd:ticker`/`input` are the handles the entry and the input service read.
- `_init()` hands the perf probe to `act/tick.gd` after `PERF.build()`, so the frame's labels are
  the schedule's.
- `_bind_pose_hosts()` binds the pose session's host callbacks (the scene, the pose host reads and
  the oral/face callbacks).
- `_init()` binds the remaining facades and callables: the anatomy bridge host, the act view
  callbacks, the readiness host, the summary, afterglow, face, reactions, scene gate, rest and
  scene hold. `PERF.build(_perf_host())` builds the probe, and the scene gate is configured once.
- The per-act systems (readiness, pose session, camera, face, afterglow, summary, reactions,
  scene hold, rest, dialogue, hands, kiss, cards, integrations) are typed fields constructed once
  per pony and reset per act.

The anatomy bridge receives the typed `anatomy/act_host.gd`, not a dictionary; `body_change/act.gd`
receives the typed `body_change/act_host.gd`. No service locator or host dictionary is passed.

## Schedules

`_physics_process` is one `act/tick.gd:tick(delta)` call and `_process` one `render(delta)` call.
The schedule's physics frame ends with the anatomy `sync_facts()` write, so the persistent anatomy
controller's own `_process` poll reads the frame's live state, pose, depth and bed frame.

Act physics, in call order (`act/tick.gd:_tick`):

1. `act/swap.gd:tick(delta)` — the handover's one tick; a suspension returns here.
2. `session.tick_clock(delta)`; then `context.pose.tick(delta)` when the state is not `IDLE`,
   timed as `pose_tick`.
3. `session.refresh_view()` → `act/view.gd`, timed as `runtime_facts`.
4. `act/tick.gd:_fanout()` when the state is not `IDLE`, timed as `pose_fanout`.
5. `IDLE`: `act/idle.gd:tick(delta, idle_perf)` runs the inventory safety, the standing
   presentation's physics and the dialogue history scan, then returns. It runs no pose tick or
   fan-out.
6. The act body: the cycle heat signal, the pose-frame sync, waking her, the vocal tick, the
   navigator keep-alive, free look, act attention, the face-turn pause, the lean tick,
   `act/phases.gd:presentation()` (timed `runtime_presentation`), the consent frame, the settled
   log, the kiss tick, auto, impact and the anatomy tick, and, in `ACTIVE`, readiness, talk, the
   form offer and the bystanders (timed `runtime_talk`).
7. The utterance tick, then `session.tick_timers(delta)`: the returned phase verdict is applied by
   `enter_active_act()`, `finish_climax()` or `act/exit.gd:finish_restore()`; the climax hearts
   tick while `CLIMAX`, and `afterglow/service.gd:phase_tick()` runs while `AFTERGLOW`.
8. The camera block (facing lock, glance, auto-cuddle suppression, clamp, depth, Anon phase,
   blush, `session.apply_camera_motion()`), the session's 0.25 s check window (the scene gate's
   running verdict applied through `act/exit.gd:stop()`) and the face's eyes.

Act render, in call order: `refresh_view()`, `context.pose.sync_frame()`,
`session.pose_render_write()`, `context.pose.idle_sample()`, the standing clamp, the camera look
write, the climax progress, the shot tick and the breath. `IDLE` runs only the standing
presentation's render tick; a suspended act runs none of it.

The entry's `_process` calls `PONIES.active()` and then `apply_camera_motion()` on it every
frame; the runtime refreshes the view and the HUD card there through `act/view.gd`. The pose and
camera timing is `docs/poses.md` and `docs/camera.md`. The frame schedule never calls an act exit
except through `act/exit.gd`'s own routes (`finish_restore`, `stop`, `force_stop`); a teardown
step lives only in the exit ledger.

## Ledgers

### Start

`offer.try_start()` is the act key's only entry (`docs/offer.md`). It hands a typed offer to
`offer.start_pose_offer(offer)`. The idle scan builds its offer from the bed side or the
free-standing fan; a live Agreement builds `trigger: "agreement"` from its frozen option and the
scene-only rows.

The live start paths share the one body (`act/start.gd:run()`; `act/session.gd:begin()` is its one
entry). The three entry points live in `act/agreement.gd`:

- **The hotkey** runs `runtime.start_hotkey()` → `act/agreement.gd:start_hotkey()`: the scene
  gate's `hotkey_ready()` (the scene-only rows plus Base clearance), then `act/start.gd:run()`. No
  policy row, no offer cooldown, no buck and no history refusal.
- **The Agreement** runs `runtime.start_agreement(handle)` →
  `act/agreement.gd:start_agreement()`: the scene-only rows with the frozen pose capability
  (`scene_only_verdict`), then `act/start.gd:run()`. It answers `AGREEMENT_WAIT`,
  `AGREEMENT_STARTED` or `AGREEMENT_FAILED`; the offer, its only caller, reports `Started` or
  `StartFailed` to the Negotiation service.
- **Auto-start** consumes a live Agreement with no key press;
  `act/agreement.gd:agreement_offer_ready()` decides whether the scene and the settled
  presentation accept it.

The start sequence:

1. `act/agreement.gd` re-reads the identity and the gate (the Agreement path runs the scene-only
   rows); `run()` opens with the presentation guard;
2. bind the act's stool handle through `act/session.gd:stool()` and reset it, then refresh the
   anatomy bridge;
3. begin the camera session, clear the idle presentation, the mood face and the act face;
4. snapshot the settings and preferences, build the profile and prompts;
5. resolve the bed when the row's `scene.requires_bed` is set (a missing bed fails closed before
   anything is borrowed), then apply the eye override and the initial face;
6. allocate the serial/event id, reset readiness, dialogue, history and the thrust state;
7. release the cradle/cuddle/navigator/player ownership through `scene_hold`;
8. snapshot the pony bones, mark the act active, build the anatomy act;
9. dispatch the row's `start.setup` (below) to place the bodies;
10. build the pose, sync the start settings group, prepare the start camera profile, capture the
    look, lock the player and the navigator, start the camera, the audio, the HUD and the act face,
    then arm the act integrations.

A failure in any step runs the one partial-start funnel, `act/start.gd:abort()` (the act's end
lines, the one exit, then finalize as a failed start); it never leaves a partial act.

### Start setup adapters

`act/start.gd:run()` matches the pose row's closed `start.setup` name and never a pose id; it
passes the name to `act/setup.gd:run()`. The names and their placement:

| Setup | Adapter | Placement |
|---|---|---|
| `bed_stand_up` | `act/setup.gd:bed_stand_up()` | a human Anon `force_stand_up()`; the cradle or bed rest release already ran in the prelude; `request_posture("stand")`; the bed frame |
| `bed_keep_lying` | `act/setup.gd:bed_keep_lying()` | no `force_stand_up()`; a `dialogue` source releases managed rest; `request_posture("stand")` so the authored act body owns her pose; the bed frame |
| `standing_place` | `act/setup.gd:standing_place()` | `act/session.gd:placement_values()` feeds `poses/placement.gd` through `bind_act()`/`begin_act()`; a failed stool aborts; `request_posture("stand")`; the view refresh; `begin_facing()` |

A missing bed fails the two bed adapters closed; a failed cradle/bed rest release already aborted
in the prelude. An unknown or missing setup logs one `start blocked setup=...` line and aborts
through the partial-start funnel; the gate already passed, so this is a spec/data error, not a
refusal.

The start settings-group sync (`sync_start_pose_config()`) and the start camera
(`prepare_start_camera()`) read the row's `settings_group` and `camera.profile`, not the pose id.

### Suspend, adopt and resume

A body-change provider can replace the act pony's presented body without ending the act; the
mechanism, the typed form and the source/binding contracts are `docs/body_change.md`.

`act/swap.gd:tick()` applies one typed action from `body_change/act.gd`: `NONE`, `SUSPEND`,
`RESUME`, `FAIL` or `END_RESTORE`. `body_change/act.gd:release(change)` stops the act's work and
records one pending swap; the runtime's `_body_swap_tick(delta)` and `_suspend_for_body_swap(change)`
are the one-line suite seams over it:

- one pending swap is recorded in `ponies`; a second change is refused until it clears;
- the runtime is reparented to the entry before the old body is freed;
- the pose session, the anatomy act handle, the navigator lease, the face-turn hold, the camera
  shot, the kiss/hand contact, the wings, the carried body and the act-key hold are released; the
  auto stroke is interrupted without resetting its pace, band, shape or on/off state, the bones
  are put back and the breath stops;
- the outer act state, depth, penetration, climaxes, readiness, satisfaction, summary, event id,
  serial, settings snapshot and dialogue state stay in the session. The player stays locked, the
  HUD stays up and the outer camera is not restored to the player as an idle camera.

`PONIES.attach(new_pony)` adopts the suspended runtime before it creates a runtime. It runs the
body-change `notify_body_ready()` first, then `anatomy.bind()` and `runtime.adopt_body()`, which
bind the new body, pose, face and anatomy but do not resume. `body_change/act.gd:resume()` is the
one resume body and `act/swap.gd:resume()` its only caller; it ends the act through the one exit
when the resume fails. The resume re-reads the settings and the new body's size, ends the old
anatomy act and begins a new one at the current depth, rebuilds the live pose at the pose the act
was in (`poses/service.gd`'s `settle()` skips the entrance ramp), resets the visual frame through
`body_change/act.gd:rebind()` (restore the true eye, clear the shot, re-anchor a standing Anon at
the new form's gap, then prepare the camera), restarts auto at its preserved values and state,
reopens the camera, re-claims the new navigator, pauses the new face-turn rate, rebinds the face,
voice, wings and integrations, and refreshes the HUD facts.

Failure paths keep the one exit: a failed handover or a watchdog calls `force_stop()`; an
ineligible new body ends through `force_stop()`; a world close or a force stop while suspended
clears the pending record and runs `act/exit.gd:run()`.

`act/swap.gd` is the typed bridge from the handover's host callbacks to the live systems: the
ordered release steps, the ordered resume steps, the adoption and revised-form rebinds, the
placement fit, and `standing_gap()` for the offer and the suites. It never reparents the node or
resumes by itself.

### Exit

`act/exit.gd:run(rejoin_cuddle)` is the only exit body. The exit's own routes are its only
callers, plus `act/consent.gd:stop_with_her()` for a partner stop: `cancel()`, `end_afterglow()`,
`restore_begin()`, `finish_restore()`, `restore_now()`, `force_stop()` and `stop(reason)`.
`runtime.force_stop()` is the one-line node delegate `ponies` calls. It gives back, in order: the auto
stroke, the handover, the inventory HUD, kiss forelegs, face-turn rate, eye override, face and
wings, player lock, camera, stool, `sex_active`, navigator, player look, posture/cuddle, pose,
audio, HUD and the active runtime. Every step checks the ownership flag it restores, so a failed
start runs the same body and restores only what it took.

- `act/exit.gd:finalize(real_act)` runs the post-act bookkeeping once and is idempotent;
  `finish_restore()`, `restore_now()` and `force_stop()` enter `run()` inside the same ledger.
- The act's end lines are deliberately outside the teardown: `act/exit.gd:cancel()` queues the
  early-stop reaction after `restore_begin()`, and `finish_restore()` must not cancel director rows.
- `restore_begin()` / `restore_now()` are the ordered leaves; `stop(reason)` is the scene gate's
  forced stop.
- The pose part is one ledger: `act/exit.gd:run()` calls `free_pose()` and then restores the pony
  bones through `context.pose.restore_bones()`. `free_pose()` runs the session's pose-scope steps
  (`leave_pose_start()`, `leave_pose_body()` and the final `release_pose()`) with the act-scope
  resets between them at their positions, resets the mod-integration bridge after the base kiss,
  releases the shared excitement Beat hold and leaves every property the act borrowed back in
  place. `act/start.gd:_build_pose()` calls the same ledger as the new-act prep before it builds
  the pose, so a pose left from the offer cannot stack. The step table and the scope split are
  `docs/poses.md`.
- `context.camera.release_act_shot()`/`finish_act_shot()` is the act's camera ledger: a separate
  act-level path, not part of the pose teardown.
- A forced stop never rejoins the missionary bed cuddle. A normal end of a bed-sourced act that did
  not go badly re-seats Anon on the bed's player seat and re-invites her through `rest/service.gd`.

The afterglow, close window and aftercare are `docs/afterglow.md`; the face and mood are
`docs/face.md`; the summary is `docs/summary.md`.

## Controls

The input service decodes the keys and calls the act's input protocol, `runtime.act.input`
(`act/input.gd`); neither the runtime node nor the schedule handles an input event.

| Input | Action |
|---|---|
| act key (single press, idle) | start the hinted act; captured in the General tab |
| act key (hold `0.35 s`) | cancel/end early at 0 climaxes; afterglow at 1+; end afterglow |
| `W` / `S` | lean forward / back |
| `Q` / `E` | side lean; standing shoulder reach |
| `A` / `D` | caress (standing flank; missionary chest/belly) |
| `Z` / `C` | toggle the caress movement |
| `F` (hold) | standing kiss at a full side lean; missionary kiss at a full forward lean |
| mouse right / `G` | smack |
| `X` (tap) | toggle auto thrust |
| `X` (hold) | auto settings layer |
| wheel | auto pace |
| `T` | the game's talk turn; scored as input |
| `H` | consumed; a stock hug cannot end the act's kiss |
| `V` / `N` | anatomy hole / oral, gated by `docs/anatomy.md` |
| Enter | the game chat during an act |
| hold middle | the debug action wheel; release runs the highlighted action; see `docs/debug.md` |
| any other key | consumed during an act; `Enter`, `T`, `Esc` and `F1`–`F12` stay live (`docs/input.md`) |

During standing oral, `W`/`S`/`Q`/`E`, the `Q`/`E` shoulder reach and the `F` lean kiss are
inactive, and `A`/`D` caress places the hands on her head sides. `N` requests the authored
`standing → standing_oral` edge and then its reverse. The camera and hand contracts are
`docs/camera.md` and `docs/hands.md`.

## Body swap

A body-change provider can replace the act pony's presented body without ending the act. The
handover (`body_change/act.gd`) reads `body_change.active_change_for(pony)` on a `0.1 s` cadence
and returns the typed action; the runtime does not poll the provider. One provider that handles
the act pony and reports a live `BodyChange` whose `previous_body` is the act pony starts the
handover. A change whose old body is not the act pony never reaches the act.

The adoption and the provider's settled form call `WORLD.refresh_body_lod()` for the new body: the
game's near and far caches are dropped and the near mesh is re-armed, so the visible body is the
form variant rather than the old body's near mesh.

A provider may clear its changing state before the new body's spawn hook reaches the registry.
The handover keeps the act suspended while the change still reports a `next_body`, then calls
`PONIES.adopt_pending_body()` after a short grace. A provider that stops without a new body still
follows the old-body or watchdog path.

A live settings edit while suspended refreshes the snapshot and returns; the resume applies it
with the rest of the rebuilt state instead of touching a released pose or the old body.

The runtime binding looks the runtime up through `PONIES.runtime_for(body)` and forwards the form;
it never creates a runtime, starts an act or runs the act exit. `act/swap.gd:resume()` stays the
one resume path and runs after the form is ready. A same-node revision takes the same
`act/swap.gd:reset_visual_for_form()` path through the runtime binding, without a resume or a
second pose session. The camera shot is released on suspend and recomputed on each presented-form change; the
flame covers the re-frame, and Anon may shift slightly. That re-frame is the accepted behavior.
The standalone base-game vocal cache can still hold an old body's freed player; the runtime prunes
only its own stable id before a vocal play, so the next clip is created on the presented body (see
`docs/audio.md`).

Failure paths keep the one exit: an old body kept alive resumes the same runtime; a named form
that fails before a new body arrives restores the pending offer; a new body that never reports the
target resumes as a failed change and restores the offer under the `8 s` watchdog; no body arrives
ends the act through `force_stop()`; a non-adult body ends through `force_stop()`.

`reparent()` runs `_exit_tree()`. The runtime's `_swapping_parent` flag makes that signal a no-op
during the handover. `attach_to_body()` is the only route that sets it.

### Form interaction

The game's talk turn (`T`/microphone) is the only player interaction; there is no new key, picker
or settings row. `_handover.player_line_tick()` reads a new director turn in `ACTIVE`, the same
turn the readiness classifier scores, and passes its text to the typed source:

- a source that wears another form consumes a reveal ask through `asks_form_change(text)`; a
  successful `runtime.request_form_change(true, "", true)` marks the change as the player's;
- with the post-climax offer pending, a line that names an adult mare through `named_form(text)`
  starts `request_form_change(false, id, true)`; `named_form_note(text)` supplies a short status
  for a worn, own, young/male or uncopyable name and returns nothing for ordinary talk;
- anything else is ordinary talk and is left to readiness and dialogue.

The provider policy owns the offer timing and prompt (`docs/body_change.md`,
`## Provider policy`). `_handover.offer_tick()` keeps the once-per-act gate and queues one
`FORM_OFFER` reaction when `policy.should_offer(context)` first returns true. The offer is
deliberately not made in `CLIMAX` or `AFTERGLOW`. An unanswered offer ends with the act; the next
act may offer again; a failed named change restores the offer.

A completed player-named change calls `policy.on_offer_accepted(context)`; a completed
player-requested return to her own form calls `policy.on_reveal(context)` once. The base runtime
executes the generic effects: a readiness heat spike and a cue while the act is `ACTIVE`, the
reveal's peak and `form_reveal` memory mark, the exceptional face beat, and the `form_reveal` input
the summary/act-history commit reads for an extra great-act comfort. The runtime dispatches the
generic policy milestones through one helper: `ACTIVE`, `CLIMAX_END`, `AFTERGLOW`,
`OFFER_ACCEPTED`, `REVEALED` and `FORM_SETTLED`.

`_handover.hint_tick()` is a debug log probe, not a HUD source. It names the reveal ask while she
wears another form and the name prompt while the offer is pending, but only when **Enable debug**
was on at the act's settings snapshot. `_form_hint` itself is always empty, so neither a release
nor a debug build puts the dialogue channel on the HUD. The debug label clears at the climax,
afterglow, restore, suspension and act end.

## Protocol and public surface

The cross-mod surface is `docs/api.md`. The internal reads the HUD, labs and tests use (`state`,
`pose_id`, `pony`, `pony_climaxes`, `satisfaction`, `mood`, `cue`, `depth`, `penetration_m`,
`thrust_up`) stay callable.

- **Start and gate:** `start_verdict`, `scene_only_verdict`, `hotkey_ready`, `start_hotkey`,
  `start_agreement`, `agreement_offer_ready`, `find_bed_under`, `hint_stool`, `debug_line`,
  `live_id`. The gate math and the verdict rows live in `scene_gate/service.gd`; the runtime keeps
  the ordered start ledger.
- **Stool queries:** `stool_gap_m`, `stool_needed_count`, `stool_case_count` and
  `stool_state_text`. The applies/required predicates are the per-act handle's
  (`stool/act.gd`), which `act/session.gd:stool()` binds and `act/session.gd:release_stool()`
  releases.
- **View and HUD:** `act_view`, `refresh_view`, `pose_view`, `hud_readouts`, `hud_controls`,
  `auto_active`, `close_hint`, `act_face_rows`, `pose_state_rows`, `face_sit_error`,
  `reload_pose_asset`.
- **Input:** `runtime.act.input` (`act/input.gd`) — `look_motion`, `thrust_motion`,
  `toggle_auto_thrust`, `auto_thrust_wheel`, `auto_panel_input`, `auto_panel_open`, `vr_y_held`,
  `free_look_active`, `request_pose`, `request_command`, `command`, `cancel`,
  `request_afterglow`, `end_afterglow`. `anatomy_hole_ready`, `anatomy_oral_ready`,
  `toggle_anatomy_hole` and `toggle_anatomy_oral` stay on the node until R4.
- **Presentation:** `present_standing`, `presentation_active`, `presentation_settled`,
  `clear_presentation`, `hold_handle`, `free_look_active`, `free_look_rotation`,
  `missionary_anon_body`, `authored_pose_asset`, `missionary_face_point`,
  `missionary_vulva_point`, `shot_lean_forward`, `rump_anchor`, `smack`, `force_act_face`,
  `debug_force_tolerance`, `voice_status_line`, `anatomy_facts`, `anatomy_normal`,
  `anatomy_opening`, `body_coat_jiggle_target`.
- **Pose-host write-backs:** `apply_anon_thrust`, `apply_anon_lean`, `apply_anon_align`,
  `apply_camera_motion` and `perf_note` are the callbacks the presentation controllers and the
  entry already call.
- **Body form:** `body_swap_pending`, `request_form_change`, `attach_to_body`, `adopt_body`,
  `bind_body_services`, `refresh_body_services`.
- **Exit:** `force_stop`, `apply_live_settings`.

`live_id()` is the act's stable pony id, refreshed from the live body; `ponies` matches a dialogue
prompt note to its one runtime through it. `request_form_change(true_form, shape_id, by_player)`
is the act-side form request the debug block and the player interaction call. `body_swap_pending()`
is true between suspension and resume. `PONIES.adopt_pending_body(pony)` runs the registry's
prepare and pending-swap adoption for a body the handover found before its spawn hook.

The pose surface is `pose_view()` and the input protocol's `request_pose(target_id, trigger,
request)`, `request_command(command_id)` and `command(command_id)`. The session supplies the state
and features; the pose service refuses or starts the edge. `request_command(id)` is the pure allow
check: `end` is reserved and always allowed, otherwise the id must be in the active pose's control
profile and the live edge lock must not deny it. `command(id)` runs that check first, then
dispatches the discrete `hole` id and `oral` to the anatomy bridge; the act-key hold still owns the
one exit path.

The act-tunable values live in one typed `SETTINGS.ActSnapshot`. A consumer reads
`_snapshot.<value>` at the use site. The camera mode is cached in the session's `eye_camera_mode`
by the same snapshot, and `act/session.gd:pose_render_write()` reads that field.

## View

`act/view.gd` composes the typed act view (`shared/act_facts.gd`) from the session, the context and
the host. `runtime.refresh_view()` and `session.refresh_view()` are the same one call: the physics
frame, the render frame, the idle pass and the `apply_camera_motion()` hand-off all call it. It
runs once per phase: idle before the idle systems, physics after the pose tick and before the
fan-out, render before the camera work, and the entry's `apply_camera_motion()` hand-off.
`act/view.gd:sync_hud()` adds the HUD card's live values and runs from `apply_camera_motion()` and
the act boundaries; the HUD reads fields and never probes the runtime. The start, resume, teardown
and live-edit paths call it directly.

The view keeps raw values; `shared/act_facts.gd` owns the field list. The HUD strings, the key caps
and the panel labels live in `hud/service.gd` and `hud/lines.gd`. `close_earned` and `auto_shape`
are raw values; the `End` tint and the auto readout are formatted by the HUD module. The view reads the plain act values from the session; the session is the one owner, so no second
read model mirrors them.

The standing start/offer gap is read from `_pose_session.pose_config["gaps"]`; a session without a
config falls back to `SETTINGS.pose(id, "standing")["gaps"]`. The shipped values live under
`default.poses.standing.gaps`; the placement handle keeps no gap table or numeric fallback, and a
per-mare pose override still wins. `_standing_gap()` adds the entrance's back offset for a
princess body.

That gap is the pre-act view, not the contact distance. Before the act, `poses/placement.gd` fits
Anon's whole body: it takes the part's natural pivot, her live opening and outward rear, and shifts
his horizontal position so the pivot starts one shaft behind her entrance. The fit is bounded by
`poses/placement.gd:FIT_MAX_M`, skipped on a stool, and repeated by `act/swap.gd:reanchor()` on a
body resume or a same-node form revision. It clears the part's old Hips handshake
(`player_reset_pelvis()`) after measuring. The per-frame aim owns the stroke's pelvis correction;
a standing start no longer pulls the Hips bone across the gap.

## Thin-runtime checker

`scripts/architecture.py --check` enforces the host shape in addition to the exit, pose-ledger and
fan-out invariants:

- `state` is declared and written only in `act/session.gd` (`_set_state()`); `runtime.gd` keeps a
  read-only `state` forward and contains no `state` assignment;
- no `Input.`/`InputMap.`/input event/keycode read and no input callback in `runtime.gd`;
- `SETTINGS.<member>` reads only at the documented snapshot boundaries
  (`act/settings.gd:snapshot_values`, `live_preferences` and the static character-name lookup);
  the start recipe's own reads moved to `act/start.gd` and the rebuilt pose's config to
  `act/swap.gd` with their owners;
- the act modules' line ceilings: `act/session.gd` at 400 and every other act module at 300;
- child nodes only from the act audio owner (the act audio node) and the host's `start_tail_tuck`
  (the pose-scope tail tuck);
- the one teardown (`act/exit.gd:run()`, called only by the exit's own routes and
  `act/consent.gd:stop_with_her()`, with `runtime.force_stop()` exactly one line calling
  `_exit.force_stop()`), the `free_pose()` order and its three exact callers (`act/exit.gd:run`,
  `act/start.gd:_build_pose`, `act/swap.gd:release_pose`), the start recipe's order,
  the pose-before-facts write and the fan-out owner order in `act/tick.gd`, the session's two
  frame forwards, and the one `act/swap.gd:resume()`.

`owner_of()` treats every `act/**` file as the runtime's own orchestrator module: an act module may
preload a service, and a service that preloads `act/` fails as a host import.

The allow-lists are compared both ways: a new read or node fails, and a stale row fails too.

## Tests

- `tests/act/test_session.gd` — the one state writer and its scene-gate refresh, the phase timer
  verdicts (`POSING_IN` → `ACTIVE`, `CLIMAX`, `RESTORE`), the clock and act-seconds reset rules, the
  running-check cadence and the typed host/context no-op seam. The act line ceilings are
  `scripts/architecture.py`'s (`check_act_budgets`).
- `tests/test_runtime_teardown.gd` — the one exit path, the ownership flags, the oral edge's
  consent/feature refusals and its abort through the exit, the standing gap's princess
  entrance shift, and the whole-body fit that rests the shaft at her entrance with a stale Hips
  offset removed.
- `tests/test_input.gd` — the act-key hold and the input protocol route: `cancel`, the afterglow
  end and request, the auto layer, the mouse thrust and the free look all reach
  `runtime.act.input`, and the shield and capture rules are unchanged.
- `tests/test_runtime_notes.gd` — the prompt forwards.
- `tests/poses/test_pose_offer.gd` — the typed offer, the Agreement/hotkey outcome table and the
  one start path.
- `tests/poses/test_start_setup.gd` — the closed setup vocabulary, the synthetic
  `auto`/`bed_keep_lying` row and the `act/setup.gd` dispatch for both bed adapters.
- `tests/readiness/test_runtime_thrust.gd` — the readiness integration: the axes, the one-axis
  chunk, heat, the shared touch cooldown and the climax separation. The cycle override is written
  through `shared/cycle.gd` directly.
- `tests/readiness/test_oral_quiet.gd` — the oral contact: the plap and rump/tail jiggle skip, the
  kept slide/vocal/wings/blush/ear, the climax-line skip and the regular-path regression.
- `tests/handover/test_body_swap.gd` — the generic handover: suspend → adopt → resume, the state
  depth, climaxes and event id survive, the old runtime is not freed, the new body's anatomy and
  pose bind, adoption binds without resuming, a named form waits for its target, the target
  completes as the form, a missing form restores the offer on the new body, the watchdog with a
  body resumes as a failed form, a repeated change, a failed change, a provider that goes
  inactive, the no-body watchdog, an ineligible body, a world close during the swap, the debug
  form label, the player's offer surviving her own change, a late body adopted once, a change
  during the restore, a held body's refusal, the presented form's name in the act facts and the
  six generic milestones in order.
- `tests/summary/test_act_flow.gd` — the state flow and the afterglow HUD summary.
- `tests/afterglow/test_afterglow.gd` — the phase decisions, including the oral passive row.
- `tests/face/test_runtime_face.gd` — the climax mode, the face beat and the idle face guard.
- `tests/hands/test_actions.gd` — the gate report reason through the scene gate facade.
- `tests/anatomy/test_attach.gd` — the action gates closed without an act.
- `tests/stool/test_gate.gd` — the act handle's applies/required rule and the runtime's stool
  reads.
- `scripts/architecture.py --check` — the thin-runtime rules above, including the schedule's
  pose-before-view-before-fan-out order and the act-module ceilings.
- The service suites indexed in `docs/README.md`.

## Verification / lab

- A full missionary act: start, pose, thrust, climax, afterglow, hold-act-key end, cuddle rejoin.
- A full standing act: presentation, lean, reach, caress, movement, smack, kiss, afterglow close,
  act-key end.
- Early end (holding the act key at 0 climaxes) and a forced stop (Debug → Force neglect stop).
- A failed start: no stuck navigator, kiss hold, inventory HUD or camera lock.
- With an installed body-change provider, run a standing and a missionary act and use the Debug
  form actions: the flame covers the swap, the act resumes with the same depth and climaxes, the
  form's rig, anatomy and tail apply, and a second change starts after the first completes.

## Related docs

- `docs/README.md` — the service index.
- `docs/act_facts.md` — the typed act view.
- `docs/eligibility.md`, `docs/scene_gate.md`, `docs/scene_hold.md` — the start gates and scene.
- `docs/poses.md`, `docs/camera.md` — the tick-time pose and camera.
- `docs/input.md` — the input owner and the act key.
- `docs/integrations.md` — optional mod reactions during the act.
- `docs/afterglow.md`, `docs/face.md`, `docs/summary.md` — the post-act phases.
