extends RefCounted
## The typed act context. The runtime owns one per act and rewrites it as the state and the camera
## change; presentation modules (cameras, hands, kiss, Anon bodies) read this object instead of the
## runtime node. Callbacks are the host boundary for services and the few values only the runtime
## can write back, so tests can build a context without a runtime.
##
## See `AGENTS.md` (`## Architecture: isolated systems`).

# Session values.
var state := 0
var pose_id := ""
var source := ""
var satisfaction := 0.0
var mood := ""
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
var oral_active := false
var anal_active := false
var cue_override := false
var preferences: Dictionary = {}
var act_prompts: Dictionary = {}
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
var pose_config: Dictionary = {}
var presentation_config: Dictionary = {}
var kiss_amount := 0.0
var kiss_active := false
var kiss_side := 0.0
var thrust_travel := 0.5
var same_height_scale := 1.0
var anon_height_scale := 1.0
var palm_scale_factor := 1.0
var standing_sway_offset := Vector3.ZERO
## The act's bed frame, or null outside a missionary act.
var bed_frame: Variant = null
## The act's bed node and the per-mare profile the presentation reads.
var bed: Variant = null
var profile: Dictionary = {}
## The physics delta the hand and reach easing uses, so a controller never asks the tree.
var physics_delta := 0.016

# HUD card values. `hud/service.gd` reads these instead of calling back into the runtime.
var max_pony_climaxes := 0
var close_hint := ""
var summary_hud := ""
var cycle_heat := false
var y_pink := 0.0
var auto_on := false
var auto_layer_open := false
var auto_min_depth := 0.0
var auto_max_depth := 0.0
var auto_pace := 0.0
var auto_shape := ""
var finish_pull_out := false
var hole_ready := false
var oral_ready := false
var finish_ready := false
var hud_readouts := true
var hud_controls := true

# Scene handles the act owns. Presentation modules are scene adapters, so they receive the nodes
# they work on rather than reading the runtime's fields.
var main: Variant = null
var pony: Variant = null
var camera: Camera3D = null
var pose: Variant = null
var viewport: Variant = null

# Host callbacks. A missing callback is a no-op.
var log := Callable()
var perf_note := Callable()
var body_coat_smack := Callable()
var on_touch := Callable()
var on_smack := Callable()
## Services and write-backs that stay runtime-owned.
var kiss := Callable()
var neck_point := Callable()
var set_look := Callable()
var set_forced_glance := Callable()
var set_camera_basis_ready := Callable()
## The live conversation director, or absent outside a scene.
var director := Callable()
## The act's processed-time clock, so line pacing freezes with the tree.
var now := Callable()
## The presentation and input dispatch the runtime still owns.
var keep_chin_last := Callable()
var play_mouth_kiss := Callable()
var act_actions_allowed := Callable()
var auto_panel_open := Callable()
var standing_camera := Callable()
var missionary_anon := Callable()
var anatomy_normal := Callable()
var anatomy_opening := Callable()
var authored_pose_asset := Callable()
var missionary_face_point := Callable()
## The missionary gaze target (the authored Anon's face), owned by the anatomy bridge.
var gaze_point := Callable()
var free_look_rotation := Callable()
var desktop_pose_driver := Callable()
var cuddle_active := Callable()
var free_of_affection := Callable()
var can_offer := Callable()
var pause_face_turn := Callable()
var restore_face_turn := Callable()
## The node that answers the Anon pose-driver write-backs (`apply_anon_thrust`,
## `apply_anon_lean`, `apply_anon_align`). It is passed as an opaque host handle.
var pose_host := Callable()


func perf(chunk: String, usec: int) -> void:
	if perf_note.is_valid():
		perf_note.call(chunk, usec)


func write_log(text: String) -> void:
	if log.is_valid():
		log.call(text)


func smack_body_coat() -> void:
	if body_coat_smack.is_valid():
		body_coat_smack.call()


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


## The standing camera controller, or null outside a standing act.
func standing_camera_controller() -> Variant:
	return standing_camera.call() if standing_camera.is_valid() else null


## The game's desktop pose driver, or null when the avatar has none.
func pose_driver() -> Variant:
	return desktop_pose_driver.call() if desktop_pose_driver.is_valid() else null


## The node that answers the Anon pose-driver write-backs.
func driver_host() -> Variant:
	return pose_host.call() if pose_host.is_valid() else null


## Whether an act may be offered now. A missing callback refuses.
func offer_allowed(pose: String, act_source: String, bed_in: Variant = null) -> bool:
	if not can_offer.is_valid():
		return false
	return bool(can_offer.call(pose, act_source, bed_in))


## Hold the face turn for the act. A missing callback is a no-op.
func pause_face(force := false) -> void:
	if pause_face_turn.is_valid():
		pause_face_turn.call(force)


func restore_face() -> void:
	if restore_face_turn.is_valid():
		restore_face_turn.call()


## A host value that may be missing: `null` outside a scene, so a caller tests it.
func call_value(callback: Callable, fallback: Variant = null) -> Variant:
	return callback.call() if callback.is_valid() else fallback


func missionary_body() -> Variant:
	return missionary_anon.call() if missionary_anon.is_valid() else null


func feature(name: String, fallback := true) -> bool:
	return bool(features.get(name, fallback))
