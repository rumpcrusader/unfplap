# Act audio contract

The act's sound: the pack foley layer, the base-game breath and squee climax, and the Ponese mute
policy. One world service owns the playback; one handle per act drives it.

## Ownership

| Module | Role |
|---|---|
| `audio/api.gd` | the world Node facade (`shared/service.gd`) and the `ActAudio` handle the act modules call |
| `audio/pool.gd` | the process-lifetime cue player pools and the one variant, level and pitch write |
| `audio/cues.gd` | the pack cue catalogue and the pure rules: tier, contact, bed profile and level |
| `audio/sound.gd` | the base-game breath and `squee_*` climax players, built once and reset per act |
| `docs/audio.md` | this contract |

The entry's service list creates one `audio/api.gd`. It owns the cue pools, the base-game sound
child, the live `mute_ponese_audio` read and its settings subscription for the process. The bound
body, the bed, the vocal cooldown and her voice player belong to the `ActAudio` handle;
`act/build.gd` constructs one per runtime from the world service, and every member no-ops without
it, which is a suite's construction. Both the context field and the builder's `Bundle` field are
`RefCounted`, so a suite can substitute its own handle.

## Act lifecycle

- `begin_act()` binds the pony, the stable id and the bed, resets the breath clocks, registers the
  handle with the world service and applies the voice policy. The pool and the sound players
  already exist: an act pays no player build and no stream load.
- `end_act()` restores her voice, silences the cues and the breath, and leaves the pool and the
  sound child for the next act. The world close silences the same players; `shutdown()` is the only
  path that unsubscribes the settings listener and frees the players.
- One pool for the process assumes one act at a time (`PONIES.set_active`). The handle is per
  runtime, so a future simultaneous act needs the pool per handle and no consumer change.

## Strokes

- `impact()` is the stroke's bottom: the body slap, the bed layer and the inward slide. The tier is
  `firm`, `rough` or empty and comes from the tracker; the slap needs both a tier and a skin gap
  inside the contact window, and a zero window with a zero gap is full contact.
- The bed and fabric layer follow the bound bed: a bound bed selects the bed profile and a
  bed-less act plays none, while only a couch, sofa or cloth surface gets the fabric layer. The
  pose view's impact profile is not applied in this version; the bound bed decides until the
  deferred typed stroke event carries the profile.
- `crossing_out()` answers whether this frame fires the outward slide, so the caller can skip the
  skeleton rump read on every other frame. `slide_out()` plays it.
- **Debt:** the tier is still a string and the outward crossing takes the depth pair instead of a
  tracker event. The tracker owns the depth, so an audio-side cursor would go stale across skipped
  calls. The `StrokeEvent` move to `shared/` retires both.

## Kiss, vocal, climax and breath

- `mouth_kiss()` plays the pack kiss at her snout for a kiss that lands without the mouth contact;
  `oral_kiss()` is the base game's own soft kiss on the oral turn's idle timer.
- `vocal()` plays her generated line through the director's vocal player, at most once per cooldown
  and only while the director is idle. A stroke that arrives during the cooldown stays silent.
- `tick()` is one rendered frame: the vocal cooldown runs down and the base-game breath follows the
  act state and the live thrust rate. Posing in and restore are silent, `ACTIVE` breathes,
  `CLIMAX` peaks and `AFTERGLOW` fades. The cooldown moved here from the physics frame, so it
  advances with the rendered act instead of the physics tick.
- `climax()` plays the base-game squee at her snout. There is no pack climax layer.
- `silence_breath()` cuts the breath for a body swap; the next act's `begin_act()` restarts it.

## Voice policy

`mute_ponese_audio` keeps the generated line and the text HUD but silences the pony's Ponese audio
for the act. Only an effective Ponese voice is muted; a generated character voice is left alone.

The setting is live without an act call: the world facade reads it and subscribes to the settings
change notification itself, so an edit restores the saved volume and applies the new policy to every
open handle. A body change rebinds the handle, which gives the old player's volume back and applies
the policy to the new body's own player.

The routing classification is `shared/voice_status.gd`, a pure match over the facts it is handed.
The world director view builds those facts from the live director's profile, its TTS node's mode and
server answer and the game's own chatter routing; the game's TTS switch arrives as the second
argument, which each caller reads from `SETTINGS.tts_enabled()`. The view's debug context carries
the routing line it reports, and the gate's debug text reads it from there.

## Base-game vocal cache

The game's `world/ai/vocal_noises.gd` caches one `AudioStreamPlayer3D` per pony id under
`_players`, parented to her body. A body change frees the old body and leaves a freed instance in
that cache; the game's typed read at `play()` fails before its own `is_instance_valid()` guard.
`audio/api.gd` clears only this runtime's stable id before the next `play`, guarded against a
changed or missing cache, so the game creates a new player under the presented body. It never edits
the game file or another pony's entry.

## Packs and settings

- The pack foley files are fetched from the resource archive and packed; see `assets/README.md`.
- `features.mute_ponese_audio` gates the Ponese mute. The outside-act flank smack is its own world
  service; see `docs/stock_smack.md`.
- The base-game breath and squee are always on and are not gated by a flag.
