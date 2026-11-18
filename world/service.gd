extends RefCounted
## Service: world
## Contract: docs/world.md
## Scope: world
## Import: world/service.gd only
##
##   const WORLD := preload("res://mods/unfplap/world/service.gd")
##   if WORLD.menu_open():
##       return
##
## The one place a service reads the live scene: the world root, Anon's body and the reads derived
## from them. It answers where and what, never whether, so every rule stays with its caller. The
## state is bound by the entry on world/player enter and cleared on world close.

const HYBRID_NEAR_MESH := preload("res://world/characters/hybrid_mare/hybrid_near_mesh.gd")
const HYBRID_FAR_MESH := preload("res://world/characters/hybrid_mare/hybrid_far_mesh.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")
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
	var direct: Variant = player.get("camera")
	if direct is Camera3D and is_instance_valid(direct):
		return direct
	var now := Time.get_ticks_msec() * 0.001
	if is_instance_valid(_camera_cache) and now - _camera_cache_at < 1.0:
		return _camera_cache
	if is_instance_valid(game) and game.has_method("_find_camera"):
		var found: Variant = game.call("_find_camera", player)
		if found is Camera3D and is_instance_valid(found):
			_camera_cache = found
			_camera_cache_at = now
			return found
	var viewport := _root_viewport()
	var current: Camera3D = viewport.get_camera_3d() if viewport != null else null
	_camera_cache = current
	_camera_cache_at = now
	return current


## The player rig's reach node, resolved once per body.
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
	var form: Variant = player.get("form_driver")
	if form != null and is_instance_valid(form):
		var avatar: Variant = form.get("avatar")
		if avatar is Node3D and is_instance_valid(avatar):
			return avatar
	var body: Variant = player.find_child("Body", true, false)
	if body is Node3D and is_instance_valid(body):
		return body
	return player


## The world's live mare list, which the game owns and mutates in place.
static func mares() -> Array:
	if is_instance_valid(game):
		var list: Variant = game.get("mares")
		if list is Array:
			return list
	return []


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
		var bed: Node3D = MATTRESS.bed_of(hit.get("collider"))
		if bed != null:
			var real := real_bed(bed)
			if real != null:
				return real
	return null


## The actual bed/couch behind a physics hit. A `SharedTorsoSupport` is a temporary child of the
## bed that also carries `soft_support`; using it as the bed leaves the act with a freed node
## once the cuddle support is removed.
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
	return real_bed(MATTRESS.bed_of(hit.get("collider")))


## Another mare already lying on the mattress top, excluding the target.
static func bed_occupied(bed: Node3D, target: Node) -> bool:
	if not is_instance_valid(bed):
		return false
	var top := float(bed.get_meta("mattress_top", 0.6))
	var at := bed.to_global(Vector3(0.0, top, 0.0))
	for node: Variant in mares():
		if not is_instance_valid(node) or node == target:
			continue
		var actor: Node3D = node as Node3D
		if actor == null or not actor.has_method("posture_status"):
			continue
		var status: Dictionary = actor.posture_status()
		if str(status.get("requested", "")) != "lie_down":
			continue
		if absf(actor.global_position.y - at.y) > 0.55:
			continue
		if Vector2(actor.global_position.x - at.x, actor.global_position.z - at.z).length() > 1.3:
			continue
		return true
	return false


## True while Anon's seat is the bed or couch itself.
static func player_beside_bed(bed: Node3D) -> bool:
	if not is_instance_valid(player):
		return false
	var seat: Variant = player.get("seat")
	if seat == null or not is_instance_valid(seat):
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
			if is_instance_valid(bed_node) and (bed_node as Node3D).is_ancestor_of(seat as Node):
				return true
	return false


## True while a menu or panel owns the mouse: the tree is paused or a known UI panel is open.
## Deliberately excludes "the mouse is visible" so a menu that leaves the cursor visible cannot
## keep offers and act input dead after it closes. Use menu_open() for "can he interact now".
static func menu_panel_open() -> bool:
	var tree := _tree()
	if tree != null and tree.paused:
		return true
	if not is_instance_valid(game):
		return false
	for key: String in ["save_menu", "settings_menu", "pause_menu"]:
		var panel: Variant = game.get(key)
		if is_instance_valid(panel) and bool(panel.get("opened")):
			return true
	var inventory: Variant = game.get("inventory")
	if not is_instance_valid(inventory):
		return false
	if inventory.has_method("_map_open") and bool(inventory.call("_map_open")):
		return true
	var case: Variant = inventory.get("case")
	if is_instance_valid(case) and bool(case.get("visible")):
		return true
	var customizer: Variant = inventory.get("customizer")
	if is_instance_valid(customizer) and bool(customizer.get("opened")):
		return true
	var inspector: Variant = inventory.get("inspector")
	if is_instance_valid(inspector) and bool(inspector.get("active")):
		return true
	return false


## True when the player should not interact with the world right now. Adds the mouse state to
## menu_panel_open(): the base game leaves the cursor visible while a menu owns the mouse.
static func menu_open() -> bool:
	if menu_panel_open():
		return true
	return Input.mouse_mode != Input.MOUSE_MODE_CAPTURED


## The eye is in a headset. There is no desktop cursor to capture, and the stock game leaves the
## mouse visible, so the "cursor is visible" gates must not read that as a menu owning the input.
static func headset_view() -> bool:
	return is_instance_valid(game) and bool(game.get("headset_view"))


## Drop the merged LOD caches for a body whose shape changed and re-arm its near mesh, so the
## visible body is rebuilt from the new rig instead of the old shape's gather.
static func refresh_body_lod(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	# Only a hybrid body has merged LOD caches; a plain or half-built node has nothing to drop.
	var identity: Variant = pony.get("identity")
	if not identity is Resource:
		return
	HYBRID_NEAR_MESH.cache.erase(HYBRID_NEAR_MESH.key(pony))
	var far_key: String = HYBRID_FAR_MESH._id(pony)
	HYBRID_FAR_MESH.cache.erase(far_key)
	HYBRID_FAR_MESH.shadow_cache.erase(far_key)
	HYBRID_FAR_MESH.eyes_cache.erase(far_key)
	if not pony.has_method("set_near_mesh"):
		return
	var enabled: Variant = pony.get("near_mesh_enabled")
	if enabled != null and not bool(enabled):
		return
	pony.call("set_near_mesh", false)
	pony.call("set_near_mesh", true)


## The chat box refuses while the act holds the controls; open it past that lock.
static func open_act_chat() -> bool:
	if not is_instance_valid(game) or not is_instance_valid(player):
		return false
	var chat: Node = game.get_node_or_null("ChatBox")
	if chat == null or not chat.has_method("_open"):
		return false
	var held: Variant = player.get("controls_locked")
	player.set("controls_locked", false)
	var opened := bool(chat.call("_open"))
	player.set("controls_locked", held)
	if opened:
		chat.set("_lock_owned", false)
	return opened
