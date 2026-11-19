extends SceneTree
## The scene gate: the live scene rows, the structural rows, the policy/scene merge, the
## start/offer verdicts, the debug status line, the bed search, the player/navigator predicates
## and the buck/push the live strict stop calls. The policy itself is the runtime's callback.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/scene_gate/test_scene_gate.gd

const WORLD := preload("res://mods/unfplap/world/service.gd")
const GATE := preload("res://mods/unfplap/scene_gate/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

const STATE_IDLE := 0
const STATE_ACTIVE := 2

var failures := 0
var checks := 0


class FakePony extends Node3D:
	var sleeping := false
	var motion_paused := false
	var actual_speed := 0.0
	var conversation_target: Variant = null
	var interruption := ""
	var posture := {"requested": "stand", "settled": true}
	var held := false
	var grounded_state := true
	var hoof_hold: Variant = null

	func posture_status() -> Dictionary:
		return posture

	func is_held() -> bool:
		return held

	func grounded() -> bool:
		return grounded_state

	func action_interruption_reason() -> String:
		return interruption


class FakeNav extends Node:
	var reserved_by := ""
	var command_owner := ""
	var _has_target := false


class FakePlayer extends Node3D:
	var controls_locked := false
	var flying := false
	var seat: Variant = null
	var wing_flight: Variant = null
	var swimming: Variant = null
	var _couch_rest: Variant = null
	var knockdown: Variant = null


class FakeInventory extends RefCounted:
	var held: Variant = {}
	var holding_case := ""


class FakeGame extends Node:
	var inventory: Variant = null
	var headset_view := false


class FakeMain extends Node:
	var player: Variant = null
	var game: Variant = null


class FakePose extends RefCounted:
	var ready := true
	var reason := ""
	var missing: Array = []

	func authored_ready(_pose := "") -> bool:
		return ready

	func authored_reason(_pose := "") -> String:
		return reason if not reason.is_empty() else "pose_asset"

	func rig_missing(_pose := "") -> Array:
		return missing

	func rig_reason(_miss: Array) -> String:
		return "pose_rig: missing"


class FakeAffection extends Node:
	var kind := ""
	var bucks := 0

	func buck(_body: Variant) -> bool:
		bucks += 1
		return true


class FakeStool extends RefCounted:
	var need := 0
	var count := 0

	func stool_need() -> int:
		return need

	func stool_count() -> int:
		return count


class FakePolicy extends RefCounted:
	var verdict: Variant = null
	var calls := 0

	func verdict_for(_mode: int, _verdict_in: Variant = null) -> Variant:
		calls += 1
		return verdict


class FakeContext extends RefCounted:
	var values: Dictionary = {}

	func context() -> Dictionary:
		return values


class FakeForm extends Node:
	var form: Dictionary = {}


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _fixture() -> Dictionary:
	var gate: RefCounted = GATE.new()
	var pony := FakePony.new()
	var nav := FakeNav.new()
	nav.name = "Navigator"
	pony.add_child(nav)
	var player := FakePlayer.new()
	var game := FakeGame.new()
	game.inventory = FakeInventory.new()
	var main := FakeMain.new()
	main.player = player
	WORLD.bind_player(main.player)
	main.game = game
	WORLD.bind_world(main.game)
	var bed := Node3D.new()
	bed.name = "GuestBed"
	bed.set_meta("mattress_top", 0.6)
	var bed_body := StaticBody3D.new()
	var bed_shape := CollisionShape3D.new()
	var bed_box := BoxShape3D.new()
	bed_box.size = Vector3(6.0, 0.2, 6.0)
	bed_shape.shape = bed_box
	bed_body.add_child(bed_shape)
	bed.add_child(bed_body)
	root.add_child(bed)
	bed.global_position = Vector3(0.0, -0.1, 0.0)
	var pose := FakePose.new()
	var stool := FakeStool.new()
	var affection := FakeAffection.new()
	affection.name = "Affection"
	pony.add_child(affection)
	root.add_child(pony)
	root.add_child(main)
	main.add_child(player)
	main.add_child(game)
	gate.bind(pony, pose)
	gate.configure(STATE_IDLE, "rarity", {})
	gate.stool_need = Callable(stool, "stool_need")
	gate.stool_count = Callable(stool, "stool_count")
	var policy := FakePolicy.new()
	var context := FakeContext.new()
	gate.policy_verdict = Callable(policy, "verdict_for")
	gate.debug_context = Callable(context, "context")
	await physics_frame
	return {
		"gate": gate, "pony": pony, "nav": nav, "player": player, "game": game,
		"main": main, "bed": bed, "pose": pose, "stool": stool,
		"affection": affection, "policy": policy, "context": context,
	}


func _free(made: Dictionary) -> void:
	var pony: FakePony = made["pony"]
	var main: FakeMain = made["main"]
	var player: FakePlayer = made["player"]
	var game: FakeGame = made["game"]
	var bed: Node3D = made["bed"]
	root.remove_child(pony)
	pony.free()
	main.remove_child(player)
	player.free()
	main.remove_child(game)
	game.free()
	root.remove_child(main)
	main.free()
	root.remove_child(bed)
	bed.free()


func run() -> void:
	await _check_conversation()
	await _check_cuddle()
	await _check_affection()
	await _check_navigator()
	await _check_player()
	await _check_bed()
	await _check_rows()
	await _check_scene_only()
	await _check_profiles()
	await _check_verdicts()
	await _check_buck_or_push()
	await _check_suppress()

	print("SCENE_GATE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("SCENE_GATE_PASS")
	quit(0 if failures == 0 else 1)


func _check_conversation() -> void:
	var made := await _fixture()
	var gate: RefCounted = made["gate"]
	var pony: FakePony = made["pony"]
	var player: FakePlayer = made["player"]
	var main: FakeMain = made["main"]
	check(bool(gate.call("conversation_ok")), "no conversation target is free")
	pony.conversation_target = player
	check(bool(gate.call("conversation_ok")), "talking to Anon is free")
	var other := Node3D.new()
	root.add_child(other)
	pony.conversation_target = other
	check(not bool(gate.call("conversation_ok")), "another pony's conversation blocks")
	pony.conversation_target = player
	main.player = null
	WORLD.bind_player(main.player)
	check(not bool(gate.call("conversation_ok")), "a missing player blocks")
	main.player = player
	WORLD.bind_player(main.player)
	root.remove_child(other)
	other.free()
	_free(made)


func _check_cuddle() -> void:
	var made := await _fixture()
	var gate: RefCounted = made["gate"]
	var pony: FakePony = made["pony"]
	check(not bool(gate.call("cuddle_active")), "no cuddle is inactive")
	pony.set_meta("cuddle_active", true)
	check(bool(gate.call("cuddle_active")), "the cuddle meta is active")
	pony.remove_meta("cuddle_active")
	check(not bool(gate.call("cuddle_active")), "clearing the meta ends it")
	var session := FakeSession.new()
	session.enabled = true
	pony.set_meta("cuddle_session", session)
	check(bool(gate.call("cuddle_active")), "an enabled session is an active cuddle")
	session.enabled = false
	session.blend = 0.5
	check(bool(gate.call("cuddle_active")), "a blending session is an active cuddle")
	session.blend = 0.0
	check(not bool(gate.call("cuddle_active")), "an ended session is inactive")
	gate.configure(STATE_IDLE, "rarity", {})
	_free(made)


class FakeSession extends Node:
	var enabled := false
	var blend := 0.0
	var ended := 0

	func end(_immediate: bool) -> void:
		ended += 1


func _check_affection() -> void:
	var made := await _fixture()
	var gate: RefCounted = made["gate"]
	var affection: FakeAffection = made["affection"]
	check(bool(gate.call("free_of_affection")), "no affection is free")
	affection.kind = "kiss"
	check(not bool(gate.call("free_of_affection")), "an active affection blocks")
	affection.kind = ""
	var hoof := FakeHoof.new()
	hoof.on = true
	(made["pony"] as FakePony).hoof_hold = hoof
	check(not bool(gate.call("free_of_affection")), "an active hoof hold blocks")
	hoof.on = false
	check(bool(gate.call("free_of_affection")), "releasing the hoof frees the gate")
	_free(made)


class FakeHoof extends RefCounted:
	var on := false

	func active() -> bool:
		return on


func _check_navigator() -> void:
	var made := await _fixture()
	var gate: RefCounted = made["gate"]
	var nav: FakeNav = made["nav"]
	nav.command_owner = ""
	check(bool(gate.call("nav_owner_allows", "standing", "")), "an idle navigator is free")
	nav.command_owner = "unfplap:request:rarity"
	check(bool(gate.call("nav_owner_allows", "standing", "")),
		"the request lease is free while idle")
	nav.command_owner = "unfplap:act"
	check(not bool(gate.call("nav_owner_allows", "standing", "")), "another act lease blocks")
	nav.command_owner = "bond:date"
	check(bool(gate.call("nav_owner_allows", "standing", "")), "a player outing is free")
	nav.command_owner = "cuddle:pending"
	check(bool(gate.call("nav_owner_allows", "missionary", "bed_side")),
		"a cuddle lease is valid for a bed-side act")
	nav.command_owner = "weather:rain"
	check(not bool(gate.call("nav_owner_allows", "standing", "")), "a weather lease blocks")
	nav.command_owner = "life:routine"
	nav._has_target = true
	check(not bool(gate.call("nav_owner_allows", "standing", "")),
		"an active routine route blocks")
	nav._has_target = false
	check(bool(gate.call("nav_owner_allows", "standing", "")), "an idle routine is free")
	nav.command_owner = "sleep:bed"
	var pony: FakePony = made["pony"]
	pony.sleeping = true
	check(not bool(gate.call("nav_owner_allows", "missionary", "bed_side")),
		"a sleeping pony blocks a bed-side act")
	pony.sleeping = false
	pony.posture = {"requested": "lie_down", "settled": true}
	check(bool(gate.call("nav_owner_allows", "missionary", "bed_side")),
		"a lying-awake sleep lease allows the bed-side act")
	pony.posture = {"requested": "stand", "settled": true}
	check(not bool(gate.call("nav_owner_allows", "missionary", "bed_side")),
		"a standing sleep lease blocks it")
	_free(made)


func _check_player() -> void:
	var made := await _fixture()
	var gate: RefCounted = made["gate"]
	var player: FakePlayer = made["player"]
	var bed: Node3D = made["bed"]
	var inventory: FakeInventory = (made["game"] as FakeGame).inventory
	check(bool(gate.call("player_ready_for", "standing", "", null)),
		"a free player is ready to stand")
	player.controls_locked = true
	check(not bool(gate.call("player_ready_for", "standing", "", null)),
		"locked controls are not ready")
	player.controls_locked = false
	player.flying = true
	check(not bool(gate.call("player_ready_for", "standing", "", null)),
		"flying is not ready")
	player.flying = false
	inventory.held = {"id": "apple"}
	check(not bool(gate.call("player_ready_for", "standing", "", null)),
		"a held item is not ready")
	inventory.held = {}
	inventory.holding_case = "picnic"
	check(not bool(gate.call("player_ready_for", "standing", "", null)),
		"a held case is not ready")
	inventory.holding_case = ""
	var seat := Node3D.new()
	bed.add_child(seat)
	player.seat = seat
	check(not bool(gate.call("player_ready_for", "standing", "", null)),
		"a standing act needs Anon off a seat")
	check(bool(gate.call("player_ready_for", "missionary", "bed_side", null)),
		"a seated Anon beside the bed is ready")
	player.seat = null
	check(not bool(gate.call("player_ready_for", "missionary", "bed_side", null)),
		"a bed-side act needs Anon seated first")
	player.seat = seat
	var sofa := FakeRest.new()
	sofa.amount = 0.5
	player._couch_rest = sofa
	check(not bool(gate.call("player_ready_for", "missionary", "bed_side", null)),
		"a half-reclined seat is not ready")
	sofa.amount = 1.0
	check(bool(gate.call("player_ready_for", "missionary", "bed_side", null)),
		"a settled seat with Anon beside the bed is ready")
	_free(made)


class FakeRest extends RefCounted:
	var amount := 0.0


func _check_bed() -> void:
	var made := await _fixture()
	var gate: RefCounted = made["gate"]
	var bed: Node3D = made["bed"]
	check(gate.call("resolve_bed", "standing", "", null) == null, "standing has no bed")
	check(gate.call("resolve_bed", "missionary", "bed_side", null) == bed,
		"missionary resolves the bed under her")
	var explicit := Node3D.new()
	explicit.set_meta("mattress_top", 0.6)
	root.add_child(explicit)
	check(gate.call("resolve_bed", "missionary", "bed_side", explicit) == explicit,
		"an explicit bed is used as given")
	root.remove_child(explicit)
	explicit.free()
	check(bool(gate.call("bed_gate", "standing", "", null)), "standing has no bed gate")
	var pony: FakePony = made["pony"]
	pony.posture = {"requested": "lie_down", "settled": true}
	check(bool(gate.call("bed_gate", "missionary", "bed_side", bed)),
		"a lying pony with Anon beside the bed passes")
	pony.posture = {"requested": "lie_down", "settled": false}
	check(not bool(gate.call("bed_gate", "missionary", "bed_side", bed)),
		"a settling lie-down fails the bed gate")
	pony.posture = {"requested": "lie_down", "settled": true}
	var player: FakePlayer = made["player"]
	var elsewhere := Node3D.new()
	root.add_child(elsewhere)
	player.seat = elsewhere
	check(not bool(gate.call("bed_gate", "missionary", "bed_side", bed)),
		"Anon away from the bed fails it")
	root.remove_child(elsewhere)
	elsewhere.free()
	_free(made)


func _check_rows() -> void:
	var made := await _fixture()
	var gate: RefCounted = made["gate"]
	var pony: FakePony = made["pony"]
	var rows: Array = gate.call("rows", "standing", "", null, "start", false)
	var keys: Array[String] = []
	for row: ELIGIBILITY.Row in rows:
		keys.append(row.key)
	for key: String in ["state", "paused", "conversation", "sleeping", "sex_active", "aftercare",
			"cuddle", "affection", "player", "navigator", "navigator_reserved", "nav_owner",
			"nav_pose", "stool"]:
		check(key in keys, "the standing start rows carry %s" % key)
	gate.configure(STATE_ACTIVE, "rarity", {})
	rows = gate.call("rows", "standing", "", null, "start", false)
	var state_ok := true
	for row: ELIGIBILITY.Row in rows:
		if row.key == "state":
			state_ok = row.ok
	check(not state_ok, "a running act fails the state row")
	gate.configure(STATE_IDLE, "rarity", {})
	pony.set_meta("sex_aftercare", true)
	rows = gate.call("rows", "standing", "", null, "start", false)
	var aftercare_ok := true
	for row: ELIGIBILITY.Row in rows:
		if row.key == "aftercare":
			aftercare_ok = row.ok
	check(not aftercare_ok, "aftercare fails its row")
	pony.remove_meta("sex_aftercare")
	var stool: FakeStool = made["stool"]
	stool.need = 2
	stool.count = 1
	rows = gate.call("rows", "standing", "", null, "start", false)
	var stool_ok := true
	for row: ELIGIBILITY.Row in rows:
		if row.key == "stool":
			stool_ok = row.ok
	check(not stool_ok, "too few footstools fail the stool row")
	stool.need = 0
	_free(made)


## The scene-only start: the frozen pose rows, the aftercare removal, the hold exemption and the
## transient/hard split. No policy row is built.
func _check_scene_only() -> void:
	var made := await _fixture()
	var gate: RefCounted = made["gate"]
	var pony: FakePony = made["pony"]
	var nav: FakeNav = made["nav"]
	var bed: Node3D = made["bed"]
	var frozen := GATE.FrozenPose.new(true, true)

	var verdict: Variant = gate.call("scene_only_verdict", "missionary", "already_lying", bed,
		frozen)
	check(not _has_row(verdict.rows, "aftercare"), "the scene-only rows drop aftercare")
	check(not _has_row(verdict.rows, "pose_form"), "the scene-only rows drop pose_form")
	check(not _has_row(verdict.rows, "pose_view"), "the scene-only rows drop pose_view")
	check(not _has_row(verdict.rows, "pose"), "the scene-only rows drop the formation row")
	check(_has_row(verdict.rows, "pose_profile"), "the frozen profile row is still named")
	check(_has_row(verdict.rows, "pose_source"), "the frozen source row is still named")
	check(verdict.hard_ok, "the hard scene rows pass")
	check(verdict.transient.has("bed_gate"), "the unfilled bed gate is transient")
	check(not verdict.ok, "a transient failure keeps the auto-start waiting")

	pony.set_meta("sex_aftercare", true)
	verdict = gate.call("scene_only_verdict", "missionary", "already_lying", bed, frozen)
	check(verdict.hard_ok, "aftercare is no longer a start row")
	pony.remove_meta("sex_aftercare")

	var player: FakePlayer = made["player"]
	var elsewhere := Node3D.new()
	root.add_child(elsewhere)
	player.seat = elsewhere
	verdict = gate.call("scene_only_verdict", "missionary", "already_lying", bed, frozen)
	check(verdict.hard_ok, "a transient player row does not fail the hard set")
	check(verdict.transient.has("player") and verdict.transient.has("bed_gate"),
		"the player and bed gate rows are both transient")
	player.seat = null
	root.remove_child(elsewhere)
	elsewhere.free()

	gate.configure(STATE_ACTIVE, "rarity", {})
	verdict = gate.call("scene_only_verdict", "missionary", "already_lying", bed, frozen)
	check(not verdict.hard_ok, "a running act fails the hard state row")
	gate.configure(STATE_IDLE, "rarity", {})

	var unfrozen := GATE.FrozenPose.new(false, false)
	verdict = gate.call("scene_only_verdict", "missionary", "already_lying", bed, unfrozen)
	check(not verdict.hard_ok, "a failed frozen capability fails the hard set")
	check(not _row_ok(verdict.rows, "pose_profile"), "the frozen profile row reports its value")
	check(not _row_ok(verdict.rows, "pose_source"), "the frozen source row reports its value")

	# A foreign navigator owner and affection hold fail; the negotiation hold exempts both.
	pony.posture = {"requested": "stand", "settled": true}
	pony.interruption = "Affection active"
	(made["affection"] as FakeAffection).kind = "nuzzle"
	nav.command_owner = "unfplap:negotiation:rarity"
	var blocked: Variant = gate.call("scene_only_verdict", "standing", "", null, frozen)
	check(not blocked.hard_ok, "an unaccepted hold fails the hard rows")
	check(not _row_ok(blocked.rows, "affection"), "the affection row names the hold")
	check(not _row_ok(blocked.rows, "nav_owner"), "the navigator owner row names the hold")
	check(not _row_ok(blocked.rows, "nav_pose"), "the standing pose row names the hold")

	gate.hold_compatible = func(_pose: String, _source: String) -> bool: return true
	var held: Variant = gate.call("scene_only_verdict", "standing", "", null, frozen)
	check(held.ok, "the negotiation hold passes the scene-only start")
	check(_row_ok(held.rows, "affection"), "the hold exempts the affection row")
	check(_row_ok(held.rows, "nav_owner"), "the hold is an accepted navigator owner")
	check(_row_ok(held.rows, "nav_pose"), "the hold exempts the standing pose row")
	gate.hold_compatible = Callable()
	nav.command_owner = ""
	pony.interruption = ""
	(made["affection"] as FakeAffection).kind = ""
	_free(made)


## One row's pass value, or false when the key is absent.
func _row_ok(rows: Array, key: String) -> bool:
	for row: ELIGIBILITY.Row in rows:
		if row.key == key:
			return row.ok
	return false


func _has_row(rows: Array, key: String) -> bool:
	for row: ELIGIBILITY.Row in rows:
		if row.key == key:
			return true
	return false


## The pose spec drives the rows: public/offerable, form/view support, the authored source and the
## scene block's stool/bed/stem choices. An internal pose fails the offer.
func _check_profiles() -> void:
	var made := await _fixture()
	var gate: RefCounted = made["gate"]
	var pony: FakePony = made["pony"]
	var main: FakeMain = made["main"]
	var bed: Node3D = made["bed"]
	var standing: Array = gate.call("rows", "standing", "", null, "start", false)
	check(_row_ok(standing, "pose_profile"), "the public standing profile passes")
	check(_row_ok(standing, "pose_asset") and _row_ok(standing, "pose_rig"),
		"the ground pose carries the asset and rig rows")
	check(_row_ok(standing, "pose_form") and _row_ok(standing, "pose_view"),
		"standing supports the default human desktop")
	check(_has_row(standing, "stool"), "the standing scene block carries the stool row")
	check(not _has_row(standing, "bed"), "the standing scene block has no bed row")
	var missionary: Array = gate.call("rows", "missionary", "bed_side", bed, "start", false)
	check(_row_ok(missionary, "pose_profile"), "the public missionary profile passes")
	check(_row_ok(missionary, "pose_source"), "the bed-side source is authored")
	check(not _has_row(missionary, "stool"), "the bed scene block has no stool row")
	var cradle: Array = gate.call("rows", "missionary", "cradle", bed, "start", false)
	check(_row_ok(cradle, "pose_source"), "the cradle source is authored")
	var unnamed: Array = gate.call("rows", "missionary", "", null, "start", false)
	check(not _row_ok(unnamed, "pose_source"), "an unauthored source fails")
	var internal_start: Array = gate.call("rows", "standing_oral", "", null, "start", false)
	check(not _row_ok(internal_start, "pose_profile"), "an internal pose fails a start")
	var internal_offer: Array = gate.call("rows", "standing_oral", "", null, "offer", true)
	check(not _row_ok(internal_offer, "pose"), "an internal pose fails an offer")
	check(not _row_ok(internal_offer, "pose_profile"),
		"an internal pose fails the offer profile too")
	var facesit_start: Array = gate.call("rows", "bed_facesit", "bed_side", bed, "start", false)
	check(not _row_ok(facesit_start, "pose_profile"), "the internal face-sit fails a start")
	var facesit_offer: Array = gate.call("rows", "bed_facesit", "", null, "offer", true)
	check(not _row_ok(facesit_offer, "pose"), "the internal face-sit fails an offer")
	check(not _row_ok(facesit_offer, "pose_profile"),
		"the internal face-sit fails the offer profile too")
	var unknown: Array = gate.call("rows", "no_such_pose", "", null, "offer", true)
	check(not _row_ok(unknown, "pose_profile") and not _row_ok(unknown, "pose"),
		"an unknown pose fails closed")

	var driver := FakeForm.new()
	driver.form = {"kind": "pony"}
	driver.add_to_group("player_pony_form")
	root.add_child(driver)
	var pony_form: Array = gate.call("rows", "missionary", "bed_side", bed, "start", false)
	check(not _row_ok(pony_form, "pose_form"), "missionary rejects AnonPony")
	var pony_standing: Array = gate.call("rows", "standing", "", null, "start", false)
	check(_row_ok(pony_standing, "pose_form"), "standing supports AnonPony")
	root.remove_child(driver)
	driver.free()

	(made["game"] as FakeGame).headset_view = true
	var vr_missionary: Array = gate.call("rows", "missionary", "bed_side", bed, "start", false)
	check(not _row_ok(vr_missionary, "pose_view"), "missionary rejects the headset view")
	var vr_standing: Array = gate.call("rows", "standing", "", null, "start", false)
	check(_row_ok(vr_standing, "pose_view"), "standing supports the headset view")
	(made["game"] as FakeGame).headset_view = false

	check(gate.call("resolve_bed", "standing_oral", "cradle", null) == null,
		"a non-bed pose resolves no bed")
	check(bool(gate.call("player_ready_for", "standing_oral", "", null)) == false,
		"a non-public pose is never start-ready")
	check(bool(gate.call("player_ready_for", "missionary", "standing", null)) == false,
		"a non-authored source is never start-ready")
	check(bool(gate.call("player_ready_for", "standing", "", null)),
		"a public standing start stays ready")
	_free(made)


func _check_verdicts() -> void:
	var made := await _fixture()
	var gate: RefCounted = made["gate"]
	var pony: FakePony = made["pony"]
	var policy: FakePolicy = made["policy"]
	var context: FakeContext = made["context"]
	var verdict := ELIGIBILITY.Verdict.new()
	verdict.show = true
	verdict.offer = true
	var row := ELIGIBILITY.Row.new()
	row.key = "relation"
	row.ok = true
	row.reason = "relation"
	verdict.rows.append(row)
	policy.verdict = verdict
	var start: Dictionary = gate.call("start_verdict", "standing", "", null)
	check(bool(start.get("show", false)), "the start verdict follows the policy")
	check(policy.calls == 1, "the policy callback runs once")
	# The idle hint supplies its cached policy; the gate must skip the callback and still run
	# every live scene row.
	var reused := ELIGIBILITY.Verdict.new()
	reused.show = true
	var calls_before := policy.calls
	var reused_start: Dictionary = gate.call("start_verdict", "standing", "", null, reused)
	check(policy.calls == calls_before, "a supplied verdict skips the policy callback")
	check(bool(reused_start.get("show", false)), "a supplied verdict still shows through the gate")
	pony.set_meta("sex_aftercare", true)
	var reused_blocked: Dictionary = gate.call("start_verdict", "standing", "", null, reused)
	check(not bool(reused_blocked.get("show", false)),
		"a supplied verdict still runs the live scene rows")
	pony.remove_meta("sex_aftercare")
	var keys: Array[String] = []
	for entry: ELIGIBILITY.Row in start.get("rows", []):
		keys.append(entry.key)
	check("invalid_pony" in keys and "no_main" in keys and "no_player" in keys \
		and "no_game" in keys, "the structural rows are appended")
	check("relation" in keys, "the policy rows are appended")
	check("state" in keys, "the scene rows are appended")
	pony.set_meta("sex_aftercare", true)
	var blocked: Dictionary = gate.call("start_verdict", "standing", "", null)
	check(not bool(blocked.get("show", false)), "a failed scene row hides the start")
	pony.remove_meta("sex_aftercare")
	var offer: Dictionary = gate.call("offer_verdict", "standing", "", null, true)
	check(bool(offer.get("ok", false)), "the offer verdict follows the policy")
	var reasons: PackedStringArray = gate.call("report_reasons", blocked.get("rows", []))
	check(reasons.has("aftercare"), "the failed rows are reported")
	context.values = {"id": "rarity", "display": "Rarity", "state": 0}
	var line: String = gate.call("debug_line", "standing", "", null)
	check(line.contains("id=rarity"), "the debug line carries the pony id")
	check(line.contains("can_start="), "the debug line carries the start verdict")
	_free(made)


class FakeKnockdown extends RefCounted:
	var starts := 0

	func start(_body: Variant, _impulse: Vector3) -> void:
		starts += 1


## The live strict stop calls this directly: the game's Affection owns the buck, and an Anon body
## without one falls back to its knockdown.
func _check_buck_or_push() -> void:
	var made := await _fixture()
	var gate: RefCounted = made["gate"]
	var pony: FakePony = made["pony"]
	var player: FakePlayer = made["player"]
	pony.global_position = Vector3(0.0, 0.0, 0.0)
	player.global_position = Vector3(0.0, 0.0, 1.5)
	check(bool(gate.call("buck_or_push")), "the Affection buck is the live buck/push")
	check((made["affection"] as FakeAffection).bucks == 1, "the game's own buck runs once")
	var affection: Node = made["affection"]
	pony.remove_child(affection)
	affection.free()
	var knockdown := FakeKnockdown.new()
	player.knockdown = knockdown
	check(bool(gate.call("buck_or_push")), "an Anon body falls back to its knockdown")
	check(knockdown.starts == 1, "the knockdown starts once")
	_free(made)


func _check_suppress() -> void:
	var made := await _fixture()
	var gate: RefCounted = made["gate"]
	var pony: FakePony = made["pony"]
	var session := FakeSession.new()
	session.name = "CuddleSession"
	session.enabled = true
	pony.add_child(session)
	pony.set_meta("cuddle_session", session)
	pony.set_meta("cuddle_active", true)
	pony.set_meta("couch_cuddle", true)
	gate.configure(STATE_ACTIVE, "rarity", {})
	gate.call("suppress_auto_cuddle")
	check(not pony.has_meta("couch_cuddle"), "the lying cuddle marker is cleared")
	check(not pony.has_meta("cuddle_active"), "the cuddle active marker is cleared")
	check(session.ended == 1, "the live cuddle session ends")
	gate.configure(STATE_IDLE, "rarity", {})
	pony.set_meta("cuddle_active", true)
	gate.call("suppress_auto_cuddle")
	check(pony.has_meta("cuddle_active"), "an idle runtime leaves the stock cuddle alone")
	_free(made)
