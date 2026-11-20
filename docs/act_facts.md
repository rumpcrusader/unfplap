# Typed act view (`shared/act_facts.gd`)

The shared, scene-free view of one act. The runtime's `act/view.gd` owns one object per pony and
rewrites it as the state, camera and line values change; presentation modules read it instead of
the runtime node. It is not a system and it stores no save data: it is the value boundary between
the runtime orchestrator and the scene adapters.

## Ownership

- `shared/act_facts.gd` defines the fields and the no-op host callbacks.
- `act/build.gd` creates it once per pony and binds each callback to its owner — a service method,
  a session accessor or an `act/host.gd` node op — so no callback names a runtime node method.
  `act/view.gd` refreshes the live values through `act/session.gd:refresh_view()`, the one call
  site. It runs once per phase: idle
  before the idle systems, physics after the pose tick and before the fan-out, render before the
  camera work, and the entry's `apply_camera_motion()` hand-off. The start, resume, teardown and
  live-edit paths call `refresh_view()` directly. The idle standing invitation, the debug actions
  and the suites therefore read the view the phase boundary just wrote, not a per-getter rebind.
- The consumers are `poses/missionary_anon.gd`, `camera/view.gd`, `poses/standing_anon.gd`,
  `poses/standing_presentation.gd`, `camera/service.gd`, `act/frame.gd`, `kiss/service.gd`,
  `hands/service.gd`, the
  hands internals (`hands/placement.gd`, `hands/surface.gd`, `hands/path_base.gd` and its paths)
  and the pose modifiers (`poses/skeleton_pose.gd`, plus
  `poses/tail_pose.gd`, `poses/tail_lay.gd`, `poses/body_sway.gd`, `poses/prone_sway.gd`, `poses/ear_twitch.gd`).
- `anatomy/facts.gd` is the same pattern for the anatomy system.

## Fields

Session and scoring:

```
state, source
satisfaction, mood, seconds_since_stroke, cue, pony_climaxes
depth, penetration_m, penetration_reach
```

Line and prompt:

```
event_id, pony_id, display_name, act_seconds
last_intensity, last_pattern, last_touch, last_talk
thrust_pace, cue_override
preferences, act_prompts, features
caress_quality (the act's precise or fast caress surface level)
```

Size and camera:

```
size_name, size_scale, lean_size_scale, standing_lean_scale
player_eye_height, anon_torso_forward, anon_torso_drop
player_pony, headset_view
free_camera_active, free_look_active
camera_owned, look_captured, look_yaw, look_pitch
head_clearance (the bed view's pad over her skull and muzzle radii, in metres)
lean_forward, lean_side, lean_action_side, lean_view_forward, lean_view_side, lean_sway
lean, shot_lean_forward
bob, back, back_target
forced_glance, pose_view, presentation_config
kiss_amount, kiss_active, kiss_side
thrust_travel, same_height_scale, anon_height_scale, palm_scale_factor
standing_sway_offset
bed_frame (the live missionary bed frame, or null), bed, profile
physics_delta (the physics tick delta the hand and reach easing uses)
```

`standing_sway_offset` is the world-space pelvis offset the standing body sway publishes; the
standing Anon controller adds it to his pinned hip. It is zero outside the standing family and
while the oral segment holds the body still.

`pose_view` is the pose read model (`shared/pose_view.gd`): the pose identity, the spec profiles,
the live config and the live contact and facing values. It is the read path for every
presentation module. During an authored transition, `pose_state` is `TRANSITIONING` and
`from_id`/`to_id`, `edge_id`, `edge_t`, `weight`, `from_config` and `to_config` carry the two
sides; the view's identity and profiles are the target. On completion the session adopts the
target into the live `pose_config`, and both sides point at that same object again; the live
object is the one `view.pose_config`, the pose node and the live view alias. The view re-reads it
only when the view's settings group or pose id changes. The view stays filled
for the whole act: the pose-scope leave steps (`leave_pose_start()`, `leave_pose_body()`) keep it,
and only `release_pose()` clears it. The runtime's `pose_id` is only the act's start identity for
logs and the start/teardown path; `view.id` is the active pose. The pose-owned oral turn writes the
live `facing` and `facing_amount` into the view each tick without copying a dictionary, and the
view's `contact_kind` is the one contact source.

HUD card (the runtime fills these once per rendered frame; `hud/service.gd` reads them instead of
calling back into the runtime):

```
max_pony_climaxes, close_hint, summary_hud, cycle_heat, close_earned
hud_readouts, hud_controls, form_hint (kept empty by the runtime)
auto_on, auto_layer_open, auto_min_depth, auto_max_depth, auto_pace, auto_shape
hole_ready, oral_ready
```

`close_earned` and `auto_shape` are raw values: the HUD module formats the `End` tint and the auto
readout, not the runtime.

Scene handles:

```
pony, camera, pose, viewport
```

A presentation module is a scene adapter, so it may receive the nodes it works on. It must not read
the runtime's private fields.

## Callbacks

A missing callback is a no-op, so a test can build the object without a runtime.

| Callback | Contract |
|---|---|
| `body_coat_smack` | the anatomy's stock-smack hook |
| `on_touch` | one readiness touch event, by kind |
| `on_smack` | one smack impact, by strength |
| `kiss` | return the live `kiss/service.gd` controller |
| `neck_point` | her neck midpoint for the standing aim |
| `set_look` | write back the captured player look |
| `set_forced_glance` | set the forced over-shoulder glance |
| `set_camera_basis_ready` | mark the camera basis ready |
| `set_head_back` | write the standing glance's head throw-back on the live pose node |
| `director` | the live conversation director |
| `now` | the act's processed-time clock |
| `play_mouth_kiss` | the mouth kiss sound |
| `act_actions_allowed` | the camera's action window |
| `auto_panel_open` | the hold-X layer |
| `view`, `missionary_anon` | the live act view and the posed Anon body |
| `anatomy_normal`, `anatomy_opening` | the anatomy reads |
| `missionary_face_point` | her face point for the eye view's kiss lean |
| `authored_pose_asset` | the live authored asset, read only for the missionary look path |
| `gaze_point` | the missionary gaze target the camera's look write uses |
| `free_look_rotation` | the debug view rotation |
| `desktop_pose_driver` | the game's pose driver |
| `pose_host` | the node that answers the Anon pose-driver write-backs |
| `cuddle_active`, `free_of_affection` | the start gates |
| `pause_face_turn`, `restore_face_turn` | the scene hold |
| `hold_excitement`, `release_excitement` | the act-level excitement Beat hold |
| `mod_enabled` | whether another mod's entry is active this launch, by mod id |

Helper methods: `smack_body_coat()`, `touch()`, `smack_hit()`,
`kiss_controller()`, `neck_midpoint()`, `write_look()`, `write_forced_glance()`,
`mark_camera_basis_ready()`, `clock()`, `call_value()`, `missionary_body()`, `feature()`,
`view_controller()`, `pose_driver()`, `driver_host()`,
`pause_face()`, `restore_face()`, `hold_beat()`, `release_beat()`, `mod_active()`.

## Rules

- No `Node`, `Time`, `SceneTree`, `FileAccess` or game scene preload. It is pure data and callables.
- Reuse the object; never allocate a facts object per frame.
- `act/view.gd` writes the fields (through the runtime's one call); presentation modules only read
  them and call the callbacks.
- A field that only one module needs is still allowed here if it keeps that module off the runtime.
- The object is not saved and has no version.
- When a field moves out of the runtime, every consumer and test moves in the same commit.

## Tests

- `tests/act_facts/test_act_facts.gd` — defaults, callback no-ops, helpers and the clock; the
  anatomy context's host callback boundary.

The import boundary is `scripts/architecture.py --check`; the "no scene reference and no runtime
reach-in" part of the rule is review, not a text scan.

## Related docs

- `AGENTS.md` — the isolated-systems architecture.
- `docs/camera.md` — the camera values the view carries.
- `docs/hands.md` — the hand/kiss readers.
- `docs/poses.md` — the body wrappers that read the view.
