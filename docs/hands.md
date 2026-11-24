# Hands

The hands are the act's hand layer: where each palm sits on her coat, the caress that strokes it, the
shoulder reach, the smack and the hand scale. It is the authority for hand placement and caress state
in the two base poses; the pose supplies the body it touches, and the act scores what the hands
report.

## Controls

Each hand toggles on its own: a tap that is released quickly still latches, and the next tap stops
it, so both hands can caress at once. A per-hand key pauses and resumes that hand's oval; while the
auto-thrust panel is open its keys belong to the panel, but the hands keep their state and the
caress keeps scoring.

Lean and caress stay live through the standing afterglow, and in standing oral the same keys keep
their per-hand toggles and ovals while the target becomes the side of her head rather than the flank
chain. A smack takes a free hand while one hand still caresses, and that caress keeps running; a
hand on a shoulder reach is not free, and with both hands busy one is picked and its caress or reach
ends with the swing, so it does not come back afterwards.

## The paths

The pose chooses the geometry, and the path holds all of it. A marked-area chain runs up her side
from the flank to the neck, and the lean walks the hand along it; when the chain cannot be built, a
procedural flank or rump point stands in, carrying no sphere so its exact point and normal survive.
Missionary uses an authored chain of her rest points, in two variants that start at the belly or the
flank and end at the cheek or the shoulder. A lean walks toward the end of the chain and back walks
down it, and the hand walks back along the chain until the palm frame fits his reach, so a short arm
never stretches to a far point. A missing authored slot fails the path; there is no ray or camera
fallback.

Standing oral holds one authored point per hand on her head side. It is exact by construction, so
the engine skips the projection and the smoothing, and no mesh query ever follows the head; a hand
whose point is missing or too far from her head goes without a target rather than reaching her
flank. The two authored documents are written from opposite viewpoints: the areas are hers, so her
own sides are used as they stand while he is behind her, and the anchors are his, used as they stand
while he faces her. That is why the oral path, which reads one of her head points while he faces
her, swaps the side. A hand already caressing when contact switches to or from the mouth eases from
its live frame onto the other path; a fresh press starts straight on the current one.

## The boundary

Only the path turns a pose into geometry. The caress reads which family it is in and whether contact
is the mouth, and needs nothing else from the pose; the placement engine works from a pony, a path, a
side and a resolved context, never from a pose, so a new pose is a path and not a branch in the
stroke.

The caress always ends on her posed coat: the fitted spheres are built for the body in front of the
hand, and hull contact is not a caress. Only the shoulder reach and the smack's recovery ask the body
hull for a coat frame, which is why a hand resting on a hull shape never counts as touching her.

## The contact engine

Each authored area is one fitted sphere: the nearest coat vertex supplies its centre, its normal and
the skin weights the point follows, so the area rides her skin instead of a static rig. The oval
stroke offsets the intended point inside that sphere, the point is projected radially onto it, and
the radial direction becomes the contact normal, which is smooth at every point and needs no blur or
mesh query. What is smoothed is the snap correction, not the intended point, so the oval motion is
never delayed or shrunk, and the normal turn is clamped over time. The palm frame is built at the
result, and the last good target stands in when the path is unavailable or a candidate is not
finite; a candidate without a sphere keeps its exact point and path normal.

The coat fit is cached per skin and area, so a pony pays for each area once and later acts reuse it.
A winking body first maps an authored mare point through its rig, about the rear anchor, and may
snap a little farther than an authored point does, while head areas skip that map entirely: every
body wears the same head.

## Reach and smack

The shoulder reach is the standing side lean's hand: a palm flat on her shoulder, blended from the
rest hand and back again, with the glance looking over that shoulder while it holds. Missionary has
no reach, and the smack that takes the reach hand ends the reach and the lean action with it.

A smack chooses its hand and a pose target: the flank patch in standing or the decal centre in
missionary, offset by the player's smack values and scaled with the pony's size. Standing runs a
raise, a strike, a held contact frame and a recover; a hand already on the coat raises off it and a
free hand swings up from behind. The swing ends the chosen hand's caress or reach, so the palm is
free for the impact. The game's own impact keeps the decal, the blush and the jiggle, and the pony's
reaction signals are held off around it; the pack's smack sound is installed just before impact and
restored when the act ends, and a short cooldown gates the next swing.

## Scoring

A held caress reports one touch after enough contact, not one per physics tick, so a tap too short to
reach the meter scores nothing. A touch uses the game's normal cooldown and its assist cap; a
disliked caress subtracts and leaves her briefly overwhelmed. In the standing afterglow enough live
caress time grants the close window's full reward and repairs a little of a bad act's hurt.

## Settings and debug

The smoothing values, the palm hover, the oval radii and the contact smoothing are the player's
contact knobs, and the pose's path choice selects the authored chain. The placement engine and the
paths receive resolved values and read no settings, so the hot path stays a value read. The same
height preset scales the caress offsets; the other presets keep their authored values.

With **Enable debug** on, the overlay draws the path anchors, the contact, the palm target and the
hand itself, one precise line per hand records the stroke, and each coat fit reports how far its
sphere sits and whether it had to snap; with **Print perf logs** on, the caress stages are timed
apart from the rest of the tick.
