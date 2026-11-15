# Afterglow and the standing close window

## Scope

`afterglow/service.gd` owns the held post-act phase: the private afterglow beat, the standing
close window with its caress reward, and the presentation row the phase asks for. It does not own
the `AFTERGLOW` state value, when the phase ends, the scene calls themselves or the memory commit.

The runtime still:

- sets `State.AFTERGLOW` and calls `begin()`;
- calls `close_tick()` from `_afterglow_tick()` after the anatomy afterglow tick;
- applies `presentation()` in the built order through `_apply_afterglow_presentation()`: the pose
  weight, tail target and flicks, HUD state, wings; then `_set_face`, `_act_face_beat` and the act
  summary;
- carries out the close reward: the `STAY_CLOSE` memory impression, the history repair, the
  content face, the heart burst and the cue clear;
- calls `cancel_close()` from `end_afterglow()` and `_restore_begin()`.

`afterglow/service.gd` is the facade and the only module another system calls. There is no private
`afterglow/` directory: the phase has no pure sub-module that is useful on its own.

## Architecture

| Piece | Owns |
|---|---|
| `afterglow/service.gd` | the private beat, the close-window timer and its reward decision |
| `runtime.gd` | the state transition, the phase end, the scene presentation, the memory/history writes and the HUD refresh |

Host callbacks, all optional so a test can build the facade without a runtime:

| Callback | Meaning |
|---|---|
| `log(text)` | debug log |
| `caress_active() -> bool` | the hand controller has an active caress |
| `on_stay_close(caressed, positive)` | the close window elapsed; the runtime presents the reward |

## Internal API

| Method | Meaning |
|---|---|
| `begin(pose_id, summary)` | start the phase, roll the private beat and open the close window the pose profile declares |
| `bind_view(view)` | carry the pose view whose `afterglow.close_window` decides that window |
| `presentation()` | the afterglow presentation row: tail target and flicks, HUD state and the wings flag; the act's current pose holds |
| `reset()` | clear every per-act value; the callbacks stay |
| `close_tick(delta)` | count caress time and run the window down |
| `cancel_close()` | drop the window without a reward |
| `hint()` | the close prompt, or the content line after the reward |

## Ending

Only the player ends the afterglow: holding the act key calls `runtime.end_afterglow()`, and a cancel on
the afterglow takes the same path. The pony never ends the phase herself and there is no end
timer, so the held moment lasts until the player leaves it. Leaving early cancels the standing
close window without its reward.

## Held pose

The afterglow holds the current pose: the pose the act ended in, unchanged. The presentation row
carries no pose mode and no afterglow pose id, and `_apply_afterglow_presentation()` only re-asserts
`target_amount`/`amount` alongside the tail, HUD and wings. The pose evaluator keeps its current
driver/delta pair and config; nothing rebuilds, releases or re-poses the body at the phase change.
The close window comes from the view's `afterglow.close_window`. The phase has no `pose_changed`
hook. The runtime and facade source must not name a pose mode.

## `[stay]` action

The mod's afterglow note does not advertise `[stay: SECONDS]`. The base game's ordinary
hold-position action is unchanged, and the afterglow facade does not bind the game's action
executor, so that action does not control the phase.

## Close window

- The pose row's `afterglow.close_window` opens it: standing declares it, missionary does not.
  `begin()` sets `close_left = STAY_CLOSE_SECONDS` (8 s) when the profile opens the window.
- `close_tick()` adds to `close_caress_seconds` while the hand controller has an active caress and
  subtracts the same delta from `close_left`.
- At zero the window grants exactly one reward. `close_caress_earned` is true only with at least
  `STAY_CLOSE_CARESS_SECONDS` (2.5 s) of caress. `on_stay_close()` receives both the caress result
  and whether the act summary was positive; the runtime writes the memory and history effect.
- `hint()` is `Stay close · Ns · caress` while the window runs and `She seems content.` after the
  reward. An early end calls `cancel_close()`, which never rewards.
- `hud_y_pink()` still reads the earned flag to turn the control card's `End` fully pink.

## Player afterglow

Hold the act key:

| State | Climaxes | Result |
|---|---:|---|
| `POSING_IN` | any | cancel |
| `ACTIVE` | 0 | cancel / early stop |
| `ACTIVE` | 1+ | afterglow |
| `CLIMAX` | 1+ | afterglow |
| `AFTERGLOW` | any | end afterglow |

- The player cannot enter afterglow before the first pony climax.
- One or more climaxes allows afterglow at any time.
- A non-zero configured climax limit forces afterglow after that climax's 5 s effect.
- Pegasi and alicorns slowly fold their wings back to rest during afterglow over 6 s rather than
  holding the spread pose until the act ends.
- Normal dialogue resumes in the afterglow. The `inside` and `stay_close` generated lines are
  removed; the HUD timer and active caress time own the standing close invitation. The live prompt
  note keeps the moment present without a scripted line: it carries one short random afterglow beat
  (`ACT_SUMMARY.afterglow_beat()`, 40 % silence) and the private relationship note; the HUD and the
  impression keep the full summary. The note does not recite the summary or append a mechanical
  “next time” wish.
- The afterglow lasts until the player holds the act key to end it; she never ends it herself. The
  live prompt note tells her whether Anon is caressing her or leaning in; leaning counts as staying
  close/hugging. A quiet moment adds no state sentence.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|

## Lifecycle

- Scope: per-act
- Constructed by: `runtime._init()`
- Begin: `begin()`
- End: `reset()`
- Idempotent: yes


## Tests

`tests/afterglow/test_afterglow.gd` builds the facade with fake callbacks and covers the close
window's timing, caress count and single reward, the early cancel, the missionary skip, the
presentation row (no pose mode/afterglow pose, the held pose and the re-asserted weight) and the
runtime forwards for the HUD and prompt note. Wing folding lives in
`poses/wing_control.gd` and is covered in the same suite; the wing controller reads the typed act
view (`facts.pony`, `facts.clock()`) and a `log` callback, never the runtime node.
