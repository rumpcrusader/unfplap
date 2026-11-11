extends SceneTree
## The standing placement raises the player onto the stool and lowers him again.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/stool/test_placement.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const STOOL := preload("res://mods/unfplap/stool.gd")

var failures := 0
var checks := 0


class FakeMain extends Node:
	var player: Node3D
	var stool: Node
	var game: Node


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(8.0, 0.2, 8.0)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.1
	floor.add_child(floor_shape)
	root.add_child(floor)

	var player := CharacterBody3D.new()
	var capsule := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.2
	shape.height = 1.8
	capsule.shape = shape
	capsule.position.y = 0.9
	player.add_child(capsule)
	root.add_child(player)
	player.global_position = Vector3.ZERO

	var pony := Node3D.new()
	root.add_child(pony)
	pony.global_position = Vector3(0.0, 0.0, 0.0)

	var main := FakeMain.new()
	main.player = player
	main.stool = STOOL.new()
	main.stool.call("setup", main)
	root.add_child(main)
	root.add_child(main.stool)

	var runtime: Node = RUNTIME.new()
	runtime.main = main
	runtime.pony = pony
	runtime.set("_stool_active", true)
	root.add_child(runtime)
	var standing: Variant = runtime.call("_begin_standing_placement")
	check(standing is Transform3D, "the standing transform is returned")
	var prop: Variant = runtime.get("_stool_node")
	check(prop is Node3D and is_instance_valid(prop), "the standing stool is built")
	var height := float(runtime.get("_stool_height_m"))
	check(height > 0.25 and height < 0.55, "the stool uses the base-game height")
	check(absf(player.global_position.y - (height + 0.005)) < 0.01,
		"the player root is raised onto the stool top")
	check(is_instance_valid(prop) and (prop as Node).get_parent() == main.stool,
		"the stool is owned by the stool system")

	runtime.call("_release_stool")
	check(absf(player.global_position.y) < 0.01, "the player is lowered to the floor")
	check(not (runtime.get("_stool_node") is Node3D), "the stool is removed on release")
	runtime.free()
	main.stool.call("shutdown")
	main.stool.free()
	main.free()
	player.free()
	pony.free()
	floor.free()

	print("STOOL_PLACEMENT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
