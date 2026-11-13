# Act memory and the mod's own lines

The memory system owns what the mod remembers and what it makes the director say: the
world-context events, the per-mare impression, the peak-memory store, the witness pass, and the
mod-owned dialogue line channel. This file is the single technical contract; other docs link here.

## Scope

This contract covers:

- the act's world-context event and its grade-aware impression;
- the fixed-wording intimacy events (cancel, pony climax, stop, apology);
- the refusal event and its private thought;
- the per-world peak-memory record and its read;
- the witness pass: the perception test, the per-observer age split and the age-appropriate row;
- the mod's own line channel: queue, key, cancel, cancel-by-act and the typed line state;
- the cue facts and the one shared-memory hit for the cue prompt.

It does not cover act scoring, the grade, history tiers or hurt repair (`docs/summary.md`), act
eligibility and consent (`docs/eligibility.md`), proactive requests (`docs/initiation.md`), or the
cue admission, prompt assembly and act-line reactions (`docs/lines.md`). The memory system only
writes the facts those systems read.

## Architecture

| File | Role |
|---|---|
| `memory/service.gd` | facade: the typed internal API, the three writes, the four line-channel calls and the four reads; composes the adapters and reads `main.game` and `main.eligibility` per call |
| `memory/facts.gd` | pure typed boundary data: `LineState`, `LineKind`, `Reaction`, `NoteKind`, `StopReason`, `ImpressionSlot`, `Sense`, and the `Impression`, `Peak`, `Witness`, `Observer`, `CueFacts`, `MemoryHit`, `Line`, `LineRequest` types |
| `memory/text.gd` | pure wording and ids: the director key and its prefix, the keep-active rule, the impression/event suffixes, the event kinds, the stop names, the event texts, the witness texts |
| `memory/world.gd` | scene adapter: the only reader of `world_context` and `impressions`, and the builder of the private cue facts and the shared-memory hit |
| `memory/dialogue.gd` | scene adapter: the only reader of the conversation director's authored-line queue |
| `memory/perception.gd` | scene adapter: the only reader of the ponies, awareness, sleeping, house lookup and the player's form |
| `memory/store.gd` | scene adapter: the only reader and writer of `Mods.state("unfplap").peak_memories` and the only memory file that asks the mod to save |
| `docs/memory.md` | this contract |
| `tests/memory/` | pure wording, facts, store and dialogue suites, plus the facade API suite |

The purity boundary is deliberate:

- `facts.gd` and `text.gd` have no `Node`, tree, time, file, `Settings`, scene or game preload.
  They take plain values and return plain values or strings.
- `world.gd` owns `world_context.record`, `world_context.events_for`, `world_context.story`,
  `impressions.commit`, `impressions.profile`, `relationship_runtime.ladder`, `bonds.record_for`
  and the `act_history` read. Every read is guarded.
- `dialogue.gd` owns the director's `queue_generated_intent`, `state`, `active`, `cancel` and the
  authored-line list. A game change that removes the queue makes the mod's lines stop instead of
  erroring.
- `perception.gd` owns `PonyAwareness`, `HouseInterior.at`, `PlaceAt`, the `mares` list and
  `PlayerForm.is_young`. The age rule comes from the eligibility capability answer
  (`eligibility.witness_age`), never from a local copy.
- `store.gd` owns the `Mods` lookup and the save. No other memory file writes the section.
- The facade is the only file that preloads `memory/*`; no file outside `memory/service.gd` and
  `memory/` preloads `memory/*`.
- `main.gd` creates the service (`setup(self)`) and exposes it as `main.memory`. The facade
  reads `main.game` and `main.eligibility` per call and stores nothing. It is a RefCounted, not a
  Node, so it has no world lifecycle.

## Internal API

`main.memory`:

```gdscript
enum LineState { ABSENT, QUEUED, GENERATING, SPEAKING, DELIVERED, UNKNOWN }
enum LineKind { REACTION, UTTERANCE, BYSTANDER }
enum Reaction { CLIMAX, END_EARLY, HISTORY_REFUSAL, HISTORY_REMINDER,
                HISTORY_COMPLAINT, TOLERANCE_WARNING, TOLERANCE_STOP }
enum NoteKind { CANCELLED, CLIMAXED, STOPPED, APOLOGY }
enum StopReason { NONE, UNWILLING, PICKED_UP, INTERRUPTED, FORM_CHANGE, WITHDREW }
enum ImpressionSlot { ACT, ACT_EARLY, REFUSAL, STAY_CLOSE }
enum Sense { SIGHT, SOUND }

class Impression:   id, event_id, slot, mood, romance, thought, event_text
class Peak:         id, event_id, text, score
class Witness:      id, young, sense, indoors, distance, place, text; to_dict()
class Observer:     id, node, sense, indoors
class CueFacts:     friendship, friendship_level, love, love_level, stage, anger,
                    mood, first_time, careful; to_dict()
class MemoryHit:    id, text; found()
class Line:         key, queued
class LineRequest:  kind, id, event_id, suffix, purpose, reaction, valid, finished

func setup(main_node: Node) -> void

func commit(impression: Impression) -> void
func note(kind: NoteKind, id: String, event_id: String, reason := 0) -> void
func record_peak(peak: Peak) -> void

func line(request: LineRequest) -> Line
func line_state(key: String) -> LineState
func cancel_line(key: String) -> void
func cancel_act(event_id: String, keep_speaking := true) -> int

func cue_facts(id: String, event_id: String) -> CueFacts
func shared_memory(id: String, cue: String, event_id: String, used: Array) -> MemoryHit
func observers(partner: Node3D) -> Array[Observer]
func witnesses(partner_id: String, name: String, serial: int,
        partner: Node3D) -> Array[Witness]
```

The enum values are the `int` members of the enum; `0` is the first member of each. The facade
re-exports them as `MEMORY.LineState`, `MEMORY.LineKind`, and so on, so a caller compares
`MEMORY.LineState.SPEAKING` instead of a string.

## Data ownership

| Data | Stored where | Owner |
|---|---|---|
| Act summary, refusal, stay-close, mood | `world_context.impressions` (per mare) | `memory/world.gd` |
| Act/refusal/stop/pony-climax/witness event | `world_context` (per world) | `memory/world.gd` |
| Peak memory | `Mods.state("unfplap").peak_memories` | `memory/store.gd` |
| Live line key, state, queue | the director's authored-line queue | `memory/dialogue.gd` |
| Cue facts, shared-memory hit | derived per call | `memory/world.gd` |
| Observer perception | derived per call | `memory/perception.gd` |

Rules:

- The only memory-owned persisted value is the peak memory. The event, impression, cue-fact and
  witness values are all game-owned and the facade only reads or writes them.
- The event id is the idempotency key: `world_context.record` and `impressions.commit` both
  ignore a repeated id. The same act never writes the same event twice.
- The store is the only memory file that calls `Mods.save_changed()`.

## Impressions and events

`commit(impression)` writes one impression and, when its slot carries an event, the event. The
`ImpressionSlot` chooses the suffix and the event kind:

| Slot | Event id | Impression suffix | Event kind | Event text |
|---|---|---|---|---|
| `ACT` | `:gain` | `:gain` | `relationship` | the summary's `text` |
| `ACT_EARLY` | `:summary` | `:summary` | `relationship` | the summary's `text` |
| `REFUSAL` | `:mood` | `:mood` | `intimacy` | the refusal text |
| `STAY_CLOSE` | `:stay_close_gain` | `:stay_close_gain` | `relationship` | the stay-close text |

The `text` is profile-safe: the game's profile rewrites a leading `You and Anon ` to
`You and <name>`, so no event line uses a second-person pronoun for the pony after that prefix.
The `thought` stays first-person and never goes through the profile rewrite. A refusal text is
chosen by the `angry` mood; the stay-close thought is chosen by the `romance` and the mood.

`note(kind, id, event_id, reason)` writes the fixed-wording intimacy events:

| Kind | Event id | Text |
|---|---|---|
| `CANCELLED` | `:cancel` | `Anon stopped before the act reached a climax.` |
| `CLIMAXED` | `:pony_climax` | `You and Anon made love, and she came.` |
| `STOPPED` | `:stop:<reason>` | the stop reason's text |
| `APOLOGY` | `apology:<id>:<usec>` | `Anon apologized for last time.` |

The `StopReason` names are `unwilling`, `picked up`, `interrupted`, `form change` and
`withdrew`. `NONE` is the default and writes nothing. The `"world close"` reason is unreachable
and is not listed.

## Witness pass

`observers(partner)` is the read-only test: it returns each adult who can perceive the act right
now, with the `Sense` she used. It commits nothing. `witnesses(partner_id, name, serial, partner)`
runs the same test and writes one row per observer:

- The act is skipped when the player is a young form, or the partner is not in the tree.
- A pony is skipped when she is sleeping, is the partner, or has no identity.
- A young pony is never an observer; the `Age` split comes from `eligibility.witness_age`.
- An adult is `SIGHT` when `PonyAwareness.visible(observer, partner)` (24 m, facing, clear line)
  or `SOUND` when `can_hear(observer, partner, HEARING_RANGE)` (12 m, clear line).
- An adult gets `witnessed_intimacy` with the explicit text and the `surprised` thought; a young
  pony gets `witnessed_scene`, a perception with an indoors/outdoors prefix and no conclusion, and
  `amused` mood only. The game's per-pony story summary forms the memory from the perception.
- The event id is `witness_<observer>_<partner>_<serial>`; the impression is
  `...:gain`. The `serial` varies the young tail so repeated gossip does not read the same.
- The `Witness` row carries the debug fields: `id`, `young`, `sense`, `indoors`, `distance`,
  `place`, `text`.

## Line channel

`line(request)` queues one of the mod's own lines. The `LineKind` picks the director path:

| Kind | Purpose source | Key |
|---|---|---|
| `REACTION` | the `act_prompts.event_<name>` override, or the caller's fallback; the climax adds a first-person thought instruction and the face note | `unfplap:<event_id>:reply:<name>` |
| `UTTERANCE` | the ready cue prompt | `unfplap:<event_id>:line:<suffix>` |
| `BYSTANDER` | the ready bystander prompt | `unfplap:<event_id>:bystander:<id>` |

`Line.key` always names the line; `Line.queued` says whether the director accepted it. Every key
is prefixed with the event id, so `cancel_act(event_id)` can drop the whole act.

`line_state(key)` returns the director's `LineState` for the key. A `SPEAKING` line is already
rendering; `DELIVERED` and `UNKNOWN` are not.

`cancel_line(key)` drops one line. `cancel_act(event_id, keep_speaking)` drops every line under
the act's prefix and keeps a line that is already speaking, or `keep_speaking` is false. The
keep-active rule is in `memory/text.gd`: a line is kept only when it is `SPEAKING`, its key is
the active row, and the caller asked to keep it. The returned count is the number of lines
dropped.

## Cue facts and shared memory

`cue_facts(id, event_id)` returns the private relationship facts for the cue prompt: the
friendship and love names and levels, the relationship stage, the anger, the mood, the first-time flag
(no prior intimacy event and no stored act) and the careful flag (the mood is `annoyed` or the
anger is positive). The `event_id` is the act's own, so a prior event does not count as the
first. The raw scores and counts never leave the `CueFacts`; `to_dict()` is only the bridge to
the pure relationship and cue formatters.

`shared_memory(id, cue, event_id, used)` returns one unused memory: the stored peak first, then
the story journal (a cue-word match, then the most recent player exchange), then the
world-context events. The `used` ids are skipped. A hit with no text is `found()` false. The
memory is marked used only after the caller queues the line.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | eligibility | `eligibility/service.gd` | adult and consent gate |
| service | settings | `settings/service.gd` | settings declarations and live values |
| shared | act_face | `shared/act_face.gd` | face beat data |
| shared | pony_id | `shared/pony_id.gd` | stable pony id |
| store | act_history | `shared/act_history.gd` | stored history rows |

## Lifecycle

- Scope: world
- Constructed by: `main._ready()`
- Begin: `setup()`
- End: `clear()`
- Idempotent: yes


## Tests

- `tests/memory/test_text.gd`: the pure wording — the adult, the young and the scene texts, the
  refusal and stop texts, the impression and event suffixes, the witness impression, and the
  keep-active rule.
- `tests/memory/test_facts.gd`: the typed defaults, the `CueFacts` dictionary and the `MemoryHit`
  `found()` flag.
- `tests/memory/test_store.gd`: the peak record, the higher-score replacement and the save.
- `tests/memory/test_dialogue.gd`: the typed line state, the keep-active cancel and the cancel
  prefix.
- `tests/memory/test_memory_api.gd`: the facade through a fake game and director — one
  impression and event per slot, the refusal mood, the stay-close reward, one event per note, the
  cue facts and the memory hit.
- `tests/test_source_hygiene.gd`: the pure-core boundary, the facade-only preload rule, the
  adapter private-access boundary and this contract's presence.

## Known limits

- The dialogue adapter reads the director's authored-line queue and the world adapter reads the
  stock `world_context` and `impressions` fields. A game change can remove them; every read is
  guarded and the memory simply stops writing.
- The witness pass reads the game's `PonyAwareness` and `HouseInterior`; a game change that moves
  the perception or the house lookup is a change to this adapter, not a new rule.
- The peak memory is a single row per mare and never expires; a higher score replaces it.
- The event id is the only idempotency key. A caller that reuses an event id for a different act
  writes nothing the second time.
