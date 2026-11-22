extends RefCounted
## Service: world
## Contract: docs/world.md
## Scope: world
## Import: world/api.gd, world/game.gd
## The one live-scene reader; it answers where and what, not whether.

const GAME := preload("res://mods/unfplap/world/game.gd")
const PONY_VIEW := preload("res://mods/unfplap/world/views/pony.gd")
const NAVIGATOR_VIEW := preload("res://mods/unfplap/world/views/navigator.gd")
const FACE_VIEW := preload("res://mods/unfplap/world/views/face.gd")
const WINGS_VIEW := preload("res://mods/unfplap/world/views/wings.gd")
const FLANK_VIEW := preload("res://mods/unfplap/world/views/flank.gd")
const ANON_VIEW := preload("res://mods/unfplap/world/views/anon.gd")
const BED_VIEW := preload("res://mods/unfplap/world/views/bed.gd")
const DIRECTOR_VIEW := preload("res://mods/unfplap/world/views/director.gd")
const STORY_VIEW := preload("res://mods/unfplap/world/views/story.gd")
const INTERACTOR_PATH := "res://player/interactor.gd"

## One pony's body reads and writes, bound to her node; every member answers typed zeroes when the
## node is gone, so a caller that keeps a view across a despawn never crashes.
class Pony extends PONY_VIEW:
	func _init(n: Node) -> void:
		super(n)

## One pony's navigator leases, travel and facing, bound to her node.
class Navigator extends NAVIGATOR_VIEW:
	func _init(n: Node) -> void:
		super(n)

## Her expression controller, dialogue face and blush, bound to her node.
class Face extends FACE_VIEW:
	func _init(n: Node) -> void:
		super(n)

## Her wing node and the excitement Beat that owns the stock spread, bound to either one.
class Wings extends WINGS_VIEW:
	func _init(n: Node) -> void:
		super(n)

## Her flank patch and touch body: the hull sync, the jiggle surface and its fold.
class Flank extends FLANK_VIEW:
	func _init(n: Node) -> void:
		super(n)

## Anon's rig, form driver, controls, eye line and seated state, bound to the facade's player.
class Anon extends ANON_VIEW:
	func _init(n: Node3D) -> void:
		super(n)

## A bed, its couch/rest, one of its seats or the seating system: the rest family's rows, bound.
class Bed extends BED_VIEW:
	func _init(n: Node) -> void:
		super(n)

## The scene's conversation director with the world context it belongs to: the routing, the voice,
## the impressions and the authored-line host, plus the subsystem and audio nodes its members take.
class Director extends DIRECTOR_VIEW:
	func _init(n: Node, world: Node) -> void:
		super(n, world)

## The world context's story journal, its line store and its recent events, bound by the facade.
class Story extends STORY_VIEW:
	func _init(n: Node) -> void:
		super(n)


## The live world root; null outside a world.
static var game: Node = null
## Anon's body; null before the player rig arrives and after a world close.
static var player: Node3D = null
## Handles resolved once for the current world and player.
static var _interactor: Node = null
static var _desktop: Node = null
static var _camera_cache: Camera3D = null
static var _camera_cache_at := 0.0
## One view per bound node, dropped by every bind so no old body survives.
static var _ponies: Dictionary = {}
static var _navigators: Dictionary = {}
static var _faces: Dictionary = {}
static var _wings: Dictionary = {}
static var _flanks: Dictionary = {}
static var _beds: Dictionary = {}
static var _directors: Dictionary = {}
static var _stories: Dictionary = {}
static var _anon: Anon = null


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


## True while both bound handles are live; false outside a world and after a close.
static func ready() -> bool:
	return is_instance_valid(game) and is_instance_valid(player)


static func _clear_handles() -> void:
	_interactor = null
	_desktop = null
	_camera_cache = null
	_camera_cache_at = 0.0
	_ponies.clear()
	_navigators.clear()
	_faces.clear()
	_wings.clear()
	_flanks.clear()
	_beds.clear()
	_directors.clear()
	_stories.clear()
	_anon = null


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


## The bound rig itself, not the body the game shows for him.
static func player_rig() -> Node3D:
	return player


## The mares as node handles, rebuilt on every read; scan cadence only.
static func mares() -> Array[Node3D]:
	if not is_instance_valid(game):
		return []
	return GAME.mares(game)


## One world point's house, resolved through GAME.
static func house_at(at: Vector3) -> Node3D:
	return GAME.house_at(_tree(), at)


## True when an idle scan may run: a live tree that is not paused, and a captured desktop cursor or
## a headset. The player and game handles are the scan's own guard.
static func can_interact() -> bool:
	var tree := _tree()
	if tree == null or tree.paused:
		return false
	if DisplayServer.get_name() != "headless" and not headset_view() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	return true


## True when Anon currently presents as a pony; a scan reads it once.
static func player_is_pony() -> bool:
	return anon().form_is_pony()


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


## A bed the house creates on demand, not one a probe found.
static func ensure_bed(house: Node, kind: String = "") -> Node3D:
	return GAME.ensure_bed(house as Node3D, kind)


## The shop's packed item scene; null when the shop has no such item.
static func shop_item(id: String) -> PackedScene:
	return GAME.shop_item_scene(id)


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


## The game's own setting by its dotted key; empty when no settings node is reachable.
static func game_setting(key: String) -> String:
	if not is_instance_valid(game):
		return ""
	var tree := _tree()
	if tree == null:
		return ""
	return GAME.setting_string(tree.root.get_node_or_null("Settings"), key)


## Drop the merged LOD caches for a body whose shape changed and re-arm its near mesh, so the
## visible body is rebuilt from the new rig instead of the old shape's gather.
static func refresh_body_lod(pony: Node) -> void:
	if is_instance_valid(pony):
		GAME.refresh_body_lod(pony)


## A body's velocity; anything that is not a live Node3D is left alone.
static func set_velocity(body: Node, value: Vector3) -> void:
	GAME.set_velocity(body as Node3D, value)


## The chat box refuses while the act holds the controls; open it past that lock.
static func open_chat() -> bool:
	if not is_instance_valid(game) or not is_instance_valid(player):
		return false
	return GAME.open_chat(game, player)


## Anon's rig view, cached for the bound player; an unbound facade answers the typed zeroes.
static func anon() -> Anon:
	var live := is_instance_valid(player)
	if _anon is Anon and (not live or _anon._bound() == player):
		return _anon
	_anon = Anon.new(player if live else null)
	return _anon


## One pony's body, cached per bound node; an invalid node answers the accessors' typed zeroes.
static func pony(n: Node) -> Pony:
	var live := is_instance_valid(n)
	var key := n.get_instance_id() if live else 0
	var found: Variant = _ponies.get(key)
	if found is Pony and (not live or found._bound() == n):
		return found
	var view := Pony.new(n if live else null)
	_ponies[key] = view
	return view


## Her navigator lease surface, cached per bound node.
static func navigator(n: Node) -> Navigator:
	var live := is_instance_valid(n)
	var key := n.get_instance_id() if live else 0
	var found: Variant = _navigators.get(key)
	if found is Navigator and (not live or found._bound() == n):
		return found
	var view := Navigator.new(n if live else null)
	_navigators[key] = view
	return view


## Her face and blush, cached per bound node.
static func face(n: Node) -> Face:
	var live := is_instance_valid(n)
	var key := n.get_instance_id() if live else 0
	var found: Variant = _faces.get(key)
	if found is Face and (not live or found._bound() == n):
		return found
	var view := Face.new(n if live else null)
	_faces[key] = view
	return view


## Her wing node, or the excitement Beat that owns it, cached per bound node.
static func wings(n: Node) -> Wings:
	var live := is_instance_valid(n)
	var key := n.get_instance_id() if live else 0
	var found: Variant = _wings.get(key)
	if found is Wings and (not live or found._bound() == n):
		return found
	var view := Wings.new(n if live else null)
	_wings[key] = view
	return view


## Her flank patch or touch body, cached per bound node.
static func flank(n: Node) -> Flank:
	var live := is_instance_valid(n)
	var key := n.get_instance_id() if live else 0
	var found: Variant = _flanks.get(key)
	if found is Flank and (not live or found._bound() == n):
		return found
	var view := Flank.new(n if live else null)
	_flanks[key] = view
	return view


## A bed, its couch/rest, one of its seats or the seating system, cached per bound node.
static func bed(n: Node) -> Bed:
	var live := is_instance_valid(n)
	var key := n.get_instance_id() if live else 0
	var found: Variant = _beds.get(key)
	if found is Bed and (not live or found._bound() == n):
		return found
	var view := Bed.new(n if live else null)
	_beds[key] = view
	return view


## The scene's conversation director, cached per scene director. It belongs to the bound world, so
## the world context and the impressions it reads are that world's own.
static func director() -> Director:
	var node := _director_node()
	var live := is_instance_valid(node)
	var key := node.get_instance_id() if live else 0
	var found: Variant = _directors.get(key)
	if found is Director and (not live or found._bound() == node):
		return found
	var view := Director.new(node if live else null, game if is_instance_valid(game) else null)
	_directors[key] = view
	return view


## The world context's story journal, cached per bound context node.
static func story() -> Story:
	var context: Node = GAME.world_context(game) if is_instance_valid(game) else null
	var live := is_instance_valid(context)
	var key := context.get_instance_id() if live else 0
	var found: Variant = _stories.get(key)
	if found is Story and (not live or found._bound() == context):
		return found
	var view := Story.new(context if live else null)
	_stories[key] = view
	return view


## The scene's director is a group node, so the facade resolves it here rather than each caller.
static func _director_node() -> Node:
	var tree := _tree()
	return tree.get_first_node_in_group("conversation_director") if tree != null else null
