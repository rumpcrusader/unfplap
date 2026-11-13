# Act lines

The line system owns what the mod makes the ponies say during an act: cue admission, the cue
prompt, the shared utterance slot, reaction lines and the optional bystander line. The runtime
keeps the act state machine; this system decides whether and how a line is queued.

## Scope

This contract covers:

- the per-act utterance scheduler and its pacing configuration;
- cue admission: stability, shared gap, demand budget, override lifetime and one pending slot;
- cue prompt assembly from the act facts, preferences, relationship facts and the shared memory;
- the normal dialogue prompt notes: the mid-act and afterglow moment, the warm after-sex note,
  the history and relationship lines and the caress/lean reads;
- reaction lines for climax, early end, history refusal and tolerance events;
- the bystander line and its observer pass;
- the recent-line text and the director's last-spoken time;
- cancelling the act's lines at climax, afterglow and act end.

It does not cover the act's mood, cue text, touch/talk scoring or readiness
(`docs/readiness.md`), the memory store and the line channel itself (`docs/memory.md`), or the act
face beats (`docs/face.md`).

## Architecture

| File | Role |
|---|---|
| `lines/service.gd` | facade: scheduler state, cue admission, prompt assembly, reactions, bystander and recent-line reads |
| `shared/act_facts.gd` | the runtime's typed act view: state, ids, mood/cue, stroke and touch/talk values, preferences, prompts, features and the director clock |
| `lines/utterance_scheduler.gd` | pure admission policy: stability, gaps, demand budget, the one pending slot |
| `lines/utterance.gd` | pure prompt formatting and the private line seed |
| `lines/prompts.gd` | pure normal-dialogue note assembly: warm, mid-act, afterglow, caress/lean |
| `memory/service.gd` | the mod's line channel: queue, key, state, cancel and cancel-by-act |
| `docs/lines.md` | this contract |
| `tests/lines/` | the pure scheduler/formatting suites and the facade suite |

The facade reads no runtime field and preloads neither `runtime.gd` nor `main.gd`. It receives
`main` through `setup()` and every act value through `shared/act_facts.gd`. The director is a callable
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
| `prompt_note(values)` | the normal dialogue note: state, warm, history, beat, relation, caress/lean, pose |
| `lover_prompt_note(stored_bond)` | the neutral lover wording; the runtime keeps the bond gates |
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

`readiness/service.gd` owns `mood`, `cue` and the override lifetime; the runtime forwards those values and
sets them on `act_facts` immediately before calling the facade.

## Prompt notes

`lines/prompts.gd` is pure and owns the normal dialogue prompt, outside and during an act:

- outside the act states, the warm after-sex note (with the relationship line appended) or the
  history note;
- mid-act, the act note plus the history note, the relationship line and one caress/lean sentence
  (chest and belly in missionary, flank standing);
- in afterglow, the afterglow note, one optional beat, the same relationship and caress reads and
  the `[stay: 120]` instruction; the mid-act history note is not recited.

The runtime supplies plain values and keeps the history, relationship, caress, lean, pose and
afterglow-beat reads, so the module has no scene access.

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

## Pacing and context

Cue lines are event-driven, not a timer. `lines/utterance_scheduler.gd` owns admission, with the
**Talk & cues** debug settings as its pacing:

- a base cue must stay unchanged for `cues.base_stable_seconds` (default `2 s`);
- a live touch/talk override only needs `cues.override_stable_seconds` (default `0.5 s`), so an
  event cue can speak inside its `cues.override_seconds` lifetime (default `10 s`); if the
  override ends first, the queued line is dropped;
- the per-mare `cue_gap` (default `12`, clamped `8..30`) and `cues.utterance_gap_seconds`
  (default `18 s`) must both have elapsed;
- demand cues (`She wants it…`, `She wants a…`, `She wants to be teased…`, `She needs…`) get
  `cues.demand_gap_seconds` (default `28 s`) and `cues.demand_repeat_seconds` (default `45 s`)
  for the same text;
- the same text as the last queued cue is not repeated, but may return after another cue;
- a cue or reaction owns one slot at a time. Reactions bypass the cue gates but reset the shared
  gap. A queued or generating row is dropped at `cues.max_age_seconds` (default `20 s`, cue) or
  `cues.reaction_max_age_seconds` (default `30 s`, reaction); a row already speaking is never cut.
  A quiet or unchanged act may produce no cue line.

Every cue line gets a private relationship note and tone: friendship/love level, a human stage
phrase, first-time/repeat, mood, then `guarded`/`friendly`/`tender`/`warm`/`ardent`/`open`/
`careful`. No romance with an acquaintance is `guarded`; no romance with a friend is `friendly`; a
first time with romance or a crush/new couple is `tender`; a marefriend is `warm`. `first_time`
uses durable act history plus the world context. The functional cue text is unchanged, and the
model is not told to repeat specific names.

`UTTERANCE.context_note()` owns the mandatory context. If a saved prompt omits `{state}`,
`{relationship}`, `{tone}` or `{memory}`, the facade appends that block and the privacy guard after
formatting. A legacy template cannot drop the relationship note.

`{face_note}` is the base-game expression hint. The default `cue`/`utterance` prompts carry it;
the facade fills it from `act_face.prompt_note("cue", mood)` and appends the same hint to a saved
prompt that does not use the placeholder. It suggests one valid `[face:...]` tag and forbids
`[mood:...]` in an act line. Voice emotions stay in the prompt text: `[whispering]` is the act
default, with `[calm]`, `[happy]`, `[annoyed]`, `[surprised]`, `[sad]` or `[fearful]` by moment.

One unused shared memory may ride with a cue. A stored peak memory is preferred; otherwise the
story journal (a cue-word match, then the most recent player exchange), then older world-context
events. Intimacy events and private brain notes are skipped. The memory is colour, not a script. A
peak memory quotes her answer only when she spoke during the act.

Talk is scored when the player actually uses the game's talk turn. There is no act
talk-invitation line or HUD hint.

`features.act_lines` (default on) gates unprompted cue and reaction lines. Off keeps normal
dialogue and the HUD cue. `features.act_line_angles` (default on) adds one fresh angle and the
shared-day/history hint to a cue line, and widens the recent-line anti-repeat window to eight.
`features.act_speech_feel` (default off) adds the thrust-paced interjection instruction. They are
independent.

The HUD cue is shorthand, not the line. `UTTERANCE.line_seed()` turns the same facts into a private
second-person seed (`{seed}`): it states the need or the moment, never “She wants…”, and ends with
“This is private, not a script; you may show it, say it, or let it go unsaid.”

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | memory | `memory/service.gd` | act memory and witness pass |
| shared | act_face | `shared/act_face.gd` | face beat data |
| shared | preferences | `shared/preferences.gd` | profile math and defaults |
| shared | relationship_cue | `shared/relationship_cue.gd` | relationship prompt note |

## Lifecycle

- Scope: per-act
- Constructed by: `runtime`
- Begin: `setup()`/`configure()`
- End: `reset()`/act end
- Idempotent: yes


## Tests

- `tests/lines/test_utterance.gd`: pure formatting and the line seed.
- `tests/lines/test_utterance_scheduler.gd`: stability, gaps, demand budget and the slot.
- `tests/lines/test_act_lines.gd`: pacing configuration, cue admission, prompt assembly,
  the memory channel, reactions, the recent-line reads, busy state and act-end cancellation.
- `tests/lines/test_prompt_notes.gd`: the warm, mid-act and afterglow notes, the
  caress/lean reads and the two facade forwarders.

Run:

```bash
godot --headless --xr-mode off --path <project> \
  --script res://mods/unfplap/tests/lines/test_act_lines.gd
```
