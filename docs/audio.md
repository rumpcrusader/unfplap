# Act audio contract

The act's sound: the pack foley layer, the base-game breath and squee climax, and the Ponese mute
policy.

## Ownership

| Module | Role |
|---|---|
| `audio/act.gd` | the per-act handle the act session and exit call: node lifetime, cues, voice policy and the shared excitement Beat holds |
| `audio/service.gd` | the per-runtime audio facade: the pack layer, the base-game sound child, and the Ponese mute policy |
| `audio/sound.gd` | base-game breath and `squee_*` climax players and their timing |
| `audio/cues.gd` | the pure pack cue table (groups, variants, volume, cooldowns, pitch) |
| `docs/audio.md` | this contract |

`audio/service.gd` is one Node per runtime. `audio/act.gd` is the one act handle: the builder
binds it once and it creates its node lazily, keeping it for the process; `start()` opens an act's layer and `stop()`
closes it. It never preloads `runtime.gd` or `main.gd`; the builder passes the node and the act
passes the pony, the id and
the classified voice info as arguments. The shared game excitement Beat is held by owner name
(`hold_excitement(owner)`/`release_excitement(owner)`); the last release restores the saved pause
state, and `reset_excitement_hold()` is the teardown fallback. The outside-act flank smack is its
own world service; see `docs/stock_smack.md`.

## Bridge

The act modules call one typed handle, never a private field or a raw player:

| Method | Call site |
|---|---|
| `start(pony, id, bed)` | the start sequence, after the vocal prepare |
| `stop()` | the one teardown ledger |
| `play_climax()` | the climax fan-out |
| `tick(delta, state, rate)` | the breath path in the tick |
| `apply_voice_policy(mute, pony, id)` | the act start and every live settings edit |
| `restore_voice_policy()` | the act end and a mute-policy change |
| `stop_breath()` | the restore begin |
| `impact(...)`, `crossed(...)`, `withdraw(...)` | the impact path |
| `play_vocal()`, `tick_vocal()`, `oral_kiss()`, `play_mouth_kiss()` | the vocal and oral paths |
| `hold_excitement(owner)`, `release_excitement(owner)`, `reset_excitement_hold()` | the shared game excitement Beat |

The runtime keeps the call sites and the director/vocal prepare.

## Act lifecycle

- `begin()` randomises the variant picker, builds the `foley` group, then creates and starts the
  `act_sound` child.
- `end()` stops and clears every pack pool and frees the sound child. The facade itself survives,
  so the mute policy can still give the voice player its volume back on a later settings edit.
- `play_impact`/`play_plap`/`play_bed`/`play_slide`/`withdraw_crossed`/`crossed`/`play_mouth_kiss`
  are the pack cues the runtime drives from the impact and kiss paths.
- The impact profile follows the pose view's `audio.impact`, cached by `pose_changed(view)`:
  `missionary` keeps the bed/fabric layer; `standing`, `standing_test` and `standing_oral` play
  none. The oral edge's `audio` switch is the speech profile, not a second impact or bed profile.
  The bed face-sit keeps the `missionary` impact profile; the runtime's face contact suppresses the
  plap, the rump/tail jiggle and the withdraw cue while the slide, vocal, wings and bed layer stay.
  `begin()` clears the cache and the first fan-out of the act fills it, so the impact and withdraw
  calls no longer take the act's start `pose_id`.
- The body slap is decided from two physical facts. `play_impact` receives the impact tier
  (`firm`, `rough` or empty) and the skin gap in metres, and plays the plap only when the tier is
  set and the gap reaches true contact. A zero epsilon with a zero gap is full contact, not the
  quiet edge; the generic epsilon still lets the tests drive a wider contact window. Standing and
  missionary share the two plap bags; only the bed cues follow the impact profile. The slide is
  never gated. The defaulted `plap` argument lets the standing oral segment pass `false`: it keeps
  the slide but drops the body slap.
- `climax(snout)` plays the base-game squee at the snout. There is no pack climax layer.
- `tick(delta, phase, rate, snout)` drives the base-game breath; `stop_breath()` silences it at
  the restore begin.

## Voice policy

`mute_ponese_audio` keeps the generated line and the text HUD but silences the pony's Ponese
audio for the act. `apply_voice_policy(mute, pony, id)` receives the live routing and
mutes only when the effective voice is Ponese (`effective_ponese`). A generated/openai voice is
left alone. The saved volume is restored by `restore_voice_policy()` at the act end or when the
setting changes.

The setting is live: `act/view.gd:apply_live()` reads the pre-edit
`mute_ponese_audio` **before** it snapshots the new feature flags, and re-applies the policy only
when the two differ. The order matters — a snapshot read first would compare the new value with
itself, and a mid-act edit would never reach the voice player.

The classification itself stays `shared/voice_status.gd` (pure); the server probe is
`GAME.tts_has_server(tts)`, which reads an absent node or op as no server. The view's debug context
carries the routing line it reports.

## Base-game vocal cache

The runtime keeps the director/vocal call sites. The game's `world/ai/vocal_noises.gd` caches one
`AudioStreamPlayer3D` per pony id under `_players`, parented to her body. A body change frees the
old body and leaves a freed instance in that cache; the game's typed read at `play()` fails before
its own `is_instance_valid()` guard. `audio/service.gd:prune_freed_vocal()` clears only this runtime's
stable id before the next `play`, guarded against a changed or missing cache, so the game creates a
new player under the presented body. It never edits the game file or another pony's entry.

## Packs and settings

- The pack foley files are fetched from the resource archive and packed; see `assets/README.md`.
- `features.mute_ponese_audio` gates the Ponese mute; the outside-act smack switch is
  `docs/stock_smack.md`.
- The base-game breath and squee are always on and are not gated by a flag.
