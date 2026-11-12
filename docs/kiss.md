# Kiss

This is the contract for the act kiss: the missionary custom head-aim path, the standing base-game
kiss, the shared mouth and lean values, the foreleg pin, the face release and the cooldown. The
camera shot is `docs/camera.md`; the face beats are `docs/face.md`; the hands are
`docs/hands.md`.

## Ownership

`kiss_control.gd` is the act kiss controller. It owns the kiss state, the lean-in, the side latch,
the mouth target, the base-kiss bridge, the foreleg pin and the sound cadence. The runtime owns
the state machine, the action latch (`F` held at a full lean), the camera and the teardown.
`kiss_legs.gd` is the standing foreleg pin. `affection_pose.gd` is the game's kiss pose.

## Controls

| Pose | Control | Start |
|---|---|---|
| Standing | hold `F` at `abs(lean_side) >= STANDING_KISS_LEAN = 0.90` | the game's own kiss path |
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
- The excitement Beat timer is paused so the stock unicorn horn sparkle does not fire.
- The game's `AffectionPose.kiss_settings()` `rear` and `hooves` values are saved and both set to
  zero before the base kiss; `kiss_legs.gd` captures both foreleg tips before the kiss and runs last
  to CCD them back to those positions, because the base kiss's chest flex would otherwise drag the
  legs after `body_sway`'s upper-arm pin.
- The side is latched at the start from the input lean (`_lean_side`, falling back to
  `_lean_action_side`), not the lagging camera view. `_pin_base_kiss_side()` pins her head tilt to
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
- The kiss does not move the authored missionary shot; the `front` shot is the kiss framing.
  `KISS_CLEARANCE_M` (0.45 m × body scale) only keeps the Anon-eyes view out of her face.
- The mouth kiss sound repeats at `KISS_SOUND_MIN = 2.0`–`KISS_SOUND_MAX = 3.4 s`.
- The `features.act_faces` flag gates the face beats; the kiss's own lid layer is not overridden by
  the act stare.

## Settings

`presentation.standing.kiss` holds the live standing values: `mouth_right`, `mouth_drop`,
`mouth_forward`, `camera_yaw_deg`, `lean_side`, `lean_forward` and `lean_drop`. The missionary
constants are in `kiss_control.gd`. Heights scale with `Settings.anon_height_scale()`, matching
`player/player_mouth.gd`. See `docs/settings.md` for the settings framework.

## Tests

- `tests/act_camera/test_camera.gd` — the kiss lean, camera yaw and the release hold.
- `tests/face/test_runtime_face.gd` — the stare release while a kiss runs.
- `tests/hands/test_actions.gd` — the `F` latch and the lean values the kiss shares with the hands.
- `tests/poses/test_session.gd` — the `AffectionPose` order and the foreleg pin.

## Verification / lab

- Standing: hold `F` at a full side lean, confirm the base-game face, mouth and deep-kiss audio,
  the foreleg pin, the camera yaw, release and the 500 ms cooldown.
- Missionary: hold `F` + `W` at a full forward lean, confirm the head aim blends from eyes to
  mouth, the mouth expression and sound, and that the authored shot does not move.

## Related docs

- `docs/camera.md` — the shot, lean and Anon-eyes view.
- `docs/face.md` — the act face owner and the stare release.
- `docs/hands.md` — caress, reach and smack.
- `docs/poses.md` — the body pose and the standing stance.
