# Act audio contract

The act's sound: the pack foley and wet layers, the base-game breath and squee climax, and the
Ponese mute policy.

## Ownership

| File | Role |
|---|---|
| `audio/service.gd` | the per-runtime audio facade: pack layers, base-game sound child, and the Ponese mute policy |
| `audio/sound.gd` | base-game breath and `squee_*` climax players and their timing |
| `audio/cues.gd` | the pure pack cue table (groups, variants, volume, cooldowns, pitch) |
| `audio/smack_cues.gd` | the hand-smack variants used by the hands system |
| `docs/audio.md` | this contract |

`audio/service.gd` is one Node per runtime. The runtime creates it lazily and keeps it for the
process: `begin(features)` opens an act's layers, `end()` closes them. It never preloads
`runtime.gd` or `main.gd`; the runtime passes the pony, the id, the feature snapshot and the
classified voice info as arguments.

## Bridge

The runtime calls one typed bridge, never a private field or a raw player:

| Method | Call site |
|---|---|
| `begin(features)` | the start sequence, after the vocal prepare |
| `end()` | the one teardown ledger |
| `climax(snout, dock)` | the climax fan-out |
| `tick(delta, phase, rate, snout)` | the breath path in the tick |
| `apply_voice_policy(pony, id, mute, info)` | the act start and every live settings edit |
| `restore_voice_policy()` | the act end and a mute-policy change |
| `stop_breath()` | the restore begin |
| `set_enabled(climax)` | `apply_live_settings()` |
| `play_impact`, `play_plap`, `play_bed`, `play_slide`, `crossed`, `withdraw_crossed`, `play_mouth_kiss` | the impact and kiss paths |

The runtime keeps the call sites, the director/vocal prepare and the feature snapshot.

## Act lifecycle

- `begin(features)` randomises the variant picker, builds the always-on `foley` group and the
  optional `climax` group from the feature flag, then creates and starts the `act_sound` child.
- `set_enabled(climax)` rebuilds the optional group when it changed; the foley group stays built.
  `apply_live_settings()` calls it while the act runs.
- `end()` stops and clears every pack pool and frees the sound child. The facade itself survives,
  so the mute policy can still give the voice player its volume back on a later settings edit.
- `play_impact`/`play_plap`/`play_bed`/`play_slide`/`withdraw_crossed`/`crossed`/`play_mouth_kiss`
  are the pack cues the runtime drives from the impact and kiss paths.
- `climax(snout, dock)` plays the base-game squee at the snout and the optional wet layer at the
  dock.
- `tick(delta, phase, rate, snout)` drives the base-game breath; `stop_breath()` silences it at
  the restore begin.

## Voice policy

`mute_ponese_audio` keeps the generated line and the text HUD but silences the pony's Ponese
audio for the act. `apply_voice_policy(pony, id, mute, info)` receives `VOICE.classify()` and
mutes only when the effective voice is Ponese (`effective_ponese`). A generated/openai voice is
left alone. The saved volume is restored by `restore_voice_policy()` at the act end or when the
setting changes.

The classification itself stays `audio/voice_status.gd` (pure); the runtime's `voice_status_line()` is
the debug read.

## Packs and settings

- The pack foley and wet files are fetched from the resource archive and packed; see
  `assets/README.md`.
- `features.act_climax` (default off) gates only the wet finish layer.
- `features.mute_ponese_audio` (default on) gates the Ponese mute.
- The base-game breath and squee are always on and are not gated by those flags.

## Dependencies

### Uses

| Kind | Target | Entry point | Purpose |
|---|---|---|---|
| shared | pose_catalog | `shared/pose_catalog.gd` | pose ids and defaults |
| shared | preferences | `shared/preferences.gd` | profile math and defaults |

## Lifecycle

- Scope: per-pony
- Constructed by: `runtime`
- Begin: `begin()`
- End: `end()`
- Idempotent: yes


## Tests

`tests/act_audio/test_audio.gd` covers the facade lifecycle, the sound child, the mute policy and
the live layer switch. `tests/act_audio/test_act_audio.gd` covers the pure catalogue and the pack
cue selection. `tests/test_runtime_teardown.gd` drives the runtime's audio forwards.
