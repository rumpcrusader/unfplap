# Poses and skeleton

The pose service is the authority on what a pose is, when the act may enter it, and how it is
placed and blended. It owns the authored pose documents, the static capability table, the live
session and its edges, the per-pose configuration and the player frame. The act camera, the hands
and the anatomy own their own parts of the act.

## What a pose is

A pose is an authored document plus static capability: family, frame, driver, settings group,
profiles, forms, views, allowed scene sources, a start setup and whether it is public. Only a
public, offerable row that the live form and view support, and whose scene source allows the act,
becomes an offer; `missionary` on a bed and `standing` standing are the offerable poses. Internal
rows such as the oral turn, the bed face-sit and the debug variant are reached through their edge
or a debug action and are never offered. The scene gate and the request path read capability, never
a pose id.

## Assets and placement

An authored pose stores local-rest bone deltas, a hips anchor with a contact point and support
height, the armature root, the body bones and optional Anon, bed and shot blocks. Every body bone
is present, including the ones left at rest: a missing bone keeps the game's own pose and breaks
the chain it hangs from. The head is never authored, because the face is aimed live. Placement is
the anchor/contact rule: the root scales about the hips anchor by the body scale and lifts so the
contact stays on support, and the live scale applies once at the world root. A bed pose also rises
by the body's measured clearance, because a body that hangs further from its armature root would
otherwise sink into the mattress. Anon's body uses the same rule. A variant keys by size name and
may replace the anchor, root, Anon block and shots and merge the bones, but it may not change the
space, frame, rig or bake reference.

## Axes and the head

Bone writes are in skeleton space. The axes are body-relative: right, up and forward read the
actor's upright basis into skeleton space, so up stays world gravity while the skeleton's bones
roll, and no bone is posed from a raw world axis. A scaled parent basis is never inverted: the
stock hiders collapse bones to a tiny scale, and a plain global write would compound that scale
every frame, so the rig builds the local pose from the parent's orthonormal rotation and rejects a
non-finite target. The head's own forward is not the face axis; the aim reads the neck link's
mapped frame, and the head is a direction target rather than an authored bone. After aiming, the
neck chain is rolled about its own forward until her head is level, so a rolled pose does not leave
her staring sideways.

## Session and edges

The session moves through idle, entering, steady, transitioning and exiting. A request reports the
first refusal only: the same target, a wrong act phase, a running transition, a pose that is not
steady, no edge, an unsupported form or view, a feature or consent refusal, a missing asset, a
lock. The same-target check comes before the phase check, so a no-op target is never reported as
busy, and a refused request changes nothing.

An edge is one clock and per-channel tracks: hold, blend or delta, switch and lock. A base channel
owns the view weight, an absent channel holds, and a constraint is only a floor on a channel's
start. The contact channel is the one contact change, from opening to mouth or face and back, and
completion settles the target row's base contact. Each edge validates its endpoints, requirements
and timing before it may start.

Settings are read on a request and on a live edit, never per frame. An accepted request snapshots
the target's settings group and presentation; a live edit re-merges that snapshot in place and
runs the pose-change pass, so a changed tuning row installs or removes its owner without resetting
the live asset.

## The player frame

The frame owns Anon's placement, his stance, the control lock and the one restore. It solves from
the pose and the rig only. Standing places him behind her at the tuned gap on his own floor, with
the body's entrance offset, and never fits his whole body or measures to her entrance; the
per-frame aim moves only his pelvis. Missionary places the act's own body from the asset and parks
the real rig. The bed frame follows a moving bed, so the pose, the act body and the eye travel with
it. The end gives the player back once, and a forced stop or a failed start uses the same restore.
The act body gives back only the pose it borrowed; the presentation hold owns his visibility.

## Standing and missionary

Standing keeps her where she stands and locks her facing every physics tick while locomotion and
emotion keep running; conversation attention is cleared each tick rather than treated as a stop
condition. The standing base is baked from the body rig's rest pose with the reference recipe, and
the live recipe applies only the difference. Body sway moves the pelvis on an inverted damped
spring and Anon's pinned hip rocks with it; the tail lifts, asides and rocks on the visible chain,
the ears twitch on a thrust, and the wings hold then fold into the afterglow.

The oral turn captures her root, facing and opening, turns her about up and restores the captured
frame on the reverse edge or the one exit. Its neck delta keeps her muzzle along the shaft, the
lean is locked and caress targets the sides of her head while the mouth contact holds. The bed
face-sit contact drives a bed-frame offset from his mouth to her opening, holds the last valid
offset when the provider is missing, and restores on the reverse switch or the exit.

Missionary is its own state. Anon stands and the desktop presentation is parked, she is released
from bed rest, and the authored asset poses her. The render-time write is the pose the renderer
sees, because the game re-poses the rig after the modifier pass; the physics write stays because
the game's contacts read the skeleton during the tick. The exit restores the avatar, the bones, the
part and the pony. A body swap rebuilds the pose on the new skeleton at the live pose id and is not
a transition; it settles without a second entrance. The afterglow holds the pose the act ended in.

## Timing

The render-time pose write and look, the physics and presentation tick and the camera motion are
separate owners; do not merge them blindly. The fan-out after the pose tick runs pose, camera,
hands, kiss and anatomy in a fixed order, and a pose change is a retarget, never a teardown.
