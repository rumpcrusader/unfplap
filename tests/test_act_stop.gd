extends SceneTree
## Runtime stop path: neutral and strict stops end the act, commit a severe summary, and only
## strict requests space and bucks. A refusal writes the game's angry/annoyed impression and
## holds the matching face. No live world is needed.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_act_stop.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const ACT_HISTORY := preload("res://mods/unfplap/act_history.gd")
const UPSET := preload("res://mods/unfplap/upset.gd")

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

	func record(_kind: String, _text: String, _witnesses: Array, _subjects: Array,
			_event_id: String) -> void:
		pass


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
	var cleared: Array = []

	func clear_active(runtime: Node) -> void:
		cleared.append(runtime)

	func player_body() -> Node3D:
		return player as Node3D

	func camera() -> Camera3D:
		return null

	func debug(_text: String) -> void:
		pass


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
	main.game = game
	main.hud = hud
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
	runtime._taste = {"tolerance": kind, "intensity": "soft", "pattern": "steady",
		"talk": [], "touch": [], "dislikes": ["smack"]}
	runtime._summary_done = false
	runtime.state = 2 # ACTIVE
	runtime.pose_id = "standing"
	runtime.pony_climaxes = 1
	runtime._act_seconds = 90.0
	runtime._act_thrusts = 10
	runtime._posture_owned = true
	runtime._nav = nav
	runtime._token = "unfplap:test"
	nav.command_owner = "unfplap:test"
	pony.face_turn_rate = 0.0
	runtime._face_turn_rate_saved = 0.45
	runtime._face_turn_rate_owned = true
	pony.set_meta("sex_active", true)
	return {
		"runtime": runtime, "pony": pony, "main": main, "game": game,
		"context": context, "impressions": impressions, "bonds": bonds,
		"affection": affection, "mods": mods, "existing": existing,
	}


func run() -> void:
	var neutral := fixture("neutral")
	var neutral_runtime: Node = neutral["runtime"]
	neutral_runtime.call("_stop_with_her", "smack")
	check(int(neutral_runtime.state) == 0, "a neutral stop ends the act")
	check(bool(neutral_runtime.get("_stopped_by_her")), "a neutral stop is flagged")
	var neutral_summary: Dictionary = neutral_runtime.get("_summary")
	check(str(neutral_summary.get("grade", "")) == "bad", "a neutral stop commits a bad summary")
	check(int(neutral["bonds"].requests) == 0, "a neutral stop does not request space")
	check(int(neutral["affection"].bucks) == 0, "a neutral stop does not buck")
	var neutral_row: Dictionary = (neutral["mods"].data["unfplap"].get("act_history", {}) as Dictionary).get("rarity", {})
	check(float(neutral_row.get("stop_until", 0.0)) > Time.get_unix_time_from_system(),
		"a neutral stop writes a cooldown")
	check(str(neutral_summary.get("mood", "")) == "annoyed", "a neutral stop is annoyed")
	neutral_runtime.queue_free()
	neutral["main"].queue_free()
	neutral["context"].queue_free()
	neutral["impressions"].queue_free()
	neutral["mods"].free()
	if neutral["existing"] != null and is_instance_valid(neutral["existing"]):
		neutral["existing"].name = "Mods"

	var strict := fixture("strict")
	var strict_runtime: Node = strict["runtime"]
	strict_runtime.call("_stop_with_her", "smack")
	check(bool(strict_runtime.get("_stopped_by_her")), "a strict stop is flagged")
	var strict_summary: Dictionary = strict_runtime.get("_summary")
	check(str(strict_summary.get("mood", "")) == "angry", "a strict stop is angry")
	check(int(strict["bonds"].requests) == 1, "a strict stop requests space")
	check(int(strict["affection"].bucks) == 1, "a strict stop bucks")
	var strict_row: Dictionary = (strict["mods"].data["unfplap"].get("act_history", {}) as Dictionary).get("rarity", {})
	check(float(strict_row.get("stop_until", 0.0)) > float(neutral_row.get("stop_until", 0.0)),
		"the strict cooldown is longer than neutral")
	strict_runtime.queue_free()
	strict["main"].queue_free()
	strict["context"].queue_free()
	strict["impressions"].queue_free()
	strict["mods"].free()
	if strict["existing"] != null and is_instance_valid(strict["existing"]):
		strict["existing"].name = "Mods"

	var refused := fixture("neutral")
	var refused_runtime: Node = refused["runtime"]
	refused_runtime.call("_note_refusal", false)
	var turned: Dictionary = (refused["impressions"] as Node).calls[-1]
	check(str((turned["data"] as Dictionary).get("mood", "")) == "annoyed",
		"a turn-away refusal is annoyed")
	check(str(turned.get("event_id", "")).ends_with(":mood"),
		"the refusal mood uses its own commit id")
	check(int(refused["bonds"].unwanted) == 1, "a refusal costs a little trust")
	refused_runtime.call("_note_refusal", true)
	var bucked: Dictionary = (refused["impressions"] as Node).calls[-1]
	check(str((bucked["data"] as Dictionary).get("mood", "")) == "angry", "a buck is angry")
	check(int(refused["bonds"].unwanted) == 2, "each refusal costs trust once")
	check(refused_runtime.get("_upset") == null,
		"the face waits for a runtime in the tree")
	check(UPSET.DURATION == 300.0, "the mood face matches the 300 s impression freshness")
	check(str(UPSET.MOOD_FACES.get("annoyed", "")) == "annoyed"
		and str(UPSET.MOOD_FACES.get("angry", "")) == "angry",
		"the mood face uses the game's expression names")
	root.add_child(refused_runtime)
	paused = true
	var blocked: PackedStringArray = refused_runtime.call("offer_reasons", "standing", "", null)
	check("paused" in blocked, "a paused tree rejects a normal offer")
	var forced: PackedStringArray = refused_runtime.call("offer_reasons", "standing", "", null, true)
	check(not ("paused" in forced), "the debug offer bypasses the paused gate")
	paused = false
	root.remove_child(refused_runtime)
	refused_runtime.queue_free()
	refused["main"].queue_free()
	refused["context"].queue_free()
	refused["impressions"].queue_free()
	refused["mods"].free()
	if refused["existing"] != null and is_instance_valid(refused["existing"]):
		refused["existing"].name = "Mods"

	print("ACT_STOP_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACT_STOP_PASS")
	quit(0 if failures == 0 else 1)
