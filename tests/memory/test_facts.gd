extends SceneTree
## The typed boundary data: defaults, the cue-facts dictionary, and the memory hit's found flag.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/memory/test_facts.gd

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
	var impression := FACTS.Impression.new()
	check(impression.id == "" and impression.event_id == "", "an impression starts empty")
	check(impression.slot == FACTS.ImpressionSlot.ACT, "an impression defaults to the act slot")
	check(impression.mood == "relaxed", "an impression defaults to relaxed")
	check(impression.romance == 0 and impression.thought == "", "an impression has no romance or thought")
	check(impression.event_text == "", "an impression has no event text")

	var peak := FACTS.Peak.new()
	check(peak.id == "" and peak.score == 0.0, "a peak starts empty")

	var witness := FACTS.Witness.new()
	check(witness.id == "" and witness.young == false, "a witness starts empty")
	check(witness.sense == FACTS.Sense.SIGHT, "a witness defaults to sight")
	check(witness.to_dict().has("distance"), "a witness row carries its distance")

	var observer := FACTS.Observer.new()
	check(observer.id == "" and observer.node == null, "an observer starts empty")

	var facts := FACTS.CueFacts.new()
	check(facts.friendship == "" and facts.friendship_level == -1, "cue facts start empty")
	check(facts.first_time == false and facts.careful == false, "cue facts start false")
	var row := facts.to_dict()
	check(row.has("friendship") and row.has("love") and row.has("stage"), "the cue facts dict carries the ladder")
	check(row.has("anger") and row.has("mood"), "the cue facts dict carries the mood and anger")
	check(row.has("first_time") and row.has("careful"), "the cue facts dict carries the flags")

	var hit := FACTS.MemoryHit.new()
	check(not hit.found(), "an empty memory hit is not found")
	hit.text = "  "
	check(not hit.found(), "a whitespace memory hit is not found")
	hit.text = "We talked about the garden."
	check(hit.found(), "a real memory hit is found")

	var line := FACTS.Line.new()
	check(line.key == "" and not line.queued, "a line starts empty")

	var request := FACTS.LineRequest.new()
	check(request.kind == FACTS.LineKind.REACTION, "a line request defaults to a reaction")
	check(request.reaction == FACTS.Reaction.CLIMAX, "a line request defaults to the climax reaction")
	check(not request.valid.is_valid() and not request.finished.is_valid(), "a line request starts with no callbacks")

	print("MEMORY_FACTS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("MEMORY_FACTS_PASS")
	quit(0 if failures == 0 else 1)
