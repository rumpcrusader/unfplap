# Act dialogue

The act dialogue service owns what the mod makes a pony say during and around an act: when a cue
becomes a spoken line, what the cue prompt carries, the reaction lines, the bystander line and the
idle scan. The act state, the line channel and the act face belong to their own systems.

A **line** here is one spoken or generated dialogue line, not a source-code line.

## When a cue may speak

A cue is event-driven, not a timer: it must change and stay changed, and a live touch or talk
override gets a shorter hold because its cue disappears with the override. Demand cues are paced with
a wider gap and guarded against the identical text repeating. The same text is not queued twice in a
row, but may return after another cue. The **Talk & cues** debug settings own the pacing values; the
per-mare cue gap is the profile's.

Only one line owns the shared utterance slot at a time. A cue asks whether the slot is free and
whether the director or the pony is already talking; a reaction bypasses the cue pacing but resets
the shared gap so a cue cannot follow immediately. A queued or generating row expires at its age; once
a line is audible it is left alone.

A cue queues only while she can speak. The pose's contact must not be a mouth contact, and the bed
face-sit's face contact is not one, so it queues and speaks normally. Entering oral ends the act's
own lines, stops her base-game voice and re-asserts the oral mouth shape; no climax line is queued
while oral lasts, and bystanders keep their own turns. Every climax and afterglow boundary and every
act end cancels queued and generating lines, while a line already speaking may finish; the early-stop
line is queued after that cancel.

## What the cue carries

The cue prompt's mandatory context is the moment, the state line, the relationship note and its
tone, one shared memory, the face hint, and the preference and recent-line blocks. A part whose slot
is empty is dropped whole; a direct slot renders empty and the rest of the line keeps its shape.

The relationship note is private context, and the tone is an instruction for how openly warm the
line may be, never a label she says aloud. Hurt overrides depth with a careful tone. A guarded line
is for an acquaintance with no romance and a friendly one for a friend; romance lets her warm
further, a first romantic encounter turns tender, and a marefriend is warm. The note also carries the
bond stage, whether it is a first time, and the current mood.

The face hint suggests one valid face tag at the start of the line and, when the moment genuinely
changes how she feels, a feeling tag after the spoken words. Voice emotion stays in the prompt text:
the act's default is a whisper, with calm, happiness, annoyance, surprise, sadness or fear by moment.
The act's own summary may still overwrite the stored mood when the act ends.

A pony a body-change source handles also gets a live body line naming her presented form and whether
it is her own. This line, not the history, tells the model her present shape; an old event may still
describe a previous one. A pony with no such source adds nothing.

One unused shared memory may ride with a cue, colour rather than script: a stored peak is preferred,
then the story journal, then older world events. Intimacy events and private notes are skipped. The
line-angle note adds one fresh angle and a "use something from today" hint, and the optional speech
interjections pace her words to the strokes.

## Reactions and bystanders

A reaction is a generated line with a validity rule the channel re-asks when it delivers, so a stale
line is dropped and a speaking one may finish. The act's reactions are the climax, an intentional
early end, a history refusal, the tolerance warning and stop, and the body-change offer once per act.

The bystander pass is always on. It picks one adult observer who can perceive the act, waits before
the first line, then repeats on a chance roll up to its cap; its validity rule checks the observer,
the act event and the live state, and the wording comes from an indoors or outdoors house lookup.

## The idle history scan

The scan runs only while she is idle and the game is unpaused. A sincere apology repairs hurt, but
only from the pony currently in conversation with the player and only once per in-game day. A pending
complaint or reminder is spoken at a quiet moment when the player is near and the director is idle;
the first tier is a rare, vague hint with no list of wants. A queued line marks the row announced, so
the same act does not speak twice.

The stored row, its tiers and its wording belong to the summary service. The scan only asks it what
to say and writes the repair back.

## Boundaries

The mood and cue text belong to readiness, the line channel to memory, and the act face beats to the
face service. This service never queues a line for a busy mouth or repeats a cue the act already
spoke.
