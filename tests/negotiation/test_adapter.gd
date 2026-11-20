extends SceneTree
## The negotiation adapter: the one director bridge, the quiet gate, the ask-line queue, the
## world-context record, the answer watch, the model calls and their reply parsing. No live
## director, classifier or model.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/negotiation/test_adapter.gd

const WORLD := preload("res://mods/unfplap/world/service.gd")
const ADAPTER := preload("res://mods/unfplap/negotiation/adapter.gd")
const PROMPTS := preload("res://mods/unfplap/negotiation/prompts.gd")
const CONTEXT := preload("res://mods/unfplap/shared/context.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


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
	var cancelled: Array = []

	func _now() -> float:
		return 100.0

	func begin_player_greeting(id: String, context: String) -> bool:
		greeted.append([id, context])
		return true

	func queue_generated_intent(id: String, purpose: String, key: String, _valid: Callable,
			_extra: Callable, priority: bool) -> bool:
		queued.append([id, purpose, key, priority])
		return true

	func cancel_authored_line(key: String) -> void:
		cancelled.append(key)


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
	var available := true
	var auto := true
	var reply := ""
	var error := ""

	func complete_raw(system: String, payload: Dictionary, key: String, done: Callable) -> bool:
		if not available:
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
	var adapter: Node = ADAPTER.new()
	root.add_child(adapter)
	adapter.classifier_source = func() -> Node: return classifier
	return {"main": main, "player": player, "game": game, "classifier": classifier,
		"director": director, "adapter": adapter}


func _free(made: Dictionary) -> void:
	for key: String in ["adapter", "main", "director"]:
		var node: Node = made[key]
		root.remove_child(node)
		node.free()


func _option(pose: String, source := "", bed: Variant = null) -> POSE_OPTIONS.Option:
	var out := POSE_OPTIONS.Option.new()
	out.pose = pose
	out.source = source
	out.bed = bed
	return out


func run() -> void:
	_check_quiet()
	_check_queue()
	_check_answer()
	_check_offer_watch()
	_check_models()
	print("NEGOTIATION_ADAPTER_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_quiet() -> void:
	var made := _fixture()
	var adapter: Node = made["adapter"]
	var main: FakeMain = made["main"]
	var director: FakeDirector = made["director"]
	var player: FakePlayer = made["player"]
	check(adapter.quiet_reason(45.0) == "", "an idle director with a free player is quiet")
	var menu := FakePanel.new()
	menu.opened = true
	(made["game"] as FakeGame).save_menu = menu
	check(adapter.quiet_reason(45.0) == "menu", "an open menu is not quiet")
	menu.opened = false
	director.state = "speaking"
	check(adapter.quiet_reason(45.0) == "director_state", "a speaking director is not quiet")
	director.state = "idle"
	(director.player_approaches as FakeActive).on = true
	check(adapter.quiet_reason(45.0) == "approach", "an approach is not quiet")
	(director.player_approaches as FakeActive).on = false
	(director.group as FakeActive).on = true
	check(adapter.quiet_reason(45.0) == "group", "a group exchange is not quiet")
	(director.group as FakeActive).on = false
	(director.speech as FakeSpeech).state = "hearing"
	check(adapter.quiet_reason(45.0) == "hearing", "hearing is not quiet")
	(director.speech as FakeSpeech).state = "idle"
	(director.config as FakeConfig).values["ai_usage"] = "talk"
	check(adapter.quiet_reason(45.0) == "ai_usage", "background AI off is not quiet")
	(director.config as FakeConfig).values["ai_usage"] = "full"
	director.characters = {"rarity": {"chat_last": 90.0}}
	check(adapter.quiet_reason(45.0) == "chat", "recent chat is not quiet")
	check(adapter.quiet_reason(5.0) == "", "an old chat is quiet again")
	director.characters = {}
	player.controls_locked = true
	check(adapter.quiet_reason(45.0) == "controls", "locked controls are not quiet")
	player.controls_locked = false
	player.flying = true
	check(adapter.quiet_reason(45.0) == "flying", "flight is not quiet")
	player.flying = false
	player.set_meta("knocked_down", true)
	check(adapter.quiet_reason(45.0) == "knocked", "a knockdown is not quiet")
	player.remove_meta("knocked_down")
	main.player = null
	WORLD.bind_player(main.player)
	check(adapter.quiet_reason(45.0) == "no_player", "a missing player is not quiet")
	check(not adapter.quiet(45.0), "the boolean gate follows the reason")
	main.player = player
	WORLD.bind_player(main.player)
	_free(made)


func _check_queue() -> void:
	var made := _fixture()
	var adapter: Node = made["adapter"]
	var director: FakeDirector = made["director"]
	var game: FakeGame = made["game"]
	check(adapter.begin_greeting("rarity", "context"),
		"the greeting is queued through the director")
	check(director.greeted.size() == 1 and director.greeted[0][0] == "rarity",
		"the greeting names the mare")
	var valid := func() -> bool: return true
	check(adapter.queue("rarity", "purpose", "key", valid, true), "an authored line is queued")
	check(director.queued.size() == 1 and director.queued[0][2] == "key",
		"the line key reaches the director")
	adapter.cancel_keys(["a", "b"])
	check(director.cancelled == ["a", "b"], "the authored keys are cancelled")
	adapter.record_situation("text", ["rarity"], "key")
	var rows: Array = (game.world_context as FakeWorldContext).rows
	check(rows.size() == 1 and rows[0]["kind"] == "situation", "the situation is recorded")
	check(rows[0]["key"] == "key" and rows[0]["audience"] == ["rarity"],
		"the situation keeps its key and audience")
	_free(made)


func _check_answer() -> void:
	var made := _fixture()
	var adapter: Node = made["adapter"]
	var director: FakeDirector = made["director"]
	var got: Array = []
	director._player_text = "an old line"
	check(adapter.await_answer(root, "negotiation:answer:1", func(text: String, error: String) -> void:
		got.append([text, error])), "the answer watch starts")
	check(got.is_empty(), "an old player line is not the answer")
	director._player_text = "yes"
	adapter._process(0.0)
	check(got.size() == 1 and got[0][0] == "yes" and got[0][1] == "",
		"the first new line is the answer")
	adapter._process(0.0)
	check(got.size() == 1, "one line answers once")

	got.clear()
	check(adapter.await_answer(root, "negotiation:answer:2", func(text: String, error: String) -> void:
		got.append([text, error])), "a second watch starts")
	director.emit_signal("transcript", " come here ")
	adapter._process(0.0)
	check(got.size() == 1 and got[0][0] == "come here",
		"the transcript signal answers the watch")

	got.clear()
	check(adapter.await_answer(root, "negotiation:answer:3", func(text: String, error: String) -> void:
		got.append([text, error])), "a third watch starts")
	adapter.cancel_scope("negotiation:answer:3")
	director._player_text = "later"
	adapter._process(0.0)
	check(got.is_empty(), "a cancelled scope drops the answer watch")
	var classifier: FakeClassifier = made["classifier"]
	check(classifier.cancelled.has("negotiation:answer:3"),
		"the cancel reaches the classifier too")
	_free(made)


func _check_offer_watch() -> void:
	var made := _fixture()
	var adapter: Node = made["adapter"]
	var director: FakeDirector = made["director"]
	var got: Array[String] = []
	director._player_text = "an old line"
	adapter.watch_player(func(text: String) -> void: got.append(text))
	check(got.is_empty(), "the offer watch ignores an old line")
	director._player_text = "want to?"
	adapter._process(0.1)
	check(got == ["want to?"], "the first new line reaches the offer watch")
	director._player_text = "take me to bed"
	adapter._process(0.1)
	check(got.size() == 2 and got[1] == "take me to bed",
		"a later line reaches the offer watch again")

	# While the director is still speaking her reply, the line waits for idle.
	got.clear()
	director.state = "speaking"
	director._player_text = "come here"
	adapter._process(0.1)
	check(got.is_empty(), "a spoken reply delays the offer line")
	director.state = "idle"
	adapter._process(0.1)
	check(got == ["come here"], "the offer line starts once the director is idle")

	# A second line replaces the pending one.
	got.clear()
	director.state = "speaking"
	director._player_text = "first"
	adapter._process(0.1)
	director._player_text = "second"
	adapter._process(0.1)
	director.state = "idle"
	adapter._process(0.1)
	check(got == ["second"], "the newest pending line is the one reported")

	# Unwatching drops a pending line and stops the watch.
	got.clear()
	director.state = "speaking"
	director._player_text = "dropped"
	adapter._process(0.1)
	adapter.unwatch_player()
	director.state = "idle"
	adapter._process(0.1)
	check(got.is_empty(), "unwatching drops the pending offer line")
	director._player_text = "after"
	adapter._process(0.1)
	check(got.is_empty(), "an unwatched line forms nothing")
	_free(made)


func _check_models() -> void:
	var made := _fixture()
	var adapter: Node = made["adapter"]
	var classifier: FakeClassifier = made["classifier"]
	var bed := Node3D.new()
	root.add_child(bed)
	var context := CONTEXT.build({"willingness": true})
	var options: Array[POSE_OPTIONS.Option] = [
		_option(CATALOG.MISSIONARY, "bed_side", bed),
		_option(CATALOG.STANDING),
	]
	var request := PROMPTS.Request.new()
	request.kind = "anon_offer"
	request.text = "take me to bed"
	request.context = context
	request.options = options
	var got: Array = []
	classifier.reply = "{\"offer\":true,\"option\":0}"
	check(adapter.classify(request, "negotiation:anon_offer:1", func(reply) -> void:
		got.append(reply)), "the Anon offer classifier runs")
	check(classifier.calls.size() == 1, "one bounded classifier call is made")
	var call: Dictionary = classifier.calls[0]
	check(str(call["system"]).contains("option"), "the Anon offer instruction is used")
	var payload: Dictionary = call["payload"]
	check(str(payload.get("player_line", "")) == "take me to bed",
		"the classifier payload carries the line")
	check((payload.get("options", []) as Array).size() == 2,
		"the classifier payload carries the options")
	check((payload.get("context", {}) as Dictionary).get("willing") == true,
		"the classifier payload carries Context")
	check(got.size() == 1 and got[0].answer == CONTEXT.ANSWER_ACCEPT and got[0].option_index == 0,
		"the reply is parsed into the typed answer")

	got.clear()
	request.kind = "anon_decision"
	request.text = "right here"
	request.line = "come here"
	classifier.reply = "{\"answer\":\"accept\"}"
	check(adapter.classify(request, "negotiation:decision:1", func(reply) -> void:
		got.append(reply)), "the Anon decision classifier runs")
	check(got.size() == 1 and got[0].answer == CONTEXT.ANSWER_ACCEPT,
		"the Anon decision is parsed")
	payload = classifier.calls[-1]["payload"]
	check(str(payload.get("offer", "")) == "come here", "the decision payload carries the offer")

	got.clear()
	request.kind = "mare_response"
	request.text = "want to?"
	request.options = [options[1]]
	classifier.reply = "{\"answer\":\"counter_offer\"}"
	check(adapter.reason(request, "negotiation:response:1", func(reply) -> void:
		got.append(reply)), "the Mare response reasoning runs")
	check(got.size() == 1 and got[0].answer == CONTEXT.ANSWER_COUNTER_OFFER,
		"the Mare response is parsed")
	payload = classifier.calls[-1]["payload"]
	check((payload.get("option", {}) as Dictionary).get("pose") == CATALOG.STANDING,
		"the Mare response payload carries the option")

	got.clear()
	classifier.reply = "not json"
	check(adapter.reason(request, "negotiation:response:2", func(reply) -> void:
		got.append(reply)), "a malformed reply still completes the call")
	check(got.size() == 1 and got[0].failed, "a malformed reply is a failed answer")

	got.clear()
	check(adapter.complete_raw("system", {"a": 1}, "negotiation:reasoning:1",
		func(reply: String, error: String) -> void: got.append([reply, error])),
		"a raw completion is available to the Proactive reasoning")
	check(classifier.calls[-1]["payload"] == {"a": 1}, "the raw payload reaches the classifier")

	classifier.available = false
	check(not adapter.classify(request, "negotiation:response:3", func(_reply) -> void: pass),
		"an unavailable classifier refuses the call")
	classifier.available = true
	var unknown := PROMPTS.Request.new()
	unknown.kind = "nonsense"
	check(not adapter.classify(unknown, "negotiation:nonsense:1", func(_reply) -> void: pass),
		"an unknown request kind is refused")
	check(not adapter.await_answer(null, "negotiation:answer:4", func(_t, _e) -> void: pass),
		"a missing pony is refused")
	root.remove_child(bed)
	bed.free()
	_free(made)
