# Typed act view (`act_facts.gd`)

The shared, scene-free view of one act. The runtime owns one object per pony and rewrites it as the
state, camera and line values change; presentation modules read it instead of the runtime node.
It is not a system and it stores no save data: it is the value boundary between the runtime
orchestrator and the scene adapters.

## Ownership

- `act_facts.gd` defines the fields and the no-op host callbacks.
- `runtime.gd` creates it, binds the callbacks in `_init()` and refreshes it at the head of each
  tick in `_sync_act_facts()`.
- `standing_camera.gd` is the proof consumer. The remaining presentation modules move to it in the
  typed-view phase.
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
lean_forward, lean_side, lean_view_forward, lean_view_side, lean_sway
bob, back, back_target
forced_glance, pose_config, presentation_config
kiss_amount, kiss_active, kiss_side
bed_frame (the live missionary bed frame, or null)
```

Scene handles:

```
main, pony, camera, pose
```

A presentation module is a scene adapter, so it may receive the nodes it works on. It must not read
the runtime's private fields.

## Callbacks

A missing callback is a no-op, so a test can build the object without a runtime.

| Callback | Contract |
|---|---|
| `log` | write one debug line |
| `perf_note` | record one timed chunk for `perf.gd` |
| `body_coat_smack` | the anatomy's stock-smack hook |
| `on_touch`, `on_smack` | the readiness touch/smack hooks |
| `kiss` | return the live `kiss_control.gd` controller |
| `neck_point` | her neck midpoint for the standing aim |
| `set_look` | write back the captured player look |
| `set_forced_glance` | set the forced over-shoulder glance |
| `set_camera_basis_ready` | mark the camera basis ready |
| `director` | the live conversation director |
| `now` | the act's processed-time clock |

Helper methods: `perf()`, `write_log()`, `smack_body_coat()`, `kiss_controller()`,
`neck_midpoint()`, `write_look()`, `write_forced_glance()`, `mark_camera_basis_ready()`, `clock()`.

## Rules

- No `Node`, `Time`, `SceneTree`, `FileAccess` or game scene preload. It is pure data and callables.
- Reuse the object; never allocate a facts object per frame.
- The runtime writes the fields; presentation modules only read them and call the callbacks.
- A field that only one module needs is still allowed here if it keeps that module off the runtime.
- The object is not saved and has no version.
- When a field moves out of the runtime, every consumer and test moves in the same commit.

## Tests

- `tests/act_facts/test_act_facts.gd` — defaults, callback no-ops, helpers and the clock.

## Related docs

- `AGENTS.md` — the isolated-systems architecture.
- `docs/camera.md` — the camera values the view carries.
- `docs/hands.md` — the hand/kiss readers.
- `docs/perf.md` — the perf callback.
