extends SceneTree
## Pure privacy rules: the offer and cuddle formulas with no public override.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/privacy_rules/test_privacy_rules.gd

const PRIVACY := preload("res://mods/unfplap/shared/privacy_rules.gd")

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
	check(PRIVACY.offer_private(true, true), "house solitude allows an offer")
	check(PRIVACY.offer_private(false, false), "nobody near allows an offer")
	check(not PRIVACY.offer_private(false, true), "a nearby pony blocks an offer")
	check(PRIVACY.offer_private(true, false), "house solitude ignores distance")

	check(PRIVACY.cuddle_private(true, true, false), "an indoor cuddle needs house solitude")
	check(not PRIVACY.cuddle_private(true, false, false),
		"an indoor cuddle rejects another pony in the house")
	check(PRIVACY.cuddle_private(false, false, false), "an outdoor cuddle needs nobody near")
	check(not PRIVACY.cuddle_private(false, false, true),
		"an outdoor cuddle rejects a nearby pony")
	check(PRIVACY.cuddle_private(false, false, false),
		"an outdoor cuddle ignores the house state")

	print("PRIVACY_RULES_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
