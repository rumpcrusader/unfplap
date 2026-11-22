extends Node
## Finds pickable footstools in the world when the player owns none. See docs/stool.md.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const ITEM := preload("res://mods/unfplap/stool/item.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const SERVICE := preload("res://mods/unfplap/stool/service.gd")
const SPAWN_COUNT := 3
const RANGE_M := 80.0
const RETRY_S := 2.0
const STOOL_PROBE := Vector3(0.62, 0.46, 0.5)

var system: SERVICE = null
var _clock := 0.0
var _started := false
var _spawned := 0
var _used: Dictionary = {}
var _wait_logged := false
var _full_logged := false


func setup(system_node: SERVICE) -> void:
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
	if not is_instance_valid(system) or not system.enabled():
		return
	_clock += delta
	if _clock < RETRY_S:
		return
	_clock = 0.0
	_tick()


func _tick() -> void:
	if not WORLD.ready():
		return
	var tree := get_tree()
	if tree == null or tree.paused:
		return
	if PONIES.act_running():
		return
	var player := WORLD.game_player()
	if not is_instance_valid(player):
		return
	var briefcase := WORLD.inventory()
	var store := briefcase.store()
	if store == null:
		return
	if not _started:
		if system.owned_count(store) > 0:
			_spawned = SPAWN_COUNT
			return
	if _spawned >= SPAWN_COUNT:
		return
	var houses: Array[GAME.HOUSE] = []
	for node: Variant in tree.get_nodes_in_group("house_interiors"):
		if not node is Node3D:
			continue
		var house := GAME.house_of(node as Node)
		if house == null:
			continue
		var place := house.place_id()
		if place.is_empty() or _used.has(place):
			continue
		if house.global_position.distance_to(player.global_position) > RANGE_M:
			continue
		houses.append(house)
	if houses.is_empty():
		if not _wait_logged:
			_wait_logged = true
			LOG.debug("stool supply waiting for a loaded house")
		return
	houses.shuffle()
	for house: GAME.HOUSE in houses:
		if _spawned >= SPAWN_COUNT:
			break
		if _place_in(house, briefcase):
			_spawned += 1
			_started = true
	if _spawned >= SPAWN_COUNT:
		LOG.debug("stool supply spawned=%d", [_spawned])


func _place_in(house: GAME.HOUSE, briefcase: WORLD.Inventory) -> bool:
	for point: Vector3 in _spots(house):
		var pose := _drop_pose(house, point)
		if not pose.origin.is_finite():
			continue
		var item := briefcase.spawn_drop(ITEM.ID, pose)
		if is_instance_valid(item):
			_used[house.place_id()] = true
			LOG.debug("stool supply house=%s at=%s", [house.place_id(), str(pose.origin)])
			return true
		if not _full_logged:
			_full_logged = true
			LOG.debug("stool supply blocked reason=briefcase_full")
		return false
	return false


func _spots(house: GAME.HOUSE) -> Array[Vector3]:
	var at_inside := house.inside()
	var at_center := house.center()
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


func _drop_pose(house: GAME.HOUSE, point: Vector3) -> Transform3D:
	if not point.is_finite():
		return Transform3D(Basis.IDENTITY, Vector3.INF)
	var world := house.get_world_3d()
	if world == null:
		return Transform3D(Basis.IDENTITY, Vector3.INF)
	var from := Vector3(point.x, point.y + 1.0, point.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0, 1)
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3.INF)
	var floor: Vector3 = hit.get("position", Vector3.ZERO)
	if not floor.is_finite():
		return Transform3D(Basis.IDENTITY, Vector3.INF)
	# The ray starts above the house roof on some plots; only use a floor inside this home.
	if not house.contains(floor):
		return Transform3D(Basis.IDENTITY, Vector3.INF)
	var house_floor: float = (house.to_global(Vector3(0.0, house.floor_y, 0.0))).y
	if absf(floor.y - house_floor) > 0.2:
		return Transform3D(Basis.IDENTITY, Vector3.INF)
	var probe := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = STOOL_PROBE
	probe.shape = box
	probe.transform = Transform3D(Basis.IDENTITY, floor + Vector3.UP * 0.26)
	probe.collision_mask = 1
	if not world.direct_space_state.intersect_shape(probe, 1).is_empty():
		return Transform3D(Basis.IDENTITY, Vector3.INF)
	return Transform3D(Basis(Vector3.UP, randf() * TAU), floor + Vector3.UP * 0.03)
