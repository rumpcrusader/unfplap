# Hands system

The hands system is the act's hand layer for both poses: caress, shoulder reach, smack and hand
scale. This file is the single technical contract; other docs link here.

## Scope

This contract covers:

- caress input and state in both poses;
- the pose-specific paths and authored anchors;
- the surface contact, smoothing and palm frame;
- the five-second touch meter and the caress scoring hooks;
- the shared shoulder reach and smack hand actions;
- the shared hand-bone scale and debug controls.

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
| `hand_control.gd` | act hand coordinator: A/D/Z/C latches, five-second touch meter, shoulder reach, smack target selection and palm-holder/path wiring |
| `hands/session.gd` | typed coordinator interface used by the smack action |
| `hands/placement.gd` | pose-free placement engine: oval, exact/hull contact, smoothing, palm frame, last-good target |
| `hands/path_base.gd` | path contract: ordered candidates, debug anchors, reset |
| `hands/paths/standing.gd` | standing path: authored flank -> shoulder -> neck, procedural flank/rump fallback |
| `hands/paths/missionary.gd` | missionary path: authored one/two, reach filtering, legacy hull fallback |
| `hands/paths/anchors.gd` | surface-anchored path builder: authored anchors, act-camera anchors, rest fallback |
| `hands/surface.gd` | stable posed body/head patch and exact ray queries |
| `hands/palm.gd` | single-point palm frame: basis, placement and normal turn |
| `hands/scale.gd` | shared per-preset hand-bone scale |
| `hands/reach_plan.gd` | pure two-bone reach plan for the missionary hand |
| `hands/contact.gd` | FlankSurface/PonyTouchBody hull queries and touch-hull sync |
| `hands/smack.gd` | smack phases, impact audio and return to the live caress |
| `hands/paths/anchors.json` | authored path one: shared belly, per-hand lower/belly/chest/neck/cheek |
| `hands/paths/anchors2.json` | authored path two: per-hand flank/shoulder/neck |

The pose boundary is deliberately small:

- `hand_control.gd` chooses the pose's path provider and palm holder, and supplies the
  shared hover, oval and body scale.
- `hands/placement.gd` never reads `pose_id`, `CATALOG`, the camera or the input. It receives a
  pony, a path and the palm side.
- The path providers contain all pose geometry.
- `hands/contact.gd` is generic; only its comments mention the poses.

## Pose paths

### Missionary

- `presentation.missionary.caress.path_id` selects the authored chain:
  - `one`: lower -> belly -> chest -> neck -> cheek;
  - `two`: flank -> shoulder -> neck.
- Neutral is the belly for path one and the flank for path two. W/lean walks toward the end of
  the chain; S walks toward the lower belly (path one) or clamps at the flank (path two).
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
- `hands/scale.gd` applies the shared per-preset hand scale in both poses and restores the cached
  bone scales on every act exit.
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
6. builds the single-point palm frame with `caress_hand.gd`;
7. falls back to the last good target when the path or surface is unavailable.

With `features.caress_surface` off, the candidate is a hull query through `coat.gd`: the
FlankSurface patch first, then PonyTouchBody nearest, with source hysteresis, a maximum contact
step and the same normal turn. The hull path keeps the last valid point on a miss.

## Settings

| Setting | Default | Effect |
|---|---|---|
| `features.caress_surface` | off | precise exact surface instead of the hull path |
| `features.caress_debug` | off | one precise contact line per hand per act, debug overlay |
| `features.caress_reach_shoulder_m` | 0.02 m | missionary reach shoulder shift |
| `presentation.missionary.caress.path_id` | one | authored chain `one` or `two` |
| `caress.hover_m` | 2 cm | body-scaled palm-centre hover in both poses |
| `caress.normal_blur_m` | 2 cm | coat-normal average radius; above 3 cm it averages the whole patch |
| `caress.normal_deg_s` | 120 | palm normal turn limit |
| `caress.contact_smooth` | 18/s | snap-correction low-pass |
| `caress.ignore` | tail, wing | hull regions the fallback skips |
| `caress.oval_across_m` | 1 cm | oval radius along the body |
| `caress.oval_up_m` | 2 cm | oval radius vertically |
| `caress.palm_scale.canon/mounting/same height/hoers` | .75/.9/1/1 | shared hand scale per body preset |

The three smoothing values apply to both poses. `0` restores the exact behaviour. The caress
offsets are multiplied by `Settings.anon_height_scale()` for the Same Height preset; the other
presets keep their authored values.

Standing point profiles (`CARESS_PROFILES`, metres before body scale): Canon `up 0.08`,
JRHNBR `up 0.16 / out 0.02`, Same Height `up 0.18 / out 0.03`, Hoers `up 0.20 / out 0.04`.
The rub centre is lifted `CARESS_UP_BIAS_M = 0.05` above the profile's `up` point.

## Debug and performance

- `features.caress_debug` logs one `precise caress` line per hand per act with `u`, target,
  normal, finger, roll, hover, surface and the ray hit/miss counts, and logs anchor builds/misses
  and each anchor's world position/normal.
- The debug overlay draws the path anchors, the exact contact, the palm target and the actual
  hand.
- `Print perf logs` reports `caress_tick`, `caress_precise`, `caress_surface`, `caress_ensure`,
  `caress_skin`, `caress_tri`, `caress_ray`, `caress_blur`, `caress_closest` and `caress_arm`
  chunks.
- `caress_tick` covers the controller; `caress_precise` covers the path plus engine for one hand;
  `caress_surface` covers the whole precise hand, `caress_ensure` the mesh/anchor cache check,
  `caress_skin` the patch update (skinning plus the face and normal arrays), `caress_tri` the
  `TriangleMesh` rebuild, `caress_ray` the segment query, `caress_blur` the normal average,
  `caress_closest` the full-triangle fallback when the ray misses; `caress_arm` covers the
  missionary reach plan.
- The patch is skinned and re-BVHed at most once per physics tick, and the normal blur averages
  the hit face's ring (`BLUR_RING_RADIUS_M = 0.03 m`, `BLUR_RING_DEPTH = 2`) instead of the whole
  patch; a wider radius keeps the full-scan average.

## Reach

The standing `Q`/`E` side lean can send Anon's same-side hand to her shoulder. It uses the same
palm holder and hull contact as the caress, blends from the current rest hand over 0.35 s, and
blends back over 0.35 s. While held, the forced glance looks over that shoulder. Missionary has
no shoulder reach.

## Smack

The smack action lives in `hands/smack.gd`; `hand_control.gd` keeps the pose-specific target
selection and starts the swing.

- A live caress hand is used when possible; otherwise the lean chooses a cheek.
- Standing targets the flank patch. The live caress point is used when that hand's contact
  source is `flank`; a free-hand smack queries the chosen cheek, offset by
  `smack.height_m` (signed, default `0.05 m`) and `smack.hind_m` (default `0.09 m`), then snaps
  to the nearest `FlankSurface` point and jitters within `smack_zone_radius`.
- Missionary keeps the decal-centre target shifted `0.08 m` up and `0.08 m` back.
- Standing runs raise -> strike -> contact -> recover. A caress raise lifts off the coat; a
  free-hand raise is a backswing from behind and below. The strike is cubic, CONTACT holds the
  exact frame for `0.03 s`, and RECOVER returns to the live caress or the captured rest hand.
- Missionary uses the hidden-hand `0.20 s` swing, impacting at phase `0.45`.
- A `200 ms` cooldown gates a new smack.
- The native `FlankTouch.impact` keeps its decal, blush and jiggle; the pony's game reaction
  signals are disconnected around the call.
- The pack hand-smack sound is installed immediately before impact and restored at act exit.

## Scoring hooks

- A held caress reports one `_on_touch("caress")` per `CAESS_TOUCH_SECONDS = 5 s` of contact, not
  one per physics tick. A tap shorter than five seconds scores nothing.
- Caress uses the normal touch cooldown and the `ASSIST_CAP`; a disliked caress subtracts and
  briefly sets `overwhelmed`.
- The standing afterglow close window counts active caress time. 2.5 s or more of caress grants
  the full reward; after a bad act it repairs one point of history hurt.

## Tests

- `tests/test_caress.gd`: surface patch, authored paths, side mapping, standing path, engine
  placement, smoothing and reach.
- `tests/test_actions.gd`: pure act-action helpers and smack geometry.
- `tests/test_source_hygiene.gd`: the engine has no pose reference and the docs link here.

## Known limits

- The precise patch covers the body and head meshes (torso, neck, cheek). Hair, mane, wing and
  tail layers are not part of the exact patch; the standing `Ignore body parts` setting still
  filters the hull fallback.
- The path builders cache per hand and pony; changing `path_id` rebuilds the next caress path.
