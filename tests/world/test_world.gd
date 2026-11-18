extends SceneTree
## The world facade: the bound scene handles, the camera cache, the bed resolution, the menu and
## headset gates, the player body and mare reads, the LOD rebuild and the act chat.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/world/test_world.gd

const WORLD := preload("res://mods/unfplap/world/service.gd")
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


class FakeGame extends Node:
	var mares: Array = []
	var headset_view := false
	var inventory: Variant = null
	var save_menu: Variant = null
	var find_calls := 0

	func _find_camera(_body: Variant) -> Variant:
		find_calls += 1
		return null


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


class FakeCase extends Control:
	pass


class FakeInventory extends Node:
	var case: Variant = null


class FakeChat extends Node:
	var opened := false
	var _lock_owned := true

	func _open() -> bool:
		opened = true
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

	func set_near_mesh(enabled: bool) -> void:
		near_calls.append(enabled)


class FakeForm extends RefCounted:
	var avatar: Variant = null


func run() -> void:
	_check_unbound()
	_check_binding()
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
	WORLD.unbind()
	check(WORLD.game == null and WORLD.player == null, "unbind clears the bound handles")

	print("WORLD_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


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
	check(is_same(WORLD.mares(), list), "the mare list is the world's own array")
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
