extends SceneTree
## Pure memory wording and ids: adults are told what it was, fillies and colts get a perception
## with the place it happened, and impressions never carry an explicit thought for a young
## witness. The director keep-active rule is pure too.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/memory/test_text.gd

const TEXT := preload("res://mods/unfplap/memory/text.gd")
const FACTS := preload("res://mods/unfplap/memory/facts.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	check(TEXT.witness_kind(false) == "witnessed_intimacy", "adult event kind")
	check(TEXT.witness_kind(true) == "witnessed_scene", "young event kind")

	var adult := TEXT.witness_text("Fluttershy", false, true, 0)
	check(adult == "She saw Anon and Fluttershy having sex.", "adult text is unchanged indoors")
	check(TEXT.witness_text("Fluttershy", false, false, 7) == adult, "adult text ignores place and serial")

	for indoors: bool in [true, false]:
		var prefix := TEXT.witness_scene_prefix("Fluttershy", indoors)
		for serial: int in [0, 1, 2, 3]:
			var text := TEXT.witness_text("Fluttershy", true, indoors, serial)
			check(text.begins_with(prefix), "young text starts with the place prefix")
			for word: String in ["sex", "climax", "naked", "bed"]:
				check(not text.to_lower().contains(word), "young text omits '%s'" % word)
	check(TEXT.witness_text("Fluttershy", true, true, 0) != TEXT.witness_text("Fluttershy", true, true, 1),
		"young text varies by act")
	check(TEXT.witness_text("Fluttershy", true, true, 0) == TEXT.witness_text("Fluttershy", true, true, 0),
		"young text is stable for one act")
	check(TEXT.witness_scene_prefix("Fluttershy", true).contains("walked in on"),
		"indoors wording")
	check(TEXT.witness_scene_prefix("Fluttershy", false).contains("out in the open"),
		"outdoors wording")

	check(TEXT.witness_thought("Fluttershy", true, true) == "", "young witness has no thought")
	check(TEXT.witness_thought("Fluttershy", true, false) == "", "young outdoor witness has no thought")
	check(TEXT.witness_thought("Fluttershy", false, true).contains("having sex"),
		"adult indoor thought says what it was")
	check(TEXT.witness_thought("Fluttershy", false, false).contains("having sex"),
		"adult outdoor thought says what it was")

	var young: Dictionary = TEXT.witness_impression("Fluttershy", true, true)
	check(young == {"mood": "amused"}, "young impression is mood only")
	check(not young.has("thought"), "young impression carries no explicit thought")
	check(not young.has("romance") and not young.has("friendship"), "young impression carries no score")

	var grown: Dictionary = TEXT.witness_impression("Fluttershy", false, false)
	check(str(grown.get("mood", "")) == "surprised", "adult impression mood")
	check(str(grown.get("thought", "")) == "I saw Anon and Fluttershy having sex out in the open.",
		"adult outdoors thought")
	check(not grown.has("romance") and not grown.has("friendship"), "adult impression carries no score")

	check(TEXT.key("act", "reply", "climax") == "unfplap:act:reply:climax",
		"director key format")
	check(TEXT.key_prefix("act") == "unfplap:act:", "director key prefix")

	check(TEXT.keep_active(FACTS.LineState.SPEAKING, "line", "line", true),
		"speaking line is kept")
	check(not TEXT.keep_active(FACTS.LineState.GENERATING, "line", "line", true),
		"generating line is dropped")
	check(not TEXT.keep_active(FACTS.LineState.SPEAKING, "other", "line", true),
		"inactive line is dropped")
	check(not TEXT.keep_active(FACTS.LineState.SPEAKING, "line", "line", false),
		"cancel-all drops even speaking")

	check(TEXT.impression_suffix(FACTS.ImpressionSlot.ACT) == ":gain", "act impression suffix")
	check(TEXT.impression_suffix(FACTS.ImpressionSlot.ACT_EARLY) == ":summary",
		"early act impression suffix")
	check(TEXT.impression_suffix(FACTS.ImpressionSlot.REFUSAL) == ":mood",
		"refusal impression suffix")
	check(TEXT.impression_suffix(FACTS.ImpressionSlot.STAY_CLOSE) == ":stay_close_gain",
		"stay-close impression suffix")
	check(TEXT.event_suffix(FACTS.ImpressionSlot.REFUSAL) == "", "refusal event keeps its bare id")
	check(TEXT.event_suffix(FACTS.ImpressionSlot.ACT) == ":summary", "act event suffix")
	check(TEXT.event_kind(FACTS.ImpressionSlot.REFUSAL) == "intimacy", "refusal is an intimacy event")
	check(TEXT.event_kind(FACTS.ImpressionSlot.ACT) == "relationship", "act is a relationship event")

	check(TEXT.stay_close_thought(true, true).contains("caressed"),
		"a positive stay-close caress names the caress")
	check(TEXT.stay_close_thought(false, true).contains("cared for"),
		"a positive stay-close without a caress reads as cared for")
	check(TEXT.stay_close_thought(false, false).contains("hurt"),
		"a bad stay-close reads as a repair beat")

	check(TEXT.refusal_text(false).contains("turned Anon away"), "plain refusal wording")
	check(TEXT.refusal_text(true).contains("bucked"), "buck refusal wording")
	check(TEXT.refusal_thought(false).contains("turned him away"), "plain refusal thought")
	check(TEXT.refusal_thought(true).contains("bucked"), "buck refusal thought")

	check(TEXT.stop_name(FACTS.StopReason.WITHDREW) == "withdrew", "withdrew stop name")
	check(TEXT.stop_text(FACTS.StopReason.WITHDREW).contains("does not like"),
		"withdrew stop wording")
	check(TEXT.stop_text(FACTS.StopReason.UNWILLING).contains("no longer wanted"),
		"unwilling stop wording")

	check(TEXT.reaction_name(FACTS.Reaction.CLIMAX) == "climax", "climax reaction name")
	check(TEXT.reaction_name(FACTS.Reaction.HISTORY_REMINDER) == "history_reminder",
		"history reminder reaction name")
	check(TEXT.reaction_name(FACTS.Reaction.TOLERANCE_WARNING) == "tolerance_warning",
		"tolerance warning reaction name")

	print("MEMORY_TEXT_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("MEMORY_TEXT_PASS")
	quit(0 if failures == 0 else 1)
