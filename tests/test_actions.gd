extends SceneTree
## Pure act-action checks: lean mapping, threshold hysteresis, pose support, smack side.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_actions.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const PALM_SCALE := preload("res://mods/unfplap/palm_scale.gd")
const WING := preload("res://mods/unfplap/wing_control.gd")
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
	check(RUNTIME.lean_action_kind(CATALOG.STANDING, -1.0) == "reach", "Q fires reach in standing")
	check(RUNTIME.lean_action_kind(CATALOG.STANDING, 1.0) == "reach", "E fires reach in standing")

	check(RUNTIME.smack_side_index(0.4) == 0, "right lean smacks left cheek")
	check(RUNTIME.smack_side_index(-0.4) == 1, "left lean smacks right cheek")
	check(RUNTIME.smack_side_index(0.0) == -1, "centered smack is random")

	check(near(RUNTIME.lean_distance(1.0), 0.24), "forward lean distance")
	check(near(RUNTIME.lean_distance(-1.0), -0.08), "backward lean distance is halved")
	check(near(RUNTIME.lean_size_scale_for(1.0), 1.0), "JRHNBR lean scale is reference")
	check(near(RUNTIME.lean_size_scale_for(0.66), 1.34), "Canon lean scale is +34 percent")
	check(near(RUNTIME.lean_distance(1.0, 1.34), 0.3216), "Canon forward lean scales")
	check(near(RUNTIME.lean_distance(-1.0, 1.34), -0.1072), "Canon back lean scales")

	var hip := Node3D.new()
	root.add_child(hip)
	var lean_runtime: Node = RUNTIME.new()
	lean_runtime.pose_id = CATALOG.STANDING
	lean_runtime._free_camera_active = true
	lean_runtime._lean_view_forward = 1.0
	lean_runtime._lean_view_side = 0.0
	lean_runtime.depth = 0.0
	var lean_scale: float = lean_runtime._standing_lean_scale()
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

	check(near(RUNTIME.CARESS_SPEED_RAD_S, 3.6), "caress speed")
	check(near(RUNTIME.CARESS_RADIUS_M, 0.04125), "caress radius")
	var right_palm: Basis = RUNTIME.palm_surface_basis("right", Vector3.RIGHT, Vector3.FORWARD)
	var left_palm: Basis = RUNTIME.palm_surface_basis("left", Vector3.RIGHT, Vector3.FORWARD)
	check((-right_palm.x).dot(Vector3.LEFT) > 0.99 and (-right_palm.z).dot(Vector3.FORWARD) > 0.99,
		"right palm faces the coat with fingers forward")
	check(left_palm.x.dot(Vector3.LEFT) > 0.99 and (-left_palm.z).dot(Vector3.FORWARD) > 0.99,
		"left palm faces the coat with fingers forward")
	check(right_palm.determinant() > 0.99 and left_palm.determinant() > 0.99,
		"palm surface bases stay orthonormal")
	check(near(RUNTIME.CARESS_OVAL_ACROSS, 1.30) and near(RUNTIME.CARESS_OVAL_UP, 0.70),
		"caress path is an oval")
	check(near(RUNTIME.CARESS_UP_BIAS_M, 0.05), "caress rub lifted 5 cm above the mark")
	check(near(RUNTIME.caress_phase_step(0.5, true, 0.25),
		RUNTIME.CARESS_SPEED_RAD_S * 0.25 + 0.5), "caress phase advances while moving")
	check(near(RUNTIME.caress_phase_step(0.5, false, 0.25), 0.5),
		"caress phase holds while movement is off")
	check(near(RUNTIME.PALM_ON_COAT_CLEARANCE_M, 0.04), "palm sits 4 cm above the coat at 1.0 scale")
	check(near(RUNTIME.palm_clearance_for(0.66), 0.0264), "Canon palm clearance scales down")
	check(near(RUNTIME.palm_clearance_for(1.10), 0.044), "Hoers palm clearance scales up")
	check(near(RUNTIME.palm_clearance_for(1.0, 0.07), 0.07),
		"caress palm distance overrides the default")
	check(RUNTIME._region_ignored("tail", ["tail"]), "caress ignores the tail hull")
	check(not RUNTIME._region_ignored("flank", ["tail"]), "caress keeps the flank hull")
	check(near(RUNTIME.PALM_NORMAL_MAX_DEG_S, 120.0), "palm normal turns at a bounded rate")
	var capped: Vector3 = RUNTIME.rotate_normal_toward(Vector3.UP, Vector3.RIGHT, deg_to_rad(10.0))
	check(near(rad_to_deg(capped.angle_to(Vector3.UP)), 10.0), "normal rate caps a large turn")
	check(RUNTIME.rotate_normal_toward(Vector3.UP, Vector3.RIGHT, PI).is_equal_approx(Vector3.RIGHT),
		"normal rate reaches the target")
	var canon_caress: Dictionary = RUNTIME.caress_profile_for("canon")
	var mounting_caress: Dictionary = RUNTIME.caress_profile_for("mounting")
	check(float(canon_caress["up"]) < float(mounting_caress["up"]), "Canon caress sits lower")
	check(near(float(mounting_caress["out"]) * 2.0, 0.04), "JRHNBR caress points 4 cm wider")
	check(RUNTIME.caress_profile_for("") == RUNTIME.caress_profile_for("mounting"),
		"unknown size falls back to JRHNBR caress")
	check(near(WING.WING_STANDING_HOLD, 0.65), "standing wings start at 60 degrees")
	check(near(RUNTIME.STANDING_KISS_LEAN, 0.90), "standing F kiss needs a full shoulder lean")
	check(RUNTIME.standing_kiss_wanted(true, 1.0), "F kisses at a full shoulder lean")
	check(not RUNTIME.standing_kiss_wanted(true, 0.8), "F does not kiss at a partial lean")

	check(near(RUNTIME.JIGGLE_RUMP_SCALE, 2.8), "thrust jiggle scale")
	check(near(RUNTIME.CAM_SURGE_M, 0.06), "camera surge amplitude")
	check(near(RUNTIME.CAM_BOB_M, 0.02), "camera bob amplitude")
	check(near(RUNTIME.KISS_LEAN_M, 0.27) and near(RUNTIME.KISS_LEAN_SIDE_M, 0.18)
		and near(RUNTIME.KISS_LEAN_DROP_M, 0.035), "kiss leans in, sideways and slightly lower")
	check(near(RUNTIME.KISS_CAMERA_YAW_DEG, 10.0), "kiss camera turns 10 degrees toward her")
	check(near(RUNTIME.KISS_PONY_SIDE_SIGN, 1.0), "pony kiss side matches the input side sign")
	check(near(RUNTIME.kiss_pony_side(-1.0), -1.0), "left lean gives her the opposite head tilt")
	check(near(RUNTIME.kiss_pony_side(1.0), 1.0), "right lean gives her the opposite head tilt")
	check(near(RUNTIME.kiss_pony_side(0.0), 0.0), "centered kiss leaves the side to her")
	check(near(RUNTIME.kiss_lateral_offset(-1.0, -1.0, 0.0), -0.18),
		"kiss starts at the lean lateral offset")
	check(near(RUNTIME.kiss_lateral_offset(-0.5, -1.0, 1.0), -0.18),
		"full kiss uses one lateral offset")
	check(near(RUNTIME.kiss_lateral_offset(-0.5, -1.0, 0.5), -0.135),
		"kiss lateral crossfades instead of stacking")
	check(near(RUNTIME.standing_palm_scale_for("canon"), 0.85), "Canon standing palm scale")
	check(near(RUNTIME.standing_palm_scale_for("mounting"), 0.95), "JRHNBR standing palm scale")
	check(near(RUNTIME.standing_palm_scale_for("hoers"), 1.0), "Hoers standing palm scale unchanged")

	var sk := Skeleton3D.new()
	root.add_child(sk)
	sk.add_bone("LeftHand")
	sk.add_bone("RightHand")
	var palm := PALM_SCALE.new()
	palm.set("skeleton", sk)
	palm.set("factor", 0.85)
	palm.call("apply_scale")
	check(near(sk.get_bone_pose_scale(sk.find_bone("LeftHand")).x, 0.85),
		"palm scale applies to the left hand")
	check(near(sk.get_bone_pose_scale(sk.find_bone("RightHand")).x, 0.85),
		"palm scale applies to the right hand")
	palm.call("restore")
	check(sk.get_bone_pose_scale(sk.find_bone("LeftHand")).is_equal_approx(Vector3.ONE),
		"palm scale restores the left hand")
	check(sk.get_bone_pose_scale(sk.find_bone("RightHand")).is_equal_approx(Vector3.ONE),
		"palm scale restores the right hand")
	palm.free()
	sk.free()

	check(near(RUNTIME.glance_back_fade_for(1.0), RUNTIME.GLANCE_BACK_FADE),
		"default glance-back fade")
	check(near(RUNTIME.glance_back_fade_for(2.0), RUNTIME.GLANCE_BACK_FADE * 0.5),
		"faster glance-back speed shortens the fade")
	check(near(RUNTIME.glance_back_fade_for(0.1), RUNTIME.GLANCE_BACK_FADE / 0.25),
		"glance-back speed clamps slow")
	check(near(RUNTIME.glance_back_fade_for(9.0), RUNTIME.GLANCE_BACK_FADE / 3.0),
		"glance-back speed clamps fast")

	var phase := RUNTIME.hip_phase_step(0.0, 1.0, 1.0 / 60.0)
	check(phase > 0.0 and phase < 1.0, "hip phase eases toward the mouse depth")
	for _step: int in 120:
		phase = RUNTIME.hip_phase_step(phase, 1.0, 1.0 / 60.0)
	check(near(phase, 1.0, 0.01), "hip phase settles at full depth")
	check(near(RUNTIME.hip_phase_step(0.0, -10.0, 1.0 / 60.0), 0.0),
		"hip phase clamps depth to zero")

	var live_runtime: Node = RUNTIME.new()
	live_runtime.state = 2 # ACTIVE
	live_runtime.pose_id = CATALOG.STANDING
	live_runtime.call("apply_live_settings")
	check(live_runtime._features.has("hud_readouts"), "live settings refresh feature flags")
	check(live_runtime._camera_surge >= 0.0 and live_runtime._camera_surge <= 1.0,
		"live settings refresh camera thrust")
	live_runtime.free()

	check(near(RUNTIME.HOLD_SWAY_FORWARD, 0.010) and near(RUNTIME.HOLD_SWAY_SIDE, 0.0084),
		"idle camera sway amplitude")
	check(near(RUNTIME.MOUNTING_STANDING_CAMERA_LIFT_M, 0.10), "JRHNBR standing camera raised 10 cm")
	check(near(RUNTIME.LEAN_SIDE_M, 0.18), "side lean travel")
	check(near(RUNTIME.LEAN_SIDE_ROLL_DEG, 8.0), "side lean roll stronger")
	check(near(RUNTIME.LEAN_FIRE, 0.75) and near(RUNTIME.LEAN_RELEASE, 0.60),
		"lean threshold uses 75/60 hysteresis")

	check(near(RUNTIME._lean_step(0.0, 1.0, 0.25), 0.5), "lean ramps in over half a second")
	check(near(RUNTIME._lean_step(1.0, 0.0, 0.8), 1.0),
		"released lean holds its position")
	check(near(RUNTIME._lean_step(1.0, 0.0, 0.8, true), 0.5),
		"shoulder recentre returns over 1.6 seconds")

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
