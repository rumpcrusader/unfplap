# Scene gate contract

The live half of the act gate and the refusal executor. Eligibility policy answers whether an
adult mare *may*; this answers whether the *scene* is ready right now.

## Ownership

`scene_gate/service.gd` (RefCounted) owns:

- the scene-only gate rows: runtime state, paused tree, player conversation, sleep, an active act
  or aftercare, cuddle, affection, player readiness, navigator existence/reservation/owner/pose,
  the footstool supply for standing, the missionary pose asset and rig, and the bed rows;
- the bed search (`find_bed_under`, `resolve_bed`) and the bed gate;
- the player predicate: controls, flight, wing flight, knockdown, swimming, mouse capture, held
  item/case, seat and bed-side recline;
- the cuddle and affection predicates, and the live auto-cuddle suppression;
- the structural rows (`invalid_pony`, `no_main`, `no_player`, `no_game`), the policy/scene merge,
  `start_verdict` / `offer_verdict`, the debug status line and the reason list;
- the refusal executor: `refuse_available`, `refuse`, the buck/push, the refusal impression, the
  lost-trust hook and the refusal floor.

`runtime.gd` keeps the policy and the live context: it supplies `policy_verdict` (the
`eligibility/service.gd` verdict) and `debug_context` (the act values the status line reads) through
callbacks, and keeps the public forwards (`can_show_start`, `can_offer`, `offer_reasons`,
`refuse_available`, `refuse`, `find_bed_under`, `free_of_affection`, `cuddle_active`). The runtime
also owns the refusal face (`_start_upset("angry"|"annoyed")`); the facade calls back with the
buck flag.

The rows carry `ELIGIBILITY.Row` objects with the policy's own keys and reasons. The pure policy
never sees a bed, a navigator, a pose asset or the player body.

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
| `cuddle` | both | no active cuddle session, or the bed-side path / `allow_act_during_cuddle` |
| `affection` | both | no live `Affection.kind` and no active hoof hold |
| `player` | start | Anon is free, unseated where the pose requires, and beside the bed when seated |
| `navigator` | start | she has a `Navigator` |
| `navigator_reserved` | start | no `reserved_by` lease |
| `nav_owner` | both | the navigator owner is compatible with the pose/source |
| `nav_pose` | start | the pose is standable (standing) or the lying/cradle path is allowed |
| `stool` | both | the standing reach gap has enough footstools (provider callbacks) |
| `pose_asset` / `pose_rig` | both, missionary | the authored pose loaded and the rig has its bones |
| `bed` / `bed_occupied` / `bed_gate` | both / both / start | the bed resolves, is free, and the bed-side/cradle conditions hold |
| `standing_free` | offer, standing | she is not held and not seated |
| `pose` | offer, not standing | the pose is unsupported for an offer |

The footstool rule lives in the per-act handle `stool/act.gd` (`docs/stool.md`); the rows reach it
through the runtime's `stool_needed_count` / `stool_case_count` forwards. The pose rows reach the
pose session facade.

## Navigator owners

| Owner prefix | Verdict |
|---|---|
| empty | free |
| `unfplap:request:` | free while the runtime is `IDLE` |
| `sleep:` | only an awake `lie_down` pony in a bed, for `bed_side`/`already_lying` |
| `unfplap:` (other) | blocked |
| `weather:`, `show:` | blocked |
| `cuddle:`, `leisure:` | only a missionary bed-side/already-lying act |
| `social:` | only `social:talk` with a free player conversation |
| `life:`, `day:` | free only with no active route |
| `bond:`, `player:`, `rest_after_command` | free |

## Refusal

`refuse_available` requires the policy's `buck_refuse` plus a live scene: idle runtime, valid
pony/main/player/game, not sleeping/active/aftercare, free conversation and affection, an
unreserved navigator compatible with the pose, Anon not locked/flying/knocked down/cursor-lost,
an `Affection` with `buck()`, and the pose context (standing: free, grounded, standing and settled
within 2.4 m; cradle: held and cradled; already lying: lying and Anon beside the bed).

`refuse` runs the buck/push (or releases the carry/bed rest first), then `note_refusal`: one
`REFUSAL` impression with `angry` for a buck and `annoyed` for a turn-away, the game's
`bonds.unwanted_contact(id, "kiss")` trust hit, and the matching held face. The lasting feeling is
the impression; the face is presentation. A strict partner stop also calls the same buck/push.

`refusal_ready` / `mark_refusal` pace the spoken refusal line at one per 4 s, so a held or repeated
Y press does not queue a line per frame. The runtime owns the refusal line and its validity.

## Debug

`scene_gate.debug_line()` owns the status string: it reads the live act values through the
runtime's `debug_context` callback, the row/verdict assembly, and the policy row reads. The
runtime's `debug_line()` is a thin forward. No scene row is recomputed twice in different ways.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | eligibility | `eligibility/service.gd` | adult and consent gate |
| service | memory | `memory/service.gd` | act memory and witness pass |
| service | settings | `settings/service.gd` | settings declarations and live values |
| shared | pose_catalog | `shared/pose_catalog.gd` | pose ids and defaults |

## Lifecycle

- Scope: per-pony
- Constructed by: `runtime._init()`
- Begin: `bind()`/`configure()`
- End: act teardown
- Idempotent: yes


## Tests

`tests/scene_gate/test_scene_gate.gd` covers the conversation, cuddle, affection, navigator,
player, bed and row sets, the structural rows, the policy/scene merge, the start/offer verdicts,
the debug line, the reason list, the refusal executor and the auto-cuddle suppression with fake
scene nodes. `tests/eligibility/` keeps the pure policy suites. The runtime suite
(`tests/test_runtime_teardown.gd`) and the history stop suite drive the public forwards.
