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
var lean_view_forward := 0.0
var lean_view_side := 0.0
var lean_sway := 0.0
var bob := 0.0
var back := 0.0
var back_target := 0.0
var forced_glance := ""
var pose_config: Dictionary = {}
var presentation_config: Dictionary = {}
var kiss_amount := 0.0
var kiss_active := false
var kiss_side := 0.0
## The act's bed frame, or null outside a missionary act.
var bed_frame: Variant = null

# Scene handles the act owns. Presentation modules are scene adapters, so they receive the nodes
# they work on rather than reading the runtime's fields.
var main: Variant = null
var pony: Variant = null
var camera: Camera3D = null
var pose: Variant = null

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
