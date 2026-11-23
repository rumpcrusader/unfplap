extends RefCounted
## The bed reads the rest service places and rejoins through: the game's own couch rest, the
## couch that owns a bed, and the mattress anchor a placement lands on.

const WORLD := preload("res://mods/unfplap/world/api.gd")


## One resolved game couch rest: the live node the rejoin seats through, or the guest transform a
## bed rest reports. A missing member answers its typed zero.
class RestState extends RefCounted:
	var node: Node3D = null
	var guest := Transform3D(Basis.IDENTITY, Vector3.INF)

	static func of_node(value: Node3D) -> RestState:
		var out := RestState.new()
		out.node = value
		return out

	static func of_guest(value: Transform3D) -> RestState:
		var out := RestState.new()
		out.guest = value
		return out

	func valid() -> bool:
		return is_instance_valid(node)

	func has_guest() -> bool:
		return guest.origin.is_finite() and guest.origin.length_squared() > 0.0

	func seats() -> Array[Node3D]:
		return WORLD.bed(node).couch_seats()

	func open() -> bool:
		return WORLD.bed(node).couch_open()

	func invite(target: Node3D, seat: Node3D) -> bool:
		return WORLD.bed(node).couch_invite(target, seat)

	func approach(seat: Node3D) -> Vector3:
		return WORLD.bed(node).couch_approach(seat)

	func mare_fits() -> bool:
		return WORLD.bed(node).couch_mare_fits()

	func cooldown_until(target: Node3D) -> int:
		return WORLD.bed(node).couch_cooldown_until(target)


## The place on the mattress: the game's own pony transform for the guest seat when it exists,
## otherwise the mattress top at the side Anon is on.
static func anchor(pony: Node3D, bed_node: Node3D, player: Node3D) -> Transform3D:
	if not is_instance_valid(pony):
		return Transform3D.IDENTITY
	if is_instance_valid(bed_node):
		var shared := shared_rest(pony, bed_node)
		if shared != null and shared.has_guest():
			return shared.guest
	var fallback := 0.6
	if is_instance_valid(bed_node) and bed_node.has_meta("mattress_top"):
		fallback = float(bed_node.get_meta("mattress_top"))
	var center: Vector3 = bed_node.global_position if is_instance_valid(bed_node) else pony.global_position
	var top: float = center.y
	if is_instance_valid(bed_node):
		var points: Array[Vector3] = [bed_node.to_global(Vector3(0.18, 0.0, 0.0)),
			bed_node.to_global(Vector3(-0.18, 0.0, 0.0))]
		top = WORLD.bed(bed_node).surface_top(points, bed_node.to_global(Vector3(0.0, fallback, 0.0)).y)
		center = Vector3(bed_node.global_position.x, top, bed_node.global_position.z)
	var player_at: Vector3 = player.global_position if is_instance_valid(player) else pony.global_position
	var side := Vector3.FORWARD
	if is_instance_valid(bed_node):
		side = bed_node.global_basis.x
		side.y = 0.0
	if side.length_squared() < 0.0001:
		side = player_at - center
		side.y = 0.0
	side = side.normalized()
	var across := side * signf((player_at - center).dot(side)) * 0.25
	var along: Vector3 = -pony.global_basis.z
	if is_instance_valid(bed_node):
		along = -bed_node.global_basis.z
	elif is_instance_valid(player):
		along = -player.global_basis.z
	along.y = 0.0
	if along.length_squared() < 0.0001:
		along = player_at - center
		along.y = 0.0
	along = along.normalized()
	var at: Vector3 = center + across
	at.y = top + 0.02
	return Transform3D(Basis.looking_at(along, Vector3.UP), at)


## The game's own bed-rest place for a pony lying beside Anon. Using it keeps her along the
## mattress (not across it) and on the drawn bedding.
static func shared_rest(pony: Node3D, bed_node: Node3D) -> RestState:
	if not is_instance_valid(bed_node) or not is_instance_valid(pony):
		return null
	var tree: SceneTree = pony.get_tree()
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group("couches"):
		if not node is Node3D or node.get("bed_node") != bed_node:
			continue
		if not node.has_method("pony_transform"):
			continue
		var couch := WORLD.bed(node)
		var seats := couch.couch_seats()
		if seats.size() < 2:
			continue
		var rest := couch.couch_pony_transform(seats[1])
		if not rest.origin.is_finite():
			continue
		if rest.origin.length_squared() < 0.01 \
				or rest.origin.distance_to(bed_node.global_position) > 4.0:
			continue
		return RestState.of_guest(rest)
	return null


## The game's live rest that owns this bed (`world/relationships/shared_bed.gd`).
## `shared_rest()` only returns her transform; the rejoin needs the seats and the invite entry.
static func rest_for(pony: Node3D, bed_node: Node3D) -> RestState:
	if not is_instance_valid(bed_node) or not is_instance_valid(pony):
		return null
	var tree: SceneTree = pony.get_tree()
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group("couches"):
		if not node is Node3D or not node.has_method("invite"):
			continue
		if node.get("_bed") != bed_node and node.get("bed_node") != bed_node:
			continue
		if WORLD.bed(node).couch_seats().size() >= 2:
			return RestState.of_node(node)
	return null
