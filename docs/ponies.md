# Ponies

The roster owns one runtime per pony body: which body has which runtime, the attach and prepare
hooks, the live set, the adoption of a suspended act's new body, the prompt note the game reads and
the character lists the selector shows. It is the only authority for that mapping, so consumers ask
it rather than reading the entry.

## Attach

A body is refused when it is the player's own pony or carries a rig, because it is Anon's body and
not a mare's. Otherwise the body is prepared, offered the pending swap, and given a runtime only
when neither the swap nor an existing runtime took it. The runtime is built by the entry's factory
and enters the body's tree; the roster preloads no runtime and calls it only through the act
contract it publishes.

A late prepare exists for a body a mod completed after its first spawn. It repeats the prepare and
never creates a runtime.

## Prepare

The order is the contract. The provider's form is fitted and mirrored first, before anything binds;
then anatomy is presented once, wearing the form the provider stored, the cycle schedule is
started, the outside-act smack layer is told about the pony, and the eligibility and act-gate
services are warmed for her. Anatomy owns the identity gate inside that presentation, so the roster
makes no separate capability or tail decision.

Every hook is idempotent, which is what makes a late prepare safe. A body with no factory, no
runtime or a missing peer is a quiet no-op, so a suite can wire any subset.

## Adoption

The act handover records the suspended swap before the runtime leaves the old body. The new body's
spawn offers itself to that record before a runtime is created; a body claimed by the source or by
the stable id adopts the suspended runtime, and any other body is attached normally and leaves the
record alone.

A duplicate runtime can appear only through a race. Its anatomy controller is withdrawn and the
duplicate is stopped and freed, because the suspended act is the real owner; the act's runtime is
reparented under the new body, the swap record is cleared and the body is bound. Adoption never
resumes the act; the handover owns that one resume.

When the spawn hook arrives late, the handover holds the suspension across a short grace and then
asks the roster again. That path repeats the prepare and the same adoption.

## The live set

The roster's set is the runtimes in its group that are still inside the tree, mapped to the bodies
they report. There is no private map: the body's named runtime child is the one lookup, so the
factory must name it so. A body the pending swap is taking away is left out, so it never reads as a
live one.

## Characters

The selector lists adult mares whose bodies hold a runtime and pass the character capability. The
base roster is dropped from that list, the mares an active installed source lists are appended even
while away, and the result is sorted by display name. A provider owns its own installation gate;
the base roster stays exactly the base roster.

## The prompt note

The game asks for one dialogue note per mare through its own note group. The runtime whose stable
id matches the query answers with its live act or afterglow note, and the cycle line is appended
when the cycle has one. A runtime that has not read its id yet is matched through its body's
identity.

## Close, settings and exit

A world enter needs no bind, because the live set is the runtime group; the roster's close ends the
live act through the one exit and frees the act owner's frame, then leaves the runtimes to depart
with their bodies. A settings edit re-runs the live pass over every runtime, the suspended act
included. The process exit closes the act and stops and frees every runtime while the World
services they read are still alive, then drops the peers and the factory.
