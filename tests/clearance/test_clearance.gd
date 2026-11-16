extends SceneTree
## Pure Base clearance: the three hard rows, their reasons and the shared relationship predicate.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/clearance/test_clearance.gd

const CLEARANCE := preload("res://mods/unfplap/shared/clearance.gd")

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
	var cleared := CLEARANCE.evaluate(true, true, true)
	check(cleared.ok(), "every cleared row passes")
	check(cleared.reason().is_empty(), "a cleared result has no reason")
	check(cleared.reasons_text() == "none", "a cleared result renders none")

	var blocked := CLEARANCE.evaluate(false, false, false)
	check(not blocked.ok(), "a failed row blocks")
	check(blocked.reason() == CLEARANCE.REASON_ELIGIBLE, "eligibility is the first reason")
	check(blocked.reasons.size() == 3, "every failed row is named")
	check(blocked.reasons_text() == "eligibility,relationship,available",
		"the reasons render in row order")

	var one := CLEARANCE.evaluate(true, false, true)
	check(not one.ok() and one.reason() == CLEARANCE.REASON_RELATIONSHIP,
		"only the relationship row fails")
	var occupied := CLEARANCE.evaluate(true, true, false)
	check(not occupied.ok() and occupied.reason() == CLEARANCE.REASON_AVAILABLE,
		"only the availability row fails")

	check(CLEARANCE.relationship_ok(true, true, true, false), "romance and floor pass")
	check(not CLEARANCE.relationship_ok(true, false, true, false), "romance eligibility gates")
	check(not CLEARANCE.relationship_ok(true, true, false, false), "the floor gates")
	check(CLEARANCE.relationship_ok(true, false, false, true), "the override opens both rows")
	check(not CLEARANCE.relationship_ok(false, true, true, true),
		"the override keeps the live relationship")

	check(CLEARANCE.available(false, false, true, false), "a free present mare is available")
	check(not CLEARANCE.available(true, false, true, false), "an act blocks availability")
	check(not CLEARANCE.available(false, true, true, false), "sleep blocks availability")
	check(not CLEARANCE.available(false, false, false, false), "absence blocks availability")
	check(not CLEARANCE.available(false, false, true, true), "Occupied blocks availability")

	print("CLEARANCE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
