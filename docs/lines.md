# Act lines

The line system owns what the mod makes the ponies say during an act: cue admission, the cue
prompt, the shared utterance slot, reaction lines and the optional bystander line. The runtime
keeps the act state machine; this system decides whether and how a line is queued.

## Scope

This contract covers:

- the per-act utterance scheduler and its pacing configuration;
- cue admission: stability, shared gap, demand budget, override lifetime and one pending slot;
- cue prompt assembly from the act facts, preferences, relationship facts and the shared memory;
- reaction lines for climax, early end, history refusal and tolerance events;
- the bystander line and its observer pass;
- the recent-line text and the director's last-spoken time;
- cancelling the act's lines at climax, afterglow and act end.

It does not cover the act's mood, cue text, touch/talk scoring or readiness (`PREFERENCES.md`),
the memory store and the line channel itself (`docs/memory.md`), or the act face beats
(`AGENTS.md`, `## Critical: act expression and mood`).

## Architecture

| File | Role |
|---|---|
| `act_lines.gd` | facade: scheduler state, cue admission, prompt assembly, reactions, bystander and recent-line reads |
| `act_facts.gd` | the runtime's typed act view: state, ids, mood/cue, stroke and touch/talk values, preferences, prompts, features and the director clock |
| `utterance_scheduler.gd` | pure admission policy: stability, gaps, demand budget, the one pending slot |
| `utterance.gd` | pure prompt formatting and the private line seed |
| `memory.gd` | the mod's line channel: queue, key, state, cancel and cancel-by-act |
| `docs/lines.md` | this contract |
| `tests/act_lines/` | the pure scheduler/formatting suites and the facade suite |

The facade reads no runtime field and preloads neither `runtime.gd` nor `main.gd`. It receives
`main` through `setup()` and every act value through `act_facts.gd`. The director is a callable
on the facts; the processed-time clock is a second callable, so line pacing freezes with a paused
tree.

## Internal API

| Method | Contract |
|---|---|
| `setup(main)` | bind the mod entry node; the memory facade is read per call |
| `configure(pacing)` | push the seven pacing values once per settings snapshot |
| `reset(now, gap)` | start a fresh act: clear the slot, serial, recent angles, memories and bystander state; keep the pacing |
| `admit_cue(now)` | observe the cue, apply the gates in order, log a change, queue one cue prompt; returns the key or `""` |
| `tick()` | release a delivered line, drop an absent row and expire a queued/generating row at its max age |
| `bystander_tick(delta)` | one adult observer line per interval, at most three per act |
| `end_act(event_id, keep_speaking)` | cancel the act's queued/generating lines; a speaking line may finish |
| `reaction_line(reaction, event_id, fallback, valid)` | queue a reaction through the memory channel |
| `note_reaction(key, cue_text, until)` | reserve the shared slot for that reaction |
| `busy()` | the director or the pony is actually speaking |
| `recent_lines()` / `last_spoken_line()` / `last_spoken_at()` | read the director's recent speech |
| `scheduler()` | the pure scheduler, for the facade's own calls and the facade suite |

## Admission

`admit_cue()` applies the gates in this order, and the first failure is the logged reason:

1. `features.act_lines` off → `act_lines_off`;
2. a demand cue inside its budget → `demand`;
3. the shared slot busy → `channel` (the scheduler owns a pending row) or `speech` (the director
   or the pony is talking);
4. scheduler stability, repeat and gap → the scheduler's `last_reason`.

A cue is queued only when the segment is not oral (`facts.oral_active`) and the act is `ACTIVE`.
The prompt is formatted, then the face note, the code-owned context note, the cue-reaction note,
the optional speech-feel note and the optional line-angle note are appended in that order. The
shared-memory id is marked used only after the line was accepted.

The runtime owns `mood`, `cue`, the override lifetime and the reacted log text's inputs; it sets
those fields on `act_facts` immediately before calling the facade.

## Reactions and bystanders

A reaction is `memory.reaction_line`: a `LineRequest` with `LineKind.REACTION`. It never waits for
a quiet channel, but `note_reaction()` resets the shared gap so a cue cannot follow immediately.
The act's reactions are climax, intentional early end, history refusal and the tolerance
warning/stop.

The bystander pass uses `memory.observers()` and the modern witness perception. It starts after
12 s, repeats every 20 s, has a 70 % roll and caps at three lines. Its validity closure checks the
observer, the act event id and `ACTIVE`/`CLIMAX`. Indoors/outdoors wording comes from
`house_interior.gd`.

## Cancelling

`end_act()` calls `memory.cancel_act(event_id, keep_speaking)` and drops the scheduler's pending
slot. It is called at every climax and afterglow boundary, every act end, and when
`features.act_lines` is switched off mid-act. The early-stop line is queued after that cancel, so
the normal restore must not cancel it again.

## Tests

- `tests/act_lines/test_utterance.gd`: pure formatting and the line seed.
- `tests/act_lines/test_utterance_scheduler.gd`: stability, gaps, demand budget and the slot.
- `tests/act_lines/test_act_lines.gd`: pacing configuration, cue admission, prompt assembly,
  the memory channel, reactions, the recent-line reads, busy state and act-end cancellation.

Run:

```bash
godot --headless --xr-mode off --path <project> \
  --script res://mods/unfplap/tests/act_lines/test_act_lines.gd
```
