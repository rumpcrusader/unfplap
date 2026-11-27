# HUD

The HUD is the mod's one screen surface: the act's text readouts, the control card, the toast line,
the game caption's act-only move and the act-key notice, plus the borrowed quick-slot card. It owns
what is on screen and gives back what it borrowed. The readiness values behind the readouts belong
to the act readiness system, and the close window belongs to the afterglow.

## The act card

The card appears for the act's active, climax and afterglow states, and an act outside them has no
line. Its top is the cue line, which carries the hearts and the current cue; underneath sit the
readiness line, the form row, the automatic readout and then the controls. The card reads one typed
act view per rendered frame, never probing the runtime.

The cue line always keeps the hearts; with `hud_readouts` off the cue and readiness segments hide.
The afterglow keeps the close prompt in the cue when one exists; otherwise the cue carries the
summary, and where the cue must keep the close prompt the summary takes the readiness line. An empty
cue reads as a dash where the segment is still shown.

The automatic readout shows only while the automatic stroke runs. Opening the auto settings replaces
the card with the depth, pace and shape rows, because those keys mean something else while the layer
is open.

The act-key row is the card's one changing control: it reads whether the act is early, active or
closing, and its colour warms one step per climax up to a cap. Only the earned standing afterglow
caress turns it fully to the accent colour. The pose rows name actions rather than both keys, and
they follow the pose family rather than a raw pose id.

The form row stays in the card even though the act never fills it, so the rows above and below keep
their places. The shape reveal and the gift are something the player works out from her words and
behaviour; no build names them on the HUD.

## Afterglow

The control card as a whole belongs to `act_controls`. The afterglow hides what cannot act: the
automatic stroke, the smack and the thrust row are gone, while the missionary arrangement keeps the
lean, caress, caress movement and act key, and standing keeps the lean, reach, caress, caress
movement, kiss and act key. The summary stays visible regardless of the readout setting.

## The caption move

The game caption moves to the top only during the act's opening, active and climax states, only when
the `captions_on_top` option is on, and only when the game's own speech setting is the explicit
bottom caption; the afterglow puts it back. Every caption the game builds is tracked, a caption
created while the act runs is positioned immediately, and the settings-page preview is never moved.

The move lands after the caption's own layout pass because the entry that reports the live act state
runs later in the frame. The HUD never subscribes to the game autoload; it listens on the settings
service's game channel and re-applies the mode only when the speech setting changes.

## The offer hint and the toast

The offer hint is one row on the game's corner control card, so it sits among the game's own
controls: a drawn key cap for the act key, which the game has no icon for, beside the words. A
headset has no card, so the same hint is built into the HUD's own centred prompt. The HUD compares
the words and the rows itself, so a steady frame only advances the card's fade.

The toast is the mod's only toast: a short corner line that the next one replaces, at the caller's
duration. A caller holds a live HUD and guards for its absence, so a bare runtime is a quiet no-op.
The act-key notice is one toast per world, shown once when the bundled Dance Mod is on and the act
key is not its Y.

## The borrowed quick slots

The act borrows the game's quick-slot card and hides it, saving exactly what it found so the same
call can put it back. The idle safety check restores it only when the live act owner's state is idle,
because every idle sibling runtime sees the same borrowed flag and none may take it from a running
act.
