extends RefCounted
## The live conversation-director reads and the player-line watches; the facade owns the model
## transport and gives this the node whose tree it reads.

const WORLD := preload("res://mods/unfplap/world/api.gd")

## The service node: the tree, the inside-tree test and the scene read's owner.
var owner: Node = null
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


## One engine frame: the idle offer poll, then the answer watch's first new line.
func process(delta: float) -> void:
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
	if not is_instance_valid(owner) or not owner.is_inside_tree():
		return null
	return owner.get_tree().get_first_node_in_group("conversation_director")


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


## A world close or enter: no watch, no pending line and no baseline of the world that is gone.
func reset() -> void:
	_watch = {}
	_offer_watch = Callable()
	_offer_pending = ""
	_offer_clock = 0.0
	_baseline_text = ""
	_baseline_held = ""
	_last_text = ""
	_seen = false


func _relay_transcript(text: String) -> void:
	_last_text = text.strip_edges()
	_seen = true


func idle() -> bool:
	var node := director()
	return node != null and str(node.get("state")) == "idle"


## The scan's quiet gate: not paused, no menu, captured input, a free player, an idle director with
## no group exchange or hearing, AI allowed and no recent chat. `chat_gap_s` is the pacing window.
## The AI check is the game's own background policy, never a mod setting.
func quiet(chat_gap_s: float) -> bool:
	return quiet_reason(chat_gap_s) == ""


## Why the automatic scan may not begin now, or "" when it may. The strings are the debug log's
## stable reason names and follow the same order as the gate itself.
func quiet_reason(chat_gap_s: float) -> String:
	if not is_instance_valid(owner) or not owner.is_inside_tree():
		return "unavailable"
	if owner.get_tree().paused:
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


func begin_greeting(id: String, context: String) -> bool:
	return WORLD.director().lines().greet(id, context)


## Queue one authored line with a validity callback. False when the director is missing or the
## queue refuses it.
func queue(id: String, purpose: String, key: String, valid: Callable, priority: bool) -> bool:
	return WORLD.director().lines().queue(id, purpose, key, valid, priority)


## Record a situation event for the director's world context: `ids` is the subject list and `key`
## the replaceable event key.
func record_situation(text: String, ids: Array[String], key: String) -> void:
	if not is_instance_valid(WORLD.world_root()):
		return
	WORLD.director().record_situation(text, ids, key)


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


## Watch the target's next spoken line; the turn baseline is this bridge's job, not the caller's.
func await_answer(pony: Node, scope: String, done: Callable) -> bool:
	if not is_instance_valid(pony) or scope.is_empty() or not done.is_valid():
		return false
	begin_turn()
	_watch = {"scope": scope, "done": done, "pony": pony}
	return true


## Drop the answer watch that belongs to one scope.
func cancel_watch(scope: String) -> void:
	if not _watch.is_empty() and str(_watch.get("scope", "")) == scope:
		_watch = {}
