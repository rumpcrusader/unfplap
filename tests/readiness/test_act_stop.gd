extends SceneTree
## Runtime stop path: neutral and strict stops end the act, commit a severe summary, and only
## strict requests space and bucks. The stop mood reaches the summary and its impression, and the
## stop face waits for an in-tree runtime. No live world is needed.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/readiness/test_act_stop.gd

const WORLD := preload("res://mods/unfplap/world/service.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")

var checks := 0
var failures := 0


class FakeMods extends Node:
	var data := {"unfplap": {}}
	var saves := 0

	func state(id: String) -> Dictionary:
		var value: Variant = data.get(id, {})
		return value if value is Dictionary else {}

	func save_changed() -> void:
		saves += 1


class FakeGame extends Node:
	var inventory: Variant = null
	var world_context: Node


class FakeContext extends Node:
	var impressions: Node
	var events: Array = []

	func record(kind: String, text: String, _witnesses: Array, _subjects: Array,
			event_id: String) -> void:
		events.append({"kind": kind, "text": text, "id": event_id})


class FakeImpressions extends Node:
	var calls: Array = []

	func commit(id: String, data: Dictionary, event_id: String) -> void:
		calls.append({"id": id, "data": data.duplicate(true), "event_id": event_id})


class FakeBonds extends Node:
	var requests := 0
	var unwanted := 0

	func request_space(_id: String) -> bool:
		requests += 1
		return true

	func unwanted_contact(_id: String, _kind: String) -> float:
		unwanted += 1
		return 40.0


class FakeRelation extends Node:
	var bonds: Node


class FakeAffection extends Node:
	var bucks := 0

	func buck(_body: Node) -> bool:
		bucks += 1
		return true


class FakePony extends Node3D:
	var sleeping := false
	var face_turn_rate := 0.45
	var body_scale := 1.0
	var posture: Variant = null
	var expressions: Variant = null
	var posture_requests: Array[String] = []

	func posture_status() -> Dictionary:
		return {"requested": "stand", "settled": true}

	func request_posture(name: String) -> bool:
		posture_requests.append(name)
		return true

	func is_held() -> bool:
		return false

	func grounded() -> bool:
		return true


class FakeNav extends Node:
	var reserved_by := ""
	var command_owner := ""
	var wander_enabled := true

	func stay() -> void:
		pass


class FakePlayer extends Node3D:
	var _pitch := 0.0
	var _stand_eye := 1.6
	var _eye_height := 1.6
	var controls_locked := false
	var form_driver: Variant = null
	var seat: Variant = null

	func eye_height() -> float:
		return _stand_eye

	func _set_eye_y(_value: float) -> void:
		pass


class FakeInventory extends RefCounted:
	var hud_hidden := false
	var hotbar: Variant = null

	func _place_hotbar() -> void:
		pass


class FakeHUD extends Node:
	func hide_all() -> void:
		pass

	func hide_prompt() -> void:
		pass


class FakeMain extends Node:
	var player: Variant = null
	var game: Variant = null
	var hud: Variant = null
	var memory: Variant = null

	func player_body() -> Node3D:
		return player as Node3D

	func camera() -> Camera3D:
		return null


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func fixture(kind: String) -> Dictionary:
	var mods := FakeMods.new()
	var existing: Node = root.get_node_or_null("Mods")
	if existing != null:
		existing.name = "ModsTestHidden"
	mods.name = "Mods"
	root.add_child(mods)
	var runtime: Node = RUNTIME.new()
	var pony := FakePony.new()
	pony.posture = Node.new()
	pony.add_child(pony.posture)
	var nav := FakeNav.new()
	var main := FakeMain.new()
	var game := FakeGame.new()
	var context := FakeContext.new()
	var impressions := FakeImpressions.new()
	context.impressions = impressions
	game.world_context = context
	game.inventory = FakeInventory.new()
	var player := FakePlayer.new()
	var hud := FakeHUD.new()
	var bonds := FakeBonds.new()
	var relation := FakeRelation.new()
	relation.bonds = bonds
	var affection := FakeAffection.new()
	affection.name = "Affection"
	pony.add_child(affection)
	pony.set_meta("relationship_runtime", relation)
	main.player = player
	WORLD.bind_player(main.player)
	main.game = game
	WORLD.bind_world(main.game)
	main.hud = hud
	var memory := MEMORY.new()
	memory.setup(main)
	main.memory = memory
	runtime.add_child(pony)
	runtime.add_child(nav)
	runtime.add_child(main)
	main.add_child(player)
	main.add_child(game)
	main.add_child(hud)
	root.add_child(context)
	root.add_child(impressions)
	runtime.pony = pony
	runtime.main = main
	runtime._id = "rarity"
	runtime._display_name = "Rarity"
	runtime._event_id = "intimacy_stop_test"
	runtime._preferences = {"tolerance": kind, "intensity": "soft", "pattern": "steady",
		"talk": [], "touch": [], "dislikes": ["smack"]}
	runtime._summary_service.summary_done = false
	runtime.state = 2 # ACTIVE
	runtime.pose_id = "standing"
	runtime._snapshot_settings()
	runtime.pony_climaxes = 1
	runtime._act_seconds = 90.0
	runtime._readiness.act_thrusts = 10
	runtime._posture_owned = true
	runtime._hold.nav = nav
	runtime._hold.token = "unfplap:test"
	nav.command_owner = "unfplap:test"
	pony.face_turn_rate = 0.0
	runtime._hold.face_turn_rate_saved = 0.45
	runtime._hold.face_turn_rate_owned = true
	pony.set_meta("sex_active", true)
	return {
		"runtime": runtime, "pony": pony, "main": main, "game": game,
		"context": context, "impressions": impressions, "bonds": bonds,
		"affection": affection, "mods": mods, "existing": existing,
	}


func run() -> void:
	var normal := fixture("normal")
	var normal_runtime: Node = normal["runtime"]
	normal_runtime.call("_stop_with_her", "smack")
	check(int(normal_runtime.state) == 0, "a normal stop ends the act")
	check(bool(normal_runtime.get("_stopped_by_her")), "a normal stop is flagged")
	var normal_summary: Dictionary = normal_runtime._summary_service.summary
	check(str(normal_summary.get("grade", "")) == "bad", "a normal stop commits a bad summary")
	check(int(normal["bonds"].requests) == 0, "a normal stop does not request space")
	check(int(normal["affection"].bucks) == 0, "a normal stop does not buck")
	var normal_row: Dictionary = (normal["mods"].data["unfplap"].get("act_history", {}) as Dictionary).get("rarity", {})
	check(float(normal_row.get("stop_until", 0.0)) > Time.get_unix_time_from_system(),
		"a normal stop writes a cooldown")
	check(str(normal_summary.get("mood", "")) == "annoyed", "a normal stop is annoyed")
	var normal_calls: Array = (normal["impressions"] as Node).calls
	check(normal_calls.size() == 1, "a normal stop writes one impression")
	var normal_impression: Dictionary = normal_calls[0]
	check(str((normal_impression.get("data", {}) as Dictionary).get("mood", "")) == "annoyed",
		"the stop impression carries the summary mood")
	check(normal_runtime._face.mood_face == null,
		"the stop face waits for a runtime in the tree")
	var normal_events: Array = normal["context"].events
	check(normal_events.size() == 1, "a partner stop writes one world event")
	check(str((normal_events[0] as Dictionary).get("kind", "")) == "relationship",
		"the one partner-stop event is the summary")
	normal_runtime.queue_free()
	normal["main"].queue_free()
	normal["context"].queue_free()
	normal["impressions"].queue_free()
	normal["mods"].free()
	if normal["existing"] != null and is_instance_valid(normal["existing"]):
		normal["existing"].name = "Mods"

	var strict := fixture("strict")
	var strict_runtime: Node = strict["runtime"]
	strict_runtime.call("_stop_with_her", "smack")
	check(bool(strict_runtime.get("_stopped_by_her")), "a strict stop is flagged")
	var strict_summary: Dictionary = strict_runtime._summary_service.summary
	check(str(strict_summary.get("mood", "")) == "angry", "a strict stop is angry")
	var strict_calls: Array = (strict["impressions"] as Node).calls
	check(strict_calls.size() == 1, "a strict stop writes one impression")
	var strict_impression: Dictionary = strict_calls[0]
	check(str((strict_impression.get("data", {}) as Dictionary).get("mood", "")) == "angry",
		"the strict impression carries the angry mood")
	var strict_events: Array = strict["context"].events
	check(strict_events.size() == 1, "a strict partner stop also writes one world event")
	check(int(strict["bonds"].requests) == 1, "a strict stop requests space")
	check(int(strict["affection"].bucks) == 1, "a strict stop bucks")
	var strict_row: Dictionary = (strict["mods"].data["unfplap"].get("act_history", {}) as Dictionary).get("rarity", {})
	check(float(strict_row.get("stop_until", 0.0)) > float(normal_row.get("stop_until", 0.0)),
		"the strict cooldown is longer than normal")
	strict_runtime.queue_free()
	strict["main"].queue_free()
	strict["context"].queue_free()
	strict["impressions"].queue_free()
	strict["mods"].free()
	if strict["existing"] != null and is_instance_valid(strict["existing"]):
		strict["existing"].name = "Mods"

	var paused_fixture := fixture("normal")
	var paused_runtime: Node = paused_fixture["runtime"]
	root.add_child(paused_runtime)
	paused = true
	var gate: Variant = paused_runtime.call("_scene_gate")
	var blocked_rows: Array = gate.call("offer_verdict", "standing", "", null).get("rows", [])
	var blocked: PackedStringArray = gate.call("report_reasons", blocked_rows)
	check("paused" in blocked, "a paused tree rejects a normal offer")
	var forced_rows: Array = gate.call("offer_verdict", "standing", "", null, true).get("rows", [])
	var forced: PackedStringArray = gate.call("report_reasons", forced_rows)
	check(not ("paused" in forced), "the debug offer bypasses the paused gate")
	paused = false
	root.remove_child(paused_runtime)
	paused_runtime.queue_free()
	paused_fixture["main"].queue_free()
	paused_fixture["context"].queue_free()
	paused_fixture["impressions"].queue_free()
	paused_fixture["mods"].free()
	if paused_fixture["existing"] != null and is_instance_valid(paused_fixture["existing"]):
		paused_fixture["existing"].name = "Mods"

	print("ACT_STOP_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACT_STOP_PASS")
	quit(0 if failures == 0 else 1)
