extends "res://mods/unfplap/tests/support/suite.gd"
## Act-history wiring that can be checked without a live world: the runtime commits one
## summary, the afterglow HUD carries it, and the snapshot uses the action counters.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/summary/test_act_flow.gd

const WORLD := preload("res://mods/unfplap/world/api.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const HANDLES := preload("res://mods/unfplap/world/handles.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const SUMMARY := preload("res://mods/unfplap/summary/service.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const HUD_LINES := preload("res://mods/unfplap/hud/lines.gd")



class FakeMods extends "res://mods/unfplap/tests/support/fakes/fake_mods.gd":
	pass


class FakeGame extends Node:
	var world_context: Node


class FakeContext extends Node:
	var impressions: Node
	var events: Array = []

	func record(kind: String, text: String, witnesses: Array, subjects: Array,
			event_id: String) -> void:
		events.append({"kind": kind, "text": text, "id": event_id})


class FakeImpressions extends "res://mods/unfplap/tests/support/fakes/fake_impressions.gd":
	pass


class FakePeakSink extends MEMORY:
	var peaks: Array = []

	func record_peak(peak: MEMORY.Peak) -> void:
		peaks.append(peak)


class FakeMain extends Node:
	var game: Node
	var memory


func _hud_view(runtime: Node) -> RefCounted:
	runtime.act.refresh_view()
	runtime.act.sync_hud()
	return runtime.act.facts()


func run() -> void:
	_check_summary_shapes()
	var runtime: Node = RUNTIME.new()
	runtime.pony = Node3D.new()
	runtime.act.preferences = {"intensity": "firm", "pattern": "steady", "talk": ["praise"]}
	runtime.act._set_state(4) # AFTERGLOW
	runtime.act.pose_id = CATALOG.MISSIONARY
	runtime.act.snapshot_settings()
	runtime.act.context.readiness.pony_climaxes = 2
	runtime.act.context.summary.summary = {
		"hud": "Great · she felt adored",
		"thought": "He gave me what I needed; I felt wanted.",
		"positive": true, "reward": true, "grade": "great",
	}
	check(HUD_LINES.cue_line_for(_hud_view(runtime), true).contains("Great"),
		"missionary afterglow cue shows the summary")
	runtime.act.context.afterglow.beat = "You are warm and quiet."
	var afterglow_note := str(runtime.act.prompt_note())
	check(afterglow_note.contains("You are warm and quiet"), "afterglow uses its private beat")
	check(not afterglow_note.contains("I felt wanted") and not afterglow_note.contains("This act"),
		"afterglow does not recite the act summary")
	check(not afterglow_note.contains("Next time you want"),
		"afterglow drops the mechanical next-time line")
	check(HUD_LINES.readiness_line_for(_hud_view(runtime), true).is_empty(),
		"missionary afterglow does not duplicate the summary")
	runtime.act.pose_id = CATALOG.STANDING
	runtime.act.context.afterglow.close_left = 8.0
	check(HUD_LINES.cue_line_for(_hud_view(runtime), true).contains("Stay close"),
		"standing afterglow cue keeps the close prompt")
	check(HUD_LINES.readiness_line_for(_hud_view(runtime), true).contains("Great"),
		"standing afterglow readiness line shows the summary")
	check(HUD_LINES.readiness_line_for(_hud_view(runtime), false).contains("Great"),
		"the afterglow summary ignores the readouts toggle")
	runtime.act._set_state(2) # ACTIVE
	check(not HUD_LINES.readiness_line_for(_hud_view(runtime), true).is_empty(),
		"active readiness line still works")
	runtime.free()

	# The snapshot must carry the per-act counters the pure scorer expects.
	var probe: Node = RUNTIME.new()
	probe.act.context.readiness.act_touch_counts = {"smack": 2}
	probe.act.context.readiness.act_touch_dislikes = {"smack": 2}
	probe.act.context.readiness.act_talk_dislikes = 1
	probe.act.context.readiness.act_player_lines = 0
	probe.act.context.readiness.act_thrusts = 5
	probe.act.context.readiness.act_intensity_total = 4
	probe.act.context.readiness.act_intensity_right = 3
	probe.act.context.readiness.act_pattern_total = 3
	probe.act.context.readiness.act_pattern_right = 1
	probe.act.context.readiness.act_liked_touch = 0
	probe.act.context.readiness.act_liked_talk = 0
	probe.act.ended_early = false
	probe.act.context.readiness.pony_climaxes = 1
	probe.act._act_seconds = 90.0
	var inputs: SUMMARY.Inputs = probe.act.context.summary.summary_inputs(
		probe.act.act_input().as_inputs(probe.act.context.readiness))
	check(inputs.thrusts == 5, "snapshot carries real thrusts")
	check(int((inputs.touch_dislikes as Dictionary).get("smack", 0)) == 2,
		"snapshot carries disliked touch kinds")
	check(inputs.talk_dislikes == 1, "snapshot carries disliked talk")
	check(inputs.player_lines == 0, "snapshot carries player lines")
	check(inputs.pattern_right == 1, "snapshot carries pattern matches")
	probe.free()

	_check_commit()
	_check_peak_commit()

	if failures == 0:
		print("ACT_FLOW_PASS")
	finish()


func _check_summary_shapes() -> void:
	var main := FakeMain.new()
	root.add_child(main)
	var summary := SUMMARY.new()
	var gathered: Dictionary = {
		"main": main,
		"pony_id": "rarity",
		"event_id": "intimacy_test",
		"preferences": {"tolerance": "forgiving", "touch": ["cheek"]},
		"seconds": 42.5,
		"thrusts": 7,
		"pony_climaxes": 2,
		"talk_liked": 1,
		"talk_dislikes": 0,
		"touches_liked": 2,
		"touch_dislikes": {"smack": 1},
		"player_lines": 3,
		"intensity_total": 6,
		"intensity_right": 5,
		"pattern_total": 4,
		"pattern_right": 3,
		"ended_early": false,
		"stopped_by_her": true,
	}
	var built := summary.summary_inputs(SUMMARY.Inputs.from_dict(gathered))
	check(is_equal_approx(built.seconds, 42.5), "the input keeps the act seconds")
	check(built.thrusts == 7, "the input keeps the real thrusts")
	check(int((built.touch_dislikes as Dictionary).get("smack", 0)) == 1,
		"the input keeps the disliked touch kinds")
	check(built.tolerance == "forgiving",
		"the tolerance comes from the gathered preferences")
	check(built.stopped_by_her, "the input keeps the partner stop")
	check(not built.forced, "a missing forced flag reads false")
	var wrapped := summary.summary_context(SUMMARY.Inputs.from_dict(gathered))
	check(wrapped.pony_id == "rarity" and wrapped.event_id == "intimacy_test",
		"the context keeps the ids")
	check(wrapped.inputs.to_dict().has("touch_dislikes"),
		"the context wraps the built inputs")
	main.free()


## The peak memory is written once per act from the committed summary, with the act's exchange.
func _check_peak_commit() -> void:
	var game := FakeGame.new()
	root.add_child(game)
	var sink := FakePeakSink.new()
	root.add_child(sink)
	var main := FakeMain.new()
	main.game = game
	WORLD.bind_world(main.game)
	main.memory = sink
	root.add_child(main)
	var summary := SUMMARY.new()
	summary.wire(sink, null, null)
	check(not summary.peak_recorded, "the peak flag starts clear")
	summary.summary = {"positive": true, "grade": "good"}
	var context := SUMMARY.Context.new()
	context.pony_id = "rarity"
	context.event_id = "intimacy_test"
	context.satisfaction = 95.0
	context.both_matches = 6
	context.dislikes = 0
	context.liked_touch = 1
	context.liked_talk = 0
	context.player_talk = "you are perfect"
	context.her_at = 10.0
	context.her_line = "I know."
	summary.record_peak_memory(context, 5.0)
	check(sink.peaks.size() == 1, "a peak act is stored once")
	if not sink.peaks.is_empty():
		var peak: MEMORY.Peak = sink.peaks[0]
		check(peak.text.contains("you are perfect") and peak.text.contains("I know."),
			"the peak quotes the act's exchange")
		check(peak.score > 0.0, "the peak keeps its score")
	summary.record_peak_memory(SUMMARY.Context.new(), 0.0)
	check(sink.peaks.size() == 1, "the peak is stored once per act")
	main.free()
	game.free()
	sink.free()


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
	WORLD.bind_world(main.game)
	main.memory = MEMORY.new()
	root.add_child(main)
	var world := HANDLES.new()
	world.memory = main.memory
	var runtime: Node = RUNTIME.new(null, world)
	runtime.act.pony_id = "rarity"
	runtime.act.pony_id = "rarity"
	runtime.act.display_name = "Rarity"
	runtime.act.event_id = "intimacy_test"
	runtime.act.preferences = {"intensity": "firm", "pattern": "steady", "talk": [],
		"touch": [], "dislikes": []}
	runtime.act._act_seconds = 90.0
	runtime.act.context.readiness.act_thrusts = 10
	runtime.act.context.readiness.pony_climaxes = 1
	runtime.act.context.readiness.act_intensity_total = 5
	runtime.act.context.readiness.act_intensity_right = 5
	runtime.act.context.readiness.act_pattern_total = 5
	runtime.act.context.readiness.act_pattern_right = 5
	runtime.act.context.readiness.act_player_lines = 0
	runtime.act.context.readiness.act_liked_talk = 0
	runtime.act.context.readiness.act_liked_touch = 0
	runtime.act.context.readiness.act_touch_dislikes = {}
	runtime.act.ended_early = false
	runtime.act.commit_summary(true)
	check(not (runtime.act.context.summary.summary as Dictionary).is_empty(), "the runtime commits one summary")
	check(str((runtime.act.context.summary.summary as Dictionary).get("grade", "")) == "good",
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
	runtime.act.commit_summary(true)
	check(int((rows.get("rarity", {}) as Dictionary).get("acts", 0)) == 1,
		"a second commit is a no-op")
	check(impressions.calls.size() == 1, "a second commit writes no second impression")

	# A partner stop forces a severe bad summary and a history cooldown.
	runtime.act.stopped_by_her = true
	runtime.act.context.summary.summary = {}
	runtime.act.context.summary.summary_done = false
	runtime.act.context.readiness.act_touch_dislikes = {"smack": 2}
	runtime.act.context.readiness.act_talk_dislikes = 0
	runtime.act.preferences = {"tolerance": "strict", "intensity": "soft", "pattern": "steady",
		"talk": [], "touch": [], "dislikes": ["smack"]}
	runtime.act.commit_summary(false)
	var stopped_summary: Dictionary = runtime.act.context.summary.summary
	check(str(stopped_summary.get("grade", "")) == "bad", "a partner stop is a bad summary")
	check(bool(stopped_summary.get("severe", false)), "a partner stop is severe")
	check(int(stopped_summary.get("romance", 0)) == -1, "a partner stop gives no romance")
	var stopped_row: Dictionary = (rows.get("rarity", {}) as Dictionary)
	check(float(stopped_row.get("stop_until", 0.0)) > Time.get_unix_time_from_system(),
		"a partner stop writes a future sex cooldown")
	check(ACT_HISTORY.blocks_start(stopped_row), "a partner stop blocks the next start")
	runtime.free()
	main.free()
	game.free()
	context.free()
	impressions.free()
	mods.free()
	if existing != null and is_instance_valid(existing):
		existing.name = "Mods"
