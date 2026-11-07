extends SceneTree
## Debug tail collapse: the modifier scales the tail chain and restores it without moving joints.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_tail_hide.gd

const TAIL_HIDE := preload("res://mods/unfplap/tail_hide.gd")
const SCHEMA := preload("res://mods/unfplap/tunables_schema.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	check(SCHEMA.has("debug_hide_tails"), "hide tails toggle exists")
	check(not bool(SCHEMA.default_value("debug_hide_tails")), "hide tails is off by default")

	var skeleton := Skeleton3D.new()
	skeleton.add_bone("mTail1")
	skeleton.add_bone("mTail2")
	skeleton.set_bone_parent(1, 0)
	root.add_child(skeleton)
	var modifier := TAIL_HIDE.new()
	modifier.bones = [&"mTail1", &"mTail2"]
	skeleton.add_child(modifier)
	modifier.call("set_hiding", true)
	modifier.call("_process_modification")
	check(near(skeleton.get_bone_pose_scale(0).x, TAIL_HIDE.HIDE_SCALE),
		"first tail bone collapses")
	check(near(skeleton.get_bone_pose_scale(1).x, TAIL_HIDE.HIDE_SCALE),
		"child tail bone collapses")
	modifier.call("set_hiding", false)
	check(near(skeleton.get_bone_pose_scale(0).x, 1.0), "first tail bone restores")
	check(near(skeleton.get_bone_pose_scale(1).x, 1.0), "child tail bone restores")
	skeleton.free()

	print("TAIL_HIDE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
