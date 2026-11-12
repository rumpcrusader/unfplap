extends Node
## The request system's conversation adapter: the only file that touches the conversation director,
## the consent classifier and the world context. The facade owns the episode and passes plain
## values in. See `docs/initiation.md`.

const AI_CONFIG := preload("res://world/ai/ai_config.gd")
const POLICY := preload("res://mods/unfplap/initiation/policy.gd")

var main: Node
var _on_player_text := Callable()


func bind(main_node: Node, on_player_text: Callable) -> void:
	main = main_node
	_on_player_text = on_player_text


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
	if _on_player_text.is_valid():
		_on_player_text.call(text)


func idle() -> bool:
	var node := director()
	return node != null and str(node.get("state")) == "idle"


## The scan's quiet gate: not paused, no menu, captured input, a free player, an idle director
## with no group exchange or hearing, background AI allowed and no recent chat.
func quiet() -> bool:
	if not is_instance_valid(main) or not is_inside_tree() or get_tree().paused:
		return false
	if DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return false
	if main.call("menu_open"):
		return false
	var player: Variant = main.get("player")
	if not is_instance_valid(player):
		return false
	if player.get("controls_locked") == true or player.get("flying") == true:
		return false
	if bool(player.get_meta("knocked_down", false)):
		return false
	var node := director()
	if node == null or not node.has_method("begin_player_greeting"):
		return false
	if str(node.get("state")) != "idle":
		return false
	var approaches: Variant = node.get("player_approaches")
	if approaches != null and approaches.has_method("active") and bool(approaches.call("active")):
		return false
	var group: Variant = node.get("group")
	if group != null and group.has_method("active") and bool(group.call("active")):
		return false
	var speech: Variant = node.get("speech")
	if speech != null and is_instance_valid(speech) and str(speech.get("state")) == "hearing":
		return false
	var config: Variant = node.get("config")
	if config != null and not AI_CONFIG.background_allowed(config):
		return false
	var now := float(node.call("_now"))
	var characters: Variant = node.get("characters")
	if characters is Dictionary:
		for entry: Variant in (characters as Dictionary).values():
			if entry is Dictionary \
					and now - float((entry as Dictionary).get("chat_last", -1e9)) < POLICY.QUIET_CHAT_GAP_S:
				return false
	return true


## True once the director holds a player line, a held line or a hearing turn.
func player_reacted() -> bool:
	var node := director()
	if node == null:
		return false
	var said: Variant = node.get("_player_text")
	if said != null and str(said) != "":
		return true
	var held: Variant = node.get("_held_text")
	if held != null and str(held) != "":
		return true
	var speech: Variant = node.get("speech")
	return speech != null and is_instance_valid(speech) and str(speech.get("state")) == "hearing"


func last_player_text() -> String:
	var node := director()
	if node == null:
		return ""
	return str(node.get("_player_text")).strip_edges()


func player_name() -> String:
	var node := director()
	if node == null:
		return "Anon"
	var config: Variant = node.get("config")
	if config == null:
		return "Anon"
	return str(config.get_value("player_name", "Anon"))


func pony_speaking(pony: Node) -> bool:
	return is_instance_valid(pony) and pony.has_method("is_speaking") \
		and bool(pony.call("is_speaking"))


func begin_greeting(id: String, context: String) -> bool:
	var node := director()
	if node == null or not node.has_method("begin_player_greeting"):
		return false
	return bool(node.call("begin_player_greeting", id, context))


## Queue one authored line with a validity callback. False when the director is missing or the
## queue refuses it.
func queue(id: String, purpose: String, key: String, valid: Callable, priority: bool) -> bool:
	var node := director()
	if node == null or not node.has_method("queue_generated_intent"):
		return false
	return bool(node.call("queue_generated_intent", id, purpose, key, valid, Callable(), priority))


func cancel_keys(keys: Array) -> void:
	var node := director()
	if node == null or not node.has_method("cancel_authored_line"):
		return
	for key: Variant in keys:
		node.call("cancel_authored_line", str(key))


func classify_offer(text: String, offer: String, key: String, callback: Callable) -> bool:
	var classifier := _classifier()
	if not is_instance_valid(classifier):
		return false
	return bool(classifier.call("classify_offer", text, offer, key, callback))


func cancel_key(key: String) -> void:
	var classifier := _classifier()
	if is_instance_valid(classifier):
		classifier.call("cancel_key", key)


func cancel_scope() -> void:
	var classifier := _classifier()
	if is_instance_valid(classifier):
		classifier.call("cancel_scope", "offer:")


func _classifier() -> Node:
	if not is_instance_valid(main):
		return null
	var classifier: Variant = main.get("classifier")
	return classifier if is_instance_valid(classifier) else null


## Record a situation event for the director's world context: `ids` is the subject list and `key`
## the replaceable event key.
func record_situation(text: String, ids: Array, key: String) -> void:
	if not is_instance_valid(main):
		return
	var game: Variant = main.get("game")
	if not is_instance_valid(game):
		return
	var ctx: Variant = game.get("world_context")
	if not is_instance_valid(ctx):
		return
	ctx.call("record", "situation", text, ids, ids, key)
