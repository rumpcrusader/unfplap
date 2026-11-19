# Act runtime

`runtime.gd` is the per-pony host and act orchestrator. One Node exists per non-player pony,
parented under the pony, and it is idle outside an act: it runs the standing presentation, the
dialogue history scan, the anatomy sync and the inventory safety. It owns lifetime, the state
machine, the act session, the one composition and bind pass, the ordered schedules, the
start/suspend/exit ledgers and the typed act view. It implements no system's rules and owns no
system's mutable state. The service contracts are indexed in `docs/README.md`.

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
| State machine | states, the pause overlay, timers, one `_set_state()` writer |
| Session | pony/id/display, `pose_id`, `source`, `bed`, `_event_id`, `_serial`, the act clock, the settings snapshot, preferences/profile/prompts/features |
| Composition | `_build_systems()` and `_bind_pose_hosts()`, one typed field per system, one bind pass |
| Schedules | idle, physics and render, each an ordered list of one-line calls |
| Ledgers | start, suspend release, resume rebuild, the one exit, finalize-once, partial-start safety |
| View | the typed act view composed once per phase |
| Protocol | start request/answer, force stop, cancel/afterglow, the input protocol, `live_id`, `act_view`, `prompt_note` |

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

`shared/act_state.gd` is the one typed definition (`ACT_STATE.State`), aliased in the runtime as
`State`. `state` has exactly one writer, `_set_state(next)`; it also refreshes the scene gate's live
state. States advance from the ordered ticks:

| From | To | Trigger |
|---|---|---|
| `IDLE` | `POSING_IN` | the end of `_begin_act()` |
| `POSING_IN` | `ACTIVE` | the `POSE_IN_SECONDS` timer |
| `ACTIVE` | `CLIMAX` | a pony climax |
| `CLIMAX` | `ACTIVE` | the `CLIMAX_SECONDS` timer while the player keeps going |
| `ACTIVE` / `CLIMAX` | `AFTERGLOW` | `request_afterglow()` or the act-key hold with a climax behind it |
| `AFTERGLOW` | `RESTORE` | `end_afterglow()` or a cancel |
| any live state | `RESTORE` | `cancel()` or `force_stop()` |

Breath timing: `0.9 s` base while active, `0.85 s` during climax, `1.4 s` in afterglow.

## Session

The act session is the runtime's own state, reset at each start:

- identity: `pony`, `_id`, `_display_name` (the presented form's name with the identity fallback);
- pose: `pose_id` (the start identity), `source`, `bed`, and the pose session handle;
- event: `_serial` from `PONIES.allocate_serial()`, `_event_id` as `intimacy_<id>_<serial>`;
- clocks: `_act_seconds`, the processed-time `_clock_s`, the phase timers, `_check_clock`;
- settings: `_snapshot`, `_features`, `_profile`, `_preferences`, `_act_prompts`,
  `_presentation_cfg`, `_eye_camera_mode`;
- act values: the readiness forwarders (`satisfaction`, `mood`, `cue`, `pony_climaxes`, `depth`,
  `penetration_m`), `_max_pony_climaxes`, `_act_climax_mode`, `_cycle_heat`, the summary handle.

`_snapshot_settings()` is the one writer of the `SETTINGS.ActSnapshot` and all derived scalars. It
runs at act start and again at the top of `apply_live_settings()`, before the `IDLE` early return.
A consumer reads `_snapshot.<value>` at the use site; no second per-frame settings read exists. A
zeroed snapshot stands in until the first start or settings edit, so an idle read sees the same
zero values the old fields defaulted to.

`_max_pony_climaxes` and `_act_climax_mode` stay ordinary fields because the thrust, handover and
face suites set them directly; the snapshot remains their act-start writer. `_features` and
`_presentation_cfg` stay as references into the snapshot because the idle view refresh, the start
sequence and the suites read them outside or across an act.

## Composition

`_init()` runs the one construction and bind pass:

- `_build_systems()` constructs the handover, placement, wings, hands, kiss, integrations, the two
  camera controllers, the two standing body controllers and the camera session, then binds the
  camera's sessions.
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

`_physics_process` runs `_physics_tick(delta)` and then one `_sync_anatomy_facts()` call, so the
persistent anatomy controller's own `_process` poll reads the frame's live state, pose, depth and
bed frame. `_process` runs `_process_tick(delta)` and the perf tick.

Act physics, in call order:

1. `_body_swap_tick(delta)` — one handover tick; a suspension returns here.
2. `_clock_s` advances; `_pose_service().tick(delta)` advances the pose edge.
3. `refresh_view()` — the typed act view, timed as `runtime_facts`.
4. `_pose_fanout()` — pose service, camera, hands, kiss, anatomy and audio.
5. Act-only work: the cycle heat flag, the pose frame sync, waking her, the vocal tick, the
   navigator keep-alive, free look, act attention, the face-turn pause, the lean tick, the act
   presentation (blush, wings, integrations), tolerance, the settled log, kiss, auto/impact and
   the anatomy tick; `ACTIVE` also runs readiness, talk, the form offer and bystanders.
6. The utterance tick, then the state timers (`POSING_IN` → `ACTIVE`, `CLIMAX`, `AFTERGLOW`,
   `RESTORE`).
7. The camera block (facing lock, glance, auto-cuddle suppression, clamp, depth, Anon phase,
   blush, `apply_camera_motion()`), the 0.25 s running check and `_eyes_tick()`.

`IDLE` still follows steps 1–4, then runs the inventory safety, the standing presentation's
physics, the dialogue history scan and their perf chunks, and returns. It runs no pose tick or
fan-out.

Act render, in call order: `refresh_view()`, `_sync_pose_frame()`, `_pose_render_write()`,
`_idle_pose_sample()`, the standing clamp, the camera look write, the climax progress, the shot
tick and the breath. `IDLE` runs only the standing presentation's render tick.

The entry's `_process` calls `PONIES.active()` and then `apply_camera_motion()` on it every
frame; the runtime refreshes the view and the HUD card there. The pose/camera timing is
`docs/poses.md` and `docs/camera.md`.

## Ledgers

### Start

`offer.try_start()` is the act key's only entry (`docs/offer.md`). It hands a typed offer to
`offer.start_pose_offer(offer)`. The idle scan builds its offer from the bed side or the
free-standing fan; a live Agreement builds `trigger: "agreement"` from its frozen option and the
scene-only rows.

The live start paths share the one body (`runtime._begin_act()`):

- **The hotkey** runs `runtime.start_hotkey()`: the scene gate's `hotkey_ready()` (the scene-only
  rows plus Base clearance), then `_begin_act()`. No policy row, no offer cooldown, no buck and no
  history refusal.
- **The Agreement** runs `runtime.start_agreement(handle)`: the scene-only rows with the frozen
  pose capability (`scene_only_verdict`), then `_begin_act()`. It answers `AGREEMENT_WAIT`,
  `AGREEMENT_STARTED` or `AGREEMENT_FAILED`; the offer, its only caller, reports `Started` or
  `StartFailed` to the Negotiation service.
- **Auto-start** consumes a live Agreement with no key press; `agreement_offer_ready()` decides
  whether the scene and the settled presentation accept it.

The start sequence:

1. re-read the identity and the gate (the Agreement path runs the scene-only rows);
2. reset the stool handle and refresh the anatomy bridge;
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

A failure in any step runs `_abort_start()` and the same teardown; it never leaves a partial act.

### Start setup adapters

`_begin_act()` matches the pose row's closed `start.setup` name (`_run_start_setup`) and never a
pose id. The names and their placement:

| Setup | Adapter | Placement |
|---|---|---|
| `bed_stand_up` | `_start_bed_stand_up()` | a human Anon `force_stand_up()`; the cradle or bed rest release already ran in the prelude; `request_posture("stand")`; the bed frame |
| `bed_keep_lying` | `_start_bed_keep_lying()` | no `force_stand_up()`; a `dialogue` source releases managed rest; `request_posture("stand")` so the authored act body owns her pose; the bed frame |
| `standing_place` | `_start_standing_place()` | `_begin_standing_placement()` (delegates to `poses/placement.gd`); a failed stool aborts; `request_posture("stand")`; the facts sync; `begin_facing()` |

A missing bed fails the two bed adapters closed; a failed cradle/bed rest release already aborted
in the prelude. An unknown or missing setup logs one `start blocked setup=...` line and aborts
through `_abort_start()`; the gate already passed, so this is a spec/data error, not a refusal.

The start settings-group sync (`_sync_start_pose_config()`) and the start camera
(`_prepare_start_camera()`) read the row's `settings_group` and `camera.profile`, not the pose id.

### Suspend, adopt and resume

A body-change provider can replace the act pony's presented body without ending the act; the
mechanism, the typed form and the source/binding contracts are `docs/body_change.md`.

`_body_swap_tick()` applies one typed action from `body_change/act.gd`: `NONE`, `SUSPEND`,
`RESUME`, `FAIL` or `END_RESTORE`. `_suspend_for_body_swap(change)` keeps the act and stops its
work:

- one pending swap is recorded in `ponies`; a second change is refused until it clears;
- the runtime is reparented to the entry before the old body is freed;
- the pose session, the anatomy act handle, the navigator lease, the face-turn hold, the camera
  shot, the kiss/hand contact, the wings, the carried body and the act-key hold are released; the
  auto stroke is interrupted without resetting its pace, band, shape or on/off state, the bones
  are put back and the breath stops;
- the outer act state, depth, penetration, climaxes, readiness, satisfaction, summary, event id,
  serial, settings snapshot and dialogue state stay in the runtime. The player stays locked, the
  HUD stays up and the outer camera is not restored to the player as an idle camera.

`PONIES.attach(new_pony)` adopts the suspended runtime before it creates a runtime. It runs the
body-change `notify_body_ready()` first, then `anatomy.bind()` and `runtime.adopt_body()`, which
bind the new body, pose, face and anatomy but do not resume. `_resume_after_body_swap()` is the one
resume path: it re-reads the settings and the new body's size, ends the old anatomy act and begins
a new one at the current depth, rebuilds the live pose at the pose the act was in
(`poses/service.gd`'s `settle()` skips the entrance ramp), resets the visual frame through
`_reset_visual_for_form()` (restore the true eye, clear the shot, re-anchor a standing Anon at the
new form's gap, then prepare the camera), restarts auto at its preserved values and state, reopens
the camera, re-claims the new navigator, pauses the new face-turn rate, rebinds the face, voice,
wings and integrations, and refreshes the HUD facts.

Failure paths keep the one exit: a failed handover or a watchdog calls `force_stop()`; an
ineligible new body ends through `force_stop()`; a world close or a force stop while suspended
clears the pending record and runs `_end_session()`.

### Exit

`_end_session(rejoin_cuddle)` is the only exit path. It gives back, in order: the auto stroke, the
handover, the inventory HUD, kiss forelegs, face-turn rate, eye override, face and wings, player
lock, camera, stool, `sex_active`, navigator, player look, posture/cuddle, pose, audio, HUD and the
active runtime. Every step checks the ownership flag it restores, so a failed start runs the same
function and restores only what it took.

- `_finalize_session(real_act)` runs the post-act bookkeeping once and is idempotent.
- `_end_act_lines()` is deliberately outside the teardown: `cancel()` queues the early-stop reaction
  after `_restore_begin()`, and `_finish_restore()` must not cancel director rows.
- `_restore_begin()` / `_restore_now()` are the ordered leaves.
- The pose part is one ledger: `_end_session()` calls `_free_pose()` and then
  `_restore_pony_bones()`. `_free_pose()` runs the session's pose-scope steps
  (`leave_pose_start()`, `leave_pose_body()` and the final `release_pose()`) with the act-scope
  resets between them at their positions, resets the mod-integration bridge after the base kiss,
  releases the shared excitement Beat hold and leaves every property the act borrowed back in
  place. `_build_pose()` calls the same ledger as the new-act prep before it builds the pose, so a
  pose left from the offer cannot stack. The step table and the scope split are `docs/poses.md`.
- `_restore_camera()` is the act's camera ledger: a separate act-level path, not part of the pose
  teardown.
- A forced stop never rejoins the missionary bed cuddle. A normal end of a bed-sourced act that did
  not go badly re-seats Anon on the bed's player seat and re-invites her through `rest/service.gd`.

The afterglow, close window and aftercare are `docs/afterglow.md`; the face and mood are
`docs/face.md`; the summary is `docs/summary.md`.

## Controls

The input service decodes the keys and calls the runtime protocol; the runtime never handles an
input event.

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
it never creates a runtime, starts an act or runs the act exit. `_resume_after_body_swap()` stays
the one resume path and runs after the form is ready. A same-node revision takes the same
`_reset_visual_for_form()` path through the runtime binding, without a resume or a second pose
session. The camera shot is released on suspend and recomputed on each presented-form change; the
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
  (`stool/act.gd`), which the runtime drives through `_stool_act()`.
- **View and HUD:** `act_view`, `refresh_view`, `pose_view`, `hud_readouts`, `hud_controls`,
  `auto_active`, `close_hint`, `act_face_rows`, `pose_state_rows`, `face_sit_error`,
  `reload_pose_asset`.
- **Input:** `look_motion`, `thrust_motion`, `toggle_auto_thrust`, `auto_thrust_wheel`,
  `auto_panel_input`, `auto_panel_open`, `vr_y_held`, `request_command`, `command`,
  `toggle_anatomy_hole`, `toggle_anatomy_oral`, `anatomy_hole_ready`, `anatomy_oral_ready`.
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
- **Exit:** `cancel`, `request_afterglow`, `end_afterglow`, `force_stop`,
  `apply_live_settings`.

`live_id()` is the act's stable pony id, refreshed from the live body; `ponies` matches a dialogue
prompt note to its one runtime through it. `request_form_change(true_form, shape_id, by_player)`
is the act-side form request the debug block and the player interaction call. `body_swap_pending()`
is true between suspension and resume. `PONIES.adopt_pending_body(pony)` runs the registry's
prepare and pending-swap adoption for a body the handover found before its spawn hook.

The pose surface is `pose_view()`, `request_pose(target_id, trigger, context)`,
`request_command(command_id)` and `command(command_id)`. The runtime supplies its state and
features; the session refuses or starts the edge. `request_command(id)` is the pure allow check:
`end` is reserved and always allowed, otherwise the id must be in the active pose's control
profile and the live edge lock must not deny it. `command(id)` runs that check first, then
dispatches the discrete `hole` id to the anatomy entry point and `oral` to
`toggle_anatomy_oral()`; the act-key hold still owns the one exit path.

The act-tunable values live in one typed `SETTINGS.ActSnapshot`. A consumer reads
`_snapshot.<value>` at the use site. The camera mode is cached in `_eye_camera_mode` by the same
snapshot, and `_pose_render_write()` reads that field.

## View

`refresh_view()` composes the typed act view (`shared/act_facts.gd`) from the session and the live
system reads. It runs once per phase: idle before the idle systems, physics after the pose tick and
before the fan-out, render before the camera work, and the entry's `apply_camera_motion()`
hand-off. `_sync_act_facts()` is its one-shot alias for the start, resume, teardown and live-edit
paths. `_sync_hud_facts()` adds the HUD card's live values and runs from `apply_camera_motion()`
and those boundaries; the HUD reads fields and never probes the runtime.

The view keeps raw values; `shared/act_facts.gd` owns the field list. The HUD strings, the key caps
and the panel labels live in `hud/service.gd` and `hud/lines.gd`. `close_earned` and `auto_shape`
are raw values; the `End` tint and the auto readout are formatted by the HUD module.

The standing start/offer gap is read from `_pose_session.pose_config["gaps"]`; a session without a
config falls back to `SETTINGS.pose(id, "standing")["gaps"]`. The shipped values live under
`default.poses.standing.gaps`; the placement handle keeps no gap table or numeric fallback, and a
per-mare pose override still wins. `_standing_gap()` adds the entrance's back offset for a
princess body.

That gap is the pre-act view, not the contact distance. Before the act, `poses/placement.gd` fits
Anon's whole body: it takes the part's natural pivot, her live opening and outward rear, and shifts
his horizontal position so the pivot starts one shaft behind her entrance. The fit is bounded by
`poses/placement.gd:FIT_MAX_M`, skipped on a stool, and repeated by `_reanchor_player_for_form()`
on a body resume or a same-node form revision. It clears the part's old Hips handshake
(`player_reset_pelvis()`) after measuring. The per-frame aim owns the stroke's pelvis correction;
a standing start no longer pulls the Hips bone across the gap.

## Thin-runtime checker

`scripts/architecture.py --check` enforces the host shape in addition to the exit, pose-ledger and
fan-out invariants:

- `state` is declared once and assigned only inside `_set_state()`;
- no `Input.`/`InputMap.`/input event/keycode read and no input callback in `runtime.gd`;
- `SETTINGS.<member>` reads only at the documented snapshot boundaries
  (`_snapshot_settings`, `apply_live_settings`, `_begin_act`, the resume pose config and the static
  character-name lookup);
- child nodes only from `_audio_service` (the act audio node) and `_start_tail_tuck` (the
  pose-scope tail tuck);
- the one `_end_session()`, the `_free_pose()` order and its three callers, the pose-before-facts
  write and the fan-out owner order, and the one `_resume_after_body_swap()`.

The allow-lists are compared both ways: a new read or node fails, and a stale row fails too.

## Tests

- `tests/test_runtime_teardown.gd` — the one exit path, the ownership flags, the oral edge's
  consent/feature refusals and its abort through `_end_session`, the standing gap's princess
  entrance shift, and the whole-body fit that rests the shaft at her entrance with a stale Hips
  offset removed.
- `tests/test_runtime_notes.gd` — the prompt forwards.
- `tests/poses/test_pose_offer.gd` — the typed offer, the Agreement/hotkey outcome table and the
  one start path.
- `tests/poses/test_start_setup.gd` — the closed setup vocabulary, the synthetic
  `auto`/`bed_keep_lying` row and the runtime dispatch for both bed adapters.
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
- `scripts/architecture.py --check` — the thin-runtime rules above.
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
