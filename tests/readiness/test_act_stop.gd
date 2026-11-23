extends "res://mods/unfplap/tests/support/suite.gd"
## Runtime stop path: neutral and strict stops end the act, commit a severe summary, and only
## strict requests space and bucks. The stop mood reaches the summary and its impression, and the
## stop face waits for an in-tree runtime. No live world is needed.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/readiness/test_act_stop.gd

const WORLD := preload("res://mods/unfplap/world/api.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const HANDLES := preload("res://mods/unfplap/world/handles.gd")



class FakeMods extends "res://mods/unfplap/tests/support/fakes/fake_mods.gd":
	pass


class FakeGame extends Node:
	var inventory: Variant = null
	var world_context: Node


class FakeContext extends Node:
	var impressions: Node
	var events: Array = []

	func record(kind: String, text: String, _witnesses: Array, _subjects: Array,
			event_id: String) -> void:
		events.append({"kind": kind, "text": text, "id": event_id})


class FakeImpressions extends "res://mods/unfplap/tests/support/fakes/fake_impressions.gd":
	pass


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


class FakeNav extends "res://mods/unfplap/tests/support/fakes/fake_nav.gd":
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


class FakeHUD extends HUD:
	## The base builds the live card and subscribes to settings; this suite drives no card.
	func _ready() -> void:
		pass

	func _exit_tree() -> void:
		pass

	func hide_all() -> void:
		pass

	func hide_prompt() -> void:
		pass

	func set_inventory_hidden(_on: bool) -> void:
		pass

	func set_state(_state: String) -> void:
		pass

	func show_act(_facts: Variant) -> void:
		pass

	func update_from(_facts: Variant) -> void:
		pass

	func hide_act() -> void:
		pass

	func ensure_act_inventory_visible(_runtime: Variant) -> void:
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


func fixture(kind: String) -> Dictionary:
	var mods := FakeMods.new()
	var existing: Node = root.get_node_or_null("Mods")
	if existing != null:
		existing.name = "ModsTestHidden"
	mods.name = "Mods"
	root.add_child(mods)
	var hud := FakeHUD.new()
	var memory := MEMORY.new()
	var world := HANDLES.new()
	world.hud = hud
	world.memory = memory
	var runtime: Node = RUNTIME.new(null, world)
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
	runtime.act.pony_id = "rarity"
	runtime.act.pony_id = "rarity"
	runtime.act.display_name = "Rarity"
	runtime.act.event_id = "intimacy_stop_test"
	runtime.act.preferences = {"tolerance": kind, "intensity": "soft", "pattern": "steady",
		"talk": [], "touch": [], "dislikes": ["smack"]}
	runtime.act.context.summary.summary_done = false
	runtime.act._set_state(2) # ACTIVE
	runtime.act.pose_id = "standing"
	runtime.act.snapshot_settings()
	runtime.act.context.readiness.pony_climaxes = 1
	runtime.act._act_seconds = 90.0
	runtime.act.context.readiness.act_thrusts = 10
	runtime.act.posture_owned = true
	runtime.act.context.hold.nav = nav
	runtime.act.context.hold.token = "unfplap:test"
	nav.command_owner = "unfplap:test"
	pony.face_turn_rate = 0.0
	runtime.act.context.hold.face_turn_rate_saved = 0.45
	runtime.act.context.hold.face_turn_rate_owned = true
	pony.set_meta("sex_active", true)
	return {
		"runtime": runtime, "pony": pony, "main": main, "game": game,
		"context": context, "impressions": impressions, "bonds": bonds,
		"affection": affection, "mods": mods, "existing": existing,
		"memory": memory, "relation": relation,
	}


func run() -> void:
	var normal := fixture("normal")
	var normal_runtime: Node = normal["runtime"]
	normal_runtime.act.context.consent.stop_with_her("smack")
	check(int(normal_runtime.act.state) == 0, "a normal stop ends the act")
	check(bool(normal_runtime.act.stopped_by_her), "a normal stop is flagged")
	var normal_summary: Dictionary = normal_runtime.act.context.summary.summary
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
	check(normal_runtime.act.context.face.mood_face == null,
		"the stop face waits for a runtime in the tree")
	var normal_events: Array = normal["context"].events
	check(normal_events.size() == 1, "a partner stop writes one world event")
	check(str((normal_events[0] as Dictionary).get("kind", "")) == "relationship",
		"the one partner-stop event is the summary")
	root.add_child(normal_runtime)
	normal_runtime.queue_free()
	normal["main"].queue_free()
	normal["context"].queue_free()
	normal["impressions"].queue_free()
	normal["mods"].free()
	normal["memory"].free()
	normal["relation"].free()
	normal["bonds"].free()
	if normal["existing"] != null and is_instance_valid(normal["existing"]):
		normal["existing"].name = "Mods"

	var strict := fixture("strict")
	var strict_runtime: Node = strict["runtime"]
	strict_runtime.act.context.consent.stop_with_her("smack")
	check(bool(strict_runtime.act.stopped_by_her), "a strict stop is flagged")
	var strict_summary: Dictionary = strict_runtime.act.context.summary.summary
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
	root.add_child(strict_runtime)
	strict_runtime.queue_free()
	strict["main"].queue_free()
	strict["context"].queue_free()
	strict["impressions"].queue_free()
	strict["mods"].free()
	strict["memory"].free()
	strict["relation"].free()
	strict["bonds"].free()
	if strict["existing"] != null and is_instance_valid(strict["existing"]):
		strict["existing"].name = "Mods"

	var paused_fixture := fixture("normal")
	var paused_runtime: Node = paused_fixture["runtime"]
	root.add_child(paused_runtime)
	paused = true
	var gate: Variant = paused_runtime.act.context.gate
	var blocked_rows: Array = gate.call("offer_verdict", "standing", "", null).rows
	var blocked: PackedStringArray = gate.call("report_reasons", blocked_rows)
	check("paused" in blocked, "a paused tree rejects a normal offer")
	var forced_rows: Array = gate.call("offer_verdict", "standing", "", null, true).rows
	var forced: PackedStringArray = gate.call("report_reasons", forced_rows)
	check(not ("paused" in forced), "the debug offer bypasses the paused gate")
	paused = false
	root.remove_child(paused_runtime)
	paused_runtime.queue_free()
	paused_fixture["main"].queue_free()
	paused_fixture["context"].queue_free()
	paused_fixture["impressions"].queue_free()
	paused_fixture["mods"].free()
	paused_fixture["memory"].free()
	paused_fixture["relation"].free()
	paused_fixture["bonds"].free()
	if paused_fixture["existing"] != null and is_instance_valid(paused_fixture["existing"]):
		paused_fixture["existing"].name = "Mods"

	if failures == 0:
		print("ACT_STOP_PASS")
	finish()
