# Afterglow and the standing close window

## Scope

`afterglow/service.gd` owns the held post-act phase: the private afterglow beat, the standing
close window with its caress reward, the presentation row the phase asks for, and the reward's
memory, history, face, heart and cue writes. It does not own the `AFTERGLOW` state or the phase's
other presentation.

`act/session.gd` guards and dispatches the transition: `begin_afterglow()` orders the phase's calls,
and the frame schedule (`act/tick.gd`) calls the facade's `phase_tick()` while the act is
`AFTERGLOW`. The facade applies its own presentation row through
`apply_presentation(pose)`; the session starts the wing return when the row asks for it. The
facade's reward writes through its bound `face`, `reactions` and `readiness` and the act ids
`set_act()` records.


`afterglow/service.gd` is the facade and the only module another system calls. The private records
are `afterglow/summary.gd` (the typed act summary the phase reads) and `afterglow/presentation.gd`
(the typed presentation row); the phase has no other useful sub-module.

## Architecture

| Piece | Owns |
|---|---|
| `afterglow/service.gd` | the private beat, the close-window timer and its reward decision, the presentation row |
| `afterglow/summary.gd` | the typed summary the afterglow beat, the positive flag and the face context read |
| `afterglow/presentation.gd` | the typed row: tail target and flicks, HUD state, wings |
| `afterglow/aftercare.gd` | the ten-second hosted body language node |
| `runtime.gd` | the state transition, the phase end, the scene presentation, the memory/history writes and the HUD refresh |

Host callbacks, all optional so a test can build the facade without a runtime:

| Callback | Meaning |
|---|---|
| `log(text)` | debug log |
| `caress_active() -> bool` | the hand controller has an active caress |
| `write_satisfaction(value)` | the aftercare decay's meter write |

The phase's act collaborators are bound once by the builder (`bind_act(face, reactions, readiness)`)
and the act ids by the session (`set_act(pony_id, event_id)`); the close reward writes through
them.

## Internal API

| Method | Meaning |
|---|---|
| `begin(summary)` | start the phase from the typed summary record, roll the private beat and open the close window the view profile declares |
| `bind_view(view)` | carry the pose view whose `afterglow.close_window` decides that window |
| `presentation()` | the typed afterglow row: tail target and flicks from the active `view.family`, HUD state and the wings flag; the act's current pose holds |
| `reset()` | clear every per-act value; the callbacks stay |
| `phase_tick(delta, anatomy, anatomy_host, standing)` | one AFTERGLOW frame: the bed-body part's tracking, then `close_tick()` when the live pose family is standing |
| `close_tick(delta)` | count caress time and run the window down |
| `cancel_close()` | drop the window without a reward |
| `apply_presentation(pose)` | apply the row: the held pose weight, the tail target and flicks and the HUD state; returns whether the row asks for the wing return |
| `hint()` | the close prompt, or the content line after the reward |

## Ending

Only the player ends the afterglow: holding the act key calls `act/input.gd:end_afterglow()`, and a
cancel on the afterglow takes the same path through `act/exit.gd:end_afterglow()`. The pony never ends the phase herself and there is no end
timer, so the held moment lasts until the player leaves it. Leaving early cancels the standing
close window without its reward.

## Held pose

The afterglow holds the current pose: the pose the act ended in, unchanged. The presentation row
carries no pose mode and no afterglow pose id, and `apply_presentation()` only re-asserts
`target_amount`/`amount` alongside the tail, HUD and wings. The pose evaluator keeps its current
driver/delta pair and config; nothing rebuilds, releases or re-poses the body at the phase change.
The close window comes from the view's `afterglow.close_window`. The phase has no `pose_changed`
hook. The runtime and facade source must not name a pose mode.

For `standing_oral` the held pose is the turned frame and the neck keys. On entry the session calls
`release_mouth_contact()`: the contact returns to the opening, the viseme clears, the soft-kiss
timer stops, and the turned root/facing stay until the one act exit restores them. No reverse edge
runs implicitly, and the pose row's passive afterglow opens no close window.

The tail target and flick count follow the active `view.family`: `standing` lifts the tail and
flicks it, `bed` lowers it and keeps it still. `view.family` is `standing` for `standing`,
`standing_test` and `standing_oral`, `bed` for missionary. Without a bound view the row reads the
bed values; there is no start-pose fallback. The bed face-sit uses the `passive` row, opens no
close window and keeps the live pose and its face contact until the one act exit.

## `[stay]` action

The mod's afterglow note does not advertise `[stay: SECONDS]`. The base game's ordinary
hold-position action is unchanged, and the afterglow facade does not bind the game's action
executor, so that action does not control the phase.

## Close window

- The pose row's `afterglow.close_window` opens it: standing declares it; missionary and
  `standing_oral` do not. `begin()` sets `close_left = STAY_CLOSE_SECONDS` (8 s) when the profile
  opens the window.
- `close_tick()` adds to `close_caress_seconds` while the hand controller has an active caress and
  subtracts the same delta from `close_left`.
- At zero the window grants exactly one reward. `close_caress_earned` is true only with at least
  `STAY_CLOSE_CARESS_SECONDS` (2.5 s) of caress. The facade's own reward writes the `STAY_CLOSE`
  memory impression, the history repair, the content face, the heart burst and the cue clear, with
  every write guarded on its bound collaborator.
- `hint()` is `Stay close · Ns · caress` while the window runs and `She seems content.` after the
  reward. An early end calls `cancel_close()`, which never rewards.
- The view's raw `close_earned` is read by `hud/lines.gd:y_pink()` to turn the control card's
  `End` fully pink.

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
| service | face | `face/service.gd` | the close reward's content face |
| host | the entry | `_init(hud, memory)` | the held HUD state |
| service | memory | `memory/service.gd` | the `STAY_CLOSE` impression |
| service | poses | `poses/service.gd` | the held pose, tail and tail flicks |
| service | readiness | `readiness/service.gd` | the reward's cue clear |
| service | reactions | `reactions/service.gd` | the reward's heart burst |
| service | world | `world/service.gd` | the live world root |
| service | world | `world/game.gd` | the navigator reads the aftercare holds |
| store | act_history | `shared/act_history.gd` | the bad-act history repair |
| shared | log | `shared/log.gd` | log sink |

## Lifecycle

- Scope: per-act
- Constructed by: `act/build.gd` through `runtime._init()`
- Begin: `begin()`
- End: `reset()`
- Idempotent: yes


## Tests

`tests/afterglow/test_afterglow.gd` builds the facade with fake callbacks and covers the close
window's timing, caress count and single reward, the early cancel, the missionary, oral and
face-sit holds,
the presentation row (no pose mode/afterglow pose, the tail row following the view family, the
held pose, the re-asserted weight and the view-less bed fallback) and the runtime forwards for the HUD
and prompt note. Wing folding lives in
`poses/wing_control.gd` and is covered in the same suite; the wing controller reads the typed act
view (`facts.pony`, `facts.clock()`) and a `log` callback, never the runtime node.
