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
		var ponies: Array = []
		for node: Variant in mares:
			if node is Node3D and BOW.hair_skeleton(node) != null:
				ponies.append(node)
		if ponies.is_empty():
			continue
		print("[bow shot] mares=", (mares as Array).size(), " fitted=", ponies.size())
		await get_tree().create_timer(2.0).timeout
		for k: int in ponies.size():
			await _shoot(ponies[k] as Node3D, k == 0)
		get_tree().quit()
		return
	print("[bow shot] no mare")
	get_tree().quit()


func _shoot(pony: Node3D, measure_cost: bool) -> void:
	await get_tree().create_timer(1.0).timeout
	BOW.set_worn(BOW.worn_id(pony), true)
	var measure_at := Time.get_ticks_usec()
	var radius_probe := BOW.tail_radius(pony)
	print("[bow shot] radius measure ms=", (Time.get_ticks_usec() - measure_at) / 1000.0,
		" radius=", radius_probe)
	var attach_at := Time.get_ticks_usec()
	var node := BOW.attach(pony)
	print("[bow shot] attach ms=", (Time.get_ticks_usec() - attach_at) / 1000.0)
	if node == null:
		print("[bow shot] attach failed")
		return
	var sk := BOW.hair_skeleton(pony)
	var root := sk.find_bone("mTail1")
	var at: Vector3 = node.global_position
	var radius := BOW.tail_radius(pony)
	var cfg := BOW.config()
	print("[bow shot] pony=", pony.name, " tail=", at, " radius=", radius,
		" standoff=", BOW.standoff(pony), " cfg=", cfg,
		" scale=", sk.global_basis.get_scale().x, " bow_scale=", node.global_basis.get_scale(),
		" aabb=", node.mesh.get_aabb())
	DirAccess.make_dir_recursive_absolute(OUT)
	# Frame the bow from its own face, so the shot does not depend on which way she is turned.
	var face := node.global_basis.z.normalized()
	var side := node.global_basis.x.normalized()
	var up := node.global_basis.y.normalized()
	var camera := Camera3D.new()
	camera.fov = 45.0
	camera.near = 0.01
	camera.far = 40.0
	get_tree().root.add_child(camera)
	camera.make_current()
	var reach := maxf(0.95, node.mesh.get_aabb().size.length() * 3.2 \
		* node.global_basis.get_scale().x)
	var shots := {
		"back": at + face * reach + up * reach * 0.25,
		"side": at + (face * 0.55 + side * 0.9) * reach + up * reach * 0.15,
		"close": at + (face * 0.9 + side * 0.25) * reach * 0.55 + up * reach * 0.1,
	}
	for name: String in shots:
		camera.global_position = shots[name]
		camera.look_at(at, up)
		for frame: int in 8:
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		var path := OUT + "bow_" + str(pony.name).to_lower() + "_" + name + ".png"
		image.save_png(path)
		print("[bow shot] wrote ", path, " size=", image.get_size())
	# Cost check on the first pony only: frames per second with the bow on, then with it off.
	if not measure_cost:
		BOW.set_worn(BOW.worn_id(pony), false)
		BOW.detach(pony)
		return
	for i: int in 90:
		await get_tree().process_frame
	var with_bow := Engine.get_frames_per_second()
	var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	BOW.set_worn(BOW.worn_id(pony), false)
	BOW.detach(pony)
	for i: int in 90:
		await get_tree().process_frame
	print("[bow shot] fps with bow=", with_bow, " process_ms=", process_ms,
		" fps without=", Engine.get_frames_per_second())
	# The same comparison while the tail is being animated like the standing act.
	var tail_script: Script = load("res://mods/unfplap/tail_pose.gd")
	var tail: Node = tail_script.new()
	tail.set("mare", pony)
	tail.set("target_amount", 1.0)
	tail.set("aside_goal", 0.4)
	tail.set("amount", 1.0)
	sk.add_child(tail)
	for i: int in 90:
		await get_tree().process_frame
	var tail_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var tail_fps := Engine.get_frames_per_second()
	BOW.attach(pony)
	for i: int in 90:
		await get_tree().process_frame
	print("[bow shot] tail animating: fps without=", tail_fps, " process_ms=", tail_ms,
		" fps with bow=", Engine.get_frames_per_second(),
		" process_ms=", Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	tail.queue_free()
	BOW.detach(pony)
