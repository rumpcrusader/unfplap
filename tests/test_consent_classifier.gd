extends SceneTree
## The shared consent classifier: local yes/no parsing and the strict model reply shapes for
## offers and lover proposals. The offer episode flow itself is tested in
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
	check(CONSENT.local_lover_intent("will you be my lover?", "yes, I'd like that") == "lover_accept",
		"clear lover agreement is accepted locally")
	check(CONSENT.local_lover_intent("will you be my lover?", "not yet") == "lover_decline",
		"clear lover refusal is declined locally")
	check(CONSENT.local_lover_intent("will you be my lover?", "maybe") == "unclear",
		"an unclear lover answer is unclear")
	check(CONSENT.local_lover_intent("hello there", "yes") == "other",
		"an ordinary line is not a lover proposal")
	check(CONSENT.local_lover_intent("I don't want to be your lover anymore", "I understand")
		== "lover_end", "a clear withdrawal ends the bond")
	check(CONSENT.local_lover_intent("hello there", "I don't want to be your lover anymore")
		== "lover_end", "her own withdrawal ends the bond")
	check(CONSENT.parse_lover_reply('{"intent":"lover_accept"}', "") == "lover_accept",
		"strict lover accept reply")
	check(CONSENT.parse_lover_reply('{"intent":"lover_end"}', "") == "lover_end",
		"strict lover end reply")
	check(CONSENT.parse_lover_reply('{"intent":"maybe"}', "") == "unclear",
		"unknown lover intent is unclear")

	print("CONSENT_CLASSIFIER_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("CONSENT_CLASSIFIER_PASS")
	quit(0 if failures == 0 else 1)
