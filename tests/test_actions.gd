extends SceneTree
## Pure act-action checks: lean mapping, threshold hysteresis, pose support, smack side.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_actions.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	var forward: Vector2 = RUNTIME.lean_targets(0.0, -1.0)
	check(near(forward.x, 1.0) and near(forward.y, 0.0), "W leans forward")
	var back: Vector2 = RUNTIME.lean_targets(0.0, 1.0)
	check(near(back.x, -1.0) and near(back.y, 0.0), "S leans back")
	var left: Vector2 = RUNTIME.lean_targets(-1.0, 0.0)
	check(near(left.x, 1.0) and near(left.y, -1.0), "Q is forward plus left")
	var right: Vector2 = RUNTIME.lean_targets(1.0, 0.0)
	check(near(right.x, 1.0) and near(right.y, 1.0), "E is forward plus right")
	var both: Vector2 = RUNTIME.lean_targets(1.0, 1.0)
	check(near(both.x, 0.0) and near(both.y, 1.0), "S plus E cancels forward")
	var clamped: Vector2 = RUNTIME.lean_targets(1.0, -1.0)
	check(near(clamped.x, 1.0) and near(clamped.y, 1.0), "combined lean clamps forward")

	check(RUNTIME.lean_action_kind(CATALOG.MISSIONARY, -1.0) == "kiss", "Q fires kiss in missionary")
	check(RUNTIME.lean_action_kind(CATALOG.MISSIONARY, 1.0) == "", "E has no missionary action")
	check(RUNTIME.lean_action_kind(CATALOG.HORSE, -1.0) == "reach", "Q fires reach in horse")
	check(RUNTIME.lean_action_kind(CATALOG.HORSE, 1.0) == "reach", "E fires reach in horse")

	check(RUNTIME.smack_side_index(0.4) == 0, "right lean smacks left cheek")
	check(RUNTIME.smack_side_index(-0.4) == 1, "left lean smacks right cheek")
	check(RUNTIME.smack_side_index(0.0) == -1, "centered smack is random")

	check(near(RUNTIME.lean_distance(1.0), 0.24), "forward lean distance increased 50 percent")
	check(near(RUNTIME.lean_distance(-1.0), -0.08), "backward lean distance is halved")
	check(near(RUNTIME.lean_size_scale_for(1.0), 1.0), "JRHNBR lean scale is reference")
	check(near(RUNTIME.lean_size_scale_for(0.66), 1.34), "Canon lean scale is +34 percent")
	check(near(RUNTIME.lean_distance(1.0, 1.34), 0.3216), "Canon forward lean scales")
	check(near(RUNTIME.lean_distance(-1.0, 1.34), -0.1072), "Canon back lean scales")

	var hip := Node3D.new()
	root.add_child(hip)
	var lean_runtime: Node = RUNTIME.new()
	lean_runtime.pose_id = CATALOG.HORSE
	lean_runtime._free_camera_active = true
	lean_runtime._lean_view_forward = 1.0
	lean_runtime._lean_view_side = 0.0
	lean_runtime.depth = 0.0
	var lean_scale: float = lean_runtime._pose2_lean_scale()
	lean_runtime.apply_anon_lean(hip, Basis.IDENTITY)
	check(near(hip.global_position.z, RUNTIME.lean_distance(1.0, lean_scale)),
		"forward lean keeps the pelvis behind the rump")
	var side_hip := Node3D.new()
	root.add_child(side_hip)
	lean_runtime._lean_view_forward = 0.0
	lean_runtime._lean_view_side = 1.0
	lean_runtime.apply_anon_lean(side_hip, Basis.IDENTITY)
	check(near(side_hip.global_position.x, -RUNTIME.LEAN_SIDE_M * lean_scale),
		"side lean keeps the pelvis centred")
	hip.free()
	side_hip.free()
	lean_runtime.free()

	check(near(RUNTIME.CARESS_SPEED_RAD_S, 4.5), "caress speed increased 50 percent again")
	check(near(RUNTIME.CARESS_OVAL_ACROSS, 1.30) and near(RUNTIME.CARESS_OVAL_UP, 0.70),
		"caress path is an oval")
	var canon_caress: Dictionary = RUNTIME.caress_profile_for("canon")
	var mounting_caress: Dictionary = RUNTIME.caress_profile_for("mounting")
	check(float(canon_caress["up"]) < float(mounting_caress["up"]), "Canon caress sits lower")
	check(near(float(mounting_caress["out"]) * 2.0, 0.04), "JRHNBR caress points 4 cm wider")
	check(RUNTIME.caress_profile_for("") == RUNTIME.caress_profile_for("mounting"),
		"unknown size falls back to JRHNBR caress")
	check(near(RUNTIME.WING_POSE2_HOLD, 0.65), "pose-2 wings start at 60 degrees")
	check(near(RUNTIME.POSE2_KISS_LEAN, 0.90), "pose-2 F kiss needs a full shoulder lean")
	check(RUNTIME.pose2_kiss_wanted(true, 1.0), "F kisses at a full shoulder lean")
	check(not RUNTIME.pose2_kiss_wanted(true, 0.8), "F does not kiss at a partial lean")

	check(near(RUNTIME.JIGGLE_RUMP_SCALE, 2.8), "pump jiggle reduced 20 percent")
	check(near(RUNTIME.CAMERA_ROCK_IMPULSE, 0.20), "camera rock impulse increased")
	check(near(RUNTIME.CAMERA_ROCK_LIMIT, 0.026), "camera rock limit increased")
	check(near(RUNTIME.LEAN_SIDE_M, 0.18), "side lean travel tripled")
	check(near(RUNTIME.LEAN_SIDE_ROLL_DEG, 8.0), "side lean roll stronger")
	check(near(RUNTIME.LEAN_FIRE, 0.75) and near(RUNTIME.LEAN_RELEASE, 0.60),
		"lean threshold uses 75/60 hysteresis")

	check(near(RUNTIME._lean_step(0.0, 1.0, 0.25), 0.5), "lean ramps in over half a second")
	check(near(RUNTIME._lean_step(1.0, 0.0, 0.8), 0.5), "lean returns over 1.6 seconds")
	check(near(RUNTIME._lean_step(1.0, 0.0, 0.8, false), 1.0),
		"lean return disabled holds position")

	var runtime: Node = RUNTIME.new()
	runtime.state = 2 # ACTIVE
	runtime.pose_id = CATALOG.MISSIONARY
	runtime._lean_side = 0.74
	runtime._lean_action_tick()
	check(not bool(runtime._lean_action_active), "below 75 percent does not fire")
	runtime._lean_side = -0.75
	runtime._lean_action_tick()
	check(bool(runtime._lean_action_active), "75 percent fires")
	check(str(runtime._lean_action_kind) == "kiss", "missionary Q starts a kiss")
	runtime._lean_side = -0.65
	runtime._lean_action_tick()
	check(bool(runtime._lean_action_active), "action stays above 60 percent")
	runtime._lean_side = -0.60
	runtime._lean_action_tick()
	check(not bool(runtime._lean_action_active), "action releases at 60 percent")
	runtime.free()

	var cuddle_runtime: Node = RUNTIME.new()
	var cuddle_pony := Node3D.new()
	cuddle_pony.set_meta("couch_cuddle", true)
	cuddle_runtime.pony = cuddle_pony
	cuddle_runtime.state = 0 # IDLE
	cuddle_runtime._suppress_auto_cuddle()
	check(cuddle_pony.has_meta("couch_cuddle"), "idle runtime leaves native bed cuddles alone")
	cuddle_runtime.state = 2 # ACTIVE
	cuddle_runtime._suppress_auto_cuddle()
	check(not cuddle_pony.has_meta("couch_cuddle"), "active runtime suppresses auto cuddle")
	cuddle_pony.free()
	cuddle_runtime.free()

	print("ACTIONS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACTIONS_PASS")
	quit(0 if failures == 0 else 1)
