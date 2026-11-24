# Model classifiers

The classifier service is the mod's one bounded model transport. It owns the client, the call
queue, the single active request, the per-call deadline and the cancellation handles, and it bounds
and schedules a call another service has already designed. It is the authority for when a
background model request may run and how long it may take; it never authors an instruction, an
utterance or a parser, and it never interprets a reply.

## What a caller owns

A caller supplies its own definition: the instruction, the input and output bounds, an optional
deadline and queue priority, and the utterance for this exchange. The definition is plain data and
must not change once handed over, because the transport reads it when the call actually starts,
not when it is queued. The reply sink belongs to the caller too: one raw text and provider error,
delivered once. The meaning of either value is the caller's business.

The transport keeps no registry of definitions. A call carries its definition and the transport
validates it at the edge, so one service cannot borrow another's instruction or parser.

## Scheduling

One model call at a time. A request joins a short queue ordered by the definition's priority and,
within one priority, first come first served; the active call is never preempted. A full queue
refuses the new request rather than dropping an older one. The deadline belongs to the definition,
and the transport stops the client and reports a timeout when it passes; a client that will not
accept the request reports itself busy.

The first start is deferred to the next idle frame, so the caller holds its cancellation handle
before any reply can arrive. The handle drops a queued request or cancels the active one; a
cancelled request never reaches its reply sink.

## Availability

Only the live director's model configuration decides. No enabled configuration, or a configuration
without a section, means no call at all, and that single answer is the gate a background producer
reads before it builds anything. The client is taken from that configuration when it is first
needed and refreshed when the world's director is replaced, so no caller manages a client of its
own.

## Lifetime

The queue and the active request belong to one world. A world enter and a world close both drop
the calls of the world that is gone and forget the director view, while the client itself survives
the close; only the process exit drops it. Nothing is persisted across a session.

## Why not batch

A batch waits for its slowest member, and it makes one item's failure or cancellation travel with
the others. The calls here do not share an instruction, a payload, a parser or a priority: they form
a dependent chain within one exchange, and a kind allows one live request at a time. The only
overlap is background reasoning beside an interactive line, which is exactly the pair that must not
fall together. If a need ever appears it is the initiation scan reasoning about several mares in
one call, which changes pacing rather than transport.

## The shared status file

The client reports into the status file the director's own client uses, so the game and the mod
show one model state rather than two. A provider refusal or a malformed reply is passed through
untouched and belongs to the caller to interpret; the transport logs no instruction, utterance or
reply body. A refused definition is an error, and a full queue is a debug line, so a misconfigured
caller is distinguishable from a busy one.
