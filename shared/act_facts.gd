extends RefCounted
## The typed act context. The runtime owns one per act and rewrites it as the state and the camera
## change; presentation modules read this object instead of the runtime node. Callbacks are the
## host boundary for services, so tests can build a context without a runtime.

# Session values.
var state := 0
var source := ""
var satisfaction := 0.0
var mood := ""
## Seconds since the last real inward stroke; the integration activity gate reads it.
var seconds_since_stroke := 0.0
var cue := ""
var pony_climaxes := 0
var depth := 0.0
var penetration_m := 0.0
var penetration_reach := 0.2

# Line and prompt values.
var event_id := ""
var pony_id := ""
var display_name := ""
var act_seconds := 0.0
var last_intensity := ""
var last_pattern := ""
var last_touch := ""
var last_talk := ""
var thrust_pace := 0.0
var cue_override := false
var preferences: Dictionary = {}
var features: Dictionary = {}

# Size and camera values.
var size_name := ""
var size_scale := 1.0
var lean_size_scale := 1.0
var standing_lean_scale := 1.0
var player_eye_height := 0.0
var anon_torso_forward := 0.0
var anon_torso_drop := 0.0
var player_pony := false
var headset_view := false
var free_camera_active := false
var free_look_active := false
var camera_owned := false
var look_captured := false
var look_yaw := 0.0
var look_pitch := 0.0
var lean_forward := 0.0
var lean_side := 0.0
var lean_action_side := 0.0
var lean_view_forward := 0.0
var lean_view_side := 0.0
var lean_sway := 0.0
## The shot's forward lean plus the idle-breathing offset, and the camera's own lean.
var shot_lean_forward := 0.0
var lean := 0.0
var bob := 0.0
var back := 0.0
var back_target := 0.0
var forced_glance := ""
## The pose read model `poses/api.gd` fills and clears. Its `id`, profiles, live config and
## contact are the one pose source for the presentation modules.
var pose_view: Variant = null
var presentation_config: Dictionary = {}
var kiss_amount := 0.0
var kiss_active := false
var kiss_side := 0.0
## The pad the bed view keeps his head out of her skull and muzzle, in world metres.
var head_clearance := 0.0
var thrust_travel := 0.5
var same_height_scale := 1.0
var anon_height_scale := 1.0
var palm_scale_factor := 1.0
var standing_sway_offset := Vector3.ZERO
## The act's bed node and the per-mare profile the presentation reads.
var bed: Variant = null
var profile: Dictionary = {}
## The physics delta the hand and reach easing uses, so a controller never asks the tree.
var physics_delta := 0.016

# HUD card values: filled once per rendered frame for the HUD module.
var max_pony_climaxes := 0
var close_hint := ""
var summary_hud := ""
var cycle_heat := false
## The earned standing afterglow caress, which makes the `End` tint fully pink.
var close_earned := false
var auto_on := false
var auto_layer_open := false
var auto_min_depth := 0.0
var auto_max_depth := 0.0
var auto_pace := 0.0
var auto_shape := ""
var hole_ready := false
var oral_ready := false
var hud_readouts := true
var hud_controls := true
## The act's one form-change hint, or "". It names the dialogue channel and no new control.
var form_hint := ""

# Scene handles the act owns. Presentation modules are scene adapters, so they receive the nodes
# they work on rather than reading the runtime's fields.
var pony: Variant = null
var camera: Camera3D = null
var viewport: Variant = null
## The act's Anon part handle, or null outside an act.
var anon: Variant = null

# The act's live anatomy opening, written by the anatomy stage.
var anatomy_opening := Vector3.ZERO

# Host callbacks. A missing callback is a no-op.
var on_touch := Callable()
var on_smack := Callable()
## Services and write-backs that stay runtime-owned.
var kiss := Callable()
var neck_point := Callable()
var set_look := Callable()
var set_forced_glance := Callable()
var set_camera_basis_ready := Callable()
var set_head_back := Callable()
## The live conversation director, or absent outside a scene.
var director := Callable()
## The act's processed-time clock, so line pacing freezes with the tree.
var now := Callable()
## The presentation and input dispatch the runtime still owns.
var play_mouth_kiss := Callable()
var act_actions_allowed := Callable()
var auto_panel_open := Callable()
var view := Callable()
var missionary_anon := Callable()
var missionary_face_point := Callable()
## The missionary gaze target (the authored Anon's face), owned by the anatomy bridge.
var gaze_point := Callable()
var free_look_rotation := Callable()
var desktop_pose_driver := Callable()
var cuddle_active := Callable()
var free_of_affection := Callable()
var pause_face_turn := Callable()
var restore_face_turn := Callable()
## Shared act-level ownership of the game's excitement Beat. A service acquires a named hold; the
## runtime restores the Beat's original pause state when the last holder releases.
var hold_excitement := Callable()
var release_excitement := Callable()
## Whether a named external mod is loaded this launch.
var mod_enabled := Callable()
## The opaque host handle for the Anon pose-driver write-backs.
var pose_host := Callable()


func kiss_controller() -> Variant:
	return kiss.call() if kiss.is_valid() else null


func neck_midpoint() -> Vector3:
	if neck_point.is_valid():
		var point: Variant = neck_point.call()
		if point is Vector3:
			return point
	return Vector3.INF


## Write the player look back through the runtime, which owns the captured snapshot.
func write_look(yaw: float, pitch: float) -> void:
	if set_look.is_valid():
		set_look.call(yaw, pitch)


func write_forced_glance(side: String) -> void:
	if set_forced_glance.is_valid():
		set_forced_glance.call(side)


func mark_camera_basis_ready() -> void:
	if set_camera_basis_ready.is_valid():
		set_camera_basis_ready.call()


func clock() -> float:
	return float(now.call()) if now.is_valid() else 0.0


## One readiness touch event of `kind` (`caress`, `kiss`, `smack`).
func touch(kind: String) -> void:
	if on_touch.is_valid():
		on_touch.call(kind)


## One smack impact of `strength`, for the jiggle and rump blush fan-out.
func smack_hit(strength: float) -> void:
	if on_smack.is_valid():
		on_smack.call(strength)


## The one live act view, or null outside an act.
func view_controller() -> Variant:
	return view.call() if view.is_valid() else null


## The game's desktop pose driver, or null when the avatar has none.
func pose_driver() -> Variant:
	return desktop_pose_driver.call() if desktop_pose_driver.is_valid() else null


## The host handle for pose-driver write-backs, or null.
func driver_host() -> Variant:
	return pose_host.call() if pose_host.is_valid() else null


## Hold the face turn for the act. A missing callback is a no-op.
func pause_face(force := false) -> void:
	if pause_face_turn.is_valid():
		pause_face_turn.call(force)


func restore_face() -> void:
	if restore_face_turn.is_valid():
		restore_face_turn.call()


## Acquire the act-level excitement Beat hold for `owner`.
func hold_beat(owner: String) -> void:
	if hold_excitement.is_valid():
		hold_excitement.call(owner)


## Release `owner`'s excitement Beat hold; the runtime restores the Beat after the last release.
func release_beat(owner: String) -> void:
	if release_excitement.is_valid():
		release_excitement.call(owner)


## Whether the external mod `id` is active this launch. A missing callback reads as inactive.
func mod_active(id: String) -> bool:
	if mod_enabled.is_valid():
		return bool(mod_enabled.call(id))
	return false


## A host value that may be missing: `null` outside a scene, so a caller tests it.
func call_value(callback: Callable, fallback: Variant = null) -> Variant:
	return callback.call() if callback.is_valid() else fallback


func missionary_body() -> Variant:
	return missionary_anon.call() if missionary_anon.is_valid() else null


func feature(name: String, fallback := true) -> bool:
	return bool(features.get(name, fallback))
