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

`main.try_start()` is the only act-start path. It composes the eligibility policy verdict with the
scene rows (`docs/eligibility.md`, `docs/scene_gate.md`) and calls `runtime.start()`. The idle hint
may reuse a per-runtime policy snapshot, but this path always builds a fresh verdict. The start
sequence:

1. re-read the identity, gate and refusal;
2. reset the stool handle and refresh the anatomy bridge;
3. begin the camera session, clear the idle presentation, the mood face and the act face;
4. snapshot the settings and preferences, build the thrust tracker and the pose config;
5. resolve the bed (missionary) or the standing spot (standing), apply the eye override and the
   initial face;
6. allocate the serial/event id, reset readiness, lines, history and the thrust state;
7. release the cradle/cuddle/navigator/player ownership through `scene_hold`;
8. snapshot the pony bones, mark the act active, build the anatomy act;
9. place the bodies, build the pose, capture the look, lock the player and the navigator, start the
   camera, the audio, the HUD and the act face, then arm the act integrations and install the
   standing stretch holder before body sway's first pass.

A failure in any step runs `_abort_start()` and the same teardown; it never leaves a partial act.

## Controls

| Input | Action |
|---|---|
| `Y` (single press, idle) | start the hinted act |
| `Y` (hold `0.35 s`) | cancel/end early at 0 climaxes; afterglow at 1+; end afterglow |
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
| `V` / `N` / `B` | anatomy hole / oral / finish, gated by `docs/anatomy.md` |
| Enter | the game chat during an act |
| hold middle | the debug action wheel; release runs the highlighted action; see `docs/debug.md` |

The debug wheel is desktop-only and does not pause the tree. While it is open the runtime ignores
mouse motion, so the wheel's virtual reticle cannot thrust or free-look the act. The wheel runs
the highlighted action and closes when the middle button is released, and normal mouse input
resumes then.

The HUD card rows, the key caps and the `End` tint are `docs/hud.md`. The lab keys are
`docs/debug.md`.

## Teardown

`_end_session(rejoin_cuddle)` is the only exit path. It gives back, in order: the inventory HUD,
request face, kiss forelegs, face-turn rate, eye override, face and wings, player lock, camera,
`sex_active`, navigator, player look, posture/cuddle, pose, audio, HUD and the active runtime. Every
step checks the ownership flag it restores (`_act_camera.camera_owned`, `_act_camera.look_captured`,
`_act_camera.eye_override`, `_hold.locked_player`, `_hold.face_turn_rate_owned`, `_hold.nav`, the
runtime's own `_posture_owned` and the HUD's borrowed quick-slot state, the controller flags), so a
failed start runs the same function and restores only what it took.

- `_finalize_session(real_act)` runs the post-act bookkeeping once and is idempotent.
- `_end_act_lines()` is deliberately outside the teardown: `cancel()` queues the early-stop reaction
  after `_restore_begin()`, and `_finish_restore()` must not cancel director rows.
- `_restore_begin()` / `_restore_now()` are the ordered leaves; `_restore_camera()` is the camera
  ledger. `_free_pose()` resets the mod-integration bridge after the base kiss, releases the shared
  excitement Beat hold, drops the standing stretch holder and its stored episode choice, and
  leaves every property the act borrowed back in place before the pose is released.
- A forced stop never rejoins the missionary bed cuddle. A normal end of a bed-sourced act that did
  not go badly re-seats Anon on the bed's player seat and re-invites her through `rest/service.gd`;
  the retry waits out aftercare and the guest cooldown, and every failure is logged before she is
  left standing.
- The afterglow, close window and aftercare are `docs/afterglow.md`; the face and mood are
  `docs/face.md`; the summary is `docs/summary.md`.

## Tick order

- `_physics_process`: `_physics_tick(delta)` — the act timer, the readiness tick, the lines, the
  history scan, the tolerance, the scene keep-alives, the anatomy tick, the thrust tracker and the
  presentation modules (wings and mod integrations).
- `_process`: `_process_tick(delta)` — the render-time pose write (which also watches the standing
  stretch toggle), the camera lean and motion, the climax wave, the breath, the face and the HUD.
- `main._process` calls `active_runtime.apply_camera_motion()` every rendered frame. Keep this
  single owner.
- Do not merge these timing domains blindly. The pose/camera timing is in `docs/poses.md` and
  `docs/camera.md`.

## Public surface

The runtime keeps thin forwards for `main.gd`, `hud/service.gd`, `input/service.gd`, the labs, `initiation/service.gd`,
`anatomy/service.gd`, `poses/standing_presentation.gd` (including `clear_stretch_offer()`) and the
tests. The stable
cross-mod surface is `docs/api.md`; the internal reads the HUD/tests use (`state`, `pose_id`,
`pony`, `pony_climaxes`, `satisfaction`, `mood`, `cue`, `depth`, `penetration_m`, `thrust_up`) stay
callable.

The runtime does not mirror a service's act state. It reads it through the owning facade
(`_readiness`, `_act_camera`, `_afterglow`, `_hold`, `_pose_session`, `_summary_service`, `_face`)
at the call site, so a suite that needs `act_thrusts`, `camera_owned`, `close_left` or `summary`
reads that facade too.

## Tests

- `tests/test_runtime_teardown.gd` — the one exit path and the ownership flags.
- `tests/test_runtime_notes.gd` — the prompt forwards.
- `tests/test_runtime_offer_policy.gd` — the idle hint's policy snapshot, its invalidation keys
  and the fresh gate path.
- `tests/summary/test_act_flow.gd` — the state flow and the afterglow HUD summary.
- `tests/afterglow/test_afterglow.gd` — the phase decisions.
- The service suites indexed in `docs/README.md`.

## Verification / lab

- A full missionary act: start, pose, thrust, climax, afterglow, hold-Y end, cuddle rejoin.
- A full standing act: presentation, lean, reach, caress, movement, smack, kiss, afterglow close,
  Y end.
- Early end (hold Y at 0 climaxes) and a forced stop (Debug → Force neglect stop).
- A failed start: no stuck navigator, kiss hold, inventory HUD or camera lock.

## Related docs

- `docs/README.md` — the service index.
- `docs/eligibility.md`, `docs/scene_gate.md`, `docs/scene_hold.md` — the start gates and scene.
- `docs/poses.md`, `docs/camera.md` — the tick-time pose and camera.
- `docs/integrations.md` — optional mod reactions during the act.
- `docs/afterglow.md`, `docs/face.md`, `docs/summary.md` — the post-act phases.
