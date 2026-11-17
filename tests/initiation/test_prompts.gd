extends SceneTree
## Pure proactive-request wording: the ask context, the ask purpose, the observed-situation text
## and the heat sentence.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/initiation/test_prompts.gd

const PROMPTS := preload("res://mods/unfplap/initiation/prompts.gd")
const FACTS := preload("res://mods/unfplap/initiation/facts.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

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
	var request := FACTS.Request.new()
	request.pose = CATALOG.STANDING
	request.private = true

	# The ask context: observed-situation framing, the standing pose and the private wording.
	var ask := PROMPTS.ask_context(request)
	check(ask.begins_with("[Observed situation, not player speech]"),
		"the ask is framed as an observed situation")
	check(ask.contains("take you from behind"), "the standing ask names the pose")
	check(ask.contains("Ask clearly enough"), "a private ask is clear, not scripted")
	check(not ask.contains("directly and unmistakably"),
		"a private ask is not forced into a blunt demand")
	check(not ask.contains("Other ponies are around"), "a private ask has no crowd hint")
	check(ask.contains("Do not describe your body"), "the ask forbids narration")

	request.private = false
	var public_ask := PROMPTS.ask_context(request)
	check(public_ask.contains("Other ponies are around"), "a public ask hints")
	check(not public_ask.contains("Ask clearly enough"), "a public ask is not direct")

	request.private = true
	request.heat = true
	check(PROMPTS.ask_context(request).contains("in heat"), "heat adds the ask line")
	check(PROMPTS.heat_line(true).contains("in heat"), "the heat line reports heat")
	check(PROMPTS.heat_line(false).is_empty(), "no heat means no heat line")
	request.heat = false
	check(not PROMPTS.ask_context(request).contains("in heat"),
		"a normal ask has no heat line")

	request.cuddle = true
	var cuddle_ask := PROMPTS.ask_context(request)
	check(cuddle_ask.contains("cuddling with Anon"), "a cuddle ask names the cuddle")
	check(cuddle_ask.contains("invite him to have sex in the bed"),
		"a cuddle ask invites him to the bed")
	request.cuddle = false

	request.pose = CATALOG.MISSIONARY
	check(PROMPTS.ask_context(request).contains("invite him to come to bed"),
		"a bed ask invites him to come to bed")

	# The generated-intent purpose carries the relationship and history notes.
	request.relation_note = "You and Anon: friends."
	request.history_note = "You want to make it up to him."
	request.pose = CATALOG.STANDING
	var purpose := PROMPTS.ask_purpose(request)
	check(purpose.contains("You and Anon: friends."), "the ask carries the relationship note")
	check(purpose.contains("You want to make it up to him."), "the ask carries the history note")
	check(purpose.contains("[calm]"), "the ask names the opening face tags")
	check(purpose.contains("question mark"), "the ask ends as a question")
	check(PROMPTS.ask_context(request).contains("You want to make it up to him."),
		"the observed-situation context carries the private history note")

	# World-context situations.
	request.pose = CATALOG.STANDING
	request.private = false
	check(PROMPTS.situation_ask(request).contains("Other ponies are around"),
		"a public situation records the crowd")
	check(not PROMPTS.situation_ask(request).contains("cuddling"),
		"a standing situation is not a cuddle")
	request.cuddle = true
	check(PROMPTS.situation_ask(request).contains("cuddling"), "a cuddle situation says so")

	print("INITIATION_PROMPTS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("INITIATION_PROMPTS_PASS")
	quit(0 if failures == 0 else 1)
