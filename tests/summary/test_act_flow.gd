extends "res://mods/unfplap/tests/support/suite.gd"
## Act-history wiring that can be checked without a live world: the summary scores a hand-built
## snapshot, commits one history row, her impression and the peak, and the afterglow HUD carries
## the act's verdict.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/summary/test_act_flow.gd

const WORLD := preload("res://mods/unfplap/world/api.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const HANDLES := preload("res://mods/unfplap/world/handles.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const SUMMARY := preload("res://mods/unfplap/summary/api.gd")
const ACT_METER := preload("res://mods/unfplap/shared/act_meter.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const MEMORY := preload("res://mods/unfplap/memory/api.gd")
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


class FakeMemory extends MEMORY:
	var impressions: Array = []
	var peaks: Array = []

	func commit(impression: MEMORY.Impression) -> void:
		impressions.append(impression)
		# The real service keeps the game-facing writes, so the suite sees the impression and event.
		super.commit(impression)

	func record_peak(peak: MEMORY.Peak) -> void:
		peaks.append(peak)


class FakeMain extends Node:
	var game: Node
	var memory


func _hud_view(runtime: Node) -> RefCounted:
	runtime.act.refresh_view()
	runtime.act.sync_hud()
	return runtime.act.facts()


## One act's snapshot with a clean outcome; the ending is the route's. Every value the scorer and
## the peak read is set, so a check that changes one names exactly what it changes.
func _snapshot(ending: SUMMARY.ActSnapshot.Ending) -> SUMMARY.ActSnapshot:
	var out := SUMMARY.ActSnapshot.new("rarity", "intimacy_test", ending)
	out.seconds = 90.0
	out.act_spoken_at = 5.0
	out.preferences = {"intensity": "firm", "pattern": "steady", "talk": [], "touch": [],
		"dislikes": [], "tolerance": "normal"}
	out.form_reveal = false
	out.meter = ACT_METER.new()
	out.meter.thrusts = 10
	out.meter.pony_climaxes = 1
	out.meter.intensity_total = 5
	out.meter.intensity_right = 5
	out.meter.pattern_total = 5
	out.meter.pattern_right = 5
	out.meter.peak_satisfaction = 95.0
	out.meter.both_matches = 6
	out.meter.player_talk = "you are perfect"
	return out


## The same act, cut short: no time and no real thrusts.
func _short_snapshot() -> SUMMARY.ActSnapshot:
	var out := _snapshot(SUMMARY.ActSnapshot.Ending.COMPLETE)
	out.seconds = 1.0
	out.meter.thrusts = 0
	return out


## The verdict the presentation reads, as the act's funnel would have stored it.
func _verdict(outcome: Dictionary) -> SUMMARY.ActScore:
	var out := SUMMARY.ActScore.new()
	out.pony_id = "rarity"
	out.event_id = "intimacy_test"
	out.outcome = outcome
	return out


func run() -> void:
	var good_outcome := {
		"hud": "Great · she felt adored",
		"thought": "He gave me what I needed; I felt wanted.",
		"positive": true, "reward": true, "grade": "great",
	}
	var runtime: Node = RUNTIME.new()
	var body := Node3D.new()
	runtime.add_child(body)
	runtime.pony = body
	root.add_child(runtime)
	runtime.act.preferences = {"intensity": "firm", "pattern": "steady", "talk": ["praise"]}
	runtime.act._set_state(4) # AFTERGLOW
	runtime.act.pose_id = CATALOG.MISSIONARY
	runtime.act.snapshot_settings()
	runtime.act.context.readiness.readout().climaxes = 2
	runtime.act.act_score = _verdict(good_outcome)
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
	runtime.act.act_score = null
	check(HUD_LINES.readiness_line_for(_hud_view(runtime), true).is_empty(),
		"an unscored act shows no summary line")
	runtime.act.act_score = _verdict(good_outcome)
	runtime.act._set_state(2) # ACTIVE
	check(not HUD_LINES.readiness_line_for(_hud_view(runtime), true).is_empty(),
		"active readiness line still works")
	runtime.free()

	# The act's snapshot must carry the meter the pure scorer expects and the route's ending.
	var probe: Node = RUNTIME.new()
	root.add_child(probe)
	var readiness: Variant = probe.act.context.readiness
	readiness._touch_counts = {"smack": 2}
	readiness._touch_dislikes = {"smack": 2}
	readiness._act_talk_dislikes = 1
	readiness._act_player_lines = 0
	readiness._act_thrusts = 5
	readiness._act_intensity_total = 4
	readiness._act_intensity_right = 3
	readiness._act_pattern_total = 3
	readiness._act_pattern_right = 1
	readiness._act_liked_touch = 0
	readiness._act_liked_talk = 0
	probe.act.ended_early = false
	readiness.readout().climaxes = 1
	probe.act._act_seconds = 90.0
	var snapshot: SUMMARY.ActSnapshot = probe.act.view.summary_snapshot(probe.act)
	check(snapshot.meter.thrusts == 5, "snapshot carries real thrusts")
	check(int((snapshot.meter.touch_dislikes as Dictionary).get("smack", 0)) == 2,
		"snapshot carries disliked touch kinds")
	check(snapshot.meter.talk_dislikes == 1, "snapshot carries disliked talk")
	check(snapshot.meter.player_lines == 0, "snapshot carries player lines")
	check(snapshot.meter.pattern_right == 1, "snapshot carries pattern matches")
	check(is_equal_approx(snapshot.seconds, 90.0), "snapshot carries the act seconds")
	check(int(snapshot.ending) == SUMMARY.ActSnapshot.Ending.COMPLETE,
		"an act that ended no way early is complete")
	probe.act.ended_early = true
	check(int(probe.act.view.summary_snapshot(probe.act).ending) == SUMMARY.ActSnapshot.Ending.EARLY,
		"a cancel is the early ending")
	probe.act.ended_early = false
	probe.act.stopped_by_her = true
	check(int(probe.act.view.summary_snapshot(probe.act).ending) == SUMMARY.ActSnapshot.Ending.STOPPED,
		"her stop is the stopped ending")
	probe.free()

	_check_score()
	_check_commit()

	if failures == 0:
		print("ACT_FLOW_PASS")
	finish()


## `score` reads a snapshot and writes nothing: a clean act, a bad act, the two end routes and a
## skipped act, each from a hand-built snapshot.
func _check_score() -> void:
	var summary := SUMMARY.new()
	var good := summary.score(_snapshot(SUMMARY.ActSnapshot.Ending.COMPLETE))
	check(not good.skipped, "a clean act is not skipped")
	check(not good.outcome.is_empty(), "a scored act keeps the scorer's record")
	check(str(good.outcome.get("grade", "")) == "good", "a clean act scores good")
	check(good.pony_id == "rarity" and good.event_id == "intimacy_test",
		"the score keeps the act's identity")
	check(good.meter != null and good.meter.thrusts == 10, "the score keeps the act's meter")

	var bad_snapshot := _snapshot(SUMMARY.ActSnapshot.Ending.COMPLETE)
	bad_snapshot.preferences = {"intensity": "firm", "pattern": "steady", "talk": [],
		"touch": ["caress"], "dislikes": ["smack"], "tolerance": "normal"}
	bad_snapshot.meter.pony_climaxes = 0
	bad_snapshot.meter.touches_liked = 0
	bad_snapshot.meter.touch_dislikes = {"smack": 3}
	bad_snapshot.meter.intensity_right = 0
	bad_snapshot.meter.pattern_right = 0
	var bad := summary.score(bad_snapshot)
	check(str(bad.outcome.get("grade", "")) == "bad", "disliked handling scores bad")
	check(bool(bad.outcome.get("severe", false)), "repeated disliked handling is severe")
	check(int(bad.outcome.get("romance", 0)) == -1, "a bad act gives no romance")

	var short := summary.score(_short_snapshot())
	check(short.skipped, "an act that was too short is skipped")
	check(short.outcome.is_empty(), "a skipped act keeps no record")
	check(short.meter != null and short.meter.thrusts == 0, "the skipped score still carries its meter")

	var early := summary.score(_snapshot(SUMMARY.ActSnapshot.Ending.EARLY))
	check(bool(early.outcome.get("early", false)), "an early end is scored as one")
	check("ended_early" in (early.outcome.get("reasons", []) as Array),
		"the early end is one of its reasons")

	var stopped := summary.score(_snapshot(SUMMARY.ActSnapshot.Ending.STOPPED))
	check(bool(stopped.outcome.get("stopped", false)), "her stop is scored as one")
	check(str(stopped.outcome.get("grade", "")) == "bad", "her stop is a bad act")
	check(bool(stopped.outcome.get("severe", false)), "her stop is severe")
	check(int(stopped.outcome.get("romance", 0)) == -1, "her stop gives no romance")
	summary.free()


## `commit` writes the history row, her impression and the peak once, and nothing at all for a
## skipped act.
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
	WORLD.bind_world(main.game)
	var memory := FakeMemory.new()
	root.add_child(memory)
	main.memory = memory
	var summary := SUMMARY.new()
	summary.wire(memory)

	var good := summary.score(_snapshot(SUMMARY.ActSnapshot.Ending.COMPLETE))
	summary.commit(good, SUMMARY.Exchange.new(10.0, "I know."))
	check(mods.saves >= 1, "the summary is saved to the mod state")
	var section: Dictionary = mods.data.get("unfplap", {})
	var rows: Dictionary = section.get("act_history", {})
	check(rows.has("rarity"), "the history row is written")
	check(int((rows.get("rarity", {}) as Dictionary).get("acts", 0)) == 1,
		"the history row counts the act once")
	check(memory.impressions.size() == 1, "the grade-aware impression is written once")
	if not memory.impressions.is_empty():
		var impression: MEMORY.Impression = memory.impressions[0]
		check(int(impression.romance) == 2, "a good summary gives romance +2")
		check(int(impression.slot) == MEMORY.ImpressionSlot.ACT, "a full act keeps the act slot")
	check(context.events.size() == 1, "the summary relationship event is written once")
	check(memory.peaks.size() == 1, "a clean act records one peak")
	if not memory.peaks.is_empty():
		var peak: MEMORY.Peak = memory.peaks[0]
		check(peak.text.contains("you are perfect") and peak.text.contains("I know."),
			"the peak quotes the act's exchange")
		check(peak.score > 0.0, "the peak keeps its score")

	# The peak keeps only her line spoken after the last player turn.
	var late := summary.score(_snapshot(SUMMARY.ActSnapshot.Ending.COMPLETE))
	summary.commit(late, SUMMARY.Exchange.new(1.0, "Too early to count."))
	if memory.peaks.size() == 2:
		check(not (memory.peaks[1] as MEMORY.Peak).text.contains("Too early"),
			"a line spoken before his turn is not the answer")

	# An early end keeps the early slot; a stop writes the severe bad act.
	summary.commit(summary.score(_snapshot(SUMMARY.ActSnapshot.Ending.EARLY)),
		SUMMARY.Exchange.new(10.0, ""))
	check(memory.impressions.size() == 3, "an early end writes its own impression")
	if memory.impressions.size() == 3:
		check(int((memory.impressions[2] as MEMORY.Impression).slot)
			== MEMORY.ImpressionSlot.ACT_EARLY, "an early end keeps the early slot")
	var stopped := summary.score(_snapshot(SUMMARY.ActSnapshot.Ending.STOPPED))
	summary.commit(stopped, SUMMARY.Exchange.new(10.0, ""))
	check(memory.impressions.size() == 4, "her stop writes its own impression")
	if memory.impressions.size() == 4:
		check(str((memory.impressions[3] as MEMORY.Impression).mood) == "annoyed",
			"her stop writes the stopped mood")
		check(int((memory.impressions[3] as MEMORY.Impression).slot)
			== MEMORY.ImpressionSlot.ACT_EARLY, "her stop keeps the early slot")

	# A skipped act writes nothing at all.
	var written := memory.impressions.size()
	var peaks := memory.peaks.size()
	var saves := mods.saves
	var events := context.events.size()
	var short := summary.score(_short_snapshot())
	summary.commit(short, SUMMARY.Exchange.new(10.0, ""))
	check(memory.impressions.size() == written and memory.peaks.size() == peaks,
		"a skipped act writes no impression and no peak")
	check(mods.saves == saves and context.events.size() == events,
		"a skipped act saves nothing and writes no event")
	check(ACT_HISTORY.blocks_start(rows.get("rarity", {})),
		"her stop blocks the next start")

	summary.free()
	main.free()
	game.free()
	context.free()
	impressions.free()
	mods.free()
	memory.free()
	if existing != null and is_instance_valid(existing):
		existing.name = "Mods"
