# Act face and the held post-act mood face

## Scope

`face/service.gd` owns the act's one face: the beat table driven by the pure `shared/act_face.gd`, the
line-face ownership rule, the stare release, the eyelids, the smile and its hold timer, the climax
quality shape, the held post-act mood face node and the warm prompt note. It does not own the
runtime state, the blush, the kiss, the HUD or the summary grade.

`act/session.gd` still:

- gathers the act values for `face_beat()` (state, first-time flag, tolerance, climax mode,
  summary), `act_face_rows()` (state, HUD mood, the game's cue mood, climax mode and the blush
  flag), the first-time read and the climax quality inputs;
- calls `face_beat()` at the start, close, warning, climax, afterglow and stop moments;
- calls `_face.start_post_act()` from the exit's aftercare when it starts, and starts the upset
  face from a stop or refusal;
- calls `eyes_tick()` late in the tick and `set_face()`/`clear_face()` at the transitions;
- forwards the face values into the act view.

`face/service.gd` is the facade and the only module another system calls. There is no private
`face/` directory: `shared/act_face.gd` stays pure and `face/mood_face.gd` stays the held-face node.

## Architecture

| Piece | Owns |
|---|---|
| `face/service.gd` | the act face, the line-face owner, the stare release, the lids and smile with their timer, the climax quality shape, the mood-face lifetime and the warm note |
| `shared/act_face.gd` | pure: beat plans, climax style, blush, summary faces, prompt hints |
| `face/mood_face.gd` | the 300 s held base-game face, its own `finished` signal and its blush |
| `runtime.gd` | the state, the scene reads, the blush, the kiss, the HUD wiring and the summary grade |

Host callbacks, all optional so a test can build the facade without a runtime:

| Callback | Meaning |
|---|---|
| `log(text)` | debug log |
| `clock() -> float` | the runtime's act clock (`_now_s()`) |

The facade also binds `pony` and `host` once. `bind()` is called from `_ready`; a suite that builds
a runtime without entering the tree calls `act/session.gd:bind_face()` on the first facade call.

## Internal API

| Method | Meaning |
|---|---|
| `bind(pony, host)` | bind the pony and the runtime node that parents the mood face and the hold timer |
| `beat(moment, context)` | run the beat table for one moment; `context` carries `first_time`, `tolerance`, and `climax_mode`/`quality` or `summary` |
| `act_beat(moment, context, debug)` | the runtime's beat call: applies the debug flag, then the beat table |
| `set_face(smile, lids, hold_seconds)` | write the act's smile and lids; a hold starts the face timer |
| `clear_face()` | stop the hold, release the stare and release the act's touch layer |
| `eyes_tick(context)` | the late lid owner; `context` carries `state`, `close_rewarded` and `eyes_active` |
| `climax_quality(context)` | the climax presentation score shape; the runtime gathers the counters |
| `set_act_face(face, hold_s)` | set one face unless a spoken line owns it; returns whether it applied |
| `end_face()` | clear only the face this owner set; a spoken line face is never cleared |
| `dialogue_face()` | the face a director line currently owns, or empty |
| `sync_settings(debug)` | apply the live debug flag |
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

## Dependencies

### Uses
| service | world | `world/service.gd` | the world root |

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | settings | `settings/service.gd` | settings declarations and live values |
| shared | act_state | `shared/act_state.gd` | act state constants |
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
expressions node. `tests/face/test_act_face.gd` covers the pure plans and the held mood-face node.
