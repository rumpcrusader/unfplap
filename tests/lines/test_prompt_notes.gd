extends SceneTree
## The pure prompt-note assembly and the act-lines facade's two forwarders: the warm note, the
## act/afterglow note, the history and relationship lines and the caress/lean reads.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/lines/test_prompt_notes.gd

const PROMPTS := preload("res://mods/unfplap/lines/prompts.gd")
const ACT_LINES := preload("res://mods/unfplap/lines/service.gd")

const STATE_IDLE := 0
const STATE_ACTIVE := 2
const STATE_CLIMAX := 3
const STATE_AFTERGLOW := 4

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
	_check_outside()
	_check_act()
	_check_afterglow()
	check(ACT_LINES.new().lover_prompt_note(true) == "- You and Anon are lovers.",
		"the facade forwards the bonded lover note")
	check(ACT_LINES.new().lover_prompt_note(false) == "- You are not Anon's lover.",
		"the facade forwards the unbonded lover note")
	print("PROMPT_NOTES_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("PROMPT_NOTES_PASS")
	quit(0 if failures == 0 else 1)


func _check_outside() -> void:
	check(PROMPTS.note({"state": STATE_IDLE}) == "", "an idle pony with no history has no note")
	check(PROMPTS.note({"state": STATE_IDLE, "history": "- hurt"}) == "- hurt",
		"outside an act the history note passes through")
	var warm := PROMPTS.note({"state": STATE_IDLE, "warm": true})
	check(warm.contains("after making love with Anon"), "the warm note names the act")
	check(warm.contains("affectionate"), "the warm note asks for the tone")
	check(not warm.to_lower().contains("sex"), "the warm note has no bare sex word")
	var warm_relation := PROMPTS.note({"state": STATE_IDLE, "warm": true,
		"relation": "- You are not Anon's lover."})
	check(warm_relation.contains("after making love") and warm_relation.contains("not Anon's lover"),
		"the warm note appends the relationship line")
	check(not PROMPTS.in_act(STATE_IDLE) and PROMPTS.in_act(STATE_ACTIVE)
		and PROMPTS.in_act(STATE_AFTERGLOW), "the act states are recognised")


func _check_act() -> void:
	for state: int in [STATE_ACTIVE, STATE_CLIMAX]:
		var note := PROMPTS.note({"state": state, "history": "- she is close"})
		check(note.begins_with("- You are in the middle of sex with Anon."),
			"the act note opens the mid-act note")
		check(note.contains("- she is close"), "the history note rides with the act note")
		check(note.ends_with("He is close but not caressing or leaning in right now."),
			"the resting state is named")
	var chest := PROMPTS.note({"state": STATE_ACTIVE, "missionary": true, "caressing": true})
	check(chest.contains("caressing your chest and belly"), "missionary caresses the chest")
	var flank := PROMPTS.note({"state": STATE_ACTIVE, "caressing": true})
	check(flank.contains("caressing your flank"), "standing caresses the flank")
	var lean := PROMPTS.note({"state": STATE_ACTIVE, "leaning": true})
	check(lean.contains("leaning in close, holding you"), "a lean is named")
	var both := PROMPTS.note({"state": STATE_ACTIVE, "leaning": true, "caressing": true})
	check(both.contains("leaning in close against you and caressing"), "a lean and caress share a line")
	var relation := PROMPTS.note({"state": STATE_ACTIVE, "relation": "- You and Anon are lovers."})
	check(relation.contains("- You and Anon are lovers."), "the relationship line rides along")
	check(not relation.contains("[stay:"), "an act does not offer the stay action")


func _check_afterglow() -> void:
	var note := PROMPTS.note({"state": STATE_AFTERGLOW})
	check(note.contains("still in the afterglow with Anon"), "the afterglow note is present")
	check(not note.contains("in the middle of sex"), "the afterglow drops the act note")
	check(note.contains("[stay: 120]"), "the afterglow offers the stay action")
	var beat := PROMPTS.note({"state": STATE_AFTERGLOW, "beat": "She is catching her breath."})
	check(beat.contains("- She is catching her breath."), "the afterglow beat rides along")
	var quiet := PROMPTS.note({"state": STATE_AFTERGLOW, "beat": ""})
	check(not quiet.contains("-  "), "an empty beat adds no stray row")
	var history := PROMPTS.note({"state": STATE_AFTERGLOW, "history": "- a good act"})
	check(not history.contains("- a good act"), "the history note is not recited in afterglow")
