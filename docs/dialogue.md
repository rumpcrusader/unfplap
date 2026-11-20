# Act dialogue

The act dialogue system owns what the mod makes the ponies say during an act: cue admission, the
cue prompt, the shared utterance slot, reaction lines, the bystander line and the idle history
scan. The runtime keeps the act state machine; this system decides whether and how a line is queued.

A **line** here is one spoken or generated dialogue line, not a source-code line. The authored-line
channel and its `Line*` types are owned by `memory`; `memory/dialogue.gd` is that channel's scene
adapter, not this service.

## Scope

This contract covers:

- the per-act utterance scheduler and its pacing configuration;
- cue admission: stability, shared gap, demand budget, override lifetime and one pending slot;
- cue prompt assembly from the act facts, preferences, relationship facts and the shared memory;
- the normal dialogue prompt notes: the mid-act and afterglow moment, the warm after-sex note,
  the history and relationship lines, the caress/lean reads and the presented body form;
- reaction lines for climax, early end, history refusal and tolerance events;
- the bystander line and its observer pass;
- the idle history scan: the apology repair and the pending reminder/complaint line;
- the recent-line text and the director's last-spoken time;
- cancelling the act's lines at climax, afterglow and act end.

It does not cover the act's mood, cue text, touch/talk scoring or readiness
(`docs/readiness.md`), the memory store and the line channel itself (`docs/memory.md`), or the act
face beats (`docs/face.md`).

## Architecture

| File | Role |
|---|---|
| `dialogue/service.gd` | facade: scheduler state, cue admission, prompt assembly, reactions, the idle history scan, bystander and recent-line reads |
| `shared/act_facts.gd` | the runtime's typed act view: state, ids, mood/cue, stroke and touch/talk values, preferences, prompts, features and the director clock |
| `dialogue/utterance_scheduler.gd` | pure admission policy: stability, gaps, demand budget, the one pending slot |
| `dialogue/utterance.gd` | pure prompt formatting and the private line seed |
| `dialogue/prompts.gd` | pure normal-dialogue note assembly: warm, mid-act, afterglow, caress/lean, presented body |
| `memory/service.gd` | the mod's line channel: queue, key, state, cancel and cancel-by-act |
| `docs/dialogue.md` | this contract |
| `tests/dialogue/` | the pure scheduler/formatting suites and the facade suite |

The facade reads no runtime field and preloads neither `runtime.gd` nor the entry. It reads the
mod's line channel through `MEMORY.instance` and every act value through
`shared/act_facts.gd`. The director is a callable
on the facts; the processed-time clock is a second callable, so line pacing freezes with a paused
tree.

## Internal API

| Method | Contract |
|---|---|
| `configure(pacing)` | push the seven pacing values once per settings snapshot |
| `reset(now, gap)` | start a fresh act: clear the slot, serial, recent angles, memories and bystander state; keep the pacing |
| `admit_cue(now)` | observe the cue, apply the gates in order, log a change, queue one cue prompt; returns the key or `""` |
| `tick()` | release a delivered line, drop an absent row and expire a queued/generating row at its max age |
| `bystander_tick(delta)` | one adult observer line per interval, at most three per act |
| `history_tick(delta, pony, pony_id, event_id, now)` | the idle history scan: repair on a sincere apology, queue one pending reminder/complaint line |
| `end_act(event_id, keep_speaking)` | cancel the act's queued/generating lines; a speaking line may finish |
| `reaction_line(reaction, event_id, fallback, valid)` | queue a reaction through the memory channel |
| `note_reaction(key, cue_text, until)` | reserve the shared slot for that reaction |
| `busy()` | the director or the pony is actually speaking |
| `recent_lines()` / `last_spoken_line()` / `last_spoken_at()` | read the director's recent speech |
| `act_prompt(values)` | the normal note from the act's typed values; the history and relationship notes are read here |
| `history_note(pony_id)` / `relationship_note(pony_id, event_id)` | the stored-history and private relationship notes |
| `climax_line(mouth_busy, cue, act_id, count, max_age)` | the one generated climax line and its validity window |
| `stop_oral_turn(pony_id)` | interrupt the shared director only when it drives this mare |
| `prompt_note(values)` | the pure note assembly's facade entry |
| `scheduler()` | the pure scheduler, for the facade's own calls and the facade suite |

## Admission

`admit_cue()` applies the gates in this order, and the first failure is the logged reason:

1. a demand cue inside its budget → `demand`;
2. the shared slot busy → `channel` (the scheduler owns a pending row) or `speech` (the director
   or the pony is talking);
3. scheduler stability, repeat and gap → the scheduler's `last_reason`.

A cue is queued only when the pose view's `contact_kind` is not `mouth` and the act is `ACTIVE`.
The bed face-sit's `face` contact is not a mouth contact: it queues and speaks normally.
The prompt is formatted, then the face note, the code-owned context note, the optional
speech-feel note and the line-angle note are appended in that order. The shared-memory id is
marked used only after the line was accepted.

Entering oral ends the act's own lines with `keep_speaking = false`: a queued or already speaking
act line is cancelled, `act/session.gd:oral_speech_stop()` stops her base-game voice and re-asserts
the oral mouth shape, and `climax_line()` queues nothing while oral lasts. Bystanders keep their own
turns.

`readiness/service.gd` owns `mood`, `cue` and the override lifetime; the session forwards those values and
sets them on `act_facts` immediately before calling the facade.

## Prompt notes

`dialogue/prompts.gd` is pure and owns the normal dialogue prompt, outside and during an act:

- outside the act states, the warm after-sex note (with the relationship line appended) or the
  history note;
- a live body line for a pony a body-change source handles: `form_name` and whether the form is her
  own or borrowed. The line is the prompt's current-form authority; the pack's event history can
  still quote an earlier shape, so the model must not infer the body from it. A pony with no source
  adds nothing, and the line rides outside, inside and after the act;
- mid-act, the act note plus the history note, the relationship line and one caress/lean sentence
  when one is active (chest and belly in missionary, flank standing); a quiet read adds nothing;
- in afterglow, the afterglow note, the presented body line, one optional beat and the same
  relationship and caress reads; the mid-act history note is not recited, and the note does not
  advertise a stay instruction.

The runtime supplies plain values and keeps the history, relationship, caress, lean, pose and
afterglow-beat reads, so the pure module has no scene access of its own. `form_name` is the
presented form's presentation name and `form_borrowed` is `not form.is_own()`; the runtime reads
both from the body-change service's stored form.

## Reactions and bystanders

A reaction is `memory.reaction_line`: a `LineRequest` with `LineKind.REACTION`. It never waits for
a quiet channel, but `note_reaction()` resets the shared gap so a cue cannot follow immediately.
The act's reactions are climax, intentional early end, history refusal, the tolerance
warning/stop and the body-change offer (`form_offer`). The offer uses the provider policy's prompt
as the fallback when the mare has no `event_form_offer` setting, and it is queued once per act from
the body-change handover's offer tick.

The bystander pass is always on. It uses `memory.observers()` and the modern witness perception.
It starts after 12 s, repeats every 20 s, has a 70 % roll and caps at three lines. Its validity
closure checks the observer, the act event id and `ACTIVE`/`CLIMAX`. Indoors/outdoors wording comes from
`house_interior.gd`.

## Idle history scan

`history_tick()` runs only while the runtime is `IDLE`. The runtime passes the pony, its id, the
act event id and the act's processed clock; the service reads the rest itself: the director through
the typed facts callback, the player turn and text, the paused tree, whether she or the director is
speaking, the director's state, the distance to Anon and whether she is talking to him
(`conversation_target` is his rig or his body). A missing game, player, pony or director ends the
scan.

- A sincere apology is detected locally by `preferences.apology_intent()`; only the pony currently
  in conversation with the player repairs, and only once per in-game day. The repair is
  `ACT_HISTORY.apology_repair()`, followed by `save()` and one `APOLOGY` memory note.
- A pending complaint (tier 2/3) is queued as one short line after a 45 s delay, when the player is
  within 5 m and the director is idle. Tier 1 uses a deterministic rare hint (about one act in
  four) and a vague line with no wants list. One line per tier rise.
- The scan checks once per second. A queued line marks the row announced through
  `ACT_HISTORY.mark_announced()`, so the same act does not speak twice.

The stored row itself is `shared/act_history.gd`; its tiers and wording are in `docs/summary.md`.

## Cancelling

`end_act()` calls `memory.cancel_act(event_id, keep_speaking)` and drops the scheduler's pending
slot. It is called at every climax and afterglow boundary and at every act end. The early-stop
line is queued after that cancel, so the normal restore must not cancel it again.

## Pacing and context

Cue lines are event-driven, not a timer. `dialogue/utterance_scheduler.gd` owns admission, with the
**Talk & cues** debug settings as its pacing:

- a base cue must stay unchanged for `cues.base_stable_seconds`;
- a live touch/talk override only needs `cues.override_stable_seconds`, so an
  event cue can speak inside its `cues.override_seconds` lifetime; if the
  override ends first, the queued line is dropped;
- the per-mare `cue_gap` (clamped `8..30`) and `cues.utterance_gap_seconds`
  must both have elapsed;
- demand cues (`She wants it…`, `She wants a…`, `She wants to be teased…`, `She needs…`) get
  `cues.demand_gap_seconds` and `cues.demand_repeat_seconds`
  for the same text;
- the same text as the last queued cue is not repeated, but may return after another cue;
- a cue or reaction owns one slot at a time. Reactions bypass the cue gates but reset the shared
  gap. A queued or generating row is dropped at `cues.max_age_seconds` (cue) or
  `cues.reaction_max_age_seconds` (reaction); a row already speaking is never cut.
  A quiet or unchanged act may produce no cue line.

The scheduler's pacing fields and `cue_gap` carry no code default: `configure(pacing)` assigns the
seven keys from the runtime snapshot and `reset(now, gap)` sets the per-mare gap, so the shipped
`cues.*` values and the profile's `cue_gap` are their only source.

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
prompt that does not use the placeholder. It suggests one valid `[face:...]` tag at the start of
the line. If the moment genuinely changes how she feels, the same hint allows the game's feeling
tag after the spoken words, such as `[mood: annoyed]`; the act summary may still overwrite the
stored mood at act end. Voice emotions stay in the prompt text: `[whispering]` is the act default,
with `[calm]`, `[happy]`, `[annoyed]`, `[surprised]`, `[sad]` or `[fearful]` by moment.

One unused shared memory may ride with a cue. A stored peak memory is preferred; otherwise the
story journal (a cue-word match, then the most recent player exchange), then older world-context
events. Intimacy events and private brain notes are skipped. The memory is colour, not a script. A
peak memory quotes her answer only when she spoke during the act.

Talk is scored when the player actually uses the game's talk turn. The turn also carries the
body-change interaction: the body-change handover reads the same text for the reveal ask and the
named form, and the act HUD shows one code-owned hint for it (`docs/hud.md`). The provider owns the phrasing: the
reveal phrase set includes the hint's own words, and a pony name only counts on a line that is the
whole name or carries an imperative shape request, so ordinary talk such as “you are a rarity” or
“I don't want Rarity” stays ordinary. There is no talk-invitation line for ordinary cues.

Unprompted cue and reaction lines are always on. The line-angle note adds one fresh angle and the
“use something from today if it fits” hint to a cue line, and the recent-line anti-repeat window
is eight; the template's `Do not repeat: {recent}` is the only copy of those lines. The optional
`features.act_speech_feel` (**Enable speech interjections**) adds the thrust-paced interjection
instruction; the two are independent.

The HUD cue is shorthand, not the line. `UTTERANCE.line_seed()` turns the same facts into a private
second-person seed (`{seed}`): it states the felt need or the moment, never “She wants…”, and ends
with “This is private; let it colour one short line, or let it pass unsaid.” A mismatched
intensity has only the too-rough and too-gentle lines; a mismatched tempo has only too-fast and
too-slow.

## Dependencies

### Uses
| service | world | `world/service.gd` | the world root |

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | memory | `memory/service.gd` | act memory and witness pass |
| service | world | `world/game.gd` | the base-game director, speech and voice members |
| shared | act_state | `shared/act_state.gd` | act state constants |
| shared | act_face | `shared/act_face.gd` | face beat data |
| read model | act_facts | `shared/act_facts.gd` | the typed act values and clock the note reads |
| shared | log | `shared/log.gd` | log sink |
| shared | preferences | `shared/preferences.gd` | profile math and defaults |
| shared | relationship_cue | `shared/relationship_cue.gd` | relationship prompt note |
| store | act_history | `shared/act_history.gd` | stored history rows |

## Lifecycle

- Scope: per-act
- Constructed by: `act/build.gd`
- Begin: `setup()`/`configure()`
- End: `reset()`/act end
- Idempotent: yes


## Tests

- `tests/dialogue/test_utterance.gd`: pure formatting and the line seed.
- `tests/dialogue/test_utterance_scheduler.gd`: stability, gaps, demand budget and the slot.
- `tests/dialogue/test_act_dialogue.gd`: pacing configuration, cue admission, prompt assembly,
  the memory channel, reactions, the recent-line reads, busy state, act-end cancellation, the
  idle apology repair and the pending reminder line.
- `tests/dialogue/test_prompt_notes.gd`: the warm, mid-act and afterglow notes, the caress/lean
  reads and the presented body's own/borrowed line.

Run:

```bash
godot --headless --xr-mode off --path <project> \
  --script res://mods/unfplap/tests/dialogue/test_act_dialogue.gd
```
