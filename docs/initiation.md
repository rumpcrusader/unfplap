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
| `initiation/service.gd` | facade: scan, admission, Base clearance, the one attempt object, the single route entry and its reject reasons, phase dispatch, the reasoning call, the ask and the handoff |
| `initiation/facts.gd` | pure typed `Request`: the plain values the wording reads |
| `initiation/policy.gd` | pure pacing: scan, cooldown, heat, retry, approach, bed search, wording mode and the phase names |
| `initiation/reasoning.gd` | pure Mare Initiation Reasoning: the instruction, the payload and the parser |
| `initiation/prompts.gd` | pure wording: the ask context, the ask purpose, the situation text and the heat line |
| `initiation/cooldowns.gd` | request cooldown store: `request_times`, the history wait and the heat shortening |
| `initiation/venue.gd` | scene adapter: the only reader of navigators, posture and beds, and the builder of the placement facts |
| `initiation/classifier.gd` | the bounded classifier this service owns: one client, one queue, one deadline and the two reasoning budgets |
| `privacy/api.gd` | world privacy provider: the house, the other mares, the radius and the one offer/cuddle predicate |
| `negotiation/adapter.gd` | the director bridge and model host the Negotiation service owns and hands over: the quiet gate, the ask queue, the situation record, the reasoning call |
| `negotiation/service.gd` | the Act Negotiation: the answer, privacy, the Agreement and the global lock |
| `docs/initiation.md` | this contract |
| `tests/initiation/` | the pure rules, facts, reasoning and wording suites, plus the facade API suite |

One attempt type carries both the offer candidate and the live route; there is no separate episode
object. `_begin_route` is the single entry for the walk-to-Anon, bed-lead and ask-now routes, and
every route starter that ends before the ask returns a short reject reason.

The purity boundary is deliberate:

- `facts.gd`, `policy.gd`, `prompts.gd` and `reasoning.gd` have no `Node`, tree, time, file,
  `Settings`, scene or game preload. They take plain values and return plain values or strings.
- `venue.gd` owns `Navigator` fields (`command_owner`, `wander_enabled`, `command_speed_limit`,
  `command_pace_target`, `reserved_by`, `_has_target`), `request_posture`/`posture_status`, the bed
  rest (`_front_for`, `_mare_fits`, `_guest`, `_sleeper`), the player seat, the `couches` group and
  `WorldLayout`. It also builds the placement facts the option builder consumes.
- The director bridge is the `negotiation/adapter.gd` the Negotiation service owns and hands over
  through its facade; this service never reads the director. The bounded classifier is this
  service's own (`classifier.gd`), created in `setup()`: the Negotiation's adapter and both
  reasoning stages make every model call on it, and no other service imports it. Its model client
  comes from the director view, so the classifier imports no base-game module.
- The facade is the only file that preloads `eligibility/service.gd`, `act_gate/service.gd`,
  `privacy/api.gd`,
  `negotiation/service.gd`, `shared/clearance.gd`, `shared/context.gd`, `shared/pose_options.gd`,
  `shared/pose_catalog.gd` and `shared/cycle.gd`; `cooldowns.gd` preloads
  `shared/act_history.gd`.
- No file outside `initiation/service.gd` and `initiation/` preloads `initiation/*` except the
  orchestrator, which owns the service.
- The entry's service list creates the service, wires it once (the live `eligibility` and
  `act_gate` instances and its privacy, Negotiation and offer peers), runs its peerless `setup()`
  and drives it: `tick`, `on_world`/`on_world_closed`, `force`,
  `cancel_approach`, `placement_for` and the outcome handoff. `runtime.gd` exposes
  `cuddle_active()` and the scene-only verdict; the offer facade answers which pony the act key
  would start (`docs/offer.md`), and the Negotiation facade answers the lock, the form view and
  the Context.

## Facade

`initiation/service.gd` is the proactive request service.

`eligibility` is the entry's live identity instance and `act_gate` the live dynamic one, both
wired once at construction and read for the whole process; the identity target comes from
`eligibility` and the Base clearance relationship row from `act_gate`. `classifier_node()` is the
node the Negotiation adapter runs its one bounded call on, and
`classifier_available()` is the Anon-offer watch's gate. `on_world` and `on_world_closed` are the
same close: a world enter and a world close both end every scope, because a scope belongs to the
world that is gone.

`force()` is the debug/lab entry: it bypasses the quiet, cooldown, retry and reasoning checks but
keeps Base clearance, the placeable options and the scene-only formation rows. An empty `pose` lets
the scan's first option decide; an internal pose is rejected, never substituted. A route that ends
before the ask reports its close reason in `reject`.

The venue adapter is internal:

`can_approach` answers a plain bool without reject reasons, and `claim_nav` always stops her
before taking ownership. `ensure_stand` is the only posture request the facade uses.

## Data ownership

| Data | Stored where | Owner |
|---|---|---|
| Request cooldown (`request_times`) | `Mods.state("unfplap")` | `initiation/cooldowns.gd` |
| The live attempt, the cuddle edge and one-ask map, retry deadlines and scan skip reasons | memory only | this facade |
| Act history and its offer cooldown | `Mods.state("unfplap").act_history` | `shared/act_history.gd` |
| Cycle phase | runtime, derived from the day | `shared/cycle.gd` |
| The formed Mare offer and the Agreement | memory only | `negotiation/service.gd` |
| Relationship, stage, love, willingness | game save | base game |

Rules:

- No eligibility block and no request block is written to `settings.json`.
- The cooldown is the only persisted value; `initiation/cooldowns.gd` is its only reader and
  writer.
- The live attempt never survives a world close; `on_world_closed()` closes it and clears the session maps.
- The request lease leaves this service at formation; after that the Negotiation service owns the
  hold and the terminal path.

## Episode

One attempt at a time. The `Candidate` is the live attempt once `_begin_route` starts it: the same
object carries the offer fields and the route fields (`serial`, `phase`, `started_at`,
`arrive_until`, `token`, the navigator lease values, `player_start`, `region` and `bed_front`). Each
phase waits on its own condition:

| Phase | Waits for | Moves to |
|---|---|---|
| `APPROACH` | arrival within `2.8 m`; cancels on quiet loss, region change, Anon moving `5 m`, nav ownership loss or `35 s` | `ARRIVE` |
| `ARRIVE` | `2 s` settle with Anon still in range | ask and handoff |
| `BED_APPROACH` | bed front within `1.4 m` or the navigator finishing its path; `25 s` cap | ask and handoff |
| `ASK` | the handoff result only; the ask line is speakable and the attempt leaves this service | none |

`ASK` is a transient label: `_ask_now` sets it, the handoff runs in the same call and
`_tick_episode` has no branch for it. A successful handoff clears the attempt and the Negotiation
service owns the answer from that moment; there is no reminder, deadline, clarification or
presentation in this service. Timers come only from `initiation/policy.gd`;
`tests/initiation/test_policy.gd` locks every value.

## Admission

An automatic scan runs every `0.5 s` and needs a quiet moment through the Negotiation's adapter.
While an Act Negotiation owns the lock (`negotiation.is_locked()`), the scan stays quiet: no second
mare starts a reasoning call, a walk or a handoff.

- not paused, no menu panel with a free cursor, Anon not locked, flying or knocked down;
- the director idle, not in a group exchange or an approach, not hearing, and background AI
  allowed (the director's own `background_allowed`, i.e. AI usage Full);
- no character chat in the last `45 s`.

A blocked quiet gate logs one `request scan quiet reason=<reason>` line when its reason changes.
The reason names are `unavailable`, `paused`, `mouse`, `menu`, `no_player`, `controls`, `flying`,
`knocked`, `director_missing`, `director_api`, `director_state`, `approach`, `group`, `hearing`,
`ai_usage` and `chat`.

Per mare, the scan then requires:

- the runtime idle (`state == 0`), present, awake and a stable id;
- Base clearance: the eligibility `eligible?` answer, the act gate's relationship row and
  availability;
- the cooldown: the history offer cooldown since `request_times[id]`, quartered in heat (the
  cooldown store owns it);
- the `30 s` retry deadline left by a failed route, reasoning failure or refused handoff.

The Negotiation's `cooldown_s` on a plain decline or acceptance is a pacing signal only; this
stored history cooldown is the effective per-mare wait.

A rejected mare logs `request scan skip id=<id> reasons=<...>` when her reason set changes or
after `10 s`, so a steady cooldown does not fill the log. One mare is reasoned about per scan, with
a rotating start index; the scan may still assemble options for several mares, and her reasoning
decides whether she offers.

A cuddle rising edge clears that mare's cooldown and permits one ask per cuddle. The debug
actions bypass the quiet, cooldown, retry and reasoning checks but keep Base clearance, the options
and the scene-only formation rows.

## Candidates

The available options are computed **before** reasoning, from one placement pass:

| Option | Requires |
|---|---|
| Cuddle | an active cuddle, the bed under her, an offerable bed pose, and `offer.offer_target()` naming her |
| Bed | an offerable bed pose, a free bed within `7 m` on the same floor and region, a finite front spot |
| Standing | an offerable standing pose, a free navigator in Anon's region, and Anon within the `24 m` standing reach |

`POLICY.STANDING_RANGE_M` is that standing offer's reach, not the walk distance.

`shared/pose_options.gd` is the one builder: it filters the pose spec's `offerable`, `forms`,
`views` and `scene.sources` rows. `standing_test` and `standing_oral` are internal, never offered,
and a forced request naming them is rejected rather than falling back to another pose. A cuddle is
the only option considered while she is in the cuddle.

Each option then passes the scene-only formation rows (`runtime.scene.scene_only_verdict` with the live
pose capability): a hard failure drops the option. The `player` and `bed_gate` rows are transient
at formation because Anon is not in position yet; the Agreement's own start waits for them. A
candidate with no game root or no runtime is rejected as `no_world`.

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

The visibility is derived once at formation from `privacy/api.gd`, with the offer rule for a
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

The handoff builds the Negotiation facade's typed `MareOffer` from the decided values: the
runtime, mare, option, Base clearance, visibility, the request lease token and release data, the
offer line and the cuddle flag. `begin_mare_offer(offer)` is the one call; the Negotiation service
owns the typed package from there. Order:

1. form the offer; a refusal releases the request lease and sets the `30 s` retry, and no line is
   spoken;
2. speak the ask line and record the situation;
3. clear the attempt. The request lease now belongs to the Negotiation service.

The offer line the Anon decision classifier reads is `The pony has just asked Anon to have sex...`
or the bed variant; it is not the generated wording.

The reverse route is the Negotiation's Anon offer. A normal line that is not an offer closes
silently: no terminal outcome reaches `on_negotiation_outcome`, so no pacing retry or cooldown is
written. A plain decline or an acceptance reports the Negotiation's `COOLDOWN_S` signal; the
stored history cooldown above remains the effective per-mare wait.

## Cancellation

`_close_episode(reason)` is the one request close path and returns the reason:

1. hand the navigator back with its saved owner, wander, speed and pace (when this service still
   owns it);
2. set the `30 s` retry when the close has a reason — any non-empty reason, including `force` and
   `interrupted`; a silent `on_world_closed()` close stamps none;
3. log the reason;
4. clear the attempt.

A successful handoff is not a close: the attempt clears and the lease moves to the Negotiation
service. `force()` closes any live attempt first; `on_world_closed()` closes it, cancels the
pending reasoning scope and clears the session maps on a world enter or close. `cancel_approach()` closes a live pre-formation
attempt when a new Anon offer or hotkey interrupts her walk.

## Prompts

`initiation/prompts.gd` builds every line from a `FACTS.Request`, and the words are the `ask` nodes
in `settings/prompts.json` (`docs/prompts.md`). This file chooses the branch: the pose opening, the
privacy mode and the heat line. The facade supplies
`relation_note` and `history_note` from `negotiation.context()`, the Negotiation's one Context
snapshot of the act gate's facts, act history and the memory cue (`docs/memory.md`); the
reasoning payload carries the same Context. Wording mode is decided once per builder by
`policy.wording_mode(private)`: `free` speaks plainly and asks clearly, `indirect` hints while other
ponies are around. The heat line is appended only in heat and is empty otherwise.

## Debug and lab

- **Trigger bed offer** / **Trigger standing offer** call `force()` and report `reject`; a pre-ask
  route failure logs its close reason. They need the settings page closed to advance.
- `request force ...`, `request force reject ...`, `request end ...`, `request ask ...` and the
  reasoning lines `request reasoning start|result|yes|no|failed|unavailable`; also
  `request outcome ... cooldown=...`, `request scan quiet reason=<reason>` and
  `request scan skip id=<id> reasons=<...>` are the debug log lines. The `result` line carries the
  parsed offer, option index, failure and the trimmed raw reply/error.
- **Show data** adds the `REQUEST` section: the id, cooldown readiness, the last request time, the
  effective wait, the retry left, whether a reasoning is pending, the live attempt phase, pose and
  privacy, and the last scan skip. The `NEGOTIATION` section beside it is the other service.
- **Clear offer cooldown** clears the aimed mare's stored cooldown, short retry and last skip.
- The lab runs with `ai_usage=talk`, so automatic offers do not fire; use the debug actions.

## Known limits

- The adapter reads stock director fields (`_player_text`, `_held_text`, `_now`, `characters`) and
  the venue adapter reads stock navigator fields through the `Navigator` view and bed-rest fields
  through the `Bed` view. A game change can remove them; every read is guarded and the offer
  simply stops.
- A reasoning call is a model request; an unavailable model or no configured endpoint means no
  automatic offer. The debug actions bypass it.
- A request is not persisted: a save during an attempt resumes with no attempt and no navigator
  lease.
- Automatic offers need AI usage Full; the lab's debug actions are the supported way to see one.
- The standing offer requires an adult mare who is an eligibility target and a free navigator;
  another pony's task or lease is a reason to skip her, not to wait.
- The request lease is best effort: a re-task is the Negotiation service's `target_left`, not this
  service's close.
