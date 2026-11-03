extends SceneTree
## Pure proactive-request rules: privacy, wording mode, cooldown and prompt schedule.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_initiation.gd

const INIT := preload("res://mods/unfplap/initiation.gd")
const CONSENT := preload("res://mods/unfplap/consent_classifier.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


class FakeMain extends Node:
	var player: Node3D
	var game: Node


class FakeGame extends Node:
	var mares: Array = []
	var world_context: Node


class FakeWorldContext extends Node:
	var keys: Array[String] = []

	func record(_kind: String, _text: String, _ids: Array, _witnesses: Array, key: String) -> void:
		keys.append(key)


class FakeRuntime extends Node:
	var presented := false

	func present_horse() -> bool:
		presented = true
		return true


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

	var fake_main := FakeMain.new()
	var player := Node3D.new()
	var target := Node3D.new()
	root.add_child(player)
	root.add_child(target)
	target.global_position = Vector3(1.0, 0.0, 0.0)
	var fake_game := FakeGame.new()
	fake_game.mares = [target]
	fake_main.player = player
	fake_main.game = fake_game
	var initiation := INIT.new()
	initiation.main = fake_main
	check(initiation._private_at_player(target),
		"the offering mare is not another pony")
	var other := Node3D.new()
	root.add_child(other)
	other.global_position = Vector3(2.0, 0.0, 0.0)
	fake_game.mares = [target, other]
	check(not initiation._private_at_player(target),
		"a third nearby pony blocks private")

	# Consent flow: a local "yes" moves the episode into the presented state; a local "no"
	# closes it without presenting. These avoid the director and the model entirely.
	var context := FakeWorldContext.new()
	fake_game.world_context = context
	fake_game.mares = [target]
	var fake_runtime := FakeRuntime.new()
	initiation._episode = {
		"serial": 7, "pony": target, "runtime": fake_runtime, "id": "rarity",
		"pose": "horse", "source": "", "bed": null, "private": true, "cuddle": false,
		"phase": "ask", "ask_started": 0.0, "keys": [],
	}
	initiation._serial = 7
	initiation._on_player_transcript("yes")
	check(fake_runtime.presented, "a private yes presents")
	check(str(initiation._episode.get("phase", "")) == "present",
		"a private yes moves to present")
	check(context.keys.size() == 1, "an accepted situation is recorded")

	fake_runtime.presented = false
	initiation._episode = {
		"serial": 8, "pony": target, "runtime": fake_runtime, "id": "rarity",
		"pose": "horse", "source": "", "bed": null, "private": true, "cuddle": false,
		"phase": "ask", "ask_started": 0.0, "keys": [],
	}
	initiation._serial = 8
	initiation._on_player_transcript("no")
	check(not fake_runtime.presented, "a private no does not present")
	check(initiation._episode.is_empty(), "a private no ends the offer")

	initiation.free()
	fake_main.free()
	fake_game.free()
	fake_runtime.free()
	context.free()
	player.free()
	target.free()
	other.free()

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
	check(CONSENT.parse_reply('{"intent":"accept"}', "boom") == "unclear", "provider error is unclear")
	check(CONSENT.parse_reply('{"intent":"accept","why":"x"}', "") == "unclear", "extra keys are rejected")
	check(CONSENT.local_dialogue_intent("let's have sex", "yes, now") == "sex_accept",
		"clear dialogue agreement is accepted locally")
	check(CONSENT.local_dialogue_intent("let's have sex", "not now") == "decline",
		"clear dialogue refusal is declined locally")
	check(CONSENT.local_dialogue_intent("hello there", "yes") == "other",
		"an ordinary line is not a sex request")
	check(CONSENT.parse_dialogue_reply('{"intent":"sex_accept"}', "") == "sex_accept",
		"strict dialogue accept reply")
	check(CONSENT.parse_dialogue_reply('{"intent":"maybe"}', "") == "unclear",
		"unknown dialogue intent is unclear")
	check(INIT.y_start_allowed(true, "", ""), "flag on allows any scenario")
	check(INIT.y_start_allowed(false, "bed_side", ""), "bed-side is allowed with flag off")
	check(INIT.y_start_allowed(false, "already_lying", ""), "already-lying is allowed with flag off")
	check(INIT.y_start_allowed(false, "", "request"), "a proactive request is allowed with flag off")
	check(INIT.y_start_allowed(false, "", "dialogue"), "a dialogue agreement is allowed with flag off")
	check(not INIT.y_start_allowed(false, "", ""), "arbitrary standing Y is blocked with flag off")

	check(INIT.next_prompt_time(0) == 12.0, "first reminder at twelve seconds")
	check(INIT.next_prompt_time(1) == 24.0, "second reminder at twenty-four seconds")
	check(INIT.next_prompt_time(2) < 0.0, "no third reminder")

	print("INITIATION_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("INITIATION_PASS")
	quit(0 if failures == 0 else 1)
