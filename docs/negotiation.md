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

`negotiation/api.gd` (world scope) owns:

- the one live Act Negotiation: phase, offer, generation, TTL and lock;
- the Agreement package and its handle;
- the classifier/reasoning scopes and their cancellation;
- the terminal outcome and the offer cooldown;
- the typed `Host` it runs on and the one adapter (`negotiation/adapter.gd`) that answers the
  model calls;
- the Agreement handoff: the standing presentation, the one react line and the offer clear.

`shared/agreement.gd` is the pure package and handle. The service is its only writer.
`negotiation/prompts.gd` is the pure model request layer: the request kinds, the payload builders
and the reply parsers (the instruction text is the prompt document's). `negotiation/host.gd` is the
service's private bridge to the live world (see `## Bridge`). The bounded classifier belongs to the
Proactive service; this service
asks its facade for the node the model calls run on. The Act service gets only the handle.

## Facade

`wire()` is the entry's one call: the facades it reads are handed over once and the service builds
the adapter and the `Host` from them. `on_world()` closes the previous world, rebuilds the `Host` for
the new one and drops its watch; it rebinds no peer. `setup()` takes a `Host` directly and is the
seam the suites use; the entry never calls it.

`context(pony)` and `form_view()` are the two snapshots the Proactive service's reasoning reads, so
both stages judge one mare from the same facts.

## Host boundary

The host callbacks are, in order:

| Field | Signature | Purpose |
|---|---|---|
| `now` | `() -> float` | the service clock |
| `eligible` | `(pony) -> bool` | the eligibility service's `eligible?` |
| `relationship_ok` | `(pony) -> bool` | the act gate's live relationship, romance and floor |
| `context_facts` | `(pony) -> Dictionary` | plain `shared/context.gd` facts |
| `privacy_private` | `(pony, cuddle) -> bool` | the privacy provider |
| `placement_for` | `(runtime) -> PoseOptions.Placement` | the live placement facts |
| `pose_placed` | `(runtime, PoseOptions.Option) -> bool` | the live scene-only placement re-check before an Agreement forms |
| `form_view` | `() -> FormView` | the player's form and display |
| `hold_for` | `(runtime) -> Node` | the per-pony `scene_hold/api.gd` ledger |
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
instance as its child in `_ready()` and wires the `Host` model callbacks to it; the Proactive service
takes the same instance through `adapter()` and does not keep a second copy. It owns every private
director read (`state`, `config`, `_player_text`, `_held_text`, the group, the approach and hearing
state), the transcript hook, one answer watch and the bounded classifier calls. The quiet gate's
background policy is the director view's answer, not the adapter's own read. No service reads the
director directly; the classifier is the Proactive service's, and the adapter reaches it only
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
- the Context facts both reasoning stages read: the act gate's snapshot, the act history, the
  world-context mood and the relationship note;
- the global Anon-offer watch, the runtime state guard and the mare the game's conversation
  target names;
- the adapter's model calls and the world-context situation record.

It reads only service facades and `WORLD`, and the fields the facade sets once from its `wire()`
peers: `service` (this facade), `adapter`, `eligibility`, `gate`, `memory`, `privacy`, `initiation`,
`offer` and `act_owner`. `initiation` and `offer` are plain nodes because each of them preloads this
facade; everything else is the typed facade, and `act_owner` is the frame its watch gates on
(`docs/act_owner.md`).

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
| Hotkey | the offer (`press`) | accepted; no buck |

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

1. The Proactive service passes the decided pose option, offer line and request hold; the service
   re-checks Base clearance and samples visibility itself, so one authority answers both.
2. The service owns the exchange: the hold is transferred (`transfer_nav`) or claimed.
3. The first new line from the conversation target goes to the Anon decision classifier; an
   ambiguous line is `Refused`.
4. A yes runs the live placement check and then forms the Agreement; a refusal writes the
   cooldown signal; a counter-offer writes none and closes with one generated line.

The hotkey never forms an offer. `press` is the act key's one decision: it returns the handle only
for the same mare and the exact `(pose, source, bed, cuddle)` option, and otherwise ends whatever
was live with `Interrupted(hotkey)` and returns null. The service logs the exchange it broke, so
the offer carries no rule of its own.

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

The Proactive service builds the typed `MareOffer` from its decided option, offer line and request
hold and calls `begin_mare_offer`. The Proactive owns the ask line and the request lease until
formation; the Negotiation service owns them after it.

`shared/agreement.gd:Package` is the frozen package: the id and generation, the mare, the pose
option, the visibility, the frozen pose pair, the acceptance time and TTL, the trigger and the one
model scope. It stays inside the service; the act only ever receives the handle.

The package is immutable: the service builds it once and never rewrites it. `Handle` is the act's
view: the id, the generation, the mare, the option, the visibility and the frozen pose pair; a stale
handle is harmless because its id and generation no longer match. Cancellation is the facade's
`cancel(handle, reason)`, because the handle carries no callback. The offer service, the Act
service's only caller, reports the `runtime.start.start_agreement()` answer as `Started`/`StartFailed`
through `report(handle, started)`; the service closes the Agreement, releases the lock and releases
the hold unless the Act adopted it on `Started`. The service's Agreement handoff starts the standing
presentation (act-owned) and clears the shared offer window, so the hint goes with the Agreement;
the act key and the auto-start consume the handle through `runtime.start.start_agreement()`; a wait keeps
the Agreement live. A handle whose runtime is gone is cancelled with `cancelled`.

`can_start()` is the one readiness read. It answers false unless the Agreement is formed, its
handle is valid and it has not expired. A private Agreement whose visibility is gone is cancelled
there, through the one close path, with the privacy reason and its reaction; the call then answers
false. It keeps no flag and no scene row: the scene gate is the readiness authority, and the offer
reads it. The offer calls `can_start()` before it offers the live Agreement and before the
auto-start consumes it.

Formation runs the live placement re-check (`Host.pose_placed`, the scene-only rows) after the
positive answer and before the package is built. A moved bed or a lost standing spot is
`Interrupted(pose)`: no Agreement forms and the offer hold is released. The hotkey's exact match
starts at once.

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
immediately, the shared reaction helper queues the line, and no cooldown is written. The offer's
readiness read takes the fresh sample: a private Agreement that lost its visibility is cancelled by
`can_start()` with the same `privacy` reason and reaction.

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
without changing the pacing. The service's cooldown signal on a plain decline or an acceptance
reaches the Proactive as `Terminal.cooldown_s`; the Proactive's stored history cooldown is the
effective per-mare wait. A counter-offer, expiry, interruption and start failure write none. A
counter-offer also queues one
short generated line declining the place or timing while still wanting him; a plain refusal keeps
the base-game dialogue and no extra line; privacy keeps its interruption line. The one react line
is queued as `unfplap:negotiation:react:<usec>` and drops itself when the mare left the tree. The
tolerance stop's `stop_until` is separate.

## Data ownership

The live negotiation and the Agreement live in memory. Nothing is persisted. The offer cooldown
belongs to the Proactive service's cooldown store; this service passes `Terminal.cooldown_s` and
the Proactive applies it. No reasoning record and no history write happens on a failure.

## Settings

No setting is read directly. The bridge's `relationship_ok` and `context_facts` read the act
gate, which owns the Promiscuity floor, heat, the public preference and the rest as Context. The
retired `features.act_public_offer` and `relationship.sex_start` are never consulted.

## Controls and debug

- No hotkey and no face. The Act key is the hotkey; this service only answers the offer's one press.
- The `negotiation ...` debug log lines are `state=offered|agreement|none`, `offer`, `hold claim`,
  `hold lost`, `privacy lost`, `press match|interrupt`, `answer`, `non-offer`, `outcome`,
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

## Known limits

- The model calls are the host adapters' work; this service only sees the typed `Decision`.
- The hold is best effort: a re-task or an attention reassignment ends the negotiation with
  `target_left`.
- Both offer routes are live. The Agreement auto-starts when the presentation settles and the
  scene-only rows pass; the act key consumes an exact match earlier and skips the presentation.
