# Model classifiers

`classifier/api.gd` (world scope) is the mod's one bounded model transport. It owns one LLM
client, one queue, one active call, the per-definition deadline and the cancellation handles. It
never builds an instruction, an utterance or a parser: the owning service does that, and the
transport only bounds and schedules the call.

## Scope

This contract covers:

- the one client, its live director configuration and the availability read;
- the queue, the active call, the deadline and the cancellation handles;
- the call contract: one raw reply and error through the reply sink passed to `run`;
- the batching decision.

It does not cover the prompt text (`docs/prompts.md`), the request kinds and parsers
(`docs/negotiation.md`, `docs/initiation.md`), the director's watches (`docs/director.md`) or the
deterministic classifiers in the shared pure modules.

## Ownership

- `classifier/api.gd` owns the client, the queue, the active call, the deadlines and the
  cancellation state.
- Each owning service owns its `Definition`: the instruction, the bounds and the utterance it
  sends, plus the parser of the reply.
- The director view supplies the live model configuration and the client factory; this service
  imports no base-game module.
- The service holds no registry. A call carries its own definition; the service validates and
  uses it.

## Definitions

| Id | Owner | Prompt | Reply |
|---|---|---|---|
| `negotiation.anon_offer` | negotiation | `classify.anon_offer` | `{"offer","option"}` |
| `negotiation.anon_decision` | negotiation | `classify.anon_decision` | `{"answer"}` |
| `negotiation.mare_response` | negotiation | `classify.mare_response` | `{"answer"}` |
| `initiation.mare_offer` | initiation | `classify.mare_offer` | `{"offer","option"}` |

The payload and parse stay with the owner's contract. A definition is plain data: the owner sets
`id` and `instruction`, and may set the input/output bounds, the deadline and the queue priority.

## Scheduling

One call at a time. `run()` returns a `Call` handle or null; the `Reply` passed with the call
receives the raw text and the provider error once. A cancelled call never calls it. The queue is
ordered by the definition's priority, FIFO within one priority; the active call is not preempted. A
queue-full call is refused. The deadline is the definition's; a timeout cancels the client and
reports `timeout`, and a client that refuses to start reports `client_busy`.

The call starts on the next idle frame, so `run()` returns the handle before any client reply.

## Availability

The live director's model configuration decides: no enabled configuration or no section means no
call. `available()` is the Anon-offer watch's gate. The client is created from the director view on
first use and reconfigured when the world's director changes; it survives a world close.

## Cancellation and lifecycle

`Call.cancel()` drops a queued call or cancels the active request. `cancel_all()` is the
world-close and shutdown sweep. A world enter and a world close both cancel the calls that belong
to the world that is gone and drop the director reference; the client stays. `shutdown()` also
drops the client reference.

## Batching

Not implemented. The four calls are a data-dependent chain within one exchange, and the state
machines allow at most one request of a kind at a time. The only overlap is a background reasoning
call and an interactive Anon line, which have different instructions, payloads, parsers and
priorities; a batch would couple their failures and cancellation and wait for the slowest item.
The first candidate, if the need appears, is the initiation scan reasoning about several mares in
one call, which is a pacing feature rather than a transport change.

## Data ownership

Nothing is persisted. The definitions are the owning services'; the client and timer belong to
this service for the process; the queue and active call belong to one world.

## Settings

No setting is declared here. The live director's model configuration decides availability.

## Debug

A refused definition is an error; a queue-full refusal and a client-busy start are debug lines. The
transport logs no utterance or reply content. The owning service logs its own start and parsed
result.

## Known limits

- The client is single-flight; there is no parallel call.
- The status file is the director's `llm_status.json`, shared with the game's own client.
- A provider refusal or a malformed reply is the owner's to interpret.
