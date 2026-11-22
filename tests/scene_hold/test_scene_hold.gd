extends "res://mods/unfplap/tests/support/suite.gd"
## The act's scene hold: navigator claim/keep/release, the face-turn rate, the conversation
## attention, the player hold, the carry release and the cuddle end.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/scene_hold/test_scene_hold.gd

const INTERACTOR := preload("res://player/interactor.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const HOLD := preload("res://mods/unfplap/scene_hold/service.gd")

const STATE_IDLE := 0
const STATE_ACTIVE := 2
const STATE_AFTERGLOW := 4



class FakeNav extends Node:
	var command_owner := ""
	var wander_enabled := true
	var reserved_by := ""
	var _has_target := false
	var stays := 0

	func stay() -> void:
		stays += 1
		_has_target = false


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


class FakeDesktopActions extends Node:
	var released := 0

	func pony_released() -> void:
		released += 1


class FakeMain extends Node:
	var player: FakeBody = null
	var game: FakeGame = null


func _fixture(pose_family := "standing", state := STATE_ACTIVE) -> Dictionary:
	var pony := FakePony.new()
	var nav := FakeNav.new()
	nav.name = "Navigator"
	pony.add_child(nav)
	var session := FakeSession.new()
	session.name = "CuddleSession"
	pony.add_child(session)
	var body := FakeBody.new()
	var reach := INTERACTOR.new()
	reach.name = "Interactor"
	reach.desktop_actions = FakeDesktopActions.new()
	body.add_child(reach)
	var game := FakeGame.new()
	game.kisser = FakeKisser.new()
	var main := FakeMain.new()
	main.player = body
	WORLD.bind_player(main.player)
	main.game = game
	WORLD.bind_world(main.game)
	var hold: RefCounted = HOLD.new()
	var host := HOLD.Host.new()
	host.pony = Callable(_value, "make").bind(pony)
	host.state = Callable(_value, "make").bind(state)
	host.pose_family = Callable(_value, "make").bind(pose_family)
	hold.bind(host)
	return {"hold": hold, "pony": pony, "nav": nav, "session": session, "body": body,
		"game": game, "reach": reach, "main": main, "host": host}


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
	_check_negotiation()
	_check_face_turn()
	_check_attention()
	_check_player()
	_check_carry()
	_check_cuddle()
	if failures == 0:
		print("SCENE_HOLD_PASS")
	finish()


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


## The negotiation lease in IDLE: claim, keep, keep-target, the affection hold, adoption and the
## idempotent release. Also the transfer from a request lease and a second ledger adopting it.
func _check_negotiation() -> void:
	var made := _fixture("standing", STATE_IDLE)
	var hold: RefCounted = made["hold"]
	var pony: FakePony = made["pony"]
	var nav: FakeNav = made["nav"]
	var main: FakeMain = made["main"]
	nav.wander_enabled = true
	nav._has_target = true
	check(not hold.claim_negotiation("rarity"), "an active route is Occupied")
	nav._has_target = false
	check(hold.claim_negotiation("rarity"), "an idle routine owner is free for negotiation")
	check(hold.token == HOLD.TOKEN_NEGOTIATION + "rarity",
		"the negotiation token names its owner")
	check(nav.command_owner == hold.token, "the navigator records the negotiation owner")
	check(hold.negotiation and hold.holds_negotiation(), "the ledger is in negotiation mode")
	check(not nav.wander_enabled, "the negotiation holds wander off")

	nav.command_owner = "weather:rain"
	nav._has_target = true
	hold.keep_nav()
	check(nav.command_owner == hold.token, "the keep re-asserts the negotiation owner")
	check(not nav._has_target, "the negotiation keep clears another route's target")

	pony.conversation_target = null
	check(hold.keep_target(), "a cleared target is kept on Anon")
	check(pony.conversation_target == main.player, "the target is Anon's body")
	var rig := Node3D.new()
	main.player.add_child(rig)
	pony.conversation_target = rig
	check(hold.keep_target(), "Anon's rig is still Anon")
	check(pony.conversation_target == main.player, "the target is re-asserted to Anon's body")
	main.player.remove_child(rig)
	rig.free()
	var other := Node3D.new()
	root.add_child(other)
	pony.conversation_target = other
	check(not hold.keep_target(), "another live target is an attention reassignment")
	check(pony.conversation_target == other, "the other target is not overwritten")
	root.remove_child(other)
	other.free()
	pony.conversation_target = main.player

	check(hold.hold_affection(), "the negotiation takes the physical affection hold")
	check(pony.has_meta("affection_active"), "the affection meta is set")
	check(hold.accepts_hold("standing", ""), "the scene gate accepts the live hold")

	check(hold.adopt_hold(), "the act adopts the negotiation hold")
	check(nav.command_owner == hold.token, "adoption keeps the same navigator owner")
	check(hold.accepts_hold("missionary", "bed_side"),
		"the adopted start is still scene-gate compatible")
	check(not hold.negotiation, "the ledger leaves negotiation mode at adoption")

	hold.release_negotiation()
	check(nav.command_owner == "", "the release gives the navigator back")
	check(nav.wander_enabled, "the release restores the saved wander flag")
	check(not pony.has_meta("affection_active"), "the release clears the affection hold")
	check(hold.nav == null and hold.token.is_empty(), "the release clears the handle and token")
	hold.release_negotiation()
	check(not hold.accepts_hold("standing", ""), "a second release is idempotent")
	_free(made)

	# A cuddle session owns the navigator. The negotiation takes the attention and affection
	# hold only, leaves the session's owner and releases without touching it.
	var cuddled := _fixture("standing", STATE_IDLE)
	var cuddle_hold: RefCounted = cuddled["hold"]
	var cuddle_nav: FakeNav = cuddled["nav"]
	var cuddle_pony: FakePony = cuddled["pony"]
	cuddle_nav.command_owner = "cuddle:1234"
	check(cuddle_hold.claim_attention(), "the cuddle hold claims attention without a lease")
	check(cuddle_nav.command_owner == "cuddle:1234",
		"the attention claim leaves the cuddle owner alone")
	check(cuddle_hold.token.is_empty() and cuddle_hold.nav == null,
		"the attention claim has no navigator lease")
	check(not cuddle_hold.accepts_hold("missionary", "bed_side"),
		"the attention claim alone is not a complete scene-gate hold")
	check(cuddle_hold.hold_affection(), "the cuddle hold takes the affection meta")
	check(cuddle_hold.accepts_hold("missionary", "bed_side"),
		"the attention and affection hold is scene-gate compatible")
	cuddle_hold.release_negotiation()
	check(cuddle_nav.command_owner == "cuddle:1234",
		"the attention release leaves the cuddle owner alone")
	check(not cuddle_pony.has_meta("affection_active"),
		"the attention release clears the affection meta")
	_free(cuddled)

	# The proactive request hands its lease over; a second ledger can adopt the same owner.
	var handed := _fixture("standing", STATE_IDLE)
	var request_hold: RefCounted = handed["hold"]
	var request_nav: FakeNav = handed["nav"]
	request_nav.command_owner = "unfplap:request:rarity"
	request_nav.wander_enabled = false
	check(request_hold.transfer_nav("unfplap:request:rarity", true),
		"the request lease transfers to the negotiation")
	check(request_hold.token == "unfplap:request:rarity" and request_hold.negotiation,
		"the transfer keeps the request token")
	check(request_hold.hold_affection(), "the transferred hold takes the affection meta")
	check(request_hold.accepts_hold("standing", ""), "the transferred hold is gate-compatible")
	var act := HOLD.new()
	act.bind(handed["host"])
	check(act.adopt_nav(request_hold.token, true), "a second ledger adopts the live owner")
	check(request_nav.command_owner == request_hold.token,
		"adoption does not change the navigator")
	check(not act.accepts_hold("standing", ""),
		"a ledger that does not own the affection hold is not complete")
	act.release_nav()
	check(request_nav.command_owner == "", "the adopted ledger releases the owner")
	check(request_nav.wander_enabled, "the release restores the handed-over wander flag")
	request_hold.release_affection()
	_free(handed)


func _check_face_turn() -> void:
	var made := _fixture()
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
	var idle := _fixture("bed")
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
	var made := _fixture("standing", STATE_ACTIVE)
	var hold: RefCounted = made["hold"]
	var pony: FakePony = made["pony"]
	hold.keep_attention()
	check(pony.conversation_target == null, "an act clears the conversation target")
	pony.conversation_target = "someone"
	var idle := _fixture("standing", STATE_IDLE)
	(idle["hold"] as RefCounted).keep_attention()
	check((idle["pony"] as FakePony).conversation_target == "someone",
		"an idle pony keeps her conversation target")
	var after := _fixture("standing", STATE_AFTERGLOW)
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
	var reach: Node = made["reach"]
	var actions: FakeDesktopActions = reach.desktop_actions
	check(not hold.release_carry(), "an empty carry is not ours")
	reach.set("held", pony)
	reach.set("cradled", true)
	check(hold.release_carry(), "the act releases its own cradled carry")
	check(reach.get("held") == null and not bool(reach.get("cradled")), "the carry flags clear")
	check(actions.released == 1, "the desktop actions hear the release")
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
