extends Node
## Unfplap manual test lab. Run with:
##   godot --xr-mode off --path <project> -- --mod-src unfplap \
##       --lab res://mods/unfplap/tests/test_lab.gd
##
## Builds a clear test bed in front of the player, puts the first mares nearby at different
## relationship levels, and stops the usual director/population/time systems so a cuddle can be
## tested without waiting for the world to cooperate.

const BED := preload("res://world/props/ponyville/pony_bed.scn")
const BED_REST := preload("res://world/relationships/shared_bed.gd")

var game: Node
var bed: Node3D
var rest: Node3D
var _done := false


func _ready() -> void:
	run.call_deferred()


func run() -> void:
	if not await _wait_for_world():
		return
	_stop_standard_systems()
	var ponies: Array = game.get("mares")
	if not ponies is Array or ponies.is_empty():
		print("[unfplap test] no mares loaded")
		return
	var anchor: Node3D = game.player if is_instance_valid(game.get("player")) else (ponies[0] as Node3D)
	_spawn_bed(anchor)
	_setup_ponies(ponies)
	_done = true
	print("[unfplap test] bed ready at %s" % str(bed.global_position))
	print("[unfplap test] E sit, Ctrl lie back; ponies are waiting nearby at different levels")
	print("[unfplap test] standard director/population/time disabled for this session")


func _wait_for_world() -> bool:
	for i in 1800:
		if is_instance_valid(game) and is_instance_valid(game.get("player")) \
				and is_instance_valid(game.get("world_context")):
			return true
		await get_tree().process_frame
	print("[unfplap test] world did not become ready")
	return false


func _stop_standard_systems() -> void:
	if is_instance_valid(game.get("director")):
		game.get("director").set_physics_process(false)
		game.get("director").set_process(false)
	if is_instance_valid(game.get("population")):
		game.get("population").set_physics_process(false)
		game.get("population").set_process(false)
	if is_instance_valid(game.get("life")):
		game.get("life").set_physics_process(false)
	if is_instance_valid(game.get("needs")):
		game.get("needs").set_physics_process(false)
	var clock: Node = get_node_or_null("/root/TimeOfDay")
	if clock != null:
		clock.set("paused", true)


func _spawn_bed(anchor: Node3D) -> void:
	var forward: Vector3 = -anchor.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	var at: Vector3 = anchor.global_position + forward.normalized() * 2.0
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 6.0, 1)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		at.y = float(hit.position.y)
	bed = BED.instantiate()
	bed.name = "UnfplapTestBed"
	game.add_child(bed)
	bed.global_position = at
	bed.rotation.y = anchor.rotation.y
	bed.set_meta("side_local", Vector3(1, 0, 0))
	bed.add_to_group("house_furniture")
	rest = BED_REST.for_bed(bed)
	rest.call("refresh")


func _setup_ponies(ponies: Array) -> void:
	var levels := [150, 400, 900]
	for i: int in mini(ponies.size(), levels.size()):
		var pony: Node3D = ponies[i] as Node3D
		if not is_instance_valid(pony):
			continue
		var id := str(pony.get_meta("relationship_id", ""))
		if id.is_empty() and pony.get("identity") != null:
			id = str(pony.get("identity").get("id"))
		if id.is_empty():
			continue
		var rel: Variant = pony.get_meta("relationship_runtime")
		if rel == null or not is_instance_valid(rel):
			continue
		var bonds: Variant = rel.get("bonds")
		if bonds != null and bonds.has_method("record_for"):
			var row: Dictionary = bonds.call("record_for", id)
			row["stage"] = "dating"
			row["familiarity"] = 80.0
			row["trust"] = 40.0
			row["together_s"] = 3600.0
			bonds.call("_save", id, row)
		var context: Variant = game.get("world_context")
		if context != null:
			var impressions: Variant = context.get("impressions")
			if impressions != null:
				var xp: Variant = impressions.get("xp")
				if not xp is Dictionary:
					xp = {}
					impressions.set("xp", xp)
				(xp as Dictionary)[id] = {"friendship": 500, "romance": levels[i]}
		var offset: Vector3 = bed.global_position + Vector3((i - 1) * 1.1, 0.0, 1.2)
		pony.global_position = offset
		pony.reset_physics_interpolation()
		var nav := pony.get_node_or_null("Navigator")
		if nav != null:
			nav.call("stay")
		print("[unfplap test] %s level xp=%d" % [id, levels[i]])


func _exit_tree() -> void:
	if is_instance_valid(bed):
		bed.queue_free()
