extends SceneTree
## The standing oral turn: the captured opening holds through the rotation, the anchor follows the
## live mouth once settled, the release returns to the opening, and the oral pose keys are written
## while live and erased once the turn ends.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_oral_turn.gd

const ORAL := preload("res://mods/unfplap/anatomy/act/oral.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

const STATE_ACTIVE := 2
const TURN_STEP_S := 0.4

var failures := 0
var checks := 0


class FakeAnatomy extends Node:
	var opening := Vector3(0.4, 0.0, 1.2)

	func hole_point(_mix := 0.0) -> Vector3:
		return opening

	func animate(_value: float, _seconds: float) -> void:
		pass


class FakeBoop extends Node:
	var pony: Node3D
	var head_skeleton: Skeleton3D

	func nose_world() -> Vector3:
		return pony.to_global(Vector3(0.0, 1.3, 0.6))


class FakePony extends Node3D:
	var boop_node: Variant
	var head: Variant = null
	var identity: Variant = null


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


## A bare rig that satisfies the oral turn's head and mouth reads.
func _rig() -> Array:
	var pony := FakePony.new()
	var boop := FakeBoop.new()
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("mHead")
	pony.add_child(boop)
	boop.add_child(skeleton)
	boop.pony = pony
	boop.head_skeleton = skeleton
	pony.boop_node = boop
	var anatomy := FakeAnatomy.new()
	root.add_child(pony)
	root.add_child(anatomy)
	return [pony, anatomy, boop]


func _mouth(pony: FakePony, boop: FakeBoop) -> Vector3:
	return boop.nose_world() + Vector3.DOWN * float(ORAL.ORAL_BELOW_NOSE_M)


## One turn tick plus the facing the standing pose would write from the camera override. The oral
## turn itself owns only her position; the runtime's facing lock applies the basis.
func _step(oral: RefCounted, pony: Node3D, delta: float) -> void:
	oral.call("tick", delta)
	var facing: Dictionary = oral.call("facing")
	if float(facing.get("amount", 0.0)) <= 0.001:
		return
	var basis: Basis = facing.get("basis", Basis.IDENTITY)
	var scale := pony.global_transform.basis.get_scale()
	pony.global_transform.basis = basis.scaled(scale)


func run() -> void:
	var was_on := SETTINGS.anatomy_oral.get_bool()
	SETTINGS.anatomy_oral.set_bool(true)

	var rig := _rig()
	var pony: FakePony = rig[0]
	var anatomy: FakeAnatomy = rig[1]
	var boop: FakeBoop = rig[2]
	var oral: RefCounted = ORAL.new()
	var status: Array[String] = []
	oral.call("setup", pony, anatomy, CATALOG.STANDING,
		func(_key: String) -> bool: return true,
		func(text: String) -> void: status.append(text))
	check(status.is_empty(), "a consented start says nothing")
	var opening: Vector3 = anatomy.opening
	var from: Vector3 = pony.global_position

	# Start: the turn is live and the anchor is seeded at the captured opening.
	check(bool(oral.call("toggle", STATE_ACTIVE)), "the toggle starts the oral turn")
	check(is_zero_approx(float(oral.call("mix"))), "a fresh turn starts at zero mix")
	check((oral.call("anchor") as Vector3).is_equal_approx(opening),
		"a fresh turn anchors at the opening")

	# Still turning: the anchor must not chase her rump around the arc.
	for i in 3:
		_step(oral, pony, TURN_STEP_S)
	check(float(oral.call("mix")) < 1.0, "the turn is still running after three steps")
	check((oral.call("anchor") as Vector3).is_equal_approx(opening),
		"the anchor holds the opening while she turns")
	var facing: Dictionary = oral.call("facing")
	check(float(facing.get("amount", 0.0)) > 0.0, "the turn publishes its facing")

	# Settled: her mouth arrives at the old opening in XZ, and the anchor starts to follow it.
	_step(oral, pony, TURN_STEP_S)
	check(is_equal_approx(float(oral.call("mix")), 1.0), "the turn settles at full mix")
	var mouth := _mouth(pony, boop)
	check(near(mouth.x, opening.x) and near(mouth.z, opening.z),
		"the turn lands her mouth on the old opening in XZ")
	var before: Vector3 = oral.call("anchor")
	_step(oral, pony, TURN_STEP_S * 0.625)
	var after: Vector3 = oral.call("anchor")
	check(after.distance_to(mouth) < before.distance_to(mouth),
		"a settled turn eases the anchor toward the live mouth")

	# Head motion: the anchor follows a moved mouth instead of freezing.
	pony.global_position += Vector3(0.2, 0.0, 0.0)
	var moved := _mouth(pony, boop)
	var moved_before: Vector3 = oral.call("anchor")
	_step(oral, pony, TURN_STEP_S * 0.625)
	var moved_after: Vector3 = oral.call("anchor")
	check(moved_after.distance_to(moved) < moved_before.distance_to(moved),
		"the anchor follows the live mouth through head motion")

	# Live pose keys: present with the style motion, gone once the release finishes.
	var config := {"oral_pitch": 99.0}
	oral.call("write_pose_delta", config)
	check(config.has("oral_pitch") and not near(float(config["oral_pitch"]), 99.0),
		"a live turn writes the oral pitch")
	check(config.has("oral_yaw") and config.has("oral_roll"),
		"a live turn writes all three oral keys")

	check(not bool(oral.call("toggle", STATE_ACTIVE)), "the second toggle releases the turn")
	for i in 5:
		_step(oral, pony, TURN_STEP_S)
	check(is_zero_approx(float(oral.call("mix"))), "the release finishes at zero mix")
	check((oral.call("anchor") as Vector3).is_equal_approx(opening),
		"the release returns the anchor to the opening")
	check(pony.global_position.is_equal_approx(from),
		"the release restores her position")
	oral.call("write_pose_delta", config)
	check(not config.has("oral_pitch") and not config.has("oral_yaw") \
		and not config.has("oral_roll"), "a finished release erases the oral keys")

	oral.call("teardown")
	check((oral.call("anchor") as Vector3).is_equal_approx(opening),
		"a teardown falls back to the live opening")
	pony.free()
	anatomy.free()
	SETTINGS.anatomy_oral.set_bool(was_on)

	print("ANATOMY_ORAL_TURN_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
