extends "res://mods/unfplap/tests/support/suite.gd"
## Pure act-action checks: lean mapping, threshold hysteresis, pose support, smack side.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/hands/test_actions.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const POSES := preload("res://mods/unfplap/poses/api.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const REACTIONS := preload("res://mods/unfplap/reactions/api.gd")
const ACT_CAMERA := preload("res://mods/unfplap/camera/api.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const PALM_SCALE := preload("res://mods/unfplap/shared/hands_scale.gd")
const WING := preload("res://mods/unfplap/poses/wing_control.gd")
const MOTION := preload("res://mods/unfplap/shared/act_motion.gd")
const HANDS := preload("res://mods/unfplap/hands/api.gd")
const MODEL := preload("res://mods/unfplap/hands/model.gd")
const CONTROLLER := preload("res://mods/unfplap/hands/controller.gd")
const SMACK_TARGET := preload("res://mods/unfplap/hands/smack_target.gd")
const PLACEMENT := preload("res://mods/unfplap/hands/placement.gd")
const SMACK := preload("res://mods/unfplap/hands/smack.gd")
const COAT := preload("res://mods/unfplap/hands/contact.gd")
const HAND := preload("res://mods/unfplap/hands/palm.gd")
const FLANK := preload("res://mods/unfplap/hands/paths/standing.gd")
const MISSIONARY_PATH := preload("res://mods/unfplap/hands/paths/missionary.gd")
const CAMERA_VIEW := preload("res://mods/unfplap/camera/view.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const STANDING_ANON := preload("res://mods/unfplap/poses/standing_anon.gd")
const HIP_THRUST := preload("res://mods/unfplap/poses/anon_hip_thrust.gd")
const MISSIONARY_ANON := preload("res://mods/unfplap/poses/missionary_anon.gd")
const TAIL := preload("res://mods/unfplap/poses/tail_pose.gd")

## The tail handle's host: records the thrust the facade sends.
class FakeTailHost extends RefCounted:
	var last_strength := 0.0

	func thrust(weight: float) -> void:
		last_strength = weight


class FakeFlank extends Node3D:
	var marks: Array = []
	var ages: Array = []
	var _jiggle_targets: Array = []
	var _jiggle_amount := 0.0


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


## The runtime fixture: constructed and parented under the suite root; the caller frees it.
func _runtime() -> Node:
	var runtime: Node = RUNTIME.new()
	root.add_child(runtime)
	return runtime


func _check_tail_tuning() -> void:
	var tail_runtime: Node = _runtime()
	var tail_pony := Node3D.new()
	root.add_child(tail_pony)
	tail_runtime.set("pony", tail_pony)
	tail_runtime.act.context.facts.pony = tail_pony
	tail_runtime.act.pony_id = "twilight_sparkle"
	tail_runtime.act.pose_id = CATALOG.STANDING
	tail_runtime.act.context.pose._view.settings_group = CATALOG.STANDING
	var pose: Variant = tail_runtime.act.context.pose
	var tuned: Dictionary = pose._config_for_group(CATALOG.STANDING,
		{"tail": {"yaw_deg": 40.0, "pitch_deg": 10.0}})
	check(near(float(tuned.get("tail_aside", 0.0)), deg_to_rad(40.0)),
		"tail yaw tunable reaches the pose")
	check(near(float(tuned.get("tail_lift", 0.0)), deg_to_rad(10.0)),
		"tail pitch tunable reaches the pose")
	var cfg: Dictionary = pose._config_for_group(CATALOG.STANDING, {})
	check(near(float(cfg.get("tail_aside", 0.0)), deg_to_rad(35.0)), "tail yaw default")
	check(near(float(cfg.get("tail_lift", 0.0)), deg_to_rad(25.0)), "tail pitch default")
	tail_pony.free()
	tail_runtime.free()


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
	COAT.sync_touch(caress_pony)
	check(touch.syncs == 1, "the caress refreshes the touch hulls from the act skeleton")
	caress_pony.free()
	touch.free()
	sk.free()
	anon.free()


## The act snapshot the facade takes: the block plus the family, size and climax length.
func tune(block := {}, family := "", size := 1.0, climax := 5.0) -> RefCounted:
	var context := REACTIONS.CONTEXT.new()
	context.fill(jiggle_block(block), family, size, climax)
	return context


## The complete `jiggle.*` block the runtime snapshot passes; overrides replace keys.
func jiggle_block(overrides := {}) -> Dictionary:
	var block := {
		"radius": float(SETTINGS.radius.default),
		"center_height_m": float(SETTINGS.center_height_m.default),
		"center_back_m": float(SETTINGS.center_back_m.default),
		"intensity": float(SETTINGS.intensity.default),
		"smack_intensity": float(SETTINGS.smack_intensity.default),
	}
	block.merge(overrides, true)
	return block


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

	check(SMACK_TARGET.side_from_lean(0.4) == MODEL.Side.LEFT,
		"right lean smacks left cheek")
	check(SMACK_TARGET.side_from_lean(-0.4) == MODEL.Side.RIGHT,
		"left lean smacks right cheek")
	check(SMACK_TARGET.side_from_lean(0.0) == MODEL.Side.NONE, "centered smack is random")
	check(SMACK_TARGET.choose_hand(true, false, 0.0) == MODEL.Side.RIGHT,
		"the free hand smacks while the left hand caresses")
	check(SMACK_TARGET.choose_hand(false, true, 0.0) == MODEL.Side.LEFT,
		"the free hand smacks while the right hand caresses")
	check(SMACK_TARGET.choose_hand(true, true, 0.1) == MODEL.Side.LEFT
		and SMACK_TARGET.choose_hand(true, true, 0.9) == MODEL.Side.RIGHT,
		"both hands busy picks one hand at random")
	check(SMACK_TARGET.choose_hand(false, false, 0.0) == MODEL.Side.NONE,
		"no busy hand leaves the choice to the lean")
	var up_offset: Vector3 = SMACK_TARGET.query_offset(0.05, 0.02, 1.0,
		Vector3.UP, Vector3.BACK)
	check(near(up_offset.y, 0.05) and near(up_offset.z, 0.02),
		"smack height and hind offsets use signed up and back")
	var down_offset: Vector3 = SMACK_TARGET.query_offset(-0.03, 0.10, 2.0,
		Vector3.UP, Vector3.BACK)
	check(near(down_offset.y, -0.06) and near(down_offset.z, 0.20),
		"smack query offset scales with the pony")
	var height_presentation := MODEL.SmackPresentation.from_dict({"height_m": 0.12})
	check(near(height_presentation.height_m, 0.12),
		"smack height reads the presentation setting")
	check(near(MODEL.SmackPresentation.new().height_m, -0.03),
		"smack height falls back to 3 cm below the mark")
	var smack_contact := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))
	var smack_raised: Transform3D = SMACK.raise_frame(
		smack_contact, Vector3.RIGHT, 0.18, 0.05, Vector3.BACK, 15.0)
	check(near(smack_raised.origin.x, 0.18) and near(smack_raised.origin.z, 0.05)
		and near(smack_raised.origin.y, 1.0), "smack raise lifts along the normal and back")
	check((-smack_raised.basis.z).y < (-smack_contact.basis.z).y,
		"raised palm pitches the fingers down")
	var smack_lowered: Transform3D = SMACK.raise_frame(
		smack_contact, Vector3.RIGHT, -0.10, -0.04, Vector3.BACK, 15.0)
	check(near(smack_lowered.origin.x, -0.10) and near(smack_lowered.origin.z, -0.04),
		"smack raise and arc are applied unclamped")
	var straight_palm: Basis = HAND.palm_basis("right", Vector3.RIGHT, Vector3.FORWARD)
	var pitched_palm: Basis = SMACK.pitch_basis(straight_palm, 15.0)
	check(pitched_palm.determinant() > 0.99, "palm pitch stays orthonormal")
	check(pitched_palm.x.dot(straight_palm.x) > 0.999, "palm pitch keeps the palm normal")
	check((-pitched_palm.z).y < (-straight_palm.z).y, "positive pitch lowers the fingers")
	var pitched_up: Basis = SMACK.pitch_basis(straight_palm, -15.0)
	check((-pitched_up.z).y > (-straight_palm.z).y, "negative pitch raises the fingers")
	var smack_left_palm: Basis = HAND.palm_basis("left", Vector3.RIGHT, Vector3.FORWARD)
	var smack_left_pitched: Basis = SMACK.pitch_basis(smack_left_palm, 15.0)
	check((-smack_left_pitched.z).y < (-smack_left_palm.z).y,
		"left palm also pitches down")
	check(smack_left_pitched.x.dot(smack_left_palm.x) > 0.999,
		"left palm pitch keeps the palm normal")
	check(SMACK.pitch_basis(straight_palm, 0.0).is_equal_approx(straight_palm),
		"zero palm pitch keeps the basis")
	check(SMACK_TARGET.finger_hint(false, Vector3.FORWARD).is_equal_approx(Vector3.DOWN),
		"non-caress smack points the fingers down")
	check(SMACK_TARGET.finger_hint(true, Vector3.FORWARD).is_equal_approx(Vector3.FORWARD),
		"caress smack keeps the fingers forward")
	var swing_contact := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))
	var swing := SMACK.swing_raise_frame(
		swing_contact, Vector3.RIGHT, Vector3.BACK, 0.20, 15.0)
	check(swing.origin.z > swing_contact.origin.z, "non-caress swing starts behind")
	check(swing.origin.y < swing_contact.origin.y, "non-caress swing starts below")
	check(swing.origin.x > swing_contact.origin.x, "non-caress swing clears outward")
	check((-swing.basis.z).y < (-swing_contact.basis.z).y,
		"non-caress swing points the fingers down")
	var raise_mid: Transform3D = SMACK.raise_blend(
		smack_contact, smack_raised, Vector3.BACK * 0.02, 0.5)
	check(raise_mid.origin.x > smack_contact.origin.x
		and raise_mid.origin.x < smack_raised.origin.x, "smack raise blends between frames")
	check(near(raise_mid.origin.z - smack_contact.origin.z
		- (smack_raised.origin.z - smack_contact.origin.z) * 0.5, 0.02, 0.002),
		"smack raise bows along the arc parameter")
	var no_arc_mid: Transform3D = SMACK.raise_blend(
		smack_contact, smack_raised, Vector3.ZERO, 0.5)
	check(near(no_arc_mid.origin.z - smack_contact.origin.z,
		(smack_raised.origin.z - smack_contact.origin.z) * 0.5, 0.002),
		"zero arc is a straight blend")
	var strike_mid: Transform3D = SMACK.strike_blend(smack_raised, smack_contact, 0.5)
	check(strike_mid.origin.distance_to(smack_raised.origin)
		< strike_mid.origin.distance_to(smack_contact.origin), "smack strike accelerates")
	check(SMACK.strike_blend(smack_raised, smack_contact, 1.0).origin.is_equal_approx(
		smack_contact.origin), "smack strike reaches the contact")
	check(SMACK.recover_blend(smack_contact, smack_raised, 1.0).origin.is_equal_approx(
		smack_raised.origin), "smack recovery reaches its target")
	check(near(SMACK.SMACK_RAISE_SPEED_M_S, 2.0)
		and near(SMACK.SMACK_RETURN_SPEED_M_S, 6.0), "smack default speeds")
	check(near(SMACK.SMACK_CONTACT_HOLD_SECONDS, 0.03), "smack contact hold")
	var quad_faces := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0),
		Vector3(0, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
	])
	var quad_normals := PackedVector3Array([
		Vector3.BACK, Vector3.BACK, Vector3.BACK,
		Vector3.BACK, Vector3.BACK, Vector3.BACK,
	])
	var flank_hit: Variant = SMACK_TARGET.closest_flank_hit(
		quad_faces, quad_normals, Vector3(0.5, 0.5, 1.0))
	check(flank_hit.hit, "a posed flank face is hit")
	check(near(flank_hit.distance, 1.0), "closest flank distance")
	check(flank_hit.point.is_equal_approx(Vector3(0.5, 0.5, 0.0)), "closest flank point")
	check(flank_hit.normal.dot(Vector3.BACK) > 0.99, "closest flank normal")
	var edge_hit: Variant = SMACK_TARGET.closest_flank_hit(
		quad_faces, quad_normals, Vector3(-1.0, 0.5, 0.0))
	check(edge_hit.point.is_equal_approx(Vector3(0.0, 0.5, 0.0)),
		"closest flank clamps outside the patch")
	check(not SMACK_TARGET.closest_flank_hit(PackedVector3Array(), PackedVector3Array(),
		Vector3.ZERO).hit, "empty flank patch has no hit")
	var reach_controller := CONTROLLER.new(ACT_FACTS.new())
	reach_controller.reach().start(MODEL.Side.RIGHT)
	check(reach_controller.reach().active(), "a held shoulder reach owns its hand")
	reach_controller.reach().cancel(MODEL.Side.RIGHT)
	check(not reach_controller.reach().active()
		and not reach_controller.reach().owns(MODEL.Side.RIGHT),
		"a taken reach hand drops the shoulder hold")

	check(near(MOTION.lean_distance(1.0), 0.24), "forward lean distance")
	check(near(MOTION.lean_distance(-1.0), 0.0), "backward lean has no travel")
	check(near(MOTION.lean_size_scale_for(1.0), 1.0), "JRHNBR lean scale is reference")
	check(near(MOTION.lean_size_scale_for(0.66), 1.34), "Canon lean scale is +34 percent")
	check(near(MOTION.lean_distance(1.0, 1.34), 0.3216), "Canon forward lean scales")

	var hip := Node3D.new()
	root.add_child(hip)
	var lean_facts: RefCounted = ACT_FACTS.new()
	lean_facts.pose_view = _standing_view()
	lean_facts.free_camera_active = true
	lean_facts.lean_view_forward = 1.0
	lean_facts.lean_view_side = 0.0
	lean_facts.shot_lean_forward = 1.0
	lean_facts.depth = 0.0
	var lean_scale := 1.0
	var lean_anon := STANDING_ANON.new(lean_facts)
	lean_anon.call("apply_anon_lean", hip, Basis.IDENTITY)
	check(near(hip.global_position.z, MOTION.lean_distance(1.0, lean_scale)),
		"forward lean keeps the pelvis behind the rump")
	lean_facts.lean_view_forward = 0.0
	lean_facts.shot_lean_forward = 0.0
	lean_facts.standing_sway_offset = Vector3(0.0, 0.0, 0.03)
	var sway_hip := Node3D.new()
	root.add_child(sway_hip)
	lean_anon.call("apply_anon_lean", sway_hip, Basis.IDENTITY)
	check(near(sway_hip.global_position.z, 0.03),
		"her pelvis sway moves Anon's pinned hip")
	lean_facts.standing_sway_offset = Vector3.INF
	var invalid_hip := Node3D.new()
	root.add_child(invalid_hip)
	lean_anon.call("apply_anon_lean", invalid_hip, Basis.IDENTITY)
	check(near(invalid_hip.global_position.z, 0.0),
		"a non-finite pelvis sway is ignored")
	lean_facts.standing_sway_offset = Vector3.ZERO
	var side_hip := Node3D.new()
	root.add_child(side_hip)
	lean_facts.lean_view_forward = 0.0
	lean_facts.lean_view_side = 1.0
	lean_facts.shot_lean_forward = 0.0
	lean_anon.call("apply_anon_lean", side_hip, Basis.IDENTITY)
	check(near(side_hip.global_position.x, -MOTION.LEAN_SIDE_M * lean_scale),
		"side lean keeps the pelvis centred")
	hip.free()
	sway_hip.free()
	invalid_hip.free()
	side_hip.free()

	check(near(MODEL.CARESS_SPEED_RAD_S, 3.6), "caress speed")
	var right_palm: Basis = HAND.palm_basis("right", Vector3.RIGHT, Vector3.FORWARD)
	var left_palm: Basis = HAND.palm_basis("left", Vector3.RIGHT, Vector3.FORWARD)
	check((-right_palm.x).dot(Vector3.LEFT) > 0.99 and (-right_palm.z).dot(Vector3.FORWARD) > 0.99,
		"right palm faces the coat with fingers forward")
	check(left_palm.x.dot(Vector3.LEFT) > 0.99 and (-left_palm.z).dot(Vector3.FORWARD) > 0.99,
		"left palm faces the coat with fingers forward")
	check(right_palm.determinant() > 0.99 and left_palm.determinant() > 0.99,
		"palm surface bases stay orthonormal")
	check(near(FLANK.CARESS_UP_BIAS_M, 0.05), "caress rub lifted 5 cm above the mark")
	check(near(MODEL.caress_phase_step(0.5, true, 0.25),
		MODEL.CARESS_SPEED_RAD_S * 0.25 + 0.5), "caress phase advances while moving")
	check(near(MODEL.caress_phase_step(0.5, false, 0.25), 0.5),
		"caress phase holds while movement is off")
	check(near(MODEL.CARESS_TOUCH_SECONDS, 5.0), "a caress action is five seconds of contact")
	var short: Variant = MODEL.caress_touch_step(0.0, true, 4.9)
	check(near(short.seconds, 4.9) and short.events == 0, "a short caress scores nothing")
	var full: Variant = MODEL.caress_touch_step(short.seconds, true, 0.1)
	check(near(full.seconds, 0.0) and full.events == 1, "five seconds of caress score once")
	var long: Variant = MODEL.caress_touch_step(1.0, true, 10.0)
	check(long.events == 2 and near(long.seconds, 1.0), "ten more seconds score twice")
	var stopped: Variant = MODEL.caress_touch_step(3.0, false, 2.0)
	check(near(stopped.seconds, 0.0) and stopped.events == 0,
		"a stopped caress keeps no partial credit")
	check(near(PLACEMENT.palm_clearance_for(0.66), 0.0132), "Canon palm clearance scales down")
	check(near(PLACEMENT.palm_clearance_for(1.10), 0.022), "Hoers palm clearance scales up")
	check(near(PLACEMENT.palm_clearance_for(1.0, 0.07), 0.07),
		"caress palm distance overrides the default")
	var tail_ignore: Array[String] = ["tail"]
	check(COAT.region_ignored("tail", tail_ignore), "caress ignores the tail hull")
	check(not COAT.region_ignored("flank", tail_ignore), "caress keeps the flank hull")
	check(SETTINGS.normal_deg_s.get_num() > 0.0, "palm normal turns at a bounded rate")
	var capped: Vector3 = HAND.rotate_normal_toward(Vector3.UP, Vector3.RIGHT, deg_to_rad(10.0))
	check(near(rad_to_deg(capped.angle_to(Vector3.UP)), 10.0), "normal rate caps a large turn")
	check(HAND.rotate_normal_toward(Vector3.UP, Vector3.RIGHT, PI).is_equal_approx(Vector3.RIGHT),
		"normal rate reaches the target")
	var canon_caress: Variant = MODEL.caress_profile_for("canon")
	var mounting_caress: Variant = MODEL.caress_profile_for("mounting")
	check(canon_caress.up < mounting_caress.up, "Canon caress sits lower")
	check(near(mounting_caress.out * 2.0, 0.04), "JRHNBR caress points 4 cm wider")
	var fallback_caress: Variant = MODEL.caress_profile_for("")
	check(near(fallback_caress.up, mounting_caress.up)
		and near(fallback_caress.back, mounting_caress.back)
		and near(fallback_caress.out, mounting_caress.out),
		"unknown size falls back to JRHNBR caress")
	check(near(MISSIONARY_PATH.MISSIONARY_CARESS_PALM_ROLL_DEG, 30.0),
		"missionary caress rolls the palm 30 degrees")
	check(near(MISSIONARY_PATH.missionary_palm_roll_deg(MODEL.Side.RIGHT), 30.0),
		"the right palm rolls counter-clockwise")
	check(near(MISSIONARY_PATH.missionary_palm_roll_deg(MODEL.Side.LEFT), -30.0),
		"the left palm rolls clockwise")
	var head_regions: Array[String] = ["head"]
	check(COAT.region_allowed("head_Ears1", head_regions),
		"the cheek path accepts a head hull")
	check(not COAT.region_allowed("neck", head_regions),
		"the cheek filter does not take a neck hull")
	var torso_regions: Array[String] = ["back", "shoulder"]
	check(COAT.region_allowed("back", torso_regions),
		"a torso region filter accepts a barrel hull")
	check(not COAT.region_allowed("leg", torso_regions),
		"a torso region filter ignores a leg hull")
	check(not COAT.region_allowed("head_Ears1", torso_regions),
		"a torso region filter ignores a head hull")
	var no_regions: Array[String] = []
	check(COAT.region_allowed("anything", no_regions),
		"an empty region filter allows every hull")
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
	check(near(MOTION.STANDING_KISS_LEAN, 0.90) and near(MOTION.MISSIONARY_KISS_LEAN, 0.90),
		"both kiss keys ask for a full lean")
	check(MOTION.kiss_wanted("standing", true, false, 1.0, 0.0),
		"F kisses at a full shoulder lean")
	check(not MOTION.kiss_wanted("standing", true, false, 0.8, 0.0),
		"F does not kiss at a partial shoulder lean")
	check(MOTION.kiss_wanted("bed", true, true, 0.0, 1.0),
		"F and the forward key kiss at a full missionary lean")
	check(not MOTION.kiss_wanted("bed", true, false, 0.0, 1.0),
		"the missionary kiss needs the forward key too")
	check(not MOTION.kiss_wanted("bed", true, false, 1.0, 1.0),
		"a side press alone cannot start the missionary kiss")
	check(not MOTION.kiss_wanted("unknown", true, true, 1.0, 1.0),
		"a family outside the two poses never kisses")

	check(near(REACTIONS.JIGGLE_RUMP_SCALE, 2.8), "thrust jiggle scale")
	check(near(ACT_CAMERA.CAM_SURGE_M, 0.06), "camera surge amplitude")
	check(near(ACT_CAMERA.CAM_BOB_M, 0.02), "camera bob amplitude")
	check(near(MOTION.KISS_LEAN_M, 0.27) and near(MOTION.KISS_LEAN_SIDE_M, 0.18)
		and near(MOTION.KISS_LEAN_DROP_M, 0.035), "kiss leans in, sideways and slightly lower")
	check(near(MOTION.KISS_CAMERA_YAW_DEG, 10.0), "kiss camera turns 10 degrees toward her")
	check(near(MOTION.kiss_pony_side(-1.0), -1.0), "left lean gives her the opposite head tilt")
	check(near(MOTION.kiss_pony_side(1.0), 1.0), "right lean gives her the opposite head tilt")
	check(near(MOTION.kiss_pony_side(0.0), 0.0), "centered kiss leaves the side to her")
	check(near(MOTION.kiss_lateral_offset(-1.0, -1.0, 0.0, 1.0, MOTION.KISS_LEAN_SIDE_M),
		-0.18), "kiss starts at the lean lateral offset")
	check(near(MOTION.kiss_lateral_offset(-0.5, -1.0, 1.0, 1.0, MOTION.KISS_LEAN_SIDE_M),
		-0.18), "full kiss uses one lateral offset")
	check(near(MOTION.kiss_lateral_offset(-0.5, -1.0, 0.5, 1.0, MOTION.KISS_LEAN_SIDE_M),
		-0.135), "kiss lateral crossfades instead of stacking")

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

	var live_runtime: Node = _runtime()
	live_runtime.act._set_state(2) # ACTIVE
	live_runtime.act.pose_id = CATALOG.STANDING
	live_runtime.act.apply_live_settings()
	check(live_runtime.act.features.has("hud_readouts"), "live settings refresh feature flags")
	check(live_runtime.act.context.camera.camera_surge >= 0.0 and live_runtime.act.context.camera.camera_surge <= 1.0,
		"live settings refresh camera thrust")
	live_runtime.free()

	var smack := REACTIONS.new()
	smack.configure(tune({"smack_intensity": 0.5}, "standing"))
	var jiggle_pony := Node3D.new()
	root.add_child(jiggle_pony)
	var tail_host := FakeTailHost.new()
	var fake_tail := POSES.PoseTail.new(tail_host)
	smack.bind_scene(jiggle_pony)
	smack.bind_tail(fake_tail)
	smack.smack(0.8)
	check(near(tail_host.last_strength, 0.5), "smack carries the tail jiggle in standing")
	root.remove_child(jiggle_pony)
	jiggle_pony.free()
	smack.free()

	var mark_flank := FakeFlank.new()
	mark_flank.name = "FlankTouch"
	var mark_a := Decal.new()
	var mark_b := Decal.new()
	mark_a.visible = true
	mark_b.visible = true
	mark_flank.marks = [mark_a, mark_b]
	mark_flank.ages = [0.0, 0.0]
	var mark_pony := Node3D.new()
	root.add_child(mark_pony)
	mark_pony.add_child(mark_flank)
	var marks := REACTIONS.new()
	marks.bind_scene(mark_pony)
	marks.clear_stock_marks()
	check(not mark_a.visible and not mark_b.visible,
		"act start hides stock flank marks")
	check(near(float(mark_flank.ages[0]), 1000.0)
		and near(float(mark_flank.ages[1]), 1000.0),
		"act start ages the stock flank marks")
	mark_pony.remove_child(mark_flank)
	mark_flank.free()
	mark_a.free()
	mark_b.free()
	mark_pony.free()
	marks.free()

	var radius_flank := FakeFlank.new()
	root.add_child(radius_flank)
	var radius_mat := ShaderMaterial.new()
	var radius_mesh := Node3D.new()
	root.add_child(radius_mesh)
	radius_flank._jiggle_targets = [[radius_mat, radius_mesh]]
	var radius := REACTIONS.new()
	radius.bind_scene(null, radius_flank)
	radius.configure(tune({"radius": 0.30}))
	radius.apply_radius()
	check(near(float(radius_mat.get_shader_parameter("jiggle_radius")), 0.30),
		"jiggle radius applies to the targets")
	radius.configure(tune({"radius": -0.05}))
	radius.apply_radius()
	check(near(float(radius_mat.get_shader_parameter("jiggle_radius")), -0.05),
		"jiggle radius is applied unclamped")
	radius.restore_radius()
	check(radius_mat.get_shader_parameter("jiggle_radius") == null,
		"jiggle radius override restores")
	radius_mesh.free()
	radius_flank.free()
	radius.free()

	check(near(STANDING_ANON.hip_offset(0.0, 1.0, 2.0), -0.045),
		"hip rests one reach behind the rump limit")
	check(near(STANDING_ANON.hip_offset(1.0, 1.0, 2.0), 0.045),
		"hip reaches the rump limit at full depth")
	check(near(STANDING_ANON.hip_offset(0.5, 1.0, 2.0), 0.0),
		"half depth returns to the base hip target")
	check(near(STANDING_ANON.hip_offset(1.0, 0.66, 2.0), 0.045 * 0.66),
		"hip reach scales with pony size")

	var hip_facts: RefCounted = ACT_FACTS.new()
	hip_facts.pose_view = _standing_view()
	hip_facts.thrust_travel = 2.0
	var hip_pony := Node3D.new()
	root.add_child(hip_pony)
	var hip_modifier = HIP_THRUST.new()
	root.add_child(hip_modifier)
	var stand := STANDING_ANON.new(hip_facts)
	stand.set("pony", hip_pony)
	stand.set("_hip_thrust", hip_modifier)
	stand.set("_hip_phase", 0.0)
	var hip_body := Node3D.new()
	stand.call("apply_anon_thrust", hip_body, Basis.IDENTITY)
	var hip_offset: Vector3 = hip_modifier.get("offset_world")
	check(near(hip_offset.length(), 0.045) and hip_offset.z > 0.0,
		"depth 0 sets the hips back from the rump limit")
	stand.set("_hip_phase", 1.0)
	stand.call("apply_anon_thrust", hip_body, Basis.IDENTITY)
	hip_offset = hip_modifier.get("offset_world")
	check(near(hip_offset.length(), 0.045) and hip_offset.z < 0.0,
		"depth 1 moves the hips onto the rump limit")
	hip_modifier.free()
	hip_pony.free()
	hip_body.free()

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
	var smack_amount := REACTIONS.new()
	var smack_pony := Node3D.new()
	root.add_child(smack_pony)
	smack_amount.bind_scene(smack_pony, smack_flank)
	smack_amount.configure(tune({"smack_intensity": 0.5}))
	smack_amount.smack(0.8)
	check(near(float(smack_flank._jiggle_amount), 0.04),
		"smack jiggle intensity scales the amount")
	smack_mesh.free()
	smack_flank.free()
	smack_pony.free()
	smack_amount.free()

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
	var tail_facts: RefCounted = ACT_FACTS.new()
	tail_facts.depth = 0.0
	var tail := TAIL.new()
	tail.mare = tail_mare
	tail.facts = tail_facts
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
	var plant_facts: RefCounted = ACT_FACTS.new()
	plant_facts.pose_view = _standing_view()
	plant_facts.free_camera_active = true
	plant_facts.features = {}
	plant_facts.pony = Node3D.new()
	root.add_child(plant_facts.pony)
	var plant_anon := STANDING_ANON.new(plant_facts)
	plant_anon.set("pony", plant_facts.pony)
	plant_anon.call("apply_anon_lean", plant_hip, Basis.IDENTITY)
	check(plant_left.global_position.is_equal_approx(Vector3(0.2, 0.0, 0.0))
		and plant_right.global_position.is_equal_approx(Vector3(-0.2, 0.0, 0.0)),
		"no lean leaves the game's stepping feet alone")
	plant_facts.shot_lean_forward = 1.0
	plant_anon.call("apply_anon_lean", plant_hip, Basis.IDENTITY)
	check(not plant_hip.global_position.is_zero_approx(),
		"a forward lean moves the pelvis")
	check(plant_left.global_position.is_equal_approx(Vector3(0.2, 0.0, 0.0))
		and plant_right.global_position.is_equal_approx(Vector3(-0.2, 0.0, 0.0)),
		"a lean pins the feet at their live stepping pose")
	root.remove_child(plant_facts.pony)
	plant_facts.pony.free()
	plant_hip.free()
	plant_skeleton.free()
	plant_left.free()
	plant_right.free()
	plant_body.free()

	var gate_runtime: Node = _runtime()
	check(not gate_runtime.act.context.gate.start_verdict(CATALOG.MISSIONARY, "bed_side").show(),
		"missing pony blocks start")
	var gate: Variant = gate_runtime.act.context.gate
	check(not gate.call("offer_verdict", CATALOG.STANDING, "", null).offer_ok(),
		"missing pony blocks offer")
	var gate_rows: Array = gate.call("start_verdict", CATALOG.MISSIONARY, "bed_side").rows
	check(gate.call("report_reasons", gate_rows) == PackedStringArray(["invalid_pony"]),
		"gate report keeps the invalid-pony reason")
	gate_runtime.free()

	check(near(MOTION.HOLD_SWAY_FORWARD, 0.010), "idle camera sway amplitude")
	check(near(CAMERA_VIEW.MOUNTING_STANDING_CAMERA_LIFT_M, 0.10), "JRHNBR standing camera raised 10 cm")
	check(near(MOTION.LEAN_SIDE_M, 0.18), "side lean travel")
	check(near(MOTION.LEAN_SIDE_ROLL_DEG, 8.0), "side lean roll stronger")
	check(near(MOTION.LEAN_FIRE, 0.75) and near(MOTION.LEAN_RELEASE, 0.60),
		"lean threshold uses 75/60 hysteresis")

	check(near(MOTION.lean_step(0.0, 1.0, 0.25), 0.5), "lean ramps in over half a second")
	check(near(MOTION.lean_step(1.0, 0.0, 0.8), 1.0),
		"released lean holds its position")
	check(near(MOTION.lean_step(1.0, 0.0, 0.8, true), 0.5),
		"shoulder recentre returns over 1.6 seconds")

	var cuddle_runtime: Node = _runtime()
	var cuddle_pony := Node3D.new()
	cuddle_pony.set_meta("couch_cuddle", true)
	root.add_child(cuddle_pony)
	cuddle_runtime.pony = cuddle_pony
	cuddle_runtime.act._set_state(0) # IDLE
	cuddle_runtime.act.context.gate.suppress_auto_cuddle()
	check(cuddle_pony.has_meta("couch_cuddle"), "idle runtime leaves native bed cuddles alone")
	cuddle_runtime.act._set_state(2) # ACTIVE
	cuddle_runtime.act.context.gate.suppress_auto_cuddle()
	check(not cuddle_pony.has_meta("couch_cuddle"), "active runtime suppresses auto cuddle")
	cuddle_pony.free()
	cuddle_runtime.free()

	_check_tail_tuning()
	_check_missionary_hand_hold()
	_check_pose_retarget()

	if failures == 0:
		print("ACTIONS_PASS")
	finish()


## The pose hook retargets the hands contact path without resetting the controller.
func _check_pose_retarget() -> void:
	var facts: RefCounted = ACT_FACTS.new()
	var view: RefCounted = VIEW.new()
	view.family = "standing"
	view.contact_kind = "opening"
	view.hands = {"path": "standing"}
	facts.pose_view = view
	var facade := HANDS.new(facts)
	facade.pose_changed(view)
	check(not facade.any_active(), "the facade accepts a pose change")
	var controller := CONTROLLER.new(facts)
	var caress := controller.caress()
	controller.pose_changed(view)
	check(controller.hook_path() == "standing", "the hands hook caches the standing path")
	caress.start(MODEL.Side.LEFT)
	view.hands = {"path": "missionary"}
	controller.pose_changed(view)
	check(controller.hook_path() == "missionary", "the path change is carried")
	check(not caress.active(MODEL.Side.LEFT), "a path change ends the live holds")
	view.contact_kind = "mouth"
	controller.pose_changed(view)
	check(controller.hook_contact() == "mouth", "a contact switch is carried for the oral blend")
	check(not caress.active(MODEL.Side.LEFT),
		"a contact switch does not restore a released hold")

	# The standing ↔ oral pair keeps the live caress: the contact switch, not the request path,
	# moves the hand, so the blend can capture its live frame.
	view.hands = {"path": "standing"}
	view.contact_kind = "opening"
	controller.pose_changed(view)
	caress.start(MODEL.Side.LEFT)
	view.hands = {"path": "oral"}
	view.contact_kind = "opening"
	controller.pose_changed(view)
	check(caress.active(MODEL.Side.LEFT),
		"the standing to oral path keeps the caress for the contact blend")
	view.contact_kind = "mouth"
	controller.pose_changed(view)
	check(controller.hook_contact() == "mouth", "the oral contact switch is carried")
	check(caress.active(MODEL.Side.LEFT), "the oral contact switch keeps the caress")
	view.hands = {"path": "standing"}
	view.contact_kind = "opening"
	controller.pose_changed(view)
	check(controller.hook_path() == "standing", "the return path is carried")
	check(caress.active(MODEL.Side.LEFT),
		"the oral to standing path keeps the caress for the return blend")
	facade.free()


## The standing pose read model the body wrappers gate on.
func _standing_view() -> RefCounted:
	var view: RefCounted = VIEW.new()
	view.family = "standing"
	view.settings_group = "standing"
	return view
