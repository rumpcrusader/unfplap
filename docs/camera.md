# Act camera and the live view

The act camera owns the player's view during a base pose: the lean input and its smoothing, the
speed-driven surge and dip, the standing offsets and glance, the missionary eye with its authored
look path, the head clearance he keeps out of her skull, and the debug free look. It is the
authority for where the act's eye sits and what it looks at; his placement belongs to the pose, and
the kiss owns its own lean-in.

## Whose view it is

Only a human Anon on a desktop gets the mod's act view. An AnonPony body and a headset stay on the
game's camera, unleaned, and the standing VR act is started with the anatomy rather than here; a
missing player rig leaves the view unowned and the act still runs.

## The lean

The side keys oppose each other and so do the forward keys, and the side magnitude also counts as
forward lean, so a pure side lean still tips the eye toward her instead of sliding past her. The
lean is continuous, not a press: it ramps toward the pressed target and holds on release.

The act end and a paused world return the lean to rest on a slower curve than the ramp; there is no
auto-return mode or toggle, and pulling back with no side armed eases the shoulder roll to neutral
instead of locking it until a lean the other way. A full side lean fires one pose action, the
shoulder reach or the lean kiss, and latches until the lean falls back inside its release band. A
reach the hands dropped, because a smack took that hand, ends the reach and its glance and does not
fire again until the lean leaves the band. When a torso angle is set, the forward lean also hinges
his upper body over her: chest, neck, head and arms tilt as one while the pelvis counters, so the eye
follows the spine arc instead of sinking into her.

## Standing oral

While contact is oral the lean is deliberately locked. The lean keys are not read, an active
shoulder reach ends, an active lean kiss releases, and the side lean, forward lean, displayed lean
and idle sway all settle to rest. The caress hands keep ticking and the standing look response keeps
running, so the player can still touch and be looked at; only the shot stops moving. The oral turn's
facing comes from the pose, and the view returns to its normal basis when the pose clears it, so no
service carries a second copy of the facing.

## The shot

The shot is speed-driven, never an impulse. The signed depth speed is filtered and followed by a
critically damped response, so a fast thrust pushes the view and a slow one barely moves it. The dip
target is negative, so the eye drops toward her on the inward stroke and rises on the return, while
outward strokes travel about half as far. Surge and dip are read from the act's camera values at
start and on a live settings edit, with no fallback copy kept here; a side lean rolls the view
outward, and the displayed lean is smoothed rather than snapped.

The idle breathing rock is a separate offset added once when the shot is built: folded into the
smoothed lean it was amplified many times over and the view crept forward while nobody was leaning.
There is no side sway.

## Standing view

Standing uses the player's own camera and applies the lean offsets on top. The eye line starts from
the preset height and rises to her head's global rest line when that is higher, though never past
Anon's own eyes, so a body fitted taller than its preset cannot leave the view at her chest and Anon
is not scaled up to her. Rest, not the posed bone, so a bow or a neck-down does not drag the camera.

Her entrance positions the shot: the presented form supplies the rear anchor and the scale, the
preset rises or falls with the entrance height and adds the standing gap, so Anon keeps his distance
whatever shape stands there. The form is read on every start and refit, and a revised form re-solves
from his true base rather than an eye already lowered, so a late variant cannot compound a previous
offset. A footstool lifts the player root before the pose and the camera follows it.

The standing glance looks her way, eases her head back for an over-the-shoulder look, aims her
pupils and clamps how far she can turn; a full forward lean with no side forces a look up at Anon,
and the kiss yaw turns the camera toward her while the kiss holds.

## Missionary view

Missionary is his eye position with the authored look path. The position is his posed head with the
game's eye offset, cached before the act hides the head bone, so it follows every movement of the
player. The orientation is not his head: the authored shot bases are blended by the same forward and
side weights the lean uses, sign-aligned before they are averaged, and a missing shot falls back to
the eye's basis or to a look at her face. The lean here is one hinge at the spine — chest, neck,
head, shoulders, arms and hands as a unit — while his hips, thighs and legs keep the thrust.

Head clearance is part of his placement. The frame publishes a pad for the pony size, and the live
view pushes his eye out of her live skull and muzzle surfaces by that pad every frame, so a close
cheek or muzzle lean cannot enter her head as she turns; the kiss lean-in keeps its own smaller
distance. Her gaze and the kiss target his authored eye and mouth, never the game camera on his
standing rig, though the game's eye modifier is pointed at the same target.

His body keeps the authored placement. There is no second stroke asset: the attached alignment moves
his pelvis and never his whole body, reaching the hips first and fading up the spine with his head
and planted legs pinned, so the view cannot swing on a thrust. In both base poses the body carrying
him applies the wanted pelvis offset along her opening's normal, so his pelvis follows the entrance
and the shaft cannot slide out of his crotch. No separate bed holder is used.

## Free look

The debug free look turns the act view where it stands instead of holding the act's orientation, so
the pose and act keep running and the same frame can be inspected. Missionary turns his eye in
place, and standing leaves the player camera's base alone because standing has no separate view. It
applies when the panel closes, since the settings page pauses the world.

## Teardown and diagnostics

The player comes back first, then the act view is freed and the game camera returns, and only then
are the lean, the torso wrapper, the palm scale and the smoothed state dropped. With **Enable debug**
on, one line reports a lean the act refused and which condition held it back.