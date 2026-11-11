extends Node
## Finds pickable footstools in the world when the player owns none. See docs/stool.md.

const ITEM := preload("res://mods/unfplap/stool/item.gd")
const SPAWN_COUNT := 3
const RANGE_M := 80.0
const RETRY_S := 2.0
const STOOL_PROBE := Vector3(0.62, 0.46, 0.5)

var main: Node
var system: Node
var _clock := 0.0
var _started := false
var _spawned := 0
var _used: Dictionary = {}
var _wait_logged := false
var _full_logged := false


func setup(main_node: Node, system_node: Node) -> void:
	main = main_node
	system = system_node
	set_process(true)


func reset() -> void:
	_clock = 0.0
	_started = false
	_spawned = 0
	_used.clear()
	_wait_logged = false
	_full_logged = false


func world_changed(_host: Node) -> void:
	reset()


func _process(delta: float) -> void:
	if not is_instance_valid(system) or not bool(system.call("enabled")):
		return
	_clock += delta
	if _clock < RETRY_S:
		return
	_clock = 0.0
	_tick()


func _tick() -> void:
	if not is_instance_valid(main):
		return
	var game: Variant = main.get("game")
	if not is_instance_valid(game):
		return
	var tree := get_tree()
	if tree == null or tree.paused:
		return
	if main.get("active_runtime") != null:
		return
	var player: Variant = game.get("player")
	if not is_instance_valid(player):
		return
	var inventory: Variant = game.get("inventory")
	if not is_instance_valid(inventory):
		return
	var store: Variant = inventory.get("inventory")
	if store == null:
		return
	if not _started:
		if int(system.call("owned_count", store)) > 0:
			_spawned = SPAWN_COUNT
			return
	if _spawned >= SPAWN_COUNT:
		return
	var houses: Array[Node3D] = []
	for node: Variant in tree.get_nodes_in_group("house_interiors"):
		if not node is Node3D or not is_instance_valid(node):
			continue
		var house := node as Node3D
		if not house.has_method("place_id") or not house.has_method("inside"):
			continue
		var place := str(house.call("place_id"))
		if place.is_empty() or _used.has(place):
			continue
		if house.global_position.distance_to(player.global_position) > RANGE_M:
			continue
		houses.append(house)
	if houses.is_empty():
		if not _wait_logged:
			_wait_logged = true
			_debug("stool supply waiting for a loaded house")
		return
	houses.shuffle()
	for house: Node3D in houses:
		if _spawned >= SPAWN_COUNT:
			break
		if _place_in(house, store, inventory):
			_spawned += 1
			_started = true
	if _spawned >= SPAWN_COUNT:
		_debug("stool supply spawned=%d" % _spawned)


func _place_in(house: Node3D, store: Variant, inventory: Node) -> bool:
	for point: Vector3 in _spots(house):
		var pose: Variant = _drop_pose(house, point)
		if not pose is Transform3D:
			continue
		var item: Variant = inventory.call("spawn_owned_drop", ITEM.ID, pose)
		if is_instance_valid(item):
			_used[str(house.call("place_id"))] = true
			_debug("stool supply house=%s at=%s" % [
				str(house.call("place_id")), str((pose as Transform3D).origin)])
			return true
		if not _full_logged:
			_full_logged = true
			_debug("stool supply blocked reason=briefcase_full")
		return false
	return false


func _spots(house: Node3D) -> Array[Vector3]:
	var inside: Variant = house.call("inside")
	var center: Variant = house.call("center") if house.has_method("center") \
		else house.global_position
	var at_inside: Vector3 = inside if inside is Vector3 else house.global_position
	var at_center: Vector3 = center if center is Vector3 else at_inside
	var toward := Vector3(at_center.x - at_inside.x, 0.0, at_center.z - at_inside.z)
	if toward.length_squared() < 0.0001:
		toward = -house.global_basis.z
	toward.y = 0.0
	toward = toward.normalized()
	var out: Array[Vector3] = [at_inside + toward * 1.0, at_center]
	for offset: Vector3 in [Vector3(0.8, 0.0, 0.0), Vector3(-0.8, 0.0, 0.0),
			Vector3(0.0, 0.0, 0.8), Vector3(0.0, 0.0, -0.8)]:
		out.append(at_center + house.global_basis * offset)
	return out


func _drop_pose(house: Node3D, point: Vector3) -> Variant:
	if not point.is_finite():
		return null
	var world := house.get_world_3d()
	if world == null:
		return null
	var from := Vector3(point.x, point.y + 1.0, point.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0, 1)
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var floor: Vector3 = hit.get("position", Vector3.ZERO)
	if not floor.is_finite():
		return null
	# The ray starts above the house roof on some plots; only use a floor inside this home.
	if house.has_method("contains") and not bool(house.call("contains", floor)):
		return null
	if house.get("floor_y") != null:
		var house_floor: float = (house.to_global(Vector3(0.0, float(house.get("floor_y")),
			0.0))).y
		if absf(floor.y - house_floor) > 0.2:
			return null
	var probe := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = STOOL_PROBE
	probe.shape = box
	probe.transform = Transform3D(Basis.IDENTITY, floor + Vector3.UP * 0.26)
	probe.collision_mask = 1
	if not world.direct_space_state.intersect_shape(probe, 1).is_empty():
		return null
	return Transform3D(Basis(Vector3.UP, randf() * TAU), floor + Vector3.UP * 0.03)


func _debug(text: String) -> void:
	if is_instance_valid(main) and main.has_method("debug"):
		main.call("debug", text)
