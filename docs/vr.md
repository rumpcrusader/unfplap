# VR act

The optional room-scale VR standing act. Desktop paths never create it. It drives the same depth
and anatomy actions as the desktop keys; the fork's auto-speed and stroke-depth controls are
deliberately not imported.

## Ownership

`vr/service.gd` is the VR controller, created by the anatomy bridge's `vr_start()` (called from the
runtime's `_start_vr_act()`) when a headset is active and a `XRCamera3D`/`XROrigin3D` pair exists
under the player. It is a scene adapter with typed handles, never the runtime node: the bridge
handle (`toggle_hole`, `toggle_finish`, `toggle_oral`, `vr_forward`, `vr_depth`), the `align`
write-back, the `touch` readiness event and a `pony_source` read. It also receives `player`,
`hip_target`, `camera` and `origin`, and queues itself free in `vr_stop()`. The runtime owns the
standing act state; the bridge owns the anatomy hooks the controller calls.

## Controls

| Input | Action |
|---|---|
| right `primary_click` | `Y` (the runtime's context start/end) |
| right `ax_button` | toggle the anatomy hole |
| left `primary_click` | toggle the finish |
| left `by_button` | toggle oral |
| waist/hip tracker | depth: the hip delta along `vr_forward()`, mapped over `HIP_RANGE_M = 0.16 m` |
| real hand petting | `on_touch("caress")` |
| left/right stick | reserved for the act's lean and turn |

The controller reads the body tracker first (`XRBodyTracker.JOINT_HIPS`), then a positional tracker
whose name contains `waist` or `hip`. With no tracking data it leaves the depth alone. The
`HIP_RANGE_M = 0.16`, `STICK_DEAD = 0.5` and `STICK_REPEAT_S = 0.18` constants are in the
controller.

## Rules

- Only the standing pose is supported. The mare stays in place, so the act never needs Anon's ground
  position from the rig root, which stays at the spawn anchor.
- A headset session has no desktop pointer: `headset_view()` stands in for a captured mouse in the
  start gate, the offer refresh, refusal and Y. A headset rig has neither a `controls_locked` nor a
  `flying` property, so those reads compare against `true` rather than going through `bool()`.
- Anatomy actions are additive and gated; they use the same `toggle_anatomy_*` runtime forwards as
  the desktop keys. `docs/anatomy.md` owns the behavior.
- VR is behind the anatomy master. Desktop human Anon owns the free act camera.

## Lab

```bash
./lab-vr.sh [--no-service] [--vr-lab-autostart]
```

- Runs the same lab in room-scale XR under Monado and writes `last-run-vr.log`;
  `last-run-vr-monado.log` holds the runtime's log.
- The script starts `monado-service` with its qwerty driver (virtual HMD plus both hand
  controllers); `--no-service` uses one you started.
- The Monado window owns the keyboard while focused; pose the headset there and keep the game
  focused for the lab keys. Seated VR cannot run this lab: that rig has no controllers.
- `tests/test_lab_vr.gd` adds a fake `waist` XRPositionalTracker, which `_tracked_hips()` accepts:
  `[`/`]` move it 5 mm, `;` toggles a 1.1 Hz stroke and `F9` places Anon behind the aimed or nearest
  adult test mare. `--vr-lab-autostart` qualifies the nearest mare, starts the standing act and
  turns the stroke on for a scripted smoke run. The log prints state, thrust count, readiness and
  both preference axes once a second.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|

## Lifecycle

- Scope: per-act
- Constructed by: `anatomy` act bridge
- Begin: act start
- End: act end
- Idempotent: yes


## Tests

- `tests/test_vr_act.gd` — tracker selection, depth clamping, hand action routing and the start
  hooks.

## Related docs

- `docs/anatomy.md` — the anatomy action hooks and the act bridge.
- `docs/poses.md` — the standing pose and placement.
- `docs/camera.md` — the desktop shot; VR keeps the stock camera.
- `docs/eligibility.md` — the headset view exception in the start gate.
