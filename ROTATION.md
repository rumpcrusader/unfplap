# Rotation and positioning contract

This file records the brittle skeleton/pose logic. Keep it next to the code and update it
whenever a pose value or order changes.

## Spaces and axes

- Bone writes use `Skeleton3D` skeleton space via `get_bone_global_pose` /
  `set_bone_global_pose`.
- Axes are body-relative:
  - `right = sk.global_basis.inverse() * pony.global_basis.x`
  - `up = sk.global_basis.inverse() * pony.global_basis.y`
  - `forward = sk.global_basis.inverse() * -pony.global_basis.z`
- `up` is world gravity, not the pony's rolled dorsal axis.
- Never use raw world axes for bone posing.
- `pony_head.basis.z` is **not** the face axis. The head must not be rotated by
  straight-chain alignment; keep it in the bone list only as a direction target for
  `pony_neck2`. The head follows neck2 through its rest offset.

## Missionary (legacy Pose 1)

Exact order:

1. `_roll_root(PI * weight)`
   - pivot: `pony_hips` origin
   - axis: `forward`
   - rotates root origin and basis, then adds `up * 0.03 * |angle|`.
2. `_lift_root(0.05 * weight)`.
3. `_straighten_spine_neck()`
   - bones: `pony_hips`, `pony_spine1..3`, `pony_neck1..2`, `pony_head`
   - slerps each local pose rotation toward its rest rotation by weight.
   - Including the pelvis removes the game's bed `lie_down` curl.
4. `_align_chain_straight()`
   - bones: spine1–3 and neck1–2; head is a direction target only.
   - target is `forward` with `y = 0`, normalized.
   - each bone direction is measured to the next bone's origin.
   - shortest-arc rotation directly written to the global pose; no joint-limit clamp.
5. `_level_body_roll()`
   - left/right hind-femur origins.
   - `_line_roll()` measures the lateral line; wrap the result into ±90°.
   - adds `POSE1_ROLL_TWEAK`.
   - rotates the root around `forward` at the hips pivot.
6. `_level_chest_roll()`
   - left/right upper-arm origins.
   - `_line_roll()`; rotates only `pony_spine1` around `forward`.
7. `_pitch_body_about_shoulders(POSE1_RUMP_DROP_DEG)`
   - pivot: midpoint of the two upper-arm origins.
   - rotates root origin and basis about `right`.
   - positive angle moves the pelvis/rump behind the pivot downward.
8. `_bend_forelegs(0.3)`.
9. `_raise_hind_legs()`
   - femur target `(up * 0.75 + forward * 0.45).normalized()`
   - knee bend `-0.55` around `right`.
10. `_hug_forelegs()`.
11. `_aim_head(POSE1_LOOK_SCALE)`
    - yaw/pitch from head origin to `look_point`.
    - neck shares `[0.30, 0.36, 0.34]`.
    - pitch clamp `±0.8`, yaw clamp `±1.1`.
12. Nuzzle
    - `_nuzzle_pulse()`: 0→1→0 over `NUZZLE_DURATION` every `NUZZLE_PERIOD`.
    - extra `_aim_head(pulse * POSE1_NUZZLE_SCALE)`.
    - during climax: `pulse = 0.75 + 0.25 * sin(_clock * 4.0)`.
13. `_roll_head(head_roll)` around `forward`, head only.
14. Dump once at weight > 0.9 if debug is on.

The debug chin pitch lives in `chin_debug.gd`, a separate `SkeletonModifier3D` appended after
the pose modifier. It is not part of the missionary recipe, so `Alt+7` / `Alt+8` also work
while idle or standing.

`_line_roll` must always select the branch nearest level, in (−90°, +90°]. Without the
wrap, the correction can roll her belly-up to belly-down while still "levelling" the
legs.

### Head-back effect (reserved)

Positive `_lift_neck()` angles were `0.10 / 0.08 / 0.06` around the body's right axis.
They throw the neck/head back and were intentionally not applied in missionary. Keep
these values here if a future pose needs that effect.

## Pose-1 camera

- Anchor: `root + up * 0.55 - back * 0.15`, where `back = +pony.global_basis.z`.
- Snout aim is sampled during the 1 s blend and then frozen; it does not track the live nose.
- Free camera mode has no mouse look. WASD rotates the view at `CAMERA_LOOK_SPEED = 1.0 rad/s`;
  W/S pitch within `±POSE1_FREE_PITCH_LIMIT = 1.0`, A/D yaw within
  `±POSE1_FREE_YAW_LIMIT = 1.2`. It never translates Anon or the view.
- Free mode locks `player.controls_locked` for both poses and restores the previous value on
  legacy toggle/end.
- Legacy mode adds mouse yaw/pitch offsets on top, scaled by `ACT_LOOK_YAW_SCALE = 0.10` and
  `ACT_LOOK_PITCH_SCALE = 0.10`.
- Camera bobs are opt-in: `pump.bobs` defaults to `false` and skips pump and climax bob motion.
- When enabled, each pump adds to the vertical and forward spring velocities.
- Pose 1 uses `_bob * POSE1_BOB_SCALE` (`0.35`); pose 2 uses `_bob` directly.
- Slow pumps scale the bob timebase: stiffness by `s²`, damping and impulse by `s`, with
  `s = clamp(speed / BOB_SPEED_REFERENCE, 0.35, 1.0)`. At `>= 0.80` depth/s the bob is unchanged.
- Climax uses `BOB_CLIMAX_AMPLITUDE = 0.025 / 6` and `BOB_CLIMAX_FORWARD = 0.12 / 6`.
- Restore order is load-bearing:
  1. player transform and yaw,
  2. pony transform and posture,
  3. camera transform + `make_current()`.
- Do not reorder: setting player yaw rotates a child camera.
- After restore, re-invite the pony through the seat's couch; if that fails, restore
  the captured posture.

## Horse (legacy Pose 2)

- Facing lock every physics tick at priority 100:
  `pony.global_transform.basis = _facing_basis.scaled(scale)`.
- Camera height through player `_stand_eye` / `_eye_height`; never teleport the rig.
- Free mode aims the player camera at the joint connecting her head and neck (`pony_head`
  origin, `pony_neck2` fallback) during the 1 s blend, then freezes; WASD rotates the view
  (W/S pitch, A/D yaw) inside the 45° cone. Legacy mode keeps the same look cone around the
  captured yaw.
- Standing gap per size preset.
- Glances use `pony.secondary.look_toward`; `head_back` is eased; pupils aim via
  `eye_motion.target_world` / `target_weight`.
- Anon's hip follows raw pump `depth` directly: `THRUST_MAX_M = 0.045 m` forward at full depth,
  no spring or return animation.
- Tail aside/lift/flick on the hair skeleton; side randomized per act.
- Withdrawal eases back, flicks the tail twice, records the inside event, then
  restores automatically.
- Pose 2 has no afterglow.

## Aftercare

- No head lowering.
- Tail held raised straight (`aside_angle = 0`), with `flick_amplitude = 0.55` and a
  one-cycle flick every `1.4–2.4 s` on the hair skeleton.
- Navigator held for 10 s.

## Timing domains

- `runtime._process`: view-depth travel, lean, climax wave, breath, look point, pose climax flag.
- `runtime._physics_process`: presentation, timers, facing lock, glances,
  auto-cuddle suppression.
- `main._process`: calls `active_runtime.apply_camera_motion()` every rendered frame.
  Keep this single owner.
- Do not merge these timing domains blindly.
