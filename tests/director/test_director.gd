extends "res://mods/unfplap/tests/support/suite.gd"
## The conversation director: the quiet gate, the ask-line queue, the world-context record, the
## answer watch, the player-line offer watch and the one model transport. No live director or model.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/director/test_director.gd

const WORLD := preload("res://mods/unfplap/world/api.gd")
const DIRECTOR := preload("res://mods/unfplap/director/api.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")



class FakeConfig extends RefCounted:
	var values := {"ai_usage": "full", "player_name": "Anon"}

	func get_value(key: String, fallback: Variant = null) -> Variant:
		return values.get(key, fallback)


class FakeActive extends RefCounted:
	var on := false

	func active() -> bool:
		return on


class FakeSpeech extends RefCounted:
	var state := "idle"


class FakeDirector extends Node:
	signal transcript(text: String)

	var state := "idle"
	var config: Variant = FakeConfig.new()
	var player_approaches: Variant = FakeActive.new()
	var group: Variant = FakeActive.new()
	var speech: Variant = FakeSpeech.new()
	var characters: Dictionary = {}
	var _player_text := ""
	var _held_text := ""
	var greeted: Array = []
	var queued: Array = []

	func _now() -> float:
		return 100.0

	func begin_player_greeting(id: String, context: String) -> bool:
		greeted.append([id, context])
		return true

	func queue_generated_intent(id: String, purpose: String, key: String, _valid: Callable,
			_extra: Callable, priority: bool) -> bool:
		queued.append([id, purpose, key, priority])
		return true


class FakeWorldContext extends Node:
	var rows: Array = []

	func record(kind: String, text: String, ids: Array, audience: Array, key: String) -> void:
		rows.append({"kind": kind, "text": text, "ids": ids, "audience": audience, "key": key})


class FakeGame extends Node:
	var world_context := FakeWorldContext.new()
	var save_menu: Variant = null


class FakePanel extends Node:
	var opened := false


class FakePlayer extends Node3D:
	var controls_locked := false
	var flying := false


class FakeClassifier extends Node:
	var calls: Array = []
	var cancelled: Array = []
	var can_answer := true
	var auto := true
	var reply := ""
	var error := ""

	func available() -> bool:
		return can_answer

	func complete_raw(system: String, payload: Dictionary, key: String, done: Callable) -> bool:
		if not can_answer:
			return false
		calls.append({"system": system, "payload": payload, "key": key})
		if auto:
			done.call(reply, error)
		return true

	func cancel_scope(scope: String) -> void:
		cancelled.append(scope)


class FakeMain extends Node:
	var player: Variant = null
	var game: Variant = null


func _fixture() -> Dictionary:
	var main := FakeMain.new()
	var player := FakePlayer.new()
	var game := FakeGame.new()
	var classifier := FakeClassifier.new()
	main.player = player
	WORLD.bind_player(main.player)
	main.game = game
	WORLD.bind_world(main.game)
	var director := FakeDirector.new()
	director.add_to_group("conversation_director")
	root.add_child(director)
	root.add_child(main)
	main.add_child(player)
	main.add_child(game)
	main.add_child(classifier)
	var service: Node = DIRECTOR.new()
	root.add_child(service)
	service.attach_classifier(classifier)
	return {"main": main, "player": player, "game": game, "classifier": classifier,
		"director": director, "service": service}


func _free(made: Dictionary) -> void:
	(made["game"] as Node).world_context.free()
	for key: String in ["service", "main", "director"]:
		var node: Node = made[key]
		root.remove_child(node)
		node.free()


func run() -> void:
	_check_quiet()
	_check_queue()
	_check_answer()
	_check_offer_watch()
	_check_transport()
	finish()


func _check_quiet() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var main: FakeMain = made["main"]
	var director: FakeDirector = made["director"]
	var player: FakePlayer = made["player"]
	check(service.quiet_reason(45.0) == "", "an idle director with a free player is quiet")
	check(service.quiet(45.0), "the boolean gate follows the reason")
	var menu := FakePanel.new()
	menu.opened = true
	(made["game"] as FakeGame).save_menu = menu
	check(service.quiet_reason(45.0) == "menu", "an open menu is not quiet")
	menu.opened = false
	director.state = "speaking"
	check(service.quiet_reason(45.0) == "director_state", "a speaking director is not quiet")
	director.state = "idle"
	(director.player_approaches as FakeActive).on = true
	check(service.quiet_reason(45.0) == "approach", "an approach is not quiet")
	(director.player_approaches as FakeActive).on = false
	(director.group as FakeActive).on = true
	check(service.quiet_reason(45.0) == "group", "a group exchange is not quiet")
	(director.group as FakeActive).on = false
	(director.speech as FakeSpeech).state = "hearing"
	check(service.quiet_reason(45.0) == "hearing", "hearing is not quiet")
	(director.speech as FakeSpeech).state = "idle"
	(director.config as FakeConfig).values["ai_usage"] = "talk"
	check(service.quiet_reason(45.0) == "ai_usage", "background AI off is not quiet")
	(director.config as FakeConfig).values["ai_usage"] = "full"
	director.characters = {"rarity": {"chat_last": 90.0}}
	check(service.quiet_reason(45.0) == "chat", "recent chat is not quiet")
	check(service.quiet_reason(5.0) == "", "an old chat is quiet again")
	director.characters = {}
	player.controls_locked = true
	check(service.quiet_reason(45.0) == "controls", "locked controls are not quiet")
	player.controls_locked = false
	player.flying = true
	check(service.quiet_reason(45.0) == "flying", "flight is not quiet")
	player.flying = false
	player.set_meta("knocked_down", true)
	check(service.quiet_reason(45.0) == "knocked", "a knockdown is not quiet")
	player.remove_meta("knocked_down")
	main.player = null
	WORLD.bind_player(main.player)
	check(service.quiet_reason(45.0) == "no_player", "a missing player is not quiet")
	check(not service.quiet(45.0), "the boolean gate follows the refusal")
	main.player = player
	WORLD.bind_player(main.player)
	menu.free()
	_free(made)


func _check_queue() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var director: FakeDirector = made["director"]
	var game: FakeGame = made["game"]
	check(service.begin_greeting("rarity", "context"),
		"the greeting is queued through the director")
	check(director.greeted.size() == 1 and director.greeted[0][0] == "rarity",
		"the greeting names the mare")
	var valid := func() -> bool: return true
	check(service.queue("rarity", "purpose", "key", DIRECTOR.Validity.of(valid), true),
		"an authored line is queued")
	check(director.queued.size() == 1 and director.queued[0][2] == "key",
		"the line key reaches the director")
	var ids: Array[String] = ["rarity"]
	service.record_situation("text", ids, "key")
	var rows: Array = (game.world_context as FakeWorldContext).rows
	check(rows.size() == 1 and rows[0]["kind"] == "situation", "the situation is recorded")
	check(rows[0]["key"] == "key" and rows[0]["audience"] == ["rarity"],
		"the situation keeps its key and audience")
	check(service.idle(), "the director reads idle")
	director.state = "speaking"
	check(not service.idle(), "a speaking director is not idle")
	_free(made)


func _check_answer() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var director: FakeDirector = made["director"]
	var got: Array = []
	director._player_text = "an old line"
	check(service.await_answer(root, "negotiation:answer:1",
		DIRECTOR.Reply.of(func(text: String, error: String) -> void:
			got.append([text, error]))), "the answer watch starts")
	check(got.is_empty(), "an old player line is not the answer")
	director._player_text = "yes"
	service._process(0.0)
	check(got.size() == 1 and got[0][0] == "yes" and got[0][1] == "",
		"the first new line is the answer")
	service._process(0.0)
	check(got.size() == 1, "one line answers once")

	got.clear()
	check(service.await_answer(root, "negotiation:answer:2",
		DIRECTOR.Reply.of(func(text: String, error: String) -> void:
			got.append([text, error]))), "a second watch starts")
	director.emit_signal("transcript", " come here ")
	service._process(0.0)
	check(got.size() == 1 and got[0][0] == "come here",
		"the transcript signal answers the watch")

	got.clear()
	check(service.await_answer(root, "negotiation:answer:3",
		DIRECTOR.Reply.of(func(text: String, error: String) -> void:
			got.append([text, error]))), "a third watch starts")
	service.cancel_scope("negotiation:answer:3")
	director._player_text = "later"
	service._process(0.0)
	check(got.is_empty(), "a cancelled scope drops the answer watch")
	var classifier: FakeClassifier = made["classifier"]
	check(classifier.cancelled.has("negotiation:answer:3"),
		"the cancel reaches the classifier too")
	_free(made)


func _check_offer_watch() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var director: FakeDirector = made["director"]
	var got: Array[String] = []
	director._player_text = "an old line"
	service.watch_player(DIRECTOR.Line.of(func(text: String) -> void: got.append(text)))
	check(got.is_empty(), "the offer watch ignores an old line")
	director._player_text = "want to?"
	service._process(0.1)
	check(got == ["want to?"], "the first new line reaches the offer watch")
	director._player_text = "take me to bed"
	service._process(0.1)
	check(got.size() == 2 and got[1] == "take me to bed",
		"a later line reaches the offer watch again")

	# While the director is still speaking her reply, the line waits for idle.
	got.clear()
	director.state = "speaking"
	director._player_text = "come here"
	service._process(0.1)
	check(got.is_empty(), "a spoken reply delays the offer line")
	director.state = "idle"
	service._process(0.1)
	check(got == ["come here"], "the offer line starts once the director is idle")

	# A second line replaces the pending one.
	got.clear()
	director.state = "speaking"
	director._player_text = "first"
	service._process(0.1)
	director._player_text = "second"
	service._process(0.1)
	director.state = "idle"
	service._process(0.1)
	check(got == ["second"], "the newest pending line is the one reported")

	# Unwatching drops a pending line and stops the watch.
	got.clear()
	director.state = "speaking"
	director._player_text = "dropped"
	service._process(0.1)
	service.unwatch_player()
	director.state = "idle"
	service._process(0.1)
	check(got.is_empty(), "unwatching drops the pending offer line")
	director._player_text = "after"
	service._process(0.1)
	check(got.is_empty(), "an unwatched line forms nothing")
	_free(made)


## The model transport: one raw completion on the classifier node, the availability read and the
## scope cancel; no request kind is known here.
func _check_transport() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var classifier: FakeClassifier = made["classifier"]
	var got: Array = []
	check(service.model_available(), "the attached classifier answers the availability read")
	check(service.complete_raw(DIRECTOR.Call.of("system", {"a": 1}, "director:scope:1",
		func(reply: String, error: String) -> void: got.append([reply, error]))),
		"a raw completion is forwarded")
	check(classifier.calls.size() == 1, "one classifier call is made")
	check(classifier.calls[-1]["payload"] == {"a": 1}, "the raw payload reaches the classifier")
	check(str(classifier.calls[-1]["system"]) == "system", "the raw instruction reaches it")
	check(got.size() == 1 and got[0][1] == "", "the completion answers once")
	service.cancel_scope("director:scope:2")
	check(classifier.cancelled.has("director:scope:2"), "the cancel reaches the classifier")
	check(not service.complete_raw(DIRECTOR.Call.of("system", {}, "",
		func(_r, _e) -> void: pass)), "an empty scope is no call")
	classifier.can_answer = false
	check(not service.model_available(), "an unavailable classifier is not available")
	check(not service.complete_raw(DIRECTOR.Call.of("system", {}, "director:scope:3",
		func(_r, _e) -> void: pass)), "an unavailable classifier refuses the call")
	classifier.can_answer = true
	service.on_world(null)
	check(service.model_available(), "a world enters with the transport intact")
	service.on_world_closed()
	check(service.model_available(), "a world close keeps the classifier for the next world")
	service.shutdown()
	check(not service.model_available(), "shutdown drops the classifier")
	_free(made)
