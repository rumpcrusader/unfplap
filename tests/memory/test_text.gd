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
	check(adult == "She saw Anon and Fluttershy together, close and unguarded.",
		"adult sight text is a perception")
	check(TEXT.witness_text("Fluttershy", false, false, 7) == adult, "adult text ignores place and serial")
	check(TEXT.witness_text("Fluttershy", false, true, 0, FACTS.Sense.SOUND)
		== "She heard Anon and Fluttershy together.", "adult sound text is a perception")

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
	check(TEXT.witness_thought("Fluttershy", false, true) == "I saw Anon and Fluttershy together.",
		"adult sight thought is a perception")
	check(TEXT.witness_thought("Fluttershy", false, false, FACTS.Sense.SOUND)
		== "I heard Anon and Fluttershy together.", "adult sound thought is a perception")

	var young: Dictionary = TEXT.witness_impression("Fluttershy", true, true)
	check(young == {"mood": "amused"}, "young impression is mood only")
	check(not young.has("thought"), "young impression carries no explicit thought")
	check(not young.has("romance") and not young.has("friendship"), "young impression carries no score")

	var grown: Dictionary = TEXT.witness_impression("Fluttershy", false, false)
	check(str(grown.get("mood", "")) == "surprised", "adult impression mood")
	check(str(grown.get("thought", "")) == "I saw Anon and Fluttershy together.",
		"adult thought is a neutral perception")
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
	check(TEXT.impression_suffix(FACTS.ImpressionSlot.STAY_CLOSE) == ":stay_close_gain",
		"stay-close impression suffix")
	check(TEXT.impression_suffix(FACTS.ImpressionSlot.FORM_REVEAL) == ":form_reveal",
		"reveal impression suffix")
	check(TEXT.event_suffix(FACTS.ImpressionSlot.ACT) == ":summary", "act event suffix")
	check(TEXT.event_suffix(FACTS.ImpressionSlot.FORM_REVEAL) == ":form_reveal",
		"the reveal keeps its own event id")

	check(TEXT.stay_close_thought(true, true).contains("caressed"),
		"a positive stay-close caress names the caress")
	check(TEXT.stay_close_thought(false, true).contains("cared for"),
		"a positive stay-close without a caress reads as cared for")
	check(TEXT.stay_close_thought(false, false).contains("hurt"),
		"a bad stay-close reads as a repair beat")

	check(TEXT.stop_name(FACTS.StopReason.WITHDREW) == "withdrew", "withdrew stop name")
	check(TEXT.stop_text(FACTS.StopReason.WITHDREW).contains("did not like"),
		"withdrew stop wording")
	check(TEXT.stop_text(FACTS.StopReason.UNWILLING).contains("did not want to keep going"),
		"unwilling stop wording")

	check(TEXT.reaction_name(FACTS.Reaction.CLIMAX) == "climax", "climax reaction name")
	check(TEXT.reaction_name(FACTS.Reaction.HISTORY_REMINDER) == "history_reminder",
		"history reminder reaction name")
	check(TEXT.reaction_name(FACTS.Reaction.TOLERANCE_WARNING) == "tolerance_warning",
		"tolerance warning reaction name")
	check(TEXT.reaction_name(FACTS.Reaction.FORM_OFFER) == "form_offer",
		"form offer reaction name")

	# The typed boundary rows keep their keys and a whitespace hit is not a found memory.
	var hit := FACTS.MemoryHit.new()
	check(not hit.found(), "an empty memory hit is not found")
	hit.text = "  "
	check(not hit.found(), "a whitespace memory hit is not found")
	hit.text = "We talked about the garden."
	check(hit.found(), "a real memory hit is found")
	check(FACTS.Witness.new().to_dict().has("distance"),
		"a witness row carries its distance")
	var cue_row: Dictionary = FACTS.CueFacts.new().to_dict()
	check(cue_row.has_all(["friendship", "love", "stage", "anger", "mood",
		"first_time", "careful"]), "the cue facts dictionary carries its keys")

	print("MEMORY_TEXT_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("MEMORY_TEXT_PASS")
	quit(0 if failures == 0 else 1)
