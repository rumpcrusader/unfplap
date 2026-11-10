# Caress system

The caress is the act hand system for both poses: A/D rub her coat, Z/C pause or resume the
oval, and the same controller owns the shoulder reach and act smack. This file is the single
technical contract for the caress; other docs link here.

## Scope

This contract covers:

- caress input and state in both poses;
- the pose-specific paths and authored anchors;
- the surface contact, smoothing and palm frame;
- caress settings and debug controls;
- the five-second touch meter and the caress scoring hooks.

Shoulder reach and smack are described here only where they share the caress hand. Their own
phase, target and audio contracts stay in `AGENTS.md`/`ROTATION.md`.

## Controls

| Input | Missionary | Standing |
|---|---|---|
| `A` | toggle Anon's left hand on her chest/belly | toggle his left hand on her flank |
| `D` | toggle Anon's right hand on her chest/belly | toggle his right hand on her flank |
| `Z` | pause/resume the left hand's oval | pause/resume the left hand's oval |
| `C` | pause/resume the right hand's oval | pause/resume the right hand's oval |
| `X` hold | auto-thrust panel freezes A/D and Z/C | same |

- Both hands can caress at once. Each press toggles that hand independently.
- A tap that is released quickly still latches; the next tap stops it.
- The hold-X auto panel owns A/D and Z/C while open: the hands keep their state and the caress
  keeps scoring, but the keys are ignored.
- Lean and A/D caress stay live in `AFTERGLOW`. The standing afterglow counts active caress time
  for its close window.
- A smack with both hands caressing chooses one hand at random; the other keeps caressing. The
  caress oval keeps moving through the smack, so the hand returns to the live point.

## Architecture

| File | Role |
|---|---|
| `caress_control.gd` | act hand controller: A/D/Z/C latches, five-second touch meter, shoulder reach, smack, palm-holder and path wiring |
| `caress/caress_system.gd` | pose-free placement engine: oval, exact/hull contact, smoothing, palm frame, last-good target |
| `caress/caress_path_base.gd` | path contract: ordered candidates, debug anchors, reset |
| `caress/flank_path.gd` | standing path: authored flank -> shoulder -> neck, procedural flank/rump fallback |
| `caress/missionary_path.gd` | missionary path: authored one/two, reach filtering, legacy hull fallback |
| `caress/caress_path.gd` | surface-anchored path builder: authored anchors, act-camera anchors, rest fallback |
| `caress/caress_surface.gd` | stable posed body/head patch and exact ray queries |
| `caress/caress_hand.gd` | palm/finger sample shape, palm basis, penetration resolver |
| `caress/caress_arm.gd` | pure two-bone reach plan for the missionary hand |
| `caress/coat.gd` | FlankSurface/PonyTouchBody hull queries and touch-hull sync |
| `caress/anchors.json` | authored path one: shared belly, per-hand lower/belly/chest/neck/cheek |
| `caress/anchors2.json` | authored path two: per-hand flank/shoulder/neck |

The pose boundary is deliberately small:

- `caress_control.gd` chooses the pose's path provider and palm holder, and supplies the
  pose's hover, oval scale and body scale.
- `caress_system.gd` never reads `pose_id`, `CATALOG`, the camera or the input. It receives a
  pony, a path and the palm side.
- The path providers contain all pose geometry.
- `caress/coat.gd` is generic; only its comments mention the poses.

## Pose paths

### Missionary

- `presentation.missionary.caress.path_id` selects the authored chain:
  - `one`: lower -> belly -> chest -> neck -> cheek;
  - `two`: flank -> shoulder -> neck.
- Neutral is the belly for path one and the flank for path two. W/lean walks toward the end of
  the chain; S walks toward the lower belly (path one) or clamps at the flank (path two).
  `presentation.missionary.caress.along_m` shifts the sampled point before the oval.
- Each anchor is a rest-space body/head point snapped to the nearest source vertex, so it keeps
  the source skin weights and follows the live pose.
- Without authored anchors, `caress_path.gd` casts rays from the act camera to the belly, chest,
  neck and head bone origins through the posed patch. A rest-space ray path remains the fallback
  when the camera is unavailable.
- The finger axis is the body head axis projected onto the coat tangent plane, not the path
  tangent. The palm roll is 30 degrees, fading to 0 at the neck/cheek. The neck/cheek use the
  `fingertip` mode.
- The path is reach-aware: the controller asks `missionary_anon.caress_reach()` for the world
  shoulder and upper/lower/hand lengths, then walks the path back until the palm frame fits.
- Authored sides use the missionary facing: Anon faces her, so his left hand reaches her right
  side. The path data is used as exported.

### Standing

- The precise path is the authored `anchors2.json` chain: flank -> shoulder -> neck.
- No lean is the flank. W/lean walks through the shoulder to the base of the neck.
- S keeps the procedural rump-top reach, reaching it at `CARESS_RUMP_LEAN = 0.5`.
- The standing provider requests the opposite authored hand side because Anon is behind her and
  his left hand reaches her left side. The path data is unchanged.
- The procedural flank/rump point is the hull path when `features.caress_surface` is off and
  the fallback when the authored anchors cannot build.
- The oval uses the standing radii and the old across/up axes. The palm fingers point forward
  (`-pony.global_basis.z`).

## Palm holder

- Missionary uses `missionary_anon.gd` as the palm holder. `set_hold_target()` /
  `clear_hold_target()` blend the hand off and back onto the mattress over 0.35 s. While held,
  the arm runs the game's regular desktop arm mode from the shoulder down.
- Standing uses the game's desktop pose driver through `set_hold_target(..., "rub")`.
  `palm_scale.gd` applies the per-preset scale after BodyIK and restores the cached bone scales
  on every act exit.
- Both holders expose `hand_frame()` for the debug overlay.

## Contact engine

A path returns ordered candidates, preferred first. Each candidate carries:

```text
point, normal, oval_x, oval_y
finger, mode, roll
region                 torso or head
precise                exact surface or hull query
hull_lift, ignore, regions, radial   legacy hull only
```

For one hand the engine:

1. applies the oval offset
   `point + oval_x * cos(phase) * across + oval_y * sin(phase) * up`;
2. for `precise`, snaps the point to the exact body/head patch with one `nearest` ray on the
   candidate's region only;
3. applies the distance-weighted normal blur around the hit;
4. clamps the temporal normal turn;
5. low-passes the **surface snap correction**, not the intended point, so the intended oval
   motion is never delayed or shrunk;
6. builds the palm frame with `caress_hand.gd`, including the optional multi-sample palm/finger
   resolver;
7. falls back to the last good target when the path or surface is unavailable.

With `features.caress_surface` off, the candidate is a hull query through `coat.gd`: the
FlankSurface patch first, then PonyTouchBody nearest, with source hysteresis, a maximum contact
step and the same normal turn. The hull path keeps the last valid point on a miss.

## Settings

| Setting | Default | Effect |
|---|---|---|
| `features.caress_surface` | off | precise exact surface instead of the hull path |
| `features.caress_hand_shape` | off | multi-sample palm/finger resolver |
| `features.caress_debug` | off | one precise contact line per hand per act, debug overlay |
| `features.caress_reach_shoulder_m` | 0.02 m | missionary reach shoulder shift |
| `features.caress_reach_body_m` | 0.0 m | missionary reach body shift |
| `features.caress_reach_stretch` | 1.0 | missionary arm stretch cap |
| `presentation.missionary.caress.path_id` | one | authored chain `one` or `two` |
| `presentation.missionary.caress.along_m` | 0 cm | signed shift toward head/tail |
| `presentation.missionary.caress.over_coat_m` | 2 cm | signed palm-centre hover |
| `presentation.missionary.caress.normal_blur_m` | 2 cm | coat-normal average radius |
| `presentation.missionary.caress.normal_deg_s` | 120 | palm normal turn limit |
| `presentation.missionary.caress.contact_smooth` | 18/s | snap-correction low-pass |
| `presentation.missionary.caress.oval_scale` | 1.0x | oval scale |
| `presentation.standing.caress.palm_distance` | 2 cm | standing palm-centre hover |
| `presentation.standing.caress.oval_across_m` | 1 cm | oval radius along the body |
| `presentation.standing.caress.oval_up_m` | 2 cm | oval radius vertically |
| `presentation.standing.caress.ignore` | tail, wing | hull regions the fallback skips |
| `presentation.standing.caress.palm_scale` | per preset | standing palm bone scale: Canon 0.75, mounting 0.9, same height/Hoers 1.0 |

The three smoothing values apply to both poses. `0` restores the exact behaviour. The standing
caress offsets are multiplied by `Settings.anon_height_scale()` for the Same Height preset; the
other presets keep their authored values.

Standing point profiles (`CARESS_PROFILES`, metres before body scale): Canon `up 0.08`,
JRHNBR `up 0.16 / out 0.02`, Same Height `up 0.18 / out 0.03`, Hoers `up 0.20 / out 0.04`.
The rub centre is lifted `CARESS_UP_BIAS_M = 0.05` above the profile's `up` point.

## Debug and performance

- `features.caress_debug` logs one `precise caress` line per hand per act with `u`, target,
  normal, finger, roll, hover and surface, and logs anchor builds/misses and each anchor's world
  position/normal.
- The debug overlay draws the path anchors, the exact contact, the palm target and the actual
  hand.
- `Print perf logs` reports `caress_tick`, `caress_precise`, `caress_surface`, `caress_hand` and
  `caress_arm` chunks.
- `caress_tick` covers the controller; `caress_precise` covers the path plus engine for one hand;
  `caress_surface` covers the stable patch update, exact query and normal blur; `caress_hand`
  covers the multi-sample resolver; `caress_arm` covers the missionary reach plan.

## Scoring hooks

- A held caress reports one `_on_touch("caress")` per `CAESS_TOUCH_SECONDS = 5 s` of contact, not
  one per physics tick. A tap shorter than five seconds scores nothing.
- Caress uses the normal touch cooldown and the `ASSIST_CAP`; a disliked caress subtracts and
  briefly sets `overwhelmed`.
- The standing afterglow close window counts active caress time. 2.5 s or more of caress grants
  the full reward; after a bad act it repairs one point of history hurt.

## Tests

- `tests/test_caress.gd`: surface patch, hand shape, authored paths, side mapping, standing path,
  engine placement, smoothing and reach.
- `tests/test_actions.gd`: pure act-action helpers and smack geometry.
- `tests/test_source_hygiene.gd`: the engine has no pose reference and the docs link here.

## Known limits

- The precise patch covers the body and head meshes (torso, neck, cheek). Hair, mane, wing and
  tail layers are not part of the exact patch; the standing `Ignore body parts` setting still
  filters the hull fallback.
- The multi-sample hand resolver is a debug feature; off uses the single palm-centre point.
- The path builders cache per hand and pony; changing `path_id` rebuilds the next caress path.
