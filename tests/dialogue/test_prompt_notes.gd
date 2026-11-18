extends SceneTree
## The pure prompt-note assembly: the warm note, the act/afterglow note, the history and
## relationship lines and the caress/lean reads.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/dialogue/test_prompt_notes.gd

const PROMPTS := preload("res://mods/unfplap/dialogue/prompts.gd")

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
	_check_body()
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
		"relation": "- You and Anon: you are dating."})
	check(warm_relation.contains("after making love") and warm_relation.contains("you are dating"),
		"the warm note appends the relationship line")
	check(not PROMPTS.in_act(STATE_IDLE) and PROMPTS.in_act(STATE_ACTIVE)
		and PROMPTS.in_act(STATE_AFTERGLOW), "the act states are recognised")


func _check_act() -> void:
	for state: int in [STATE_ACTIVE, STATE_CLIMAX]:
		var note := PROMPTS.note({"state": state, "history": "- she is close"})
		check(note.begins_with("- You are having sex with Anon right now."),
			"the act note opens the mid-act note")
		check(note.contains("- she is close"), "the history note rides with the act note")
		check(note.ends_with("- she is close"),
			"a quiet caress/lean read adds no mechanical resting sentence")
	var chest := PROMPTS.note({"state": STATE_ACTIVE, "missionary": true, "caressing": true})
	check(chest.contains("caressing your chest and belly"), "missionary caresses the chest")
	var flank := PROMPTS.note({"state": STATE_ACTIVE, "caressing": true})
	check(flank.contains("caressing your flank"), "standing caresses the flank")
	var lean := PROMPTS.note({"state": STATE_ACTIVE, "leaning": true})
	check(lean.contains("leaning in close, holding you"), "a lean is named")
	var both := PROMPTS.note({"state": STATE_ACTIVE, "leaning": true, "caressing": true})
	check(both.contains("leaning in close against you and caressing"), "a lean and caress share a line")
	var relation := PROMPTS.note({"state": STATE_ACTIVE, "relation": "- You and Anon: you are dating."})
	check(relation.contains("- You and Anon: you are dating."), "the relationship line rides along")
	check(not relation.contains("[stay:"), "an act does not offer the stay action")


func _check_afterglow() -> void:
	var note := PROMPTS.note({"state": STATE_AFTERGLOW})
	check(note.contains("still close with Anon in the afterglow"), "the afterglow note is present")
	check(not note.contains("having sex"), "the afterglow drops the act note")
	check(not note.contains("[stay:"), "the afterglow does not advertise the stay action")
	var beat := PROMPTS.note({"state": STATE_AFTERGLOW, "beat": "She is catching her breath."})
	check(beat.contains("- She is catching her breath."), "the afterglow beat rides along")
	var quiet := PROMPTS.note({"state": STATE_AFTERGLOW, "beat": ""})
	check(not quiet.contains("-  "), "an empty beat adds no stray row")
	var history := PROMPTS.note({"state": STATE_AFTERGLOW, "history": "- a good act"})
	check(not history.contains("- a good act"), "the history note is not recited in afterglow")


## The live body line tells the model which body Anon can see, independently of stale event history.
## It appears only for a pony a body-change source handles.
func _check_body() -> void:
	var borrowed := PROMPTS.note({"state": STATE_IDLE, "form_source": true,
		"form_name": "Luna", "form_borrowed": true})
	check(borrowed.contains("Luna") and borrowed.contains("not your own body"),
		"a borrowed form names the presented body")
	var own := PROMPTS.note({"state": STATE_IDLE, "form_source": true,
		"form_name": "Queen Chrysalis", "form_borrowed": false})
	check(own.contains("your own body") and own.contains("Queen Chrysalis"),
		"the own form says the body is her own")
	check(PROMPTS.note({"state": STATE_IDLE, "form_name": "Luna", "form_borrowed": true}) == "",
		"a pony with no body-change source adds no body line")
	var active := PROMPTS.note({"state": STATE_ACTIVE, "form_source": true,
		"form_name": "Luna", "form_borrowed": true})
	check(active.contains("Luna") and active.contains("having sex"),
		"the body line rides with the act note")
	var afterglow := PROMPTS.note({"state": STATE_AFTERGLOW, "form_source": true,
		"form_name": "Luna", "form_borrowed": true})
	check(afterglow.contains("Luna") and afterglow.contains("afterglow"),
		"the body line rides with the afterglow note")
	var unnamed := PROMPTS.note({"state": STATE_IDLE, "form_source": true,
		"form_name": "", "form_borrowed": true})
	check(unnamed.contains("borrowed shape"), "an unnamed borrowed form still reads as borrowed")
	var history := PROMPTS.note({"state": STATE_IDLE, "form_source": true,
		"form_name": "Luna", "form_borrowed": true, "history": "- a good act"})
	check(history.contains("Luna") and history.contains("- a good act"),
		"the body line keeps the idle history")
