extends RefCounted
## Service: world
## Scope: world
## Contract: docs/world.md
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
const INVENTORY_VIEW := preload("res://mods/unfplap/world/views/inventory.gd")
const MENU_VIEW := preload("res://mods/unfplap/world/views/menu.gd")
const RELATIONSHIP_VIEW := preload("res://mods/unfplap/world/views/relationship.gd")
const MODS_VIEW := preload("res://mods/unfplap/world/views/mods.gd")
const AFFECTION_VIEW := preload("res://mods/unfplap/world/views/affection.gd")
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

## The bound inventory node's briefcase store, world drops, shop item scene and quick-slot HUD.
class Inventory extends INVENTORY_VIEW:
	func _init(n: Node) -> void:
		super(n)

## The bound world root's named panels, HUD toast line and stock UI cue.
class Menu extends MENU_VIEW:
	func _init(n: Node) -> void:
		super(n)

## The scene's relationship runtime and bond store, bound by the facade; the pony-keyed members
## still take her node because the store she carries is not the receiver.
class Relationship extends RELATIONSHIP_VIEW:
	func _init(n: Node) -> void:
		super(n)

## The game's mods registry, bound to its autoload host: one mod's live state, its rows and folder.
class ModRegistry extends MODS_VIEW:
	func _init(n: Node) -> void:
		super(n)

## The scene's kisser, plus the affection, cuddle and carry writes the act makes; each write takes
## its own node because it is not the kisser.
class Affection extends AFFECTION_VIEW:
	func _init(n: Node) -> void:
		super(n)


## The live world root; null outside a world. Only the binds write it.
static var _game: Node = null
## Anon's body; null before the player rig arrives and after a world close.
static var _player: Node3D = null
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
static var _inventory_view: Inventory = null
static var _menu_view: Menu = null
static var _relationship_view: Relationship = null
static var _mods_view: ModRegistry = null
static var _affection_view: Affection = null


## The world entered. The resolved handles belong to the old one.
static func bind_world(host: Node) -> void:
	_game = host
	_clear_handles()


## The player rig arrived.
static func bind_player(body: Node3D) -> void:
	_player = body
	_clear_handles()


## The world closed: every read falls back to the unbound answers.
static func unbind() -> void:
	_game = null
	_player = null
	_clear_handles()


## True while both bound handles are live; false outside a world and after a close.
static func ready() -> bool:
	return is_instance_valid(_game) and is_instance_valid(_player)


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
	_inventory_view = null
	_menu_view = null
	_relationship_view = null
	_mods_view = null
	_affection_view = null


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _root_viewport() -> Viewport:
	var tree := _tree()
	return tree.root if tree != null else null


## Anon's view camera: his own handle, else the game's found camera (cached for a second), else the
## active 3D camera. Every scan and frame reads it, so the lookup is cached.
static func camera() -> Camera3D:
	if not is_instance_valid(_player):
		return null
	var direct := GAME.player_camera(_player)
	if direct != null:
		return direct
	var now := Time.get_ticks_msec() * 0.001
	if is_instance_valid(_camera_cache) and now - _camera_cache_at < 1.0:
		return _camera_cache
	var found := GAME.find_camera(_game, _player) if is_instance_valid(_game) else null
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
	if not is_instance_valid(_player):
		return null
	for node: Node in _player.find_children("*", "", true, false):
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
	if not is_instance_valid(_player):
		return null
	var avatar := GAME.player_avatar(_player)
	if avatar != null:
		return avatar
	var body := GAME.player_body_node(_player)
	if body != null:
		return body
	return _player


## The game's desktop presentation node, or null; the act parks it while it poses Anon's body.
static func presentation() -> Node:
	if not is_instance_valid(_game):
		return null
	return GAME.desktop_presentation(_game)


## The game's player property, read defensively so a rename returns null.
## The entry uses this when the rig arrives before `bind_player()`.
static func game_player() -> Node3D:
	if not is_instance_valid(_game):
		return null
	return GAME.game_player(_game)


## The bound rig itself, not the body the game shows for him.
static func player_rig() -> Node3D:
	return _player


## The bound world root, for the body-swap reparent; null outside a world.
static func world_root() -> Node:
	return _game if is_instance_valid(_game) else null


## The mares as node handles, rebuilt on every read; scan cadence only.
static func mares() -> Array[Node3D]:
	if not is_instance_valid(_game):
		return []
	return GAME.mares(_game)


## One world point's house, resolved through GAME.
static func house_at(at: Vector3) -> Node3D:
	return GAME.house_at(_tree(), at)


## The region id the witness rows record for a point; empty outside every region.
static func place_at(at: Vector3) -> String:
	return GAME.place_at(at)


## The house interior a node belongs to; null for any other node.
static func house_of(n: Node) -> Node3D:
	return GAME.house_of(n)


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
	if is_instance_valid(_player):
		world = _player.get_world_3d()
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
	if not is_instance_valid(_player):
		return false
	var seat := GAME.seat_of(_player)
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
	return inventory().item_scene(id)


## The shape ids the changelings note and the offline identity lookup walk; a copy, never the
## game's own map.
static func shape_ids() -> Array[String]:
	if not is_instance_valid(_game):
		return []
	return GAME.shape_ids(_game)


## Loads the catalogue's scene for one shape id; null when it has no entry.
static func shape_scene(id: String) -> PackedScene:
	if not is_instance_valid(_game):
		return null
	return GAME.shape_scene(_game, id)


## True while a menu or panel owns the mouse: the tree paused or a known panel open.
## "Mouse is visible" is deliberately excluded: a closed menu would leave input dead.
static func menu_panel_open() -> bool:
	var tree := _tree()
	if tree != null and tree.paused:
		return true
	if not is_instance_valid(_game):
		return false
	for key: String in ["save_menu", "settings_menu", "pause_menu"]:
		var panel := menu().panel(key)
		if is_instance_valid(panel) and bool(panel.get("opened")):
			return true
	var inventory := GAME.inventory(_game)
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


## Only a live world answers; the idle scans read it before queuing a line.
static func paused() -> bool:
	if not is_instance_valid(_game):
		return false
	var tree := _tree()
	return tree != null and tree.paused


## The eye is in a headset. There is no desktop cursor to capture, and the stock game leaves the
## mouse visible, so the "cursor is visible" gates must not read that as a menu owning the input.
static func headset_view() -> bool:
	if not is_instance_valid(_game):
		return false
	return GAME.headset_view(_game)


## Resolved by child name from the bound root; null when the scene lacks it.
static func interaction_hints() -> Node:
	if not is_instance_valid(_game):
		return null
	return GAME.interaction_hints(_game)


## The game's per-pony love level from the world context, with the cache's own -1 kept distinct
## from a row the cache does not hold.
static func bond_level(id: String) -> GAME.BondLevel:
	if not is_instance_valid(_game):
		return GAME.BondLevel.new()
	return GAME.bond_level(_game, id)


## Drop the merged LOD caches for a body whose shape changed and re-arm its near mesh, so the
## visible body is rebuilt from the new rig instead of the old shape's gather.
static func refresh_body_lod(pony: Node) -> void:
	if is_instance_valid(pony):
		GAME.refresh_body_lod(pony)


## The dock rump height for one body name and vertex height; NAN for an unknown body name.
static func dock_rump_z(body_name: String, y: float) -> float:
	return GAME.dock_rump_z(body_name, y)


## A body's velocity; anything that is not a live Node3D is left alone.
static func set_velocity(body: Node, value: Vector3) -> void:
	GAME.set_velocity(body as Node3D, value)


## The chat box refuses while the act holds the controls; open it past that lock.
static func open_chat() -> bool:
	if not is_instance_valid(_game) or not is_instance_valid(_player):
		return false
	return GAME.open_chat(_game, _player)


## Anon's rig view, cached for the bound player; an unbound facade answers the typed zeroes.
static func anon() -> Anon:
	var live := is_instance_valid(_player)
	if _anon is Anon and (not live or _anon._bound() == _player):
		return _anon
	_anon = Anon.new(_player if live else null)
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
	var view := Director.new(node if live else null, _game if is_instance_valid(_game) else null)
	_directors[key] = view
	return view


## The world context's story journal, cached per bound context node.
static func story() -> Story:
	var context: Node = GAME.world_context(_game) if is_instance_valid(_game) else null
	var live := is_instance_valid(context)
	var key := context.get_instance_id() if live else 0
	var found: Variant = _stories.get(key)
	if found is Story and (not live or found._bound() == context):
		return found
	var view := Story.new(context if live else null)
	_stories[key] = view
	return view


## The inventory node's briefcase and quick-slot HUD, resolved from the bound world and cached.
static func inventory() -> Inventory:
	var node: Node = GAME.inventory(_game) if is_instance_valid(_game) else null
	var live := is_instance_valid(node)
	if _inventory_view is Inventory and (not live or _inventory_view._bound() == node):
		return _inventory_view
	_inventory_view = Inventory.new(node if live else null)
	return _inventory_view


## The bound world root's menu and toast surface, cached for that root.
static func menu() -> Menu:
	var live := is_instance_valid(_game)
	if _menu_view is Menu and (not live or _menu_view._bound() == _game):
		return _menu_view
	_menu_view = Menu.new(_game if live else null)
	return _menu_view


## The scene's relationship runtime, resolved from the bound world and cached for it.
static func relationship() -> Relationship:
	var node: Node = GAME.relationship_runtime(_game) if is_instance_valid(_game) else null
	var live := is_instance_valid(node)
	if _relationship_view is Relationship and (not live or _relationship_view._bound() == node):
		return _relationship_view
	_relationship_view = Relationship.new(node if live else null)
	return _relationship_view


## The game's mods registry, cached for its autoload host; one registry serves every world.
static func mods() -> ModRegistry:
	var node := _mods_host()
	var live := is_instance_valid(node)
	if _mods_view is ModRegistry and (not live or _mods_view._bound() == node):
		return _mods_view
	_mods_view = ModRegistry.new(node if live else null)
	return _mods_view


## The scene's stock kisser, resolved from the bound world and cached for it.
static func affection() -> Affection:
	var node: Node = GAME.kisser_of(_game) if is_instance_valid(_game) else null
	var live := is_instance_valid(node)
	if _affection_view is Affection and (not live or _affection_view._bound() == node):
		return _affection_view
	_affection_view = Affection.new(node if live else null)
	return _affection_view


## The mods autoload is the registry the game installs at the root, so the facade resolves it.
static func _mods_host() -> Node:
	var tree := _tree()
	return tree.root.get_node_or_null("Mods") if tree != null else null


## The scene's director is a group node, so the facade resolves it here rather than each caller.
static func _director_node() -> Node:
	var tree := _tree()
	return tree.get_first_node_in_group("conversation_director") if tree != null else null
