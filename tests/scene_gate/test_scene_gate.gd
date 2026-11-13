extends SceneTree
## The scene gate: the live scene rows, the structural rows, the policy/scene merge, the
## start/offer verdicts, the debug status line, the bed search, the player/navigator predicates
## and the refusal executor. The policy itself is the runtime's callback.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/scene_gate/test_scene_gate.gd

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


class FakeBonds extends Node:
	var unwanted := 0

	func unwanted_contact(_id: String, _kind: String) -> float:
		unwanted += 1
		return 40.0


class FakeRelation extends Node:
	var bonds: Variant = null


class FakeMemory extends RefCounted:
	var events: Array = []

	func commit(impression: Variant) -> void:
		events.append(impression)


class FakeMain extends Node:
	var player: Variant = null
	var game: Variant = null
	var memory: Variant = null
	var bed: Variant = null
	var occupied := false
	var beside := true
	var carry: Variant = null

	func player_body() -> Node3D:
		return player as Node3D

	func camera() -> Camera3D:
		return null

	func bed_under(_at: Vector3, _exclude: RID) -> Node3D:
		return bed as Node3D

	func bed_occupied(_bed_node: Node3D, _pony: Node3D) -> bool:
		return occupied

	func player_beside_bed(_bed_node: Node3D) -> bool:
		return beside

	func interactor() -> Node:
		return carry

	func real_bed(bed_node: Variant) -> Variant:
		return bed_node

	func bed_for_cradle(_pony: Node3D) -> Node3D:
		return bed as Node3D


class FakePose extends RefCounted:
	var ready := true
	var reason := ""
	var missing: Array = []

	func authored_ready() -> bool:
		return ready

	func authored_reason() -> String:
		return reason if not reason.is_empty() else "pose_asset"

	func rig_missing() -> Array:
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


class FakeFace extends RefCounted:
	var moods: Array[String] = []

	func on_face(bucked: bool) -> void:
		moods.append("angry" if bucked else "annoyed")


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
	main.game = game
	main.memory = FakeMemory.new()
	var bed := Node3D.new()
	bed.name = "GuestBed"
	root.add_child(bed)
	main.bed = bed
	var pose := FakePose.new()
	var stool := FakeStool.new()
	var face := FakeFace.new()
	var affection := FakeAffection.new()
	affection.name = "Affection"
	pony.add_child(affection)
	root.add_child(pony)
	root.add_child(main)
	main.add_child(player)
	main.add_child(game)
	gate.bind(pony, main, pose)
	gate.configure(STATE_IDLE, "rarity", {})
	gate.stool_need = Callable(stool, "stool_need")
	gate.stool_count = Callable(stool, "stool_count")
	gate.on_refusal_face = Callable(face, "on_face")
	var policy := FakePolicy.new()
	var context := FakeContext.new()
	gate.policy_verdict = Callable(policy, "verdict_for")
	gate.debug_context = Callable(context, "context")
	return {
		"gate": gate, "pony": pony, "nav": nav, "player": player, "game": game,
		"main": main, "bed": bed, "pose": pose, "stool": stool, "face": face,
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
	_check_conversation()
	_check_cuddle()
	_check_affection()
	_check_navigator()
	_check_player()
	_check_bed()
	_check_rows()
	_check_verdicts()
	_check_refusal()
	_check_suppress()

	print("SCENE_GATE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("SCENE_GATE_PASS")
	quit(0 if failures == 0 else 1)


func _check_conversation() -> void:
	var made := _fixture()
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
	check(not bool(gate.call("conversation_ok")), "a missing player blocks")
	main.player = player
	root.remove_child(other)
	other.free()
	_free(made)


func _check_cuddle() -> void:
	var made := _fixture()
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
	check(bool(gate.call("cuddle_start_override", CATALOG.MISSIONARY, "bed_side")),
		"a bed-side missionary act overrides the cuddle gate")
	check(bool(gate.call("cuddle_start_override", CATALOG.STANDING, "")),
		"an act always starts through a cuddle")
	gate.configure(STATE_IDLE, "rarity", {})
	check(bool(gate.call("cuddle_start_override", CATALOG.STANDING, "")),
		"an empty snapshot still starts through a cuddle")
	_free(made)


class FakeSession extends Node:
	var enabled := false
	var blend := 0.0
	var ended := 0

	func end(_immediate: bool) -> void:
		ended += 1


func _check_affection() -> void:
	var made := _fixture()
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
	var made := _fixture()
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
	var made := _fixture()
	var gate: RefCounted = made["gate"]
	var player: FakePlayer = made["player"]
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
	var made := _fixture()
	var gate: RefCounted = made["gate"]
	var bed: Node3D = made["bed"]
	check(gate.call("find_bed_under") == bed, "the bed under the pony resolves")
	check(gate.call("resolve_bed", "standing", "", null) == null, "standing has no bed")
	check(gate.call("resolve_bed", "missionary", "bed_side", null) == bed,
		"missionary resolves the bed under her")
	var explicit := Node3D.new()
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
	(made["main"] as FakeMain).beside = false
	check(not bool(gate.call("bed_gate", "missionary", "bed_side", bed)),
		"Anon away from the bed fails it")
	_free(made)


func _check_rows() -> void:
	var made := _fixture()
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
	check(rows.size() == keys.size(), "every row is typed")
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
	var offer_rows: Array = gate.call("rows", "standing", "", null, "offer", true)
	for row: ELIGIBILITY.Row in offer_rows:
		check(row.key != "player", "the offer rows skip the player row")
	_free(made)


func _check_verdicts() -> void:
	var made := _fixture()
	var gate: RefCounted = made["gate"]
	var pony: FakePony = made["pony"]
	var policy: FakePolicy = made["policy"]
	var context: FakeContext = made["context"]
	var verdict := ELIGIBILITY.Verdict.new()
	verdict.show = true
	verdict.attempt = true
	verdict.offer = true
	verdict.buck_refuse = true
	verdict.history_refuse = true
	var row := ELIGIBILITY.Row.new()
	row.key = "relation"
	row.ok = true
	row.reason = "relation"
	verdict.rows.append(row)
	policy.verdict = verdict
	var start: Dictionary = gate.call("start_verdict", "standing", "", null)
	check(bool(start.get("show", false)), "the start verdict follows the policy")
	check(bool(start.get("attempt", false)), "the start verdict follows the policy")
	check(bool(start.get("buck_refuse", false)), "the start verdict follows the policy")
	check(bool(start.get("history_refuse", false)), "the start verdict follows the policy")
	check(policy.calls == 1, "the policy callback runs once")
	# The idle hint supplies its cached policy; the gate must skip the callback and still run
	# every live scene row.
	var reused := ELIGIBILITY.Verdict.new()
	reused.show = true
	reused.attempt = true
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
	check(not bool(blocked.get("attempt", false)), "a failed scene row blocks the attempt")
	check(not bool(blocked.get("history_refuse", false)), "a failed scene row hides the history refusal")
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


func _check_refusal() -> void:
	var made := _fixture()
	var gate: RefCounted = made["gate"]
	var pony: FakePony = made["pony"]
	var player: FakePlayer = made["player"]
	var main: FakeMain = made["main"]
	var view := Node3D.new()
	root.add_child(view)
	view.global_position = Vector3(0.0, 0.0, 0.0)
	player.global_position = Vector3(0.0, 0.0, 1.5)
	pony.global_position = Vector3(0.0, 0.0, 0.0)
	var verdict := ELIGIBILITY.Verdict.new()
	verdict.buck_refuse = true
	var gate_dict := {"policy": verdict}
	check(bool(gate.call("refuse_available", "standing", "", null, gate_dict)),
		"a willing-but-unwelcome pony can refuse")
	gate.call("refuse", "standing", "", null, gate_dict)
	var face: FakeFace = made["face"]
	check(face.moods == ["angry"], "a standing refusal bucks and holds the angry face")
	check((made["affection"] as FakeAffection).bucks == 1, "the refusal uses the game's buck")
	check((main.memory as FakeMemory).events.size() == 1, "the refusal writes one impression")
	var impression: Variant = (main.memory as FakeMemory).events[0]
	check(str(impression.mood) == "angry", "the buck sets the angry impression")
	check(str(impression.id) == "rarity", "the impression uses the mare id")
	var rel := FakeRelation.new()
	var bonds := FakeBonds.new()
	rel.bonds = bonds
	pony.set_meta("relationship_runtime", rel)
	gate.call("note_refusal", false)
	check(bonds.unwanted == 1, "a turn-away refusal costs a little trust")
	check(face.moods[-1] == "annoyed", "a turn-away holds the annoyed face")
	(main.memory as FakeMemory).events.clear()
	main.bed = null
	verdict.buck_refuse = false
	check(not bool(gate.call("refuse_available", "standing", "", null, gate_dict)),
		"a willing gate cannot refuse")
	check(bool(gate.call("refusal_ready", 10.0)), "a fresh refusal is ready")
	gate.call("mark_refusal", 10.0)
	check(not bool(gate.call("refusal_ready", 11.0)), "the refusal rate limit holds")
	check(bool(gate.call("refusal_ready", 15.0)), "the refusal rate limit clears")
	_free(made)
	root.remove_child(view)
	view.free()


func _check_suppress() -> void:
	var made := _fixture()
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
