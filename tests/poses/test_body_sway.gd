extends SceneTree
## The standing body sway holds at its base while the oral segment owns the act and follows depth
## again after the release.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_body_sway.gd

const SWAY := preload("res://mods/unfplap/poses/body_sway.gd")

var failures := 0
var checks := 0


class FakeFacts extends RefCounted:
	var depth := 1.0
	var oral_active := false
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
	var mare := Node3D.new()
	var skeleton := Skeleton3D.new()
	for bone_name: String in ["pony_hips", "pony_upperArm_L", "pony_upperArm_R",
			"pony_femur_L", "pony_femur_R"]:
		skeleton.add_bone(bone_name)
	var facts := FakeFacts.new()
	var sway: SkeletonModifier3D = SWAY.new()
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

	facts.oral_active = true
	sway.call("_apply", 0.05)
	check(facts.standing_sway_offset == Vector3.ZERO,
		"oral publishes a zero sway offset")
	check(is_zero_approx(float(sway.get("_offset"))) and is_zero_approx(float(sway.get("_velocity"))),
		"oral holds the sway spring at rest")
	check(skeleton.get_bone_pose(hips).origin.is_equal_approx(base),
		"oral leaves the pelvis at its base")

	facts.oral_active = false
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

	print("POSE_BODY_SWAY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
