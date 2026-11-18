extends SceneTree
## Pure Context: the typed snapshot, its reasoning payload and answer normalization.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/context/test_context.gd

const CONTEXT := preload("res://mods/unfplap/shared/context.gd")

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
	var empty := CONTEXT.build({})
	check(not empty.willingness and empty.cycle_phase == "normal" and not empty.aftercare,
		"an empty snapshot reads an unwilling, normal, soft-free day")
	check(empty.history_tier == "steady" and empty.history_offer_weight == 0.0,
		"an empty snapshot reads a steady history with no offer weight")

	var facts := CONTEXT.build({
		"willingness": true,
		"history": {
			"tier": "hurt", "hurt": 3, "comfort": 1,
			"blocks_start": false, "blocks_offers": true, "offer_weight": 0.5,
		},
		"cycle_phase": "heat",
		"heat": true,
		"aftercare": true,
		"private": true,
		"public_preference": true,
		"mood": "warm",
		"relation_note": "she trusts him",
		"history_note": "a rough week",
	})
	check(facts.willingness, "willingness is read")
	check(facts.history_tier == "hurt", "the history tier is read")
	check(facts.history_hurt == 3 and facts.history_comfort == 1, "history points are read")
	check(not facts.history_blocks_start and facts.history_blocks_offers,
		"history rows are read")
	check(facts.history_offer_weight == 0.5, "the offer weight is read")
	check(facts.heat and not facts.diestrus, "heat does not imply diestrus")
	check(facts.aftercare and facts.private and facts.public_preference, "soft flags are read")
	check(facts.mood == "warm", "mood is read")
	check(facts.relation_note == "she trusts him", "relation note is read")
	check(facts.history_note == "a rough week", "history note is read")

	var diestrus := CONTEXT.build({"cycle_phase": "diestrus"})
	check(diestrus.diestrus, "the diestrus phase sets the flag")

	var payload := facts.prompt_facts()
	check(payload.get("willing") == true, "the payload carries willingness")
	check(payload.get("private") == true, "the payload carries privacy")
	check(int((payload.get("history", {}) as Dictionary).get("hurt", -1)) == 3,
		"the payload carries history points")
	check(payload.get("cycle") == "heat", "the payload carries the cycle")

	check(CONTEXT.answer("accept") == CONTEXT.ANSWER_ACCEPT, "accept normalizes")
	check(CONTEXT.answer("YES") == CONTEXT.ANSWER_ACCEPT, "yes normalizes to accept")
	check(CONTEXT.answer("counter_offer") == CONTEXT.ANSWER_COUNTER_OFFER,
		"counter-offer normalizes")
	check(CONTEXT.answer("not here") == CONTEXT.ANSWER_COUNTER_OFFER,
		"a not-here reason normalizes to counter-offer")
	check(CONTEXT.answer("refuse") == CONTEXT.ANSWER_REFUSE, "refuse normalizes")
	check(CONTEXT.answer("maybe later") == CONTEXT.ANSWER_REFUSE,
		"an unknown answer is a refusal")

	print("CONTEXT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
