# Act face and the held post-act mood face

## Scope

`face/service.gd` owns the act's one face: the beat table driven by the pure `shared/act_face.gd`, the
line-face ownership rule, the stare release, the eyelids, the smile and its hold timer, the climax
quality shape, the held post-act mood face node and the warm prompt note. It does not own the
runtime state, the blush, the kiss, the HUD or the summary grade.

`act/view.gd` gathers the act values for `act_beat_for()` (state, first-time flag, tolerance,
climax mode, summary, blush flag) and `act_rows()`, and the climax shape from the readiness meter
(`quality_for()`). `act/session.gd` calls `face_beat()` at the start, close, warning, climax,
afterglow and stop moments; the runtime calls `eyes_for()` late in the tick, and the start and exit
ledgers call `set_face()`/`clear_face()`/`end_face()` at the transitions. The aftercare's
`start_post_act()` and the upset face are the ledgers' calls.

`face/service.gd` is the facade and the only module another system calls. `shared/face_beat.gd` holds the
typed beat context and its plan, summary and climax-quality records; `shared/act_face.gd` stays
pure and `face/mood_face.gd` stays the held-face node. The expression table is the caller's:
`act_face` validates every name against the `line_faces` it is handed, and the Face view supplies
it.

## Architecture

| Piece | Owns |
|---|---|
| `face/service.gd` | the act face, the line-face owner, the stare release, the lids and smile with their timer, the climax quality shape, the mood-face lifetime and the warm note |
| `shared/face_beat.gd` | the typed beat context, the plan parser and the summary and climax-quality records |
| `shared/act_face.gd` | pure: beat plans, climax style, blush, summary faces, prompt hints |
| `face/mood_face.gd` | the 300 s held base-game face, its own `finished` signal and its blush |
| `act/session.gd` | the act state and values the beats read |
| `runtime.gd` | the Node host: it binds the face once and owns the node that parents the mood face and the hold timer |

Host callbacks, all optional so a test can build the facade without a runtime:

| Callback | Meaning |
|---|---|
| `log(text)` | debug log |
| `clock() -> float` | the runtime's act clock (`_now_s()`) |

The facade also binds `pony` and `host` once. `bind()` is called from `_ready`; a suite that builds
a runtime without entering the tree calls `ensure_bound()` on its first facade call.

## Beat table

| Moment | Face | Hold |
|---|---|---|
| start, first time | `shy` | 2.5 s |
| start, repeat | `relaxed` | 2.5 s |
| readiness reaches 65 | `anticipation` | 3 s |
| climax, `fluster` | `shy` + `fluster(5.0)` | 5 s |
| climax, `ooo` | `ooo` | 5 s |
| climax, `wide` | none | — |
| afterglow, positive | `affectionate` | 3 s |
| afterglow, neutral non-early | `relaxed` | 3 s |
| afterglow, bad | `sad`/`annoyed` | 3 s |
| warning / overwhelmed | `sad` for forgiving, else `annoyed` | 3 s / 2.5 s |

The plan is `act_face.plan_for(moment, context, line_faces)`; an empty plan does nothing. A face
with a hold calls `finish_dialogue(hold_s)`. A climax with `release_stare` sets
`stare_release_until` to `clock() + hold + 0.9`.

## Line-face ownership

- `set_act_face()` refuses while `dialogue_face()` is non-empty and not the face the act set. The
  session's `set_face()`/`end_act_face()` are the same call; the `end_face()` rule only clears the
  face the act set, so a director line survives teardown.
- `face_beat()` is the only place the session writes a beat. It gathers the act values and
  calls `act_beat()`, which reads `_feature("face_debug")`, sets `debug_enabled` and runs the beat
  table. The post-act mood face stays independent.

## Stare and blush

`eyes_tick()` releases the stare while `stare_release_until` is in the future or while a kiss is
active, then reasserts the state's lids: half-lidded through `POSING_IN`/`ACTIVE`, wide at
`CLIMAX`, sleepier in `AFTERGLOW` and sleepier again when the close window was rewarded. The lid
values are the facade's constants; the session passes the state and the flags. `set_face()` and
the act view own the smile and the blush; `blush_for()` is in `shared/act_face.gd` and reads
`act_phase()`.

## Post-act mood face

`start_post_act()` starts the held face only when the act is not a stop and the host is in the
tree. A positive or non-early neutral summary uses `ACT_FACE.face_for_summary_hold()` and a
`0.35` blush when `summary.reward` is true and the final satisfaction is at least
`aftercare_min`. A face with no summary uses `relaxed` when the satisfaction reaches the minimum.
The mood face node is `face/mood_face.gd`; the facade owns its `finished` signal, the `warm_note` flag
and the `_left`/`face`/`mood` reads for the debug row.

`start_upset()` starts the same node with the refusal face and no blush. `end_mood_face()` calls
`_finish("replaced")` and clears the warm note. A new act clears the held face. The node receives
the main handle and the `log` callback from the facade; it never reads the runtime node.
