extends SceneTree
## The missionary prone sway follows raw depth, replays its slide and nod after the pose evaluator
## rewrites the body, and holds still outside the active states.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_prone_sway.gd

const SWAY := preload("res://mods/unfplap/poses/prone_sway.gd")

var failures := 0
var checks := 0


class FakeFacts extends RefCounted:
	var depth := 1.0
	var state := 2


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
	for bone_name: String in ["pony_spine1", "pony_neck2", "pony_head"]:
		skeleton.add_bone(bone_name)
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_parent(2, 1)
	skeleton.set_bone_pose_position(1, Vector3(0.0, 0.2, 0.0))
	skeleton.set_bone_pose_position(2, Vector3(0.0, 0.1, 0.0))
	var facts := FakeFacts.new()
	var sway: SkeletonModifier3D = SWAY.new()
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

	print("POSE_PRONE_SWAY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
