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
	var runtimes: Dictionary = {}

	func runtime_for(pony: Node) -> Node:
		var runtime: Variant = runtimes.get(pony)
		return runtime if is_instance_valid(runtime) else null


class FakeGame extends Node:
	var mares: Array = []
	var world_context: Node


class FakeWorldContext extends Node:
	var keys: Array[String] = []

	func record(_kind: String, _text: String, _ids: Array, _witnesses: Array, key: String) -> void:
		keys.append(key)


class FakeRuntime extends Node:
	var presented := false
	var phase := "normal"

	func present_standing() -> bool:
		presented = true
		return true

	func cycle_phase() -> String:
		return phase


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	check(INIT.cooldown_ready(1000.0, 399.0), "cooldown is over at ten minutes")
	check(not INIT.cooldown_ready(1000.0, 401.0), "cooldown blocks inside ten minutes")
	check(INIT.cooldown_ready(1000.0, 949.0, 50.0), "cooldown accepts an explicit duration")
	check(not INIT.cooldown_ready(1000.0, 951.0, 50.0), "explicit cooldown still blocks")
	check(INIT.heat_cooldown(600.0) == 150.0, "heat cuts the offer cooldown to a quarter")

	var weighted := [
		{"id": "a", "weight": 0.7},
		{"id": "b", "weight": 0.3},
	]
	check(str(INIT.weighted_pick(weighted, 0.0).get("id", "")) == "a",
		"a low roll picks the first weighted candidate")
	check(str(INIT.weighted_pick(weighted, 0.8).get("id", "")) == "b",
		"a high roll picks the second weighted candidate")
	check(INIT.weighted_pick([{"id": "a", "weight": 0.0}], 0.5).is_empty(),
		"zero total weight picks nothing")

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
	fake_main.runtimes[target] = fake_runtime
	fake_game.mares = [target, other]
	fake_runtime.phase = "heat"
	check(initiation._private_at_player(target), "heat overrides the privacy reserve")
	initiation._episode = {"runtime": fake_runtime}
	check(initiation._heat_ask_line().contains("in heat"), "heat adds an ask line")
	fake_runtime.phase = "normal"
	check(not initiation._private_at_player(target), "normal phase restores the privacy reserve")
	check(initiation._heat_ask_line().is_empty(), "normal phase has no heat ask line")
	fake_game.mares = [target]
	initiation._episode = {
		"serial": 7, "pony": target, "runtime": fake_runtime, "id": "rarity",
		"pose": "standing", "source": "", "bed": null, "private": true, "cuddle": false,
		"phase": "ask", "ask_started": 0.0, "keys": [],
	}
	initiation._serial = 7
	var standing_ask := str(initiation._ask_purpose())
	check(standing_ask.contains("Ask clearly enough"), "a private ask is clear, not scripted")
	check(not standing_ask.contains("directly and unmistakably"),
		"a private ask is not forced into a blunt demand")
	initiation._on_player_transcript("yes")
	check(fake_runtime.presented, "a private yes presents")
	check(str(initiation._episode.get("phase", "")) == "present",
		"a private yes moves to present")
	check(context.keys.size() == 1, "an accepted situation is recorded")

	fake_runtime.presented = false
	initiation._episode = {
		"serial": 8, "pony": target, "runtime": fake_runtime, "id": "rarity",
		"pose": "standing", "source": "", "bed": null, "private": true, "cuddle": false,
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
	check(CONSENT.local_lover_intent("will you be my lover?", "yes, I'd like that") == "lover_accept",
		"clear lover agreement is accepted locally")
	check(CONSENT.local_lover_intent("will you be my lover?", "not yet") == "lover_decline",
		"clear lover refusal is declined locally")
	check(CONSENT.local_lover_intent("will you be my lover?", "maybe") == "unclear",
		"an unclear lover answer is unclear")
	check(CONSENT.local_lover_intent("hello there", "yes") == "other",
		"an ordinary line is not a lover proposal")
	check(CONSENT.local_lover_intent("I don't want to be your lover anymore", "I understand") == "lover_end",
		"a clear withdrawal ends the bond")
	check(CONSENT.local_lover_intent("hello there", "I don't want to be your lover anymore") == "lover_end",
		"her own withdrawal ends the bond")
	check(CONSENT.parse_lover_reply('{"intent":"lover_accept"}', "") == "lover_accept",
		"strict lover accept reply")
	check(CONSENT.parse_lover_reply('{"intent":"lover_end"}', "") == "lover_end",
		"strict lover end reply")
	check(CONSENT.parse_lover_reply('{"intent":"maybe"}', "") == "unclear",
		"unknown lover intent is unclear")
	check(INIT.pick_offer_pose(true, true, 0.1) == "missionary", "bed wins the low coin flip")
	check(INIT.pick_offer_pose(true, true, 0.9) == "standing", "standing wins the high coin flip")
	check(INIT.pick_offer_pose(true, false, 0.9) == "missionary", "bed is used when standing is unavailable")
	check(INIT.pick_offer_pose(false, true, 0.1) == "standing", "standing is used when no bed is available")
	check(INIT.pick_offer_pose(false, false, 0.5) == "", "no pose when neither offer fits")

	check(INIT.next_prompt_time(0) == 12.0, "first reminder at twelve seconds")
	check(INIT.next_prompt_time(1) == 24.0, "second reminder at twenty-four seconds")
	check(INIT.next_prompt_time(2) < 0.0, "no third reminder")

	print("INITIATION_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("INITIATION_PASS")
	quit(0 if failures == 0 else 1)
