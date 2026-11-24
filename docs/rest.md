# Bed rest and cuddle rejoin

The rest service owns the scene work around a bed or couch act: where she is placed on the mattress,
how the bed is given back, the clear floor beside it and the return to the game's own cuddle. The act
state, the pose and the teardown belong to the act session; this service owns no act rule.

## Placement

The cradle start puts her on the bed anchor, waits for support and settles her upright; the act then
poses her body. The placement only puts her in bed space and never poses her.

The anchor is the game's own guest-seat transform when the live couch reports one. Without it, the
anchor is the mattress top on Anon's side, with the pony facing along the bed, or toward him when the
bed is gone.

Giving the bed back restores the pre-act player, pony and camera for a bed act and stands her. A
ground act keeps Anon where the act ended.

## The rejoin

The rejoin is offered only after a normal bed end that did not go badly, for desktop human Anon. A
forced stop never reaches it. A bad act, or an upset mare, leaves her standing.

The rejoin seats Anon on his own seat and reclines him, then moves her to clear floor beside the bed
before inviting her. The move comes first because the game's front probe rejects a floor too far
below her feet. It then waits for the recline blend to finish: inviting earlier seats the guest at
standing height. After that it opens the bed and invites her to the real guest seat, retrying within
a window long enough to outlast the aftercare lease and the couch's guest cooldown. Every attempt
re-reads the live act and the recline, so a new act, a forced stop or a stood-up player cancels it; a
timeout logs the posture, navigator and cooldown state and leaves her standing.

The game's accept path is not used. It lets a social-talk lease count as routine, and its invite
ignores the seat argument; the rejoin opens the bed itself and passes the actual guest seat. The
stock closeness rule remains the authority: she must welcome closeness and be at least a friend.

## Failures

A missing pony, tree or bed, a stale act, a missing player rest, no live couch rest or fewer than two
seats refuses before any scene write. The async paths re-read the live values after every wait, so a
stale rejoin acts on nothing.

## Boundary

The service holds no state between calls; the act supplies the live values through one context and
the pre-act restore through one callback. It never reads the act's node directly.
