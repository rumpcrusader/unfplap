# Thrust and climax reactions

## Scope

`reactions/service.gd` owns the scene reactions that ride the act's thrust and climax events:

- the standing rump jiggle and its body-coat shader target;
- the act smack reaction (the native cheek jiggle carried into the tail);
- the standing rump blush decal;
- the climax heart pulses and the dock burst.

It does not own the act state, the stroke events, the act audio, the wings, the tail pose modifier,
the ear twitch or the HUD. The runtime dispatches its presentation events to this facade in the
same order as before. The anatomy features that need the patched coat call the facade through the
runtime's stock-smack callback.

The runtime skips `thrust()` and `tail_thrust()` while the standing oral segment is active. The
same impact still runs the wings, the rump blush and the ear twitch; the body plap is owned by the
audio facade (`docs/audio.md`).

## Architecture

| Part | Rule |
|---|---|
| `reactions/service.gd` | the facade: scene handles, live blush/heart state and the per-act tuning |
| `reactions/context.gd` | the typed act tuning: pose family, size, climax length and the five `jiggle.*` values |
| `runtime.gd` | binds the scene, snapshots the settings, calls the facade from the stroke/climax paths |

The facade is a `RefCounted` scene adapter. It reads the base-game flank and boop members through
the `GAME` accessors and the `body_coat_deform` setting; the jiggle tuning is pushed in by
`configure()` from the runtime's act snapshot. The block is complete, so the reaction context reads
its five keys and the facade holds no fallback value. The anatomy API and the standing tail modifier are the facade's
collaborators (`anatomy/api.gd` and `SkeletonModifier3D`); the pose builder binds the tail because
it changes with the pose. The flank is discovered lazily from
the pony's `FlankTouch`, so a stock smack outside an act still reaches the patched body coat.

The patched body coat is the runtime case: `FlankTouch` rebuilds its `_jiggle_targets` list on
every slap, so the facade calls `anatomy.follow_body_coat(pony, flank)` after every
`_start_jiggle()`; anatomy re-adds its current rig and merged-near pairs. The list covers the rig body and outline and, when the merged near mesh
contains her body, its palette and outline materials.

## Jiggle and smack

- One shader center on the rump midline so both flanks wobble together. The center is the
  hind-femur midpoint plus `center_height_m` and `center_back_m`; without a skeleton it is
  `RUMP_CONE.approx_point(pony)`, the shared approximate anchor the standing cone scans.
- The flank's `wake_tick`, `_start_jiggle`, `_process` and `_jiggle_amount` are reached through the
  `GAME` accessors; the `marks` reads stay direct.
- `FlankTouch._start_jiggle()` clamps its own impulse to `0.3…1.0`, so the facade passes `1.0`,
  scales the resolved `_jiggle_amount` by `weight × JIGGLE_RUMP_SCALE × size_scale × intensity`
  and re-runs `_process(0.0)` once so a soft stroke cannot flash at full amplitude.
- `jiggle.intensity` scales the thrust amount; `jiggle.smack_intensity` scales the act smack.
  `size_scale` is the camera's `jiggle_size_scale()` (`clampf(size_scale(), 0.5, 1.2)`), which
  `act/session.gd:snapshot_settings()` passes into `configure()`.
- The first thrust of an act logs the resolved center, targets and mark once.
- A smack first calls `body_coat_target()` because the native `_start_jiggle()` rebuilt the target
  list, then scales the resolved amount by `smack_intensity` and runs the standing tail impulse at
  `size_scale × smack_intensity`.
- `apply_radius()` writes the `jiggle_radius` shader parameter to every live target and records
  the material; `restore_radius()` clears it so stock smacks keep the shader default.
- The facade never clamps a setting-derived radius or smack intensity. See `docs/settings.md`.

## Rump blush

- The `standing` family only. A thrust at `RUMP_BLUSH_MIN_STRENGTH` or above adds `RUMP_BLUSH_STEP`, capped at
  `RUMP_BLUSH_MAX`. It decays at `RUMP_BLUSH_DECAY` per second.
- The decal is created lazily from `FlankTouch.texture` on the first step and freed at act end.
- The decal rides the live hind-femur midpoint, so it follows the body sway.
- It is separate from the face blush in `docs/face.md` and from the stock `FlankTouch` marks,
  which the act hides and ages at start.

## Climax hearts

- `schedule_hearts()` builds three pulses: four bursts at `t=0`, two at a random time between
  `1.0 s` and `min(2.4, climax_seconds - 0.4) s`, and one at least one second after the second.
- `hearts_tick()` fires every due pulse and logs its time and count.
- `hearts_burst_at(origin)` calls the pony's boop `celebrate()` through `GAME.celebrate` and shifts
  the new hearts from their stored origin to `origin`; the standing afterglow close and the climax
  start both use it.
- `dock_point()` is the hair `mTail1` base. It falls back to the body `pony_hips` plus her back
  axis and a small lift, then to her origin.
