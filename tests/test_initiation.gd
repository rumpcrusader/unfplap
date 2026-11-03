extends SceneTree
## Pure proactive-request rules: privacy, wording mode, cooldown and prompt schedule.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_initiation.gd

const INIT := preload("res://mods/unfplap/initiation.gd")

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
	check(INIT.cooldown_ready(1000.0, 399.0), "cooldown is over at ten minutes")
	check(not INIT.cooldown_ready(1000.0, 401.0), "cooldown blocks inside ten minutes")

	check(INIT.cuddle_private(true, true, false), "indoor cuddle needs house solitude")
	check(not INIT.cuddle_private(true, false, false), "indoor cuddle rejects another pony in the house")
	check(INIT.cuddle_private(false, false, false), "outdoor cuddle needs nobody near")
	check(not INIT.cuddle_private(false, false, true), "outdoor cuddle rejects a nearby pony")
	check(INIT.cuddle_private(false, false, false), "outdoor cuddle ignores house-only state")

	check(INIT.presentation_allowed(true, true), "house solitude allows presentation")
	check(INIT.presentation_allowed(false, false), "no nearby pony allows presentation")
	check(not INIT.presentation_allowed(false, true), "nearby pony blocks presentation without house solitude")

	check(INIT.wording_mode(true) == "free", "private wording is free")
	check(INIT.wording_mode(false) == "indirect", "public wording is indirect")

	check(INIT.next_prompt_time(0) == 12.0, "first reminder at twelve seconds")
	check(INIT.next_prompt_time(1) == 24.0, "second reminder at twenty-four seconds")
	check(INIT.next_prompt_time(2) < 0.0, "no third reminder")

	print("INITIATION_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("INITIATION_PASS")
	quit(0 if failures == 0 else 1)
