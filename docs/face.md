# Act face

The face service owns the act's one expression owner: the beats at the act's moments, the rule that
a spoken line owns the face, the stare release and eyelids, the smile with its hold, and the held
post-act mood face with its warm note. It does not own blush, the kiss, the HUD or the summary grade.

## Beats

The act sets a face at its moments: shy on a first time and relaxed on a repeat, anticipation as she
nears, a climax face chosen from how the act is going, an afterglow face from the summary, and sad or
annoyed on a warning or when she is overwhelmed. A warm, well-matched act may blush and part her
lips; a weak or distressed one keeps the wide-eyed stare. A face with a hold finishes itself after
the hold; an empty result does nothing.

The beat plan is pure and data-driven, and the expression table belongs to the caller: every name is
validated against the table the caller hands in, so a face the game does not know is refused rather
than applied.

## The line owns the face

A spoken line's face always wins until it ends. The act's face refuses while another line owner holds
the expression, so the act cannot talk over the director. Ending the act clears only the face the act
set, so a director line survives teardown.

The beat writer is the only path that sets a beat; it applies the face-debug flag before the table
runs. The post-act mood face is independent of it.

## The stare and the lids

The act releases the stare on a warm climax or while a kiss is active, then reasserts the state's
lids: half-lidded through positioning and the act, wide at the climax, sleepier in the afterglow and
sleepier again when the close window was rewarded. The release is applied once, so a reassert does
not run every frame. The act runs no expression of its own while a kiss owns her face.

## The held post-act face

A completed act that is not a partner stop starts one held face. A summary supplies the face and the
mood; a rewarded act at or above her aftercare minimum also gets the warm note and a soft blush. If
no summary exists, a relaxed fallback appears only when her minimum is still met.

The face yields to any spoken line, ends when its freshness runs out, and ends early when her AI
commits a different mood, so it never outlives the note it shows. It owns no navigator and blocks
nothing. A partner stop gets the refusal face and no blush, and a new act clears the held face.

## Failures and lifetime

With no controller, no tree or an unknown face nothing is applied, and a missing bind is repaired on
the first call. The hold timer lives under the runtime host and is freed with it; the mood-face node
frees itself when it finishes. The act face and the held face are dropped on shutdown.
