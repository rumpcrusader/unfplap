extends RefCounted
## Service: world
## Contract: docs/world.md
## Scope: world
## Import: world/service.gd, world/game.gd
## The one live-scene reader; it answers where and what, not whether.

const GAME := preload("res://mods/unfplap/world/game.gd")
const INTERACTOR_PATH := "res://player/interactor.gd"

## The live world root; null outside a world.
static var game: Node = null
## Anon's body; null before the player rig arrives and after a world close.
static var player: Node3D = null
## Handles resolved once for the current world and player.
static var _interactor: Node = null
static var _desktop: Node = null
static var _camera_cache: Camera3D = null
static var _camera_cache_at := 0.0


## The world entered. The resolved handles belong to the old one.
static func bind_world(host: Node) -> void:
	game = host
	_clear_handles()


## The player rig arrived.
static func bind_player(body: Node3D) -> void:
	player = body
	_clear_handles()


## The world closed: every read falls back to the unbound answers.
static func unbind() -> void:
	game = null
	player = null
	_clear_handles()


static func _clear_handles() -> void:
	_interactor = null
	_desktop = null
	_camera_cache = null
	_camera_cache_at = 0.0


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _root_viewport() -> Viewport:
	var tree := _tree()
	return tree.root if tree != null else null


## Anon's view camera: his own handle, else the game's found camera (cached for a second), else the
## active 3D camera. Every scan and frame reads it, so the lookup is cached.
static func camera() -> Camera3D:
	if not is_instance_valid(player):
		return null
	var direct := GAME.player_camera(player)
	if direct != null:
		return direct
	var now := Time.get_ticks_msec() * 0.001
	if is_instance_valid(_camera_cache) and now - _camera_cache_at < 1.0:
		return _camera_cache
	var found := GAME.find_camera(game, player) if is_instance_valid(game) else null
	if found != null:
		_camera_cache = found
		_camera_cache_at = now
		return found
	var viewport := _root_viewport()
	var current: Camera3D = viewport.get_camera_3d() if viewport != null else null
	_camera_cache = current
	_camera_cache_at = now
	return current


## The rig's reach node, cached per body.
static func interactor() -> Node:
	if is_instance_valid(_interactor):
		return _interactor
	if not is_instance_valid(player):
		return null
	for node: Node in player.find_children("*", "", true, false):
		var script: Variant = node.get_script()
		if script != null and str(script.resource_path) == INTERACTOR_PATH:
			_interactor = node
			return node
	return null


static func desktop() -> Node:
	if is_instance_valid(_desktop):
		return _desktop
	var tree := _tree()
	_desktop = tree.get_first_node_in_group("desktop_interactions") if tree != null else null
	return _desktop


## The rig body the game shows: the AnonPony avatar, else the rig's Body child, else the rig.
static func player_body() -> Node3D:
	if not is_instance_valid(player):
		return null
	var avatar := GAME.player_avatar(player)
	if avatar != null:
		return avatar
	var body := GAME.player_body_node(player)
	if body != null:
		return body
	return player


## The game's player property, read defensively so a rename returns null.
## The entry uses this when the rig arrives before `bind_player()`.
static func game_player() -> Node3D:
	if not is_instance_valid(game):
		return null
	return GAME.game_player(game)


## The mares as node handles, rebuilt on every read; scan cadence only.
static func mares() -> Array[Node3D]:
	if not is_instance_valid(game):
		return []
	return GAME.mares(game)


## The bed or couch under a point, from the world's own support collision.
static func bed_under(point: Vector3, exclude: RID = RID()) -> Node3D:
	var world: World3D = null
	if is_instance_valid(player):
		world = player.get_world_3d()
	if world == null:
		var viewport := _root_viewport()
		world = viewport.world_3d if viewport != null else null
	if world == null:
		return null
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return null
	for lift: float in [0.6, 0.35, 0.15]:
		var from := point + Vector3.UP * lift
		var query := PhysicsRayQueryParameters3D.create(from, point + Vector3.DOWN * 2.5, 1)
		if exclude.is_valid():
			query.exclude = [exclude]
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			continue
		var bed := GAME.bed_of(hit.get("collider"))
		if bed != null:
			var real := real_bed(bed)
			if real != null:
				return real
	return null


## The real bed behind a physics hit; a `SharedTorsoSupport` is a temporary child of it.
## Returning the support instead would leave the act with a freed node.
static func real_bed(node: Node) -> Node3D:
	if not is_instance_valid(node):
		return null
	if node.has_meta("shared_rest_support"):
		var parent := node.get_parent() as Node3D
		if is_instance_valid(parent):
			return parent
	var walk: Node = node
	while walk != null:
		if walk is Node3D and walk.has_meta("mattress_top"):
			return walk as Node3D
		walk = walk.get_parent()
	if node is Node3D and node.has_meta("soft_support"):
		return node as Node3D
	return null


static func bed_for_cradle(pony: Node3D) -> Node3D:
	if not is_instance_valid(pony):
		return null
	var exclude: RID = (pony as CollisionObject3D).get_rid() if pony is CollisionObject3D else RID()
	var down: Node3D = bed_under(pony.global_position, exclude)
	if down != null:
		return down
	var view: Camera3D = camera()
	if view == null:
		return null
	var space: PhysicsDirectSpaceState3D = view.get_world_3d().direct_space_state
	if space == null:
		return null
	var from := view.global_position
	var to := from - view.global_basis.z * 3.2
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	if exclude.is_valid():
		query.exclude = [exclude]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return null
	return real_bed(GAME.bed_of(hit.get("collider")))


## Whether another mare (not the target) already lies on the mattress.
static func bed_occupied(bed: Node3D, target: Node) -> bool:
	if not is_instance_valid(bed):
		return false
	var top := float(bed.get_meta("mattress_top", 0.6))
	var at := bed.to_global(Vector3(0.0, top, 0.0))
	for node: Node3D in mares():
		if not is_instance_valid(node) or node == target:
			continue
		if not node.has_method("posture_status"):
			continue
		var status: Dictionary = node.posture_status()
		if str(status.get("requested", "")) != "lie_down":
			continue
		if absf(node.global_position.y - at.y) > 0.55:
			continue
		if Vector2(node.global_position.x - at.x, node.global_position.z - at.z).length() > 1.3:
			continue
		return true
	return false


## True while Anon is seated on the bed or couch.
static func player_beside_bed(bed: Node3D) -> bool:
	if not is_instance_valid(player):
		return false
	var seat := GAME.seat_of(player)
	if seat == null:
		return true
	if not is_instance_valid(bed):
		return true
	if seat is Node3D and (seat as Node3D).get_parent() == bed:
		return true
	if seat is Node3D and (seat as Node3D).has_meta("couch"):
		var couch: Variant = (seat as Node3D).get_meta("couch")
		if is_instance_valid(couch):
			var bed_node: Variant = couch.get("_bed") if couch.get("_bed") != null else couch.get("bed_node")
			if bed_node == bed:
				return true
			if is_instance_valid(bed_node) and (bed_node as Node3D).is_ancestor_of(seat):
				return true
	return false


## True while a menu or panel owns the mouse: the tree paused or a known panel open.
## "Mouse is visible" is deliberately excluded: a closed menu would leave input dead.
static func menu_panel_open() -> bool:
	var tree := _tree()
	if tree != null and tree.paused:
		return true
	if not is_instance_valid(game):
		return false
	for key: String in ["save_menu", "settings_menu", "pause_menu"]:
		var panel := GAME.menu_panel(game, key)
		if is_instance_valid(panel) and bool(panel.get("opened")):
			return true
	var inventory := GAME.inventory(game)
	if inventory == null:
		return false
	if GAME.map_open(inventory):
		return true
	if GAME.case_visible(inventory):
		return true
	if GAME.customizer_opened(inventory):
		return true
	return GAME.inspector_active(inventory)


## True when the player should not interact with the world right now. Adds the mouse state to
## menu_panel_open(): the base game leaves the cursor visible while a menu owns the mouse.
static func menu_open() -> bool:
	if menu_panel_open():
		return true
	return Input.mouse_mode != Input.MOUSE_MODE_CAPTURED


## The eye is in a headset. There is no desktop cursor to capture, and the stock game leaves the
## mouse visible, so the "cursor is visible" gates must not read that as a menu owning the input.
static func headset_view() -> bool:
	if not is_instance_valid(game):
		return false
	return GAME.headset_view(game)


## Drop the merged LOD caches for a body whose shape changed and re-arm its near mesh, so the
## visible body is rebuilt from the new rig instead of the old shape's gather.
static func refresh_body_lod(pony: Node) -> void:
	if is_instance_valid(pony):
		GAME.refresh_body_lod(pony)


## The chat box refuses while the act holds the controls; open it past that lock.
static func open_act_chat() -> bool:
	if not is_instance_valid(game) or not is_instance_valid(player):
		return false
	return GAME.open_chat(game, player)
