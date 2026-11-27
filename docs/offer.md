# Idle act offer

The offer service owns the idle act offer and the start it leads to: what the act key could start
here, the hint on the game's corner control card, the press, and a live Agreement's automatic
start. It is the discovery and press authority for a start that already has a scene; the rows
behind that scene are `scene_gate`.

## Discovery

The standing candidate is found by a fan behind Anon rather than by aim: a half-angle to each side
of her backward axis, within reach of an approximate rump anchor, nearest first. A squared
eye-to-body distance rejects the mares out of reach before any rump math. A human Anon's missionary
candidate is the pony lying in the other seat of his couch rest; for AnonPony it is the pony already
lying within sight and on a bed.

The sensor polls at its own cadence, and the act key or a new seat forces a read. A transition is a
changed candidate set, lying or bed-side candidate, offer target or scene fingerprint, so the hint
follows a pony who stood up, was picked up, fell asleep or lost her navigator; a crowd rotates
through a small budget instead of hashing every candidate in one frame.

## One evaluation

An evaluation takes a live Agreement that is already ready first, because it is a yes; one still
waiting leaves the scene pass free to find the hotkey attempt. Then come the bed-side or
already-lying missionary candidate and the standing fan nearest first, each with the same business
checks: the act-target capability, the stool pair read once, the small scene checks, and Base
clearance last. Nothing is cached between passes and no row objects are built here, so a changed
scene re-allows or re-refuses on the next pass.

## The hint

The hint is one row on the game's corner control card, carrying the player's act key, so it reads
as one more control the game offers; the HUD puts it there, and a headset, which has no card, uses
the HUD's own centred prompt instead. A standing candidate who needs footstools shows the "Needs a
footstool" note instead, with a toast that says what to find; both appear once per target, not once
per poll. With no offer the hint goes away and its logged key resets, so the same offer speaks
again when it returns.

## The press

The act key has one entry. A live act takes the press and stops there; a paused tree or a released
cursor turns the press away before it reads anything; anything else forces a sensor read and a
fresh evaluation, so a press never starts a stale offer. No offer means no attempt; a blocked one
toasts and starts nothing.

The typed offer carries its pose, source, bed and trigger, so the start reads them from the record
rather than from a pose name. A hotkey attempt asks the scene gate for readiness and Base clearance
with no policy snapshot and no offer cooldown: the press accepts when the scene does, and the
physical refusal belongs to the tolerance stop. Before that attempt it asks the negotiation service
whether the press matches a live Agreement exactly, which starts at once and skips the presentation,
and any other live exchange ends there. A started attempt clears the hint; a blocked one keeps it.

## The live Agreement

A formed Agreement is offered as a typed start of its own: the scene-only rows against the pose
pair frozen at formation, with no new policy verdict. A wait keeps the Agreement and the hint for
another press; a start or a failure ends it and reports the result to the negotiation service. The
offer restates the runtime's start answer for itself because a service never preloads the runtime.

An Agreement also starts without any key. A readiness clock in the common idle frame consumes a
live one once the negotiation declares it ready and the live scene rows pass, so the standing
presentation has settled and Anon is in position. The clock runs before the handle read, so a
handle that appears between polls is caught on the next one. A live act holds the clock, as does an
open menu, a halted tree or a free cursor after the clock was consumed. The readiness decision
belongs to the negotiation, and the rows to the scene gate.

The standing presentation is started here, ahead of every interaction gate, so an open menu cannot
hold it back; it runs once per Agreement and is undone when the handle disappears or the world
closes.

## Lifetime and settings

Nothing is persisted: the sensor's senses, the offer, its logged keys, the toast flag, the last
seat, the resolved hint row, the presented runtime and the clock live for one world. A settings
edit drops the resolved hint row and forgets the sensor's senses, so the next idle frame rebuilds
the hint with the new act-key label and re-evaluates with the new values. The label is read when a
hint is built, never per frame.

With the debug switch on, one line reports each new offer, each blocked target and the press that
followed.
