extends SceneTree
## The shared consent classifier: local yes/no parsing and the strict model reply shapes for
## offers and gift agreements. The offer episode flow itself is tested in
## `tests/initiation/test_initiation_api.gd`.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_consent_classifier.gd

const CONSENT := preload("res://mods/unfplap/initiation/classifier.gd")

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
	check(CONSENT.local_intent("yes") == "accept", "plain yes accepts")
	check(CONSENT.local_intent("Yes, please.") == "accept", "yes please accepts")
	check(CONSENT.local_intent("I'd love to.") == "accept", "i'd love to accepts")
	check(CONSENT.local_intent("okay") == "accept", "okay accepts")
	check(CONSENT.local_intent("not now") == "decline", "not now declines")
	check(CONSENT.local_intent("not tonight") == "decline", "not tonight declines")
	check(CONSENT.local_intent("maybe") == "unclear", "maybe is not a clear answer")
	check(CONSENT.local_intent("if you want") == "unclear", "hypothetical is not consent")
	check(CONSENT.local_intent("you're beautiful") == "unclear", "a compliment is not consent")

	check(CONSENT.parse_reply('{"intent":"accept"}', "") == "accept", "strict accept reply")
	check(CONSENT.parse_reply('{"intent":"decline"}', "") == "decline", "strict decline reply")
	check(CONSENT.parse_reply('{"intent":"maybe"}', "") == "unclear", "unknown intent is unclear")
	check(CONSENT.parse_reply("yes", "") == "unclear", "non-JSON reply is unclear")
	check(CONSENT.parse_reply('{"intent":"accept"}', "boom") == "unclear",
		"provider error is unclear")
	check(CONSENT.parse_reply('{"intent":"accept","why":"x"}', "") == "unclear",
		"extra keys are rejected")

	print("CONSENT_CLASSIFIER_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("CONSENT_CLASSIFIER_PASS")
	quit(0 if failures == 0 else 1)
