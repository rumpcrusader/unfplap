extends SceneTree
## Act-history wiring that can be checked without a live world: the runtime commits one
## summary, the afterglow HUD carries it, and the snapshot uses the action counters.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_act_flow.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")

var failures := 0
var checks := 0


class FakeMods extends Node:
	var data := {"unfplap": {}}
	var saves := 0

	func state(id: String) -> Dictionary:
		var value: Variant = data.get(id, {})
		return value if value is Dictionary else {}

	func save_changed() -> void:
		saves += 1


class FakeGame extends Node:
	var world_context: Node


class FakeContext extends Node:
	var impressions: Node
	var events: Array = []

	func record(kind: String, text: String, witnesses: Array, subjects: Array,
			event_id: String) -> void:
		events.append({"kind": kind, "text": text, "id": event_id})


class FakeImpressions extends Node:
	var calls: Array = []

	func commit(id: String, data: Dictionary, event_id: String) -> void:
		calls.append({"id": id, "data": data.duplicate(true), "event_id": event_id})


class FakeMain extends Node:
	var game: Node
	var lines: Array[String] = []

	func debug(text: String) -> void:
		lines.append(text)


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var runtime: Node = RUNTIME.new()
	runtime.pony = Node3D.new()
	runtime._taste = {"intensity": "firm", "pattern": "steady", "talk": ["praise"]}
	runtime.state = 4 # AFTERGLOW
	runtime.pose_id = CATALOG.MISSIONARY
	runtime.pony_climaxes = 2
	runtime._summary = {
		"hud": "Great · she felt adored",
		"note": "You and Anon made love. You felt completely wanted.",
		"positive": true, "reward": true, "grade": "great",
	}
	check(str(runtime.call("hud_cue_line", true)).contains("Great"), "missionary afterglow cue shows the summary")
	check(str(runtime.call("hud_readiness_line", true)).is_empty(),
		"missionary afterglow does not duplicate the summary")
	runtime.pose_id = CATALOG.STANDING
	runtime._close_left = 8.0
	check(str(runtime.call("hud_cue_line", true)).contains("Stay close"),
		"standing afterglow cue keeps the close prompt")
	check(str(runtime.call("hud_readiness_line", true)).contains("Great"),
		"standing afterglow readiness line shows the summary")
	check(str(runtime.call("hud_readiness_line", false)).contains("Great"),
		"the afterglow summary ignores the readouts toggle")
	runtime.state = 2 # ACTIVE
	check(not str(runtime.call("hud_readiness_line", true)).is_empty(),
		"active readiness line still works")
	runtime.free()

	# The snapshot must carry the per-act counters the pure scorer expects.
	var probe: Node = RUNTIME.new()
	probe._act_touch_counts = {"smack": 2}
	probe._act_touch_dislikes = {"smack": 2}
	probe._act_talk_dislikes = 1
	probe._act_player_lines = 0
	probe._act_thrusts = 5
	probe._act_intensity_total = 4
	probe._act_intensity_right = 3
	probe._act_pattern_total = 3
	probe._act_pattern_right = 1
	probe._act_liked_touch = 0
	probe._act_liked_talk = 0
	probe._act_ended_early = false
	probe.pony_climaxes = 1
	probe._act_seconds = 90.0
	var inputs: Dictionary = probe.call("_summary_inputs")
	check(int(inputs.get("thrusts", 0)) == 5, "snapshot carries real thrusts")
	check(int((inputs.get("touch_dislikes", {}) as Dictionary).get("smack", 0)) == 2,
		"snapshot carries disliked touch kinds")
	check(int(inputs.get("talk_dislikes", 0)) == 1, "snapshot carries disliked talk")
	check(int(inputs.get("player_lines", 0)) == 0, "snapshot carries player lines")
	check(int(inputs.get("pattern_right", 0)) == 1, "snapshot carries pattern matches")
	probe.free()

	_check_commit()

	print("ACT_FLOW_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACT_FLOW_PASS")
	quit(0 if failures == 0 else 1)


func _check_commit() -> void:
	var mods := FakeMods.new()
	var existing: Node = root.get_node_or_null("Mods")
	if existing != null and existing != mods:
		existing.name = "ModsTestHidden"
	mods.name = "Mods"
	root.add_child(mods)
	var game := FakeGame.new()
	var context := FakeContext.new()
	var impressions := FakeImpressions.new()
	context.impressions = impressions
	game.world_context = context
	root.add_child(game)
	root.add_child(context)
	root.add_child(impressions)
	var main := FakeMain.new()
	main.game = game
	root.add_child(main)
	var runtime: Node = RUNTIME.new()
	runtime.main = main
	runtime._id = "rarity"
	runtime._display_name = "Rarity"
	runtime._event_id = "intimacy_test"
	runtime._taste = {"intensity": "firm", "pattern": "steady", "talk": [],
		"touch": [], "dislikes": []}
	runtime._act_seconds = 90.0
	runtime._act_thrusts = 10
	runtime.pony_climaxes = 1
	runtime._act_intensity_total = 5
	runtime._act_intensity_right = 5
	runtime._act_pattern_total = 5
	runtime._act_pattern_right = 5
	runtime._act_player_lines = 0
	runtime._act_liked_talk = 0
	runtime._act_liked_touch = 0
	runtime._act_touch_dislikes = {}
	runtime._act_ended_early = false
	runtime.call("_commit_summary", true)
	check(not (runtime._summary as Dictionary).is_empty(), "the runtime commits one summary")
	check(str((runtime._summary as Dictionary).get("grade", "")) == "good",
		"a clean act summary is good")
	check(mods.saves >= 1, "the summary is saved to the mod state")
	var section: Dictionary = mods.data.get("unfplap", {})
	var rows: Dictionary = section.get("act_history", {})
	check(rows.has("rarity"), "the history row is written")
	check(int((rows.get("rarity", {}) as Dictionary).get("acts", 0)) == 1,
		"the history row counts the act once")
	check(impressions.calls.size() == 1, "the grade-aware impression is written once")
	if not impressions.calls.is_empty():
		check(int((impressions.calls[0]["data"] as Dictionary).get("romance", 0)) == 2,
			"a good summary gives romance +2")
	check(context.events.size() == 1, "the summary relationship event is written once")
	runtime.call("_commit_summary", true)
	check(int((rows.get("rarity", {}) as Dictionary).get("acts", 0)) == 1,
		"a second commit is a no-op")
	check(impressions.calls.size() == 1, "a second commit writes no second impression")
	runtime.free()
	main.free()
	game.free()
	context.free()
	impressions.free()
	mods.free()
	if existing != null and is_instance_valid(existing):
		existing.name = "Mods"
