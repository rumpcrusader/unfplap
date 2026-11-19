# Act runtime

The per-pony act orchestrator. `runtime.gd` hosts one act at a time for one pony: it owns the state
machine, the tick order, the start sequence, the one teardown ledger and the composition of the
services. It never holds a service's implementation. The service contracts are indexed in
`docs/README.md`.

## States

```text
IDLE → POSING_IN → ACTIVE → CLIMAX → AFTERGLOW → RESTORE → IDLE
```

- `IDLE`: no act; the runtime is attached, runs its idle schedule and may show the start hint.
- `POSING_IN`: the start sequence has run and the pose is building.
- `ACTIVE`: thrusting, readiness, cues, caress and the pose actions are live.
- `CLIMAX`: the pony's 5 s climax; the player may keep thrusting but it does not score.
- `AFTERGLOW`: the held post-act phase, the standing close window and normal dialogue.
- `RESTORE`: the teardown ledger runs; the runtime returns to `IDLE` at the end.

Breath timing: `0.9 s` base while active, `0.85 s` during climax, `1.4 s` in afterglow.

## Start

`offer.try_start()` is the act key's only entry (`docs/offer.md`). It hands a typed offer to
`offer.start_pose_offer(offer)`. The idle scan builds its offer from the bed side or the
free-standing fan; a live Agreement builds `trigger: "agreement"` from its frozen option and the
scene-only rows. The offer owns its pose, blocked hint and trigger, so that one function never
names a pose and never reaches into a request or negotiation service.

The live start paths share the one body (`runtime._begin_act()`):

- **The hotkey** runs `runtime.start_hotkey()`: the scene gate's `hotkey_ready()` (the scene-only
  rows plus Base clearance), then `_begin_act()`. No policy row, no offer cooldown, no buck and no
  history refusal. The idle hint scans once per second and reads Base clearance live after the
  scene rows pass; a real press runs the same path. There is no eligibility cache, and a failing
  scene reads no Base clearance. A transient failed gate leaves the offer and the hint alive.
- **The Agreement** runs `runtime.start_agreement(handle)`: only the scene-only rows with the
  frozen pose capability (`scene_only_verdict`), then `_begin_act()`. The runtime answers
  `AGREEMENT_WAIT`, `AGREEMENT_STARTED` or `AGREEMENT_FAILED` and the offer, its only caller,
  reports `Started` or `StartFailed` to the Negotiation service. `AGREEMENT_WAIT` means a
  transient row or an unsettled presentation, and the Agreement stays live. The presentation is
  act-owned and starts when the entry forms the Agreement.
- **Auto-start:** the offer's clock samples the live Agreement at `0.25 s`. When the presentation
  is settled and the scene-only rows pass, with no menu, no pause and no live act, it starts with
  no key press. A private Agreement takes a fresh privacy sample first; a public one does not
  sample.
- **The hotkey's exact match:** the act key always accepts. No context pose means no attempt (log
  and toast). A live Agreement's exact `(pose, source, bed, cuddle)` match starts it immediately,
  skips the presentation and does not resample privacy; any other live Agreement or negotiation is
  interrupted with `Interrupted(hotkey)` and the immediate attempt runs.

The aftercare is cleared before an Agreement start: the `sex_aftercare` meta, the visual aftercare
node and its navigator lease. The act then adopts the negotiation hold through `_claim_nav()`:
the scene-hold ledger already owns the navigator, so the start keeps the same owner instead of
claiming a second one. The start sequence:

1. re-read the identity and the gate (the Agreement path runs the scene-only rows);
2. reset the stool handle and refresh the anatomy bridge;
3. begin the camera session, clear the idle presentation, the mood face and the act face;
4. snapshot the settings and preferences, build the thrust tracker and the pose config;
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
`bed_keep_lying` has no shipped consumer yet; the riding pose is its first, and
`tests/poses/test_start_setup.gd` proves the dispatch until then.

The start settings-group sync (`_sync_start_pose_config()`) and the start camera
(`_prepare_start_camera()`) read the row's `settings_group` and `camera.profile`, not the pose id.
The group sync is a small dispatch today: a new settings group adds its own sync next to its row.
`start` logs the chosen setup with the pose and source.

## Controls

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
`standing → standing_oral` edge and then its reverse; the edge owns the 1.6 s turn, the contact
switch to the mouth at 0.9 s, the speech stop, the `D` viseme and the soft-kiss cue timer on the
pose side. The camera and hand contracts are `docs/camera.md` and `docs/hands.md`.

The debug wheel is desktop-only and does not pause the tree. While it is open the runtime ignores
mouse motion, so the wheel's virtual reticle cannot thrust or free-look the act. The wheel runs
the highlighted action and closes when the middle button is released, and normal mouse input
resumes then.

The HUD card rows, the key caps and the `End` tint are `docs/hud.md`. The lab keys are
`docs/debug.md`.

## Body swap

A body-change provider can replace the act pony's presented body without ending the act. The
mechanism, the typed form and the source/binding contracts are `docs/body_change.md`; this section
owns the act side.

The provider observes its own pack and pushes the change through the body-change service's
bindings; the runtime does not poll it. `_body_swap_tick()` reads `active_change_for(pony)` on its
existing `0.1 s` cadence. One provider that handles the act pony and reports a live `BodyChange` whose
`previous_body` is the act pony starts the handover. A provider may start a change from its own AI
as well as from a `request_*` call; the typed change carries its origin. A change whose old body is
not the act pony never reaches the act.

`_suspend_for_body_swap(change)` keeps the act and stops its work:

- one pending swap is recorded in `ponies`; a second change is refused until it clears;
- the runtime is reparented to the entry before the old body is freed;
- the pose session, the anatomy act handle, the navigator lease, the face-turn hold, the camera
  shot and the body-bound controllers are released; the kiss and hand contact are reset, a held
  body is released, the act-key hold stops and the auto stroke is interrupted without resetting
  its pace, band, shape or on/off state, the cached form-state debug label is cleared, the bones
  are put back and the breath stops;
- the outer act state, depth, penetration, climaxes, readiness, satisfaction, summary, event id,
  serial, settings snapshot and dialogue state stay in the runtime. The player stays locked, the
  HUD stays up and the outer camera is not restored to the player as an idle camera.

`PONIES.attach(new_pony)` adopts the suspended runtime before it creates a runtime. It runs the
body-change `notify_body_ready()` first, so the service asks the provider for the new body's form,
applies it and fans it out before the tail seat and the anatomy bind; the placement and tail then
read the presented form. It adopts when the change's typed source `claims_body()` or the stable
id matches, then `anatomy.bind()` runs, the runtime is reparented under the new body, and
`runtime.adopt_body()` binds the new body, pose, face and anatomy but does not resume. The
watcher resumes once the new body reports the requested form or the provider has finished; a
true-form change (an empty target) is ready at once, and a target the provider fills in after the
suspension is read from the typed change's `target_form_id` on the same ticks. A named form that
settles without the target resumes on the adult body as a failed change and puts the offer back. A
runtime created in a race is stopped and freed, and its anatomy controller is detached first, so
the act never keeps two controllers or two owners. The stable id is the act's id: a borrowed form
keeps the same relationship, preferences, history and summary; the caption and dialogue name follow
the adopted form's `BodyForm.form_name`, and an empty form name falls back to the identity's display
name. The normal dialogue prompt note also names the live presented body (own or borrowed) from the
stored form, so a stale shape event cannot make the model describe a body she is no longer wearing.

The adoption and the provider's settled form call `WORLD.refresh_body_lod()` for the new body: the
game's near and far caches are dropped and the near mesh is re-armed, so the visible body is the
form variant rather than the old body's near mesh. A rebuilt near mesh that still shows her own
materials is a pack-side look issue, not a game-file edit.

A provider may clear its changing state before the new body's spawn hook reaches the registry.
The watcher keeps the act suspended while the change still reports a `next_body`, then calls
`PONIES.adopt_pending_body()` to run the same prepare-and-adopt path after a short grace. The old
body is not resumed while that new body exists, so the late spawn cannot attach a second runtime.
A provider that stops without a new body still follows the old-body or watchdog path below.

A live settings edit while suspended refreshes the snapshot and returns; the resume applies it
with the rest of the rebuilt state instead of touching a released pose or the old body.

`_resume_after_body_swap()` re-reads the settings and the new body's size, ends the old anatomy
act and begins a new one at the current depth, rebuilds the live pose at the pose the act was in
(`poses/service.gd`'s `settle()` skips the entrance ramp), resets the visual frame through
`_reset_visual_for_form()` (restore the true eye, clear the shot, re-anchor a standing Anon at the
new form's gap, then prepare the camera), restarts auto at its preserved values and state, reopens
the camera, re-claims the new navigator, pauses the new face-turn rate, rebinds the face, voice,
wings and integrations, and refreshes the HUD facts. The body-change service has already applied
the presented form and bound the world systems; the resume is the act's own ordered rebuild of the
runtime's sub-services, not a second binding fan-out. The runtime binding looks the runtime up
through `PONIES.runtime_for(body)` and forwards the form; it never creates a runtime, starts an act
or runs the act exit. `_resume_after_body_swap()` stays the one resume path and runs after the
form is ready, so the standing re-anchor, the eye override and the pose use the new body's form.
A same-node revision takes the same `_reset_visual_for_form()` path through the runtime binding,
without a resume or a second pose session. The act continues from its current state. The camera
shot is released on suspend and recomputed on each presented-form change; the flame covers the
re-frame, and Anon may shift slightly. That re-frame is the accepted behavior, not a zero-frame
swap. The standalone base-game vocal cache can still hold an old body's freed player; the runtime
prunes only its own stable id before a vocal play, so the next clip is created on the presented
body (see `docs/audio.md`).

Failure paths keep the one exit:

- the provider stops with no new body and the old body alive: the same runtime resumes on the old
  body;
- a named form fails before a new body arrives: the pending offer is restored so the player can
  name another;
- a named form's new body never reports the target: the act resumes on that adult body as a failed
  change and restores the offer; the `8 s` watchdog bounds the wait;
- no body arrives: the `8 s` watchdog ends the act through `force_stop()`;
- the new body is not an adult mare: `adopt_body()` ends the act through `force_stop()`;
- the world closes or the act is force-stopped while suspended: `_end_session()` clears the
  pending record and runs the normal teardown.

A change that starts while the act is already in `RESTORE` is not suspended. The restore finishes
through `force_stop()` and the one exit before the pack can free the body under the runtime, so the
borrowed scene state is returned instead of a world-close. `request_form_change()` refuses a body
another system is holding, and the suspend path releases a carried body before the flame.

`reparent()` runs `_exit_tree()`. The runtime's `_swapping_parent` flag makes that signal a no-op
during the handover, so a move between bodies cannot run the world-close teardown. `attach_to_body()`
is the only route that sets it.

### Form interaction

The game's talk turn (`T`/microphone) is the only player interaction; there is no new key, picker
or settings row. `_player_line_tick()` reads a new director turn in `ACTIVE`, the same turn the
readiness classifier scores, and passes its text to the typed source:

- a source that wears another form consumes a reveal ask through `asks_form_change(text)`; a
  successful `runtime.request_form_change(true, "", true)` marks the change as the player's;
- with the post-climax offer pending, a line that names an adult mare through `named_form(text)`
  starts `request_form_change(false, id, true)`; `named_form_note(text)` supplies a short status
  for a worn, own, young/male or uncopyable name and returns nothing for ordinary talk;
- anything else is ordinary talk and is left to readiness and dialogue.

The provider policy owns the offer timing and prompt (`docs/body_change.md`,
`## Provider policy`). `_shape_offer_tick()` keeps the once-per-act gate, asks
`policy.should_offer(context)` on each live `ACTIVE` tick and queues one `FORM_OFFER` reaction with
`policy.offer_prompt()` when it first returns true. A policy may wait for its own stage; a false
before its trigger does not spend the offer. The offer is deliberately not made in `CLIMAX` or
`AFTERGLOW`: the player cannot answer it there, so a player who ends immediately after the first
climax misses an indulgence. An unanswered offer ends with the act; the next act may offer again. A
named change whose handover fails before a new body arrives restores the offer.

A completed player-named change calls `policy.on_offer_accepted(context)`; a completed
player-requested return to her own form calls `policy.on_reveal(context)` once. The base runtime
executes the generic effects: a readiness heat spike and a cue while the act is `ACTIVE`, the
reveal's peak and `form_reveal` memory mark, the exceptional face beat, and the `form_reveal` input
the summary/act-history commit reads for an extra great-act comfort. The shipped policy gives the
player-requested reveal its values and a named form none; an AI-origin own-form change is neutral
because the runtime only calls `on_reveal()` for the player's own ask. The reveal's comfort is the
summary's `form_reveal` input, not an effects field. The same runtime keeps the flags across the
swap; `_end_session()` clears the pending offer and the debug form label.

The runtime dispatches the generic policy milestones through one helper and the reused act
context: `ACTIVE` at the first active entry, `CLIMAX_END` when a pony climax ends, `AFTERGLOW` at
the afterglow entry, `OFFER_ACCEPTED` and `REVEALED` when the player's named or own-form change
completes, and `FORM_SETTLED` after the act resumes on the presented form. The provider decides
which events matter; `should_offer()` remains the per-`ACTIVE`-tick offer check.

The player's offer survives her own change. An AI-origin form change leaves
`_shape_offer_pending` set, and only the form the player names through the offer clears it; a
player-requested reveal leaves it set too. The offer is therefore still available after her AI
takes or leaves a form.

`_form_hint_tick()` is a debug log probe, not a HUD source. It names the reveal ask while she wears
another form and the reveal is unused, and the name prompt while the offer is pending, but only
when **Enable debug** was on at the act's settings snapshot; `_form_hint` itself is always empty, so
neither a release nor a debug build puts the dialogue channel on the HUD. The reveal and the gift
are for the player to discover from her own words and behaviour. The probe runs on the state and
event changes, not per frame, and `shared/act_facts.gd` keeps the empty `form_hint` field so the act
view and the card's existing row need no shape change. The debug label clears at the climax,
afterglow, restore, suspension and act end, so the log never claims an action the player can no
longer take.

## Teardown

`_end_session(rejoin_cuddle)` is the only exit path. It gives back, in order: the inventory HUD,
kiss forelegs, face-turn rate, eye override, face and wings, player lock, camera,
`sex_active`, navigator, player look, posture/cuddle, pose, audio, HUD and the active runtime. Every
step checks the ownership flag it restores (`_act_camera.camera_owned`, `_act_camera.look_captured`,
`_act_camera.eye_override`, `_hold.locked_player`, `_hold.face_turn_rate_owned`, `_hold.nav`, the
runtime's own `_posture_owned` and the HUD's borrowed quick-slot state, the controller flags), so a
failed start runs the same function and restores only what it took.

- `_finalize_session(real_act)` runs the post-act bookkeeping once and is idempotent.
- `_end_act_lines()` is deliberately outside the teardown: `cancel()` queues the early-stop reaction
  after `_restore_begin()`, and `_finish_restore()` must not cancel director rows.
- `_restore_begin()` / `_restore_now()` are the ordered leaves.
- The pose part is one ledger: `_end_session()` calls `_free_pose()` and then
  `_restore_pony_bones()`. `_free_pose()` runs the session's pose-scope steps
  (`leave_pose_start()`, `leave_pose_body()` and the final `release_pose()`) with the act-scope
  resets between them at their positions, resets the mod-integration bridge after the base kiss,
  releases the shared excitement Beat hold and leaves every property the act borrowed back in
  place. `_build_pose()` calls the same ledger as the new-act prep
  before it builds the pose, so a pose left from the offer cannot stack. The step table and the
  scope split are `docs/poses.md`.
- `_restore_camera()` is the act's camera ledger: a separate act-level path, not part of the pose
  teardown.
- A forced stop never rejoins the missionary bed cuddle. A normal end of a bed-sourced act that did
  not go badly re-seats Anon on the bed's player seat and re-invites her through `rest/service.gd`;
  the retry waits out aftercare and the guest cooldown, and every failure is logged before she is
  left standing.
- The afterglow, close window and aftercare are `docs/afterglow.md`; the face and mood are
  `docs/face.md`; the summary is `docs/summary.md`.

## Tick order

- `_physics_process`: `_physics_tick(delta)` — the body-swap watcher, the pose tick, the facts
  refresh, the pose fan-out, the
  act timer, the readiness tick, the dialogue service, the form offer, the
  tolerance, the scene
  keep-alives, the anatomy tick, the thrust tracker and the presentation modules (wings and mod
  integrations); the anatomy facts sync runs once, after the tick, so the persistent controller's
  own `_process` poll reads the frame's live state, pose, depth and bed frame. `_sync_pose_frame()`
  follows the bed or the pony root ground frame before the
  render write. The pose tick advances the oral turn and the edge's switches and events; the
  anatomy tick only reads the resulting contact.
- `_physics_tick` times `_pose_service().tick(delta)` as the `pose_tick` chunk before the
  `refresh_view()` in every phase above `IDLE`, then times the fixed-order `_pose_fanout()` as
  the `pose_fanout` chunk after that refresh: the pose service first (modifier reconcile and the
  `act_body`/`anon` channel), then camera, hands, kiss, anatomy and audio. An edge keeps ticking
  through `CLIMAX`/`AFTERGLOW`. The `IDLE` early return still follows the facts refresh and runs
  no pose tick or fan-out: its schedule is the inventory safety, the standing presentation's
  physics, the dialogue history scan and its perf chunks.
- A suspended act returns before the pose tick: `_body_swap_tick()` owns the wait and the resume,
  and no act work runs until the new body adopts the runtime and its form is ready.
- `_process`: `_process_tick(delta)` — the render-time pose write after every game writer (the bed
  family places its Anon body and eye camera; the standing family syncs its ground frame and
  writes the same pose), the camera lean and motion, the climax wave, the breath,
  the face and the HUD. `IDLE` runs only the standing presentation's render tick.
- the entry's `_process` calls `PONIES.active()` and then `apply_camera_motion()` on it every
  frame. Keep this single owner.
- Do not merge these timing domains blindly. The pose/camera timing is in `docs/poses.md` and
  `docs/camera.md`.

## Public surface

The runtime keeps thin forwards for the entry, `ponies/service.gd`, `hud/service.gd`,
`input/service.gd`, the labs, `initiation/service.gd`, `anatomy/service.gd`,
`poses/standing_presentation.gd` and the tests. The stable cross-mod surface is `docs/api.md`; the
internal reads the HUD/tests use (`state`, `pose_id`, `pony`, `pony_climaxes`, `satisfaction`,
`mood`, `cue`, `depth`, `penetration_m`, `thrust_up`) stay callable.

`live_id()` is the act's stable pony id, refreshed from the live body; `ponies` matches a
dialogue prompt note to its one runtime through it and the id itself stays private to the act.

`request_form_change(true_form, shape_id, by_player)` is the act-side form request the debug block
uses and the player interaction calls; `by_player` becomes the typed `BodyChange.Origin`, and the
watcher turns the request into the suspension. Only a player-requested own form is exceptional.
`body_swap_pending()` is true between suspension and resume.
`PONIES.adopt_pending_body(pony)` runs the registry's prepare and pending-swap adoption for a body
the watcher found before its spawn hook. `runtime.gd` is the only caller; no presentation module
reads it.

The runtime does not mirror a service's act state. It reads it through the owning facade
(`_readiness`, `_act_camera`, `_afterglow`, `_hold`, `_pose_session`, `_summary_service`, `_face`)
at the call site, so a suite that needs `act_thrusts`, `camera_owned`, `close_left` or `summary`
reads that facade too.

The pose surface is `pose_view()`, `request_pose(target_id, trigger, context)`,
`request_command(command_id)` and `command(command_id)`. The runtime supplies its state and
features; the session refuses or starts the edge. It also binds the session's pose host
callbacks: `mouth_point` and `opening_point` for the oral turn and `face_point` for the face
contact, plus the oral kiss/speech/viseme/status callbacks. `face_point` is the anatomy bridge's
real face anchor on the act body; a missing or inactive body is `Vector3.INF`. `request_command(id)` is the pure allow check:
`end` is reserved and always allowed, otherwise the id must be in the active pose's control profile
and the live edge lock must not deny it. `command(id)` runs that check first, then dispatches the
discrete `hole` id to the anatomy entry point and `oral` to `toggle_anatomy_oral()`,
which requests the target pose with the per-mare consent string; the reserved `pose_back`/
`pose_forward` return false, and `end` returns true without an act exit. The act-key hold still
owns the one exit path.

The runtime's `pose_id` is the act's start identity for the start sequence, the scene gate and
the teardown; the pose view is the active pose. `_end_session()` aborts a live edge through the
one pose teardown. `apply_live_settings()` also refreshes a running edge's target snapshot after
the start pose's own config sync.

The act-tunable values (the thrust values, the caress quality, the cue/talk pacing, the jiggle,
camera and climax values) live in one typed `SETTINGS.ActSnapshot`. `_snapshot_settings()` is its
only writer and runs at act start and again at the top of `apply_live_settings()`, before the IDLE
early return; a consumer reads `_snapshot.<value>` at the use site instead of keeping a second
copy. The camera mode is read per rendered frame, so it is cached in `_eye_camera_mode` by the same
snapshot and `_pose_render_write()` reads that field, never the setting. A zeroed snapshot stands
in until the first start or settings edit, so an idle read sees the same zero values the removed
fields defaulted to. `_features` and `_presentation_cfg` stay as references into the snapshot
because the idle view refresh, the start sequence and the suites read them outside or across an
act; the climax limit and the climax mode stay runtime fields that the acts and suites set
directly.

The standing start/offer gap is read from `_pose_session.pose_config["gaps"]`; a session without a
config falls back to `SETTINGS.pose(id, "standing")["gaps"]`. The shipped values live under
`default.poses.standing.gaps`; the placement handle keeps no gap table or numeric fallback, and a
per-mare pose override still wins. The gap is measured from her centre, and a princess body's
entrance sits further back or forward than the mare's the gaps were tuned on, so `_standing_gap()`
adds the entrance's back offset (`camera/service.gd:entrance_offset()`).

That gap is the pre-act view, not the contact distance. Before the act, `poses/placement.gd` fits
Anon's whole body: it takes the part's natural pivot (`player_root_natural()`, the applied Hips
offset removed), her live opening and outward rear, and shifts his horizontal position so the pivot
starts one shaft behind her entrance. The fit is bounded by `poses/placement.gd:FIT_MAX_M`, skipped
on a stool, and repeated by `_reanchor_player_for_form()` on a body resume or a same-node form
revision, with the presented form passed in for the entrance gap. It clears the
part's old Hips handshake (`player_reset_pelvis()`) after measuring, so a body swap cannot carry the
previous body's offset into the fit. The per-frame aim then owns the stroke's pelvis correction; a
standing start no longer pulls the Hips bone across the gap. The fit log line carries
`fit=<signed metres>` beside the placement.

## Tests

- `tests/test_runtime_teardown.gd` — the one exit path, the ownership flags and the oral edge's
  consent/feature refusals plus its abort through `_end_session`, the standing gap's princess
  entrance shift, and the whole-body fit that rests the shaft at her entrance with a stale Hips
  offset removed.
- `tests/test_runtime_notes.gd` — the prompt forwards.
- `tests/poses/test_pose_offer.gd` — the typed offer, the Agreement/hotkey outcome table and the
  one start path. The idle hint no longer keeps a policy snapshot; its readiness is
  `runtime.hotkey_ready()`, which forwards the scene gate's readiness and reads Base clearance live
  after the scene rows pass (`tests/test_runtime_teardown.gd`). The stool suite covers the per-scan
  reach pair and the scene-first read (`tests/stool/test_gate.gd`).
- `tests/poses/test_start_setup.gd` — the closed setup vocabulary, the synthetic
  `auto`/`bed_keep_lying` row and the runtime dispatch for both bed adapters.
- `tests/readiness/test_oral_quiet.gd` — the oral contact: the plap and rump/tail jiggle skip, the
  kept slide/vocal/wings/blush/ear, the climax-line skip and the regular-path regression.
- `tests/handover/test_body_swap.gd` — the generic handover: suspend → adopt → resume, the state
  depth, climaxes and event id survive, the old runtime is not freed, the new body's anatomy and
  pose bind, adoption binds without resuming, a named form waits for its target, the target
  completes as the form, a missing form restores the offer on the new body, the watchdog with a
  body resumes as a failed form, a change the provider started on its own, a repeated change, a
  failed change resumes the old body, a provider that goes inactive, the no-body watchdog and an
  ineligible body end through the one exit, a world close during the swap is safe, the debug form
  label clears on the state changes while the HUD string stays empty, a failed named change restores
  the offer, her own change keeps the player's offer, a late body is adopted once after the grace
  instead of resuming the old body, a change during the restore finishes the act through the one
  exit, a held body refuses the request, the presented form's name drives the act facts with the
  identity fallback while the stable id and event id survive, and the fake policy records all six
  generic act milestones in order. The suite binds the real `ponies` registry and fakes only the
  runtime's host handle and the body-change service, because it drives the runtime through that
  handle and never starts a world. The entry itself is `tests/entry/test_services.gd`.
- `tests/summary/test_act_flow.gd` — the state flow and the afterglow HUD summary.
- `tests/afterglow/test_afterglow.gd` — the phase decisions, including the oral passive row.
- `scripts/architecture.py --check` — the one exit, the pose ledger order and its three callers,
  the fan-out order and the pose-before-facts write in `_physics_tick`, and the thin-runtime
  shape: the one `state` writer, no raw input, the settings snapshot boundaries and the two
  system-owned child nodes.
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
- `docs/eligibility.md`, `docs/scene_gate.md`, `docs/scene_hold.md` — the start gates and scene.
- `docs/poses.md`, `docs/camera.md` — the tick-time pose and camera.
- `docs/integrations.md` — optional mod reactions during the act.
- `docs/afterglow.md`, `docs/face.md`, `docs/summary.md` — the post-act phases.
