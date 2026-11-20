extends RefCounted
## Service: world
## Contract: docs/world.md `## Base-game access`
## Stateless readers for the base-game members the mod touches; the scene root is an argument.

const MATTRESS := preload("res://world/life/couch/mattress.gd")
const HYBRID_NEAR_MESH := preload("res://world/characters/hybrid_mare/hybrid_near_mesh.gd")
const HYBRID_FAR_MESH := preload("res://world/characters/hybrid_mare/hybrid_far_mesh.gd")


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


## One named game panel; the caller decides what an open panel means.
static func menu_panel(game: Node, key: StringName) -> Node:
	if not is_instance_valid(game):
		return null
	var panel: Variant = game.get(key)
	if panel is Node and is_instance_valid(panel):
		return panel
	return null


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


## Feed the blush sustainer; a body without one stays silent.
static func sustain_blush(boop: Node, amount: float) -> void:
	if not is_instance_valid(boop) or not boop.has_method("sustain_blush"):
		return
	boop.call("sustain_blush", amount)


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


## Let a form driver apply its own view limit; a body without one keeps the camera as it is.
static func clamp_view(form: Node) -> void:
	if not is_instance_valid(form) or not form.has_method("clamp_view"):
		return
	form.call("clamp_view")


## Clear a pony's navigator face point so a stale conversation aim cannot turn her.
static func clear_face_point(pony: Node) -> void:
	var nav := _navigator(pony)
	if nav == null or not "face_point" in nav:
		return
	nav.set("face_point", Vector3.INF)


## Clear her navigator conversation target, which would otherwise face her away from the act.
static func clear_conversation_target(pony: Node) -> void:
	var nav := _navigator(pony)
	if nav == null or not nav.has_method("set_conversation_target"):
		return
	nav.call("set_conversation_target", null, false)


## The pony's navigator node; null when the body has none.
static func _navigator(pony: Node) -> Node:
	if not is_instance_valid(pony):
		return null
	return pony.get_node_or_null("Navigator")


## Turn her secondary gaze toward `angles`; false when the body has no gaze controller.
static func look_toward(secondary: Node, angles: Vector3, weight: float) -> bool:
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


## Drop the merged LOD caches for a body whose shape changed and re-arm its near mesh, so the
## visible body is rebuilt from the new rig instead of the old shape's gather.
static func refresh_body_lod(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	# Only a hybrid body has merged LOD caches; a plain or half-built node has nothing to drop.
	if identity_of(pony) == null:
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
	set_near_mesh(pony, false)
	set_near_mesh(pony, true)


## The bed a physics hit belongs to; off a bed it answers null.
static func bed_of(collider: Object) -> Node3D:
	var bed: Variant = MATTRESS.bed_of(collider)
	if bed is Node3D and is_instance_valid(bed):
		return bed
	return null
