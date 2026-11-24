# Act audio

The act audio service is the one authority on what an act sounds like: the pack foley layer, the
game's own breath and climax voice, and the policy that mutes her Ponese audio. It owns the
process-lifetime playback pools and the per-act handle that every act module calls; it owns no cue
outside an act, and the outside-act flank smack is its own subject.

## The pool and the handle

The pools and the base-game sound players exist for the process, so an act pays no player build and
no stream load. The handle binds the body, the stable id and the bed when the act opens, and every
call without it is a quiet no-op, which is how a suite constructs one. Ending the act restores her
voice and silences the cues and the breath but leaves the players for the next act. A world close
silences the same players; shutting the service down is the only path that unsubscribes and frees
them.

A single pool serves a single act at a time, so the act asserts one owner. The handle is per
runtime: simultaneous acts would need a pool per handle, and no consumer would change.

## Strokes and the bed

The bottom of a stroke is the body slap, the bed or fabric layer and the inward slide. A plap tier
arrives from the stroke tracker; the slap needs both a tier and a real skin gap inside the contact
window, and a window of zero matches only full contact. A touching stroke below the firm tier is a
slow press and stays silent.

The bound bed decides the surface: a bed-bound act gets the bed layer, a bed-less act gets none, and
only a couch, sofa or cloth surface adds the fabric layer. The pose view's impact profile is
deliberately left unread here, so a pose cannot invent a surface the act has not bound; the deferred
stroke event will carry the profile instead.

The caller asks whether this frame crosses outward and then plays the outward slide on that frame,
so an act that skips frames does not have to read the rump every frame. The depth pair travels with
the request because the tracker owns depth and an audio-side cursor would go stale across the
skipped calls.

## Her voice

Her generated line plays through the director's own vocal player while the director is idle, at
most once per cooldown; a stroke inside the cooldown stays silent. The `mute_ponese_audio` setting
keeps the text HUD and the generated line but silences only a voice that is effectively Ponese; a
generated character voice is left alone.

The mute setting is live without an act call: the service reads it and follows the settings change
notification itself, so an edit gives the saved volume back and applies the new policy to every open
handle. A body change rebinds the handle, which returns the old player's volume and applies the
policy to the new body's own player.

## Kiss, climax and breath

A kiss that lands without the mouth contact plays the pack cue at her snout; the oral turn's idle
timer uses the game's own soft kiss. Her climax is the game's squee at her snout, with no pack layer
of its own.

The rendered tick runs the vocal cooldown down and drives the breath from the act state and the live
thrust rate: posing in and restore are silent, the active act breathes, the climax peaks and the
afterglow fades. A body swap cuts the breath and the next act restarts it.

## The game's vocal cache

The game caches one vocal player per pony id and parents it to her body. A body change frees that old
body and leaves a freed instance in the cache, and the game's typed read at play time fails before
its own validity guard. The service clears only this runtime's own id before the next play, guarded
against a changed or missing cache, so the game builds a fresh player under the presented body; it
never touches another pony's entry.

## Settings and packs

The Ponese mute is the act audio's only setting, and the base-game breath and climax are always on.
The foley streams belong to the external resource pack, so a checkout without the pack cannot run
the act.
