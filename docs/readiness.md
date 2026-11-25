# Act readiness, strength and tolerance

Readiness is the meter of one act. It measures the stroke, follows her satisfaction along with her
mood, her cue and her climax count, scores the caress, the kiss, the smack and the player's own
words, and keeps the neglect-tolerance meter that can end the act. The automatic stroke is
`auto_thrust`'s; the long-term summary and history belong to `summary`, cue admission and the
prompt to `dialogue`, the HUD shorthand to `hud` and the camera's response to `camera`.

## One owner of the act's state

The act starts the meter, opens the scoring window once the pose has settled and ends it. Nothing
else writes it: a caller takes the one live readout and reads it, and the summary takes a copy of
the counter record at its verdict. The meter ticks itself — staleness, the overwhelmed pause, the
idle stroke, the cue and the tolerance decay all run inside the service, so the act neither polls
nor drives it. The act hears the meter only through its events: her climax, the close threshold, an
overwhelmed beat, a cue change, a tolerance decision and a stroke that closed on an idle frame.

## The stroke

A stroke is continuous movement in one direction, closing on a real reversal or after a short
stillness. Its bottom is a separate event: it fires at the reversal or after a brief stall without
real progress, and it drives the jiggle, wings, blush, ear twitch and the body slap, so the slap
and the flinch arrive with the movement rather than at the close. The close is the only event that
scores, and it is scored inside the meter. A stroke that closed on an idle frame reaches the act
through the meter's event instead of a call, with no withdrawal slide because the depth did not
change.

## Strength, depth and intensity

His strength is the physical impact value. Travel matters most and average speed scales it, with a
floor that keeps a slow full-depth stroke soft and a cap so one fast sample cannot saturate it.
Visual response follows strength, while the flank wobble follows travel, so a full stroke swings
the same at any speed.

The body slap is gated on true contact and tiered by the speed at the bottom. That speed counts
only the intervals that actually deepened, so a pause or jitter at the bottom cannot dilute the
tier: a touching stroke below the firm tier is a slow press and stays silent.

The intensity preference is read from travel and the pattern from tempo. The axes are
independent, so a deep slow stroke is rough and a shallow fast one is soft, and the physical
strength stays the foley and impact value rather than the preference band.

## Readiness

Satisfaction is readiness, and it rises in discrete chunks from real thrusts rather than on a
passive timer. Hitting both preferred axes gains the most; one matching axis still gains something,
while a full mismatch gains nothing at all and stopping merely pauses it. The body change's warmth
is the only reward that does not come from a stroke, and it arrives as the provider's own number. A
liked touch or talk adds once and caps the assist short of a climax, so only real thrusting can
finish her; a disliked one subtracts and leaves her overwhelmed for a moment. Touch shares one
scoring cooldown across caress, kiss and smack, and talk has its own, so alternating inputs cannot
bypass either. The meter never decays on its own, and a mismatch is never a hard stop.

## Mood and cues

Mood follows readiness through warming, wanting and close, with a climax mood and an overwhelmed
state of its own. The base cue asks the player to keep going, a liked or disliked touch or talk sets
its own line for the configured lifetime, a form's line and a warning come in with their own, and
the assist-cap lines say plainly that hands or words cannot add more. The act hears a cue only when
its text or its nature changes, not on every frame.

## The pony's climax

At full readiness the meter reports her climax once the call that filled it has finished writing.
The configured limit may be zero for an unlimited act. The act opens its climax state for a fixed
span and hands the span to the meter, which counts the climax and sets her cue; the player may keep
thrusting through it, and that thrust is presentation and changes no score. When the span ends she
either returns to the act with the meter reset, or, at a configured limit, the act moves on to
afterglow.

## Neglect tolerance

Tolerance is a per-mare preference tier (forgiving, normal, strict); the per-act thresholds are
debug declarations, so an edit reaches the meter on its next generation. Each real disliked touch
or talk adds distress, each liked one relieves it, and passive time decays it. Warnings are
one-shot per act: compensation can lower distress and avoid a stop, but it never replays a warning.
A forgiving mare is never stopped, a normal one warns twice and then stops, and a strict one warns
once and stops sooner. One input produces at most one decision and the decision arrives as an
event, so two dislikes in one frame are two presentations where the old single queue kept only the
last; only a stop reaches the act as work to do, and it leaves by the act's own stop path.

## The end

The act's end stops the scoring, the input and the stroke, and the meter then runs down to zero on
its own while the afterglow and the HUD keep reading it. A new act starts over and cancels a run
that is still going.

## The cycle

The estrus feature multiplies every scored thrust while she is in heat. The phase and the diestrus
start block are the act gate's, not this service's.

## Settings

The thrust, cooldown, receptive-window and cue-pacing values are settings declarations with their
own bounds, read where they are used so a live edit reaches the meter at its next use rather than
at the next push; the tolerance tier is a per-mare Characters preference.
