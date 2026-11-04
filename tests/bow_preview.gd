extends Node
## Accessory preview: ties the tail bow on a loaded mare and writes three screenshots of her rear
## to /tmp/opencode/bow_*.png. Run it with the real display so the images are rendered:
##   godot --xr-mode off --display-driver wayland --path <project> -- --mod-src unfplap \
##     --skip-title --world-id unfplap-test --lab res://mods/unfplap/tests/bow_preview.gd
## It is a developer tool, not a test: tests/ never ships in the pack.

const BOW := preload("res://mods/unfplap/tail_bow.gd")
const OUT := "/tmp/opencode/"
var game: Node


func _ready() -> void:
	run.call_deferred()


func run() -> void:
	for i: int in 900:
		await get_tree().create_timer(0.1).timeout
		if not is_instance_valid(game):
			var scene := get_tree().current_scene
			if scene != null and scene.get("world_context") != null:
				game = scene
		if not is_instance_valid(game):
			continue
		# The loading screen spawns residents behind its own coroutine; wait for it to finish.
		if game.get("title_active") == true or game.get_node_or_null("LoadingCover") != null:
			continue
		var mares: Variant = game.get("mares")
		if not mares is Array:
			continue
		var pony: Node3D = null
		var first: Node3D = null
		for node: Variant in mares:
			if not node is Node3D or BOW.hair_skeleton(node) == null:
				continue
			if first == null:
				first = node as Node3D
			if str((node as Node3D).name).to_lower().begins_with("flutter"):
				pony = node as Node3D
				break
		if pony == null:
			pony = first
		if pony == null:
			continue
		print("[bow shot] mares=", (mares as Array).size(), " picked=", pony.name)
		await get_tree().create_timer(2.0).timeout
		await _shoot(pony)
		get_tree().quit()
		return
	print("[bow shot] no mare")
	get_tree().quit()


func _shoot(pony: Node3D) -> void:
	await get_tree().create_timer(1.0).timeout
	BOW.set_worn(BOW.worn_id(pony), true)
	var node := BOW.attach(pony)
	if node == null:
		print("[bow shot] attach failed")
		return
	var sk := BOW.hair_skeleton(pony)
	var root := sk.find_bone("mTail1")
	var at: Vector3 = sk.global_transform * sk.get_bone_global_pose(root).origin
	var radius := BOW.tail_radius(pony, 0.02)
	print("[bow shot] pony=", pony.name, " tail=", at, " radius=", radius,
		" scale=", sk.global_basis.get_scale().x, " bow=", node.global_position,
		" aabb=", node.mesh.get_aabb())
	DirAccess.make_dir_recursive_absolute(OUT)
	var back := pony.global_basis.z.normalized()
	var side := pony.global_basis.x.normalized()
	var camera := Camera3D.new()
	camera.fov = 45.0
	camera.near = 0.01
	camera.far = 40.0
	get_tree().root.add_child(camera)
	camera.make_current()
	var reach := maxf(0.75, radius * 9.0)
	var shots := {
		"back": at + back * reach + Vector3.UP * reach * 0.45,
		"side": at + (back * 0.35 + side * 1.0) * reach + Vector3.UP * reach * 0.25,
		"close": at + (back * 0.55 + side * 0.25) * reach * 0.55 + Vector3.UP * reach * 0.2,
	}
	for name: String in shots:
		camera.global_position = shots[name]
		camera.look_at(at + Vector3.UP * radius * 0.2, Vector3.UP)
		for frame: int in 8:
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		var path := OUT + "bow_" + name + ".png"
		image.save_png(path)
		print("[bow shot] wrote ", path, " size=", image.get_size())
	await get_tree().create_timer(0.2).timeout
