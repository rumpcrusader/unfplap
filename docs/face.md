# Act face and the held post-act mood face

## Scope

`face/service.gd` owns the act's one face: the beat table driven by the pure `shared/act_face.gd`, the
line-face ownership rule, the stare release, the eyelids, the smile and its hold timer, the climax
quality shape, the held post-act mood face node and the warm prompt note. It does not own the
runtime state, the blush, the kiss, the HUD or the summary grade.

The runtime still:

- gathers the act values for `_act_face_beat()` (state, first-time flag, tolerance, climax mode,
  summary), `_act_face_rows()`, `_read_first_time()` and `_climax_quality_inputs()`;
- calls `_act_face_beat()` at the start, close, warning, climax, afterglow and stop moments;
- calls `_start_post_act_face()` from `_begin_aftercare()` and `_start_upset()` from a stop or
  refusal;
- calls `_eyes_tick()` late in the tick and `_set_face()`/`_clear_face()` at the transitions;
- forwards the face values to `_act_presentation()`.

`face/service.gd` is the facade and the only module another system calls. There is no private
`face/` directory: `shared/act_face.gd` stays pure and `face/mood_face.gd` stays the held-face node.

## Architecture

| Piece | Owns |
|---|---|
| `face/service.gd` | the act face, the line-face owner, the stare release, the lids and smile with their timer, the climax quality shape, the mood-face lifetime and the warm note |
| `shared/act_face.gd` | pure: beat plans, climax style, blush, summary faces, prompt hints |
| `face/mood_face.gd` | the 300 s held base-game face, its own `finished` signal and its blush |
| `runtime.gd` | the state, the scene reads, the blush, the kiss, the HUD and the summary grade |

Host callbacks, all optional so a test can build the facade without a runtime:

| Callback | Meaning |
|---|---|
| `log(text)` | debug log |
| `clock() -> float` | the runtime's act clock (`_now_s()`) |

The facade also binds `pony` and `host` once. `bind()` is called from `_ready`; a suite that builds
a runtime without entering the tree calls `_bind_face()` on the first facade call.

## Internal API

| Method | Meaning |
|---|---|
| `bind(pony, host)` | bind the pony and the runtime node that parents the mood face and the hold timer |
| `beat(moment, context)` | run the beat table for one moment; `context` carries `enabled`, `debug`, `first_time`, `tolerance`, and `climax_mode`/`quality` or `summary` |
| `act_beat(moment, context, enabled, debug)` | the runtime's beat call: applies the `act_faces` gate and the debug flag, then the beat table |
| `set_face(smile, lids, hold_seconds)` | write the act's smile and lids; a hold starts the face timer |
| `clear_face()` | stop the hold, release the stare and release the act's touch layer |
| `eyes_tick(context)` | the late lid owner; `context` carries `state`, `close_rewarded` and `eyes_active` |
| `climax_quality(context)` | the climax presentation score shape; the runtime gathers the counters |
| `set_act_face(face, hold_s)` | set one face unless a spoken line owns it; returns whether it applied |
| `end_face()` | clear only the face this owner set; a spoken line face is never cleared |
| `dialogue_face()` | the face a director line currently owns, or empty |
| `sync_settings(enabled, debug)` | apply the live feature flags; turning act faces off ends the act's face |
| `force_face(face)` | debug preview: set one face for 3 s |
| `rows(context)` | the act-face rows in Show data's ACT section |
| `start_post_act(context)` | start the held post-act face from the summary or the satisfaction |
| `start_mood_face(mood, face, blush, warm)` | start or replace the held face |
| `end_mood_face()` | free the held face and clear the warm note |
| `start_upset(mood)` | the refusal face |
| `end_upset()` / `end_satisfied()` | compatibility aliases for `end_mood_face()` |
| `shutdown()` | free the held face and clear the act face when the runtime leaves the tree |

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

The plan is `act_face.plan_for(moment, context)`; an empty plan does nothing. A face with a hold
calls `finish_dialogue(hold_s)`. A climax with `release_stare` sets `stare_release_until` to
`clock() + hold + 0.9`.

## Line-face ownership

- `set_act_face()` refuses while `dialogue_face()` is non-empty and not the face the act set. The
  runtime's `_set_act_face()` and `_end_act_face()` are the same call; the `end_face()` rule only
  clears the face the act set, so a director line survives teardown.
- `_act_face_beat()` is the only place the runtime writes a beat. It gathers the act values and
  calls `act_beat()`, which reads `_feature("act_faces")`/`_feature("face_debug")`, sets
  `debug_enabled` and returns before the beat table when act faces are off.
- `sync_settings()` ends the act face when `act_faces` is off; the post-act mood face stays
  independent.

## Stare and blush

`eyes_tick()` releases the stare while `stare_release_until` is in the future or while a kiss is
active, then reasserts the state's lids: half-lidded through `POSING_IN`/`ACTIVE`, wide at
`CLIMAX`, sleepier in `AFTERGLOW` and sleepier again when the close window was rewarded. The lid
values are the facade's constants; the runtime passes the state and the flags. `_set_face()` and
`_act_presentation()` own the smile and the blush; `blush_for()` is in `shared/act_face.gd` and reads
`_act_phase()`.

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

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | settings | `settings/service.gd` | settings declarations and live values |
| shared | act_face | `shared/act_face.gd` | face beat data |
| shared | preferences | `shared/preferences.gd` | profile math and defaults |

## Lifecycle

- Scope: per-act
- Constructed by: `runtime._init()`
- Begin: `bind()`
- End: `shutdown()`
- Idempotent: yes


## Tests

`tests/face/test_runtime_face.gd` covers the beat table, the line-face owner, the stare release,
the lids and the smile hold, the climax quality shape, the mood face and the warm note with a fake
expressions node. `tests/face/test_act_face.gd` covers the pure plans and
`tests/face/test_mood_face.gd` covers the held node.
