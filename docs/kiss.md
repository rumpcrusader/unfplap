# Kiss

The kiss service owns the act's kiss: the standing path through the game's own kiss, the missionary
custom head aim, the lean and mouth values, the foreleg pin, the release and the restart cooldown.
The act state, the camera and the face are not its own.

## Two paths

In standing the act reuses the game's kiss, so her face, mouth, deep kiss and soft-kiss audio are the
stock ones. The stock pose modifier is moved to the end of the skeleton so its IK layers on top of
the act pose, and a release ends the game's affection. The side is latched from the input lean, not
the lagging camera, and pinned to the complementary side so the two heads interlock instead of
colliding; the stock side switch is held off for the act.

Missionary always takes the custom path. The stock kiss is authored for a standing pony: its chest
and neck give lift a lying body off the mattress and turn her head across it. Her look blends from
his eyes to his mouth as the kiss fades in, so her head leans in instead of snapping, and the target
is his authored mouth on the bed rather than the game camera on his standing rig. The mouth
expressions and the kiss sound still run.

The kiss does not move the view's base: his eye keeps a clearance to her face, and the head aim does
the reaching.

## The lean

Both paths start from a full lean with the kiss key held; standing reads the side lean, missionary
the forward lean and requires the forward key too. A side press also pushes the forward target, so a
side-only lean would otherwise start the kiss; the extra key prevents it. Releasing the key or
dropping the lean ends it.

Anon leans in, shifts to the shoulder side and drops by the live presentation values, and the camera
yaws toward her; the values apply live. The lateral offset crossfades from the lean's offset to the
kiss's instead of adding both, which would overshoot her neck and push her muzzle back. The forced
over-the-shoulder glance is cleared and her head eases back while the kiss and its release run, so
the kiss head pose is not fought by the reach.

The kiss key never ends the act, and a stock hug or deep kiss cannot end the act's kiss.

## What the stock kiss drags along

The game's kisser is inactive for the act's whole length, so the act supplies the stock kiss with the
current mouth, eye and face and repeats the mouth kiss sound itself. A shared lock keeps the game's
excitement Beat paused, so no unicorn sparkle plays and reads as a spell; only the last release
restores the Beat.

The stock kiss bends her chest to reach him, and that motion arrives after the upper-arm pin, so her
forelegs would slide. A modifier that runs last captures both hoof tips before the kiss and solves
the real leg chains back to them. The stock rear and hoof kiss settings are saved and zeroed for the
kiss and restored after.

## Shared rules

Either path may stop her current speech, but not thrusting or the act's stats. The act's own
affection-driven kiss counts as part of the act, not as an interruption, and a changed pose family
or kiss profile never ends a running kiss or releases its pin; a shared config keep is a no-op.

The side latch and the pose lock clear when the lean returns to zero. A completed kiss has a short
restart cooldown before another can start. The kiss also owns its own lid layer, so the act stare does
not override it.

## Boundaries

The runtime owns the controls, the state machine, the camera and the teardown. The pose service owns
the act body, and the world boundary owns the base-game reads and writes. This service keeps only the
kiss state and the bridge to the stock pose.
