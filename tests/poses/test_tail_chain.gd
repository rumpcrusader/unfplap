extends SceneTree
## The visible tail chain: devkit hair tails use `mTail1..6`, fitted body exports use
## `pony_tail_01..05`. The resolver and both standing tail modifiers must work on either.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_tail_chain.gd

const TAIL_CHAIN := preload("res://mods/unfplap/poses/tail_chain.gd")
const TAIL_POSE := preload("res://mods/unfplap/poses/tail_pose.gd")
const TAIL_LAY := preload("res://mods/unfplap/poses/tail_lay.gd")
const TAIL_TUCK := preload("res://mods/unfplap/poses/tail_tuck.gd")

var failures := 0
var checks := 0


class FakePony extends Node3D:
	var skeleton: Variant = null
	var hair_skeleton: Variant = null


class FakeFacts extends RefCounted:
	var bed_frame: Variant = null


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


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
	facts.bed_frame = Transform3D.IDENTITY
	var lay: SkeletonModifier3D = TAIL_LAY.new()
	lay.mare = pony
	lay.facts = facts
	lay.amount = 1.0
	lay.target_amount = 1.0
	body.add_child(lay)
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

	print("TAIL_CHAIN_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
