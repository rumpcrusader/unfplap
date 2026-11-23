# VR act

The optional room-scale VR standing act. Desktop paths never create it. It drives the same depth
and anatomy actions as the desktop keys; the fork's auto-speed and stroke-depth controls are
deliberately not imported.

## Ownership

`vr/act.gd` is the per-act VR handle. `act/session.gd:begin_vr()` calls its static `attach()`,
which resolves the player, the `AnonBody` avatar, the `XRCamera3D`/`XROrigin3D` pair and the
avatar's hip target from the live scene; a desktop launch or a missing rig returns null. The
controller is a scene adapter with typed callables, never the runtime node: `toggle_hole`,
`oral_ready`, `forward`, `depth`, the `command` dispatcher for the oral id, the `touch` readiness
event and a `pony_source` read. The session binds those to its own anatomy target and impact
calls, so VR scene construction no longer lives in anatomy. The session also passes `player`,
`hip_target`, `camera` and `origin`; `stop_vr()` frees the node with the act handle.

## Controls

| Input | Action |
|---|---|
| right `primary_click` | the act key (the runtime's context start/end) |
| right `ax_button` | toggle the anatomy hole |
| left `by_button` | the `oral` command while the anatomy gate is open |
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
  start gate, the offer refresh, refusal and the act key. A headset rig has neither a `controls_locked` nor a
  `flying` property, so those reads compare against `true` rather than going through `bool()`.
- Anatomy actions are additive and gated; the hole and finish use the same `toggle_anatomy_*`
  runtime forwards as the desktop keys, and the oral button emits the `oral` command only while
  `oral_ready()` is open. `docs/anatomy.md` owns the behavior.
- VR is behind the anatomy master. Desktop human Anon owns the free act camera.
- A form change in the optional VR standing act uses the same handover, with no new input-map key:
  the reveal ask and the named shape still arrive through the game's own talk turn. There is no
  act-HUD form hint in any build; the player discovers the reveal and the gift. **Enable debug**
  writes the state to the run log only (`docs/runtime.md`). The flame covers the re-pose and the
  camera/view adjustment; the head-tracked view is not broken by the reopen.

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
