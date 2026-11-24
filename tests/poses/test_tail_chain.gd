extends "res://mods/unfplap/tests/support/suite.gd"
## The visible tail chain: devkit hair tails use `mTail1..6`, fitted body exports use
## `pony_tail_01..05`. The resolver and both standing tail modifiers must work on either.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_tail_chain.gd

const TAIL_CHAIN := preload("res://mods/unfplap/poses/tail_chain.gd")
const TAIL_POSE := preload("res://mods/unfplap/poses/tail_pose.gd")
const TAIL_LAY := preload("res://mods/unfplap/poses/tail_lay.gd")
const TAIL_TUCK := preload("res://mods/unfplap/poses/tail_tuck.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")



class FakePony extends Node3D:
	var skeleton: Variant = null
	var hair_skeleton: Variant = null


class FakeFacts extends RefCounted:
	var pose_view: Variant = null


## A fitted body tail: ponytail root under the body hips, with five rest segments.
func _add_body_tail(body: Skeleton3D) -> void:
	var parent := body.find_bone("pony_hips")
	for i: int in range(1, 6):
		var bone := body.add_bone("pony_tail_0%d" % i)
		body.set_bone_parent(bone, parent)
		var rest := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.08))
		body.set_bone_rest(bone, rest)
		body.set_bone_pose(bone, rest)
		parent = bone


func run() -> void:
	var pony := FakePony.new()
	var body := Skeleton3D.new()
	body.add_bone("pony_hips")
	_add_body_tail(body)
	var hair := Skeleton3D.new()
	hair.add_bone("mTail1")
	pony.skeleton = body
	pony.hair_skeleton = hair
	root.add_child(pony)
	root.add_child(body)

	var both: Dictionary = TAIL_CHAIN.resolve(pony)
	check(both.get("skeleton") == hair and bool(both.get("hair", false)),
		"the devkit hair tail wins when both chains exist")
	pony.hair_skeleton = null
	var fitted: Dictionary = TAIL_CHAIN.resolve(pony)
	check(fitted.get("skeleton") == body and not bool(fitted.get("hair", true)),
		"a fitted pony falls back to the body tail chain")
	check((fitted.get("bones") as Array).size() == 5,
		"the body chain finds every pony_tail bone")
	pony.skeleton = null
	check(TAIL_CHAIN.resolve(pony).is_empty(),
		"a pony without a tail chain resolves to nothing")
	pony.skeleton = body

	var tail1 := body.find_bone("pony_tail_01")
	var before := body.get_bone_pose(tail1)
	var tail: SkeletonModifier3D = TAIL_POSE.new()
	tail.mare = pony
	tail.aside_angle = 0.6
	tail.lift_angle = 0.3
	tail.amount = 1.0
	tail.target_amount = 1.0
	body.add_child(tail)
	## The modifier's bone cache is private to the rig; this pins the cache on purpose.
	check(int(tail.get("_bones").size()) == 5,
		"the standing tail caches the body chain")
	check(int(tail.get("_pelvis")) < 0,
		"the body chain does not translate a hair pelvis")
	tail.call("_apply", 0.1)
	check(not body.get_bone_pose(tail1).is_equal_approx(before),
		"the standing tail moves the body chain")
	tail.call("restore_tail")
	check(body.get_bone_pose(tail1).is_equal_approx(before),
		"the standing tail restores the body chain")
	body.remove_child(tail)
	tail.free()

	var facts := FakeFacts.new()
	facts.pose_view = VIEW.new()
	facts.pose_view.bed_frame = Transform3D.IDENTITY
	var lay: SkeletonModifier3D = TAIL_LAY.new()
	lay.mare = pony
	lay.facts = facts
	lay.amount = 1.0
	lay.target_amount = 1.0
	body.add_child(lay)
	## The lay modifier's bone cache is private to the rig; this pins the cache on purpose.
	check(int(lay.get("_bones").size()) == 5,
		"the tail lay caches the body chain")
	var lay_before := body.get_bone_pose(tail1)
	lay.call("_process_modification_with_delta", 0.5)
	check(not body.get_bone_pose(tail1).is_equal_approx(lay_before),
		"the tail lay turns the body chain onto the bed")
	lay.call("restore_tail")
	check(body.get_bone_pose(tail1).is_equal_approx(lay_before),
		"the tail lay restores the body chain")
	body.remove_child(lay)
	lay.free()

	# A custom tail root (an integration's own visible tail) replaces the bone path: the standing
	# modifier and the lay rotate that node and restore it, and never touch the body chain.
	var holder := Node3D.new()
	pony.add_child(holder)
	var chain := Skeleton3D.new()
	chain.name = "Chain"
	holder.add_child(chain)
	for i: int in 5:
		var bone := chain.add_bone("tail_%d" % i)
		if i > 0:
			chain.set_bone_parent(bone, bone - 1)
		chain.set_bone_rest(bone, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -0.04)))
	chain.reset_bone_poses()
	var saved_root := Transform3D(Basis.from_euler(Vector3(0.1, 0.2, 0.3)),
		Vector3(0.1, 0.2, 0.3))
	chain.transform = saved_root
	pony.set_meta("tail_pose_root", chain)
	check(TAIL_CHAIN.custom_root(pony) == chain, "the custom tail root resolves from metadata")
	check(TAIL_CHAIN.root_direction(chain).length_squared() > 0.9,
		"the custom root has a tail direction")
	var root_tail: SkeletonModifier3D = TAIL_POSE.new()
	root_tail.mare = pony
	root_tail.aside_angle = 0.6
	root_tail.lift_angle = 0.3
	root_tail.amount = 1.0
	root_tail.target_amount = 1.0
	body.add_child(root_tail)
	var body_before := body.get_bone_pose(tail1)
	root_tail.call("_apply", 0.1)
	check(not chain.transform.is_equal_approx(saved_root),
		"the standing tail rotates the custom root")
	check(body.get_bone_pose(tail1).is_equal_approx(body_before),
		"the standing tail leaves the body chain alone with a custom root")
	root_tail.call("restore_tail")
	check(chain.transform.is_equal_approx(saved_root),
		"the standing tail restores the custom root")
	body.remove_child(root_tail)
	root_tail.free()

	var root_lay: SkeletonModifier3D = TAIL_LAY.new()
	root_lay.mare = pony
	root_lay.facts = facts
	root_lay.amount = 1.0
	root_lay.target_amount = 1.0
	body.add_child(root_lay)
	body_before = body.get_bone_pose(tail1)
	root_lay.call("_process_modification_with_delta", 0.5)
	check(not chain.transform.is_equal_approx(saved_root),
		"the tail lay turns the custom root")
	check(body.get_bone_pose(tail1).is_equal_approx(body_before),
		"the tail lay leaves the body chain alone with a custom root")
	root_lay.call("restore_tail")
	check(chain.transform.is_equal_approx(saved_root),
		"the tail lay restores the custom root")
	body.remove_child(root_lay)
	root_lay.free()
	pony.remove_meta("tail_pose_root")
	check(TAIL_CHAIN.custom_root(pony) == null, "no metadata means no custom root")

	var tuck: Node = TAIL_TUCK.new()
	tuck.set("pony", pony)
	root.add_child(tuck)
	var tucked: Variant = tuck.get("_tail")
	check(tucked != null and tucked.get_parent() == body,
		"the post-stop tuck installs on the body chain")
	root.remove_child(tuck)
	tuck.free()

	root.remove_child(body)
	body.free()
	root.remove_child(pony)
	pony.free()
	hair.free()

	finish()
