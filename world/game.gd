extends RefCounted
## Service: world
## Contract: docs/world.md `## Base-game access`
## Stateless readers for the base-game and presentation members; the scene root is an argument.

const MATTRESS := preload("res://world/life/couch/mattress.gd")
const COUCH_EXIT := preload("res://world/life/couch/exit_space.gd")
const SHARED_BED := preload("res://world/relationships/shared_bed.gd")
const HYBRID_NEAR_MESH := preload("res://world/characters/hybrid_mare/hybrid_near_mesh.gd")
const HYBRID_FAR_MESH := preload("res://world/characters/hybrid_mare/hybrid_far_mesh.gd")
const SHOP_ITEMS := preload("res://world/shop/shop_items.gd")
const HOUSE := preload("res://world/buildings/house_interior.gd")
const AI_CONFIG := preload("res://world/ai/ai_config.gd")
const CHATTER := preload("res://world/ai/chatter_voice.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const OUTLINE_EXCLUSION := preload("res://world/post_outline_exclusion.gd")
const DOCK_TAIL_MOUNT := preload("res://world/characters/hybrid_mare/dock_tail_mount.gd")
const HYBRID_DOCK := preload("res://world/characters/hybrid_mare/hybrid_dock.gd")
const MENU_PICKER := preload("res://world/ui/menu_picker.gd")
const INTERACTION_SOUNDS := preload("res://world/audio/interaction_sounds.gd")


## The game's dock-fit document; the tail seat owns a copy and nudges it before a rebuild.
class DockFit extends RefCounted:
	var data: Dictionary = {}


## The eye is in a headset; absent reads as false.
static func headset_view(game: Node) -> bool:
	if not is_instance_valid(game):
		return false
	return game.get("headset_view") == true


## The game's player property; null when absent or not a body.
static func game_player(game: Node) -> Node3D:
	if not is_instance_valid(game):
		return null
	var body: Variant = game.get("player")
	if body is Node3D and is_instance_valid(body):
		return body
	return null


## A typed copy of the live mare list: rebuilds on every call, so scan only, never per frame.
static func mares(game: Node) -> Array[Node3D]:
	var copy: Array[Node3D] = []
	if not is_instance_valid(game):
		return copy
	var list: Variant = game.get("mares")
	if not list is Array:
		return copy
	for node: Variant in list:
		if node is Node3D and is_instance_valid(node):
			copy.append(node)
	return copy


## The scene's own camera search, read only while the scene still exposes it.
static func find_camera(game: Node, player: Node3D) -> Camera3D:
	if not is_instance_valid(game) or not is_instance_valid(player):
		return null
	if not game.has_method("_find_camera"):
		return null
	var found: Variant = game.call("_find_camera", player)
	if found is Camera3D and is_instance_valid(found):
		return found
	return null


## The camera Anon's rig holds; null without a live one.
static func player_camera(player: Node3D) -> Camera3D:
	if not is_instance_valid(player):
		return null
	var view: Variant = player.get("camera")
	if view is Camera3D and is_instance_valid(view):
		return view
	return null


## The AnonPony avatar the form driver shows; null for a rig without one.
static func player_avatar(player: Node3D) -> Node3D:
	if not is_instance_valid(player):
		return null
	var form: Variant = player.get("form_driver")
	if form == null or not is_instance_valid(form):
		return null
	var avatar: Variant = form.get("avatar")
	if avatar is Node3D and is_instance_valid(avatar):
		return avatar
	return null


## The rig's Body child, wherever it sits; null without one.
static func player_body_node(player: Node3D) -> Node3D:
	if not is_instance_valid(player):
		return null
	var body: Variant = player.find_child("Body", true, false)
	if body is Node3D and is_instance_valid(body):
		return body
	return null


## The seat Anon's rig is held on; null when he stands.
static func seat_of(player: Node3D) -> Node:
	if not is_instance_valid(player):
		return null
	var seat: Variant = player.get("seat")
	if seat is Node and is_instance_valid(seat):
		return seat
	return null


## Whether the game holds Anon's controls; an absent flag reads as unlocked.
static func controls_locked(player: Node3D) -> bool:
	if not is_instance_valid(player):
		return false
	return player.get("controls_locked") == true


## Release or hold Anon's controls; nothing happens without a rig.
static func set_controls_locked(player: Node3D, locked: bool) -> void:
	if is_instance_valid(player):
		player.set("controls_locked", locked)


## The desktop presentation's own show switch; a node without the op is left alone.
static func set_presentation_enabled(presentation: Node, on: bool) -> void:
	if is_instance_valid(presentation) and presentation.has_method("set_enabled"):
		presentation.call("set_enabled", on)


## Make a reclined Anon stand up; nothing happens without the body's own op.
static func force_stand_up(player: Node) -> void:
	if is_instance_valid(player) and player.has_method("force_stand_up"):
		player.call("force_stand_up")


## One game setting by its dotted key; empty when the settings node has no reader.
static func setting_string(settings: Node, key: String) -> String:
	if not is_instance_valid(settings) or not settings.has_method("get_value"):
		return ""
	return str(settings.call("get_value", key))


## The game's Anon height scale; NAN when the settings node cannot answer.
static func anon_height(settings: Node) -> float:
	if not is_instance_valid(settings) or not settings.has_method("anon_height_scale"):
		return NAN
	return float(settings.call("anon_height_scale"))


## One mod's live state section, as the registry keeps the reference; empty without the reader.
static func mods_state(mods: Node, id: String) -> ModState:
	var out := ModState.new()
	if not is_instance_valid(mods) or not mods.has_method("state"):
		return out
	var state: Variant = mods.call("state", id)
	if state is Dictionary:
		out.rows = state
	return out


## Whether the mod registry reports one mod active; false without the reader.
static func mod_active(mods: Node, id: String) -> bool:
	if not is_instance_valid(mods) or id.is_empty() or not mods.has_method("is_active"):
		return false
	return bool(mods.call("is_active", id))


## Ask the mod registry to persist its state; nothing happens without the writer.
static func mods_save(mods: Node) -> void:
	if is_instance_valid(mods) and mods.has_method("save_changed"):
		mods.call("save_changed")


## The mods host's installed pack rows; empty without the op.
static func mods_list(mods: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_instance_valid(mods) or not mods.has_method("list"):
		return out
	var rows: Variant = mods.call("list")
	if not rows is Array:
		return out
	for row: Variant in rows:
		if row is Dictionary:
			out.append(row)
	return out


## One mod's data folder from the registry; empty when the host has no folder reader.
static func mods_data_folder(mods: Node, id: String) -> String:
	if not is_instance_valid(mods) or not mods.has_method("data_folder"):
		return ""
	return str(mods.call("data_folder", id))


## One named game panel; the caller decides what an open panel means.
static func menu_panel(game: Node, key: StringName) -> Node:
	if not is_instance_valid(game):
		return null
	var panel: Variant = game.get(key)
	if panel is Node and is_instance_valid(panel):
		return panel
	return null


## One button from the game's settings page; null when the page has no builder.
static func _settings_page_button(page: Node, parent: Node, text: String,
		callback: Callable) -> Button:
	if not is_instance_valid(page) or not page.has_method("_button"):
		return null
	var button: Variant = page.call("_button", parent, text, callback)
	if button is Button and is_instance_valid(button):
		return button
	return null


## One icon texture from the game's settings page; null when the page has no texture op.
static func settings_page_icon(page: Node, kind: String) -> Texture2D:
	if not is_instance_valid(page) or not page.has_method("_icon_texture"):
		return null
	var icon: Variant = page.call("_icon_texture", kind)
	if icon is Texture2D:
		return icon
	return null


## Ask the game's settings page to repaint; nothing happens without its own redraw.
static func settings_page_redraw(page: Node) -> void:
	if is_instance_valid(page) and page.has_method("_redraw"):
		page.call("_redraw")


## Set the picture on one of the game's menu icons; a control without the field is left alone.
static func set_menu_icon_kind(icon: Control, kind: String) -> void:
	if is_instance_valid(icon):
		icon.set("kind", kind)


## The game's inventory node; null when the scene has none.
static func inventory(game: Node) -> Node:
	if not is_instance_valid(game):
		return null
	var node: Variant = game.get("inventory")
	if node is Node and is_instance_valid(node):
		return node
	return null


## Whether the inventory has its map open; its own private test when it has one.
static func map_open(inventory: Node) -> bool:
	if not is_instance_valid(inventory) or not inventory.has_method("_map_open"):
		return false
	return bool(inventory.call("_map_open"))


## Whether the inventory's briefcase is on screen.
static func case_visible(inventory: Node) -> bool:
	if not is_instance_valid(inventory):
		return false
	var briefcase: Variant = inventory.get("case")
	if not briefcase is Node or not is_instance_valid(briefcase):
		return false
	return briefcase.get("visible") == true


## Whether the inventory's customizer panel is open.
static func customizer_opened(inventory: Node) -> bool:
	if not is_instance_valid(inventory):
		return false
	var customizer: Variant = inventory.get("customizer")
	if not customizer is Node or not is_instance_valid(customizer):
		return false
	return customizer.get("opened") == true


## Whether the inventory's inspector panel is active.
static func inspector_active(inventory: Node) -> bool:
	if not is_instance_valid(inventory):
		return false
	var inspector: Variant = inventory.get("inspector")
	if not inspector is Node or not is_instance_valid(inspector):
		return false
	return inspector.get("active") == true


## The briefcase store the inventory node owns; null when it has none.
static func case_store(inventory: Node) -> Object:
	if not is_instance_valid(inventory):
		return null
	var store: Variant = inventory.get("inventory")
	if store is Object and is_instance_valid(store):
		return store as Object
	return null


## The store's slot rows as a typed copy, one row per slot; empty without a store.
static func case_slots(store: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_instance_valid(store):
		return out
	var rows: Variant = store.get("slots")
	if not rows is Array:
		return out
	for row: Variant in rows:
		# A non-dictionary row keeps its index but reads as an item the case does not know.
		out.append(row if row is Dictionary else {"id": ""})
	return out


## The store's checked-out loans as a typed copy; empty without one.
static func case_loans(store: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_instance_valid(store):
		return out
	var loans: Variant = store.get("loans")
	if not loans is Dictionary:
		return out
	for loan: Variant in (loans as Dictionary).values():
		if loan is Dictionary:
			out.append(loan)
	return out


## Whether the store accepts writes; an absent flag reads false.
static func case_writable(store: Object) -> bool:
	if not is_instance_valid(store):
		return false
	return store.get("writable") == true


## How many units of a slot can be taken now; -1 when the store has no availability op.
static func case_available(store: Object, slot: int) -> int:
	if not is_instance_valid(store) or not store.has_method("available"):
		return -1
	return int(store.call("available", slot))


## Take one unit from a slot; the token it returns, empty when it refuses.
static func case_take(store: Object, slot: int) -> String:
	if not is_instance_valid(store) or not store.has_method("take"):
		return ""
	return str(store.call("take", slot))


## Put a checked-out token back, at `slot` when it fits; false when it refuses.
static func case_put(store: Object, token: String, slot: int) -> bool:
	if not is_instance_valid(store) or not store.has_method("put"):
		return false
	return bool(store.call("put", token, slot))


## Add `count` units of an item to the case; the slot used, -1 when it does not fit.
static func case_grant(store: Object, id: String, count: int) -> int:
	if not is_instance_valid(store) or not store.has_method("grant"):
		return -1
	return int(store.call("grant", id, count))


## One stock UI cue at a world point; a source that is not a live node3D is silent.
static func interaction_sound(source: Node3D, kind: String, at: Vector3) -> void:
	if is_instance_valid(source):
		INTERACTION_SOUNDS.play_at(source, kind, at)


## A new in-page dropdown for the game's pages; each one keeps its own entries.
static func menu_picker() -> Control:
	return MENU_PICKER.new()


## The shop's packed item scene; null when the shop has none.
static func shop_item_scene(id: String) -> PackedScene:
	return SHOP_ITEMS.scene(id) as PackedScene


## A house interior the way the game groups it; null for any other node.
static func house_of(node: Node) -> HOUSE:
	if not is_instance_valid(node):
		return null
	return node as HOUSE


## The house group's own point lookup; a missing tree or an outdoor point is null.
static func house_at(tree: SceneTree, at: Vector3) -> Node3D:
	if tree == null:
		return null
	return HOUSE.at(tree, at)


## Spawn an owned world drop through the inventory; null when it refuses.
static func spawn_owned_drop(inventory: Node, id: String, pose: Transform3D) -> Node:
	if not is_instance_valid(inventory) or not inventory.has_method("spawn_owned_drop"):
		return null
	var item: Variant = inventory.call("spawn_owned_drop", id, pose)
	if item is Node and is_instance_valid(item):
		return item
	return null


## The world's chat box; null when the scene has none.
static func chat_box(game: Node) -> Node:
	if not is_instance_valid(game):
		return null
	return game.get_node_or_null("ChatBox") as Node


## Open the chat box with a held control released, then hand the held value back.
static func open_chat(game: Node, player: Node3D) -> bool:
	var chat := chat_box(game)
	if not is_instance_valid(chat) or not is_instance_valid(player):
		return false
	if not chat.has_method("_open"):
		return false
	var held: Variant = player.get("controls_locked")
	player.set("controls_locked", false)
	var opened := bool(chat.call("_open"))
	player.set("controls_locked", held)
	if opened:
		chat.set("_lock_owned", false)
	return opened


## A pony's identity resource; null for a node that has none.
static func identity_of(pony: Node) -> Resource:
	if not is_instance_valid(pony):
		return null
	var identity: Variant = pony.get("identity")
	if identity is Resource:
		return identity
	return null


## One pony's relationship love stage name, or `?` without a live ladder.
static func relationship_love_name(pony: Node, id: String) -> String:
	if not is_instance_valid(pony) or not pony.has_meta("relationship_runtime"):
		return "?"
	var rel: Variant = pony.get_meta("relationship_runtime")
	if not is_instance_valid(rel) or not rel.has_method("ladder"):
		return "?"
	var ladder: Variant = rel.call("ladder", id)
	if not ladder is Dictionary:
		return "?"
	var love: Variant = (ladder as Dictionary).get("love", {})
	return str((love as Dictionary).get("name", "?")) if love is Dictionary else "?"


## The scene's relationship runtime; null when the scene has none.
static func relationship_runtime(game: Node) -> Node:
	if not is_instance_valid(game):
		return null
	var runtime: Variant = game.get("relationship_runtime")
	if runtime is Node and is_instance_valid(runtime):
		return runtime
	return null


## The runtime's bond store; null when it has none.
static func relationship_bonds(runtime: Node) -> Object:
	if not is_instance_valid(runtime):
		return null
	var bonds: Variant = runtime.get("bonds")
	return bonds as Object if is_instance_valid(bonds) else null


## One pony's friendship and love ladder as a typed view; empty without the reader.
static func relationship_ladder(runtime: Node, id: String) -> Ladder:
	if not is_instance_valid(runtime) or not runtime.has_method("ladder"):
		return Ladder.new()
	var row: Variant = runtime.call("ladder", id)
	return Ladder.from_dict(row if row is Dictionary else {})


## The pony's bond store; null without a relationship runtime or a bonds store.
static func bonds_of(pony: Node) -> Object:
	if not is_instance_valid(pony) or not pony.has_meta("relationship_runtime"):
		return null
	var rel: Variant = pony.get_meta("relationship_runtime")
	if not is_instance_valid(rel):
		return null
	var bonds: Variant = rel.get("bonds")
	return bonds as Object if is_instance_valid(bonds) else null


## One bond record through the store's own reader, as a typed view.
static func bond_record_for(bonds: Object, id: String) -> BondRecord:
	if not is_instance_valid(bonds) or not bonds.has_method("record_for"):
		return BondRecord.new()
	var row: Variant = bonds.call("record_for", id)
	return BondRecord.from_dict(row if row is Dictionary else {})


## Whether the bond store calls one pony romance-eligible; false without the store's op.
static func bond_eligible_for_romance(bonds: Object, id: String) -> bool:
	if not is_instance_valid(bonds) or not bonds.has_method("eligible_for_romance"):
		return false
	return bool(bonds.call("eligible_for_romance", id))


## Whether the bond store welcomes `kind` from one pony; false without the store's op.
static func bond_welcomes(bonds: Object, id: String, kind: String) -> bool:
	if not is_instance_valid(bonds) or not bonds.has_method("welcomes"):
		return false
	return bool(bonds.call("welcomes", id, kind))


## The bond store's world day; NAN when the store has no clock.
static func bond_day(bonds: Object) -> float:
	if not is_instance_valid(bonds) or not bonds.has_method("day"):
		return NAN
	var value: Variant = bonds.call("day")
	return float(value) if value is int or value is float else NAN


## Mark one pony as met through the store's own writer; false without the op.
static func bond_mark_met(bonds: Object, id: String) -> bool:
	if not is_instance_valid(bonds) or not bonds.has_method("mark_met"):
		return false
	bonds.call("mark_met", id)
	return true


## Withdraw a bond's standing invitation; nothing happens without the store's op.
static func request_space(pony: Node, id: String) -> void:
	var bonds := bonds_of(pony)
	if bonds != null and bonds.has_method("request_space"):
		bonds.call("request_space", id)


## The game's Ponese mute setting; false when the autoload has no such op.
static func tts_enabled(settings: Node) -> bool:
	if not is_instance_valid(settings) or not settings.has_method("tts_enabled"):
		return false
	return bool(settings.call("tts_enabled"))


## The TTS node's own voice mode; an absent node answers the Ponese default.
static func _voice_mode(tts: Node) -> String:
	if not is_instance_valid(tts):
		return "ponese"
	return str(tts.get("voice_mode"))


## The director's TTS node; null when it has none.
static func tts_of(director: Node) -> Node:
	if not is_instance_valid(director):
		return null
	var tts: Variant = director.get("tts")
	return tts as Node if is_instance_valid(tts) else null


## True while the TTS node reports a running speech server.
static func tts_has_server(tts: Node) -> bool:
	if not is_instance_valid(tts) or not tts.has_method("has_server"):
		return false
	return bool(tts.call("has_server"))


## One AI profile's live voice routing: the profile the director holds and the game's own answers
## for its mode, server and chatter choice.
class VoiceRoute:
	var profile: Dictionary = {}
	var mode := "ponese"
	var server := false
	var ponese := true
	var chatter := false


## The routing the game applies to one pony's profile; every answer defaults as if absent.
static func voice_route(director: Node, id: String) -> VoiceRoute:
	var out := VoiceRoute.new()
	if not is_instance_valid(director):
		return out
	var characters: Variant = director.get("characters")
	if not characters is Dictionary or not (characters as Dictionary).has(id):
		return out
	var entry: Variant = (characters as Dictionary)[id]
	if not entry is Dictionary:
		return out
	var profile: Variant = (entry as Dictionary).get("profile", {})
	if not profile is Dictionary:
		return out
	var tts := tts_of(director)
	out.profile = profile
	out.mode = _voice_mode(tts)
	out.server = tts_has_server(tts)
	out.ponese = CHATTER.is_ponese_mode(out.mode)
	out.chatter = CHATTER.use_chatter(out.profile, out.mode)
	return out


## Play one line through the game's own vocal node; false without the op.
static func vocal_play(vocal: Node, id: String, gender: String, pony: Node3D,
		db: float) -> bool:
	if not is_instance_valid(vocal) or not vocal.has_method("play"):
		return false
	return bool(vocal.call("play", id, gender, pony, db))


## One kiss sound through her own boop node; false without the op.
static func play_kiss(boop: Node, db: float, loop: bool) -> bool:
	if not is_instance_valid(boop) or not boop.has_method("play_kiss"):
		return false
	# The game's op returns void, so the cast would fail on its null answer.
	boop.call("play_kiss", db, loop)
	return true


## The pony's body scale; an absent member answers the ordinary 1.0.
static func body_scale_of(pony: Node) -> float:
	if not is_instance_valid(pony):
		return 1.0
	var value: Variant = pony.get("body_scale")
	return float(value) if value != null else 1.0


## Write a body's live scale through the game's setter when it has one, else the bare field.
static func set_body_scale(pony: Node, scale: float) -> void:
	if not is_instance_valid(pony):
		return
	var live: Variant = pony.get("body_scale")
	if pony.has_method("set_body_scale"):
		# The game setter moves the capsule and the pose calibration with the field.
		if live == null or not is_equal_approx(float(live), scale):
			pony.call("set_body_scale", scale)
	elif live != null:
		pony.set("body_scale", scale)


## The pony's body skeleton; null when the body has none.
static func skeleton_of(pony: Node) -> Skeleton3D:
	if not is_instance_valid(pony):
		return null
	var skeleton: Variant = pony.get("skeleton")
	if skeleton is Skeleton3D and is_instance_valid(skeleton):
		return skeleton
	return null


## The pony's hair skeleton; null when the body has none.
static func hair_skeleton_of(pony: Node) -> Skeleton3D:
	if not is_instance_valid(pony):
		return null
	var skeleton: Variant = pony.get("hair_skeleton")
	if skeleton is Skeleton3D and is_instance_valid(skeleton):
		return skeleton
	return null


## The pony's hair node; null when the body has none.
static func hair_of(pony: Node) -> Node3D:
	if not is_instance_valid(pony):
		return null
	var hair: Variant = pony.get("hair")
	if hair is Node3D and is_instance_valid(hair):
		return hair
	return null


## The pony's model root; null when the body has none.
static func model_of(pony: Node) -> Node:
	if not is_instance_valid(pony):
		return null
	var model: Variant = pony.get("_model")
	if model is Node and is_instance_valid(model):
		return model
	return null


## The drawn MareBody mesh under the model; null when the body has none.
static func body_of(pony: Node) -> MeshInstance3D:
	var model := model_of(pony)
	if model == null:
		return null
	var body: Variant = model.find_child("MareBody", true, false)
	if body is MeshInstance3D and is_instance_valid(body):
		return body
	return null


## The game's dock mesh under the pony; null when the body has none.
static func dock_of(pony: Node) -> MeshInstance3D:
	if not is_instance_valid(pony):
		return null
	var dock: Variant = pony.find_child("OpenPonyDock", true, false)
	if dock is MeshInstance3D and is_instance_valid(dock):
		return dock
	return null


## The reference dock's anchor for a pony; `Vector3.INF` when the body cannot be measured.
static func dock_tail_anchor(pony: Node) -> Vector3:
	if not is_instance_valid(pony):
		return Vector3.INF
	var measured: Dictionary = DOCK_TAIL_MOUNT.measure(pony)
	var raw: Variant = measured.get("anchor")
	if not raw is Array or (raw as Array).size() != 3:
		return Vector3.INF
	var anchor := Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return anchor if anchor.is_finite() else Vector3.INF


## The game's dock fit, including the seat shift; null when the pony is gone.
static func dock_fit(pony: Node) -> DockFit:
	if not is_instance_valid(pony):
		return null
	var fit := DockFit.new()
	fit.data = HYBRID_DOCK.effective_fit(pony, HYBRID_DOCK.read_fit())
	return null if fit.data.is_empty() else fit


## The fitted dock mesh from one fit document; null when the fit is absent.
static func dock_fitted_mesh(fit: DockFit) -> ArrayMesh:
	if fit == null:
		return null
	return HYBRID_DOCK.fitted_mesh(fit.data, false)


## The dock mesh pushed into the rump; the input mesh when the pony cannot answer.
static func dock_reach_rump(mesh: ArrayMesh, pony: Node) -> ArrayMesh:
	if mesh == null or not is_instance_valid(pony) or identity_of(pony) == null:
		return mesh
	return HYBRID_DOCK.reach_rump(mesh, pony, false)


## The game's rump surface height for a body name; NAN for a name the table does not know.
static func dock_rump_z(body_name: String, y: float) -> float:
	if not HYBRID_DOCK.RUMP_Z.has(body_name):
		return NAN
	return HYBRID_DOCK.rump_z(body_name, y)


## Let the pony's FlankTouch copy its body materials before the anatomy patches them.
static func own_body_materials(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	var flank := pony.get_node_or_null("FlankTouch")
	if flank == null or not flank.has_method("_own_body_materials"):
		return
	flank.call("_own_body_materials")


## The pony's hair link; null when the body has none.
static func hair_link_of(pony: Node) -> Node:
	if not is_instance_valid(pony):
		return null
	var link: Variant = pony.get("hair_link")
	if link is Node and is_instance_valid(link):
		return link
	return null


## True when the pony has the hair link and its pelvis offset; false otherwise.
static func hair_link_ready(pony: Node) -> bool:
	var link := hair_link_of(pony)
	return link != null and link.get("pelvis_offset") is Transform3D


## The hair link's pelvis offset; identity when the link is absent.
static func hair_link_pelvis(pony: Node) -> Transform3D:
	var link := hair_link_of(pony)
	if link == null:
		return Transform3D.IDENTITY
	var value: Variant = link.get("pelvis_offset")
	return value if value is Transform3D else Transform3D.IDENTITY


## Write the hair link's pelvis offset; nothing happens without a link.
static func set_hair_link_pelvis(pony: Node, value: Transform3D) -> void:
	var link := hair_link_of(pony)
	if link != null:
		link.set("pelvis_offset", value)


## Let the hair link re-read its body after a pelvis write.
static func notify_hair_link(pony: Node) -> void:
	var link := hair_link_of(pony)
	if link != null and link.has_method("_body_updated"):
		link.call("_body_updated")


## True while the far LOD mesh is shown; an absent flag reads false.
static func far_mesh_shown(pony: Node) -> bool:
	if not is_instance_valid(pony):
		return false
	return pony.get("_far_mesh_shown") == true


## Switch the near/far LOD; a body without the switch is left alone.
static func set_near_mesh(pony: Node, on: bool) -> void:
	if not is_instance_valid(pony) or not pony.has_method("set_near_mesh"):
		return
	pony.call("set_near_mesh", on)


## The pony's native eye modifier; null when the body has none.
static func eye_motion_of(pony: Node) -> Node:
	if not is_instance_valid(pony):
		return null
	var eye: Variant = pony.get("eye_motion")
	if eye is Node and is_instance_valid(eye):
		return eye
	return null


## Anon's body under the player rig; null when the rig has none.
static func anon_body_of(player: Node) -> Node3D:
	if not is_instance_valid(player):
		return null
	var body: Variant = player.find_child("AnonBody", true, false)
	if body is Node3D and is_instance_valid(body):
		return body
	return null


## The pony's blush sustainer node; null when the body has none.
static func boop_of(pony: Node) -> Node:
	if not is_instance_valid(pony):
		return null
	var boop: Variant = pony.get("boop_node")
	if boop is Node and is_instance_valid(boop):
		return boop
	return null


## The pony's head node; null when the body has none.
static func head_of(pony: Node) -> Node:
	if not is_instance_valid(pony):
		return null
	var head: Variant = pony.get("head")
	if head is Node and is_instance_valid(head):
		return head
	return null


## The head node's mouth rig; null when the head has none.
static func mouth_of(head: Node) -> Node:
	if not is_instance_valid(head):
		return null
	var mouth: Variant = head.get("mouth")
	if mouth is Node and is_instance_valid(mouth):
		return mouth
	return null


## The head skeleton the blush sustainer holds; null when the body has none.
static func head_skeleton_of(boop: Node) -> Skeleton3D:
	if not is_instance_valid(boop):
		return null
	var head: Variant = boop.get("head_skeleton")
	if head is Skeleton3D and is_instance_valid(head):
		return head
	return null


## Set the mouth rig's viseme; a rig without the method stays silent.
static func set_viseme(mouth: Node, letter: String) -> void:
	if not is_instance_valid(mouth) or not mouth.has_method("set_viseme"):
		return
	mouth.call("set_viseme", letter)


## Clear the mouth rig's viseme; a rig without the method stays silent.
static func clear_viseme(mouth: Node) -> void:
	if not is_instance_valid(mouth) or not mouth.has_method("clear"):
		return
	mouth.call("clear")


## Feed the blush sustainer; a body without one stays silent.
static func sustain_blush(boop: Node, amount: float) -> void:
	if not is_instance_valid(boop) or not boop.has_method("sustain_blush"):
		return
	boop.call("sustain_blush", amount)


## Fire the boop's own heart burst; false when the node has no celebrate op.
static func celebrate(boop: Node) -> bool:
	if not is_instance_valid(boop) or not boop.has_method("celebrate"):
		return false
	boop.call("celebrate")
	return true


## The pony's expression controller; null when the body has none.
static func expressions_of(pony: Node) -> Object:
	if not is_instance_valid(pony):
		return null
	var expressions: Variant = pony.get("expressions")
	return expressions as Object


## Feed the expression controller's touch layer; an absent layer is left alone.
static func touch(expressions: Object, source: String, smile: float, lids: float) -> void:
	if is_instance_valid(expressions) and expressions.has_method("touch"):
		expressions.call("touch", source, smile, lids)


## Release the expression controller's touch layer.
static func release_touch(expressions: Object, source: String) -> void:
	if is_instance_valid(expressions) and expressions.has_method("release_touch"):
		expressions.call("release_touch", source)


## Hold or release the stare; a NAN `lids` leaves the game's own default in place.
static func stare(expressions: Object, on: bool, lids: float = NAN) -> void:
	if not is_instance_valid(expressions) or not expressions.has_method("stare"):
		return
	if is_nan(lids):
		expressions.call("stare", on)
	else:
		expressions.call("stare", on, lids)


## Keep the flustered loop running for `seconds`.
static func fluster(expressions: Object, seconds: float, peeks := true) -> void:
	if is_instance_valid(expressions) and expressions.has_method("fluster"):
		expressions.call("fluster", seconds, peeks)


## The live fluster weight; 0.0 when the controller has none.
static func fluster_amount(expressions: Object) -> float:
	if not is_instance_valid(expressions):
		return 0.0
	var value: Variant = expressions.get("fluster_amount")
	return float(value) if value is float or value is int else 0.0


## The face a spoken line owns right now; empty when the controller has none.
static func dialogue_face(expressions: Object) -> String:
	if not is_instance_valid(expressions):
		return ""
	var value: Variant = expressions.get("dialogue_face")
	return value if value is String else ""


## Set the spoken line's face on the expression controller.
static func set_dialogue(expressions: Object, face: String) -> void:
	if is_instance_valid(expressions) and expressions.has_method("set_dialogue"):
		expressions.call("set_dialogue", face)


## Hold the spoken line's face for `seconds`.
static func finish_dialogue(expressions: Object, seconds: float) -> void:
	if is_instance_valid(expressions) and expressions.has_method("finish_dialogue"):
		expressions.call("finish_dialogue", seconds)


## Drop the spoken line's face.
static func clear_dialogue(expressions: Object) -> void:
	if is_instance_valid(expressions) and expressions.has_method("clear_dialogue"):
		expressions.call("clear_dialogue")


## The scene's world-context node; null when the scene has none.
static func world_context(game: Node) -> Node:
	if not is_instance_valid(game):
		return null
	var context: Variant = game.get("world_context")
	if context is Node and is_instance_valid(context):
		return context
	return null


## The world context's story journal; null when it has none.
static func story_of(context: Node) -> Object:
	if not is_instance_valid(context):
		return null
	var story: Variant = context.get("story")
	return story as Object if is_instance_valid(story) else null


## The story journal's line store; null when it has none.
static func story_store(story: Object) -> Object:
	if not is_instance_valid(story):
		return null
	var store: Variant = story.get("store")
	return store as Object if is_instance_valid(store) else null


## True while the game's story journal can answer lines.
static func story_open(story: Object) -> bool:
	if not is_instance_valid(story) or not story.has_method("is_open"):
		return false
	return bool(story.call("is_open"))


## The newest line id the store holds; -1 without the reader.
static func story_last_line_id(store: Object) -> int:
	if not is_instance_valid(store) or not store.has_method("last_line_id"):
		return -1
	return int(store.call("last_line_id"))


## The store's matching lines, newest first; empty without the reader.
static func story_search(store: Object, pony: String, words: Array[String],
		before: int, limit: int) -> Array[StoryRow]:
	var out: Array[StoryRow] = []
	if not is_instance_valid(store) or not store.has_method("search"):
		return out
	var rows: Variant = store.call("search", pony, words, before, limit)
	if not rows is Array:
		return out
	for row: Variant in rows:
		if row is Dictionary:
			out.append(StoryRow.from_dict(row))
	return out


## The store's recent witnessed lines; empty without the reader.
static func story_witnessed(store: Object, pony: String, limit: int, before: int,
		kinds: Array[String]) -> Array[StoryRow]:
	var out: Array[StoryRow] = []
	if not is_instance_valid(store) or not store.has_method("witnessed"):
		return out
	var rows: Variant = store.call("witnessed", pony, limit, before, kinds)
	if not rows is Array:
		return out
	for row: Variant in rows:
		if row is Dictionary:
			out.append(StoryRow.from_dict(row))
	return out


## One stored line's text through the game's own reader.
static func story_line_text(story: Object, row: StoryRow, pony: String,
		with_day: bool) -> String:
	if not is_instance_valid(story) or not story.has_method("line_text"):
		return ""
	if row == null:
		return ""
	return str(story.call("line_text", row.raw, pony, with_day))


## The world context's recent events for one pony, as typed rows; empty without the reader.
static func world_events(context: Node, id: String, limit: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_instance_valid(context) or not context.has_method("events_for"):
		return out
	var events: Variant = context.call("events_for", id, limit)
	if not events is Array:
		return out
	for event: Variant in events:
		if event is Dictionary:
			out.append(event)
	return out


## The world context's impressions store; null when it has none.
static func impressions_of(context: Node) -> Node:
	if not is_instance_valid(context):
		return null
	var impressions: Variant = context.get("impressions")
	if impressions is Node and is_instance_valid(impressions):
		return impressions
	return null


## One pony's committed mood; `absent` when the store has a profile without a mood.
static func impression_mood(impressions: Node, id: String, absent: String = "neutral") -> String:
	if not is_instance_valid(impressions) or not impressions.has_method("profile"):
		return ""
	var profile: Variant = impressions.call("profile", id)
	if not profile is Dictionary:
		return ""
	return str((profile as Dictionary).get("mood", absent))


## Write one mood change; false without a store or a commit op.
static func impression_set_mood(impressions: Node, id: String, mood: String,
		key: String) -> bool:
	if not is_instance_valid(impressions) or not impressions.has_method("commit"):
		return false
	impressions.call("commit", id, {"mood": mood}, key)
	return true


## Commit one impression row through the store's own writer; false without the op.
static func impression_commit(impressions: Node, id: String, mood: String, romance: int,
		thought: String, event_id: String) -> bool:
	if not is_instance_valid(impressions) or not impressions.has_method("commit"):
		return false
	var data := {}
	if not mood.is_empty():
		data["mood"] = mood
	if romance != 0:
		data["romance"] = romance
	if not thought.is_empty():
		data["thought"] = thought.left(240)
	impressions.call("commit", id, data, event_id)
	return true


## The store's one-line standing note; empty without the op.
static func impression_standing_line(impressions: Node, id: String) -> String:
	if not is_instance_valid(impressions) or not impressions.has_method("standing_line"):
		return ""
	return str(impressions.call("standing_line", id))


## The rig's private look pitch; NAN when the rig has no such member.
static func pitch(body: Node) -> float:
	if not is_instance_valid(body):
		return NAN
	var value: Variant = body.get("_pitch")
	if value == null:
		return NAN
	return float(value)


## Write the rig's look pitch; the same presence test the read uses, so an absent member stays
## untouched.
static func set_pitch(body: Node, pitch: float) -> void:
	if not is_instance_valid(body) or body.get("_pitch") == null:
		return
	body.set("_pitch", pitch)


## The form driver the rig shows; null for a plain body.
static func form_of(player: Node3D) -> Node:
	if not is_instance_valid(player):
		return null
	var form: Variant = player.get("form_driver")
	if form is Node and is_instance_valid(form):
		return form
	return null


## The live player form's age; the human default when no form driver is live.
static func player_form_is_young(tree: SceneTree) -> bool:
	return PLAYER_FORM.is_young(PLAYER_FORM.active(tree))


## The live player form's kind; false for the human default.
static func player_form_is_pony(tree: SceneTree) -> bool:
	return PLAYER_FORM.is_pony(PLAYER_FORM.active(tree))


## The post-outline exclusion the anatomy mesh and teats install; an absent mesh is a no-op.
static func exclude_from_outline(mesh: MeshInstance3D) -> void:
	if not is_instance_valid(mesh):
		return
	OUTLINE_EXCLUSION.apply_to(mesh)


## Let a form driver apply its own view limit; a body without one keeps the camera as it is.
static func clamp_view(form: Node) -> void:
	if not is_instance_valid(form) or not form.has_method("clamp_view"):
		return
	form.call("clamp_view")


## Drop both stale navigator writes that would face her away from the act, with one child lookup.
static func clear_facing(pony: Node) -> void:
	var nav := navigator_of(pony)
	if nav == null:
		return
	if "face_point" in nav:
		nav.set("face_point", Vector3.INF)
	if nav.has_method("set_conversation_target"):
		nav.call("set_conversation_target", null, false)


## The pony's navigator node; null when the body has none.
static func navigator_of(pony: Node) -> Node:
	if not is_instance_valid(pony):
		return null
	return pony.get_node_or_null("Navigator")


## The navigator's owner lease; empty when it is free.
static func navigator_owner(nav: Node) -> String:
	if not is_instance_valid(nav):
		return ""
	return str(nav.get("command_owner"))


## The navigator's reservation lease; empty when it is unreserved.
static func navigator_reserved(nav: Node) -> String:
	if not is_instance_valid(nav):
		return ""
	return str(nav.get("reserved_by"))


## Whether the navigator may wander; an absent member reads as disabled.
static func navigator_wander(nav: Node) -> bool:
	if not is_instance_valid(nav):
		return false
	return nav.get("wander_enabled") == true


## Whether the navigator is walking to a target.
static func navigator_has_target(nav: Node) -> bool:
	return is_instance_valid(nav) and nav.get("_has_target") == true


## Stop the navigator where it is; a node without the op is left alone.
static func navigator_stay(nav: Node) -> void:
	if is_instance_valid(nav) and nav.has_method("stay"):
		nav.call("stay")


## Write the navigator's owner lease.
static func set_navigator_owner(nav: Node, owner: String) -> void:
	if is_instance_valid(nav):
		nav.set("command_owner", owner)


## Write the navigator's reservation lease.
static func set_navigator_reserved(nav: Node, value: String) -> void:
	if is_instance_valid(nav):
		nav.set("reserved_by", value)


## Clear a travel lease's carried body; nothing happens without the node's op.
static func travel_clear(travel: Node, pony: Node3D) -> void:
	if is_instance_valid(travel) and travel.has_method("clear"):
		travel.call("clear", pony)


## Write the navigator's wander switch.
static func set_navigator_wander(nav: Node, enabled: bool) -> void:
	if is_instance_valid(nav):
		nav.set("wander_enabled", enabled)


## The navigator's speed override; NAN when the node has no such member.
static func navigator_speed_limit(nav: Node) -> float:
	if not is_instance_valid(nav):
		return NAN
	var value: Variant = nav.get("command_speed_limit")
	return float(value) if value != null else NAN


## The navigator's pace override; NAN when the node has no such member.
static func navigator_pace_target(nav: Node) -> float:
	if not is_instance_valid(nav):
		return NAN
	var value: Variant = nav.get("command_pace_target")
	return float(value) if value != null else NAN


## Write the navigator's speed override; nothing happens without a navigator.
static func set_navigator_speed_limit(nav: Node, value: float) -> void:
	if is_instance_valid(nav):
		nav.set("command_speed_limit", value)


## Write the navigator's pace override; nothing happens without a navigator.
static func set_navigator_pace_target(nav: Node, value: float) -> void:
	if is_instance_valid(nav):
		nav.set("command_pace_target", value)


## The navigator's own reachable point near `point`; `Vector3.INF` when it cannot answer.
static func navigator_support(nav: Node, point: Vector3) -> Vector3:
	if not is_instance_valid(nav) or not nav.has_method("command_support"):
		return Vector3.INF
	var goal: Variant = nav.call("command_support", point)
	if goal is Vector3:
		return goal
	return Vector3.INF


## Walk the navigator to `point`; false when it has no op or refuses the goal.
static func navigator_destination(nav: Node, point: Vector3, gait: String) -> bool:
	if not is_instance_valid(nav) or not nav.has_method("command_destination"):
		return false
	return bool(nav.call("command_destination", point, gait))


## Keep Anon as her conversation target; a body without the setter is left alone.
static func set_conversation_target(pony: Node, target: Node3D, hold: bool) -> void:
	if is_instance_valid(pony) and pony.has_method("set_conversation_target"):
		pony.call("set_conversation_target", target, hold)


## Her current face-turn rate; NAN when the body has none.
static func face_turn_rate(pony: Node) -> float:
	if not is_instance_valid(pony):
		return NAN
	var rate: Variant = pony.get("face_turn_rate")
	return float(rate) if rate != null else NAN


## Write her face-turn rate; a body without it keeps its own.
static func set_face_turn_rate(pony: Node, value: float) -> void:
	if is_instance_valid(pony) and pony.get("face_turn_rate") != null:
		pony.set("face_turn_rate", value)


## Whether she is held; a body without the op reads as not held.
static func is_held(pony: Node) -> bool:
	if not is_instance_valid(pony) or not pony.has_method("is_held"):
		return false
	return bool(pony.call("is_held"))


## Whether her feet are grounded; a body without the op reads as not grounded.
static func grounded(pony: Node) -> bool:
	if not is_instance_valid(pony) or not pony.has_method("grounded"):
		return false
	return bool(pony.call("grounded"))


## Her posture's requested name; empty when the body has no posture.
static func posture_requested(pony: Node) -> String:
	if not is_instance_valid(pony) or not pony.has_method("posture_status"):
		return ""
	var status: Variant = pony.call("posture_status")
	if not status is Dictionary:
		return ""
	return str((status as Dictionary).get("requested", ""))


## Whether her posture has settled; false when the body has no posture.
static func posture_settled(pony: Node) -> bool:
	if not is_instance_valid(pony) or not pony.has_method("posture_status"):
		return false
	var status: Variant = pony.call("posture_status")
	return status is Dictionary and bool((status as Dictionary).get("settled", false))


## Ask her to take a posture; a body without the request keeps its own.
static func request_posture(pony: Node, posture: String) -> void:
	if is_instance_valid(pony) and pony.has_method("request_posture"):
		pony.call("request_posture", posture)


## The reason her current action is interrupted; empty when nothing interrupts.
static func interruption_reason(pony: Node) -> String:
	if not is_instance_valid(pony) or not pony.has_method("action_interruption_reason"):
		return ""
	return str(pony.call("action_interruption_reason"))


## The conversation director's own interrupt, when the loop still exposes it.
static func interrupt_director(director: Node) -> void:
	if not is_instance_valid(director) or not director.has_method("interrupt"):
		return
	director.call("interrupt")


## True while the conversation director is doing anything but idling.
static func director_speaking(director: Node) -> bool:
	if not is_instance_valid(director):
		return false
	return str(director.get("state")) != "idle"


## True while the pony's own speech loop reports speaking.
static func pony_speaking(pony: Node) -> bool:
	if not is_instance_valid(pony) or not pony.has_method("is_speaking"):
		return false
	return bool(pony.call("is_speaking"))


## The director's own clock, in seconds; NAN when it has no clock.
static func director_now(director: Node) -> float:
	if not is_instance_valid(director) or not director.has_method("_now"):
		return NAN
	return float(director.call("_now"))


## Whether a director sub-system (an approach, a group exchange) reports itself active.
static func subsystem_active(node: Object) -> bool:
	if not is_instance_valid(node) or not node.has_method("active"):
		return false
	return bool(node.call("active"))


## The director's authored-line host: the greeting, the queue and the cancel.
static func director_lines(director: Node) -> DirectorLines:
	var out := DirectorLines.new()
	out.director = director
	return out


## One director's live model configuration, typed for the classifier's own setup.
static func llm_config(director: Node) -> LlmConfig:
	var out := LlmConfig.new()
	if not is_instance_valid(director):
		return out
	var config: Variant = director.get("config")
	if config == null or not AI_CONFIG.ai_enabled(config):
		return out
	if not director.has_method("_llm_section"):
		return out
	out.enabled = true
	var section: Variant = director.call("_llm_section")
	if section is Dictionary:
		out.section = section
	var llm: Variant = director.get("llm")
	if is_instance_valid(llm):
		out.status_path = str(llm.get("status_path"))
	return out


## Record one world-context event with its kind and text; nothing without the op.
static func world_record(context: Node, kind: String, text: String,
		witnesses: Array[String], subjects: Array[String], event_id: String,
		place: String = "") -> void:
	if not is_instance_valid(context) or not context.has_method("record"):
		return
	if place.is_empty():
		context.call("record", kind, text, witnesses, subjects, event_id)
	else:
		context.call("record", kind, text, witnesses, subjects, event_id, place)


## Record one world-context event; `ids` is the subject list and `key` the replaceable event key.
static func record_situation(context: Node, text: String, ids: Array[String],
		key: String) -> void:
	if not is_instance_valid(context) or not context.has_method("record"):
		return
	context.call("record", "situation", text, ids, ids, key)


## Prepare her generated voice cache for the act; absent when the director has no voice loop.
static func prepare_vocal(director: Node, pony_id: String) -> void:
	if not is_instance_valid(director):
		return
	var vocal: Variant = director.get("vocal")
	if vocal is Node and is_instance_valid(vocal) and vocal.has_method("prepare"):
		vocal.call("prepare", pony_id)


## The game's pony kisser; null when the scene has none.
static func kisser_of(game: Node) -> Node:
	if not is_instance_valid(game):
		return null
	var kisser: Variant = game.get("kisser")
	if kisser is Node and is_instance_valid(kisser):
		return kisser
	return null


## Start the stock kiss from her side; false when the kisser refuses or has no op.
static func begin_from_pony(kisser: Node, pony: Node3D) -> bool:
	if not is_instance_valid(kisser) or not kisser.has_method("begin_from_pony"):
		return false
	return bool(kisser.call("begin_from_pony", pony))


## Drop the kisser's own latch so the next kiss starts clean.
static func clear_kisser(kisser: Node) -> void:
	if not is_instance_valid(kisser):
		return
	kisser.set("_active", null)
	kisser.set("_her_kiss", false)
	kisser.set("_used_hold", false)


## End the stock affection through its own op; a node without it is left alone.
static func end_affection(affection: Node) -> void:
	if is_instance_valid(affection) and affection.has_method("end"):
		affection.call("end")


## Clear the affection's own 60 s stare afterglow.
static func cancel_afterglow(affection: Node) -> void:
	if is_instance_valid(affection) and affection.has_method("cancel_afterglow"):
		affection.call("cancel_afterglow")


## Feed the stock affection Anon's live mouth target, eye and face; a node without the members is
## left alone.
static func feed_affection(affection: Node, target: Vector3, eye: Vector3, face: Basis) -> void:
	if not is_instance_valid(affection):
		return
	affection.set("target", target)
	affection.set("eye", eye)
	affection.set("face", face)


## A body's mouth point; INF when the body cannot answer.
static func mouth_point(node: Node) -> Vector3:
	if not is_instance_valid(node) or not node.has_method("mouth_point"):
		return Vector3.INF
	var point: Variant = node.call("mouth_point")
	if point is Vector3:
		return point
	return Vector3.INF


## Whether the stock kiss pose exposes the side latch the act pins.
static func kiss_side_known(pose: SkeletonModifier3D) -> bool:
	return is_instance_valid(pose) and pose.get("_side") != null


## Pin the stock kiss pose to `side` and hold it there: the act owns the head tilt while it runs.
static func pin_kiss_side(pose: SkeletonModifier3D, side: float, hold_s: float) -> void:
	if not is_instance_valid(pose):
		return
	pose.set("_side", side)
	pose.set("_side_now", side)
	pose.set("_side_wait", hold_s)


## Release the stock kiss pose's side hold; a pose without the member keeps its own.
static func release_kiss_side(pose: SkeletonModifier3D) -> void:
	if is_instance_valid(pose) and pose.get("_side_wait") != null:
		pose.set("_side_wait", 0.0)


## Settle the excitement Beat's own hold so the stock horn sparkle does not fire.
static func settle_excitement(excitement: Node) -> void:
	if is_instance_valid(excitement):
		excitement.set("_until", 0.0)


## One mouth expression write; a rig without the op is left alone.
static func set_expression(mouth: Node, name: String, amount: float) -> void:
	if is_instance_valid(mouth) and mouth.has_method("set_expression"):
		mouth.call("set_expression", name, amount)


## Let her Affection buck at Anon; false without the op or when it refuses.
static func affection_buck(affection: Node, body: Node3D) -> bool:
	if not is_instance_valid(affection) or not affection.has_method("buck"):
		return false
	return bool(affection.call("buck", body))


## The knockdown handle Anon's body carries; null when it has none.
static func knockdown_of(body: Node3D) -> Object:
	if not is_instance_valid(body):
		return null
	return body.get("knockdown") as Object


## Push Anon down along `direction`; false without a live knockdown handle.
static func start_knockdown(node: Object, body: Node3D, direction: Vector3) -> bool:
	if not is_instance_valid(node) or not node.has_method("start"):
		return false
	node.call("start", body, direction)
	return true


## End a cuddle session at once; a session without the op is left alone.
static func cuddle_end(session: Node) -> void:
	if is_instance_valid(session) and session.has_method("end"):
		session.call("end", true)


## Whether a hoof hold is active; false without the op.
static func hoof_active(hoof: Object) -> bool:
	if not is_instance_valid(hoof) or not hoof.has_method("active"):
		return false
	return bool(hoof.call("active"))


## Seat Anon on a rest seat; false when the rig refuses or has no seat op.
static func player_sit_on(player: Node3D, seat: Node3D) -> bool:
	if not is_instance_valid(player) or not player.has_method("sit_on"):
		return false
	return bool(player.call("sit_on", seat))


## Recline Anon on his couch seat; false without the op.
static func player_toggle_couch_sleep(player: Node3D) -> bool:
	if not is_instance_valid(player) or not player.has_method("toggle_couch_sleep"):
		return false
	return bool(player.call("toggle_couch_sleep"))


## The guest-seat transform a couch rest lays a pony at; an infinite origin when it cannot.
static func couch_pony_transform(node: Node3D, seat: Node3D) -> Transform3D:
	if not is_instance_valid(node) or not is_instance_valid(seat) \
			or not node.has_method("pony_transform"):
		return Transform3D(Basis.IDENTITY, Vector3.INF)
	var value: Variant = node.call("pony_transform", seat)
	return value if value is Transform3D else Transform3D(Basis.IDENTITY, Vector3.INF)


## A couch rest's seats, as a typed copy; empty when it has fewer than two.
static func couch_seats(node: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if not is_instance_valid(node):
		return out
	var seats: Variant = node.get("seats")
	if not seats is Array:
		return out
	for seat: Variant in seats:
		if seat is Node3D and is_instance_valid(seat):
			out.append(seat)
	return out


## Open the couch rest for a guest; false without the op.
static func couch_open(node: Node3D) -> bool:
	if not is_instance_valid(node) or not node.has_method("open"):
		return false
	return bool(node.call("open"))


## Invite a pony to the guest seat; false without the op or when it refuses.
static func couch_invite(node: Node3D, pony: Node3D, seat: Node3D) -> bool:
	if not is_instance_valid(node) or not node.has_method("invite"):
		return false
	return bool(node.call("invite", pony, seat))


## The front stand point a couch rest reports; `Vector3.INF` without the op.
static func couch_approach(node: Node3D, seat: Node3D) -> Vector3:
	if not is_instance_valid(node) or not node.has_method("approach"):
		return Vector3.INF
	var value: Variant = node.call("approach", seat)
	return value if value is Vector3 else Vector3.INF


## Whether the couch rest measured that this mare fits.
static func couch_mare_fits(node: Node3D) -> bool:
	return is_instance_valid(node) and node.get("_mare_fits") == true


## When this pony's guest cooldown ends, in engine milliseconds; 0 when there is none.
static func couch_cooldown_until(node: Node3D, pony: Node3D) -> int:
	if not is_instance_valid(node) or not is_instance_valid(pony):
		return 0
	var cooldowns: Variant = node.get("_cooldowns")
	if not cooldowns is Dictionary:
		return 0
	return int((cooldowns as Dictionary).get(pony.get_instance_id(), 0))


## The clear floor to step off a seat; `Vector3.INF` without a body in a physics space.
static func couch_exit(body: Node, seat: Node3D, fallback: Vector3, height: float,
		radius: float) -> Vector3:
	if not body is CharacterBody3D or not (body as Node).is_inside_tree():
		return Vector3.INF
	return COUCH_EXIT.find_exit(body as CharacterBody3D, seat, fallback, height, radius)


## Take the carry the reach holds; false when it is not this pony or not cradled.
static func carry_ours(reach: Node, pony: Node3D) -> bool:
	if not is_instance_valid(reach) or not is_instance_valid(pony):
		return false
	return reach.get("held") == pony and reach.get("cradled") == true


## The reach's desktop action node; null when it has none.
static func carry_actions(reach: Node) -> Node:
	if not is_instance_valid(reach):
		return null
	var actions: Variant = reach.get("desktop_actions")
	return actions as Node if actions is Node else null


## Clear the carry flags the salute path leaves behind.
static func clear_carry(reach: Node) -> void:
	if not is_instance_valid(reach):
		return
	reach.set("held", null)
	reach.set("cradled", false)
	reach.set("_drop_upright", false)
	reach.set("_laying", -1.0)
	reach.set("_sleepy_kiss", false)
	reach.set("_lean", 0.0)
	reach.set("_lay", {})


## Tell the desktop actions the carried pony was released.
static func carry_released(actions: Node) -> void:
	if is_instance_valid(actions) and actions.has_method("pony_released"):
		actions.call("pony_released")


## End her hold interaction; a body without the op is left alone.
static func end_interaction(pony: Node) -> void:
	if is_instance_valid(pony) and pony.has_method("end_interaction"):
		pony.call("end_interaction")


## Set a body's velocity; a body without the member is left alone.
static func set_velocity(body: Node3D, velocity: Vector3) -> void:
	if is_instance_valid(body):
		body.set("velocity", velocity)


## Pause or resume a pony's motion; a body without the member is left alone.
static func set_motion_paused(pony: Node, paused: bool) -> void:
	if is_instance_valid(pony) and pony.get("motion_paused") != null:
		pony.set("motion_paused", paused)


## Whether a rest seat is free for this pony; false without the seat's op.
static func seat_free_for(seat: Node, pony: Node3D) -> bool:
	if not is_instance_valid(seat) or not seat.has_method("free_for"):
		return false
	return bool(seat.call("free_for", pony))


## A house's guest or unnamed bed through its own builder; null when it cannot answer.
static func ensure_bed(house: Node3D, kind: String) -> Node3D:
	if not is_instance_valid(house) or not house.has_method("ensure_bed"):
		return null
	var bed: Variant = house.call("ensure_bed", kind)
	return bed as Node3D if bed is Node3D and is_instance_valid(bed) else null


## The stock bed rest that owns a bed, installed on first use; null when it cannot answer.
static func stock_bed_rest(bed: Node) -> Node3D:
	if not is_instance_valid(bed) or not bed is Node3D or not (bed as Node).is_inside_tree():
		return null
	var rest: Variant = SHARED_BED.for_bed(bed as Node3D)
	return rest as Node3D if rest is Node3D and is_instance_valid(rest) else null


## Whether the bed rest accepts this pony through its own gate; false without the op.
static func bed_rest_accept(rest: Node, pony: Node3D) -> bool:
	if not is_instance_valid(rest) or not rest.has_method("accept"):
		return false
	return bool(rest.call("accept", pony))


## Whether the bed rest judged this pony willing; false without the op.
static func bed_rest_willing(rest: Node, pony: Node3D) -> bool:
	if not is_instance_valid(rest) or not rest.has_method("_willing"):
		return false
	return bool(rest.call("_willing", pony))


## Whether the bed rest judges this pony eligible; false without the op.
static func bed_rest_eligible(rest: Node, pony: Node3D) -> bool:
	if not is_instance_valid(rest) or not rest.has_method("eligible"):
		return false
	return bool(rest.call("eligible", pony))


## End a pony's own speech loop; a body without the op keeps speaking.
static func stop_speaking(pony: Node) -> void:
	if is_instance_valid(pony) and pony.has_method("stop_speaking"):
		pony.call("stop_speaking")


## Hold the seated player's Q action; a rig without the member is left alone.
static func set_q_held(body: Node3D, held: bool) -> void:
	if is_instance_valid(body):
		body.set("_q_held", held)


## The seating system's phase for this pony; empty when it has no entry.
static func seating_phase(seating: Node, id: int) -> String:
	if not is_instance_valid(seating):
		return ""
	var users: Variant = seating.get("_users")
	if not users is Dictionary:
		return ""
	var entry: Variant = (users as Dictionary).get(id)
	if not entry is Dictionary:
		return ""
	return str((entry as Dictionary).get("phase", ""))


## Release this pony's seating entry; nothing happens without one.
static func seating_release_entry(seating: Node, id: int) -> void:
	if not is_instance_valid(seating) or not seating.has_method("_release"):
		return
	var users: Variant = seating.get("_users")
	if not users is Dictionary:
		return
	var entry: Variant = (users as Dictionary).get(id)
	if entry is Dictionary:
		seating.call("_release", entry)


## End a couch's guest stay; a rest without the private op is left alone.
static func couch_finish_guest(node: Node3D) -> void:
	if is_instance_valid(node) and node.has_method("_finish_guest"):
		node.call("_finish_guest")


## Release a pony from a couch's occupant list.
static func couch_release_pony(node: Node3D, id: int) -> void:
	if is_instance_valid(node) and node.has_method("_release_pony"):
		node.call("_release_pony", id, false)


## Turn her secondary gaze toward `angles`; false when the body has no gaze controller.
static func look_toward(secondary: Object, angles: Vector3, weight: float) -> bool:
	if not is_instance_valid(secondary) or not secondary.has_method("look_toward"):
		return false
	secondary.call("look_toward", angles, weight)
	return true


## Aim the native eye modifier's pupils at a world point for the frame.
static func aim_eyes(eye_motion: Node, target: Vector3) -> void:
	if not is_instance_valid(eye_motion):
		return
	eye_motion.set("target_world", target)
	eye_motion.set("target_weight", 1.0)


## Where she listens from: her own point, or her root plus `UP` when the body answers none.
static func listen_point(pony: Node) -> Vector3:
	if not is_instance_valid(pony):
		return Vector3.INF
	if pony.has_method("listen_point"):
		var point: Variant = pony.call("listen_point")
		if point is Vector3:
			return point
	if pony is Node3D:
		return (pony as Node3D).global_position + Vector3.UP
	return Vector3.INF


## The act body's posed eye; a transform with an infinite origin when it has none.
static func eye_transform(body: Node) -> Transform3D:
	if not is_instance_valid(body) or not body.has_method("eye_transform"):
		return Transform3D(Basis.IDENTITY, Vector3.INF)
	var eye: Variant = body.call("eye_transform")
	if eye is Transform3D:
		return eye
	return Transform3D(Basis.IDENTITY, Vector3.INF)


## Her skull centre in world space; INF when the body has no head surfaces.
static func skull_world(boop: Node) -> Vector3:
	if not is_instance_valid(boop) or not boop.has_method("skull_world"):
		return Vector3.INF
	var point: Variant = boop.call("skull_world")
	if point is Vector3:
		return point
	return Vector3.INF


## Her nose tip in world space; INF when the body has no head surfaces.
static func nose_world(boop: Node) -> Vector3:
	if not is_instance_valid(boop) or not boop.has_method("nose_world"):
		return Vector3.INF
	var point: Variant = boop.call("nose_world")
	if point is Vector3:
		return point
	return Vector3.INF


## Her muzzle root in world space; INF when the body has no head surfaces.
static func muzzle_world(boop: Node) -> Vector3:
	if not is_instance_valid(boop) or not boop.has_method("muzzle_world"):
		return Vector3.INF
	var point: Variant = boop.call("muzzle_world")
	if point is Vector3:
		return point
	return Vector3.INF


## The eye line the rig reports; NAN when the rig cannot answer.
static func eye_height(player: Node3D) -> float:
	if not is_instance_valid(player) or not player.has_method("eye_height"):
		return NAN
	return float(player.call("eye_height"))


## The rig's private eye placement; a rig without it keeps the property write only.
static func set_eye_y(body: Node3D, y: float) -> void:
	if not is_instance_valid(body) or not body.has_method("_set_eye_y"):
		return
	body.call("_set_eye_y", y)


## Write the rig's standing eye line; a rig without the member is left alone.
static func set_stand_eye(body: Node3D, y: float) -> void:
	if is_instance_valid(body) and body.get("_stand_eye") != null:
		body.set("_stand_eye", y)


## Write the rig's own eye height; a rig without the member is left alone.
static func set_eye_height(body: Node3D, y: float) -> void:
	if is_instance_valid(body) and body.get("_eye_height") != null:
		body.set("_eye_height", y)


## Drop the far-mesh caches for one body; a valid node with no identity uses the "default" key.
static func forget_far_mesh(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	var key: String = HYBRID_FAR_MESH._id(pony)
	HYBRID_FAR_MESH.cache.erase(key)
	HYBRID_FAR_MESH.shadow_cache.erase(key)
	HYBRID_FAR_MESH.eyes_cache.erase(key)


## Drop the merged LOD caches for a body whose shape changed and re-arm its near mesh, so the
## visible body is rebuilt from the new rig instead of the old shape's gather.
static func refresh_body_lod(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	# Only a hybrid body has merged LOD caches; a plain or half-built node has nothing to drop.
	if identity_of(pony) == null:
		return
	HYBRID_NEAR_MESH.cache.erase(HYBRID_NEAR_MESH.key(pony))
	forget_far_mesh(pony)
	if not pony.has_method("set_near_mesh"):
		return
	var enabled: Variant = pony.get("near_mesh_enabled")
	if enabled != null and not bool(enabled):
		return
	set_near_mesh(pony, false)
	set_near_mesh(pony, true)


## The bed a physics hit belongs to; off a bed it answers null.
static func bed_of(collider: Object) -> Node3D:
	var bed: Variant = MATTRESS.bed_of(collider)
	if bed is Node3D and is_instance_valid(bed):
		return bed
	return null


## Mean drawn bedding height (world y) under `points`; the caller's physics top when nothing is drawn.
static func visible_top(bed: Node, points: Array[Vector3], fallback: float) -> float:
	if not is_instance_valid(bed) or not bed is Node3D:
		return fallback
	return MATTRESS.visible_top(bed as Node3D, points, fallback)


## A couch or rest node's `rest_word` answer; empty when it has no op.
static func rest_word(node: Node) -> String:
	if not is_instance_valid(node) or not node.has_method("rest_word"):
		return ""
	return str(node.call("rest_word"))


## The bed a couch or rest node resolves to; null when it has none.
static func rest_bed_of(node: Node) -> Node3D:
	if not is_instance_valid(node):
		return null
	var bed: Variant = node.get("_bed") if node.get("_bed") != null else node.get("bed_node")
	if bed is Node3D and is_instance_valid(bed):
		return bed
	return null


## Let a bed rest re-measure its bed, seats and sleeper; nothing happens without the op.
static func bed_rest_refresh(rest: Node) -> void:
	if is_instance_valid(rest) and rest.has_method("refresh"):
		rest.call("refresh")


## Whether the rest measured that this mare fits; false without the member.
static func bed_rest_fits(rest: Node) -> bool:
	return is_instance_valid(rest) and rest.get("_mare_fits") == true


## Whether the rest already holds a guest row; false without the member.
static func bed_rest_has_guest(rest: Node) -> bool:
	if not is_instance_valid(rest):
		return false
	var guest: Variant = rest.get("_guest")
	return guest is Dictionary and not (guest as Dictionary).is_empty()


## The rest's current sleeper; null when the bed is free or the member is absent.
static func bed_rest_sleeper(rest: Node) -> Node3D:
	if not is_instance_valid(rest):
		return null
	var sleeper: Variant = rest.get("_sleeper")
	if sleeper is Node3D and is_instance_valid(sleeper):
		return sleeper
	return null


## The rest's front stand point for one pony; `Vector3.INF` when it cannot report one.
static func bed_rest_front(rest: Node, pony: Node3D) -> Vector3:
	if not is_instance_valid(rest) or not rest.has_method("_front_for"):
		return Vector3.INF
	var front: Variant = rest.call("_front_for", pony)
	if front is Vector3 and (front as Vector3).is_finite():
		return front
	return Vector3.INF


## The pony lying beside Anon on one couch seat; null without a partner or a live one.
static func couch_partner(couch: Node, seat: Node) -> Node:
	if not is_instance_valid(couch) or not couch.has_method("partner"):
		return null
	var partner: Variant = couch.call("partner", seat)
	if partner is Node and is_instance_valid(partner):
		return partner
	return null


## One PonyTouchBody hull sync for a rig index; a body without the private sync stays stale.
static func touch_sync(body: Object, rig: int) -> void:
	if not is_instance_valid(body) or not body.has_method("_unprofiled_sync"):
		return
	body.call("_unprofiled_sync", rig, true)


## PonyTouchBody's nearest hull; empty when the body has no query.
static func _touch_nearest(body: Object, point: Vector3) -> Dictionary:
	if not is_instance_valid(body) or not body.has_method("nearest"):
		return {}
	var near: Variant = body.call("nearest", point)
	return near if near is Dictionary else {}


## Skin the flank patch to the current pose; a surface without the op keeps its old skin.
static func flank_surface_update(surface: Object, skeleton: Skeleton3D, frame: Transform3D) -> void:
	if not is_instance_valid(surface) or not surface.has_method("update_pose"):
		return
	surface.call("update_pose", skeleton, frame)


## The flank patch's contact query at a local point; empty when it has no query.
static func _flank_surface_contact(surface: Object, point: Vector3, palm: Vector3,
		reach: float) -> Dictionary:
	if not is_instance_valid(surface) or not surface.has_method("contact"):
		return {}
	var hit: Variant = surface.call("contact", point, point, palm, reach)
	return hit if hit is Dictionary else {}


## The native flank decal, blush and jiggle impact; a flank without the op stays still.
static func flank_impact(flank: Node, index: int, at: Vector3, strength: float) -> void:
	if not is_instance_valid(flank) or not flank.has_method("impact"):
		return
	flank.call("impact", index, at, strength)


## Wake the flank's own touch tick; a flank without the op is left alone.
static func flank_wake_tick(flank: Node) -> void:
	if is_instance_valid(flank) and flank.has_method("wake_tick"):
		flank.call("wake_tick")


## Start the flank's own jiggle; false when the flank has no op.
static func flank_start_jiggle(flank: Node, index: int, strength: float) -> bool:
	if not is_instance_valid(flank) or not flank.has_method("_start_jiggle"):
		return false
	flank.call("_start_jiggle", index, strength)
	return true


## Run one flank jiggle frame; a flank without the op is left alone.
static func flank_process(flank: Node, delta: float) -> void:
	if is_instance_valid(flank) and flank.has_method("_process"):
		flank.call("_process", delta)


## The flank's resolved jiggle amount; NAN when the member is absent.
static func flank_jiggle_amount(flank: Node) -> float:
	if not is_instance_valid(flank):
		return NAN
	var amount: Variant = flank.get("_jiggle_amount")
	if amount == null:
		return NAN
	return float(amount)


## Write the flank's resolved jiggle amount; a flank without the member is left alone.
static func set_flank_jiggle_amount(flank: Node, amount: float) -> void:
	if is_instance_valid(flank) and flank.get("_jiggle_amount") != null:
		flank.set("_jiggle_amount", amount)


## Hand the desktop rig one palm target; a rig without the holder is left alone.
static func set_hold_target(driver: Node, side: String, frame: Transform3D,
		kind := "hold") -> void:
	if not is_instance_valid(driver) or not driver.has_method("set_hold_target"):
		return
	driver.call("set_hold_target", side, frame, kind)


## Release one palm target; a rig without the holder is left alone.
static func clear_hold_target(driver: Node, side: String) -> void:
	if not is_instance_valid(driver) or not driver.has_method("clear_hold_target"):
		return
	driver.call("clear_hold_target", side)


## The rig's live palm frame; an infinite transform when the rig cannot answer.
static func hand_frame(driver: Node, side: String) -> Transform3D:
	if not is_instance_valid(driver) or not driver.has_method("hand_frame"):
		return Transform3D(Basis.IDENTITY, Vector3.INF)
	var frame: Variant = driver.call("hand_frame", side)
	if frame is Transform3D:
		return frame
	return Transform3D(Basis.IDENTITY, Vector3.INF)


## Show one short line in the HUD's toast corner; a node without the sink is left alone.
static func show_toast(instance: Node, text: String, seconds: float) -> void:
	if not is_instance_valid(instance) or not instance.has_method("_show_toast"):
		return
	instance.call("_show_toast", text, seconds)


## The inventory's quick-slot HUD flag; false without the member.
static func inventory_hud_hidden(inventory: Object) -> bool:
	if not is_instance_valid(inventory):
		return false
	return inventory.get("hud_hidden") == true


## Hide or restore the inventory's quick-slot HUD; a node without the member is left alone.
static func set_inventory_hud_hidden(inventory: Object, hidden: bool) -> void:
	if is_instance_valid(inventory) and inventory.get("hud_hidden") != null:
		inventory.set("hud_hidden", hidden)


## The inventory's quick-slot bar; null when the inventory has none.
static func hotbar(inventory: Object) -> Node:
	if not is_instance_valid(inventory):
		return null
	var bar: Variant = inventory.get("hotbar")
	if bar is Node and is_instance_valid(bar):
		return bar
	return null


## Whether the quick-slot bar is on screen; false without the member.
static func hotbar_visible(bar: Node) -> bool:
	if not is_instance_valid(bar):
		return false
	return bar.get("visible") == true


## Show or hide the quick-slot bar; a bar without the member is left alone.
static func set_hotbar_visible(bar: Node, visible: bool) -> void:
	if is_instance_valid(bar) and bar.get("visible") != null:
		bar.set("visible", visible)


## The CanvasLayer the quick-slot bar draws on; null when the bar has none.
static func hotbar_hud_layer(bar: Node) -> CanvasLayer:
	if not is_instance_valid(bar):
		return null
	var layer: Variant = bar.get("_hud")
	if layer is CanvasLayer and is_instance_valid(layer):
		return layer
	return null


## Show or hide the quick-slot bar's own HUD layer; a bar without the op is left alone.
static func set_hotbar_hud_visible(bar: Node, visible: bool) -> void:
	if is_instance_valid(bar) and bar.has_method("set_hud_visible"):
		bar.call("set_hud_visible", visible)


## Re-place the inventory's quick slots after its HUD flag changes; nothing without the op.
static func inventory_place_hotbar(inventory: Object) -> void:
	if is_instance_valid(inventory) and inventory.has_method("_place_hotbar"):
		inventory.call("_place_hotbar")


## The seated player's Q hold; false when the rig has no such member.
static func q_held(body: Node3D) -> bool:
	if not is_instance_valid(body):
		return false
	return body.get("_q_held") == true


## Clear the seated player's own space hold; a body without the member is left alone.
static func set_space_hold(body: Node3D, seconds: float) -> void:
	if is_instance_valid(body) and "_space_hold" in body:
		body.set("_space_hold", seconds)


## Set the seated player's rest hold; a body without the member is left alone.
static func set_rest_held(body: Node3D, held: bool) -> void:
	if is_instance_valid(body) and "_rest_held" in body:
		body.set("_rest_held", held)


## Whether the anatomy bridge's oral gate is open; false without a bridge or its op.
static func oral_ready(bridge: Object) -> bool:
	if not is_instance_valid(bridge) or not bridge.has_method("oral_ready"):
		return false
	return bool(bridge.call("oral_ready"))


## One host callable for the VR touch bridge; the typed wrapper keeps the accessor strong.
class TouchBridge:
	var run := Callable()

	## Fire the bridge's `caress` event; an invalid callable stays silent.
	func caress() -> void:
		if run.is_valid():
			run.call("caress")


## Fire the touch host's caress event; an absent host is left alone.
static func caress(touch: TouchBridge) -> void:
	if touch != null:
		touch.caress()


## One stored story line as a typed row; `raw` is the game's own row for its text reader.
class StoryRow:
	var id := ""
	var kind := ""
	var text := ""
	var speaker := ""
	var listener := ""
	var raw: Dictionary = {}

	static func from_dict(row: Dictionary) -> StoryRow:
		var out := StoryRow.new()
		out.raw = row
		out.id = str(row.get("id", ""))
		out.kind = str(row.get("kind", ""))
		out.text = str(row.get("text", ""))
		out.speaker = str(row.get("speaker", ""))
		out.listener = str(row.get("listener", ""))
		return out


## One pony's friendship and love ladder as typed names and levels.
class Ladder:
	var friendship_name := ""
	var friendship_level := -1
	var love_name := ""
	var love_level := -1
	## True when the game answered with a row rather than an absent value.
	var found := false
	var friendship_found := false
	var love_found := false

	static func from_dict(row: Dictionary) -> Ladder:
		var out := Ladder.new()
		out.found = not row.is_empty()
		var friend: Variant = row.get("friendship", {})
		if friend is Dictionary:
			out.friendship_found = true
			out.friendship_name = str((friend as Dictionary).get("name", ""))
			out.friendship_level = int((friend as Dictionary).get("level", -1))
		var love: Variant = row.get("love", {})
		if love is Dictionary:
			out.love_found = true
			out.love_name = str((love as Dictionary).get("name", ""))
			out.love_level = int((love as Dictionary).get("level", -1))
		return out


## One pony's bond record, read once and written back through the store's own save.
class BondRecord:
	var stage := "acquaintance"
	var familiarity := 0.0
	var trust := 0.0
	var anger := 0.0
	var together_s := 0.0
	var plan: Dictionary = {}
	var offer: Dictionary = {}
	var cooldowns: Dictionary = {}
	## The untouched rows, so a key this view does not model survives the save.
	var rows: Dictionary = {}

	static func from_dict(row: Dictionary) -> BondRecord:
		var out := BondRecord.new()
		out.rows = row.duplicate(true)
		out.stage = str(row.get("stage", "acquaintance"))
		out.familiarity = float(row.get("familiarity", 0.0))
		out.trust = float(row.get("trust", 0.0))
		out.anger = float(row.get("anger", 0.0))
		out.together_s = float(row.get("together_s", 0.0))
		var stored_plan: Variant = row.get("plan", {})
		out.plan = stored_plan if stored_plan is Dictionary else {}
		var stored_offer: Variant = row.get("offer", {})
		out.offer = stored_offer if stored_offer is Dictionary else {}
		var stored_cooldowns: Variant = row.get("cooldowns", {})
		out.cooldowns = stored_cooldowns if stored_cooldowns is Dictionary else {}
		return out

	func to_row() -> Dictionary:
		var row := rows
		row["stage"] = stage
		row["familiarity"] = familiarity
		row["trust"] = trust
		row["anger"] = anger
		row["together_s"] = together_s
		row["plan"] = plan
		row["offer"] = offer
		row["cooldowns"] = cooldowns
		return row

	## Write the view back through the store's own save; false without the op.
	func save(bonds: Object, id: String) -> bool:
		if not is_instance_valid(bonds) or not bonds.has_method("_save"):
			return false
		bonds.call("_save", id, to_row())
		return true


## One mod's live state section: the Dictionary the registry keeps, read and written in place.
class ModState:
	var rows: Dictionary = {}


## The director's authored-line host: the greeting, the generated-intent queue and the cancel.
class DirectorLines:
	var director: Node = null

	## Greet in the director's own opening line; false when it refuses or has no op.
	func greet(id: String, context: String) -> bool:
		if not is_instance_valid(director) or not director.has_method("begin_player_greeting"):
			return false
		return bool(director.call("begin_player_greeting", id, context))

	## Queue one authored line with the game's own validity callback; false when it refuses.
	func queue(id: String, purpose: String, key: String, valid: Callable,
			priority: bool) -> bool:
		if not is_instance_valid(director) or not director.has_method("queue_generated_intent"):
			return false
		return bool(director.call("queue_generated_intent", id, purpose, key, valid,
			Callable(), priority))

	## Queue one authored line that also reports when it finishes; false when it refuses.
	func queue_finished(id: String, purpose: String, key: String, valid: Callable,
			finished: Callable, once: bool, firm: bool) -> bool:
		if not is_instance_valid(director) or not director.has_method("queue_generated_intent"):
			return false
		return bool(director.call("queue_generated_intent", id, purpose, key, valid,
			finished, once, firm))

	## Cancel one authored line the queue still holds; false when it has no op.
	func cancel(key: String) -> bool:
		if not is_instance_valid(director) or not director.has_method("cancel_authored_line"):
			return false
		director.call("cancel_authored_line", key)
		return true


## One director's live model configuration: the section a client configures from and its status.
class LlmConfig:
	var section: Dictionary = {}
	var status_path := ""
	## The game's AI gate allows a model call and the director can hand over its section.
	var enabled := false


## Write the navigator's face point; a node without the member is left alone.
static func set_face_point(nav: Node, point: Vector3) -> void:
	if is_instance_valid(nav) and "face_point" in nav:
		nav.set("face_point", point)


## Drop the navigator's conversation facing; a node without the setter is left alone.
static func clear_conversation_target(nav: Node) -> void:
	if is_instance_valid(nav) and nav.has_method("set_conversation_target"):
		nav.call("set_conversation_target", null, false)


## Hand her own locomotion facing a direction; a body without the turn is left alone.
static func face_direction(pony: Node, direction: Vector3) -> void:
	if is_instance_valid(pony) and pony.has_method("face_direction"):
		pony.call("face_direction", direction)


## Whether an identity resource has wings; an absent op reads as no wings.
static func identity_has_wings(identity: Object) -> bool:
	if not is_instance_valid(identity) or not identity.has_method("has_wings"):
		return false
	return bool(identity.call("has_wings"))


## The excitement Beat's wing node, through its private member; null when absent.
static func wings_of(excitement: Node) -> Node:
	if not is_instance_valid(excitement) or not excitement.has_method("_wings"):
		return null
	var wings: Variant = excitement.call("_wings")
	if wings is Node and is_instance_valid(wings):
		return wings
	return null


## Take the wing hold at `value`; false without the hold op or when it refuses.
static func wing_hold_at(wings: Node, owner: String, value: float) -> bool:
	if not is_instance_valid(wings) or not wings.has_method("hold_at"):
		return false
	return bool(wings.call("hold_at", owner, value))


## Release the wing hold `owner` took; a node without the op is left alone.
static func wing_release_hold(wings: Node, owner: String) -> void:
	if is_instance_valid(wings) and wings.has_method("release_hold"):
		wings.call("release_hold", owner)


## Ask the wing node to open or close; a node without the op is left alone.
static func wing_set_open(wings: Node, open: bool) -> void:
	if is_instance_valid(wings) and wings.has_method("set_open"):
		wings.call("set_open", open)


## Fire the excitement Beat's stock wing spread; a Beat without the op is left alone.
static func wing_spread(excitement: Node, seconds: float) -> void:
	if is_instance_valid(excitement) and excitement.has_method("spread"):
		excitement.call("spread", seconds)


## Flutter her wings through the excitement Beat; a Beat without the op stays still.
static func wing_flutter(excitement: Node) -> void:
	if is_instance_valid(excitement) and excitement.has_method("flutter"):
		excitement.call("flutter")


## Whether the wing node shows its open meshes; an absent flag reads closed.
static func wing_opened(wings: Node) -> bool:
	if not is_instance_valid(wings):
		return false
	return wings.get("opened") == true


## Show or hide the wing node's open meshes.
static func set_wing_opened(wings: Node, open: bool) -> void:
	if is_instance_valid(wings):
		wings.set("opened", open)


## Write the wing node's tuck blend.
static func set_wing_tuck(wings: Node, value: float) -> void:
	if is_instance_valid(wings):
		wings.set("tuck", value)


## Write the wing node's half-open blend.
static func set_wing_half(wings: Node, value: float) -> void:
	if is_instance_valid(wings):
		wings.set("half", value)


## Forward one desktop torso pose to the body's own driver; a driver without the op is left alone.
static func apply_torso_pose(driver: Node, hip: Node3D, facing: Basis) -> void:
	if is_instance_valid(driver) and driver.has_method("apply_torso_pose"):
		driver.call("apply_torso_pose", hip, facing)


## Hand both rest-hand targets to the body's own driver; without the op they keep their own.
static func set_rest_hand_targets(driver: Node, left: Node3D, right: Node3D) -> void:
	if is_instance_valid(driver) and driver.has_method("set_rest_hand_targets"):
		driver.call("set_rest_hand_targets", left, right)


## Release both rest-hand targets; a driver without the op is left alone.
static func clear_rest_hand_targets(driver: Node, left: Node3D, right: Node3D) -> void:
	if is_instance_valid(driver) and driver.has_method("clear_rest_hand_targets"):
		driver.call("clear_rest_hand_targets", left, right)


## The desktop rig's own pose driver; null when the body has none.
static func desktop_pose_driver(avatar: Node) -> Node:
	if not is_instance_valid(avatar):
		return null
	return avatar.get("desktop_pose_driver") as Node


## Replace the desktop rig's pose driver; a body without the member is left alone.
static func set_desktop_pose_driver(avatar: Node, driver: Node) -> void:
	if is_instance_valid(avatar):
		avatar.set("desktop_pose_driver", driver)


## Her awareness facing from the body's own op; a zero vector when the body cannot answer.
static func awareness_forward(pony: Node) -> Vector3:
	if not is_instance_valid(pony) or not pony.has_method("awareness_forward"):
		return Vector3.ZERO
	var forward: Variant = pony.call("awareness_forward")
	return forward if forward is Vector3 else Vector3.ZERO


## Clamp one local bone basis with the pony's joint limits; the input when they cannot answer.
static func joint_constrain(limits: Object, bone: int, basis: Basis) -> Basis:
	if not is_instance_valid(limits) or not limits.has_method("constrain"):
		return basis
	var held: Variant = limits.call("constrain", bone, basis)
	return held if held is Basis else basis
