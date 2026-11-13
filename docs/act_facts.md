# Typed act view (`shared/act_facts.gd`)

The shared, scene-free view of one act. The runtime owns one object per pony and rewrites it as the
state, camera and line values change; presentation modules read it instead of the runtime node.
It is not a system and it stores no save data: it is the value boundary between the runtime
orchestrator and the scene adapters.

## Ownership

- `shared/act_facts.gd` defines the fields and the no-op host callbacks.
- `runtime.gd` creates it, binds the callbacks in `_init()`, refreshes the live values in
  `_sync_act_facts()` at the head of each act tick, and refreshes them again in `_bind_act_view()`
  before it hands a presentation controller out. The second refresh exists because the idle
  standing invitation, the debug actions and the suites call the controllers outside the act tick.
- The consumers are `poses/missionary_anon.gd`, `camera/missionary_camera.gd`, `poses/standing_anon.gd`,
  `camera/standing_camera.gd`, `poses/standing_presentation.gd`, `kiss/service.gd`, `hands/service.gd`, the
  hands internals (`hands/placement.gd`, `hands/surface.gd`, `hands/path_base.gd` and its paths)
  and the pose modifiers (`poses/skeleton_pose.gd` through its `perf`/`log` handles, plus
  `poses/tail_pose.gd`, `poses/tail_lay.gd`, `poses/body_sway.gd`, `poses/prone_sway.gd`, `poses/ear_twitch.gd`).
- `anatomy/facts.gd` is the same pattern for the anatomy system.

## Fields

Session and scoring:

```
state, pose_id, source
satisfaction, mood, cue, pony_climaxes
depth, penetration_m, penetration_reach
```

Line and prompt:

```
event_id, pony_id, display_name, act_seconds
last_intensity, last_pattern, last_touch, last_talk
thrust_pace, oral_active, anal_active, cue_override
preferences, act_prompts, features
```

Size and camera:

```
size_name, size_scale, lean_size_scale, standing_lean_scale
player_eye_height, anon_torso_forward, anon_torso_drop
player_pony, headset_view
free_camera_active, free_look_active
camera_owned, look_captured, look_yaw, look_pitch
lean_forward, lean_side, lean_action_side, lean_view_forward, lean_view_side, lean_sway
lean, shot_lean_forward
bob, back, back_target
forced_glance, pose_config, presentation_config
kiss_amount, kiss_active, kiss_side
thrust_travel, same_height_scale, anon_height_scale, palm_scale_factor
standing_sway_offset
bed_frame (the live missionary bed frame, or null), bed, profile
physics_delta (the physics tick delta the hand and reach easing uses)
```

Scene handles:

```
main, pony, camera, pose, viewport
```

A presentation module is a scene adapter, so it may receive the nodes it works on. It must not read
the runtime's private fields.

## Callbacks

A missing callback is a no-op, so a test can build the object without a runtime.

| Callback | Contract |
|---|---|
| `log` | write one debug line |
| `perf_note` | record one timed chunk for `shared/perf.gd` |
| `body_coat_smack` | the anatomy's stock-smack hook |
| `on_touch` | one readiness touch event, by kind |
| `on_smack` | one smack impact, by strength |
| `kiss` | return the live `kiss/service.gd` controller |
| `neck_point` | her neck midpoint for the standing aim |
| `set_look` | write back the captured player look |
| `set_forced_glance` | set the forced over-shoulder glance |
| `set_camera_basis_ready` | mark the camera basis ready |
| `director` | the live conversation director |
| `now` | the act's processed-time clock |
| `keep_chin_last` | the chin overlay's last write |
| `play_mouth_kiss` | the mouth kiss sound |
| `act_actions_allowed` | the camera's action window |
| `auto_panel_open` | the hold-X layer |
| `standing_camera`, `missionary_anon` | the pose bodies |
| `anatomy_normal`, `anatomy_opening` | the anatomy reads |
| `authored_pose_asset`, `missionary_face_point` | the shot targets |
| `free_look_rotation` | the debug view rotation |
| `desktop_pose_driver` | the game's pose driver |
| `pose_host` | the node that answers the Anon pose-driver write-backs |
| `cuddle_active`, `free_of_affection`, `can_offer` | the start gates |
| `pause_face_turn`, `restore_face_turn` | the scene hold |

Helper methods: `perf()`, `write_log()`, `smack_body_coat()`, `touch()`, `smack_hit()`,
`kiss_controller()`, `neck_midpoint()`, `write_look()`, `write_forced_glance()`,
`mark_camera_basis_ready()`, `clock()`, `call_value()`, `missionary_body()`, `feature()`,
`standing_camera_controller()`, `pose_driver()`, `driver_host()`, `offer_allowed()`,
`pause_face()`, `restore_face()`.

## Rules

- No `Node`, `Time`, `SceneTree`, `FileAccess` or game scene preload. It is pure data and callables.
- Reuse the object; never allocate a facts object per frame.
- The runtime writes the fields; presentation modules only read them and call the callbacks.
- A field that only one module needs is still allowed here if it keeps that module off the runtime.
- The object is not saved and has no version.
- When a field moves out of the runtime, every consumer and test moves in the same commit.

## Tests

- `tests/act_facts/test_act_facts.gd` — defaults, callback no-ops, helpers and the clock.
- `tests/test_source_hygiene.gd` — the context has no scene reference and no presentation module
  reaches into the runtime.

## Related docs

- `AGENTS.md` — the isolated-systems architecture.
- `docs/camera.md` — the camera values the view carries.
- `docs/hands.md` — the hand/kiss readers.
- `docs/poses.md` — the body wrappers that read the view.
- `docs/perf.md` — the perf callback.
