# Kiss

This is the contract for the act kiss: the missionary custom head-aim path, the standing base-game
kiss, the shared mouth and lean values, the foreleg pin, the face release and the cooldown. The
live view is `docs/camera.md`; the face beats are `docs/face.md`; the hands are
`docs/hands.md`.

## Ownership

`kiss/service.gd` is the act kiss controller. It owns the kiss state, the lean-in, the side latch,
the mouth target, the base-kiss bridge, the foreleg pin and the sound cadence. The runtime owns
the state machine, the action latch (`F` held at a full lean), the camera and the teardown.
`kiss/legs.gd` is the standing foreleg pin. `affection_pose.gd` is the game's kiss pose. The
controller reads `shared/act_facts.gd` (`pose_view` for the family and the presentation kiss
profile, `state`, `lean_*`, `anon_height_scale`, `standing_lean_scale`, `camera`, the scene handles
and the `kiss_controller()`, `touch()` and `write_forced_glance()` callbacks), never the runtime
node; see `docs/act_facts.md`. The pose view is held typed, the act body is the poses facade's
`MISSIONARY_ANON`, and every base-game member it reads or writes goes through `world/game.gd`.

The kiss's `pose_changed(view)` hook follows the view's family, presentation kiss profile and live
`from_config`/`pose_config` without ending a running kiss or releasing its foreleg pin; it never
reads a facts config alias. A shared keep is a cheap no-op; `_sync()` reads the same view
config per tick. The hook is pinned by `tests/act_camera/test_kiss.gd`; the face and mouth suites
stay unchanged.

## Controls

| Pose | Control | Start |
|---|---|---|
| Standing | hold `F` at `abs(lean_side) >= STANDING_KISS_LEAN = 0.90` | the game's own kiss path |
| Standing oral | the mouth contact owns the head | no kiss starts; the oral lean tick ends a running lean kiss |
| Bed face-sit | no kiss in its control set | the debug action refuses while a kiss is running; the pose never starts one |
| Missionary | hold `F` at `lean_forward >= MISSIONARY_KISS_LEAN = 0.90` **and** `W` held | the custom head-aim path |
| Both | release `F` or drop the lean | ends the kiss |
| Both | `H` | consumed; a stock hug/deep kiss cannot end the act's kiss |

The standing check uses the lean side; the missionary check uses the forward lean. `lean_targets`
adds `|side|` to the forward lean, so without the explicit `W` test a pure side lean would pull the
missionary kiss. `Q`/`E` are not kiss inputs; `lean_action_kind()` only fires the standing shoulder
reach.

## Standing base kiss

- Reuses the game's own path: temporarily clear `controls_locked` for
  `pony_kisser.begin_from_pony()`, move `AffectionPose` last in the skeleton so its IK layers on
  the act pose, and call `Affection.end()` on release. This gives the normal face, mouth, deep-kiss
  and soft-kiss audio.
- `pony_kisser` physics is paused for the whole act. The runtime feeds a base kiss the live
  `target`/`eye`/`face` from Anon's real mouth camera and repeats the mouth kiss sound itself.
- The shared act-level excitement Beat hold keeps the Beat paused so the stock unicorn horn
  sparkle does not fire. The kiss service holds the `kiss` token; the mod-integration service holds
  its own token, and the runtime restores the original state after the last release.
- The game's `AffectionPose.kiss_settings()` `rear` and `hooves` values are saved and both set to
  zero before the base kiss; `kiss/legs.gd` captures both foreleg tips before the kiss and runs last
  to CCD them back to those positions, because the base kiss's chest flex would otherwise drag the
  legs after `body_sway`'s upper-arm pin.
- The side is latched at the start from the input lean (`lean_side`, falling back to
  `lean_action_side`), not the lagging camera view. `_pin_base_kiss_side()` pins her head tilt to
  the complementary side (`KISS_PONY_SIDE_SIGN = 1`) so their heads interlock instead of colliding;
  the deep-kiss side switch is disabled for the act.
- Lateral offset crossfades from the lean's `0.18 m` to the kiss's `0.18 m` instead of adding both.
- Anon leans in by `presentation.standing.kiss.lean_forward`, shifts to the shoulder side by
  `lean_side` and drops by `lean_drop` over `KISS_LEAN_SECONDS = 0.35 s`; the camera yaws by
  `camera_yaw_deg` toward her. The values apply live.
- While the kiss and its `Affection` release run, the forced over-the-shoulder glance is cleared and
  `head_back` eases to zero, so the kiss head pose is not fought by the reach glance. The camera
  lean is held until the release has retracted (`Affection.amount > 0.2`) before easing out.

## Missionary custom kiss

The stock kiss pose is authored for a standing pony; its chest/neck give lifts the lying body and
turns her head across the mattress. Missionary always uses the custom head-aim path:

- The look point blends from his eyes to his mouth by the kiss's own `KISS_FADE_IN = 0.35 s` fade
  (`kiss.amount()`), so her head leans in instead of snapping to the mouth on the first frame.
- The solve follows the moving point each frame; the base-game contact target is his authored mouth
  (`mouth_point()`), never the game camera on his standing player rig.
- The path still sets the mouth expressions and repeats the mouth kiss sound.
- `KISS_LEAN_M = 0.27`, side `0.18`, drop `0.035` and camera yaw `10°` are the missionary lean
  values.
- Her gaze and the kiss target his authored eye and mouth; the anatomy trims and `gaze_offset_mm`
  are in `docs/camera.md` and `docs/anatomy.md`.

## Shared behaviour

- The kiss side is latched at the start; a completed kiss has
  `KISS_RESTART_COOLDOWN_MS = 500` before another can start. The side latch and the pose lock clear
  when the kiss lean reaches zero.
- Either path may stop the pony's current speech, but it does not interrupt thrusting or stats.
  `_check_running()` treats the act's own `Affection`-driven `kiss` as part of the act, not as an
  interruption.
- A kiss is not a lean action any more: `lean_action_kind()` only fires the standing shoulder reach.
- The kiss does not move the view's base: the eye leans in toward her face by `KISS_CLEARANCE_M`,
  and the head aim blends from her eyes to her mouth.
  `KISS_CLEARANCE_M` (0.45 m × body scale) only keeps the Anon-eyes view out of her face.
- The mouth kiss sound repeats at `KISS_SOUND_MIN = 2.0`–`KISS_SOUND_MAX = 3.4 s`.
- The kiss's own lid layer is not overridden by the act stare.

## Settings

The live standing values are the `presentation.standing.kiss.*` declarations, each described by its
`##` comment. The missionary/bed lean constants (`KISS_LEAN_M`, `KISS_LEAN_SIDE_M`, `KISS_LEAN_DROP_M`, `KISS_CAMERA_YAW_DEG`) stay
in `kiss/service.gd`: `_kiss_controls()` is empty for the bed family, so the same values serve the
missionary path and are not copies of `presentation.standing.kiss`. `KISS_LEAN_SIDE_M` is also the
pure side-geometry constant the hands suite pins. Heights scale with `Settings.anon_height_scale()`,
matching `player/player_mouth.gd`. See `docs/settings.md` for the settings framework.

## Verification / lab

- Standing: hold `F` at a full side lean, confirm the base-game face, mouth and deep-kiss audio,
  the foreleg pin, the camera yaw, release and the 500 ms cooldown.
- Missionary: hold `F` + `W` at a full forward lean, confirm the head aim blends from eyes to
  mouth, the mouth expression and sound, and that the kiss lean-in stops at her face clearance.
