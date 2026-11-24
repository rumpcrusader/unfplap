# Act scene hold

The scene hold is the scene ownership an act borrows while it runs, and the negotiation hold
that reserves the same mare before it starts: the navigator lease, the physical affection hold, the
player's movement hold, the face-turn rate, the conversation attention, the carry, the cuddle
session and the game's shared excitement Beat. It is ownership, not permission: whether an act may
start belongs to `scene_gate`, and what the act and the negotiation take over is here.

## One ledger

The negotiation claims a token the scene gate accepts, keeps Anon as her conversation target, sets
the physical affection hold, and hands the same owner to the act at the start; an act that starts
from a live negotiation adopts that hold instead of taking a second one. The ledger decides which
ownership is taken, which is kept, and in which order it is given back. The runtime's composition
creates it, and it works while the runtime is idle, because a negotiation runs before the act it
leads to.

## Order

The ledger clears the cuddle or the carry before the pose and claims the navigator before it; on the
way out it restores the face turn, unlocks the player, releases the carry and the footstool, and
gives the navigator back last. The negotiation releases the affection hold before the navigator
lease. Nothing is released that its own flag does not say was taken, so a failed start gives back
exactly what it took, in the order a normal end uses.

Two holds are deliberately not flags. The player's movement hold is the game's kiss-hold marker
rather than its control lock, so the camera stays free; the game's kisser wipes that marker on each
physics step, so its own physics is paused for the length of the act. The carry and the cuddle are
released by reading the live scene, so releasing one that is already gone is harmless.

## The excitement Beat

The game's shared excitement Beat is held by owner name: the first holder saves its pause state,
every holder keeps it paused, and only the last release restores it, so a Beat that was already
paused stays paused. The integrations and the kiss ask for a named hold through the act's facts
rather than writing the pause flag themselves, because a release cannot know about a holder it
never saw. The teardown drops every hold and restores the Beat once.

## Working from the handle

The lease calls work from the navigator handle the claim recorded, not from a fresh read of her
body. A teardown that has already lost the pony still gives the lease back, and a freed node is not
looked up again.

## Boundary

The act state, the pose, the serial and the teardown ledger belong to the act session; this service
keeps only the ownership flags and their releases. It reads no setting and declares no control. Its
debug report is the ownership state the teardown leaves.
