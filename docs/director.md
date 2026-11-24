# Conversation director

`director/api.gd` (world scope) is the mod's one bridge to the conversation director and its one
model transport: the quiet gate, the authored lines and situation records, the player-line
baselines and watches, and the raw completion every reasoning route runs on. It owns no prompt
text and no request schema; the routes that speak build and parse their own.

## Scope

This contract covers:

- the quiet gate the automatic request scan reads, and its stable reason names;
- the director's authored greeting, queued lines and the situation record;
- the transcript hook and the player-line baselines: the answer watch and the global offer watch;
- the one model transport: the classifier node, its availability, the raw completion and the
  scope cancel.

It does not cover a negotiation's request kinds or replies (`docs/negotiation.md`), the Proactive
pacing and wording (`docs/initiation.md`) or the act's dialogue (`docs/dialogue.md`).

## Ownership

- `director/api.gd` is the service: the classifier node reference, the transport and the watches'
  lifecycle.
- `director/bridge.gd` is the private director bridge: every stock director field read, the
  transcript hook, the baselines and the two watches.
- The bounded classifier node is the Proactive service's. It builds the node and hands it over in
  its `setup()`; this service imports no classifier file, and the classifier's own queue, deadline
  and budgets stay its owner's contract.

## Watches

The offer watch is armed and disarmed by the negotiation, which owns when the field is free. The
bridge captures the first new player line and holds it until the director is idle again, so her
reply to the same line is never read as a new ask. The answer watch is one at a time; a scope
cancel drops the watch and the classifier request together.

The baseline is the bridge's: the director's player-line fields are recorded when a watch starts
and compared afterwards, so an old line left in place is not the answer. A transcript signal wins
over the polling fields; the fields alone are not an answer.

## Transport

One classifier node, one raw completion: the caller builds the instruction and the payload, and
parses the reply. The transport reports whether the call started and never inspects the text. A
missing or unavailable classifier refuses the call, and the availability read is the offer
watch's gate.

## Data ownership

Nothing is persisted. The hooks, the watches and the baselines live for one world: a world close
drops the watch, the pending line and the transcript hook before the director node is freed, and a
world enter hooks the new director. The classifier node belongs to the Proactive service for the
process.

## Settings

No setting is declared here. The quiet gate asks the world's own background-AI policy through the
director view, not a mod setting.

## Debug

`quiet_reason()`'s strings are the request scan's stable debug reasons, logged by that scan. The
transport logs no line of its own; the request owners log their calls and replies.
