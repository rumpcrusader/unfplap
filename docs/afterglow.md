# Afterglow and the standing close window

## Scope

`afterglow.gd` owns the held post-act phase: how long it lasts before she may end it, the game's
`[stay: SECONDS]` hold, and the standing close window with its caress reward. It does not own the
`AFTERGLOW` state value, the wings, the pose, the tail, the HUD or the memory commit.

The runtime still:

- sets `State.AFTERGLOW` and calls `begin()`;
- calls `advance()`, `self_end_tick()` and `close_tick()` from `_afterglow_tick()` in that order,
  with the anatomy afterglow tick between the first two;
- presents the phase: `_set_face`, wing begin, pose/tail amounts, `_act_face_beat("afterglow")`,
  the HUD state and the act summary;
- carries out the close reward: the `STAY_CLOSE` memory impression, the history repair, the
  content face, the heart burst and the cue clear;
- calls `cancel_close()` from `end_afterglow()` and `_restore_begin()`.

`afterglow.gd` is the facade and the only module another system calls. There is no private
`afterglow/` directory: the phase has no pure sub-module that is useful on its own.

## Architecture

| Piece | Owns |
|---|---|
| `afterglow.gd` | the phase timers, the self-end roll, the `[stay]` hold, the close window and its reward decision |
| `runtime.gd` | the state transition, the scene presentation, the memory/history writes and the HUD refresh |

Host callbacks, all optional so a test can build the facade without a runtime:

| Callback | Meaning |
|---|---|
| `log(text)` | debug log |
| `clock() -> float` | the runtime's act clock (`_now_s()`) |
| `in_phase() -> bool` | true while the runtime is in `AFTERGLOW` |
| `speech_busy() -> bool` | true while a director line is speaking |
| `player_close() -> bool` | caressing or leaning in close |
| `caress_active() -> bool` | the hand controller has an active caress |
| `on_end()` | the self-end roll chose to end; the runtime leaves afterglow |
| `on_stay_close(caressed, positive)` | the close window elapsed; the runtime presents the reward |

## Internal API

| Method | Meaning |
|---|---|
| `begin(pose_id, summary)` | start the phase, roll the private beat and open the standing close window |
| `reset()` | clear every per-act value; the executor and callbacks stay |
| `advance(delta)` | add to the elapsed time |
| `self_end_tick(delta)` | one self-end roll |
| `bind_action_executor(director, pony_id)` | find the game's action executor once and listen for `outcome` |
| `receive_action(event)` | the executor's `outcome` hook; only an accepted `stay` matters |
| `close_tick(delta)` | count caress time and run the standing window down |
| `cancel_close()` | drop the window without a reward |
| `hint()` | the close prompt, or the content line after the reward |
| `self_end_chance(close)` | static; holding her lowers the chance |

## Self-end

- The roll starts after `SELF_END_SECONDS` (16 s) and is checked once per `SELF_END_CHECK_S`
  (1 s). An accepted `[stay]` moves `hold_until` forward and pauses it.
- A speaking director defers the roll. Caressing or leaning in lowers the chance from `0.30` to
  `0.12`; it never removes it.
- The roll only calls `on_end()`. `self_end_tick()` never changes the runtime state itself.

## `[stay]` hold

- `bind_action_executor()` reads the director's `actions.executors[pony_id]` once and keeps it
  across acts while it is inside the tree.
- `receive_action()` ignores everything unless the runtime is still in the afterglow and the event
  is `type=stay`, `status=accepted`. The duration comes from the executor's `movement.duration_s`,
  clamped to `0.5…600 s`, and extends `hold_until` instead of replacing an earlier hold.

## Close window

- Only the standing afterglow opens it; `begin()` sets `close_left = STAY_CLOSE_SECONDS` (8 s) for
  `standing` and zero for `missionary`.
- `close_tick()` adds to `close_caress_seconds` while the hand controller has an active caress and
  subtracts the same delta from `close_left`.
- At zero the window grants exactly one reward. `close_caress_earned` is true only with at least
  `STAY_CLOSE_CARESS_SECONDS` (2.5 s) of caress. `on_stay_close()` receives both the caress result
  and whether the act summary was positive; the runtime writes the memory and history effect.
- `hint()` is `Stay close · Ns · caress` while the window runs and `She seems content.` after the
  reward. An early end calls `cancel_close()`, which never rewards.
- `hud_y_pink()` still reads the earned flag to turn the control card's `End` fully pink.

## Tests

`tests/afterglow/test_afterglow.gd` builds the facade with fake callbacks and covers the self-end
gates (minimum time, hold, speech), the `[stay]` extension, the close window's timing, caress
count and single reward, the early cancel, the missionary skip and the runtime forwards for the
HUD and prompt note. Wing folding lives in `wing_control.gd` and is covered in the same suite.
