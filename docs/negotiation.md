# Negotiation

The Act Negotiation: one process from the first offer to the Agreement and the act start or
termination. This service owns the Anon offer, the Anon decision, the Mare response, the global
lock and the Agreement package. The Proactive service forms a Mare offer; the Act service consumes
the Agreement handle.

## Scope

This contract covers:

- Base clearance and pose options for the Anon offer and the hotkey;
- the Anon classifier, the Anon decision and the Mare Response Reasoning;
- the live privacy sampling and the derived offer visibility;
- the hold claim, transfer, keep and release;
- the global lock across the offer and the Agreement window;
- the Agreement package, its TTL, its opaque handle and its one close path;
- the bridge to the live world: the typed host, the Context facts, the global Anon-offer watch,
  the react line and the two terminal handoffs;
- the terminal outcome to the Proactive service;
- the debug rows.

It does not cover pacing, the approach, the Mare Initiation Reasoning, the bounded classifier, the
presentation, the act start, the scene rows or the pose placement gate. Those belong to
`docs/initiation.md`, `docs/poses.md`, `docs/runtime.md` and `docs/scene_gate.md`.

## Ownership

`negotiation/service.gd` (world scope) owns:

- the one live Act Negotiation: phase, offer, generation, TTL and lock;
- the Agreement package and its handle;
- the classifier/reasoning scopes and their cancellation;
- the terminal outcome and the offer cooldown;
- the typed `Host` it runs on and the one adapter (`negotiation/adapter.gd`) that answers the
  model calls;
- the Agreement handoff: the standing presentation, the one react line and the offer clear.

`negotiation/agreement.gd` is the pure package and handle. The service is its only writer.
`negotiation/prompts.gd` is the pure model request layer: the request kinds, the payload builders
and the reply parsers (the instruction text is the prompt document's). `negotiation/host.gd` is the
service's private bridge to the live world (see `## Bridge`). The bounded classifier belongs to the
Proactive service; this service
asks its facade for the node the model calls run on. The Act service gets only the handle.

## Internal API

```gdscript
enum Phase { NONE, OFFERED, AGREEMENT }
enum Outcome { ACCEPTED, REFUSED, EXPIRED, INTERRUPTED, START_FAILED, NO_OFFER, OCCUPIED, STARTED }

class FormView:       form, view
class MareOffer:      runtime, pony, option, base, private, hold_token, hold_old_wander, line, cuddle
class Request:        kind, text, line, context, options
class Reply:          answer, option_index, failed, out_of_range
class Terminal:       pony, pony_id, outcome, reason, trigger, cooldown_s
class Host:           the named callbacks below

bind(eligibility: Eligibility, memory: Memory, privacy: Privacy, initiation: Node, offer: Node)
  -> void
setup(host: Host) -> void
on_world(host: Node) -> void
on_world_closed() -> void
adapter() -> ADAPTER
context(pony: Node) -> Context
form_view() -> FormView
tick(delta: float) -> void
phase() -> Phase
is_locked() -> bool
handle() -> Agreement.Handle
agreement() -> Agreement.Package
begin_mare_offer(offer: MareOffer) -> bool
begin_anon_offer(runtime: Node, text: String) -> bool
report(handle: Handle, started: bool) -> bool
cancel(handle: Handle, reason: String) -> bool
hotkey_handle(runtime: Node, option: PoseOptions.Option) -> Handle
interrupt_for_hotkey() -> bool
debug_rows(pony: Node) -> Array[String]
```

`bind()` is the entry's one call: the facades it reads are handed over once and the service builds
the adapter and the `Host` from them. `on_world()` re-reads the eligibility service the entry
rebuilds on every world enter, rebuilds the `Host` and drops the previous world's watch. `setup()`
takes a `Host` directly and is the seam the suites use; the entry never calls it.

`context(pony)` and `form_view()` are the two snapshots the Proactive service's reasoning reads, so
both stages judge one mare from the same facts.

The host callbacks are, in order:

| Field | Signature | Purpose |
|---|---|---|
| `now` | `() -> float` | the service clock |
| `eligible` | `(pony) -> bool` | the eligibility service's `eligible?` |
| `relationship_ok` | `(pony) -> bool` | the live relationship, romance and floor |
| `context_facts` | `(pony) -> Dictionary` | plain `shared/context.gd` facts |
| `privacy_private` | `(pony, cuddle) -> bool` | the privacy provider |
| `placement_for` | `(runtime) -> PoseOptions.Placement` | the live placement facts |
| `pose_placed` | `(runtime, PoseOptions.Option) -> bool` | the live scene-only placement re-check before an Agreement forms |
| `form_view` | `() -> FormView` | the player's form and display |
| `hold_for` | `(runtime) -> RefCounted` | the per-pony `scene_hold/service.gd` ledger |
| `classify` | `(PROMPTS.Request, scope, done) -> bool` | the dialogue classifier; `done` gets a `PROMPTS.Reply` |
| `reason` | `(PROMPTS.Request, scope, done) -> bool` | the Mare Response Reasoning |
| `await_answer` | `(pony, scope, done) -> bool` | the first new line from the target |
| `cancel_scope` | `(scope) -> void` | cancels one model scope |
| `toast` | `(text) -> void` | player feedback through the HUD toast line |
| `react` | `(pony, reason) -> void` | the shared interruption line |
| `on_outcome` | `(Terminal) -> void` | the Proactive pacing |
| `on_agreement` | `(Handle) -> void` | the Agreement handoff: the standing presentation and the offer clear |

A model callback is called once. A late result after a terminal transition is ignored by the
generation token.

## Director and model host

`negotiation/adapter.gd` is the one director bridge and model host. This service builds one
instance as its child in `bind()` and wires the `Host` model callbacks to it; the Proactive service
takes the same instance through `adapter()` and does not keep a second copy. It owns every private
director read (`state`, `config`, `_player_text`, `_held_text`, the group, the approach and hearing
state), the transcript hook, one answer watch and the bounded classifier calls. No service reads
the director directly; the classifier is the Proactive service's, and the adapter reaches it only
through `classifier_source`.

The bridge methods are the pacing reads and the director writes: `quiet(chat_gap_s)`,
`quiet_reason(chat_gap_s)`, `idle()`, `begin_greeting()`, `queue()`, `cancel_keys()`,
`record_situation()`, `player_name()`, `pony_speaking()`.

The model methods are `classify(request, scope, done)` and `reason(request, scope, done)`, which
turn a `PROMPTS.Request` into the instruction and payload, call the shared classifier once and
parse the reply into a `PROMPTS.Reply`; `complete_raw(system, payload, scope, done)` is the raw
path for the Proactive's Mare Initiation Reasoning, which owns its own prompt; `await_answer()`
baselines the director's player-line fields and reports the first new line; `cancel_scope()`
drops the watch and cancels the classifier scope together.

The shared classifier (`initiation/classifier.gd`, owned by the Proactive service) bounds every
call: one client, one queue, one deadline, `input_bytes` and `output_tokens` limits, a
private-reasoning room on top of the visible output budget, and a raw completion that reports the
text and the provider error without parsing it. The budget and deadline are sized for a reasoning
model: a call that exhausts the budget returns no JSON and the route reports
`NoOffer(classifier_unavailable)`. The adapter reaches it through `classifier_source`, a callable
the service sets to the Proactive facade's `classifier_node()`; the adapter imports no classifier
file, and the Proactive's model calls and both reasoning stages use the same node.

## Bridge

`negotiation/host.gd` is the private bridge between this service and the live world. It owns what
used to be the entry's assembly:

- the `Host` callbacks that read another service or the scene: `now`, `eligible`,
  `relationship_ok`, `context_facts`, `privacy_private`, `placement_for`, `pose_placed`,
  `hold_for`, `classify`, `reason`, `await_answer`, `cancel_scope` and `toast`;
- the Context facts both reasoning stages read: the eligibility snapshot, the act history, the
  world-context mood and the relationship note;
- the global Anon-offer watch, the runtime state guard and the mare the game's conversation
  target names;
- the adapter's model calls and the world-context situation record.

It reads only service facades, `WORLD` and the `GAME` accessors, and the fields the entry binds
once through `bind()`: `service` (this facade), `adapter`, `eligibility`, `memory`, `privacy`,
`initiation` and `offer`. `initiation` and `offer` are plain nodes because each of them preloads
this facade; everything else is the typed facade. `eligibility` is the one field a world enter
rebinds, because the entry rebuilds that service.

The watch is armed by `tick()`, which is the entry's idle frame: the exchange's TTL and privacy
sample first, then the bridge's watch as its own `entry_watch` perf chunk. The watch is armed only
while no act and no negotiation own the frame, and the previous world's watch is dropped on
`on_world()`.

## Process

The routes:

| Route | Formed by | Answer |
|---|---|---|
| Mare offer | the Proactive service (`begin_mare_offer`) | the Anon decision classifier |
| Anon offer | this service (`begin_anon_offer`) | the Mare Response Reasoning |
| Hotkey | the Act service (`hotkey_handle`) | accepted; no buck |

The Anon offer is formed from the first new player line while Anon talks to a mare. This service
arms the adapter's global watch only while no negotiation and no act is live; the adapter captures
the first new line and reports it once the director is idle again, so the classifier never races
her reply to the same line. The bridge resolves the mare from the game's conversation target
(`conversation_target` bound to Anon), drops an empty line, a line over `MAX_LINE`, a locked
negotiation, an unavailable classifier and a busy runtime, cancels an in-flight proactive approach
that has not formed a Mare offer, and calls `begin_anon_offer(runtime, line)`. A line that is not a
clear offer is silent: it reports no terminal outcome, shows no toast and writes no cooldown, so
the Proactive pacing sees nothing.

1. Base clearance: `eligible?`, `relationship_ok` and availability; a failure is `NoOffer`.
2. Pose options from `shared/pose_options.gd`; an empty list is `NoOffer`. The service stores the
   exact list it sends to the classifier on that offer.
3. The classifier picks intent and one option index; the reply indexes the captured list, never a
   recomputed one. A missing or non-integer option is `NoOffer(classifier_unavailable)`; an index
   outside the captured list is `NoOffer(no_context_pose)` with log and toast; a genuine non-offer
   closes silently.
4. The live placement check runs on the chosen option before the hold claim; a failure is
   `Interrupted(pose)` and forms no Agreement.
5. The negotiation hold is claimed (`claim_negotiation`); a failure is `Occupied`.
6. Visibility is derived from `privacy_private` with the offer or cuddle rule.
7. The Mare Response Reasoning answers with Context plus the offer text and option; a failure is
   `Refused`; a plain refusal writes the offer cooldown signal; a counter-offer writes none and
   closes with one generated line.

The Mare offer:

1. The Proactive service passes the already-decided Base clearance, option, visibility and hold.
2. The service owns the exchange: the hold is transferred (`transfer_nav`) or claimed.
3. The first new line from the conversation target goes to the Anon decision classifier; an
   ambiguous line is `Refused`.
4. A yes runs the live placement check and then forms the Agreement; a refusal writes the
   cooldown signal; a counter-offer writes none and closes with one generated line.

The hotkey never forms an offer. `hotkey_handle` returns the live Agreement only for the same mare
and the exact `(pose, source, bed, cuddle)` option; `interrupt_for_hotkey` ends any live
negotiation with `Interrupted(hotkey)`.

## Decisions

| Request | Instruction | Payload | Parse |
|---|---|---|---|
| Anon offer | `classify.anon_offer` | the player line, the indexed options, Context | `{"offer","option"}`; a clear offer returns the raw index and an `out_of_range` marker when it is outside the captured list |
| Anon decision | `classify.anon_decision` | the Mare offer line, the player reply | `{"answer"}`; `unclear` is a refusal, malformed is a failure |
| Mare response | `classify.mare_response` | the player offer, the option, Context | `{"answer"}`; `unclear` or malformed is a failure |

`negotiation/prompts.gd` owns the request, the payload and the parser; the instruction prose is the
`classify` group in `settings/prompts.json` (`docs/prompts.md`), and the host adapter owns the LLM
call and the cancel scope. A parsed failure maps to `NoOffer` for the classifier and `Refused` for
the answer, with no cooldown. A clear offer with an out-of-list index maps to
`NoOffer(no_context_pose)`; the service validates the index against the list it captured at
request time.

## Agreement

The Proactive service builds the typed `MareOffer` from its decided values and calls
`begin_mare_offer`. The Proactive owns the ask line and the request lease until formation; the
Negotiation service owns them after it.

`negotiation/agreement.gd:Package` is the frozen package:

- id and generation, the mare (node and stable id);
- the pose option `(pose, source, bed, cuddle)`;
- the visibility boolean;
- the Base clearance result, the Context, the answer;
- the frozen pose capability (`pose_profile_ok`, `pose_source_ok`);
- the acceptance time and the 120 s TTL;
- the hold token and the release data;
- the trigger, the classifier scope and the offer line.

The package is immutable: the service builds it once and never rewrites it. The Act service gets
`Handle`: the id, the generation, the operational frozen values, and one `cancel(reason)` callback
whose bound arguments make a late handle harmless. The offer service, the Act service's only
caller, reports the `runtime.gate.start_agreement()` answer as `Started`/`StartFailed` through
`report(handle, started)`; the service closes the Agreement, releases the lock and releases the
hold unless the Act adopted it on `Started`. The service's Agreement handoff starts the standing
presentation (act-owned) and clears the shared offer window, so the hint goes with the Agreement;
the act key and the auto-start consume the handle through `runtime.gate.start_agreement()`; a wait keeps
the Agreement live. A handle whose runtime is gone is cancelled with `cancelled`.

Formation runs the live placement re-check (`Host.pose_placed`, the scene-only rows) after the
positive answer and before the package is built. A moved bed or a lost standing spot is
`Interrupted(pose)`: no Agreement forms and the offer hold is released. The auto-start samples a
private Agreement's visibility freshly at the offer service's `0.25 s` clock; if it is now public
it cancels with `privacy`. The hotkey's exact match starts at once and does not resample: the
live Agreement's own visibility wins for that press.

Close reasons: `Started`, `StartFailed`, `Expired`, `Interrupted` (`privacy`, `pose`, `hotkey`,
`target_left`, `cancelled`). Every close releases the lock. Only `Started` leaves the adopted hold
to the act.

## Lock

One Act Negotiation at a time, including the Agreement window. A live offer or Agreement blocks a
new Mare offer, Anon offer or proactive approach; the Proactive scan stays quiet while
`is_locked()` answers true, and an attempt that still reaches the service is reported `NoOffer`
with reason `locked`, logged and toasted. The hotkey is the only break. The lock lasts at most
240 s (120 s negotiation + 120 s Agreement).

## Privacy

The service samples the provider every 0.5 s while a private offer or Agreement lives. A public
offer never subscribes: its visibility was derived at formation and stays public. A private offer
that loses privacy is `Interrupted(privacy)` in the negotiation or the Agreement; the state ends
immediately, the shared reaction helper queues the line, and no cooldown is written. The
auto-start takes its own fresh sample immediately before a private Agreement starts; a loss there
cancels the Agreement with the same `privacy` reason and reaction.

## Hold

The bridge supplies the per-pony `scene_hold` ledger from the runtime's `hold_handle()`. The
service claims `unfplap:negotiation:<id>` for an Anon offer, or takes the Proactive request's
token over for a Mare offer, then takes the physical affection hold. A cuddle offer takes the
attention and affection hold only (`claim_attention`): the cuddle session keeps its own navigator
lease. Every tick it re-asserts the navigator and keeps Anon as the conversation target. A lost
owner, a missing ledger or a target outside Anon's subtree is `Interrupted(target_left)`. Every
terminal outcome calls `release_negotiation()`; `Started` leaves the adopted hold to the act.

## Feedback and cooldown

Log + toast for `NoOffer`, `Occupied`, lock-blocked and every terminal outcome. A genuine
non-offer is the exception for the player: no outcome, no toast and no pacing retry; the debug log
still records `negotiation non-offer` and `state=none reason=non_offer`, so it is diagnosable
without changing the pacing. `COOLDOWN_S` is the service's cooldown signal on a plain decline or
an acceptance; the Proactive's stored history cooldown is the effective per-mare wait. A
counter-offer, expiry, interruption and start failure write none. A counter-offer also queues one
short generated line declining the place or timing while still wanting him; a plain refusal keeps
the base-game dialogue and no extra line; privacy keeps its interruption line. The one react line
is queued as `unfplap:negotiation:react:<usec>` and drops itself when the mare left the tree. The
tolerance stop's `stop_until` is separate.

## Data ownership

The live negotiation and the Agreement live in memory. Nothing is persisted. The offer cooldown
belongs to the Proactive service's cooldown store; this service passes `Terminal.cooldown_s` and
the Proactive applies it. No reasoning record and no history write happens on a failure.

## Lifecycle

- Scope: world
- Constructed by: the entry's service list (`_build_services()`)
- Begin: `bind()`/`on_world(host)`; `setup(host)` in the suites
- End: `on_world_closed()` on a world enter or close
- Idempotent: yes

## Settings

No setting is read directly. The bridge's `relationship_ok` reads the Promiscuity floor, and its
`context_facts` carries heat, public preference and the rest as Context. The retired
`features.act_public_offer` and `relationship.sex_start` are never consulted.

## Controls and debug

- No hotkey and no face. The Act key is the hotkey; this service only matches an Agreement or
  interrupts for it.
- The `negotiation ...` debug log lines are `state=offered|agreement|none`, `offer`, `hold claim`,
  `hold lost`, `privacy lost`, `hotkey match|interrupt`, `answer`, `non-offer`, `outcome`,
  `agreement`, `refused`, `expired`, `interrupted`, `start failed`, `started`, `blocked` and
  `occupied`.
- The classifier runs and results are `classifier start` / `classifier result` from
  `negotiation/adapter.gd`; the result carries the kind, scope, answer, option index, failure and
  the trimmed raw reply/error.
- `debug_rows()` adds the `NEGOTIATION` Show data section: phase, lock, live offer/Agreement and
  the TTL.
- **Trigger Anon offer** (Debug → Actions / the Mare wheel) forms an Anon offer for the aimed mare
  as if Anon had just asked her. **Clear offer cooldown** is the Proactive service's action; the
  `NEGOTIATION` Show data section is the live state.

## Dependencies

### Uses
| service | world | `world/service.gd` | menu, player and world context |

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| service | eligibility | `eligibility/service.gd` | the act target, the relationship row and the Context facts |
| service | hud | `hud/service.gd` | the one toast sink |
| service | memory | `memory/service.gd` | the relationship note in Context |
| service | ponies | `ponies/service.gd` | the runtime of the outcome, the Agreement and the mare the watch asks |
| service | privacy | `privacy/service.gd` | live offer and cuddle privacy |
| service | world | `world/game.gd` | the director's clock, sub-systems and model configuration |
| shared | clearance | `shared/clearance.gd` | Base clearance result |
| shared | context | `shared/context.gd` | typed Context snapshot |
| shared | defaults_data | `shared/defaults_data.gd` | the shipped prompt document |
| shared | log | `shared/log.gd` | log sink |
| shared | perf | `shared/perf.gd` | one profiler |
| shared | pony_id | `shared/pony_id.gd` | stable mare id |
| shared | pose_catalog | `shared/pose_catalog.gd` | the standing pose the Agreement presents |
| shared | pose_options | `shared/pose_options.gd` | the available options and exact match |
| shared | pose_placement | `shared/pose_placement.gd` | the frozen source capability |
| shared | pose_specs | `shared/pose_specs.gd` | the frozen pose capability |
| shared | prompt_text | `shared/prompt_text.gd` | the prompt renderer |
| shared | relationship_cue | `shared/relationship_cue.gd` | the relationship prompt note |
| store | act_history | `shared/act_history.gd` | the offer history note |

## Tests

- `tests/negotiation/test_agreement.gd`: the package fields, TTL, expiry, exact match and the
  handle.
- `tests/negotiation/test_service.gd`: the Anon offer, the captured option list, the live
  placement re-check, the Anon decision, the Mare response, the silent non-offer, the counter-offer
  line, the failure semantics, the lock, the hold, privacy, `target_left`, the cooldown table, the
  Agreement handle, `Started`/`StartFailed` and the stale-handle guard, with a fake host and model.
- `tests/negotiation/test_prompts.gd`: the payload shape, the request dispatch and the three
  reply parsers, including the Anon offer's out-of-range marker.
- `tests/negotiation/test_adapter.gd`: the quiet gate, the queue and the situation record, the
  answer watch and its cancel, the three model calls and the raw path, with a fake director and
  classifier source.
- `tests/negotiation/test_host.gd`: the bridge — the host callbacks resolving to the service, the
  Context and form view the Proactive reads, the watch arming only while idle and unlocked, the
  Anon-line guard table, the react purpose per close reason, the outcome routing and the
  Agreement handoff.

## Known limits

- The model calls are the host adapters' work; this service only sees the typed `Decision`.
- The hold is best effort: a re-task or an attention reassignment ends the negotiation with
  `target_left`.
- Both offer routes are live. The Agreement auto-starts when the presentation settles and the
  scene-only rows pass; the act key consumes an exact match earlier and skips the presentation.
