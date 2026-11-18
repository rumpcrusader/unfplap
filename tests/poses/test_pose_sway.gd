extends SceneTree
## The pose modifiers' sway: the standing body sway follows depth outside the oral segment and the
## missionary prone sway slides and nods, both replaying their offset after the pose evaluator
## rewrites the body.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_pose_sway.gd

const BODY_SWAY := preload("res://mods/unfplap/poses/body_sway.gd")
const PRONE_SWAY := preload("res://mods/unfplap/poses/prone_sway.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")

var failures := 0
var checks := 0


class FakeFacts extends RefCounted:
	var depth := 1.0
	var state := 2
	var pose_view: Variant = null
	var standing_sway_offset := Vector3.ZERO

	func perf(_key: String, _usec: int) -> void:
		pass


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	_check_body_sway()
	_check_prone_sway()
	print("POSE_SWAY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


## The standing sway holds at its base while the oral segment owns the act and returns afterwards.
func _check_body_sway() -> void:
	var mare := Node3D.new()
	var skeleton := Skeleton3D.new()
	for bone_name: String in ["pony_hips", "pony_upperArm_L", "pony_upperArm_R",
			"pony_femur_L", "pony_femur_R"]:
		skeleton.add_bone(bone_name)
	var facts := FakeFacts.new()
	var view: RefCounted = VIEW.new()
	view.contact_kind = "opening"
	facts.pose_view = view
	var sway: SkeletonModifier3D = BODY_SWAY.new()
	sway.mare = mare
	sway.facts = facts
	root.add_child(mare)
	root.add_child(skeleton)
	skeleton.add_child(sway)

	var hips := skeleton.find_bone("pony_hips")
	var base := skeleton.get_bone_pose(hips).origin
	for _i: int in 4:
		sway.call("_apply", 0.05)
	check(facts.standing_sway_offset.length() > 0.0001,
		"a regular thrust sways the body and publishes its offset")
	check(skeleton.get_bone_pose(hips).origin.distance_to(base) > 0.0001,
		"the pelvis leaves its base on a regular thrust")

	# The pose evaluator rewrites the 30 body bones after the modifier pass; the session replays
	# the sway from the render write, so the offset survives to the rendered frame.
	var replayed := skeleton.get_bone_pose(hips).origin
	skeleton.set_bone_pose_position(hips, base)
	sway.call("apply_render", skeleton)
	check(skeleton.get_bone_pose(hips).origin.is_equal_approx(replayed),
		"the render replay restores the pelvis offset after the pose write")
	check(facts.standing_sway_offset.length() > 0.0001,
		"the render replay keeps the published world offset")
	sway.call("apply_render", skeleton)
	check(skeleton.get_bone_pose(hips).origin.is_equal_approx(replayed),
		"a repeated render replay does not accumulate the offset")

	view.contact_kind = "mouth"
	sway.call("_apply", 0.05)
	check(facts.standing_sway_offset == Vector3.ZERO,
		"oral publishes a zero sway offset")
	check(is_zero_approx(float(sway.get("_offset"))) and is_zero_approx(float(sway.get("_velocity"))),
		"oral holds the sway spring at rest")
	check(skeleton.get_bone_pose(hips).origin.is_equal_approx(base),
		"oral leaves the pelvis at its base")
	sway.call("apply_render", skeleton)
	check(skeleton.get_bone_pose(hips).origin.is_equal_approx(base)
		and facts.standing_sway_offset == Vector3.ZERO,
		"the oral render replay keeps the pelvis and published offset at rest")

	view.contact_kind = "opening"
	for _i: int in 4:
		sway.call("_apply", 0.05)
	check(facts.standing_sway_offset.length() > 0.0001,
		"the sway returns after the oral release")

	skeleton.remove_child(sway)
	sway.free()
	root.remove_child(skeleton)
	root.remove_child(mare)
	skeleton.free()
	mare.free()


## The prone sway follows raw depth, replays its slide and nod after the pose write, and holds
## still outside the active states.
func _check_prone_sway() -> void:
	var mare := Node3D.new()
	var skeleton := Skeleton3D.new()
	for bone_name: String in ["pony_spine1", "pony_neck2", "pony_head"]:
		skeleton.add_bone(bone_name)
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_parent(2, 1)
	skeleton.set_bone_pose_position(1, Vector3(0.0, 0.2, 0.0))
	skeleton.set_bone_pose_position(2, Vector3(0.0, 0.1, 0.0))
	var facts := FakeFacts.new()
	var sway: SkeletonModifier3D = PRONE_SWAY.new()
	sway.mare = mare
	sway.facts = facts
	root.add_child(mare)
	root.add_child(skeleton)
	skeleton.add_child(sway)

	var spine := skeleton.find_bone("pony_spine1")
	var neck := skeleton.find_bone("pony_neck2")
	var head := skeleton.find_bone("pony_head")
	var base_spine := skeleton.get_bone_pose(spine).origin
	var base_neck := skeleton.get_bone_pose_rotation(neck)
	var base_head := skeleton.get_bone_pose_rotation(head)
	for _i: int in 4:
		sway.call("_apply", 0.05)
	check(skeleton.get_bone_pose(spine).origin.distance_to(base_spine) > 0.0001,
		"a regular thrust slides the prone body along the bed")
	check(not skeleton.get_bone_pose_rotation(head).is_equal_approx(base_head),
		"a regular thrust nods the head")

	# The pose evaluator rewrites the 30 body bones after the modifier pass; the session replays
	# the slide and nod from the render write, so they survive to the rendered frame.
	var replayed_spine := skeleton.get_bone_pose(spine).origin
	skeleton.set_bone_pose_position(spine, base_spine)
	skeleton.set_bone_pose_rotation(neck, base_neck)
	skeleton.set_bone_pose_rotation(head, base_head)
	sway.call("apply_render", skeleton)
	var replayed_head := skeleton.get_bone_pose_rotation(head)
	check(skeleton.get_bone_pose(spine).origin.is_equal_approx(replayed_spine),
		"the render replay restores the prone slide after the pose write")
	check(not replayed_head.is_equal_approx(base_head),
		"the render replay applies the prone nod after the pose write")
	skeleton.set_bone_pose_position(spine, base_spine)
	skeleton.set_bone_pose_rotation(neck, base_neck)
	skeleton.set_bone_pose_rotation(head, base_head)
	sway.call("apply_render", skeleton)
	check(skeleton.get_bone_pose(spine).origin.is_equal_approx(replayed_spine)
		and skeleton.get_bone_pose_rotation(head).is_equal_approx(replayed_head),
		"a repeated render replay does not accumulate the prone pose")

	facts.state = 5
	skeleton.set_bone_pose_position(spine, base_spine)
	skeleton.set_bone_pose_rotation(neck, base_neck)
	skeleton.set_bone_pose_rotation(head, base_head)
	sway.call("apply_render", skeleton)
	check(skeleton.get_bone_pose(spine).origin.is_equal_approx(base_spine)
		and skeleton.get_bone_pose_rotation(head).is_equal_approx(base_head),
		"the render replay holds still outside the active states")

	skeleton.remove_child(sway)
	sway.free()
	root.remove_child(skeleton)
	root.remove_child(mare)
	skeleton.free()
	mare.free()
