# Act runtime

`runtime.gd` is the per-pony **Node host**. One exists for every non-player pony, parented under
the pony and idle outside an act. It owns existence, parenting, the reparent across a body swap,
the two engine frames and the world-close release; it owns no act rule and holds no act value.

The act itself is four layers, all under `act/`:

| Layer | Owner | Contract |
|---|---|---|
| Node | `runtime.gd` | lifetime, node operations, engine callbacks and the typed handles |
| Session | `act/session.gd` | act state, timers, clock, act values, transitions and the two frame forwards |
| Ledgers | `act/start.gd`, `act/exit.gd` | the ordered start recipe and the one teardown |
| Modules | `act/tick.gd`, `act/view.gd`, `act/idle.gd`, `act/input.gd`, `act/phases.gd`, `act/agreement.gd`, `act/consent.gd`, `act/impact.gd`, `act/swap.gd`, `act/setup.gd`, `act/settings.gd` | schedule, view, idle, input protocol, presentation, the start ports, consent, stroke, swap seams and the start adapters |

`act/build.gd` constructs every one of them once per pony and binds their typed hosts. The systems
(readiness, poses, camera, audio, face, reactions, dialogue, summary, afterglow, anatomy, hands,
kiss, wings, integrations, scene gate, scene hold, rest) own their own state and math.

## Node

- Scope: per-pony. Constructed by `ponies/service.gd` through the entry's one factory on the body's
  attach hook; parented under the pony and recorded in the registry.
- `_init(hud, memory, stool)` calls `ACT_BUILD.build(null, self, hud, memory, stool)` once and
  stores the returned bundle. The entry's factory passes the three world facades; a bare `new()`
  leaves them null and the per-pony modules treat that as an absent HUD, memory or stool.
- `_ready()` sets process and physics on at priority `100` (after locomotion, the navigator and
  attention), reads the identity, binds the pony through the bundle, caches the idle probe flag,
  binds the face, refreshes the persistent anatomy controller and retries the identity and anatomy
  reads after the first frame.
- `_physics_process(delta)` is one `act.tick(delta)`; `_process(delta)` is one `act.render(delta)`.
- `pony` is the presented body; its setter rebinds the pose session and the act host through the
  bundle. `live_id()` refreshes the identity and returns the stable act id.
- `attach_to_body(parent)` reparents the live runtime under another node for the handover and sets
  `_swapping_parent`, so the `_exit_tree()` that `reparent()` fires is a no-op.
- `adopt_body(new_pony)` adopts the handover's new body, binds it through the session
  (`bind_adopted_body`), ends a non-adult body through the one exit and refreshes the game LOD.
- End: pony despawn, world close or mod shutdown. `_exit_tree()` releases the kiss forelegs, the
  stool, the tail tuck, the aftercare, the anatomy act and the face, and clears the pending
  body-swap record. The audio node and the pose-scope tail tuck are system-owned children created
  by their owners, not by the node.

The node's public surface is exactly:

| Surface | Contract |
|---|---|
| `act` | the typed `ActSession` handle (`act/session.gd`) |
| `scene` | the per-pony `SceneGate` handle (`scene_gate/service.gd`) |
| `start` | the per-pony start handle (`shared/start_port.gd`, implemented by `act/agreement.gd`) |
| `presentation` | the per-pony presentation handle (`shared/presentation_port.gd`, implemented by `act/session.gd`) |
| `pony` | the presented body |
| `live_id()` | the stable pony id the entry and `ponies` read |
| `attach_to_body()` | the handover's reparent off the old body |
| `adopt_body()` | the handover's reparent onto the new body |
| `_init`, `_ready`, `_physics_process`, `_process`, `_exit_tree` | the engine callbacks |

`scripts/architecture.py` holds this list as `NODE_SURFACE` (functions) and `NODE_PROPERTIES`
(properties) and compares both directions: a new public member fails and a stale row fails.

## Ownership

| State | Owner |
|---|---|
| pony, parent, `_swapping_parent` | `runtime.gd` |
| stable id, display name, serial | `ponies/service.gd` identity |
| act state, timers, clock, `pose_id`, `source`, `bed`, `event_id`, `serial`, act flags | `act/session.gd` |
| act settings snapshot and live apply | `act/settings.gd`, reached through the session |
| satisfaction, mood, cue, climax count, tolerance, heat | `readiness/service.gd` |
| swap record, form offer/reveal/policy | `body_change/act.gd` |
| suspension flag | `body_change/act.gd`, read through `session.suspended()` |
| pose, pose view, bones | `poses/service.gd` |
| lean, surge/bob, free look | `camera/service.gd` |
| act view, glance, facing lock, eye | `camera/view.gd` |
| player placement, stance, restore, scene token | `act/frame.gd` |
| audio, voice | `audio/act.gd` |
| aftercare plan, satisfaction decay, close window | `afterglow/service.gd` |
| face/eyes, reactions, dialogue, hands, kiss, wings, integrations, anatomy | their services |
| act view | `shared/act_facts.gd`, filled by `act/view.gd` |
| injected HUD, memory and stool | the entry's factory, passed to `RUNTIME.new()` and `act/context.gd` |

No value is mirrored in two owners. The session is the one state writer: `act/session.gd:_set_state`
is the only assignment to `state`, and it refreshes the scene gate's live state.

## State machine

```text
IDLE → POSING_IN → ACTIVE → CLIMAX → AFTERGLOW → RESTORE → IDLE
```

- `IDLE`: no act; the runtime is attached and runs the idle schedule.
- `POSING_IN`: the start ledger has run and the pose is building.
- `ACTIVE`: thrusting, readiness, cues, caress and the pose actions are live.
- `CLIMAX`: the pony's 5 s climax; thrusting continues but does not score.
- `AFTERGLOW`: the held post-act phase, the standing close window and normal dialogue.
- `RESTORE`: the teardown ledger runs; the act returns to `IDLE` at the end.

`shared/act_state.gd` is the one typed definition (`ACT_STATE.State`), aliased in the session as
`State`. The session's transition helpers write the state and arm its timer (`begin_pose_in`,
`enter_active`, `enter_climax`, `enter_afterglow`, `begin_restore`, `finish_restore`, `enter_idle`).

| From | To | Trigger |
|---|---|---|
| `IDLE` | `POSING_IN` | the end of `act/start.gd:run()` |
| `POSING_IN` | `ACTIVE` | the session's pose-in timer |
| `ACTIVE` | `CLIMAX` | a pony climax |
| `CLIMAX` | `ACTIVE` | the session's climax timer while the player keeps going |
| `ACTIVE` / `CLIMAX` | `AFTERGLOW` | a close request or the act-key hold with a climax behind it |
| `AFTERGLOW` | `RESTORE` | `end_afterglow()` or a cancel |
| any live state | `RESTORE` | `cancel()` or `force_stop()` |

Breath timing: `0.9 s` base while active, `0.85 s` during climax, `1.4 s` in afterglow.

## Session

`runtime.act` is the session. It owns:

- state and clock: `state`, the one writer `_set_state`, `_act_seconds`, `_clock_s`,
  `_pose_in_left`, `_climax_left`, `_restore_left`, `_check_clock` and the climax progress.
  `reset_act()` clears the clock and timers; `tick_timers(delta)` reports the one transition
  verdict and the frame schedule applies it. `act_seconds()`, `clock_s()` and
  `climax_progress()` are the typed reads.
- frame handles: `ticker` (the ordered schedule), `input` (the input protocol), `start`, `view`,
  `exit` and `swap`. `tick(delta)` and `render(delta)` are the two one-line forwards to `ticker`.
- values: `pose_id`, `source`, `bed`, `pony_id`, `display_name`, `event_id`, `serial`,
  `preferences`, `profile`, `player_pony`, `forced_glance`.
- act bookkeeping: `aftercare_min`, `cue_gap`, `first_time`, `stopped_by_her`, `act_spoken_at`,
  `ended_early`, `cycle_heat`, `preserve_auto_shape`, `posture_owned` and `finalized`.
- typed reads the host bindings use instead of reading a field: `state_value()`, `act_live()`,
  `restoring()`, `suspended()`, `act_id()`, `start_id()`, `event_id_value()`, `climax_limit()`,
  `cue_reaction_max_age()`, `current_pose_id()`, `in_heat()`, `rest_context()` and the service
  handles `kiss_service()`, `reactions_service()`.

`refresh_identity()` re-reads the stable identity from the presented body, adopts its display name
through `PONIES.display_name_for()` and refreshes the scene gate. `live_id()` is one Node caller;
`cycle_phase()` re-reads it only when the body's relationship meta moved; the bond-day phase is
cached for `CYCLE_REFRESH_S`, while the feature switch and the debug override stay live.

The act settings snapshot lives in `act/settings.gd`: one `SETTINGS.ActSnapshot`, the feature
flags, the presentation block, and the climax limit and mode.
`snapshot_settings()` is the one bulk snapshot at act start and again at the top of
`apply_live_settings()`, before the `IDLE` early return. The session exposes typed read-throughs
(`snapshot`, `features`, `presentation_config`, `max_pony_climaxes`, `climax_mode`); no second
per-frame settings read exists, and a zeroed snapshot stands in until the first act.

The session dispatches; the owners keep the bodies. `act/view.gd` composes the act values the
owners read: the face beat and rows, the climax line, the summary input, the prompt note, the debug
context and the render pose write. `act/context.gd` carries the live systems and no callables.

## Builder

`act/build.gd` is the one composition root and a plain struct builder. `Bundle` holds typed fields
plus `bind_pony(value)`, which the `pony` setter and `_ready()` call to rebind the pose session's
body and id and the act host's pony. There is no second bind pass and no facade re-export.

`build(pony, node, hud, memory, stool)` constructs, in order:

1. the early modules (`input`, `swap`, `tick`, `phases`, the pose session, the scene gate, rest,
   the camera facade, readiness, summary, face, reactions, the act view, dialogue, afterglow, the
   scene hold) and the empty typed hosts the bridge and the handover will hold;
2. `_build_systems()`: the handover, wings, hands, kiss, integrations, the one live view, the two
   standing body controllers, the camera and audio bindings;
3. `_bind_act_frame()`: `act/host.gd` (node operations), `act/context.gd`, `act/settings.gd`,
   `act/session.gd`, consent, impact, view, idle, exit, input, swap, phases, tick, setup, start,
   agreement and their sibling handles;
4. the two service-owned hosts: `AnatomyHost` and `BodyChangeHost` implement their ports from the
   bundle, so there is no callback pass;
5. `_bind_pose_hosts()` and `_bind_facts()`: the pose, readiness, face, reactions, gate, rest,
   scene-hold, afterglow and act-view callbacks;
6. the bridge's host bind, the scene gate's bind and its one configuration.

The three world facades are injected, never static: `Bundle` holds `hud`, `memory` and `stool`;
`act/context.gd` carries `hud`, `memory` and `stool_service`; `afterglow`, `summary`, `face`,
`dialogue` and the handover receive memory through their constructor; `anatomy` receives the HUD in
`setup(hud)`, `negotiation` and `debug/actions` in their `bind()`, and `offer` at construction. A
null facade is an absent one: the act modules guard every call, and a bare runtime remains valid.

Every callback names its owner rather than a runtime method:

- act state and act values are session accessors (`b.act.state_value`, `b.act.act_id`, …);
- a system value is its own service's method (`b.readiness.depth_value`,
  `b.camera.view_controller`, `b.pose._bed_frame_value`, …);
- node and scene operations are `act/host.gd` (`pony_value`, `runtime`, `director`, `mod_enabled`,
  `vr_scene`, `near_mesh`, `tier`);
- logging is `shared/log.gd` (`debug`, `warning`, `error`, `block`);
- anatomy reads are `anatomy/act_bridge.gd` (`mouth_point`, `opening`, `face_point`,
  `set_oral_viseme`, `gaze_point`, `set_missionary_anon`, …).

There is no `Callable(node, "_method")` left in the builder. The checker still validates any that
would be introduced against `runtime.gd`'s functions.

The anatomy bridge receives the typed `anatomy/act_host.gd`, and the body change receives the typed
`body_change/act_host.gd`; no service locator or host dictionary is passed.

## Schedule

`_physics_process` is one `act/tick.gd:tick(delta)` call and `_process` one `render(delta)` call.
The schedule's physics frame ends with the anatomy `sync_facts()` write, so the persistent anatomy
controller's own `_process` poll reads the frame's live state, pose, depth and bed frame.

Act physics, in call order (`act/tick.gd:_tick`):

1. `act/swap.gd:tick(delta)` — the handover's one tick; a suspension returns here.
2. `session.tick_clock(delta)`; then `context.pose.tick(delta)` when the state is not `IDLE`,
   timed as `pose_tick`.
3. `session.refresh_view()` → `act/view.gd`, timed as `runtime_facts`.
4. `act/tick.gd:_fanout()` when the state is not `IDLE`, timed as `pose_fanout`.
5. `IDLE`: `act/idle.gd:tick(delta)` runs the inventory safety, the standing presentation's
   physics and the dialogue history scan, then returns. It runs no pose tick or fan-out.
6. The act body: the cycle heat signal, the pose-frame sync, waking her, the vocal tick, the
   navigator keep-alive, free look, act attention, the face-turn pause, the lean tick,
   `act/phases.gd:presentation()` (timed `runtime_presentation`), the consent frame, the settled
   log, the kiss tick, auto, impact and the anatomy tick, and, in `ACTIVE`, readiness, talk, the
   form offer and the bystanders (timed `runtime_talk`).
7. The utterance tick, then `session.tick_timers(delta)`: the returned verdict is applied by
   `enter_active_act()`, `finish_climax()` or `act/exit.gd:finish_restore()`; the climax hearts
   tick while `CLIMAX`, and `afterglow/service.gd:phase_tick()` runs while `AFTERGLOW`.
8. The camera block (facing lock, glance, auto-cuddle suppression, clamp, depth, Anon phase,
   blush, `session.apply_camera_motion()`), the session's `0.25 s` check window (the scene gate's
   running verdict applied through `act/exit.gd:stop()`) and the face's eyes.

Act render, in call order: `refresh_view()`, `context.pose.sync_frame()`,
`session.pose_render_write()`, `context.pose.idle_sample()`, the standing clamp, the camera look
write, the climax progress, the shot tick and the breath. `IDLE` runs only the standing
presentation's render tick; a suspended act runs none of it.

The entry's `_process` calls `PONIES.active()` and then `apply_camera_motion()` on it every frame;
the runtime refreshes the view and the HUD card there through `act/view.gd`. The pose and camera
timing is `docs/poses.md` and `docs/camera.md`. The frame schedule never calls an act exit except
through `act/exit.gd`'s own routes (`finish_restore`, `stop`, `force_stop`).

## Ledgers

### Start

`offer.try_start()` is the act key's only entry (`docs/offer.md`). It hands a typed offer to
`offer.start_pose_offer(offer)`. The idle scan builds its offer from the bed side or the
free-standing fan; a live Agreement builds `trigger: "agreement"` from its frozen option and the
scene-only rows.

The live start paths share the one body (`act/start.gd:run()`; `act/session.gd:begin()` is its one
entry). The three entry points live in `act/agreement.gd`:

- **The hotkey** runs `runtime.start.start_hotkey()`: the scene gate's `hotkey_ready()` (the small
  scene checks plus Base clearance), then `act/start.gd:run()`. No policy row, no offer
  cooldown, no buck and no history refusal.
- **The Agreement** runs `runtime.start.start_agreement(handle)`: the scene-only rows with the
  frozen pose capability (`scene_only_verdict`), then `act/start.gd:run()`. It answers
  `AGREEMENT_WAIT`, `AGREEMENT_STARTED` or `AGREEMENT_FAILED`; the offer, its only caller, reports
  `Started` or `StartFailed` to the Negotiation service.
- **Auto-start** consumes a live Agreement with no key press; `negotiation/service.gd:ready_offer()`
  decides whether the live scene accepts it, and the offer cancels a private Agreement whose fresh
  privacy sample is now public.

The start sequence:

1. `act/agreement.gd` re-reads the identity and the gate (the Agreement path runs the scene-only
   rows); `run()` opens with the presentation guard;
2. bind the act's stool handle through `act/session.gd:stool()` and reset it, then refresh the
   anatomy bridge;
3. clear the idle presentation, the mood face and the act face;
4. snapshot the settings and preferences, build the profile and prompts;
5. resolve the bed when the row's `scene.requires_bed` is set (a missing bed fails closed before
   anything is borrowed), then set the initial face;
6. allocate the serial/event id, reset readiness, dialogue, history and the thrust state;
7. release the cradle/cuddle/navigator/player ownership through `scene_hold`;
8. snapshot the pony bones, mark the act active, build the anatomy act;
9. dispatch the row's `start.setup` (below) to place the bodies;
10. build the pose, run the player frame's `begin()` (place him, station his stance, park the
    avatar, lock his controls and capture the scene), sync the start settings group, mount the
    view for a bed act, open the act camera, lock the navigator, start the audio, the HUD and the
    act face, then arm the act integrations.

A failure in any step runs the one partial-start funnel, `act/start.gd:abort()` (the act's end
lines, the one exit, then finalize as a failed start); it never leaves a partial act.

### Start setup adapters

`act/start.gd:run()` matches the pose row's closed `start.setup` name and never a pose id; it
passes the name to `act/setup.gd:run()`.

| Setup | Adapter | Placement |
|---|---|---|
| `bed_stand_up` | `act/setup.gd:bed_stand_up()` | a human Anon `force_stand_up()`; the cradle or bed rest release already ran in the prelude; `request_posture("stand")`; the bed frame |
| `bed_keep_lying` | `act/setup.gd:bed_keep_lying()` | no `force_stand_up()`; a `dialogue` source releases managed rest; `request_posture("stand")` so the authored act body owns her pose; the bed frame |
| `standing_place` | `act/setup.gd:standing_place()` | `request_posture("stand")`; `act/start.gd` then runs `context.frame.begin()`, which places her player-pony/headset rig in front or Anon behind her, checks the stool and writes the view's `begin_facing()` |

A missing bed fails the two bed adapters closed; a failed cradle/bed rest release already aborted
in the prelude. An unknown or missing setup logs one `start blocked setup=...` line and aborts
through the partial-start funnel; the gate already passed, so this is a spec/data error.

The start settings-group sync (`sync_start_pose_config()`) reads the row's `settings_group`, not the
pose id; `act/start.gd` mounts the act view for the `bed` family and opens the camera once.

### Exit

`act/exit.gd:run(rejoin_cuddle)` is the only exit body. The exit's own routes are its only callers,
plus `act/consent.gd:stop_with_her()` for a partner stop: `cancel()`, `end_afterglow()`,
`restore_begin()`, `finish_restore()`, `restore_now()`, `force_stop()` and `stop(reason)`.
`act/session.gd:force_stop()` is the one-line session delegate `ponies` calls. It gives back, in
order: the auto stroke, the handover, the inventory HUD, kiss forelegs, face-turn rate, the player
frame (`frame.end()`: stance, look, controls, avatar hold), the act view (`view.unmount()`), face
and wings, player lock, camera, stool, `sex_active`, navigator, posture/cuddle, pose, audio, HUD
and the active runtime. Every step checks the ownership flag it
restores, so a failed start runs the same body and restores only what it took.

- `act/exit.gd:finalize(real_act)` runs the post-act bookkeeping once and is idempotent;
  `finish_restore()`, `restore_now()` and `force_stop()` enter `run()` inside the same ledger.
- The act's end lines are deliberately outside the teardown: `cancel()` queues the early-stop
  reaction after `restore_begin()`, and `finish_restore()` must not cancel director rows.
- The pose part is one ledger: `run()` calls `free_pose()` and then restores the pony bones through
  `context.pose.restore_bones()`. `free_pose()` runs the session's pose-scope steps
  (`leave_pose_start()`, `leave_pose_body()` and the final `release_pose()`), resets the
  mod-integration bridge after the base kiss, releases the shared excitement Beat hold and leaves
  every property the act borrowed back in place. `act/start.gd:_build_pose()` calls the same
  ledger as the new-act prep, so a pose left from the offer cannot stack.
- `context.camera.finish_act()` is the act camera's own end: it drops the lean, the Anon wrapper,
  the palm scale, the smoothed state and the act view after `frame.end()` gave the player back. It
  is an act-level path, not part of the pose teardown.
- A forced stop never rejoins the missionary bed cuddle. A normal end of a bed-sourced act that did
  not go badly re-seats Anon on the bed's player seat and re-invites her through `rest/service.gd`.

The afterglow, close window and aftercare are `docs/afterglow.md`; the face and mood are
`docs/face.md`; the summary is `docs/summary.md`.

### Suspend, adopt and resume

A body-change provider can replace the act pony's presented body without ending the act; the
mechanism, the typed form and the source/binding contracts are `docs/body_change.md`.

`act/swap.gd:tick()` applies one typed action from `body_change/act.gd`: `NONE`, `SUSPEND`,
`RESUME`, `FAIL` or `END_RESTORE`. `body_change/act.gd:release(change)` stops the act's work and
records one pending swap. `act/swap.gd` is the typed bridge from the handover's host callbacks to
the live systems: `tick`, `suspend`, `resume`, the ordered release and resume steps, the adoption
and revised-form rebinds, the frame refit and `standing_gap()` for the offer and the suites. It
never reparents the node or resumes by itself.

- one pending swap is recorded in `ponies`; a second change is refused until it clears;
- the runtime is reparented to the entry before the old body is freed;
- the pose session, the anatomy act handle, the navigator lease, the face-turn hold, the act view,
  the kiss/hand contact, the wings, the carried body and the act-key hold are released; the
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
`body_change/act.gd:rebind()` (clear the smoothed shot and `frame.refit()` the new form, which
re-places a standing Anon at the new gap and stance without an entrance), restarts auto at its
preserved values and state, reopens the camera, re-claims the new navigator, pauses the new
face-turn rate, rebinds the face, voice, wings and integrations, and refreshes the HUD facts.

Failure paths keep the one exit: a failed handover or a watchdog calls `force_stop()`; an
ineligible new body ends through `act/swap.gd:end_non_adult()` and `force_stop()`; a world close or
a force stop while suspended clears the pending record and runs `act/exit.gd:run()`.

`reparent()` runs `_exit_tree()`. The runtime's `_swapping_parent` flag makes that signal a no-op
during the handover. `attach_to_body()` is the only route that sets it.

### Form interaction

The game's talk turn (`T`/microphone) is the only player interaction; there is no new key, picker
or settings row. `_handover.player_line_tick()` reads a new director turn in `ACTIVE`, the same
turn the readiness classifier scores, and passes its text to the typed source:

- a source that wears another form consumes a reveal ask through `asks_form_change(text)`; a
  successful `runtime.act.request_form_change(true, "", true)` marks the change as the player's;
- with the post-climax offer pending, a line that names an adult mare through `named_form(text)`
  starts `request_form_change(false, id, true)`; `named_form_note(text)` supplies a short status
  for a worn, own, young/male or uncopyable name and returns nothing for ordinary talk;
- anything else is ordinary talk and is left to readiness and dialogue.

The provider policy owns the offer timing and prompt (`docs/body_change.md`, `## Provider policy`).
`_handover.offer_tick()` keeps the once-per-act gate and queues one `FORM_OFFER` reaction when
`policy.should_offer(context)` first returns true. The offer is deliberately not made in `CLIMAX` or
`AFTERGLOW`. An unanswered offer ends with the act; the next act may offer again; a failed named
change restores the offer.

A completed player-named change calls `policy.on_offer_accepted(context)`; a completed
player-requested return to her own form calls `policy.on_reveal(context)` once. The base runtime
executes the generic effects: a readiness heat spike and a cue while the act is `ACTIVE`, the
reveal's peak and `form_reveal` memory mark, the exceptional face beat, and the `form_reveal` input
the summary/act-history commit reads for an extra great-act comfort. The handover dispatches the
generic policy milestones through one helper: `ACTIVE`, `CLIMAX_END`, `AFTERGLOW`, `OFFER_ACCEPTED`,
`REVEALED` and `FORM_SETTLED`.

`_handover.hint_tick()` is a debug log probe, not a HUD source. It names the reveal ask while she
wears another form and the name prompt while the offer is pending, but only when **Enable debug**
was on at the act's settings snapshot. `_form_hint` itself is always empty, so neither a release
nor a debug build puts the dialogue channel on the HUD. The debug label clears at the climax,
afterglow, restore, suspension and act end.

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

## View and protocol

`act/view.gd` composes the typed act view (`shared/act_facts.gd`) from the session, the context and
the host. `session.refresh_view()` is the one call: the physics frame, the render frame, the idle
pass and the `apply_camera_motion()` hand-off all call it. It runs once per phase: idle before the
idle systems, physics after the pose tick and before the fan-out, render before the camera work.
`act/view.gd:sync_hud()` adds the HUD card's live values and runs from `apply_camera_motion()` and
the act boundaries; the HUD reads fields and never probes the runtime. The view keeps raw values;
`shared/act_facts.gd` owns the field list, and the HUD strings live in `hud/service.gd` and
`hud/lines.gd`.

`runtime.act.facts()` is the typed view. `runtime.act.pose_view()` and the input protocol's
`request_pose(target_id, trigger, request)`, `request_command(command_id)` and `command(command_id)`
are the pose surface. `request_command(id)` is the pure allow check: `end` is reserved and always
allowed, otherwise the id must be in the active pose's control profile and the live edge lock must
not deny it. `command(id)` runs that check first, then dispatches the discrete `hole` id and `oral`
to the anatomy bridge; the act-key hold still owns the one exit path.

The standing start/offer gap is `runtime.act.swap.standing_gap(form)`: it asks
`act/frame.gd:standing_gap()`, which reads `context.pose.pose_config["gaps"]` (falling back to
`SETTINGS.pose(id, "standing").rows("gaps").raw()` in a session without a config) and adds the
entrance's back offset for a princess body. The shipped values live under
`default.poses.standing.gaps`; the frame keeps no gap table or numeric fallback.

That gap is the pre-act view, not the contact distance. Before the act, `act/frame.gd:begin()` places
Anon at the gap on her centreline; there is no whole-body fit and no start measurement of the
animated part. It clears the part's old Hips handshake (`player_reset_pelvis()`) after placing him,
and `refit()` repeats the placement on a body resume or a same-node form revision. The per-frame
aim owns the stroke's pelvis correction.

The cross-mod surface is `docs/api.md`. A new public function or property on the node is a
regression; everything else reads the session, the gate or the owning service.

## Checker

`scripts/architecture.py --check` enforces the host shape in addition to the exit, pose-ledger and
fan-out invariants:

- `state` is declared and written only in `act/session.gd` (`_set_state()`); `runtime.gd` has no
  `state` field and contains no `state` assignment;
- `NODE_SURFACE` and `NODE_PROPERTIES` fix the node's public surface (`act`, `scene`, `start`,
  `presentation`, `pony`, `live_id`, `attach_to_body`, `adopt_body`); both lists are compared both
  ways, and the engine callbacks are private;
- no `Input.`/`InputMap.`/input event/keycode read and no input callback in `runtime.gd`;
- `runtime.gd` contains no settings read; `act/settings.gd` is the act's one snapshot boundary
  (`snapshot_values` and `live_preferences`), and every `SETTINGS.<member>` read there is a named
  allow-list row;
- `runtime.gd` creates no child node; the act audio node and the pose-scope tail tuck are created by
  their owners;
- a file over 1,000 lines prints `SMELL large file` and does not fail; size is information, not a
  hard gate, and no line, function or preload cap exists;
- every `Callable(node, ...)` in `act/build.gd` must name a function `runtime.gd` defines (the
  current builder has none);
- the one teardown (`act/exit.gd:run()`, called only by the exit's own routes and
  `act/consent.gd:stop_with_her()`, with `act/session.gd:force_stop()` exactly one line calling
  `exit.force_stop()`), the `free_pose()` order and its three exact callers (`act/exit.gd:run`,
  `act/start.gd:_build_pose`, `act/swap.gd:release_pose`), the start recipe's order, the
  pose-before-facts write and the fan-out owner order in `act/tick.gd`, the session's two frame
  forwards, and the one `act/swap.gd:resume()`.

`owner_of()` treats every `act/**` file as the runtime's own orchestrator module: an act module may
preload a service, and a service that preloads `act/` fails as a host import.

## Tests

- `tests/act/test_session.gd` — the one state writer and its scene-gate refresh, the phase timer
  verdicts (`POSING_IN` → `ACTIVE`, `CLIMAX`, `RESTORE`), the clock and act-seconds reset rules and
  the typed host/context no-op seam.
- `tests/test_runtime_teardown.gd` — the one exit path, the ownership flags, the oral edge's
  consent/feature refusals and its abort through the exit, the standing gap's princess entrance
  shift, and the frame placement that leaves Anon at the gap with a stale Hips offset removed.
- `tests/test_input.gd` — the act-key hold and the input protocol route: `cancel`, the afterglow
  end and request, the auto layer, the mouse thrust and the free look all reach
  `runtime.act.input`, and the shield and capture rules are unchanged.
- `tests/test_runtime_notes.gd` — the prompt forwards through `runtime.act`.
- `tests/offer/test_start.gd` — the typed offer, the Agreement/hotkey outcome table and the one
  start path.
- `tests/poses/test_start_setup.gd` — the closed setup vocabulary, the synthetic
  `auto`/`bed_keep_lying` row and the `act/setup.gd` dispatch for both bed adapters.
- `tests/readiness/test_runtime_thrust.gd` — the readiness integration: the axes, the one-axis
  chunk, heat, the shared touch cooldown, the climax separation and the climax limit through
  `runtime.act.max_pony_climaxes`.
- `tests/readiness/test_oral_quiet.gd` — the oral contact: the plap and rump/tail jiggle skip, the
  kept slide/vocal/wings/blush/ear, the climax-line skip and the regular-path regression.
- `tests/handover/test_body_swap.gd` — the generic handover: suspend → adopt → resume through
  `runtime.act.swap`, the state, depth, climaxes and event id survive, the old runtime is not
  freed, the new body's anatomy and pose bind, adoption binds without resuming, a named form waits
  for its target, the target completes as the form, a missing form restores the offer, the
  watchdog with a body resumes as a failed form, a repeated change, a failed change, a provider
  that goes inactive, the no-body watchdog, an ineligible body, a world close during the swap, the
  debug form label, the player's offer surviving her own change, a late body adopted once, a change
  during the restore, a held body's refusal, the presented form's name in the act facts and the
  six generic milestones in order.
- `tests/summary/test_act_flow.gd` — the state flow and the afterglow HUD summary.
- `tests/afterglow/test_afterglow.gd` — the phase decisions, including the oral passive row.
- `tests/face/test_runtime_face.gd` — the climax mode, the face beat and the idle face guard.
- `tests/hands/test_actions.gd` — the gate report reason through the scene gate facade.
- `tests/anatomy/test_attach.gd` — the action gates closed without an act.
- `tests/stool/test_gate.gd` — the act handle's applies/required rule and the stool reads.
- `scripts/architecture.py --check` — the host rules above and the schedule's
  pose-before-view-before-fan-out order.
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

The labs and the in-game perf checkpoint need a display and a person at the keyboard; they are not
part of the headless gate.

## Related docs

- `docs/README.md` — the service index.
- `docs/act_facts.md` — the typed act view.
- `docs/eligibility.md`, `docs/scene_gate.md`, `docs/scene_hold.md` — the start gates and scene.
- `docs/poses.md`, `docs/camera.md` — the tick-time pose and camera.
- `docs/input.md` — the input owner and the act key.
- `docs/integrations.md` — optional mod reactions during the act.
- `docs/afterglow.md`, `docs/face.md`, `docs/summary.md` — the post-act phases.
