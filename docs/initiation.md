# Proactive requests

The proactive service is the one controller that lets a mare ask Anon for sex. It keeps the pacing,
the placeable choice, the walk and the ask; it does not own the answer, the Agreement or the act
start. It never starts the act: the Negotiation service owns the exchange and the act key consumes
the Agreement. This file is the single technical contract; other docs link here.

## Scope

This contract covers:

- the quiet gate that decides when an automatic request may begin;
- admission: the per-mare cooldown, the heat shortening, the short retry and the scan interval;
- Base clearance and the placeable pose options for a cuddle, a bed and a standing offer;
- Mare Initiation Reasoning: whether she offers and which option she chooses;
- the walk to Anon or to the bed front and the arrival settle;
- the ask line, the observed-situation record and the Mare-offer handoff;
- the pacing update from the Negotiation service's terminal outcome;
- the world-context situations, the debug actions and the lab path.

It does not cover the exchange, the Anon decision, privacy sampling, the Agreement, the presentation
or the act start: those are `docs/negotiation.md` and `docs/runtime.md`.

## Architecture

| File | Role |
|---|---|
| `initiation/service.gd` | facade: scan, admission, Base clearance, candidate assembly, the live episode, phase dispatch, the reasoning call, the ask and the handoff |
| `initiation/facts.gd` | pure typed `Request`: the plain values the wording reads |
| `initiation/policy.gd` | pure pacing: scan, cooldown, heat, retry, approach, bed search, wording mode and the phase names |
| `initiation/reasoning.gd` | pure Mare Initiation Reasoning: the instruction, the payload and the parser |
| `initiation/prompts.gd` | pure wording: the ask context, the ask purpose, the situation text and the heat line |
| `initiation/cooldowns.gd` | request cooldown store: `request_times`, the history wait and the heat shortening |
| `initiation/venue.gd` | scene adapter: the only reader of navigators, posture, the bed search and the placement facts |
| `privacy/service.gd` | world privacy provider: the house, the other mares, the radius and the offer/cuddle predicates |
| `negotiation/adapter.gd` | the director bridge and model host `main` injects: the quiet gate, the ask queue, the situation record, the reasoning call |
| `negotiation/service.gd` | the Act Negotiation: the answer, privacy, the Agreement and the global lock |
| `docs/initiation.md` | this contract |
| `tests/initiation/` | the pure rules, facts, reasoning and wording suites, plus the facade API suite |

The purity boundary is deliberate:

- `facts.gd`, `policy.gd`, `prompts.gd` and `reasoning.gd` have no `Node`, tree, time, file,
  `Settings`, scene or game preload. They take plain values and return plain values or strings.
- `venue.gd` owns `Navigator` fields (`command_owner`, `wander_enabled`, `command_speed_limit`,
  `command_pace_target`, `reserved_by`, `_has_target`), `request_posture`/`posture_status`, the bed
  rest (`_front_for`, `_mare_fits`, `_guest`, `_sleeper`), the player seat, the `couches` group and
  `WorldLayout`. It also builds the placement facts the option builder consumes.
- The director bridge is the injected `negotiation/adapter.gd`; this service never reads the
  director or the classifier. `main` owns one adapter and gives it to this service at `setup()`.
- The facade is the only file that preloads `eligibility/service.gd`, `privacy/service.gd`,
  `shared/clearance.gd`, `shared/context.gd`, `shared/pose_options.gd`, `shared/pose_catalog.gd`
  and `shared/cycle.gd`; `cooldowns.gd` preloads `shared/act_history.gd`.
- No file outside `initiation/service.gd` and `initiation/` preloads `initiation/*` except the
  orchestrator, which owns the service.
- `main.gd` creates the service (`setup(self, privacy, adapter)`) and drives it: `tick`, `reset`,
  `force`, `placement_for` and the outcome handoff. `runtime.gd` exposes `cuddle_active()` and the
  scene-only verdict.

## Internal API

`main.initiation`:

```gdscript
enum Phase { NONE, APPROACH, ARRIVE, ASK, BED_APPROACH }

class Candidate:   id, runtime, pony, options, option, base, context, private, cuddle, forced
class Episode:     serial, phase, candidate values, timers, hazard, navigator lease
class ForceResult: ok, id, pose, reject

func setup(main_node: Node, privacy_node: Privacy = null, adapter_node: Node = null) -> void
func tick(delta: float) -> void
func reset() -> void
func force(runtime: Node, pose := "") -> ForceResult
func on_negotiation_outcome(terminal: RefCounted) -> void
func clear_cooldown(pony: Node) -> bool
func placement_for(runtime: Node) -> PoseOptions.Placement
func debug_rows(pony: Node) -> Array[String]
```

`force()` is the debug/lab entry: it bypasses the quiet, cooldown, retry and reasoning checks but
keeps Base clearance, the placeable options and the scene-only formation rows. An empty `pose` lets
the scan's first option decide; an internal pose is rejected, never substituted.

The venue adapter is internal:

```gdscript
venue: player, mares, pony_id, region_of, camera_forward, house_at, can_approach, stand,
       ensure_stand, claim_nav, nav_owned, nav_has_target, stay, release_nav, restore_limits,
       find_bed_for, rest_front, accept_bed, player_in_bed, placement_for
```

## Data ownership

| Data | Stored where | Owner |
|---|---|---|
| Request cooldown (`request_times`) | `Mods.state("unfplap")` | `initiation/cooldowns.gd` |
| Live episode, cuddle edge, one-ask-per-cuddle, retry deadlines and scan skip reasons | memory only | this facade |
| Act history and its offer cooldown | `Mods.state("unfplap").act_history` | `shared/act_history.gd` |
| Cycle phase | runtime, derived from the day | `shared/cycle.gd` |
| The formed Mare offer and the Agreement | memory only | `negotiation/service.gd` |
| Relationship, stage, love, willingness | game save | base game |

Rules:

- No eligibility block and no request block is written to `settings.json`.
- The cooldown is the only persisted value, and only the facade reads or writes it.
- The episode never survives a world close; `reset()` closes it and clears the session maps.
- The request lease leaves this service at formation; after that the Negotiation service owns the
  hold and the terminal path.

## Episode

One episode at a time. Each phase waits on its own condition:

| Phase | Waits for | Moves to |
|---|---|---|
| `APPROACH` | arrival within `2.8 m`; cancels on quiet loss, region change, Anon moving `5 m`, nav ownership loss or `35 s` | `ARRIVE` |
| `ARRIVE` | `2 s` settle with Anon still in range | ask and handoff |
| `BED_APPROACH` | bed front within `1.4 m` or the navigator finishing its path; `25 s` cap | ask and handoff |
| `ASK` | the handoff result only; the ask line is speakable and the episode leaves this service | none |

`ASK` is a transient phase: the offer is formed, the ask line is queued and the episode clears. The
Negotiation service owns the answer from that moment; there is no reminder, deadline, clarification
or presentation in this service. Timers come only from `initiation/policy.gd`;
`tests/initiation/test_policy.gd` locks every value.

## Admission

An automatic scan runs every `0.5 s` and needs a quiet moment through the injected adapter:

- not paused, no menu panel with a free cursor, Anon not locked, flying or knocked down;
- the director idle, not in a group exchange or an approach, not hearing, and background AI
  allowed (`AI_CONFIG.background_allowed`, i.e. AI usage Full);
- no character chat in the last `45 s`.

A blocked quiet gate logs one `request scan quiet reason=<reason>` line when its reason changes.
The reason names are `unavailable`, `paused`, `mouse`, `menu`, `no_player`, `controls`, `flying`,
`knocked`, `director_missing`, `director_api`, `director_state`, `approach`, `group`, `hearing`,
`ai_usage` and `chat`.

Per mare, the scan then requires:

- the runtime idle (`state == 0`), present, awake and a stable id;
- Base clearance: the eligibility `eligible?` answer, the relationship row and availability;
- the cooldown: the history offer cooldown since `request_times[id]`, quartered in heat (the
  cooldown store owns it);
- the `30 s` retry deadline left by a failed walk-over, reasoning failure or refused handoff.

A rejected mare logs `request scan skip id=<id> reasons=<...>` when her reason set changes or
after `10 s`, so a steady cooldown does not fill the log. One mare is considered per scan, with a
rotating start index; her reasoning still decides whether she offers.

A cuddle rising edge clears that mare's cooldown and permits one ask per cuddle. The debug
actions bypass the quiet, cooldown, retry and reasoning checks but keep Base clearance, the options
and the scene-only formation rows.

## Candidates

The available options are computed **before** reasoning, from one placement pass:

| Option | Requires |
|---|---|
| Cuddle | an active cuddle, the bed under her, an offerable bed pose, and `main.offer_target()` naming her |
| Bed | an offerable bed pose, a free bed within `7 m` on the same floor and region, a finite front spot |
| Standing | an offerable standing pose, a free navigator in Anon's region, and Anon within `24 m` |

`shared/pose_options.gd` is the one builder: it filters the pose spec's `offerable`, `forms`,
`views` and `scene.sources` rows. `standing_test` and `standing_oral` are internal, never offered,
and a forced request naming them is rejected rather than falling back to another pose. A cuddle is
the only option considered while she is in the cuddle.

Each option then passes the scene-only formation rows (`runtime.scene_only_verdict` with the live
pose capability): a hard failure drops the option. The `player` and `bed_gate` rows are transient
at formation because Anon is not in position yet; the Agreement's own start waits for them.

## Reasoning

`initiation/reasoning.gd` is the Mare Initiation Reasoning: one bounded model call per scan with the
Context facts and the indexed options. It answers `{"offer": bool, "option": int}`.

- `offer: false` is not a terminal outcome: she applies the full pacing cooldown and the scan moves
  to the next mare.
- An unavailable or malformed reasoning applies the `30 s` retry.
- An in-range option is chosen; an out-of-range index is a no-offer.
- The reasoning runs after the options exist and before the walk. A missing option list means no
  call.
- Full AI is required for an automatic offer. The debug `force()` bypasses the reasoning and uses
  the requested option (or the first placeable one), so the lab works with `ai_usage=talk`.

## Privacy

The visibility is derived once at formation from `privacy/service.gd`, with the offer rule for a
bed or standing offer and the cuddle rule for a cuddle. There is no public-offer override and no
heat/public-consent visibility rule: a crowded offer is simply public. The Negotiation service owns
the live privacy sampling after formation; this service does not monitor it.

## Ask and handoff

The ask line uses `begin_greeting` through the adapter, otherwise one `queue_generated_intent` row
keyed `unfplap:request:<id>:<serial>:ask`. It uses the observed-situation context and the
generated-intent purpose, and records one `situation` world-context event. There is no negotiation
face and no presentation: she asks in the normal standing pose.

A non-cuddle offer claims the navigator (`unfplap:request:<id>`, wander off, no route) in the
approach or the ask, and asks her to stand; a cuddle keeps the session's own navigator owner. The
request's speed and pace overrides are restored before the handoff.

The handoff is one `main.form_mare_offer(fields)` call with plain values: the runtime, mare, option,
Base clearance, visibility, the request lease token and release data, the offer line and the cuddle
flag. `main` builds the typed package and calls the Negotiation service. Order:

1. form the offer; a refusal releases the request lease and sets the `30 s` retry, and no line is
   spoken;
2. speak the ask line and record the situation;
3. clear the episode. The request lease now belongs to the Negotiation service.

The offer line the Anon decision classifier reads is `The pony has just asked Anon to have sex...`
or the bed variant; it is not the generated wording.

## Cancellation

`_close_episode(retry, reason)` is the one request close path:

1. hand the navigator back with its saved owner, wander, speed and pace (when this service still
   owns it);
2. set the `30 s` retry when the close is a failure;
3. log the reason;
4. clear the episode.

A successful handoff is not a close: the episode clears and the lease moves to the Negotiation
service. `force()` closes any live episode first; `reset()` closes it, cancels the pending reasoning
scope and clears the session maps on a world close. `cancel_approach()` closes a live pre-formation
episode when a new Anon offer or hotkey interrupts her walk.

## Prompts

`initiation/prompts.gd` builds every line from a `FACTS.Request`. The facade supplies
`relation_note` and `history_note` from `main.context_facts`, which reads the eligibility snapshot,
act history and the memory cue (`docs/memory.md`). Wording mode is decided once per builder by
`policy.wording_mode(private)`: `free` speaks plainly and asks clearly, `indirect` hints while other
ponies are around. The heat line is appended only in heat and is empty otherwise.

## Debug and lab

- **Trigger bed offer** / **Trigger standing offer** call `force()` and report the reject reason.
  They need the settings page closed to advance.
- `request force ...`, `request ask ...`, `request reasoning ...`, `request outcome ...`,
  `request scan quiet reason=<reason>` and `request scan skip id=<id> reasons=<...>` are the debug
  log lines.
- **Show data** adds the `REQUEST` section: the id, cooldown readiness, the last request time, the
  effective wait, the retry left, whether a reasoning is pending, the live episode phase/pose/
  privacy and the last scan skip. The `NEGOTIATION` section beside it is the other service.
- **Clear offer cooldown** clears the aimed mare's stored cooldown, short retry and last skip.
- The lab runs with `ai_usage=talk`, so automatic offers do not fire; use the debug actions.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | eligibility | `eligibility/service.gd` | adult and consent gate |
| service | privacy | `privacy/service.gd` | live offer and cuddle privacy |
| shared | clearance | `shared/clearance.gd` | the Base clearance result |
| shared | context | `shared/context.gd` | typed Context for the reasoning |
| shared | cycle | `shared/cycle.gd` | estrus cycle |
| shared | pony_id | `shared/pony_id.gd` | stable pony id |
| shared | pose_catalog | `shared/pose_catalog.gd` | pose ids and defaults |
| shared | pose_options | `shared/pose_options.gd` | the placement and option list |
| store | act_history | `shared/act_history.gd` | stored history rows and the offer cooldown |

## Lifecycle

- Scope: world
- Constructed by: `main._ready()`
- Begin: `setup()`
- End: `reset()`/world close
- Idempotent: yes

## Tests

- `tests/initiation/test_policy.gd`: the pacing lock, cooldown, heat, retry, approach and the phase
  names.
- `tests/initiation/test_facts.gd`: the typed request defaults and independence.
- `tests/initiation/test_prompts.gd`: the private/public ask, heat, the notes and the situation
  text.
- `tests/initiation/test_reasoning.gd`: the payload shape and the reply parser.
- `tests/initiation/test_cooldowns.gd`: the stored clock, the history wait, the heat shortening
  and the set/clear round trip.
- `tests/initiation/test_initiation_api.gd`: the facade through `force()` and the scan with a fake
  adapter, privacy and runtime — Base clearance and the option filters, the reasoning no/yes and
  failure, the walk and the arrival, the ask line and its fallback, the situation record, the
  handoff and a refused handoff, the cuddle attention hold, the outcome pacing, `clear_cooldown`,
  the debug rows and the scan logs.
- `tests/negotiation/test_adapter.gd`: the injected bridge this service calls.
- `tests/test_source_hygiene.gd`: the pure-core boundary, the facade-only preload rule, the adapter
  private-access boundary and this contract's presence.

## Known limits

- The adapter reads stock director fields (`_player_text`, `_held_text`, `_now`, `characters`) and
  the venue adapter reads stock navigator and bed-rest fields. A game change can remove them; every
  read is guarded and the offer simply stops.
- A reasoning call is a model request; an unavailable model or no configured endpoint means no
  automatic offer. The debug actions bypass it.
- A request is not persisted: a save during an episode resumes with no episode and no navigator
  lease.
- Automatic offers need AI usage Full; the lab's debug actions are the supported way to see one.
- The standing offer requires an adult mare who is an eligibility target and a free navigator;
  another pony's task or lease is a reason to skip her, not to wait.
- The request lease is best effort: a re-task is the Negotiation service's `target_left`, not this
  service's close.
