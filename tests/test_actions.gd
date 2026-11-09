extends SceneTree
## Pure act-action checks: lean mapping, threshold hysteresis, pose support, smack side.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_actions.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const PALM_SCALE := preload("res://mods/unfplap/palm_scale.gd")
const WING := preload("res://mods/unfplap/wing_control.gd")
const MOTION := preload("res://mods/unfplap/act_motion.gd")
const CAESS := preload("res://mods/unfplap/standing_caress.gd")
const KISS := preload("res://mods/unfplap/kiss_control.gd")
const STANDING_CAMERA := preload("res://mods/unfplap/standing_camera.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const STANDING_ANON := preload("res://mods/unfplap/standing_anon.gd")
const HIP_THRUST := preload("res://mods/unfplap/anon_hip_thrust.gd")
const MISSIONARY_ANON := preload("res://mods/unfplap/missionary_anon.gd")
const TAIL := preload("res://mods/unfplap/tail_pose.gd")

class FakeTail extends Node:
	var last_strength := 0.0

	func thrust(strength: float) -> void:
		last_strength = strength


class FakeFlank extends Node3D:
	var marks: Array = []
	var ages: Array = []
	var _jiggle_targets: Array = []
	var _jiggle_amount := 0.0


class FakeAnatomy extends Node:
	var mesh: MeshInstance3D
	var material: ShaderMaterial
	var outline: ShaderMaterial

	func body_coat_mesh() -> MeshInstance3D:
		return mesh

	func body_coat_material() -> ShaderMaterial:
		return material

	func body_outline_material() -> ShaderMaterial:
		return outline

	func detach() -> void:
		pass


class FakeTouchBody extends Node:
	var _rigs: Array = []
	var _entries: Array = []
	var syncs := 0

	func _unprofiled_sync(_rig: int, _every: bool) -> void:
		syncs += 1


class FakeCaressPony extends Node3D:
	var touch_body: Node
	var skeleton: Skeleton3D


class FakeBody extends Node3D:
	var _left_foot: Node3D
	var _right_foot: Node3D


class FakeMain extends Node:
	var debug_logs := true
	var debug_perf := true
	var lines: Array[String] = []

	func debug(text: String) -> void:
		lines.append(text)


func _check_body_coat_jiggle_target() -> void:
	var flank := FakeFlank.new()
	var body := MeshInstance3D.new()
	var material := ShaderMaterial.new()
	var outline := ShaderMaterial.new()
	var anatomy := FakeAnatomy.new()
	anatomy.mesh = body
	anatomy.material = material
	anatomy.outline = outline
	flank._jiggle_targets = []
	var was_on := SETTINGS.body_coat_deform.get_bool()
	SETTINGS.body_coat_deform.set_bool(true)
	var runtime: Node = RUNTIME.new()
	runtime._flank = flank
	runtime._anatomy = anatomy
	root.add_child(runtime)
	root.add_child(flank)
	root.add_child(anatomy)
	root.add_child(body)
	runtime.call("_attach_body_coat_jiggle_target")
	check(flank._jiggle_targets.size() == 2, "body and outline join the jiggle targets")
	runtime.call("_attach_body_coat_jiggle_target")
	check(flank._jiggle_targets.size() == 2, "body target is not duplicated")
	root.remove_child(runtime)
	runtime.free()
	root.remove_child(anatomy)
	anatomy.free()
	root.remove_child(body)
	body.free()
	root.remove_child(flank)
	flank.free()
	SETTINGS.body_coat_deform.set_bool(was_on)


func _check_tail_tuning() -> void:
	var tail_runtime: Node = RUNTIME.new()
	var tail_pony := Node3D.new()
	tail_runtime.set("pony", tail_pony)
	tail_runtime.set("_id", "twilight_sparkle")
	tail_runtime.set("pose_id", CATALOG.STANDING)
	tail_runtime.set("_presentation_cfg", {"tail": {"yaw_deg": 40.0, "pitch_deg": 10.0}})
	tail_runtime.call("_sync_standing_pose_config")
	var cfg: Dictionary = tail_runtime.get("_pose_cfg")
	check(near(float(cfg.get("tail_aside", 0.0)), deg_to_rad(40.0)), "tail yaw tunable reaches the pose")
	check(near(float(cfg.get("tail_lift", 0.0)), deg_to_rad(10.0)), "tail pitch tunable reaches the pose")
	tail_runtime.set("_presentation_cfg", {})
	tail_runtime.call("_sync_standing_pose_config")
	cfg = tail_runtime.get("_pose_cfg")
	check(near(float(cfg.get("tail_aside", 0.0)), deg_to_rad(45.0)), "tail yaw default")
	check(near(float(cfg.get("tail_lift", 0.0)), deg_to_rad(32.0)), "tail pitch default")
	tail_pony.free()
	tail_runtime.free()


func _check_perf_probe() -> void:
	var fake_main := FakeMain.new()
	var probe: Node = RUNTIME.new()
	probe.set("main", fake_main)
	probe.set("_id", "twilight_sparkle")
	probe.set("pose_id", CATALOG.STANDING)
	probe.set("state", 2)
	probe.call("perf_note", "probe_chunk", 1200)
	probe.call("perf_note", "probe_chunk", 800)
	probe.call("_perf_tick", 0.4)
	check(fake_main.lines.is_empty(), "perf window waits for a full second")
	probe.call("_perf_tick", 0.7)
	check(fake_main.lines.size() == 1, "perf prints one block a second")
	if not fake_main.lines.is_empty():
		var line := fake_main.lines[0]
		check(line.begins_with("perf pony=twilight_sparkle pose=standing state=2"),
			"perf block names the pony and pose")
		check(line.contains("\n\tprobe_chunk"), "perf block lists a timed chunk")
		check(line.contains("2.00ms/s"), "perf block totals the window")
	fake_main.debug_logs = false
	probe.call("perf_note", "hidden_chunk", 500)
	probe.call("_perf_tick", 1.1)
	check(fake_main.lines.size() == 1, "perf is silent with debug logs off")
	fake_main.debug_logs = true
	fake_main.debug_perf = false
	probe.call("perf_note", "hidden_chunk", 500)
	probe.call("_perf_tick", 1.1)
	check(fake_main.lines.size() == 1, "perf is silent with perf logs off")
	probe.free()
	fake_main.free()


## A held caress must solve the hand through the regular arm pole and return to the authored
## frame without the scaled-basis slerp error the first implementation logged every frame.
func _check_missionary_hand_hold() -> void:
	var anon: Node = MISSIONARY_ANON.new()
	root.add_child(anon)
	var sk := Skeleton3D.new()
	root.add_child(sk)
	var armature := sk.add_bone("armature")
	sk.set_bone_parent(armature, -1)
	var upper := sk.add_bone("LeftUpperArm")
	sk.set_bone_parent(upper, armature)
	var lower := sk.add_bone("LeftLowerArm")
	sk.set_bone_parent(lower, upper)
	sk.set_bone_rest(lower, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.30, 0.0)))
	var hand := sk.add_bone("LeftHand")
	sk.set_bone_parent(hand, lower)
	sk.set_bone_rest(hand, Transform3D(Basis(Vector3.UP, 0.2), Vector3(0.0, -0.25, 0.0)))
	sk.reset_bone_poses()
	anon.set("skeleton", sk)
	anon.set("active", true)
	var offset := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.07))
	anon.set("_hand_offsets", {"left": offset, "right": offset})
	var hold := Transform3D(Basis(Vector3.UP, 0.2), Vector3(0.05, -0.45, 0.10))
	anon.set("_holds", {"left": hold})
	anon.set("_hold_from", {"left": hold})
	anon.set("_hold_started", {"left": Time.get_ticks_msec() - 1000})
	var plants := {"Left": sk.get_bone_global_pose(hand)}
	anon.call("_place_hands", plants, Transform3D.IDENTITY)
	var solved := sk.get_bone_global_pose(hand)
	check(solved.is_finite() and solved.origin.length() < 0.6,
		"a held hand solves to the caress target")
	check(solved.basis.get_scale().is_equal_approx(Vector3.ONE),
		"the held hand keeps the regular-game orthonormal basis")
	anon.call("clear_hold_target", "left")
	anon.set("_release_started", {"left": Time.get_ticks_msec() - 1000})
	anon.call("_place_hands", plants, Transform3D.IDENTITY)
	check(sk.get_bone_global_pose(hand).is_finite(),
		"the release returns to the authored hand frame")
	var touch := FakeTouchBody.new()
	root.add_child(touch)
	touch.set("_rigs", [sk])
	touch.set("_entries", [{}])
	var caress_pony := FakeCaressPony.new()
	root.add_child(caress_pony)
	caress_pony.skeleton = sk
	caress_pony.touch_body = touch
	var caress: RefCounted = CAESS.new()
	caress.set("pony", caress_pony)
	caress.call("_sync_missionary_touch")
	check(touch.syncs == 1, "the caress refreshes the touch hulls from the act skeleton")
	caress_pony.free()
	touch.free()
	sk.free()
	anon.free()

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
	var forward: Vector2 = MOTION.lean_targets(0.0, -1.0)
	check(near(forward.x, 1.0) and near(forward.y, 0.0), "W leans forward")
	var back: Vector2 = MOTION.lean_targets(0.0, 1.0)
	check(near(back.x, -1.0) and near(back.y, 0.0), "S leans back")
	var left: Vector2 = MOTION.lean_targets(-1.0, 0.0)
	check(near(left.x, 1.0) and near(left.y, -1.0), "Q is forward plus left")
	var right: Vector2 = MOTION.lean_targets(1.0, 0.0)
	check(near(right.x, 1.0) and near(right.y, 1.0), "E is forward plus right")
	var both: Vector2 = MOTION.lean_targets(1.0, 1.0)
	check(near(both.x, 0.0) and near(both.y, 1.0), "S plus E cancels forward")
	var clamped: Vector2 = MOTION.lean_targets(1.0, -1.0)
	check(near(clamped.x, 1.0) and near(clamped.y, 1.0), "combined lean clamps forward")

	check(MOTION.lean_action_kind(CATALOG.MISSIONARY, -1.0) == "",
		"missionary Q is a lean only; the kiss is on the front lean")
	check(MOTION.lean_action_kind(CATALOG.MISSIONARY, 1.0) == "", "E has no missionary action")
	check(MOTION.lean_action_kind(CATALOG.STANDING, -1.0) == "reach", "Q fires reach in standing")
	check(MOTION.lean_action_kind(CATALOG.STANDING, 1.0) == "reach", "E fires reach in standing")

	check(CAESS.smack_side_index(0.4) == 0, "right lean smacks left cheek")
	check(CAESS.smack_side_index(-0.4) == 1, "left lean smacks right cheek")
	check(CAESS.smack_side_index(0.0) == -1, "centered smack is random")
	var up_offset: Vector3 = CAESS.smack_query_offset(0.05, 0.02, 1.0,
		Vector3.UP, Vector3.BACK)
	check(near(up_offset.y, 0.05) and near(up_offset.z, 0.02),
		"smack height and hind offsets use signed up and back")
	var down_offset: Vector3 = CAESS.smack_query_offset(-0.03, 0.10, 2.0,
		Vector3.UP, Vector3.BACK)
	check(near(down_offset.y, -0.06) and near(down_offset.z, 0.20),
		"smack query offset scales with the pony")
	var height_controller := CAESS.new()
	height_controller.set("_presentation_cfg", {"smack": {"height_m": 0.12}})
	check(near(float(height_controller.call("_smack_height_m")), 0.12),
		"smack height reads the presentation setting")
	var default_height := CAESS.new()
	check(near(float(default_height.call("_smack_height_m")), -0.03),
		"smack height falls back to 3 cm below the mark")
	var smack_contact := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))
	var smack_raised: Transform3D = CAESS.smack_raise_frame(
		smack_contact, Vector3.RIGHT, 0.18, 0.05, Vector3.BACK, 15.0)
	check(near(smack_raised.origin.x, 0.18) and near(smack_raised.origin.z, 0.05)
		and near(smack_raised.origin.y, 1.0), "smack raise lifts along the normal and back")
	check((-smack_raised.basis.z).y < (-smack_contact.basis.z).y,
		"raised palm pitches the fingers down")
	var smack_lowered: Transform3D = CAESS.smack_raise_frame(
		smack_contact, Vector3.RIGHT, -0.10, -0.04, Vector3.BACK, 15.0)
	check(near(smack_lowered.origin.x, -0.10) and near(smack_lowered.origin.z, -0.04),
		"smack raise and arc are applied unclamped")
	var straight_palm: Basis = CAESS.palm_surface_basis("right", Vector3.RIGHT, Vector3.FORWARD)
	var pitched_palm: Basis = CAESS.smack_pitch_basis(straight_palm, 15.0)
	check(pitched_palm.determinant() > 0.99, "palm pitch stays orthonormal")
	check(pitched_palm.x.dot(straight_palm.x) > 0.999, "palm pitch keeps the palm normal")
	check((-pitched_palm.z).y < (-straight_palm.z).y, "positive pitch lowers the fingers")
	var pitched_up: Basis = CAESS.smack_pitch_basis(straight_palm, -15.0)
	check((-pitched_up.z).y > (-straight_palm.z).y, "negative pitch raises the fingers")
	var smack_left_palm: Basis = CAESS.palm_surface_basis("left", Vector3.RIGHT, Vector3.FORWARD)
	var smack_left_pitched: Basis = CAESS.smack_pitch_basis(smack_left_palm, 15.0)
	check((-smack_left_pitched.z).y < (-smack_left_palm.z).y,
		"left palm also pitches down")
	check(smack_left_pitched.x.dot(smack_left_palm.x) > 0.999,
		"left palm pitch keeps the palm normal")
	check(CAESS.smack_pitch_basis(straight_palm, 0.0).is_equal_approx(straight_palm),
		"zero palm pitch keeps the basis")
	check(CAESS.smack_finger_hint(false, Vector3.FORWARD).is_equal_approx(Vector3.DOWN),
		"non-caress smack points the fingers down")
	check(CAESS.smack_finger_hint(true, Vector3.FORWARD).is_equal_approx(Vector3.FORWARD),
		"caress smack keeps the fingers forward")
	var swing_contact := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))
	var swing := CAESS.smack_swing_raise_frame(
		swing_contact, Vector3.RIGHT, Vector3.BACK, 0.20, 15.0)
	check(swing.origin.z > swing_contact.origin.z, "non-caress swing starts behind")
	check(swing.origin.y < swing_contact.origin.y, "non-caress swing starts below")
	check(swing.origin.x > swing_contact.origin.x, "non-caress swing clears outward")
	check((-swing.basis.z).y < (-swing_contact.basis.z).y,
		"non-caress swing points the fingers down")
	var raise_mid: Transform3D = CAESS.smack_raise_blend(
		smack_contact, smack_raised, Vector3.BACK * 0.02, 0.5)
	check(raise_mid.origin.x > smack_contact.origin.x
		and raise_mid.origin.x < smack_raised.origin.x, "smack raise blends between frames")
	check(near(raise_mid.origin.z - smack_contact.origin.z
		- (smack_raised.origin.z - smack_contact.origin.z) * 0.5, 0.02, 0.002),
		"smack raise bows along the arc parameter")
	var no_arc_mid: Transform3D = CAESS.smack_raise_blend(
		smack_contact, smack_raised, Vector3.ZERO, 0.5)
	check(near(no_arc_mid.origin.z - smack_contact.origin.z,
		(smack_raised.origin.z - smack_contact.origin.z) * 0.5, 0.002),
		"zero arc is a straight blend")
	var strike_mid: Transform3D = CAESS.smack_strike_blend(smack_raised, smack_contact, 0.5)
	check(strike_mid.origin.distance_to(smack_raised.origin)
		< strike_mid.origin.distance_to(smack_contact.origin), "smack strike accelerates")
	check(CAESS.smack_strike_blend(smack_raised, smack_contact, 1.0).origin.is_equal_approx(
		smack_contact.origin), "smack strike reaches the contact")
	check(CAESS.smack_recover_blend(smack_contact, smack_raised, 1.0).origin.is_equal_approx(
		smack_raised.origin), "smack recovery reaches its target")
	check(near(CAESS.SMACK_RAISE_SPEED_M_S, 2.0)
		and near(CAESS.SMACK_RETURN_SPEED_M_S, 6.0), "smack default speeds")
	check(near(CAESS.SMACK_CONTACT_HOLD_SECONDS, 0.03), "smack contact hold")
	var quad_faces := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0),
		Vector3(0, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
	])
	var quad_normals := PackedVector3Array([
		Vector3.BACK, Vector3.BACK, Vector3.BACK,
		Vector3.BACK, Vector3.BACK, Vector3.BACK,
	])
	var flank_hit: Dictionary = CAESS.closest_flank_hit(
		quad_faces, quad_normals, Vector3(0.5, 0.5, 1.0))
	var flank_point: Vector3 = flank_hit.get("point", Vector3.INF)
	var flank_normal: Vector3 = flank_hit.get("normal", Vector3.ZERO)
	check(near(float(flank_hit.get("distance", -1.0)), 1.0), "closest flank distance")
	check(flank_point.is_equal_approx(Vector3(0.5, 0.5, 0.0)), "closest flank point")
	check(flank_normal.dot(Vector3.BACK) > 0.99, "closest flank normal")
	var edge_hit: Dictionary = CAESS.closest_flank_hit(
		quad_faces, quad_normals, Vector3(-1.0, 0.5, 0.0))
	var edge_point: Vector3 = edge_hit.get("point", Vector3.INF)
	check(edge_point.is_equal_approx(Vector3(0.0, 0.5, 0.0)),
		"closest flank clamps outside the patch")
	check(CAESS.closest_flank_hit(PackedVector3Array(), PackedVector3Array(),
		Vector3.ZERO).is_empty(), "empty flank patch has no hit")

	check(near(MOTION.lean_distance(1.0), 0.24), "forward lean distance")
	check(near(MOTION.lean_distance(-1.0), 0.0), "backward lean has no travel")
	check(near(MOTION.lean_size_scale_for(1.0), 1.0), "JRHNBR lean scale is reference")
	check(near(MOTION.lean_size_scale_for(0.66), 1.34), "Canon lean scale is +34 percent")
	check(near(MOTION.lean_distance(1.0, 1.34), 0.3216), "Canon forward lean scales")

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
	check(near(hip.global_position.z, MOTION.lean_distance(1.0, lean_scale)),
		"forward lean keeps the pelvis behind the rump")
	var side_hip := Node3D.new()
	root.add_child(side_hip)
	lean_runtime._lean_view_forward = 0.0
	lean_runtime._lean_view_side = 1.0
	lean_runtime.apply_anon_lean(side_hip, Basis.IDENTITY)
	check(near(side_hip.global_position.x, -MOTION.LEAN_SIDE_M * lean_scale),
		"side lean keeps the pelvis centred")
	hip.free()
	side_hip.free()
	lean_runtime.free()

	check(near(CAESS.CARESS_SPEED_RAD_S, 3.6), "caress speed")
	check(near(CAESS.CARESS_RADIUS_M, 0.04125), "caress radius")
	var right_palm: Basis = CAESS.palm_surface_basis("right", Vector3.RIGHT, Vector3.FORWARD)
	var left_palm: Basis = CAESS.palm_surface_basis("left", Vector3.RIGHT, Vector3.FORWARD)
	check((-right_palm.x).dot(Vector3.LEFT) > 0.99 and (-right_palm.z).dot(Vector3.FORWARD) > 0.99,
		"right palm faces the coat with fingers forward")
	check(left_palm.x.dot(Vector3.LEFT) > 0.99 and (-left_palm.z).dot(Vector3.FORWARD) > 0.99,
		"left palm faces the coat with fingers forward")
	check(right_palm.determinant() > 0.99 and left_palm.determinant() > 0.99,
		"palm surface bases stay orthonormal")
	check(near(CAESS.CARESS_OVAL_ACROSS, 1.30) and near(CAESS.CARESS_OVAL_UP, 0.70),
		"caress path is an oval")
	check(near(CAESS.CARESS_UP_BIAS_M, 0.05), "caress rub lifted 5 cm above the mark")
	check(near(CAESS.caress_phase_step(0.5, true, 0.25),
		CAESS.CARESS_SPEED_RAD_S * 0.25 + 0.5), "caress phase advances while moving")
	check(near(CAESS.caress_phase_step(0.5, false, 0.25), 0.5),
		"caress phase holds while movement is off")
	check(near(CAESS.CAESS_TOUCH_SECONDS, 5.0), "a caress action is five seconds of contact")
	var short := CAESS.caress_touch_step(0.0, true, 4.9)
	check(near(float(short[0]), 4.9) and int(short[1]) == 0, "a short caress scores nothing")
	var full := CAESS.caress_touch_step(float(short[0]), true, 0.1)
	check(near(float(full[0]), 0.0) and int(full[1]) == 1, "five seconds of caress score once")
	var long := CAESS.caress_touch_step(1.0, true, 10.0)
	check(int(long[1]) == 2 and near(float(long[0]), 1.0), "ten more seconds score twice")
	var stopped := CAESS.caress_touch_step(3.0, false, 2.0)
	check(near(float(stopped[0]), 0.0) and int(stopped[1]) == 0,
		"a stopped caress keeps no partial credit")
	check(near(CAESS.PALM_ON_COAT_CLEARANCE_M, 0.04), "palm sits 4 cm above the coat at 1.0 scale")
	check(near(CAESS.palm_clearance_for(0.66), 0.0264), "Canon palm clearance scales down")
	check(near(CAESS.palm_clearance_for(1.10), 0.044), "Hoers palm clearance scales up")
	check(near(CAESS.palm_clearance_for(1.0, 0.07), 0.07),
		"caress palm distance overrides the default")
	check(CAESS._region_ignored("tail", ["tail"]), "caress ignores the tail hull")
	check(not CAESS._region_ignored("flank", ["tail"]), "caress keeps the flank hull")
	check(near(CAESS.PALM_NORMAL_MAX_DEG_S, 120.0), "palm normal turns at a bounded rate")
	var capped: Vector3 = CAESS.rotate_normal_toward(Vector3.UP, Vector3.RIGHT, deg_to_rad(10.0))
	check(near(rad_to_deg(capped.angle_to(Vector3.UP)), 10.0), "normal rate caps a large turn")
	check(CAESS.rotate_normal_toward(Vector3.UP, Vector3.RIGHT, PI).is_equal_approx(Vector3.RIGHT),
		"normal rate reaches the target")
	var canon_caress: Dictionary = CAESS.caress_profile_for("canon")
	var mounting_caress: Dictionary = CAESS.caress_profile_for("mounting")
	check(float(canon_caress["up"]) < float(mounting_caress["up"]), "Canon caress sits lower")
	check(near(float(mounting_caress["out"]) * 2.0, 0.04), "JRHNBR caress points 4 cm wider")
	check(CAESS.caress_profile_for("") == CAESS.caress_profile_for("mounting"),
		"unknown size falls back to JRHNBR caress")
	check(near(CAESS.MISSIONARY_CARESS_TRAVEL_M, 0.12), "missionary caress travel")
	check(near(CAESS.MISSIONARY_CARESS_LIFT_M, 0.18),
		"missionary caress starts at the barrel radius")
	check(near(CAESS.MISSIONARY_CARESS_PALM_ROLL_DEG, 30.0),
		"missionary caress rolls the palm 30 degrees")
	check(near(CAESS.missionary_palm_roll_deg("right"), 30.0),
		"the right palm rolls counter-clockwise")
	check(near(CAESS.missionary_palm_roll_deg("left"), -30.0),
		"the left palm rolls clockwise")
	check(CAESS._region_allowed("head_Ears1", ["head"]),
		"the cheek path accepts a head hull")
	check(not CAESS._region_allowed("neck", ["head"]),
		"the cheek filter does not take a neck hull")
	check(CAESS._region_allowed("back", CAESS.MISSIONARY_TORSO_REGIONS),
		"the missionary caress accepts a barrel hull")
	check(not CAESS._region_allowed("leg", CAESS.MISSIONARY_TORSO_REGIONS),
		"the missionary caress ignores a leg hull")
	check(not CAESS._region_allowed("head_Ears1", CAESS.MISSIONARY_TORSO_REGIONS),
		"the missionary caress ignores a head hull")
	check(CAESS._region_allowed("anything", []), "an empty region filter allows every hull")
	check(CAESS.caress_single_hand_toggle("", "L") == "L",
		"A starts the left hand when nothing is caressing")
	check(CAESS.caress_single_hand_toggle("L", "R") == "R",
		"D swaps the caress to the right hand")
	check(CAESS.caress_single_hand_toggle("R", "R") == "",
		"pressing the active hand stops the caress")
	check(CAESS.caress_single_hand_toggle("L", "") == "L",
		"no press keeps the active hand")
	var hand_offset := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.07))
	var palm_frame := Transform3D(Basis.IDENTITY, Vector3(1.0, 2.0, 3.0))
	var bone_frame: Transform3D = MISSIONARY_ANON.palm_to_bone(palm_frame, hand_offset)
	check(bone_frame.origin.is_equal_approx(Vector3(1.0, 2.0, 3.07)),
		"the palm frame sits 7 cm ahead of the wrist bone")
	check(MISSIONARY_ANON.bone_to_palm(bone_frame, hand_offset).is_equal_approx(palm_frame),
		"the palm and wrist conversions round trip")
	var rest_basis := Basis(Vector3.UP, 0.4)
	var rest_bone: Transform3D = MISSIONARY_ANON.palm_to_bone(
		palm_frame, hand_offset, rest_basis)
	check(rest_bone.basis.is_equal_approx(
		(palm_frame.basis * hand_offset.basis * rest_basis).orthonormalized()),
		"the regular arm mode composes the hand rest basis")
	check(MISSIONARY_ANON.bone_to_palm(rest_bone, hand_offset, rest_basis) \
		.is_equal_approx(palm_frame), "the rest-basis conversion round trips")
	var scaled_frame := Transform3D(
		Basis.IDENTITY.scaled(Vector3(1.35, 1.35, 1.35)), Vector3.ZERO)
	var blended: Transform3D = MISSIONARY_ANON._blend_frame(
		scaled_frame, Transform3D(Basis.IDENTITY, Vector3.ONE), 0.5)
	check(blended.is_finite() and near(blended.basis.get_scale().x, 1.0, 0.001),
		"the caress blend orthonormalizes scaled world bases")
	check(near(WING.WING_STANDING_HOLD, 0.65), "standing wings start at 60 degrees")
	check(near(KISS.STANDING_KISS_LEAN, 0.90), "standing F kiss needs a full shoulder lean")
	check(KISS.standing_kiss_wanted(true, 1.0), "F kisses at a full shoulder lean")
	check(not KISS.standing_kiss_wanted(true, 0.8), "F does not kiss at a partial lean")

	check(near(RUNTIME.JIGGLE_RUMP_SCALE, 2.8), "thrust jiggle scale")
	check(near(RUNTIME.CAM_SURGE_M, 0.06), "camera surge amplitude")
	check(near(RUNTIME.CAM_BOB_M, 0.02), "camera bob amplitude")
	check(near(KISS.KISS_LEAN_M, 0.27) and near(KISS.KISS_LEAN_SIDE_M, 0.18)
		and near(KISS.KISS_LEAN_DROP_M, 0.035), "kiss leans in, sideways and slightly lower")
	check(near(KISS.KISS_CAMERA_YAW_DEG, 10.0), "kiss camera turns 10 degrees toward her")
	check(near(KISS.KISS_PONY_SIDE_SIGN, 1.0), "pony kiss side matches the input side sign")
	check(near(KISS.kiss_pony_side(-1.0), -1.0), "left lean gives her the opposite head tilt")
	check(near(KISS.kiss_pony_side(1.0), 1.0), "right lean gives her the opposite head tilt")
	check(near(KISS.kiss_pony_side(0.0), 0.0), "centered kiss leaves the side to her")
	check(near(KISS.kiss_lateral_offset(-1.0, -1.0, 0.0), -0.18),
		"kiss starts at the lean lateral offset")
	check(near(KISS.kiss_lateral_offset(-0.5, -1.0, 1.0), -0.18),
		"full kiss uses one lateral offset")
	check(near(KISS.kiss_lateral_offset(-0.5, -1.0, 0.5), -0.135),
		"kiss lateral crossfades instead of stacking")

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

	check(near(MOTION.glance_back_fade_for(1.0), MOTION.GLANCE_BACK_FADE),
		"default glance-back fade")
	check(near(MOTION.glance_back_fade_for(2.0), MOTION.GLANCE_BACK_FADE * 0.5),
		"faster glance-back speed shortens the fade")
	check(near(MOTION.glance_back_fade_for(0.1), MOTION.GLANCE_BACK_FADE / 0.25),
		"glance-back speed clamps slow")
	check(near(MOTION.glance_back_fade_for(9.0), MOTION.GLANCE_BACK_FADE / 3.0),
		"glance-back speed clamps fast")

	var phase := MOTION.hip_phase_step(0.0, 1.0, 1.0 / 60.0)
	check(phase > 0.0 and phase < 1.0, "hip phase eases toward the mouse depth")
	for _step: int in 120:
		phase = MOTION.hip_phase_step(phase, 1.0, 1.0 / 60.0)
	check(near(phase, 1.0, 0.01), "hip phase settles at full depth")
	check(near(MOTION.hip_phase_step(0.0, -10.0, 1.0 / 60.0), 0.0),
		"hip phase clamps depth to zero")

	var live_runtime: Node = RUNTIME.new()
	live_runtime.state = 2 # ACTIVE
	live_runtime.pose_id = CATALOG.STANDING
	live_runtime.call("apply_live_settings")
	check(live_runtime._features.has("hud_readouts"), "live settings refresh feature flags")
	check(live_runtime._camera_surge >= 0.0 and live_runtime._camera_surge <= 1.0,
		"live settings refresh camera thrust")
	live_runtime.free()

	var jiggle_runtime: Node = RUNTIME.new()
	var jiggle_pony := Node3D.new()
	root.add_child(jiggle_pony)
	var fake_tail := FakeTail.new()
	root.add_child(fake_tail)
	jiggle_runtime.pony = jiggle_pony
	jiggle_runtime.pose_id = CATALOG.STANDING
	jiggle_runtime._tail = fake_tail
	root.add_child(jiggle_runtime)
	jiggle_runtime.call("_on_smack_impact", 0.8)
	var expected_jiggle := float(jiggle_runtime.call("_jiggle_size_scale")) \
		* float(jiggle_runtime._jiggle_smack_intensity)
	check(near(fake_tail.last_strength, expected_jiggle),
		"smack carries the tail jiggle in standing")
	root.remove_child(jiggle_runtime)
	jiggle_runtime.free()
	fake_tail.free()
	jiggle_pony.free()

	var mark_flank := FakeFlank.new()
	mark_flank.name = "FlankTouch"
	var mark_a := Decal.new()
	var mark_b := Decal.new()
	mark_a.visible = true
	mark_b.visible = true
	mark_flank.marks = [mark_a, mark_b]
	mark_flank.ages = [0.0, 0.0]
	var mark_runtime: Node = RUNTIME.new()
	var mark_pony := Node3D.new()
	root.add_child(mark_pony)
	mark_pony.add_child(mark_flank)
	mark_runtime.pony = mark_pony
	root.add_child(mark_runtime)
	mark_runtime.call("_clear_stock_flank_marks")
	check(not mark_a.visible and not mark_b.visible,
		"act start hides stock flank marks")
	check(near(float(mark_flank.ages[0]), 1000.0)
		and near(float(mark_flank.ages[1]), 1000.0),
		"act start ages the stock flank marks")
	root.remove_child(mark_runtime)
	mark_runtime.free()
	mark_a.free()
	mark_b.free()
	mark_pony.free()

	var radius_flank := FakeFlank.new()
	root.add_child(radius_flank)
	var radius_mat := ShaderMaterial.new()
	var radius_mesh := Node3D.new()
	root.add_child(radius_mesh)
	radius_flank._jiggle_targets = [[radius_mat, radius_mesh]]
	var radius_runtime: Node = RUNTIME.new()
	radius_runtime._flank = radius_flank
	radius_runtime._jiggle_radius_m = 0.30
	root.add_child(radius_runtime)
	radius_runtime.call("_apply_jiggle_radius")
	check(near(float(radius_mat.get_shader_parameter("jiggle_radius")), 0.30),
		"jiggle radius applies to the targets")
	radius_runtime._jiggle_radius_m = -0.05
	radius_runtime.call("_apply_jiggle_radius")
	check(near(float(radius_mat.get_shader_parameter("jiggle_radius")), -0.05),
		"jiggle radius is applied unclamped")
	radius_runtime.call("_restore_jiggle_radius")
	check(radius_mat.get_shader_parameter("jiggle_radius") == null,
		"jiggle radius override restores")
	root.remove_child(radius_runtime)
	radius_runtime.free()
	radius_mesh.free()
	radius_flank.free()

	check(near(STANDING_ANON.hip_offset(0.0, 1.0, 2.0), -0.045),
		"hip rests one reach behind the rump limit")
	check(near(STANDING_ANON.hip_offset(1.0, 1.0, 2.0), 0.045),
		"hip reaches the rump limit at full depth")
	check(near(STANDING_ANON.hip_offset(0.5, 1.0, 2.0), 0.0),
		"half depth returns to the base hip target")
	check(near(STANDING_ANON.hip_offset(1.0, 0.66, 2.0), 0.045 * 0.66),
		"hip reach scales with pony size")

	var hip_runtime: Node = RUNTIME.new()
	hip_runtime.pose_id = CATALOG.STANDING
	hip_runtime._thrust_travel = 2.0
	var hip_pony := Node3D.new()
	root.add_child(hip_pony)
	var hip_modifier = HIP_THRUST.new()
	root.add_child(hip_modifier)
	var stand := STANDING_ANON.new(hip_runtime)
	stand.set("pony", hip_pony)
	stand.set("_hip_thrust", hip_modifier)
	stand.set("_hip_phase", 0.0)
	stand.call("apply_anon_thrust", Node3D.new(), Basis.IDENTITY)
	var hip_offset: Vector3 = hip_modifier.get("offset_world")
	check(near(hip_offset.length(), 0.045) and hip_offset.z > 0.0,
		"depth 0 sets the hips back from the rump limit")
	stand.set("_hip_phase", 1.0)
	stand.call("apply_anon_thrust", Node3D.new(), Basis.IDENTITY)
	hip_offset = hip_modifier.get("offset_world")
	check(near(hip_offset.length(), 0.045) and hip_offset.z < 0.0,
		"depth 1 moves the hips onto the rump limit")
	hip_runtime.free()
	hip_modifier.free()
	hip_pony.free()

	var modifier_skeleton := Skeleton3D.new()
	root.add_child(modifier_skeleton)
	modifier_skeleton.add_bone("Hips")
	modifier_skeleton.add_bone("Spine")
	modifier_skeleton.add_bone("LeftUpperLeg")
	modifier_skeleton.add_bone("RightUpperLeg")
	modifier_skeleton.add_bone("LeftLowerLeg")
	modifier_skeleton.add_bone("RightLowerLeg")
	modifier_skeleton.set_bone_parent(1, 0)
	modifier_skeleton.set_bone_parent(2, 0)
	modifier_skeleton.set_bone_parent(3, 0)
	modifier_skeleton.set_bone_parent(4, 2)
	modifier_skeleton.set_bone_parent(5, 3)
	modifier_skeleton.set_bone_pose_position(0, Vector3.ZERO)
	modifier_skeleton.set_bone_pose_position(1, Vector3(0.0, 0.2, 0.0))
	modifier_skeleton.set_bone_pose_position(2, Vector3(0.1, -0.1, 0.0))
	modifier_skeleton.set_bone_pose_position(3, Vector3(-0.1, -0.1, 0.0))
	modifier_skeleton.set_bone_pose_position(4, Vector3(0.1, -0.3, 0.0))
	modifier_skeleton.set_bone_pose_position(5, Vector3(-0.1, -0.3, 0.0))
	var hips_before := modifier_skeleton.get_bone_global_pose(0).origin
	var spine_before := modifier_skeleton.get_bone_global_pose(1).origin
	var left_before := modifier_skeleton.get_bone_global_pose(2).origin
	var right_before := modifier_skeleton.get_bone_global_pose(3).origin
	var left_shin_before := modifier_skeleton.get_bone_global_pose(4).origin
	var right_shin_before := modifier_skeleton.get_bone_global_pose(5).origin
	var modifier = HIP_THRUST.new()
	modifier_skeleton.add_child(modifier)
	modifier.set("offset_world", Vector3(0.0, 0.0, 0.1))
	modifier.call("_process_modification_with_delta", 0.0)
	check(modifier_skeleton.get_bone_global_pose(0).origin.is_equal_approx(
		hips_before + Vector3(0.0, 0.0, 0.1)), "hip modifier moves the hips")
	check(modifier_skeleton.get_bone_global_pose(1).origin.is_equal_approx(
		spine_before + Vector3(0.0, 0.0, 0.1) * 0.55),
		"hip modifier grades the spine with the pelvis")
	check(modifier_skeleton.get_bone_global_pose(2).origin.is_equal_approx(
		left_before + Vector3(0.0, 0.0, 0.1) * 0.35),
		"hip modifier grades the thighs with the pelvis")
	check(modifier_skeleton.get_bone_global_pose(3).origin.is_equal_approx(
		right_before + Vector3(0.0, 0.0, 0.1) * 0.35),
		"hip modifier grades the right thigh with the pelvis")
	check(modifier_skeleton.get_bone_global_pose(4).origin.is_equal_approx(left_shin_before),
		"hip modifier keeps the left shin planted")
	check(modifier_skeleton.get_bone_global_pose(5).origin.is_equal_approx(right_shin_before),
		"hip modifier keeps the right shin planted")
	modifier_skeleton.free()

	var smack_flank := FakeFlank.new()
	root.add_child(smack_flank)
	var smack_mat := ShaderMaterial.new()
	var smack_mesh := Node3D.new()
	smack_flank._jiggle_targets = [[smack_mat, smack_mesh]]
	smack_flank._jiggle_amount = 0.08
	var smack_runtime: Node = RUNTIME.new()
	var smack_pony := Node3D.new()
	root.add_child(smack_pony)
	smack_runtime.pony = smack_pony
	smack_runtime._flank = smack_flank
	smack_runtime._jiggle_smack_intensity = 0.5
	root.add_child(smack_runtime)
	smack_runtime.call("_on_smack_impact", 0.8)
	check(near(float(smack_flank._jiggle_amount), 0.04),
		"smack jiggle intensity scales the amount")
	root.remove_child(smack_runtime)
	smack_runtime.free()
	smack_mesh.free()
	smack_flank.free()
	smack_pony.free()

	var hair := Skeleton3D.new()
	root.add_child(hair)
	var hair_names := ["mPelvis", "mChest", "mNeck", "mHead",
		"mTail1", "mTail2", "mTail3", "mTail4", "mTail5", "mTail6"]
	for name: String in hair_names:
		hair.add_bone(name)
	hair.set_bone_parent(1, 0)
	hair.set_bone_parent(2, 1)
	hair.set_bone_parent(3, 2)
	hair.set_bone_parent(4, 0)
	for i: int in range(5, hair_names.size()):
		hair.set_bone_parent(i, i - 1)
	hair.set_bone_pose_position(0, Vector3.ZERO)
	hair.set_bone_pose_position(1, Vector3(0.0, 0.2, 0.0))
	hair.set_bone_pose_position(2, Vector3(0.0, 0.1, 0.0))
	hair.set_bone_pose_position(3, Vector3(0.0, 0.1, 0.0))
	hair.set_bone_pose_position(4, Vector3(0.0, 0.0, -0.1))
	for i: int in range(5, hair_names.size()):
		hair.set_bone_pose_position(i, Vector3(0.0, 0.0, -0.05))
	var tail_mare := Node3D.new()
	root.add_child(tail_mare)
	var tail_runtime: Node = RUNTIME.new()
	tail_runtime.depth = 0.0
	root.add_child(tail_runtime)
	var tail := TAIL.new()
	tail.mare = tail_mare
	tail.runtime = tail_runtime
	tail.amount = 1.0
	tail.target_amount = 1.0
	hair.add_child(tail)
	tail.call("_cache")
	var pelvis_before := hair.get_bone_global_pose(0).origin
	var chest_before := hair.get_bone_global_pose(1).origin
	var neck_before := hair.get_bone_global_pose(2).origin
	var head_before := hair.get_bone_global_pose(3).origin
	tail.set("_thrust_strength", 1.0)
	tail.set("_thrust_clock", 0.0)
	tail.call("_process_modification_with_delta", 0.05)
	check(not hair.get_bone_global_pose(0).origin.is_equal_approx(pelvis_before),
		"tail base pelvis moves with the jiggle")
	check(hair.get_bone_global_pose(1).origin.is_equal_approx(chest_before)
		and hair.get_bone_global_pose(2).origin.is_equal_approx(neck_before)
		and hair.get_bone_global_pose(3).origin.is_equal_approx(head_before),
		"tail jiggle keeps the mane planted")


	hair.free()
	tail_mare.free()
	tail_runtime.free()

	var plant_body := FakeBody.new()
	root.add_child(plant_body)
	var plant_left := Node3D.new()
	var plant_right := Node3D.new()
	plant_body.add_child(plant_left)
	plant_body.add_child(plant_right)
	plant_body._left_foot = plant_left
	plant_body._right_foot = plant_right
	plant_left.global_position = Vector3(0.2, 0.0, 0.0)
	plant_right.global_position = Vector3(-0.2, 0.0, 0.0)
	# The real HipsTarget is parented to the skeleton, not to AnonBody; the body owns the feet.
	var plant_skeleton := Node3D.new()
	plant_body.add_child(plant_skeleton)
	var plant_hip := Node3D.new()
	plant_skeleton.add_child(plant_hip)
	var plant_runtime: Node = RUNTIME.new()
	plant_runtime.pose_id = CATALOG.STANDING
	plant_runtime._free_camera_active = true
	plant_runtime._features = {"standing_plant_feet": true}
	plant_runtime.pony = Node3D.new()
	root.add_child(plant_runtime)
	var plant_anon := STANDING_ANON.new(plant_runtime)
	plant_anon.set("pony", plant_runtime.pony)
	plant_anon.call("apply_anon_lean", plant_hip, Basis.IDENTITY)
	var planted_left := plant_left.global_position
	var planted_right := plant_right.global_position
	var stance := SETTINGS.plant_spread_m.get_num() * 0.5
	# `Hip drop` lowers the pinned pelvis, and it is on by default.
	var plant_drop := Vector3.DOWN * SETTINGS.hip_drop_m.get_num()
	check(planted_left.is_equal_approx(Vector3(0.2 + stance, 0.0, 0.15)),
		"planted left foot sits 15 cm behind and half a stance out")
	check(planted_right.is_equal_approx(Vector3(-0.2 - stance, 0.0, 0.15)),
		"planted right foot sits 15 cm behind and half a stance out")
	plant_left.global_position = Vector3(5.0, 0.0, 0.0)
	plant_right.global_position = Vector3(-5.0, 0.0, 0.0)
	plant_hip.global_position = Vector3(7.0, 7.0, 7.0)
	plant_anon.call("apply_anon_lean", plant_hip, Basis.IDENTITY)
	check(plant_left.global_position.is_equal_approx(planted_left),
		"planted left foot holds its act-start point")
	check(plant_right.global_position.is_equal_approx(planted_right),
		"planted right foot holds its act-start point")
	check(plant_hip.global_position.is_equal_approx(plant_drop),
		"planted hips hold their act-start point")
	# A forward lean must not move the pinned lower body; the head/camera is what travels.
	plant_runtime._lean_view_forward = 1.0
	plant_left.global_position = Vector3(5.0, 0.0, 0.0)
	plant_right.global_position = Vector3(-5.0, 0.0, 0.0)
	plant_hip.global_position = Vector3(7.0, 7.0, 7.0)
	plant_anon.call("apply_anon_lean", plant_hip, Basis.IDENTITY)
	check(plant_hip.global_position.is_equal_approx(plant_drop),
		"a forward lean keeps the planted hips at the act-start point")
	check(plant_left.global_position.is_equal_approx(planted_left)
		and plant_right.global_position.is_equal_approx(planted_right),
		"a forward lean keeps the planted feet")
	plant_runtime.set("_standing_sway_offset", Vector3(0.02, 0.0, 0.0))
	plant_left.global_position = Vector3(5.0, 0.0, 0.0)
	plant_right.global_position = Vector3(-5.0, 0.0, 0.0)
	plant_hip.global_position = Vector3(7.0, 7.0, 7.0)
	plant_anon.call("apply_anon_lean", plant_hip, Basis.IDENTITY)
	check(plant_hip.global_position.is_equal_approx(Vector3(0.02, 0.0, 0.0) + plant_drop),
		"the body sway moves the pinned hip with her")
	check(plant_left.global_position.is_equal_approx(planted_left)
		and plant_right.global_position.is_equal_approx(planted_right),
		"the body sway leaves the planted feet")
	plant_runtime.set("_standing_sway_offset", Vector3.ZERO)
	plant_runtime._lean_view_forward = 0.0
	plant_runtime._features = {"standing_plant_feet": false}
	plant_left.global_position = Vector3(5.0, 0.0, 0.0)
	plant_right.global_position = Vector3(-5.0, 0.0, 0.0)
	plant_hip.global_position = Vector3.ZERO
	plant_anon.call("apply_anon_lean", plant_hip, Basis.IDENTITY)
	check(plant_left.global_position.is_equal_approx(Vector3(5.0, 0.0, 0.0)),
		"plant flag off releases the feet")
	plant_runtime._lean_view_forward = 1.0
	plant_anon.call("apply_anon_lean", plant_hip, Basis.IDENTITY)
	check(not plant_hip.global_position.is_zero_approx(),
		"plant flag off lets the forward lean move the pelvis")
	plant_runtime.free()
	plant_hip.free()
	plant_skeleton.free()
	plant_left.free()
	plant_right.free()
	plant_body.free()

	var gate_runtime: Node = RUNTIME.new()
	check(not gate_runtime.can_start(CATALOG.MISSIONARY, "bed_side"), "missing pony blocks start")
	check(not gate_runtime.can_offer(CATALOG.STANDING, ""), "missing pony blocks offer")
	check(gate_runtime._start_reasons(CATALOG.MISSIONARY, "bed_side") == PackedStringArray(["invalid_pony"]),
		"gate report keeps the invalid-pony reason")
	gate_runtime.free()

	check(near(MOTION.HOLD_SWAY_FORWARD, 0.010), "idle camera sway amplitude")
	check(near(STANDING_CAMERA.MOUNTING_STANDING_CAMERA_LIFT_M, 0.10), "JRHNBR standing camera raised 10 cm")
	check(near(MOTION.LEAN_SIDE_M, 0.18), "side lean travel")
	check(near(MOTION.LEAN_SIDE_ROLL_DEG, 8.0), "side lean roll stronger")
	check(near(MOTION.LEAN_FIRE, 0.75) and near(MOTION.LEAN_RELEASE, 0.60),
		"lean threshold uses 75/60 hysteresis")

	check(near(MOTION.lean_step(0.0, 1.0, 0.25), 0.5), "lean ramps in over half a second")
	check(near(MOTION.lean_step(1.0, 0.0, 0.8), 1.0),
		"released lean holds its position")
	check(near(MOTION.lean_step(1.0, 0.0, 0.8, true), 0.5),
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
	check(str(runtime._lean_action_kind) == "",
		"missionary Q fires no action; the kiss is F at a full forward lean")
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

	_check_body_coat_jiggle_target()
	_check_tail_tuning()
	_check_perf_probe()
	_check_missionary_hand_hold()

	print("ACTIONS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACTIONS_PASS")
	quit(0 if failures == 0 else 1)
