# Hands system

The hands system is the act's hand layer for the two base poses: caress, shoulder reach, smack and hand
scale. This file is the single technical contract; other docs link here.

## Scope

This contract covers:

- caress input and state in the two base poses;
- the pose-specific paths and authored anchors;
- the fitted-sphere contact, smoothing and palm frame;
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
- During standing oral, `A`/`D` keep their per-hand toggles and `Z`/`C` keep the oval, but the
  target is the side of her head instead of the flank chain.
- The hold-X auto panel owns A/D and Z/C while open: the hands keep their state and the caress
  keeps scoring, but the keys are ignored.
- Lean and A/D caress stay live in `AFTERGLOW`. The standing afterglow counts active caress time
  for its close window.
- A smack uses the free hand while one hand caresses; the caress keeps running. A reaching hand
  is not free. With both hands busy (caressing or reaching), one hand is picked at random and its
  caress or reach ends: it does not come back after the swing.

## Architecture

| File | Role |
|---|---|
| `hands/api.gd` | the one facade: public `Side`, the per-pony handle and its eight actions |
| `hands/controller.gd` | coordinator: composition, tick order, pose hook and smack policy |
| `hands/port.gd` | typed host seam between the coordinator and the action modules |
| `hands/model.gd` | private typed records, the side mirror and the pure caress math |
| `hands/caress.gd` | two-hand caress state, input latch, touch meter, oral blend and warm-up |
| `hands/reach.gd` | shoulder reach state, hold and release blend |
| `hands/smack.gd` | swing, impact and the pack-sound swap |
| `hands/smack_target.gd` | hand choice, pose target, flank/cheek query and jitter |
| `hands/debug_draw.gd` | the debug overlay nodes and immediate-mesh drawing |
| `hands/path_selector.gd` | pose view to the current path provider, cache and reset |
| `hands/placement.gd` | pose-free placement engine: oval, fitted-sphere contact, smoothing, palm frame, last-good target |
| `hands/path_base.gd` | path contract: ordered candidates, debug anchors, reset |
| `hands/paths/standing.gd` | standing path: marked area chain, procedural flank/rump fallback |
| `hands/paths/oral.gd` | standing oral path: one authored head-side node per hand, mare-PoV lookup flipped for Anon |
| `hands/paths/missionary.gd` | missionary and bed face-sit path: authored one/two and reach filtering |
| `hands/paths/anchors.gd` | sphere path builder: one fitted sphere per authored area, skinning, lean sampling, background fit |
| `hands/coat_fit.gd` | the one coat reader: one sphere per authored area, fitted once per skin and cached |
| `hands/palm.gd` | single-point palm frame: basis, placement and normal turn |
| `hands/contact.gd` | FlankSurface/PonyTouchBody hull queries and typed helpers |
| `shared/hands_scale.gd` | shared per-preset hand-bone scale |
| `shared/hands_reach_plan.gd` | pure two-bone reach plan for the missionary hand |
| `hands/paths/anchors.json` | authored path one: shared belly, per-hand lower/belly/chest/neck/cheek |
| `hands/paths/anchors2.json` | authored path two: per-hand flank/shoulder/neck |
| `hands/areas/areas.json` | marked caress areas from the Blender vertex groups; standing chain and the single oral head-side node |

`hands/api.gd` is the only file another part of the mod may import. The controller,
port, model, action modules, engine, paths and the shared hand modules stay private to the
service or to the poses.

## Ownership

The hands service owns the per-act caress, reach and smack state and the two debug overlay nodes.
It keeps no saved data: the state is per act and `reset()` clears it on the existing exit, start
and body-swap paths. The controller owns its action modules and each holds it only weakly, so the
graph collects without a release; the facade's private release still drops the links on the
runtime's exit path, and `reset()` stays the per-act reset.
The runtime owns scoring and the act state; hands reports through the typed act view.

## Data ownership

No hands data is saved. The act session owns the state, timers and scoring values the hands
report into; the pose owns the body and the hold targets. The service has no persistent node or
subscription, so it takes no world lifecycle hooks.

## Typed view

`hands/api.gd` is the facade; the controller and the action modules read `shared/act_facts.gd`,
never the runtime node. The controller takes the view in `_init(facts)`, the caress and the reach
receive the same view, and the path selector and path base hold it. They read `state`,
`lean_forward`, `lean_side`, `size_name`, `size_scale`, `same_height_scale`, `physics_delta`,
`presentation_config`, `profile`, `camera`, `pony`, `pose_view` and the
`feature()`, `call_value()`, `pose_driver()`, `missionary_body()`, `touch()` and `smack_hit()`
callbacks. The pose path and the contact come from `facts.pose_view`: the path selector reads
`view.hands.path` and `view.contact_kind`, not a start pose id or a contact mirror. The smack
reports through `PORT.touch()` and `PORT.impact()`, so `hands/smack.gd` needs no host node. The
field and callback contract is `docs/act_facts.md`.

The caress profile, touch step, flank hit, smack presentation and the context records are typed
in `hands/model.gd`. The public side enum lives in `hands/api.gd`; `hands/model.gd` carries a
private mirror because the controller cannot preload the facade without a cycle. The facade maps
one to the other once. Base-game hand, flank and `PonyTouchBody` members go through the world
facade's typed views; the mod-owned `missionary_anon.caress_reach()` read stays a `Callable`
because that body is not a base-game node.

The hands' `pose_changed(view)` hook retargets the contact path: it caches `view.hands.path` and
`view.contact_kind`; a path change ends the live caress holds but keeps the controller, and a
contact switch (opening -> mouth) keeps them so the oral blend captures the hand frames on the next
tick. The bed face-sit reuses `hands.path = "missionary"`; a four-size reach failure is a focused
path fix, never a pose-id branch. The standing ↔ oral path change is the one exception: the pair is
one contact-driven path, so the holds survive the request and the mouth switch does the retarget. A
path change to or from missionary still ends them. `tests/hands/test_caress.gd` and
`tests/hands/test_actions.gd` pin both seams.

## Pose boundary

The pose boundary is deliberately small:

- `hands/path_selector.gd` chooses the pose's path provider from the pose view.
- `hands/placement.gd` never reads `pose_id`, `CATALOG`, the camera or the input. It receives a
  pony, a path, a hand side and a resolved `CaressContext`.
- The path providers contain all pose geometry and receive the same resolved context.
- `hands/contact.gd` is generic; only its comments mention the poses.

**The caress service and placement engine never read the pose; only the path does.** The caress
always ends on the posed coat surface in the two base poses, at either quality level. Hull contact
is not a caress: only the shoulder reach and the smack use `coat_frame()` /
`hands/contact.gd`.

## Pose paths

`path_selector.gd` selects from `facts.pose_view.hands.path`: `missionary` is the chest/neck/cheek
path; `standing` and `oral` use the mouth contact (`view.contact_kind == "mouth"`) for the head
path and the flank path otherwise. The contact is the switch, so the head path starts at the
edge's contact time, not at the request.

### Missionary

- `presentation.missionary.caress.path_id` selects the authored chain:
  - `one`: lower -> belly -> chest -> neck -> cheek;
  - `two`: flank -> shoulder -> neck.
- Neutral is the belly for path one and the flank for path two. W/lean walks toward the end of
  the chain; S walks toward the lower belly (path one) or clamps at the flank (path two).
- Each anchor is one fitted rest-space sphere: its centre sits under the authored point, and the
  nearest coat vertex supplies the coat normal and the skin weights it follows.
- The missionary pose uses this authored area chain. There is no hull caress: the authored pose is
  bed-space, and a procedural hull palm frame is not valid on the lying body.
- A missing authored slot fails the path; there is no camera or rest ray fallback.
- The finger axis is the body head axis projected onto the coat tangent plane, not the path
  tangent. The palm roll is 30 degrees, fading to 0 at the neck/cheek. The neck/cheek use the
  `fingertip` mode.
- The path is reach-aware: the controller asks `missionary_anon.caress_reach()` for the world
  shoulder and upper/lower/hand lengths, then walks the path back until the palm frame fits. The
  resolved lengths and the shoulder cap travel in the caress context.
- Authored sides use the missionary facing: Anon faces her, so his left hand reaches her right
  side. The path data is used as exported.

### Standing

- The standing path is the marked-area chain from `hands/areas/areas.json`:
  `flank_back -> flank_side` (the JSON `start`) `-> flank_top -> back -> shoulder -> neck`.
- No lean is the `start`; W/lean walks through the shoulder to the neck, and S walks toward
  `flank_back`. The points are the representative rest points of the marked vertex groups, and
  `hands/coat_fit.gd` fits one sphere through the nearest coat vertex at each.
- The area JSON stores the mare's own body sides, so the standing hand side is used directly.
- The area's `region` field picks the body or head mesh. This pass is lean-driven: W/S
  still leans and the hand follows the chain. The discrete area index, one-sided pause and
  slide/arc transition are not part of it.
- The procedural flank/rump point is the fallback when the area chain cannot build; it carries
  no sphere, so the placement engine keeps its exact point and path normal.
- The oval uses the standing radii and the old across/up axes. The palm fingers point forward
  (`-pony.global_basis.z`).

### Standing oral

- While `view.contact_kind == "mouth"`, the path selector returns `hands/paths/oral.gd` instead
  of the standing chain. `A`/`D` still toggle each hand, `Z`/`C` keep the oval and the five-second
  caress meter keeps scoring.
- The path holds one authored node per hand: the `head_side` area in `hands/areas/areas.json`,
  region `head`, mode `palm`, roll `1.0`. `hands/paths/anchors.gd:build_single_area()` fits one
  sphere through the nearest head coat vertex, so the node keeps the live head skin weights.
- The candidate is `exact`: the path's skinned coat point already is the contact, so the
  placement engine skips the sphere projection and the smoothing. No mesh query follows the head.
- There is no lean sample or chain, and no flank fallback. A missing `head_side` side or a point
  farther than `coat_fit.MAX_DISTANCE_M` from the head coat leaves that hand without a target and
  logs the miss; a flank contact during oral would be the wrong target.
- The oval travels fore/aft along the head tangent with the vertical as its other axis. The
  fingers point forward and the palm roll is `ORAL_PALM_ROLL_DEG = 24°` with the hand sign,
  mirroring the missionary roll convention.
- A hand that is already caressing when the contact switches to or from the mouth eases from its
  live `hand_frame()` onto the other path over `CARESS_ORAL_BLEND_S = 0.35 s`. A fresh `A`/`D`
  press starts directly on the current path, because the normal caress start already resets the
  hand.
- The side lookup is flipped: see the side convention below.

The two authored files use different points of view. `hands/areas/areas.json` is authored from
the mare's point of view (`left` is her left side), which the standing chain uses directly.
`hands/paths/anchors.json` is authored from Anon's point of view (`left` is his left hand on her
right side), and the missionary path uses it as exported. The oral path reads the opposite
`head_side` key because Anon faces her; the palm still receives Anon's `hand_side`.

`head_side` was authored in `sources/work/caress_paths.blend` (gitignored, not shipped or built)
from the `caress_head_L` / `caress_head_R` groups on the `Head` mesh, one vertex each. Blender
`(x, y, z)` maps to the game head rest space as `(-x, z, y)`.

## Palm holder

- Missionary uses `poses/missionary_anon.gd` as the palm holder. `set_hold_target()` /
  `clear_hold_target()` blend the hand off and back onto the mattress over 0.35 s. While held,
  the arm runs the game's regular desktop arm mode from the shoulder down.
- Standing uses the game's desktop pose driver through `set_hold_target(..., "rub")`.
- `shared/hands_scale.gd` applies the shared per-preset hand scale in the two base poses and restores the cached
  bone scales on every act exit.
- Both holders expose `hand_frame()` for the debug overlay.

## Contact engine

A path returns ordered candidates, preferred first. Each candidate carries:

```text
point, normal, oval_x, oval_y
center, radius          the fitted sphere the point was derived from; radius 0 means none
finger, mode, roll
region                  torso or head
exact                   the point is already on the coat; skip the sphere projection
u                       optional debug parameter
```

For one hand the engine:

1. applies the oval offset
   `point + oval_x * cos(phase) * across + oval_y * sin(phase) * up`;
2. an `exact` candidate skips the next two steps and builds the palm frame directly, because
   its point already is the skinned coat point;
3. projects the intended point radially onto the candidate's sphere,
   `center + normalize(intended - center) * radius`, and uses that radial direction as the contact
   normal: it is smooth at every point and needs no blur or mesh query;
4. low-passes the **sphere snap correction**, not the intended point, so the intended oval motion
   is never delayed or shrunk, and clamps the temporal normal turn;
5. builds the single-point palm frame with `hands/palm.gd`;
6. falls back to the last good target when the path is unavailable or the candidate is not finite.

A candidate without a sphere (`radius 0`, the procedural flank/rump fallback) keeps its exact
point and path normal.

## Coat fit

`hands/coat_fit.gd` is the only code that reads a coat mesh after the fit. Per authored area it
takes the nearest coat vertex, its normal and its skin influences, then scans the radius whose
centre `point - normal * r` best matches the coat within `FIT_RADIUS_M = 0.06 m`, keeping a flat
patch at the `MAX_RADIUS_M = 1 m` plane limit. The result is cached per skin and area, so a pony
fits each area once.

An authored area farther than `MAX_DISTANCE_M = 0.06 m` from its body is a miss. A winking body
(princesses, changelings, a borrowed form) first maps the authored mare point through the body rig
(`BODY_PROFILE.rig_for_pony`, falling back to the identity's character) about the rear anchor, and
may snap up to `REMAPPED_DISTANCE_M = 0.12 m`; the fit line reports that distance as `snap`. Head
areas are never rig-mapped: the loose heads are the shared native head.

## Settings

The caress declarations live in `settings/api.gd`, and each one's `##` comment describes its
row.

The service layers read their typed settings handles at use, including on the hot path; they keep
no snapshot and no hands cache. `hands/caress.gd`, `hands/reach.gd` and `hands/smack_target.gd`
resolve the values and fill the typed context; the placement engine and the paths receive the
resolved values and never read settings. The `caress_tick` / `caress_precise` perf rows are the
signal to improve `settings/api.gd`, not to add a hands cache.

The three smoothing values apply to the two base poses. `0` restores the exact behaviour. The caress
offsets are multiplied by `facts.same_height_scale` for the Same Height preset; the other
presets keep their authored values. `Palm hover`, the oval radii and the contact smoothing are the
contact knobs; the sphere fit itself is fixed and has no player row.

The marked area JSON also stores `mode` and `roll`. The lean-driven standing provider uses
`region` and keeps its existing palm frame and roll; the oral head path reads `mode` and `roll`
from `head_side`.

Standing point profiles (`CARESS_PROFILES`, metres before body scale): Canon `up 0.08`,
JRHNBR `up 0.16 / out 0.02`, Same Height `up 0.18 / out 0.03`, Hoers `up 0.20 / out 0.04`.
The rub centre is lifted `CARESS_UP_BIAS_M = 0.05` above the profile's `up` point.

## Debug and performance

- `features.caress_debug` logs one `precise caress` line per hand per act with `u`, target,
  normal, finger, roll, hover and the fitted radius, plus each path build's anchors and their
  world position/normal. `PORT.debug()` resolves the feature; the engine and paths receive it in
  their context.
- Every coat fit logs `caress fit mesh=… region=… r=… err=…mm snap=…mm`, and a failed area logs
  `caress area miss region=… rig=… authored=… mapped=…`. Both use the normal debug log switch, not
  the caress feature.
- `hands/debug_draw.gd` draws the path anchors, the exact contact, the palm target and the actual
  hand.
- `Print perf logs` reports `caress_tick`, `caress_precise`, `caress_path`, `caress_fit`,
  `caress_contact` and `caress_arm` chunks.
- `caress_tick` covers the controller and the background fit; `caress_precise` covers the path plus
  engine for one hand; `caress_path` covers a one-time path build, `caress_fit` the sphere fit it
  triggers, `caress_contact` the radial projection and the smoothing, `caress_arm` the missionary
  reach plan.
- The first act on a pony pays one fit per authored area, spread over the posing ticks; later acts
  reuse the cache, and a rig-mapped body reports its `snap` distances on that first build.

## Reach

`hands/reach.gd` owns the standing `Q`/`E` side lean hand. It uses the same palm holder as the
caress but a hull contact, blends from the current rest hand over 0.35 s, and blends back over
0.35 s. While held, the forced glance looks over that shoulder. Missionary has no shoulder reach.
A smack that takes the reach hand ends the reach and the lean action with it; the reach does not
fire again until the lean leaves the release band. The camera starts or holds the reach through
`hands/api.gd:set_reach()`, and releases it with the `NONE` side.

## Smack

`hands/smack_target.gd` chooses the hand and the pose-specific target; `hands/smack.gd` runs the
swing.

- The free hand is used while one hand caresses; a reaching hand is not free. With both hands
  busy one is picked at random. With neither busy the lean chooses a cheek.
- The picked hand's caress or reach ends before the swing, so the smack never resumes it; a fresh
  `A`/`D` press or a new side lean is needed.
- Standing targets the flank patch. The live caress point is used when the picked hand's contact
  source is `flank`; a free-hand smack queries the chosen cheek, offset by
  `smack.height_m` (signed) and `smack.hind_m`, then snaps
  to the nearest `FlankSurface` point and jitters within `smack_zone_radius`.
- Missionary keeps the decal-centre target shifted `0.08 m` up and `0.08 m` back.
- Every smack offset and the raise scale with the pony's body size.
- Standing runs raise -> strike -> contact -> recover. A hand on the coat (caressing or reaching)
  raises off it; a free-hand raise is a backswing from behind and below. The strike is cubic,
  CONTACT holds the exact frame for `0.03 s`, and RECOVER returns to the frame the swing started
  from.
- Missionary uses the hidden-hand `0.20 s` swing, impacting at phase `0.45`.
- A `200 ms` cooldown gates a new smack.
- The native `FlankTouch.impact` keeps its decal, blush and jiggle; the pony's game reaction
  signals are disconnected around the call.
- The pack hand-smack sound is installed immediately before impact and restored at act exit.

## Scoring hooks

- A held caress reports one `PORT.touch("caress")` per `CARESS_TOUCH_SECONDS = 5 s` of contact,
  not one per physics tick. A tap shorter than five seconds scores nothing.
- Caress uses the normal touch cooldown and the `ASSIST_CAP`; a disliked caress subtracts and
  briefly sets `overwhelmed`.
- The standing afterglow close window counts active caress time. 2.5 s or more of caress grants
  the full reward; after a bad act it repairs one point of history hurt.

## Verification / lab

`./lab.sh` is the manual pass: both base poses, standing oral, the shoulder reach, one smack, the
standing afterglow, a body swap and a live settings edit, with the mod off and on. With **Enable
debug** + **Print perf logs**, read one `perf` block in an act and one outside it and watch the
caress rows. The automated seams are the two hands suites, the camera suite and the act-audio
suite.

## Known limits

- The coat fit covers the body and head meshes (torso, neck, cheek). Hair, mane, wing and tail
  layers are not fitted; the standing `Ignore body parts` setting filters the smack's hull contact
  query only.
- One sphere per area is a local approximation: it follows the area's skinned point but not local
  skin deformation under it, and on a body the areas were not authored on, a snapped bead can sit
  several centimetres from the authored spot.
- The path builders cache per hand and pony; changing `path_id` rebuilds the next caress path.
- The oral head path has no fallback: a missing `head_side` side, an unbuilt head fit or a point
  beyond `coat_fit.MAX_DISTANCE_M` leaves that hand without a caress target for the turn. A flank
  contact during oral is deliberately not accepted.
- The exact oral node uses the authored coat normal directly, without the sphere projection.
- The area chain is lean-driven: W/S still leans and the hand follows the JSON chain. It does not
  add a discrete area index, a one-sided pause or the slide/arc transition.
- The area JSON is global for the shared body/head. A missing side or fewer than three buildable
  areas makes the area chain fail and the standing provider falls back to the procedural flank/rump
  point.
- The area chain fits one sphere per marked group at its representative point; it does not roam the
  whole region, and the oval remains the local stroke.
- The base-game hull, flank and JSON reads stay `Variant` at the query edge; each is parsed into a
  typed record immediately. `hands/api.gd` is the only outside import; new hand code uses the
  controller's modules, never a host read.
