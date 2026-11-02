extends RefCounted
## Adds a usable outdoor bed beside the Golden Oak Library entrance. The guest bed inside is
## occasionally hard for the navigator to reach, so this gives the act and cuddles a second
## pathable bed outside. The bed is a normal pony-bed node: Seating installs its shared-bed rest
## on first aim, exactly like any other bed.

const KIT := preload("res://world/buildings/golden_oak/furniture_kit.gd")
const PLACE := "house:golden_oak_library"


static func install(game: Node) -> Node3D:
	if not is_instance_valid(game) or not game.is_inside_tree():
		return null
	if game.has_meta("unfplap_outdoor_bed"):
		var existing: Variant = game.get_meta("unfplap_outdoor_bed")
		if is_instance_valid(existing):
			return existing as Node3D
	var home := _golden_oak(game)
	if home == null:
		return null
	var kit := KIT.new()
	var right: Vector3 = home.global_basis.x.normalized()
	var back: Vector3 = home.global_basis.z.normalized()
	var spot: Vector3 = home.outside() + right * 3.0 + back * 0.6
	var world: World3D = home.get_world_3d()
	if world != null:
		var query := PhysicsRayQueryParameters3D.create(
			spot + Vector3.UP * 2.0, spot + Vector3.DOWN * 4.0, 1)
		var hit: Dictionary = world.direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			spot = hit.get("position", spot)
	var bed: Node3D = kit.bed(spot, home.global_rotation.y, "OutdoorGoldenOakBed", false)
	bed.name = "UnfplapOutdoorBed"
	if not bed.has_meta("mattress_top"):
		bed.set_meta("mattress_top", 0.6)
	bed.add_to_group("unfplap_outdoor_bed")
	bed.set_meta("ai_label", "bed")
	game.add_child(bed)
	bed.global_transform = Transform3D(Basis(Vector3.UP, home.global_rotation.y), spot)
	game.set_meta("unfplap_outdoor_bed", bed)
	return bed


static func _golden_oak(game: Node) -> Node3D:
	for node: Variant in game.get_tree().get_nodes_in_group("house_interiors"):
		if not is_instance_valid(node) or not node is Node3D:
			continue
		var house := node as Node3D
		if not house.has_method("place_id") or not house.has_method("outside"):
			continue
		if str(house.call("place_id")) == PLACE:
			return house
	return null
