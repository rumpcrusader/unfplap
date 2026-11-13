extends SceneTree
## The act's scene hold: navigator claim/keep/release, the face-turn rate, the conversation
## attention, the player hold, the carry release and the cuddle end.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/scene_hold/test_scene_hold.gd

const HOLD := preload("res://mods/unfplap/scene_hold/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

const STATE_IDLE := 0
const STATE_ACTIVE := 2
const STATE_AFTERGLOW := 4

var failures := 0
var checks := 0


class FakeNav extends Node:
	var command_owner := ""
	var wander_enabled := true
	var reserved_by := ""
	var stays := 0

	func stay() -> void:
		stays += 1


class FakeSession extends Node:
	var enabled := false
	var blend := 0.0
	var ends: Array[bool] = []

	func end(immediate: bool) -> void:
		ends.append(immediate)


class FakePony extends Node3D:
	var face_turn_rate := 0.6
	var conversation_target: Variant = "someone"
	var interaction_ends := 0

	func set_conversation_target(target: Variant, _keep := false) -> void:
		conversation_target = target

	func end_interaction() -> void:
		interaction_ends += 1


class FakeBody extends Node3D:
	var seat: Variant = null
	var _q_held := false


class FakeKisser extends Node:
	var processing := true

	func _init() -> void:
		set_physics_process(true)

	func _physics_process(_delta: float) -> void:
		pass


class FakeGame extends Node:
	var kisser: Node = null


class FakeReach extends Node:
	var held: Variant = null
	var cradled := false
	var _drop_upright := false
	var _laying := -1.0
	var _sleepy_kiss := false
	var _lean := 1.0
	var _lay: Dictionary = {"a": 1}
	var desktop_actions: Variant = null
	var released := 0

	func _init() -> void:
		desktop_actions = self

	func pony_released() -> void:
		released += 1


class FakeMain extends Node:
	var player: FakeBody = null
	var game: FakeGame = null
	var reach: FakeReach = null

	func interactor() -> Node:
		return reach


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _fixture(pose := CATALOG.STANDING, state := STATE_ACTIVE) -> Dictionary:
	var pony := FakePony.new()
	var nav := FakeNav.new()
	nav.name = "Navigator"
	pony.add_child(nav)
	var session := FakeSession.new()
	session.name = "CuddleSession"
	pony.add_child(session)
	var body := FakeBody.new()
	var game := FakeGame.new()
	game.kisser = FakeKisser.new()
	var reach := FakeReach.new()
	var main := FakeMain.new()
	main.player = body
	main.game = game
	main.reach = reach
	var hold: RefCounted = HOLD.new()
	hold.bind({
		"pony": Callable(_value, "make").bind(pony),
		"main": Callable(_value, "make").bind(main),
		"state": Callable(_value, "make").bind(state),
		"pose_id": Callable(_value, "make").bind(pose),
	})
	return {"hold": hold, "pony": pony, "nav": nav, "session": session, "body": body,
		"game": game, "reach": reach, "main": main}


class _value extends RefCounted:
	static func make(value: Variant) -> Variant:
		return value


func _free(made: Dictionary) -> void:
	(made["pony"] as Node).free()
	(made["game"] as Node).free()
	(made["reach"] as Node).free()
	(made["main"] as Node).free()


func run() -> void:
	_check_nav()
	_check_face_turn()
	_check_attention()
	_check_player()
	_check_carry()
	_check_cuddle()
	print("SCENE_HOLD_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("SCENE_HOLD_PASS")
	quit(0 if failures == 0 else 1)


func _check_nav() -> void:
	var made := _fixture()
	var hold: RefCounted = made["hold"]
	var nav: FakeNav = made["nav"]
	nav.wander_enabled = false
	check(hold.claim_nav("rarity"), "the claim takes an unreserved navigator")
	check(hold.token == "unfplap:rarity", "the token names the act owner")
	check(nav.command_owner == "unfplap:rarity", "the navigator records the owner")
	check(not nav.wander_enabled, "the claim holds wander off")
	check(hold.nav_old_wander == false, "the claim keeps the wander flag it found")
	nav.command_owner = "someone_else"
	hold.keep_nav()
	check(nav.command_owner == "unfplap:rarity", "the keep re-asserts the owner")
	hold.release_nav()
	check(nav.command_owner == "", "the release gives the owner back")
	check(not nav.wander_enabled, "the release restores the saved wander flag")
	check(hold.nav == null, "the release clears the handle")
	nav.reserved_by = "another"
	check(not hold.claim_nav("rarity"), "a reserved navigator is refused")
	nav.reserved_by = ""
	check(hold.claim_nav("rarity"), "the freed reservation is ignored")
	hold.release_nav()
	(made["pony"] as Node).remove_child(nav)
	nav.free()
	check(not hold.claim_nav("rarity"), "a missing navigator is refused")
	_free(made)


func _check_face_turn() -> void:
	var made := _fixture(CATALOG.STANDING)
	var hold: RefCounted = made["hold"]
	var pony: FakePony = made["pony"]
	pony.face_turn_rate = 0.45
	hold.pause_face_turn()
	check(is_zero_approx(pony.face_turn_rate), "standing pauses the face-turn rate")
	check(hold.face_turn_rate_owned, "the pause records ownership")
	check(is_equal_approx(hold.face_turn_rate_saved, 0.45), "the pause saves the rate")
	hold.restore_face_turn()
	check(is_equal_approx(pony.face_turn_rate, 0.45), "the restore puts the rate back")
	check(not hold.face_turn_rate_owned, "the restore clears ownership")
	var idle := _fixture(CATALOG.MISSIONARY)
	var idle_hold: RefCounted = idle["hold"]
	var idle_pony: FakePony = idle["pony"]
	idle_hold.pause_face_turn()
	check(is_equal_approx(idle_pony.face_turn_rate, 0.6), "a non-standing pose leaves the rate")
	idle_hold.pause_face_turn(true)
	check(is_zero_approx(idle_pony.face_turn_rate), "a forced pause works in any pose")
	idle_hold.restore_face_turn()
	check(is_equal_approx(idle_pony.face_turn_rate, 0.6), "the forced pause restores too")
	_free(made)
	_free(idle)


func _check_attention() -> void:
	var made := _fixture(CATALOG.STANDING, STATE_ACTIVE)
	var hold: RefCounted = made["hold"]
	var pony: FakePony = made["pony"]
	hold.keep_attention()
	check(pony.conversation_target == null, "an act clears the conversation target")
	pony.conversation_target = "someone"
	var idle := _fixture(CATALOG.STANDING, STATE_IDLE)
	(idle["hold"] as RefCounted).keep_attention()
	check((idle["pony"] as FakePony).conversation_target == "someone",
		"an idle pony keeps her conversation target")
	var after := _fixture(CATALOG.STANDING, STATE_AFTERGLOW)
	(after["hold"] as RefCounted).keep_attention()
	check((after["pony"] as FakePony).conversation_target == "someone",
		"afterglow keeps normal conversation attention")
	_free(made)
	_free(idle)
	_free(after)


func _check_player() -> void:
	var made := _fixture()
	var hold: RefCounted = made["hold"]
	var body: FakeBody = made["body"]
	var kisser: FakeKisser = made["game"].kisser
	body.seat = "chair"
	hold.lock_player()
	check(body.has_meta("kiss_hold"), "the lock sets the kiss hold")
	check(bool(body.get("_q_held")), "a seated player holds Q")
	check(not kisser.is_physics_processing(), "the kisser physics pauses")
	check(hold.locked_player, "the lock records ownership")
	hold.unlock_player()
	check(not body.has_meta("kiss_hold"), "the unlock removes the hold it set")
	check(kisser.is_physics_processing(), "the kisser physics resumes")
	check(not hold.locked_player, "the unlock clears ownership")
	# A hold the act did not set is left in place.
	body.set_meta("kiss_hold", true)
	hold.lock_player()
	hold.unlock_player()
	check(body.has_meta("kiss_hold"), "a pre-existing kiss hold survives the act")
	body.remove_meta("kiss_hold")
	_free(made)


func _check_carry() -> void:
	var made := _fixture()
	var hold: RefCounted = made["hold"]
	var pony: FakePony = made["pony"]
	var reach: FakeReach = made["reach"]
	check(not hold.release_carry(), "an empty carry is not ours")
	reach.held = pony
	reach.cradled = true
	check(hold.release_carry(), "the act releases its own cradled carry")
	check(reach.held == null and not reach.cradled, "the carry flags clear")
	check(reach.released == 1, "the desktop actions hear the release")
	check(pony.interaction_ends == 1, "her interaction ends")
	check((reach.get("_lay") as Dictionary).is_empty(), "the saved lay pose clears")
	_free(made)


func _check_cuddle() -> void:
	var made := _fixture()
	var hold: RefCounted = made["hold"]
	var pony: FakePony = made["pony"]
	var session: FakeSession = made["session"]
	session.enabled = false
	hold.end_cuddle()
	check(session.ends.is_empty(), "an inactive cuddle is left alone")
	session.blend = 0.5
	hold.end_cuddle()
	check(session.ends == [true], "a live cuddle ends immediately")
	pony.set_meta("cuddle_active", true)
	hold.end_cuddle()
	check(not pony.has_meta("cuddle_active"), "the cuddle meta clears")
	_free(made)
