extends SceneTree
## The act prop loads the base-game footstool visual and builds a standable top.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/stool/test_prop.gd

const PROP := preload("res://mods/unfplap/stool/prop.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var pony := CharacterBody3D.new()
	var pony_shape := CollisionShape3D.new()
	var pony_capsule := CapsuleShape3D.new()
	pony_capsule.radius = 0.2
	pony_capsule.height = 1.0
	pony_shape.shape = pony_capsule
	pony.add_child(pony_shape)
	root.add_child(pony)
	var built := PROP.build(host, Vector3(0.0, 0.0, 0.0), 0.0, 2, 0.20, pony)
	var node: Variant = built.get("node")
	check(node is Node3D and is_instance_valid(node), "the footstool stack is built")
	var height := float(built.get("height", 0.0))
	check(is_equal_approx(height, 0.40), "two 20 cm stools are 40 cm high")
	check(int(built.get("count", 0)) == 2, "the stack reports two stools")
	var body := node as StaticBody3D
	var holder: CollisionShape3D = null
	if body != null:
		for child: Node in body.get_children():
			if child is CollisionShape3D:
				holder = child
				break
	check(holder != null and holder.shape is BoxShape3D, "the prop has a box top")
	check(body != null and body.get_collision_exceptions().has(pony),
		"the stack ignores the pony")
	check(pony.get_collision_exceptions().has(body), "the pony ignores the stack")
	PROP.remove(node)
	check(node is Node and (node as Node).get_parent() == null,
		"the prop leaves the physics space immediately")
	check(not pony.get_collision_exceptions().has(body),
		"the pony exception is removed with the prop")
	pony.queue_free()
	host.queue_free()

	print("STOOL_PROP_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
