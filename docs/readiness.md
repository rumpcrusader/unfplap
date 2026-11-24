# Act readiness, strength and auto thrust

Readiness is the act's readiness loop: the measured stroke, the physical strength value,
satisfaction, mood and cues, the pony's climax count, the touch and talk assist, the
neglect-tolerance meter and the automatic stroke. The long-term summary and history belong to
`summary`, cue admission and the prompt to `dialogue`, the HUD shorthand to `hud` and the camera's
response to `camera`.

## The stroke

A stroke is continuous movement in one direction, closing on a real reversal or after a short
stillness. Its bottom is a separate event: it fires at the reversal or after a brief stall without
real progress, and it drives the jiggle, wings, blush, ear twitch and the body slap, so the slap
and the flinch arrive with the movement rather than at the close. The close is the only event that
scores.

A thrust is an inward stroke that travels far enough and lasts long enough. Tiny jitter, pullbacks
and outward strokes are presentation: they update no axis and score nothing.

## Strength, depth and intensity

His strength is the physical impact value. Travel matters most and average speed scales it, with a
floor that keeps a slow full-depth stroke soft and a cap so one fast sample cannot saturate it.
Visual response follows strength, while the flank wobble follows travel, so a full stroke swings
the same at any speed.

The body slap is gated on true contact and tiered by the speed at the bottom. That speed counts
only the intervals that actually deepened, so a pause or jitter at the bottom cannot dilute the
tier: a touching stroke below the firm tier is a slow press and stays silent.

The intensity preference is read from travel and the pattern from tempo. The axes are independent,
so a deep slow stroke is rough and a shallow fast one is soft, and the physical strength stays the
foley and impact value rather than the preference band.

## Readiness

Satisfaction is readiness, and it rises in discrete chunks from real thrusts rather than on a
passive timer. Hitting both preferred axes gains the most; one matching axis still gains something,
while a full mismatch gains nothing at all and stopping merely pauses it. A liked touch or talk adds
once and caps the assist short of a climax, so only real thrusting can finish her; a disliked one
subtracts and leaves her overwhelmed for a moment. Touch shares one scoring cooldown across caress,
kiss and smack, and talk has its own, so alternating inputs cannot bypass either. The meter never
decays on its own, and a mismatch is never a hard stop.

## Mood and cues

Mood follows readiness through warming, wanting and close, with a climax mood and an overwhelmed
state of its own. The base cue asks the player to keep going, a liked or disliked touch or talk
sets its own line, and the assist-cap lines say plainly that hands or words cannot add more.

## The pony's climax

At full readiness she climaxes. The configured limit may be zero for an unlimited act. The act
enters its climax state for a fixed span, counting the climax and setting its cue, and the player
may keep thrusting through it: that thrust is presentation and changes no score. When the span ends
she either returns to the act with the meter reset, or, at a configured limit, the act moves on to
afterglow.

## Neglect tolerance

Tolerance is a per-mare preference tier (forgiving, normal, strict); the per-act thresholds are
debug declarations, so an edit reaches the meter on its next generation. Each real disliked touch
or talk adds distress, each liked one relieves it, and passive time decays it. Warnings are one-shot
per act: compensation can lower distress and avoid a stop, but it never replays a warning. A
forgiving mare is never stopped, a normal one warns twice and then stops, and a strict one warns
once and stops sooner. The meter yields at most one decision per frame, and a stop is the only
decision the act acts on, through its own stop path.

## Auto thrust

The automatic stroke generates the depth the mouse would, through the same tracker, so it adds no
score, heat or presentation path of its own: intensity, pattern, readiness, audio and the body all
follow the manual rules. A tap of X starts and stops it at the hand's current depth; the wheel sets
the pace; holding X opens a small layer for the band and the shape while it freezes the lean, the
caress keys and the kiss. The band keeps each stroke wider than the tracker's reversal gap and the
smallest peak still reaches a thrust's travel, so nothing generated is too shallow to count; every
shape returns to the bottom, so the tracker only ever sees depth. The mouse does nothing meanwhile.

A body swap stops the running stroke but keeps the live band, pace, shape and the on/off intent; the
resumed act restarts it at the current depth, while a fresh act starts from the settings defaults.

## The cycle

The estrus feature multiplies every scored thrust while she is in heat. The phase and the diestrus
start block are the act gate's, not this service's.

## Settings

The thrust, cooldown, receptive-window and cue-pacing values are settings declarations with their
own bounds; the tolerance tier is a per-mare Characters preference.
