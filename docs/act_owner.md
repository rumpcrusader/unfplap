# Act owner

The act owner is the one World service that owns the act frame: which runtime is acting, the
serial floor under the act ids, and the single suspended body swap. It is the only place where an
act start, an act end and a body-change adoption agree on who owns the act, so callers ask it
instead of tracking a live act of their own.

## The frame

An act start takes the frame before the runtime announces the act: the idle offer drops its
playable offer, and the stock smack layer hands the acting body's outside-act player over to the
act. An act end frees the frame only when the requesting runtime is the one that holds it, so a
stale exit from another body cannot end the live act; the same call returns the smack layer to the
body. The plain "an act is running" read is what the idle probe, the act key, the offer, the fan
sensor, the footstool supply and the Anon-offer watch gate on.

A missing owner is ordinary rather than an error: every consumer reads it as no act, so a suite or
a bare runtime needs no stand-in instance.

## The swap record

The handover records one suspended act before the runtime leaves the old body, so the new body's
spawn finds the record instead of building a second runtime. The record holds the runtime, the body
being left, the stable id and the change that asked. A change with no body-change record records
nothing.

The record is scoped to its runtime. A clear from another runtime is a no-op, as is a clear with no
runtime, and its one end belongs to the adopting roster or to the handover's own finish, abort and
failure paths. The roster also reads it to leave the old body out of its live list while the swap
is pending, so a body whose act has already moved on never reads as a live one.

## World close and process exit

A world enter and a world close both drop the pending swap with the world that is gone. A world
close never force-stops a live act from here: the swap goes with the world, and the roster's own
close path ends the act and frees the frame. The process exit is the one place a live act is
stopped through its exit; the roster owns that path and stops every runtime before the services
shut down.

## The serial

The serial is the act's identity, not the entry's, and it is issued into a store the world keeps.
The last value this process issued is a floor under the stored one, so a store that cannot keep the
write still never hands out the same serial twice, while a store that did keep the write outranks
the fresh floor. The floor is World state and the teardown drops it.

## Peers and boundary

The frame calls exactly two peers, the idle offer and the stock smack layer, and takes them as
peers rather than through the World record, which already carries this service. The service
preloads no runtime: the runtime is a Node, and the only value read from it is the body it reports.

## Settings and controls

None. It reads no setting and declares no control; the act key belongs to the input service and the
idle scan to the offer.
