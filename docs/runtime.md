# Act runtime

The per-pony act orchestrator. `runtime.gd` hosts one act at a time for one pony: it owns the state
machine, the tick order, the start sequence, the one teardown ledger and the composition of the
services. It never holds a service's implementation. The service contracts are indexed in
`docs/README.md`.

## States

```text
IDLE → POSING_IN → ACTIVE → CLIMAX → AFTERGLOW → RESTORE → IDLE
```

- `IDLE`: no act; the runtime is attached and may show the start hint.
- `POSING_IN`: the start sequence has run and the pose is building.
- `ACTIVE`: thrusting, readiness, cues, caress and the pose actions are live.
- `CLIMAX`: the pony's 5 s climax; the player may keep thrusting but it does not score.
- `AFTERGLOW`: the held post-act phase, the standing close window and normal dialogue.
- `RESTORE`: the teardown ledger runs; the runtime returns to `IDLE` at the end.

Breath timing: `0.9 s` base while active, `0.85 s` during climax, `1.4 s` in afterglow.

## Start

`main.try_start()` is the act key's only entry. It hands a typed offer to
`main.start_pose_offer(offer)`. The idle scan builds its offer from the bed side or the
free-standing fan; a live Agreement builds `trigger: "agreement"` from its frozen option and the
scene-only rows. The offer owns its pose, blocked hint and trigger, so that one function never
names a pose and never reaches into a request or negotiation service.

The live start paths share the one body (`runtime._begin_act()`):

- **The hotkey** runs `runtime.start_hotkey()`: the scene-only rows plus Base clearance, then
  `_begin_act()`. No policy row, no offer cooldown, no buck and no history refusal. The idle hint
  scans once per second and reads Base clearance live after the scene rows pass; a real press runs
  the same path. There is no eligibility cache, and a failing scene reads no Base clearance. A
  transient failed gate leaves the offer and the hint alive.
- **The Agreement** runs `runtime.start_agreement(handle)`: only the scene-only rows with the
  frozen pose capability (`scene_only_verdict`), then `_begin_act()`. It reports `Started` or
  `StartFailed` to the Negotiation service through `main.report_agreement()`. `AGREEMENT_WAIT`
  means a transient row or an unsettled presentation, and the Agreement stays live. The
  presentation is act-owned and starts when `main` receives the Agreement.
- **Auto-start:** `main._tick_agreement_auto_start()` samples the live Agreement at `0.25 s`. When
  the presentation is settled and the scene-only rows pass, with no menu, no pause and no live
  act, it starts with no key press. A private Agreement takes a fresh privacy sample first; a
  public one does not sample.
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
| `standing_place` | `_start_standing_place()` | `_begin_standing_placement()`; a failed stool aborts; `request_posture("stand")`; the facts sync; `begin_facing()` |

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

A shape-changing source can replace the act pony's body without ending the act. A world-side
source contract (the manager and the duck-typed surface are `integrations/shape_change.gd`) is
polled by `_body_swap_tick()` at `0.1 s`; one source that handles the act pony and reports a change
starts the handover. The adapter alone talks to the installed pack. A source may start a change
from its own AI as well as from a `request_*` call: `poll()` sets the source's changing state, and
the watcher reads `is_changing()` and `old_actor()` after the poll. A change whose old actor is not
the act pony never reaches the act.

`_suspend_for_body_swap(source)` keeps the act and stops its work:

- one pending swap is recorded in `main`; a second change is refused until it clears;
- the runtime is reparented to `main` before the old body is freed;
- the pose session, the anatomy act handle, the navigator lease, the face-turn hold, the camera
  shot and the body-bound controllers are released; the kiss and hand contact are reset, a held
  body is released, the act-key hold and the auto stroke are dropped, the cached form-state debug
  label is cleared, the bones are put back and the breath stops;
- the outer act state, depth, penetration, climaxes, readiness, satisfaction, summary, event id,
  serial, settings snapshot and dialogue state stay in the runtime. The player stays locked, the
  HUD stays up and the outer camera is not restored to the player as an idle camera.

`main._on_pony(new_pony)` adopts the suspended runtime before it creates a runtime: the source's
`claims_body()` or the stable id must match, the adapter's `prepare_pony()` has already fitted the
new body, `anatomy.bind()` runs, the runtime is reparented under the new body, and
`runtime.adopt_body()` binds the new body, pose, face and anatomy but does not resume. The watcher
resumes once the new body reports the requested shape or the source has finished; a true-form
change (an empty target) is ready at once, and a target the source fills in after the suspension is
read from its `target()` on the same ticks. A named shape that settles without the target resumes on
the adult body as a failed change and puts the offer back. A runtime created in a race is stopped
and freed, and its anatomy controller is detached first, so the act never keeps two controllers or
two owners. The stable id is the act's id: a borrowed shape keeps the same relationship,
preferences, history and summary; only the display name follows the new identity.

The adoption and the adapter's settled fit call `main.refresh_body_lod()` for the new body: the
game's near and far caches are dropped and the near mesh is re-armed, so the visible body is the
shape variant rather than the old body's near mesh. A rebuilt near mesh that still shows her own
materials is a pack-side look issue, not a game-file edit.

A source may clear its changing state before the new body's spawn hook reaches `main`. The watcher
keeps the act suspended while the source still reports a new body through `new_actor()`, then calls
`main.adopt_pending_body()` to run the same prepare-and-adopt path after a short grace. The old body
is not resumed while that new body exists, so the late spawn cannot attach a second runtime. A
source that stops without a new body still follows the old-body or watchdog path below.

A live settings edit while suspended refreshes the snapshot and returns; the resume applies it
with the rest of the rebuilt state instead of touching a released pose or the old body.

`_resume_after_body_swap()` re-reads the settings and the new body's size, ends the old anatomy
act and begins a new one at the current depth, rebuilds the live pose at the pose the act was in
(`poses/service.gd`'s `settle()` skips the entrance ramp), re-anchors Anon at the new body's gap
for a standing act, resets the act-key hold and the auto stroke, reopens the camera, re-claims the
new navigator, pauses the new face-turn rate, rebinds the face, voice, wings and integrations, and
refreshes the HUD facts. It stays the one resume path and runs after the shape is ready, so the
standing re-anchor, the eye override and the pose use the shape body's size. The act continues from
its current state. The camera shot is released on suspend and reopened on resume; the flame covers
the re-frame, and Anon may shift slightly. That re-frame is the accepted behavior, not a zero-frame
swap.

Failure paths keep the one exit:

- the source stops with no new body and the old body alive: the same runtime resumes on the old
  body;
- a named shape fails before a new body arrives: the pending offer is restored so the player can
  name another;
- a named shape's new body never reports the target: the act resumes on that adult body as a failed
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
readiness classifier scores, and passes its text to the source:

- a source that wears another shape consumes a reveal ask through `asks_form_change(text)`; a
  successful `runtime.request_form_change(true, "", true)` marks the change as the player's;
- with the post-climax offer pending, a line that names an adult mare through `named_form(text)`
  starts `request_form_change(false, id, true)`; `named_form_note(text)` supplies a short status
  for a worn, own, young/male or uncopyable name and returns nothing for ordinary talk;
- anything else is ordinary talk and is left to readiness and dialogue.

The offer is made once per act after the first pony climax, in her own form and in `ACTIVE`:
`_shape_offer_tick()` sets `_shape_offer_pending` and queues one `FORM_OFFER` reaction with a
code-owned prompt. It is deliberately not offered in `CLIMAX` or `AFTERGLOW`: the player cannot
answer it there, so a player who ends immediately after the first climax misses an indulgence. An
unanswered offer ends with the act; the next act may offer again. A named change whose handover
fails before a new body arrives restores the offer.

A player-requested return to her own form is the act's one exceptional beat
(`_complete_form_change()`): a `FORM_REVEAL_HEAT` readiness spike, a special impression and world
event in the `FORM_REVEAL` slot, one `FORM_REVEAL_PEAK_SCORE` peak, and the `form_reveal` input the
summary/act-history commit reads for an extra great-act comfort. It is recorded once before the
effects, so a second ask in the same act does nothing. Her own reveal and any named shape are
neutral: the handover runs, the act continues, and none of the exceptional effects apply. The same
runtime keeps the flags across the swap; `_end_session()` clears the pending offer and the debug
form label.

The player's offer survives her own change. An AI-origin shape change leaves `_shape_offer_pending`
set, and only the shape the player names through the offer clears it; a player-requested reveal
leaves it set too. The offer is therefore still available after her AI takes or leaves a shape.

`_form_hint_tick()` is a debug log probe, not a HUD source. It names the reveal ask while she wears
another shape and the reveal is unused, and the name prompt while the offer is pending, but only
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

- `_physics_process`: `_physics_tick(delta)` — the body-swap watcher, the pose tick, the facts sync,
  the pose fan-out, the
  act timer, the readiness tick, the dialogue service, the form offer, the history scan, the
  tolerance, the scene
  keep-alives, the anatomy tick, the thrust tracker and the presentation modules (wings and mod
  integrations). `_sync_pose_frame()` follows the bed or the pony root ground frame before the
  render write. The pose tick advances the oral turn and the edge's switches and events; the
  anatomy tick only reads the resulting contact.
- `_physics_tick` times `_pose_service().tick(delta)` as the `pose_tick` chunk before the first
  `_sync_act_facts()` in every phase above `IDLE`, then times the fixed-order `_pose_fanout()` as
  the `pose_fanout` chunk after that sync: the pose service first (modifier reconcile and the
  `act_body`/`anon` channel), then camera, hands, kiss, anatomy and audio. An edge keeps ticking
  through `CLIMAX`/`AFTERGLOW`. The `IDLE` early return still follows the first facts sync and runs
  no pose tick or fan-out.
- A suspended act returns before the pose tick: `_body_swap_tick()` owns the wait and the resume,
  and no act work runs until the new body adopts the runtime and its shape is ready.
- `_process`: `_process_tick(delta)` — the render-time pose write after every game writer (the bed
  family places its Anon body and eye camera; the standing family syncs its ground frame and
  writes the same pose), the camera lean and motion, the climax wave, the breath,
  the face and the HUD.
- `main._process` calls `active_runtime.apply_camera_motion()` every rendered frame. Keep this
  single owner.
- Do not merge these timing domains blindly. The pose/camera timing is in `docs/poses.md` and
  `docs/camera.md`.

## Public surface

The runtime keeps thin forwards for `main.gd`, `hud/service.gd`, `input/service.gd`, the labs, `initiation/service.gd`,
`anatomy/service.gd`, `poses/standing_presentation.gd` and the tests. The stable
cross-mod surface is `docs/api.md`; the internal reads the HUD/tests use (`state`, `pose_id`,
`pony`, `pony_climaxes`, `satisfaction`, `mood`, `cue`, `depth`, `penetration_m`, `thrust_up`) stay
callable.

`request_form_change(true_form, shape_id, by_player)` is the act-side shape request the debug block
uses and the player interaction calls; the watcher turns it into the suspension, and `by_player`
marks the change as the player's (only a player-requested true form is exceptional).
`body_swap_pending()` is true between suspension and resume. `main.adopt_pending_body(pony)` runs
the entry's prepare and pending-swap adoption for a body the watcher found before its spawn hook.
`main` and the debug actions use these; no presentation module reads them.

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

The act-tunable fields (the thrust values, the caress quality, the cue/talk pacing, the jiggle,
camera and climax values) are declared without a code default. `_snapshot_settings()` is their
only writer and runs at act start and again at the top of `apply_live_settings()`, before the
IDLE early return, so a read outside an act sees the current settings after the first snapshot.

The standing start/offer gap is read from `_pose_session.pose_config["gaps"]`; a session without a
config falls back to `SETTINGS.pose(id, "standing")["gaps"]`. The shipped values live under
`default.poses.standing.gaps`; the runtime keeps no gap table or numeric fallback, and a per-mare
pose override still wins. The gap is measured from her centre, and a princess body's entrance sits
further back or forward than the mare's the gaps were tuned on, so `_standing_gap()` adds the
entrance's back offset (`camera/service.gd:entrance_offset()`).

That gap is the pre-act view, not the contact distance. Before the act, `_begin_standing_placement()`
fits Anon's whole body: it takes the part's natural pivot (`player_root_natural()`, the applied Hips
offset removed), her live opening and outward rear, and shifts his horizontal position so the pivot
starts one shaft behind her entrance. The fit is bounded by `STANDING_FIT_MAX_M`, skipped on a
stool, and repeated by the shape resume through `_reanchor_player_after_swap()`. It clears the
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
  `runtime.hotkey_ready()`, which reads Base clearance live after the scene rows pass
  (`tests/test_runtime_teardown.gd`). The stool suite covers the per-scan reach pair and the
  scene-first read (`tests/stool/test_gate.gd`).
- `tests/poses/test_start_setup.gd` — the closed setup vocabulary, the synthetic
  `auto`/`bed_keep_lying` row and the runtime dispatch for both bed adapters.
- `tests/readiness/test_oral_quiet.gd` — the oral contact: the plap and rump/tail jiggle skip, the
  kept slide/vocal/wings/blush/ear, the climax-line skip and the regular-path regression.
- `tests/handover/test_body_swap.gd` — the generic handover: suspend → adopt → resume, the state
  depth, climaxes and event id survive, the old runtime is not freed, the new body's anatomy and
  pose bind, adoption binds without resuming, a named shape waits for its target, the target
  completes as the shape, a missing shape restores the offer on the new body, the watchdog with a
  body resumes as a failed shape, a change the source started on its own, a repeated change, a
  failed change resumes the old body, a source that goes inactive, the no-body watchdog and an
  ineligible body end through the one exit, a world close during the swap is safe, the debug form
  label clears on the state changes while the HUD string stays empty, a failed named change restores
  the offer, her own change keeps the player's
  offer, a late body is adopted once after the grace instead of resuming the old body, a change
  during the restore finishes the act through the one exit, and a held body refuses the request.
  The entry's own adoption order is review-only: the suite fakes the entry because `main.gd` names
  the `Mods` autoload, which a `--script` suite cannot load.
- `tests/summary/test_act_flow.gd` — the state flow and the afterglow HUD summary.
- `tests/afterglow/test_afterglow.gd` — the phase decisions, including the oral passive row.
- `scripts/architecture.py --check` — the one exit, the pose ledger order and its three callers,
  the fan-out order and the pose-before-facts write in `_physics_tick`.
- The service suites indexed in `docs/README.md`.

## Verification / lab

- A full missionary act: start, pose, thrust, climax, afterglow, hold-act-key end, cuddle rejoin.
- A full standing act: presentation, lean, reach, caress, movement, smack, kiss, afterglow close,
  act-key end.
- Early end (holding the act key at 0 climaxes) and a forced stop (Debug → Force neglect stop).
- A failed start: no stuck navigator, kiss hold, inventory HUD or camera lock.
- With an installed shape-changing source, run a standing and a missionary act and use the Debug
  form actions: the flame covers the swap, the act resumes with the same depth and climaxes, the
  tail and anatomy use the new body, and a second change starts after the first completes.

## Related docs

- `docs/README.md` — the service index.
- `docs/eligibility.md`, `docs/scene_gate.md`, `docs/scene_hold.md` — the start gates and scene.
- `docs/poses.md`, `docs/camera.md` — the tick-time pose and camera.
- `docs/integrations.md` — optional mod reactions during the act.
- `docs/afterglow.md`, `docs/face.md`, `docs/summary.md` — the post-act phases.
