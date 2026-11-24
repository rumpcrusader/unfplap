# Footstool

The footstool service handles the standing reach case: a mare whose bits sit higher than Anon can
reach from the ground, so he stands on one or more stacked case footstools. It owns the reach rule,
the case loan, the act stack and the world supply; the act start, the pose and the inventory belong
to their own systems.

## When a stool is needed

The rule applies only to standing, desktop human Anon, with the feature on and the anatomy controller
online. It compares where her opening sits above the ground with where his part sits above his own
feet, and makes the difference between their floors explicit, so a step between them counts. The
first stool is needed once the gap passes the configured threshold, and each further stool covers one
step; the remainder under the last stool is left to the anatomy aim.

A missing anatomy controller, an unprepared part, a non-finite value, AnonPony or a headset rig makes
the rule inapplicable rather than required. A gap larger than the available stack is never bypassed:
the gate asks for more case stools, and a short or unwritable case blocks the start.

The same rule feeds the scene gate's blocked row and the offer's needs-a-footstool note, which has no
act-key icon. The idle hint reads the reach and case pair once per scan and hands it to the row; the
blocked note reuses that pair instead of measuring again.

## The act stack

The start checks the required case units out and keeps their tokens and slots. The frame then places
the stack under Anon and raises his player root to the stool floor, so the pose, camera and anatomy
aim all use the same raised body, and a form revision re-places him on the same stack.

The stack is static and supports only Anon: the partner pony is added to its collision exceptions in
both directions, so the stack neither lifts nor tilts her, and the player still collides with it. The
stack stays through the afterglow. The one exit removes it, lowers Anon to the saved floor and
returns every unit; a world close repeats the release as a last resort.

Stepping up happens as the act begins and stepping down is an instant at the end; no climbing
animation plays.

A loan that cannot be returned is left without a world transform, and the game restores it into the
case on the next open. A save taken during the act restores the loans the same way, but the act does
not resume, so a load can drop the player from the stack height.

## Supply

With the feature on and nothing owned, the world spawns a few pickable footstools in loaded house
interiors near the player. House-generated footstools are fixed scenery and never enter the owned
count; a single stool anywhere, whether in the case, held, placed or dropped, stops the supply. The
shop
remains a valid way to get more for a larger stack.

A drop starts near the inside door and the room centre, takes the real floor from a downward ray and
rejects furniture, walls and bodies with a box query, so it persists as an ordinary owned world item.
The supply retries while no home is loaded, pauses with the tree and during an act, and logs once
when no home is available or the case is full.

## Settings and debug

The switch and the two standing values are declared settings, and the step height is a debug value.
**Give footstool** adds one to the case. **Show data** reports the aimed mare's opening, part height,
gap, threshold, step, required and case counts.
