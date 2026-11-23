extends Node
## The one conversation-director bridge and model host for the negotiation routes; no service
## reads the director directly.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const PROMPTS := preload("res://mods/unfplap/negotiation/prompts.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## The classifier node the service owns, or null. The file is not this service's to import.
var classifier_source := Callable()
## The director's player-line fields when the watch began, and the newest line seen since: an old
## line left there is not the answer to this offer.
var _baseline_text := ""
var _baseline_held := ""
var _last_text := ""
var _seen := false
## The one live answer watch: `{scope, done, pony}`. Empty when nothing is waiting.
var _watch: Dictionary = {}
## The Anon-offer watch: his first new line while he addresses a mare, held until the director
## falls idle so her own reply cannot be mistaken for his.
var _offer_watch := Callable()
var _offer_pending := ""
## The idle offer watch reads the director at 10 Hz, not per frame; the transcript signal still
## clears the wait immediately.
var _offer_clock := 0.0


## The director exists once this node is in the world, so the transcript hook is taken here.
func _ready() -> void:
	hook()


func _exit_tree() -> void:
	unhook()
	_watch = {}
	_offer_watch = Callable()
	_offer_pending = ""


func _process(delta: float) -> void:
	if _offer_watch.is_valid():
		_offer_clock += delta
		if _offer_clock >= 0.1:
			_offer_clock = 0.0
			_poll_offer_watch()
	if _watch.is_empty():
		return
	if not player_reacted():
		return
	var text := last_player_text()
	if text.is_empty():
		return
	var watch := _watch
	_watch = {}
	var done: Callable = watch.get("done", Callable())
	if done.is_valid():
		done.call(text, "")


func director() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("conversation_director")


func hook() -> void:
	var node := director()
	if node == null or not node.has_signal("transcript"):
		return
	if not node.transcript.is_connected(_relay_transcript):
		node.transcript.connect(_relay_transcript)


func unhook() -> void:
	var node := director()
	if node == null or not node.has_signal("transcript"):
		return
	if node.transcript.is_connected(_relay_transcript):
		node.transcript.disconnect(_relay_transcript)


func _relay_transcript(text: String) -> void:
	_last_text = text.strip_edges()
	_seen = true


func idle() -> bool:
	var node := director()
	return node != null and str(node.get("state")) == "idle"


## The scan's quiet gate: not paused, no menu, captured input, a free player, an idle director with
## no group exchange or hearing, AI allowed and no recent chat. `chat_gap_s` is the pacing window.
func quiet(chat_gap_s: float) -> bool:
	return quiet_reason(chat_gap_s) == ""


## Why the automatic scan may not begin now, or "" when it may. The strings are the debug log's
## stable reason names and follow the same order as the gate itself.
func quiet_reason(chat_gap_s: float) -> String:
	if not is_inside_tree():
		return "unavailable"
	if get_tree().paused:
		return "paused"
	if DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return "mouse"
	if WORLD.menu_panel_open():
		return "menu"
	var player: Variant = WORLD.player_rig()
	if not is_instance_valid(player):
		return "no_player"
	if player.get("controls_locked") == true:
		return "controls"
	if player.get("flying") == true:
		return "flying"
	if bool(player.get_meta("knocked_down", false)):
		return "knocked"
	var node := director()
	if node == null:
		return "director_missing"
	if not node.has_method("begin_player_greeting"):
		return "director_api"
	if str(node.get("state")) != "idle":
		return "director_state"
	var approaches: Variant = node.get("player_approaches")
	if approaches != null and approaches.has_method("active") \
			and WORLD.director().subsystem_active(approaches):
		return "approach"
	var group: Variant = node.get("group")
	if group != null and group.has_method("active") \
			and WORLD.director().subsystem_active(group):
		return "group"
	var speech: Variant = node.get("speech")
	if speech != null and is_instance_valid(speech) and str(speech.get("state")) == "hearing":
		return "hearing"
	var config: Variant = node.get("config")
	if config != null and not WORLD.director().background_allowed(config):
		return "ai_usage"
	var now := WORLD.director().clock()
	var characters: Variant = node.get("characters")
	if characters is Dictionary:
		for entry: Variant in (characters as Dictionary).values():
			if entry is Dictionary \
					and now - float((entry as Dictionary).get("chat_last", -1e9)) < chat_gap_s:
				return "chat"
	return ""


## Reset the turn baseline when an answer watch starts: the fallback queue path leaves an old line
## in place, so a stale line must not pass as the answer.
func begin_turn() -> void:
	_baseline_text = ""
	_baseline_held = ""
	_last_text = ""
	_seen = false
	var node := director()
	if node == null:
		return
	_baseline_text = str(node.get("_player_text")).strip_edges()
	_baseline_held = str(node.get("_held_text")).strip_edges()


## True once a new player line has arrived: the transcript signal, or a changed director field
## since the turn baseline. The old polling fields alone are not an answer.
func player_reacted() -> bool:
	if _seen:
		return true
	return not _changed_text().is_empty() or not _changed_held().is_empty()


func last_player_text() -> String:
	if not _last_text.is_empty():
		return _last_text
	var changed := _changed_text()
	if not changed.is_empty():
		return changed
	return _changed_held()


func _changed_text() -> String:
	var node := director()
	if node == null:
		return ""
	var text := str(node.get("_player_text")).strip_edges()
	return "" if text == _baseline_text else text


func _changed_held() -> String:
	var node := director()
	if node == null:
		return ""
	var text := str(node.get("_held_text")).strip_edges()
	return "" if text == _baseline_held else text


func player_name() -> String:
	var node := director()
	if node == null:
		return "Anon"
	var config: Variant = node.get("config")
	if config == null:
		return "Anon"
	return str(config.get_value("player_name", "Anon"))


func pony_speaking(pony: Node) -> bool:
	return WORLD.pony(pony).speaking()


func begin_greeting(id: String, context: String) -> bool:
	return WORLD.director().lines().greet(id, context)


## Queue one authored line with a validity callback. False when the director is missing or the
## queue refuses it.
func queue(id: String, purpose: String, key: String, valid: Callable, priority: bool) -> bool:
	return WORLD.director().lines().queue(id, purpose, key, valid, priority)


func cancel_keys(keys: Array) -> void:
	var lines := WORLD.director().lines()
	for key: Variant in keys:
		lines.cancel(str(key))


## Record a situation event for the director's world context: `ids` is the subject list and `key`
## the replaceable event key.
func record_situation(text: String, ids: Array, key: String) -> void:
	if not is_instance_valid(WORLD.world_root()):
		return
	var subjects: Array[String] = []
	subjects.assign(ids)
	WORLD.director().record_situation(text, subjects, key)


# --------------------------------------------------------------------------- model calls

## The Anon dialogue classifier: one typed request in, one parsed reply out.
func classify(request: PROMPTS.Request, scope: String, done: Callable) -> bool:
	return _complete(request, scope, done)


## The Mare Response Reasoning: the same bounded call with a different instruction.
func reason(request: PROMPTS.Request, scope: String, done: Callable) -> bool:
	return _complete(request, scope, done)


## One raw bounded completion. The caller owns the schema and parses the reply; this is the path
## the Proactive service's Mare Initiation Reasoning uses.
func complete_raw(system: String, payload: Dictionary, scope: String, done: Callable) -> bool:
	var classifier := _classifier()
	if not is_instance_valid(classifier) or not classifier.has_method("complete_raw"):
		return false
	return classifier.complete_raw(system, payload, scope, done)


## Watch the first new player line for an Anon offer; the service arms it only while nothing is
## negotiating or acting.
func watch_player(callback: Callable) -> void:
	if not callback.is_valid():
		return
	if _offer_watch.is_valid():
		_offer_watch = callback
		return
	_offer_watch = callback
	_offer_pending = ""
	begin_turn()


## Stop the global Anon-offer watch without touching an answer watch.
func unwatch_player() -> void:
	_offer_watch = Callable()
	_offer_pending = ""


func _poll_offer_watch() -> void:
	if player_reacted():
		var text := last_player_text()
		if not text.is_empty():
			begin_turn()
			_offer_pending = text
	if _offer_pending.is_empty() or not idle():
		return
	var text := _offer_pending
	_offer_pending = ""
	if _offer_watch.is_valid():
		_offer_watch.call(text)


## Watch the target's next spoken line; the turn baseline is this node's job, not the caller's.
func await_answer(pony: Node, scope: String, done: Callable) -> bool:
	if not is_instance_valid(pony) or scope.is_empty() or not done.is_valid():
		return false
	begin_turn()
	_watch = {"scope": scope, "done": done, "pony": pony}
	return true


## Cancel one classifier scope and any answer watch that belongs to it.
func cancel_scope(scope: String) -> void:
	if scope.is_empty():
		return
	if not _watch.is_empty() and str(_watch.get("scope", "")) == scope:
		_watch = {}
	var classifier := _classifier()
	if is_instance_valid(classifier):
		classifier.cancel_scope(scope)


func _complete(request: PROMPTS.Request, scope: String, done: Callable) -> bool:
	if request == null or not done.is_valid() or scope.is_empty():
		return false
	var system := PROMPTS.system_for(request.kind)
	if system.is_empty():
		LOG.debug("classifier skip kind=%s reason=unknown_kind", [request.kind])
		return false
	var payload := PROMPTS.payload_for(request)
	var count := request.options.size()
	LOG.debug("classifier start kind=%s scope=%s options=%d text_len=%d", [
		request.kind, scope, count, request.text.length()])
	return complete_raw(system, payload, scope,
		func(reply: String, error: String) -> void:
			var parsed := PROMPTS.parse(request.kind, reply, error, count)
			LOG.debug("classifier result kind=%s scope=%s answer=%s option=%d failed=%s out_of_range=%s reply=%s error=%s", [
				request.kind, scope, parsed.answer, parsed.option_index, str(parsed.failed),
				str(parsed.out_of_range), _reply_text(reply), error])
			done.call(parsed))




func _reply_text(reply: String) -> String:
	var text := reply.strip_edges()
	return text if text.length() <= 512 else text.left(512) + "..."


func _classifier() -> Node:
	if not classifier_source.is_valid():
		return null
	var classifier: Variant = classifier_source.call()
	return classifier as Node if is_instance_valid(classifier) else null
