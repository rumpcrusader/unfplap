extends "res://mods/unfplap/tests/support/suite.gd"
## The standing oral mouth/contact provider: her mouth point, the base opening, the D viseme hold
## and the clear. It owns no turn, mix, facing or pose keys.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_oral_turn.gd

const ORAL := preload("res://mods/unfplap/anatomy/act/oral.gd")
const RIG := preload("res://mods/unfplap/anatomy/rig.gd")



class FakeAnatomy extends "res://mods/unfplap/anatomy/controller.gd":
	var opening := Vector3(0.4, 0.0, 1.2)

	func hole_point(_mix := 0.0) -> Vector3:
		return opening


class FakeBoop extends Node:
	var pony: Node3D
	var head_skeleton: Skeleton3D

	func nose_world() -> Vector3:
		return pony.to_global(Vector3(0.0, 1.3, 0.6))


class FakeMouth extends "res://mods/unfplap/tests/support/fakes/fake_mouth.gd":
	pass


class FakeHead extends Node:
	var mouth: Variant = null


class FakePony extends Node3D:
	var boop_node: Variant
	var head: Variant = null

func run() -> void:
	var pony := FakePony.new()
	var boop := FakeBoop.new()
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("mHead")
	var head := FakeHead.new()
	var mouth := FakeMouth.new()
	head.mouth = mouth
	pony.add_child(head)
	pony.add_child(boop)
	boop.add_child(skeleton)
	boop.pony = pony
	boop.head_skeleton = skeleton
	pony.boop_node = boop
	pony.head = head
	var anatomy := FakeAnatomy.new()
	anatomy.set_process(false)
	root.add_child(pony)
	root.add_child(anatomy)

	var oral: RefCounted = ORAL.new()
	oral.call("setup", pony, anatomy, RIG.new())
	var nose: Vector3 = boop.nose_world()
	check(oral.call("mouth_point").is_equal_approx(
		nose + Vector3.DOWN * float(ORAL.ORAL_BELOW_NOSE_M)),
		"the mouth point sits below her nose")
	oral.call("set_scale", 2.0)
	check(near((oral.call("mouth_point") as Vector3).y,
		nose.y - float(ORAL.ORAL_BELOW_NOSE_M) * 2.0),
		"the mouth point follows the player size scale")
	check((oral.call("opening") as Vector3).is_equal_approx(anatomy.opening),
		"the provider exposes the base opening")

	check(mouth.visemes.is_empty(), "a fresh provider mouths nothing")
	oral.call("set_viseme", "D")
	check(mouth.visemes == ["D"], "the viseme event opens the D mouth")
	mouth.visemes.clear()
	oral.call("hold_viseme")
	check(mouth.visemes == ["D"], "a speech stop re-asserts the held viseme")
	oral.call("clear")
	check(mouth.clears == 1, "the contact release clears the mouth")
	mouth.visemes.clear()
	oral.call("hold_viseme")
	check(mouth.visemes.is_empty(), "a cleared provider does not re-assert a viseme")
	oral.call("set_viseme", "D")
	oral.call("reset")
	mouth.visemes.clear()
	oral.call("hold_viseme")
	check(mouth.visemes.is_empty(), "the provider reset drops the held viseme")
	oral.call("teardown")

	for method: String in ["toggle", "mix", "anchor", "facing", "write_facing",
			"write_pose_delta", "active"]:
		check(not oral.has_method(method), "the provider has no %s" % method)
	check(not oral.has_method("pose_delta"), "the provider carries no pose keys")

	pony.free()
	mouth.free()
	anatomy.free()
	finish()
