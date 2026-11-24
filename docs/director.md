# Conversation director

`director/api.gd` (world scope) is the mod's one bridge to the conversation director: the quiet
gate, the authored lines and situation records, and the player-line baselines and watches. It owns
no prompt text and no request schema; the routes that speak build and parse their own, and the
model transport is the `classifier` service (`docs/classifier.md`).

## Scope

This contract covers:

- the quiet gate the automatic request scan reads, and its stable reason names;
- the director's authored greeting, queued lines and the situation record;
- the transcript hook and the player-line baselines: the answer watch and the global offer watch.

It does not cover a negotiation's request kinds or replies (`docs/negotiation.md`), the Proactive
pacing and wording (`docs/initiation.md`), the act's dialogue (`docs/dialogue.md`) or the model
transport (`docs/classifier.md`).

## Ownership

- `director/api.gd` is the service: the watches' lifecycle and the quiet gate.
- `director/bridge.gd` is the private director bridge: every stock director field read, the
  transcript hook, the baselines and the two watches.
- The model transport is the `classifier` service; this service owns only the watches and the
  lines.

## Watches

The offer watch is armed and disarmed by the negotiation, which owns when the field is free. The
bridge captures the first new player line and holds it until the director is idle again, so her
reply to the same line is never read as a new ask. The answer watch is one at a time; a scope
cancel drops the watch.

The baseline is the bridge's: the director's player-line fields are recorded when a watch starts
and compared afterwards, so an old line left in place is not the answer. A transcript signal wins
over the polling fields; the fields alone are not an answer.

## Data ownership

Nothing is persisted. The hooks, the watches and the baselines live for one world: a world close
drops the watch, the pending line and the transcript hook before the director node is freed, and a
world enter hooks the new director.

## Settings

No setting is declared here. The quiet gate asks the world's own background-AI policy through the
director view, not a mod setting.

## Debug

`quiet_reason()`'s strings are the request scan's stable debug reasons, logged by that scan.
