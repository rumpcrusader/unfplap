# Thrust and climax reactions

The reactions service owns the scene effects that ride an act's thrust and climax: the standing
rump jiggle and the coat target it drives, the carry of a smack into the tail, the standing rump
blush, and the climax heart pulses with the dock burst. It does not own the act state, the stroke
math, the act audio, the wings, the tail pose, the ear twitch or the HUD; it turns an impact the
act has already decided into presentation.

## What an impact starts

The bottom of a stroke fans out to the wings, the rump effects, the standing blush and the ear
twitch. While her mouth is on him the plap, the rump wobble and its tail carry are skipped, because
that motion belongs to the other body; the wings, the standing blush and the ear twitch still run,
and the audio owns the body plap.

## The rump jiggle

The stock flank touch holds one wobble at a time, so one shared shader center on the rump midline
makes both flanks move together. The center is the midpoint of her hind femurs plus the tuned
height and backset; without a skeleton it falls back to the shared approximate rump anchor.

The stock slapper clamps its own impulse, so the service hands it a full one and scales the
resolved amount itself by the stroke's weight, her size and the act's jiggle intensity. A smaller
pony then gets proportionally less shader travel rather than a weaker stroke reading. One process
step is re-run after the scale so a soft stroke does not flash at the previous full amplitude.

The jiggle radius is written to every live target material and remembered; the teardown clears it so
a stock smack outside an act gets the shader's own default again. The service never clamps a
setting-derived radius or smack intensity.

## The coat target

Her patched coat no longer answers the stock shader check the same way, so the service asks anatomy
to enrol the coat and outline materials it has, and any it gains later, with the flank on every
thrust. The stock flank touch rebuilds its own target list on every slap, which is why anatomy has
to re-add after each start. The registration covers the body and its outline and, when the merged
near mesh holds her body, that mesh's palette and outline too. The flank is found lazily, so a
stock smack outside an act still reaches the coat, and the coat setting is read live.

## The smack

A smack has already started the game's native cheek jiggle by the time the act sees it. The service
carries that same wobble into the tail base, scaled by the act's smack intensity and her size, and
writes the act's radius over the live targets. At act start the stock redness marks are hidden and
aged, so the act's own blush and mark speak for her skin; a smack outside the act leaves them
alone.

## The rump blush

Only a standing act builds it. A strong enough thrust steps the blush up to a cap and it fades over
time. The decal is made on the first step from the flank's own rump-blush texture, rides the live
hind-femur point so it follows the body sway, and is freed at the end. It is separate from the face
blush and from the stock marks.

## Climax hearts

The climax schedules a first full burst, then a smaller pulse a moment later, then a last single
heart after a further pause, all inside the act's climax length. The dock has its own burst,
triggered by the climax transition rather than by this schedule. Each pulse uses the same heart
effect as a boop without counting one or restarting her blush and squeak. The burst can be moved to
a chosen origin, which the standing afterglow close and the climax start use.

## Tuning and teardown

The act snapshot pushes the pose family, her size, the climax length and the jiggle values in one
configuration; the block is complete, so the service keeps no fallback of its own. A fresh act
clears only the live visuals and keeps the tuning. The end frees the decal, drops the tail handle
and restores the radius.
