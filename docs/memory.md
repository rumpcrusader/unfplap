# Act memory

The memory service owns what the mod remembers and what it makes the director say. It writes the
impressions and world-context events an act leaves behind, keeps the strongest act as a per-mare
peak, tests who saw the act and records one perception for each of them, and queues the mod's own
spoken lines. It is the authority for the wording and the idempotency of those writes; the grade,
the act state, the offer decision and the cue's admission belong elsewhere, to systems that read
the facts this service leaves.

## What it owns

A pure core holds the typed values and the fixed wording; scene adapters read the game's world
context, impressions and story journal, the conversation director's authored-line queue, and the
live mares. The peak memory is the one value the mod persists. Every other value belongs to the
game and is only read or written here. A game read is guarded, so a game update that removes a
queue or a field makes the writing stop rather than error.

## Impressions and events

One impression write carries her mood, an optional romance value, a private thought and a
profile-safe event line. Its slot chooses the idempotent id suffix and whether a world event
follows. The line begins with the pair, letting the profile drop her name in, and the pony is never
addressed as "you" after that point; the thought stays first person and never passes through the
profile, because it is shown in her own voice.

Staying close has its own slot and a thought chosen by the act's warmth. The reveal of her true
form is the one exceptional beat, with fixed private and public wording and a peak of its own; her
stable identity names it, never the borrowed form she is wearing.

The fixed intimacy notes cover a cancel, her climax, a stop and an apology. The stop vocabulary is
the reachable reasons only. There is no world-close stop: closing a world does not produce a stop
reason the note could carry, so none is named for it.

## The peak

One strongest clean act per mare is kept and never expires; a later higher score replaces it. Only
the peak is written by the mod itself, and only its writer asks the game to save.

## Witnesses

The read-only test lists the adults who can perceive the act right now, with the sense each used,
and commits nothing. The committing pass runs the same test and leaves one private perception per
observer. An adult who sees or hears the pair receives a witnessed-intimacy row and a neutral
thought, so an older unrelated impression is replaced rather than inherited. The age split that
admits a young bystander comes from the eligibility capability, not from a local copy; a young
witness gets a scene row whose gossip varies between passes, no thought and an amused mood. What
she remembers afterwards is the game's own story summary, formed from that perception.

The partner, a sleeping pony and a pony with no identity are skipped. The whole act is skipped when
the player is in a young form or the partner has left the tree.

## The line channel

The mod queues a reaction, a ready cue utterance or a bystander line through the game's director.
A reaction falls back to its own shipped line when the caller gives none, and a climax adds the
first-person thought instruction and the face note. Every key is prefixed by the act's event id, so
one act's lines can be dropped together. Cancelling keeps only a line that is already speaking, and
only while the caller asks to keep it; a queued or generating line never outlives its act. The
returned state distinguishes a line already rendering from one delivered, absent or unknown.

## Cue facts and shared memory

The cue prompt receives private relationship facts: friendship and love levels, the relationship
stage, anger, mood, a first-time flag and a careful flag. The first-time flag looks for an earlier
intimacy event and a stored act, excluding the current event, and no raw score leaves the record. A
shared memory is one unused beat for the cue: the stored peak first, then the story journal by a
cue-word match or the latest exchange with the player, then the older world events. Used ids are
skipped, and a memory is marked used only after the caller has queued its line.

## Idempotency

The event id is the only guard against a double write: the game ignores an event or an impression
under an id it has already seen. A caller that reuses an id for a different act therefore reaches
neither store, and the second write silently does nothing.
