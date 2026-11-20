extends SceneTree
## The world facade: the bound scene handles, the camera cache, the bed resolution, the menu and
## headset gates, the player body and mare reads, the LOD rebuild and the act chat.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/world/test_world.gd

const WORLD := preload("res://mods/unfplap/world/service.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const HYBRID_NEAR_MESH := preload("res://world/characters/hybrid_mare/hybrid_near_mesh.gd")
const HYBRID_FAR_MESH := preload("res://world/characters/hybrid_mare/hybrid_far_mesh.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


class FakePlayer extends Node3D:
	var seat: Variant = null
	var camera: Variant = null
	var controls_locked := false
	var form_driver: Variant = null
	var eye_line := 1.5

	func eye_height() -> float:
		return eye_line


class FakeGame extends Node:
	var mares: Array = []
	var headset_view := false
	var inventory: Variant = null
	var save_menu: Variant = null
	var player: Variant = null
	var found_camera: Variant = null
	var find_calls := 0

	func _find_camera(_body: Variant) -> Variant:
		find_calls += 1
		return found_camera


## The same world without `_find_camera`: the viewport camera is the fallback.
class BareGame extends Node:
	var mares: Array = []
	var headset_view := false


class FakeMare extends Node3D:
	var requested := "stand"

	func posture_status() -> Dictionary:
		return {"requested": requested}


class FakePanel extends Node:
	var opened := false
	var active := false


class FakeCase extends Control:
	pass


class FakeInventory extends Node:
	var case: Variant = null
	var customizer: Variant = null
	var inspector: Variant = null


class FakeMapInventory extends FakeInventory:
	func _map_open() -> bool:
		return true


class FakeChat extends Node:
	var opened := false
	var saw_unlocked := false
	var watcher: Variant = null
	var _lock_owned := true

	func _open() -> bool:
		opened = true
		if watcher != null:
			saw_unlocked = not bool(watcher.get("controls_locked"))
		return opened


class FakeSeat extends Node3D:
	pass


class FakeIdentity extends Resource:
	var id := "fake_mare"


class FakeBody extends Node3D:
	var identity: Resource = FakeIdentity.new()
	var reference_face_enabled := false
	var shading_version := 3
	var head_width := 1.0
	var head_width_factor := 1.0
	var near_mesh_enabled := true
	var near_calls: Array = []
	var boop_node: Variant = null
	var body_scale: Variant = null
	var head: Variant = null
	var eye_y := 0.0
	var skeleton: Skeleton3D
	var hair_skeleton: Skeleton3D
	var hair: Node3D
	var _model: Node
	var hair_link: Node
	var _far_mesh_shown := false
	var eye_motion: Node

	func set_near_mesh(enabled: bool) -> void:
		near_calls.append(enabled)

	func _set_eye_y(value: float) -> void:
		eye_y = value


## The game's hair link: the pelvis offset the tail seat writes and its private body update.
class FakeHairLink extends Node:
	var pelvis_offset := Transform3D(Basis(), Vector3(0.0, 1.0, 2.0))
	var updates := 0

	func _body_updated() -> void:
		updates += 1


## A body that never grew the eye-line setter: the accessor must leave its field alone.
class FakePlainBody extends Node3D:
	var eye_y := 0.0


class FakeBoop extends Node:
	var amount := -1.0
	var head_skeleton: Skeleton3D

	func sustain_blush(value: float) -> void:
		amount = value


class FakeMouth extends Node:
	var visemes: Array[String] = []
	var clears := 0

	func set_viseme(letter: String, _blend := -1.0) -> void:
		visemes.append(letter)

	func clear() -> void:
		clears += 1


class FakeHead extends Node:
	var mouth: Variant = null


class FakeFlank extends Node:
	var calls := 0

	func _own_body_materials() -> void:
		calls += 1


class FakeForm extends RefCounted:
	var avatar: Variant = null


func run() -> void:
	_check_unbound()
	_check_binding()
	_check_game_player()
	_check_accessors()
	_check_camera()
	_check_player_body()
	_check_real_bed()
	_check_bed_occupancy()
	_check_player_beside_bed()
	_check_menu_and_headset()
	_check_open_act_chat()
	_check_body_lod()
	_check_desktop()
	await _check_bed_under()
	_check_freed_handles()
	WORLD.unbind()
	check(WORLD.game == null and WORLD.player == null, "unbind clears the bound handles")

	print("WORLD_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


## A bound handle freed without unbind answers the unbound values, not a dead node's.
func _check_freed_handles() -> void:
	var game := FakeGame.new()
	root.add_child(game)
	var player := FakePlayer.new()
	root.add_child(player)
	WORLD.bind_world(game)
	WORLD.bind_player(player)
	game.free()
	player.free()
	check(WORLD.headset_view() == false, "a freed world is no headset")
	check(WORLD.game_player() == null, "a freed world has no game player")
	check(WORLD.mares().is_empty(), "a freed world has no mares")
	check(not WORLD.menu_panel_open(), "a freed world has no open panel")
	check(WORLD.camera() == null, "a freed rig has no camera")
	check(not WORLD.open_act_chat(), "a freed world opens no chat")
	WORLD.unbind()


func _check_unbound() -> void:
	WORLD.unbind()
	check(WORLD.game == null and WORLD.player == null, "an unbound facade has no world")
	check(WORLD.camera() == null, "an unbound facade has no camera")
	check(WORLD.interactor() == null, "an unbound facade has no interactor")
	check(WORLD.player_body() == null, "an unbound facade has no player body")
	check(WORLD.mares().is_empty(), "an unbound facade has no mares")
	check(WORLD.bed_under(Vector3.ZERO) == null, "an unbound facade finds no bed")
	check(WORLD.real_bed(null) == null, "no node is no bed")
	check(WORLD.bed_for_cradle(null) == null, "no pony is no cradle bed")
	check(not WORLD.bed_occupied(null, null), "no bed is not occupied")
	check(not WORLD.player_beside_bed(null), "no player is not beside a bed")
	check(not WORLD.headset_view(), "no world is no headset")
	check(not WORLD.open_act_chat(), "no world opens no chat")
	WORLD.refresh_body_lod(null)


func _check_binding() -> void:
	var game := FakeGame.new()
	root.add_child(game)
	var list: Array = [FakeMare.new(), FakeMare.new()]
	game.mares = list
	WORLD.bind_world(game)
	check(WORLD.game == game, "bind_world stores the world root")
	check(not is_same(WORLD.mares(), list), "the facade answers with a copy, not the game array")
	check(WORLD.mares().size() == list.size(), "the copy holds every mare")
	WORLD.bind_player(FakePlayer.new())
	check(WORLD.player != null, "bind_player stores Anon's body")
	WORLD.bind_world(null)
	check(WORLD.player != null, "a world bind keeps the player")
	check(WORLD.game == null, "a null world bind clears the world")
	WORLD.bind_world(game)
	WORLD.bind_player(null)
	check(WORLD.game == game and WORLD.player == null, "the player leaves on its own")
	game.queue_free()
	WORLD.unbind()


## Every base-game accessor: the live answer and the absent one.
func _check_accessors() -> void:
	var player := FakePlayer.new()
	root.add_child(player)
	var camera := Camera3D.new()
	player.add_child(camera)
	player.camera = camera
	check(GAME.player_camera(player) == camera, "the rig's own camera is read")
	check(GAME.player_camera(null) == null, "no rig reads no camera")
	var plain := Node3D.new()
	root.add_child(plain)
	check(GAME.player_camera(plain) == null, "a rig without a camera reads null")

	var game := FakeGame.new()
	root.add_child(game)
	var found := Camera3D.new()
	root.add_child(found)
	game.found_camera = found
	check(GAME.find_camera(game, player) == found, "the scene's camera search is read")
	check(GAME.find_camera(plain, player) == null, "a scene without the search finds no camera")
	check(GAME.find_camera(game, null) == null, "no player finds no camera")

	var mare := FakeMare.new()
	var stray := Node.new()
	root.add_child(mare)
	root.add_child(stray)
	game.mares = [mare, stray, null]
	var copy := GAME.mares(game)
	check(copy.size() == 1 and copy[0] == mare, "the mare copy keeps only live bodies")
	check(GAME.mares(null).is_empty(), "no world copies no mares")

	var avatar := Node3D.new()
	player.add_child(avatar)
	var form := FakeForm.new()
	form.avatar = avatar
	player.form_driver = form
	check(GAME.player_avatar(player) == avatar, "the form driver's avatar is read")
	check(GAME.player_avatar(plain) == null, "a rig without a form has no avatar")
	var body := Node3D.new()
	body.name = "Body"
	plain.add_child(body)
	check(GAME.player_body_node(plain) == body, "the rig's Body child is found")
	check(GAME.player_body_node(null) == null, "no rig has no body child")

	var seat := FakeSeat.new()
	player.seat = seat
	check(GAME.seat_of(player) == seat, "the rig's seat is read")
	check(GAME.seat_of(plain) == null, "a standing rig has no seat")

	player.controls_locked = true
	check(GAME.controls_locked(player), "a held rig reads locked")
	GAME.set_controls_locked(player, false)
	check(not player.controls_locked, "the hold is released")
	check(not GAME.controls_locked(plain), "an absent hold flag reads unlocked")
	GAME.set_controls_locked(null, true)

	check(GAME.menu_panel(game, "settings_menu") == null, "an absent panel reads null")
	var save_menu := FakePanel.new()
	game.save_menu = save_menu
	check(GAME.menu_panel(game, "save_menu") == save_menu, "a named panel is read")
	check(GAME.menu_panel(null, "save_menu") == null, "no world reads no panel")

	var inventory := FakeInventory.new()
	game.inventory = inventory
	check(GAME.inventory(game) == inventory, "the inventory is read")
	check(GAME.inventory(null) == null, "no world has no inventory")
	check(not GAME.map_open(inventory), "an inventory without a map test is closed")
	var map_inventory := FakeMapInventory.new()
	root.add_child(map_inventory)
	check(GAME.map_open(map_inventory), "the inventory's own map test answers")
	var briefcase := FakeCase.new()
	briefcase.visible = true
	inventory.case = briefcase
	check(GAME.case_visible(inventory), "a visible briefcase reads open")
	briefcase.visible = false
	check(not GAME.case_visible(inventory), "a hidden briefcase reads closed")
	var customizer := FakePanel.new()
	customizer.opened = true
	inventory.customizer = customizer
	check(GAME.customizer_opened(inventory), "an opened customizer reads open")
	var inspector := FakePanel.new()
	inspector.active = true
	inventory.inspector = inspector
	check(GAME.inspector_active(inventory), "an active inspector reads active")
	check(not GAME.inspector_active(null), "no inventory has no inspector")

	var chat := FakeChat.new()
	chat.name = "ChatBox"
	chat.watcher = player
	game.add_child(chat)
	player.controls_locked = true
	check(GAME.chat_box(game) == chat, "the chat box is read by name")
	check(GAME.open_chat(game, player), "the chat opens past the hold")
	check(chat.saw_unlocked, "the hold is released while the chat opens")
	check(player.controls_locked, "the hold is restored after the chat opens")
	check(not GAME.open_chat(null, player), "no world opens no chat")

	var pony := FakeBody.new()
	root.add_child(pony)
	check(GAME.identity_of(pony) == pony.identity, "a hybrid identity is read")
	check(GAME.identity_of(plain) == null, "a plain node has no identity")
	var boop := FakeBoop.new()
	pony.boop_node = boop
	check(GAME.boop_of(pony) == boop, "the blush sustainer is read")
	check(GAME.boop_of(plain) == null, "a body without a sustainer reads null")
	GAME.sustain_blush(boop, 0.5)
	check(boop.amount == 0.5, "the sustainer takes the amount")
	GAME.sustain_blush(plain, 0.7)
	check(boop.amount == 0.5, "a node without the method stays silent")
	var head_skeleton := Skeleton3D.new()
	boop.add_child(head_skeleton)
	boop.head_skeleton = head_skeleton
	check(GAME.head_skeleton_of(boop) == head_skeleton, "the sustainer's head skeleton is read")
	check(GAME.head_skeleton_of(plain) == null, "a plain node has no head skeleton")
	var head := FakeHead.new()
	root.add_child(head)
	var mouth := FakeMouth.new()
	head.add_child(mouth)
	head.mouth = mouth
	pony.head = head
	check(GAME.head_of(pony) == head, "the head node is read")
	check(GAME.head_of(plain) == null, "a plain node has no head")
	check(GAME.mouth_of(head) == mouth, "the head's mouth rig is read")
	check(GAME.mouth_of(plain) == null, "a plain head has no mouth")
	GAME.set_viseme(mouth, "D")
	check(mouth.visemes == ["D"], "the viseme is written to the mouth rig")
	GAME.set_viseme(plain, "D")
	check(mouth.visemes == ["D"], "a node without the viseme method stays silent")
	GAME.clear_viseme(mouth)
	check(mouth.clears == 1, "the viseme clear reaches the mouth rig")
	GAME.clear_viseme(plain)
	check(mouth.clears == 1, "a node without the clear method stays silent")
	head.queue_free()

	# The body members the anatomy reads: skeleton, hair, model, dock link, LOD and the eye rig.
	var rig := FakeBody.new()
	root.add_child(rig)
	var body_skeleton := Skeleton3D.new()
	rig.add_child(body_skeleton)
	rig.skeleton = body_skeleton
	var hair_skeleton := Skeleton3D.new()
	rig.add_child(hair_skeleton)
	rig.hair_skeleton = hair_skeleton
	var hair := Node3D.new()
	rig.add_child(hair)
	rig.hair = hair
	var model := Node3D.new()
	rig.add_child(model)
	rig._model = model
	var drawn_body := MeshInstance3D.new()
	drawn_body.name = "MareBody"
	model.add_child(drawn_body)
	var link := FakeHairLink.new()
	rig.add_child(link)
	rig.hair_link = link
	var eye := SkeletonModifier3D.new()
	rig.add_child(eye)
	rig.eye_motion = eye
	rig.body_scale = 1.25
	var dock := MeshInstance3D.new()
	dock.name = "OpenPonyDock"
	rig.add_child(dock)
	check(GAME.skeleton_of(rig) == body_skeleton, "the body skeleton is read")
	check(GAME.skeleton_of(plain) == null, "a plain node has no body skeleton")
	check(GAME.hair_skeleton_of(rig) == hair_skeleton, "the hair skeleton is read")
	check(GAME.hair_skeleton_of(plain) == null, "a plain node has no hair skeleton")
	check(GAME.hair_of(rig) == hair, "the hair node is read")
	check(GAME.hair_of(plain) == null, "a plain node has no hair")
	check(GAME.dock_of(rig) == dock, "the game dock is found under the pony")
	check(GAME.dock_of(plain) == null, "a plain node has no dock")
	check(is_equal_approx(GAME.body_scale_of(rig), 1.25), "the body scale is read")
	check(is_equal_approx(GAME.body_scale_of(plain), 1.0), "an absent body scale answers 1.0")
	var flank := FakeFlank.new()
	flank.name = "FlankTouch"
	rig.add_child(flank)
	GAME.own_body_materials(rig)
	check(flank.calls == 1, "the per-pony body materials are copied")
	GAME.own_body_materials(plain)
	check(flank.calls == 1, "a pony without FlankTouch stays silent")
	check(GAME.model_of(rig) == model, "the model root is read")
	check(GAME.model_of(plain) == null, "a plain node has no model")
	check(GAME.body_of(rig) == drawn_body, "the drawn MareBody is found under the model")
	check(GAME.body_of(plain) == null, "a plain node has no drawn body")
	check(GAME.hair_link_of(rig) == link, "the hair link is read")
	check(GAME.hair_link_of(plain) == null, "a plain node has no hair link")
	check(GAME.hair_link_ready(rig), "a link with a pelvis offset is ready")
	check(GAME.hair_link_pelvis(rig) == link.pelvis_offset, "the pelvis offset is read")
	check(not GAME.hair_link_ready(plain), "a node without a link is not ready")
	check(GAME.hair_link_pelvis(plain) == Transform3D.IDENTITY,
		"an absent link answers the identity")
	GAME.set_hair_link_pelvis(rig, Transform3D.IDENTITY)
	check(rig.hair_link.pelvis_offset == Transform3D.IDENTITY, "the pelvis offset is written")
	GAME.notify_hair_link(rig)
	check(link.updates == 1, "the link's body update is forwarded")
	GAME.set_hair_link_pelvis(plain, Transform3D.IDENTITY)
	GAME.notify_hair_link(plain)
	check(not GAME.far_mesh_shown(rig), "the near mesh reads as the shown one")
	rig._far_mesh_shown = true
	check(GAME.far_mesh_shown(rig), "the far mesh flag is read")
	check(not GAME.far_mesh_shown(plain), "a plain node is never far")
	GAME.set_near_mesh(rig, false)
	check(rig.near_calls == [false], "the near-mesh switch is forwarded")
	GAME.set_near_mesh(plain, true)
	check(GAME.eye_motion_of(rig) == eye, "the eye modifier is read")
	check(GAME.eye_motion_of(plain) == null, "a plain node has no eye modifier")
	var anon := Node3D.new()
	anon.name = "AnonBody"
	player.add_child(anon)
	check(GAME.anon_body_of(player) == anon, "Anon's body is found under the rig")
	check(GAME.anon_body_of(plain) == null, "a rig without Anon's body answers null")
	anon.queue_free()
	eye.queue_free()
	flank.queue_free()
	dock.queue_free()
	link.queue_free()
	drawn_body.queue_free()
	model.queue_free()
	hair.queue_free()
	hair_skeleton.queue_free()
	body_skeleton.queue_free()
	rig.queue_free()

	check(GAME.headset_view(null) == false, "no world is no headset")
	check(GAME.game_player(null) == null, "no world has no game player")
	check(GAME.chat_box(null) == null, "no world has no chat box")
	check(GAME.identity_of(null) == null, "no pony has no identity")
	check(GAME.boop_of(null) == null, "no pony has no sustainer")
	check(is_nan(GAME.eye_height(null)), "no rig answers NAN")

	check(GAME.eye_height(player) == player.eye_line, "the rig's eye line is read")
	check(is_nan(GAME.eye_height(plain)), "a rig without the read answers NAN")
	GAME.set_eye_y(pony, 1.4)
	check(pony.eye_y == 1.4, "the eye setter writes the line")
	var bare := FakePlainBody.new()
	root.add_child(bare)
	GAME.set_eye_y(bare, 1.4)
	check(bare.eye_y == 0.0, "a rig without the setter is left alone")

	var bed := Node3D.new()
	bed.set_meta("mattress_top", 0.6)
	root.add_child(bed)
	var support := Node3D.new()
	bed.add_child(support)
	check(GAME.bed_of(support) == bed, "a mattress ancestor is the bed")
	check(GAME.bed_of(bare) == null, "a plain collider is no bed")
	check(GAME.bed_of(null) == null, "no collider is no bed")

	var cached := HYBRID_NEAR_MESH.cache.size()
	GAME.refresh_body_lod(plain)
	check(HYBRID_NEAR_MESH.cache.size() == cached, "a plain node has no LOD cache to drop")

	chat.queue_free()
	pony.queue_free()
	bare.queue_free()
	bed.queue_free()
	save_menu.queue_free()
	inventory.queue_free()
	map_inventory.queue_free()
	customizer.queue_free()
	inspector.queue_free()
	briefcase.queue_free()
	stray.queue_free()
	mare.queue_free()
	plain.queue_free()
	player.queue_free()
	game.queue_free()
	found.queue_free()


## The game's own player read stays defensive: a missing or renamed property is null, not a crash.
func _check_game_player() -> void:
	WORLD.unbind()
	check(WORLD.game_player() == null, "an unbound facade has no game player")
	var game := FakeGame.new()
	root.add_child(game)
	WORLD.bind_world(game)
	check(WORLD.game_player() == null, "a game without a player read has no game player")
	var player := FakePlayer.new()
	root.add_child(player)
	game.player = player
	check(WORLD.game_player() == player, "the game's player property is read defensively")
	var wrong := Node.new()
	root.add_child(wrong)
	game.player = wrong
	check(WORLD.game_player() == null, "a non-Node3D player reads as null")
	game.player = null
	player.queue_free()
	wrong.queue_free()
	game.queue_free()
	WORLD.unbind()


func _check_camera() -> void:
	var player := FakePlayer.new()
	var direct := Camera3D.new()
	root.add_child(player)
	player.add_child(direct)
	player.camera = direct
	WORLD.bind_player(player)
	check(WORLD.camera() == direct, "Anon's own camera wins")

	player.camera = null
	var game := FakeGame.new()
	root.add_child(game)
	WORLD.bind_world(game)
	WORLD.camera()
	WORLD.camera()
	check(game.find_calls == 1, "the found camera is cached for a second")

	var bare := BareGame.new()
	root.add_child(bare)
	WORLD.bind_world(bare)
	check(WORLD.camera() == root.get_camera_3d(),
		"no player camera and no find hook read the viewport camera")

	WORLD.bind_player(null)
	check(WORLD.camera() == null, "no player is no camera")
	player.queue_free()
	game.queue_free()
	bare.queue_free()
	WORLD.unbind()


func _check_player_body() -> void:
	var player := FakePlayer.new()
	root.add_child(player)
	WORLD.bind_player(player)
	check(WORLD.player_body() == player, "the rig is the body when it has no Body child")
	var body := Node3D.new()
	body.name = "Body"
	player.add_child(body)
	check(WORLD.player_body() == body, "the rig's Body child is the shown body")
	var avatar := Node3D.new()
	avatar.name = "AnonBody"
	player.add_child(avatar)
	var form := FakeForm.new()
	form.avatar = avatar
	player.form_driver = form
	check(WORLD.player_body() == avatar, "the AnonPony avatar wins")
	player.queue_free()
	WORLD.unbind()


func _check_real_bed() -> void:
	var bed := Node3D.new()
	bed.set_meta("mattress_top", 0.6)
	root.add_child(bed)
	var support := Node3D.new()
	bed.add_child(support)
	check(WORLD.real_bed(support) == bed, "a mattress ancestor is the bed")
	var rest_support := Node3D.new()
	rest_support.set_meta("shared_rest_support", true)
	bed.add_child(rest_support)
	check(WORLD.real_bed(rest_support) == bed, "a shared rest support resolves to its parent")
	var soft := Node3D.new()
	soft.set_meta("soft_support", true)
	root.add_child(soft)
	check(WORLD.real_bed(soft) == soft, "a soft support is its own bed")
	var floor := Node3D.new()
	root.add_child(floor)
	check(WORLD.real_bed(floor) == null, "a plain node is no bed")
	bed.queue_free()
	soft.queue_free()
	floor.queue_free()


func _check_bed_occupancy() -> void:
	var game := FakeGame.new()
	root.add_child(game)
	var bed := Node3D.new()
	bed.set_meta("mattress_top", 0.6)
	root.add_child(bed)
	var target := FakeMare.new()
	var neighbour := FakeMare.new()
	neighbour.requested = "lie_down"
	root.add_child(target)
	root.add_child(neighbour)
	game.mares = [target, neighbour]
	neighbour.global_position = bed.to_global(Vector3(0.0, 0.6, 0.0))
	WORLD.bind_world(game)
	check(WORLD.bed_occupied(bed, target), "a lying mare on the mattress top occupies it")
	check(not WORLD.bed_occupied(bed, neighbour), "the target never occupies its own bed")
	neighbour.requested = "stand"
	check(not WORLD.bed_occupied(bed, target), "a standing mare does not occupy the bed")
	neighbour.requested = "lie_down"
	neighbour.global_position = bed.to_global(Vector3(3.0, 0.6, 0.0))
	check(not WORLD.bed_occupied(bed, target), "a mare across the room does not occupy it")
	neighbour.global_position = bed.to_global(Vector3(0.0, 1.8, 0.0))
	check(not WORLD.bed_occupied(bed, target), "a mare a storey up does not occupy it")
	game.queue_free()
	bed.queue_free()
	target.queue_free()
	neighbour.queue_free()
	WORLD.unbind()


func _check_player_beside_bed() -> void:
	var game := FakeGame.new()
	root.add_child(game)
	WORLD.bind_world(game)
	var bed := Node3D.new()
	root.add_child(bed)
	var player := FakePlayer.new()
	root.add_child(player)
	WORLD.bind_player(player)
	check(WORLD.player_beside_bed(bed), "a standing Anon is beside the bed")
	var seat := FakeSeat.new()
	bed.add_child(seat)
	player.seat = seat
	check(WORLD.player_beside_bed(bed), "a seat on the bed is beside it")
	var elsewhere := FakeSeat.new()
	root.add_child(elsewhere)
	player.seat = elsewhere
	check(not WORLD.player_beside_bed(bed), "a seat elsewhere is not beside it")
	player.queue_free()
	bed.queue_free()
	elsewhere.queue_free()
	game.queue_free()
	WORLD.unbind()


func _check_menu_and_headset() -> void:
	var game := FakeGame.new()
	root.add_child(game)
	WORLD.bind_world(game)
	check(not WORLD.menu_panel_open(), "an empty world has no open panel")
	var save_menu := FakePanel.new()
	save_menu.opened = true
	game.save_menu = save_menu
	check(WORLD.menu_panel_open(), "an opened save menu owns the mouse")
	save_menu.opened = false
	check(not WORLD.menu_panel_open(), "a closed save menu does not")
	var inventory := FakeInventory.new()
	var case := FakeCase.new()
	case.visible = true
	inventory.case = case
	root.add_child(inventory)
	game.inventory = inventory
	check(WORLD.menu_panel_open(), "a visible briefcase owns the mouse")
	case.visible = false
	check(not WORLD.menu_panel_open(), "a hidden briefcase does not")
	check(WORLD.menu_open() == (Input.mouse_mode != Input.MOUSE_MODE_CAPTURED),
		"menu_open adds the visible cursor to the panel test")
	game.headset_view = true
	check(WORLD.headset_view(), "the world's headset flag is the headset view")
	paused = true
	check(WORLD.menu_panel_open(), "a paused tree is an open panel")
	paused = false
	game.queue_free()
	inventory.queue_free()
	WORLD.unbind()


func _check_open_act_chat() -> void:
	var game := FakeGame.new()
	root.add_child(game)
	var player := FakePlayer.new()
	root.add_child(player)
	var chat := FakeChat.new()
	chat.name = "ChatBox"
	game.add_child(chat)
	WORLD.bind_world(game)
	WORLD.bind_player(player)
	player.controls_locked = true
	check(WORLD.open_act_chat(), "the act chat opens past the controls lock")
	check(chat.opened, "the game's chat box was opened")
	check(player.controls_locked, "the controls lock is restored")
	check(not bool(chat._lock_owned), "the opened chat takes its lock back")
	chat.queue_free()
	var bare := BareGame.new()
	root.add_child(bare)
	WORLD.bind_world(bare)
	check(not WORLD.open_act_chat(), "a world without a chat box opens nothing")
	bare.queue_free()
	game.queue_free()
	player.queue_free()
	WORLD.unbind()


func _check_body_lod() -> void:
	var pony := FakeBody.new()
	root.add_child(pony)
	var near_key: String = HYBRID_NEAR_MESH.key(pony)
	var far_key: String = HYBRID_FAR_MESH._id(pony)
	HYBRID_NEAR_MESH.cache[near_key] = true
	HYBRID_FAR_MESH.cache[far_key] = true
	HYBRID_FAR_MESH.shadow_cache[far_key] = true
	HYBRID_FAR_MESH.eyes_cache[far_key] = true
	WORLD.refresh_body_lod(pony)
	check(not HYBRID_NEAR_MESH.cache.has(near_key), "the near LOD cache entry is dropped")
	check(not HYBRID_FAR_MESH.cache.has(far_key), "the far LOD cache entry is dropped")
	check(not HYBRID_FAR_MESH.shadow_cache.has(far_key), "the shadow cache entry is dropped")
	check(not HYBRID_FAR_MESH.eyes_cache.has(far_key), "the eyes cache entry is dropped")
	check(pony.near_calls == [false, true], "the near mesh is re-armed off then on")
	pony.near_calls.clear()
	pony.near_mesh_enabled = false
	WORLD.refresh_body_lod(pony)
	check(pony.near_calls.is_empty(), "a body with the near mesh disabled is not re-armed")
	pony.queue_free()


func _check_desktop() -> void:
	var node := Node.new()
	root.add_child(node)
	node.add_to_group("desktop_interactions")
	WORLD.bind_world(FakeGame.new())
	check(WORLD.desktop() == node, "the desktop interactions node is found by group")
	WORLD.unbind()
	node.queue_free()


## The one read that needs a live physics space: a mattress probe under a resting body.
func _check_bed_under() -> void:
	var bed := Node3D.new()
	bed.name = "FakeBed"
	bed.set_meta("mattress_top", 0.6)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.2, 4.0)
	shape.shape = box
	body.add_child(shape)
	bed.add_child(body)
	root.add_child(bed)
	bed.global_position = Vector3(0.0, 0.5, 0.0)
	var player := FakePlayer.new()
	root.add_child(player)
	WORLD.bind_world(BareGame.new())
	WORLD.bind_player(player)
	await physics_frame
	await physics_frame
	var found := WORLD.bed_under(Vector3(0.0, 0.6, 0.0))
	check(found == bed, "the probe under a body finds the bed")
	check(WORLD.bed_under(Vector3(40.0, 0.6, 0.0)) == null, "the probe under nothing finds no bed")
	bed.queue_free()
	player.queue_free()
	WORLD.unbind()
