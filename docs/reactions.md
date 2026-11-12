# Thrust and climax reactions

## Scope

`act_reactions.gd` owns the scene reactions that ride the act's thrust and climax events:

- the standing rump jiggle and its body-coat shader target;
- the act smack reaction (the native cheek jiggle carried into the tail);
- the standing rump blush decal;
- the climax heart pulses and the dock burst.

It does not own the act state, the stroke events, the act audio, the wings, the tail pose modifier,
the ear twitch or the HUD. The runtime dispatches its presentation events to this facade in the
same order as before. The anatomy features that need the patched coat call the facade through the
runtime's stock-smack callback.

## Architecture

| Part | Rule |
|---|---|
| `act_reactions.gd` | the facade: scene handles, live blush/heart state and the per-act tuning |
| `runtime.gd` | binds the scene, snapshots the settings, calls the facade from the stroke/climax paths |

The facade is a `RefCounted` scene adapter. It reads Nodes and the `body_coat_deform` setting; the
jiggle tuning is pushed in by `configure()` from the runtime's act snapshot. The standing tail
modifier is bound by the pose builder because it changes with the pose. The flank is discovered
lazily from the pony's `FlankTouch`, so a stock smack outside an act still reaches the patched
body coat.

The patched body coat is the runtime case: `FlankTouch` rebuilds its `_jiggle_targets` list on
every slap, so the body and outline materials are re-added after every `_start_jiggle()`.

## Internal API

| Method | Purpose |
|---|---|
| `bind_scene(pony, anatomy, flank = null)` | set the act's pony, anatomy controller and (optional) flank |
| `bind_tail(tail)` | set the standing tail modifier, or null outside standing |
| `configure(context)` | take `jiggle`, `pose_id`, `size_scale` and `climax_seconds` from the act snapshot |
| `begin_act()` | clear the per-act blush, jiggle log and heart pulses |
| `end_act()` | free the blush decal, drop the tail and restore the stock shader radius |
| `body_coat_target()` | re-add the patched body and outline to the jiggle targets |
| `thrust(weight)` | start the rump jiggle and scale its resolved amount |
| `tail_thrust(weight)` | add the standing tail impulse for the same thrust |
| `smack(strength)` | carry the native smack jiggle into the tail |
| `add_blush(impact)` / `blush_tick(delta)` | step, cap, decay and place the rump blush |
| `apply_radius()` / `restore_radius()` | set or clear `jiggle_radius` on the live targets |
| `clear_stock_marks()` | hide and age the stock `FlankTouch` marks at act start |
| `rump_point()` | the hind-femur midpoint plus the configured height/backset |
| `schedule_hearts()` / `hearts_tick(delta)` | the three climax pulses |
| `hearts_burst()` / `hearts_burst_at(origin)` | one boop burst, optionally moved to the dock |
| `dock_point()` | the hair `mTail1` base, with the hips and body fallbacks |

`smack()` keeps its `strength` parameter for the runtime's event shape; the native smack has
already set its own impulse before the facade scales it.

## Jiggle and smack

- One shader center on the rump midline so both flanks wobble together. The center is the
  hind-femur midpoint plus `center_height_m` and `center_back_m`; the fallback is her origin plus
  `JIGGLE_HEIGHT` and `JIGGLE_BACK` along her back axis.
- `FlankTouch._start_jiggle()` clamps its own impulse to `0.3…1.0`, so the facade passes `1.0`,
  scales the resolved `_jiggle_amount` by `weight × JIGGLE_RUMP_SCALE × size_scale × intensity`
  and re-runs `_process(0.0)` once so a soft stroke cannot flash at full amplitude.
- `jiggle.intensity` scales the thrust amount; `jiggle.smack_intensity` scales the act smack.
  `size_scale` is the runtime's `_jiggle_size_scale()` (`clampf(_size_scale(), 0.5, 1.2)`).
- The first thrust of an act logs the resolved center, targets and mark once.
- A smack first calls `body_coat_target()` because the native `_start_jiggle()` rebuilt the target
  list, then scales the resolved amount by `smack_intensity` and runs the standing tail impulse at
  `size_scale × smack_intensity`.
- `apply_radius()` writes the `jiggle_radius` shader parameter to every live target and records
  the material; `restore_radius()` clears it so stock smacks keep the shader default.
- The facade never clamps a setting-derived radius or smack intensity. See `docs/settings.md`.

## Rump blush

- Standing only. A thrust at `RUMP_BLUSH_MIN_STRENGTH` or above adds `RUMP_BLUSH_STEP`, capped at
  `RUMP_BLUSH_MAX`. It decays at `RUMP_BLUSH_DECAY` per second.
- The decal is created lazily from `FlankTouch.texture` on the first step and freed at act end.
- The decal rides the live hind-femur midpoint, so it follows the body sway.
- It is separate from the face blush in `docs/face.md` and from the stock `FlankTouch` marks,
  which the act hides and ages at start.

## Climax hearts

- `schedule_hearts()` builds three pulses: four bursts at `t=0`, two at a random time between
  `1.0 s` and `min(2.4, climax_seconds - 0.4) s`, and one at least one second after the second.
- `hearts_tick()` fires every due pulse and logs its time and count.
- `hearts_burst_at(origin)` calls the pony's boop `celebrate()` and shifts the new hearts from
  their stored origin to `origin`; the standing afterglow close and the climax start both use it.
- `dock_point()` is the hair `mTail1` base. It falls back to the body `pony_hips` plus her back
  axis and a small lift, then to her origin.

## Tests

`tests/reactions/test_reactions.gd` covers the configuration defaults and overrides, the radius
apply/restore, the body-coat target list, the smack scaling, the blush step/cap/decay and the
heart pulses and dock shift. `tests/hands/test_actions.gd` keeps the smack/tail and stock-mark
checks on the facade.
