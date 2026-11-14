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
| `hands/service.gd` | act hand coordinator: A/D/Z/C latches, five-second touch meter, shoulder reach, smack target selection and palm-holder/path wiring |
| `hands/session.gd` | typed coordinator interface used by the smack action |
| `hands/placement.gd` | pose-free placement engine: oval, posed-coat snap, smoothing, palm frame, last-good target |
| `hands/path_base.gd` | path contract: ordered candidates, debug anchors, reset |
| `hands/paths/standing.gd` | standing path: marked area chain, procedural flank/rump fallback |
| `hands/paths/missionary.gd` | missionary path: authored one/two and reach filtering |
| `hands/paths/anchors.gd` | surface-anchored path builder: authored anchors, marked area chains, act-camera anchors, rest fallback |
| `hands/surface.gd` | stable posed body/head patch, local caress window and coat queries |
| `hands/palm.gd` | single-point palm frame: basis, placement and normal turn |
| `shared/hands_scale.gd` | shared per-preset hand-bone scale |
| `shared/hands_reach_plan.gd` | pure two-bone reach plan for the missionary hand |
| `hands/contact.gd` | FlankSurface/PonyTouchBody hull queries and touch-hull sync |
| `hands/smack.gd` | smack phases, impact audio and return to the live caress |
| `hands/paths/anchors.json` | authored path one: shared belly, per-hand lower/belly/chest/neck/cheek |
| `hands/paths/anchors2.json` | authored path two: per-hand flank/shoulder/neck |
| `hands/areas/areas.json` | marked caress areas from the Blender vertex groups; standing chain |

The pose boundary is deliberately small:

- `hands/service.gd` chooses the pose's path provider and palm holder, and supplies the
  shared hover, oval and body scale.
- `hands/placement.gd` never reads `pose_id`, `CATALOG`, the camera or the input. It receives a
  pony, a path and the palm side.
- The path providers contain all pose geometry.
- `hands/contact.gd` is generic; only its comments mention the poses.

**The caress service and placement engine never read the pose; only the path does.** The caress
always ends on the posed coat surface in both poses, at either quality level. Hull contact is not
a caress: only the shoulder reach and the smack use `coat_frame()` / `hands/contact.gd`.

## Typed view

`hands/service.gd` and every hands internal read `shared/act_facts.gd`, never the runtime node. The
controller takes the view in `_init(facts)`, the engine and each path receive the same view, and
they read `pose_id`, `state`, `lean_forward`, `lean_side`, `size_name`, `size_scale`,
`same_height_scale`, `physics_delta`, `presentation_config`, `profile`, `camera` and `main`, plus
the `perf()`, `write_log()`, `feature()`, `pose_driver()`, `missionary_body()`, `touch()` and
`smack_hit()` callbacks. The smack reports through `hand_on_touch()` / `hand_on_smack_impact()` on
`hands/session.gd`, so `hands/smack.gd` needs no host node. The field and callback contract is
`docs/act_facts.md`; `tests/test_source_hygiene.gd` fails on a runtime reach-in.

## Pose paths

### Missionary

- `presentation.missionary.caress.path_id` selects the authored chain:
  - `one`: lower -> belly -> chest -> neck -> cheek;
  - `two`: flank -> shoulder -> neck.
- Neutral is the belly for path one and the flank for path two. W/lean walks toward the end of
  the chain; S walks toward the lower belly (path one) or clamps at the flank (path two).
- Each anchor is a rest-space body/head point snapped to the nearest source vertex, so it keeps
  the source skin weights and follows the live pose.
- The missionary pose uses this authored surface chain. There is no hull caress: the authored
  pose is bed-space, and a procedural hull palm frame is not valid on the lying body.
- Without authored anchors, `hands/paths/anchors.gd` casts rays from the act camera to the belly,
  chest, neck and head bone origins through the posed patch. A rest-space ray path remains the
  fallback when the camera is unavailable.
- The finger axis is the body head axis projected onto the coat tangent plane, not the path
  tangent. The palm roll is 30 degrees, fading to 0 at the neck/cheek. The neck/cheek use the
  `fingertip` mode.
- The path is reach-aware: the controller asks `missionary_anon.caress_reach()` for the world
  shoulder and upper/lower/hand lengths, then walks the path back until the palm frame fits.
- Authored sides use the missionary facing: Anon faces her, so his left hand reaches her right
  side. The path data is used as exported.

### Standing

- The standing path is the marked-area chain from `hands/areas/areas.json`:
  `flank_back -> flank_side` (the JSON `start`) `-> flank_top -> back -> shoulder -> neck`.
- No lean is the `start`; W/lean walks through the shoulder to the neck, and S walks toward
  `flank_back`. The points are the representative rest points of the marked vertex groups,
  snapped to the body/head source.
- The area JSON stores the mare's own body sides, so the standing hand side is used directly.
- The area's `region` field picks the body or head coat patch. This pass is lean-driven: W/S
  still leans and the hand follows the chain. The discrete area index, one-sided pause and
  slide/arc transition are not part of it.
- The procedural flank/rump point is the fallback when the area chain cannot build; it is
  still snapped to the posed coat by the placement engine.
- The oval uses the standing radii and the old across/up axes. The palm fingers point forward
  (`-pony.global_basis.z`).

## Palm holder

- Missionary uses `poses/missionary_anon.gd` as the palm holder. `set_hold_target()` /
  `clear_hold_target()` blend the hand off and back onto the mattress over 0.35 s. While held,
  the arm runs the game's regular desktop arm mode from the shoulder down.
- Standing uses the game's desktop pose driver through `set_hold_target(..., "rub")`.
- `shared/hands_scale.gd` applies the shared per-preset hand scale in both poses and restores the cached
  bone scales on every act exit.
- Both holders expose `hand_frame()` for the debug overlay.

## Contact engine

A path returns ordered candidates, preferred first. Each candidate carries:

```text
point, normal, oval_x, oval_y
finger, mode, roll
region                 torso or head
u                      optional debug parameter
```

For one hand the engine:

1. applies the oval offset
   `point + oval_x * cos(phase) * across + oval_y * sin(phase) * up`;
2. snaps the point to the exact body/head coat patch with one `nearest` ray on the candidate's
   region only; a ray miss uses the exact `closest()` point at `precise` quality and keeps the
   intended oval point with the path normal at `fast`;
3. applies the distance-weighted normal blur around a ray hit; a miss keeps the exact `closest()`
   normal at `precise` or the path normal at `fast`;
4. clamps the temporal normal turn;
5. low-passes the **surface snap correction**, not the intended point, so the intended oval
   motion is never delayed or shrunk;
6. builds the single-point palm frame with `hands/palm.gd`;
7. falls back to the last good target when the path or surface is unavailable.

With `features.caress_local` on, the stable region patch stays the source, but each hand skins and
raycasts only a rest-space window of its intended point. The window re-centres when the point
leaves its inner half, so the contact and the normal blur's rings never see the window boundary;
the mesh gather, the vertex rings and the face buckets are shared per source, while each hand owns
its own window so opposite flanks never compete. A point beyond the source keeps the full patch.
With the flag off, both hands share the full region patch as before.

## Lifecycle

- Scope: per-act
- Constructed by: `runtime`
- Begin: `bind()`/`begin()`
- End: act teardown
- Idempotent: yes


## Settings

| Setting | Default | Effect |
|---|---|---|
| `caress.quality` | precise | player-facing caress surface level; `precise` snaps to the coat every tick, `fast` refreshes at 15 Hz with a 1-ring blur and accepts the intended point on a ray miss |
| `features.caress_local` | on | debug: skin and raycast only the coat window around each caress hand; off restores the full region patch |
| `features.caress_debug` | off | one precise contact line per hand per act, debug overlay |
| `features.caress_reach_shoulder_m` | 0 m | missionary reach shoulder shift |
| `presentation.missionary.caress.path_id` | two | authored chain `one` or `two` |
| `caress.hover_m` | 1.5 cm | body-scaled palm-centre hover in both poses |
| `caress.normal_blur_m` | 0.5 cm | coat-normal average radius; above 3 cm it averages the whole patch |
| `caress.normal_deg_s` | 120 | palm normal turn limit |
| `caress.contact_smooth` | 24/s | snap-correction low-pass |
| `caress.ignore` | tail, wing | hull regions the smack contact query skips |
| `caress.oval_across_m` | 1 cm | oval radius along the body |
| `caress.oval_up_m` | 2 cm | oval radius vertically |
| `caress.palm_scale.canon/mounting/same height/hoers` | .75/.9/1/1 | shared hand scale per body preset |

The three smoothing values apply to both poses. `0` restores the exact behaviour. The caress
offsets are multiplied by `Settings.anon_height_scale()` for the Same Height preset; the other
presets keep their authored values.

The marked area JSON also stores `mode` and `roll`; the lean-driven standing provider uses
`region`, but keeps its existing palm frame and roll. The `mode`/`roll` fields are data for the
later discrete area pass.

Standing point profiles (`CARESS_PROFILES`, metres before body scale): Canon `up 0.08`,
JRHNBR `up 0.16 / out 0.02`, Same Height `up 0.18 / out 0.03`, Hoers `up 0.20 / out 0.04`.
The rub centre is lifted `CARESS_UP_BIAS_M = 0.05` above the profile's `up` point.

## Debug and performance

- `features.caress_debug` logs one `precise caress` line per hand per act with `u`, target,
  normal, finger, roll, hover, surface and the ray hit/miss counts, and logs anchor builds/misses
  and each anchor's world position/normal. The caress path line prints `path=areas`; the surface
  field reports `faces=<window>/<patch>`.
- The debug overlay draws the path anchors, the exact contact, the palm target and the actual
  hand.
- `Print perf logs` reports `caress_tick`, `caress_precise`, `caress_surface`, `caress_ensure`,
  `caress_select`, `caress_skin`, `caress_tri`, `caress_ray`, `caress_blur`, `caress_closest` and
  `caress_arm` chunks.
- `caress_tick` covers the controller; `caress_precise` covers the path plus engine for one hand;
  `caress_surface` covers the whole caress hand, `caress_ensure` the mesh/anchor cache check,
  `caress_select` the window re-centre, `caress_skin` the patch update (skinning plus the face and
  normal arrays), `caress_tri` the `TriangleMesh` rebuild, `caress_ray` the segment query (it also
  contains the lazy `TriangleMesh` rebuild on a refresh), `caress_blur` the normal average,
  `caress_closest` the full-triangle fallback when the ray misses; `caress_arm` covers the
  missionary reach plan.
- The patch is skinned and re-BVHed at most once per `caress.quality` refresh (33 ms precise,
  66 ms fast) and at most once per physics tick per hand; a window re-centre forces one update
  regardless of the refresh. A refresh is also skipped while every bound bone is within
  `POSE_EPS_M` (0.8 mm) and `POSE_EPS_SIN` (0.15°) of the last skinned pose, so a still body does
  not pay for the skin, the soup write and the BVH rebuild; the retry costs one bone compare per
  tick. The normal blur averages the hit face's ring (`BLUR_RING_RADIUS_M = 0.03 m`, 2 rings
  precise, 1 fast) instead of the whole patch; a wider radius scans the whole active patch, which
  is the local window when the flag is on.

## Reach

The standing `Q`/`E` side lean can send Anon's same-side hand to her shoulder. It uses the same
palm holder as the caress but a hull contact, blends from the current rest hand over 0.35 s, and
blends back over 0.35 s. While held, the forced glance looks over that shoulder. Missionary has
no shoulder reach.

## Smack

The smack action lives in `hands/smack.gd`; `hands/service.gd` keeps the pose-specific target
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

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | settings | `settings/service.gd` | settings declarations and live values |
| shared | pose_catalog | `shared/pose_catalog.gd` | pose ids and defaults |

## Tests

- `tests/hands/test_caress.gd`: surface patch and its two quality levels, authored paths, marked
  area path, side mapping, standing path, engine placement, smoothing and reach.
- `tests/hands/test_actions.gd`: pure act-action helpers and smack geometry.
- `tests/test_source_hygiene.gd`: the engine has no pose reference and the docs link here.

## Known limits

- The coat patch covers the body and head meshes (torso, neck, cheek). Hair, mane, wing and tail
  layers are not part of the exact patch; the standing `Ignore body parts` setting filters the
  smack's hull contact query only.
- The local window follows the hand's intended point; a point that lands beyond the region source
  keeps the full patch for that hand. `ray()` (the authored anchor build) always uses the full
  patch, because it maps a soup face back to a source vertex.
- The path builders cache per hand and pony; changing `path_id` rebuilds the next caress path.
- The area chain is lean-driven: W/S still leans and the hand follows the JSON chain.
  It does not add a discrete area index, a one-sided pause or the slide/arc transition.
- The area JSON is global for the shared body/head. A missing side or fewer than three buildable
  areas makes the area chain fail and the standing provider falls back to the procedural
  flank/rump point.
- The area chain uses one representative point per group (the vertex nearest the group mean). It
  does not roam the whole marked region; the oval remains the local stroke.
- `hands/service.gd` is the facade and the coordinator in one file. It reads the typed act view
  (`facts.lean_forward`, `facts.size_scale`) and its own copies of the presentation config and the
  per-mare profile, and calls callbacks the runtime injects (`_on_touch`, `_log`, `perf_note`).
  New hand code uses the coordinator's methods; do not add another host read.
