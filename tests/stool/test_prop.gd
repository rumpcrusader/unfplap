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
	var built := PROP.build(host, Vector3(0.0, 0.0, 0.0), 0.0)
	var node: Variant = built.get("node")
	check(node is Node3D and is_instance_valid(node), "the footstool prop is built")
	var height := float(built.get("height", 0.0))
	check(height > 0.25 and height < 0.55, "the prop height is the base-game footstool's")
	var body := node as StaticBody3D
	var holder: CollisionShape3D = null
	if body != null:
		for child: Node in body.get_children():
			if child is CollisionShape3D:
				holder = child
				break
	check(holder != null and holder.shape is BoxShape3D, "the prop has a box top")
	PROP.remove(node)
	check(node is Node and (node as Node).get_parent() == null,
		"the prop leaves the physics space immediately")
	host.queue_free()

	print("STOOL_PROP_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
