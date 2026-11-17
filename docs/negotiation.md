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
- the terminal outcome to the Proactive service;
- the debug rows.

It does not cover pacing, the approach, the Mare Initiation Reasoning, the presentation, the act
start, the scene rows or the pose placement gate. Those belong to `docs/initiation.md`,
`docs/poses.md`, `docs/runtime.md` and `docs/scene_gate.md`.

## Ownership

`negotiation/service.gd` (world scope) owns:

- the one live Act Negotiation: phase, offer, generation, TTL and lock;
- the Agreement package and its handle;
- the classifier/reasoning scopes and their cancellation;
- the terminal outcome and the offer cooldown.

`negotiation/agreement.gd` is the pure package and handle. The service is its only writer.
`negotiation/prompts.gd` is the pure model request layer: the three instructions, the payload
builders and the reply parsers. `main` mediates the per-pony hold, the director, the model calls
and the Proactive handoff; the Act service gets only the handle.

## Internal API

```gdscript
enum Phase { NONE, OFFERED, AGREEMENT }
enum Outcome { ACCEPTED, REFUSED, EXPIRED, INTERRUPTED, START_FAILED, NO_OFFER, OCCUPIED, STARTED }

class FormView:       form, view
class MareOffer:      runtime, pony, option, base, private, hold_token, hold_old_wander, line, cuddle
class DecisionRequest: kind, text, line, context, options
class Decision:       answer, option_index, failed
class Terminal:       pony, pony_id, outcome, reason, trigger, cooldown_s
class Host:           the named callbacks below

setup(host: Host) -> void
reset() -> void
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

The host callbacks are:

| Field | Signature | Purpose |
|---|---|---|
| `now` | `() -> float` | the service clock |
| `eligible` | `(pony) -> bool` | the eligibility service's `eligible?` |
| `relationship_ok` | `(pony) -> bool` | the live relationship, romance and floor |
| `context_facts` | `(pony) -> Dictionary` | plain `shared/context.gd` facts |
| `privacy_private` | `(pony, cuddle) -> bool` | the privacy provider |
| `placement_for` | `(runtime) -> PoseOptions.Placement` | the live placement facts |
| `form_view` | `() -> FormView` | the player's form and display |
| `hold_for` | `(runtime) -> RefCounted` | the per-pony `scene_hold/service.gd` ledger |
| `classify` | `(PROMPTS.Request, scope, done) -> bool` | the dialogue classifier; `done` gets a `PROMPTS.Reply` |
| `reason` | `(PROMPTS.Request, scope, done) -> bool` | the Mare Response Reasoning |
| `await_answer` | `(pony, scope, done) -> bool` | the first new line from the target |
| `cancel_scope` | `(scope) -> void` | cancels one model scope |
| `toast` / `log` | `(text) -> void` | player feedback and the debug line |
| `react` | `(pony, reason) -> void` | the shared interruption line |
| `on_outcome` | `(Terminal) -> void` | the Proactive pacing |
| `on_agreement` | `(Handle) -> void` | hands the Agreement to the Act service through `main` |

A model callback is called once. A late result after a terminal transition is ignored by the
generation token.

## Director and model host

`negotiation/adapter.gd` is the one director bridge and model host. `main` owns one instance,
injects it into the Proactive service and binds the `Host` model callbacks to it. It owns every
private director read (`state`, `config`, `_player_text`, `_held_text`, the group, the approach
and hearing state), the transcript hook, one answer watch and the bounded classifier calls. No
service reads the director or the classifier directly, and the Proactive does not keep a second
copy.

The bridge methods are the pacing reads and the director writes: `quiet(chat_gap_s)`,
`quiet_reason(chat_gap_s)`, `idle()`, `begin_greeting()`, `queue()`, `cancel_keys()`,
`record_situation()`, `player_name()`, `pony_speaking()`.

The model methods are `classify(request, scope, done)` and `reason(request, scope, done)`, which
turn a `PROMPTS.Request` into the instruction and payload, call the shared classifier once and
parse the reply into a `PROMPTS.Reply`; `complete_raw(system, payload, scope, done)` is the raw
path for the Proactive's Mare Initiation Reasoning, which owns its own prompt; `await_answer()`
baselines the director's player-line fields and reports the first new line; `cancel_scope()`
drops the watch and cancels the classifier scope together.

The shared classifier (`initiation/classifier.gd`, owned by `main`) bounds every call: one client,
one queue, one deadline, `input_bytes` and `output_tokens` limits, and a raw completion that
reports the text and the provider error without parsing it.

## Process

The routes:

| Route | Formed by | Answer |
|---|---|---|
| Mare offer | the Proactive service (`begin_mare_offer`) | the Anon decision classifier |
| Anon offer | this service (`begin_anon_offer`) | the Mare Response Reasoning |
| Hotkey | the Act service (`hotkey_handle`) | accepted; no buck |

The Anon offer is formed from the first new player line while Anon talks to a mare. `main` arms
the adapter's global watch only while no negotiation and no act is live; the adapter captures the
first new line and reports it once the director is idle again, so the classifier never races her
reply to the same line. `main` resolves the mare from the game's conversation target
(`conversation_target` bound to Anon), cancels an in-flight proactive approach that has not formed
a Mare offer, and calls `begin_anon_offer(runtime, line)`. A line that is not a clear offer is a
silent `NoOffer(not_offer)`: no toast and no cooldown.

1. Base clearance: `eligible?`, `relationship_ok` and availability; a failure is `NoOffer`.
2. Pose options from `shared/pose_options.gd`; an empty list is `NoOffer`.
3. The classifier picks intent and one option index; an unclear line or an out-of-list option is
   `NoOffer`.
4. The negotiation hold is claimed (`claim_negotiation`); a failure is `Occupied`.
5. Visibility is derived from `privacy_private` with the offer or cuddle rule.
6. The Mare Response Reasoning answers with Context plus the offer text and option; a failure is
   `Refused`; a plain refusal writes the 120 s cooldown; a counter-offer does not.

The Mare offer:

1. The Proactive service passes the already-decided Base clearance, option, visibility and hold.
2. The service owns the exchange: the hold is transferred (`transfer_nav`) or claimed.
3. The first new line from the conversation target goes to the Anon decision classifier; an
   ambiguous line is `Refused`.
4. A yes forms the Agreement; a refusal writes the cooldown; a counter-offer does not.

The hotkey never forms an offer. `hotkey_handle` returns the live Agreement only for the same mare
and the exact `(pose, source, bed, cuddle)` option; `interrupt_for_hotkey` ends any live
negotiation with `Interrupted(hotkey)`.

## Decisions

| Request | Instruction | Payload | Parse |
|---|---|---|---|
| Anon offer | `ANON_OFFER_INSTRUCTION` | the player line, the indexed options, Context | `{"offer","option"}`; only a clear offer with an in-range option survives |
| Anon decision | `ANON_DECISION_INSTRUCTION` | the Mare offer line, the player reply | `{"answer"}`; `unclear` is a refusal, malformed is a failure |
| Mare response | `MARE_RESPONSE_INSTRUCTION` | the player offer, the option, Context | `{"answer"}`; `unclear` or malformed is a failure |

`negotiation/prompts.gd` owns the strings and the parsers; the host adapter owns the LLM call and
the cancel scope. A parsed failure maps to `NoOffer` for the classifier and `Refused` for the
answer, with no cooldown.

## Agreement

`main.form_mare_offer(fields)` builds the typed Mare offer from the Proactive service's plain
values and calls `begin_mare_offer`. The Proactive owns the ask line and the request lease until
formation; the Negotiation service owns them after it.

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
whose bound arguments make a late handle harmless. It reports `Started`/`StartFailed` through
`report(handle, started)`; the service closes the Agreement, releases the lock and releases the
hold unless the Act adopted it on `Started`. `main._on_agreement()` starts the standing
presentation (act-owned) and the act key consumes the handle through `runtime.start_agreement()`;
a wait keeps the Agreement live.

Close reasons: `Started`, `StartFailed`, `Expired`, `Interrupted` (`privacy`, `pose`, `hotkey`,
`target_left`, `cancelled`). Every close releases the lock. Only `Started` leaves the adopted hold
to the act.

## Lock

One Act Negotiation at a time, including the Agreement window. A live offer or Agreement blocks a
new Mare offer, Anon offer or proactive approach; the attempt is reported `NoOffer` with reason
`locked`, logged and toasted. The hotkey is the only break. The lock lasts at most 240 s (120 s
negotiation + 120 s Agreement).

## Privacy

The service samples the provider every 0.5 s while a private offer or Agreement lives. A public
offer never subscribes: its visibility was derived at formation and stays public. A private offer
that loses privacy is `Interrupted(privacy)` in the negotiation or the Agreement; the state ends
immediately, the shared reaction helper queues the line, and no cooldown is written.

## Hold

`main` supplies the per-pony `scene_hold` ledger. The service claims
`unfplap:negotiation:<id>` for an Anon offer, or takes the Proactive request's token over for a
Mare offer, then takes the physical affection hold. A cuddle offer takes the attention and
affection hold only (`claim_attention`): the cuddle session keeps its own navigator lease. Every tick it re-asserts the navigator and
keeps Anon as the conversation target. A lost owner, a missing ledger or a reassigned target is
`Interrupted(target_left)`. Every terminal outcome calls `release_negotiation()`; `Started` leaves
the adopted hold to the act.

## Feedback and cooldown

Log + toast for `NoOffer`, `Occupied`, lock-blocked and every terminal outcome. The cooldown is
120 s only on a plain decline or an acceptance; a counter-offer, expiry, interruption and start
failure write none. The tolerance stop's `stop_until` is separate.

## Data ownership

The live negotiation and the Agreement live in memory. Nothing is persisted. The offer cooldown
belongs to the Proactive service's cooldown store; this service passes `Terminal.cooldown_s` and
the Proactive applies it. No reasoning record and no history write happens on a failure.

## Lifecycle

- Scope: world
- Constructed by: `main._ready()`
- Begin: `setup(host)`
- End: `reset()`/world close
- Idempotent: yes

## Settings

No setting is read directly. The host's `relationship_ok` reads the Promiscuity floor, and the
host's `context_facts` carries heat, public preference and the rest as Context. The retired
`features.act_public_offer` and `relationship.sex_start` are never consulted.

## Controls and debug

- No hotkey and no face. The Act key is the hotkey; this service only matches an Agreement or
  interrupts for it.
- The `negotiation ...` debug log lines are `offer`, `agreement`, `refused`, `expired`,
  `interrupted`, `start failed`, `started`, `blocked` and `occupied`.
- `debug_rows()` adds the `NEGOTIATION` Show data section: phase, lock, live offer/Agreement and
  the TTL.
- Debug actions (trigger Anon offer, force expiry, force privacy loss, force start failure, clear
  cooldown) are wired by `main` and documented in `docs/debug.md` when the route lands.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| shared | clearance | `shared/clearance.gd` | Base clearance result |
| shared | context | `shared/context.gd` | typed Context snapshot |
| shared | pony_id | `shared/pony_id.gd` | stable mare id |
| shared | pose_options | `shared/pose_options.gd` | the available options and exact match |
| shared | pose_placement | `shared/pose_placement.gd` | the frozen source capability |
| shared | pose_specs | `shared/pose_specs.gd` | the frozen pose capability |

## Tests

- `tests/negotiation/test_agreement.gd`: the package fields, TTL, expiry, exact match and the
  handle.
- `tests/negotiation/test_service.gd`: the Anon offer, the Anon decision, the Mare response, the
  failure semantics, the lock, the hold, privacy, `target_left`, the cooldown table, the Agreement
  handle, `Started`/`StartFailed` and the stale-handle guard, with a fake host and model.
- `tests/negotiation/test_prompts.gd`: the payload shape, the request dispatch and the three
  reply parsers.
- `tests/negotiation/test_adapter.gd`: the quiet gate, the queue and the situation record, the
  answer watch and its cancel, the three model calls and the raw path, with a fake director and
  classifier.

## Known limits

- The model calls are the host adapters' work; this service only sees the typed `Decision`.
- The hold is best effort: a re-task or an attention reassignment ends the negotiation with
  `target_left`.
- The Agreement auto-start (without the act key) is not wired yet; both offer routes are live and
  the act key consumes the Agreement through the scene-only start.
