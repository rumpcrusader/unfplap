# Scene gate contract

The live half of the act gate. Eligibility policy answers whether an adult mare *may*; this answers
whether the *scene* is ready right now.

## Ownership

`scene_gate/service.gd` (RefCounted) owns:

- the scene-only gate rows: runtime state, paused tree, player conversation, sleep, an active act
  or aftercare, cuddle, affection, the pose profile/form/view/source, player readiness, navigator
  existence/reservation/owner/pose, the footstool supply for a `scene.stool` pose, the bed pose
  asset and rig, and the bed rows;
- the bed search (`find_bed_under`, `resolve_bed`) and the bed gate;
- the player predicate: controls, flight, wing flight, knockdown, swimming, mouse capture, held
  item/case, seat and bed-side recline;
- the cuddle and affection predicates, and the live auto-cuddle suppression;
- the structural rows (`invalid_pony`, `no_world` — the missing game root — `no_player`,
  `no_game`), the policy/scene merge, `start_verdict` / `offer_verdict`, the debug status line and
  the reason list;
- the act key's readiness (`hotkey_ready`), the small checks it composes and the policy verdict read
  (`policy_verdict_for`);
- the running verdict (`running_verdict()`), a `RunningVerdict` the act session applies through
  the one stop;
- the physical buck/push (`buck_or_push`), which the tolerance strict stop uses.

`runtime.scene` is the offer-facing scene handle; `runtime.start` carries the hotkey/Agreement
starts and the footstool hint, and `runtime.presentation` the stool and standing-presentation
reads. The live scene context comes through the gate's `debug_context` callback, bound by
`act/build.gd` to `runtime.act.debug_context()`: that gathers `debug/pony.gd`'s pony, world,
relationship and player facts and adds the session's act values. The scene handle exposes
`find_bed_under`, `free_of_affection`, `cuddle_active`, `hotkey_ready`, the small checks
(`available`, `pose_supported`, `player_ready`, `navigator_allows`, `posture_allows`,
`agreement_ready`) and the scene-only verdict; the stool pair, hint and Agreement start are the
other two handles. The gate reads
`PONIES.eligibility` itself for the policy verdict; a suite may still override
`policy_verdict`. The tolerance stop owns its impression and face (`docs/summary.md`,
`docs/face.md`).

The rows carry `ELIGIBILITY.Row` objects with the policy's own keys and reasons. The pure policy
never sees a bed, a navigator, a pose asset or the player body. The merge answers a typed
`GateVerdict`: `policy` is the snapshot, `rows` every row, and `show()` / `offer_ok()` the start
and proactive-offer answers. `bind()` takes the typed pose session and `configure()` the act's
typed feature snapshot.

The pose half reads `shared/pose_specs.gd`, never a pose-id comparison: `scene()` gives the frame,
`requires_bed`, `stool`, `standing_free` and the authored act sources; `is_public()` and
`is_offerable()` decide whether the mode may see the pose at all; `forms`/`views` are checked
against `PLAYER_FORM.active()` and the headset view. An unknown or internal pose fails
`pose_profile`; an offer of a non-offerable pose also fails `pose`. The gate fails closed.

`start_verdict()` and `offer_verdict()` accept a `verdict_in` policy snapshot. The idle hint never
runs them: it reads the small checks below, builds no `Row` objects and reads Base clearance only
after the scene passes. The act key and the hint share `hotkey_ready()`; the matrix suite pins it
equal to `scene_only_verdict().ok`. `scene_only_verdict()` remains the accepted-Agreement start and
the debug read: it takes the footstool pair the host read for this call as an optional
`stool_need`/`stool_have`, where `-1` reads the live provider callbacks. The blocked standing hint
reads the same pair through the stool handle's `hint_pair()`; it never reruns a gate. An accepted
proactive offer starts through its Agreement's scene-only rows; the request handoff only changes
hint discovery (`docs/initiation.md`).

## Row sets

A `start` gate adds the final scene rows; an `offer` gate uses the offer-safe subset. `forced`
(the Debug offer bypass) skips the paused row only.

| Row | Mode | Passes when |
|---|---|---|
| `state` | both | the runtime is `IDLE` |
| `paused` | both | the tree is not paused, or the offer is forced |
| `conversation` | both | no conversation target, or the target is Anon's rig/body |
| `sleeping` | both | she is not sleeping |
| `sex_active` | both | no `sex_active` meta |
| `aftercare` | both | no `sex_aftercare` meta |
| `cuddle` | both | no active cuddle session, or the act starts through it |
| `affection` | both | no live `Affection.kind` and no active hoof hold |
| `pose_profile` | both | the pose has a public spec row with a scene frame |
| `pose_form` | both | the player's live form is in the pose's `forms` |
| `pose_view` | both | the live display is in the pose's `views` |
| `pose_source` | both | the act source is in the pose's authored `scene.sources` (or the list is empty) |
| `player` | start | Anon is free, unseated where the pose requires, and beside the bed when seated |
| `navigator` | start | she has a `Navigator` |
| `navigator_reserved` | start | no `reserved_by` lease |
| `nav_owner` | both | the navigator owner is compatible with the pose/source |
| `nav_pose` | start | the pose is standable (standing) or the lying/cradle path is allowed |
| `stool` | both | a `scene.stool` pose has enough footstools (provider callbacks, or the runtime's pair for this call) |
| `pose_asset` / `pose_rig` | both, bed or ground pose | the authored pose loaded and the rig has its bones |
| `bed` / `bed_occupied` / `bed_gate` | both / both / start | a `scene.requires_bed` pose resolves a free bed and the bed-side/cradle conditions hold |
| `standing_free` | offer, standing | she is not held and not seated |
| `pose` | offer, not offerable | the pose is internal or unknown, so it cannot be offered |

The footstool rule lives in the per-act handle `stool/act.gd` (`docs/stool.md`); the rows reach it
through the host's `stool_needed_count` / `stool_case_count` forwards, and the hotkey pair comes
from the handle's `hotkey_pair()`. The pose rows reach the pose session facade. `pose_asset` and
`pose_rig` are emitted for a bed pose and for a ground pose: the candidate's own `asset` is resolved
through its `base` chain, and a missing or frame-mismatched asset refuses the start. The ground
family has no procedural fallback.

## Small checks

`hotkey_ready(pose, source, bed, stool_pair)` is the hint's and the act key's readiness. It calls
the same helpers as the rows, in this order, and never allocates a row:

| Check | Rows it answers |
|---|---|
| `available()` | the structural handles, `state`, `paused`, `conversation`, `sleeping`, `sex_active`, `cuddle`, `affection` |
| `pose_supported(pose, source)` | `pose_profile`, `pose_source`, `pose_asset`, `pose_rig` |
| `player_ready(pose, source, bed)` | `player`, `bed`, `bed_occupied`, `bed_gate` |
| `navigator_allows(pose, source)` | `navigator`, `navigator_reserved`, `nav_owner` |
| `posture_allows(pose)` | `nav_pose`, `standing_free` |
| the stool pair | `stool` |

`hotkey_ready()` then reads Base clearance: `eligible(pony, Target.ACT)` and
`relationship_ok(pony)`. `agreement_ready(pose, source, bed, FrozenPose)` is the same scene
composition for a formed Agreement: the frozen profile and source rows instead of the live pose
support, and no clearance read. Its caller is the Negotiation service's `ready_offer()`.

## Pose options and placement

The negotiation routes build their offerable list with the pure `shared/pose_options.gd`: the
capability row (`pose_specs`) plus one plain `Placement` record (cuddle and the bed under her, a
free bed and its front spot, a free standing approach) produce a typed `Array[Option]` of
`(pose, source, bed)`. Only offerable, public, form/view-supported options with an authored source
are returned; an empty list means no offer and no reasoning. The active offer owns the bed handle
it carries.

`shared/pose_placement.gd` answers the live feasibility of one chosen option from plain facts
(`bed_known`, `bed_front_known`, `standing_free`, `stool_ok`, `player_ready`) and never reads the
scene. The scene gate remains the single owner of the live rows and the start verdict; the module
is the shared vocabulary the answer transition and the route checks use to name a failure, not a
second gate.

### Bed size

The stock bed admits a guest through `SharedBed.eligible()`, which measures her own `body_scale`
with `scale_fits()`: her barrel beside Anon must sit inside the mattress width and her whole length
inside its length. Anon's half of the lane and his head/sit offsets scale with
`Settings.anon_height_scale()`; hers scale with her own body. A bed too short for a Hoers or Same
Height mare is refused. This is stock behaviour, not a mod override, and the `bed` / `bed_gate`
rows report it.

## Scene-only start

`scene_only_verdict(pose, source, bed, FrozenPose)` is the accepted-Agreement start. It does not
build a policy verdict: Base clearance and the pose capability were frozen at formation, so the
gate runs only the live world rows. `FrozenPose` carries `pose_profile_ok` and `pose_source_ok`
from the Agreement; the form and view are applied by the act with the frozen pair and are not
start rows. `aftercare` is removed; the Act service clears it at start. `SceneVerdict` reports
`hard_ok` (every non-transient row), `transient_ok`, `ok`, the typed `rows`, the failing
`transient` keys and every failed reason.

| Row | Scene-only start |
|---|---|
| `state` | live |
| `paused` | live |
| `conversation` | live |
| `sleeping` | live |
| `sex_active` | live |
| `aftercare` | removed; the Act service clears it |
| `cuddle` | live |
| `affection` | live; the negotiation hold is exempt |
| `pose_profile` | frozen from the Agreement |
| `pose_source` | frozen from the Agreement |
| `pose_form` | dropped; the frozen form is applied |
| `pose_view` | dropped; the frozen view is applied |
| `player` | live, **transient** |
| `navigator` | live |
| `navigator_reserved` | live; the hold uses `command_owner`, so `reserved_by` still blocks |
| `nav_owner` | live; the negotiation hold token is accepted |
| `nav_pose` | live; the negotiation hold is exempt |
| `stool` | live |
| `pose_asset` | live technical |
| `pose_rig` | live technical |
| `bed` | live |
| `bed_occupied` | live |
| `bed_gate` | live, **transient** |
| `standing_free` | live |
| `pose` | formation-only; not a start row |

The host binds `hold_compatible(pose, source) -> bool`; it is true only while the navigator owner
and the affection hold belong to the live negotiation hold. A hard failure is a `StartFailed`; a
failing transient row is waited on within the Agreement TTL. `runtime.start.start_agreement(handle)`
consumes this verdict; the act key's general path still runs `start_verdict()`.

`running_verdict(nav, bed, player_pony, kissing)` is the live act's periodic check. It returns a
`RunningVerdict` with `ok` and a typed `reason`; the session applies a failed verdict through the
one stop. It never rereads the start rows or the policy.

## Navigator owners

| Owner prefix | Verdict |
|---|---|
| empty | free |
| `unfplap:request:` | free while the runtime is `IDLE` |
| `sleep:` | only an awake `lie_down` pony in a bed, for `bed_side`/`already_lying` |
| `unfplap:` (other) | blocked |
| `weather:`, `show:` | blocked |
| `cuddle:`, `leisure:` | only a bed pose with an authored bed source |
| `social:` | only `social:talk` with a free player conversation |
| `life:`, `day:` | free only with no active route |
| `bond:`, `player:`, `rest_after_command` | free |

## Standing offer hint

The free-standing act-key hint is discovered by `offer/service.gd` through
`PONIES.cone_target()`: a 90 degree half-angle fan to each side of her backward axis, within 2 m of
an approximate rump anchor (`shared/rump_cone.gd`). It is a discovery rule for the idle hint, not a
scene-gate row; the hotkey and the Agreement start keep their own scene checks.

## Buck and push

`buck_or_push()` asks her `Affection` to buck; when that is unavailable or fails, it starts a
knockdown push on Anon. It returns whether either ran. It is the physical stop the tolerance strict
stop uses; the impression and the held face belong to `docs/summary.md` and `docs/face.md`. The
live act key never bucks, and no eligibility verdict carries a refusal.

## Debug

`scene_gate.debug_line()` owns the status string: it reads the live values through the
`debug_context` callback (`debug/pony.gd`'s gather plus the runtime's act values), the
row/verdict assembly, and the policy row reads. The offer handle's `debug_line()` is a thin forward. No
scene row is recomputed twice in different ways.

## Dependencies

### Uses
| service | world | `world/service.gd` | beds, occupancy and the player body |

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | eligibility | `eligibility/service.gd` | adult and consent gate |
| host | runtime | `bind(pony, pose, eligibility)` | the live eligibility service for the hotkey readiness |
| service | poses | `poses/service.gd` | pose and skeleton |
| service | settings | `settings/service.gd` | settings declarations and live values |
| service | world | `world/game.gd` | service dependency |
| shared | act_state | `shared/act_state.gd` | act state constants |
| shared | pose_specs | `shared/pose_specs.gd` | scene block, support lists and offerability |

## Lifecycle

- Scope: per-pony
- Constructed by: `act/build.gd` through `runtime._init()`
- Begin: `bind()`/`configure()`
- End: act teardown
- Idempotent: yes


## Tests

`tests/scene_gate/test_scene_gate.gd` covers the conversation, cuddle, affection, navigator,
player, bed and row sets, the structural rows, the policy/scene merge (including a supplied
`verdict_in` snapshot), the start/offer verdicts, the scene-only verdict (the aftercare removal,
the frozen pose rows, the hold exemption and the transient/hard split), the small checks and the
matrix that pins `hotkey_ready()` equal to `scene_only_verdict().ok`, the debug line, the reason
list, the buck/push and the auto-cuddle suppression with fake scene nodes.
`tests/eligibility/` keeps the pure policy suites. The runtime suite
(`tests/test_runtime_teardown.gd`) and the stool suite (`tests/stool/test_gate.gd`) drive the
public forwards and the gate's hotkey readiness; the history stop suite drives the history row.
