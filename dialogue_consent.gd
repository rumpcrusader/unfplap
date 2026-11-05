extends Node
## Lover-bond dialogue. Every player line that receives a pony reply is classified by the
## shared classifier: a clear agreement grants the mod-owned lover bond, a clear refusal does
## nothing, and a clear withdrawal ends it. This controller never starts an act; the act gate
## still checks runtime._relationship_ok() and the normal act gates.

const CONSENT := preload("res://mods/unfplap/consent_classifier.gd")
const PENDING_AGE_S := 20.0

var main

var _director: Node
var _pending: Dictionary = {}
var _serial := 0


func _ready() -> void:
	set_process(true)


func reset() -> void:
	_disconnect_director()
	_pending = {}
	_serial = 0


func _process(_delta: float) -> void:
	_ensure_director()


func clear_all() -> void:
	_pending = {}
	_serial += 1


func _ensure_director() -> void:
	if is_instance_valid(_director):
		return
	if not is_inside_tree():
		return
	_director = get_tree().get_first_node_in_group("conversation_director")
	if not is_instance_valid(_director):
		return
	if _director.has_signal("transcript") and not _director.transcript.is_connected(_on_transcript):
		_director.transcript.connect(_on_transcript)
	if _director.has_signal("reply") and not _director.reply.is_connected(_on_reply):
		_director.reply.connect(_on_reply)


func _disconnect_director() -> void:
	if not is_instance_valid(_director):
		_director = null
		return
	if _director.has_signal("transcript") and _director.transcript.is_connected(_on_transcript):
		_director.transcript.disconnect(_on_transcript)
	if _director.has_signal("reply") and _director.reply.is_connected(_on_reply):
		_director.reply.disconnect(_on_reply)
	_director = null


func _on_transcript(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return
	if is_instance_valid(main) and is_instance_valid(main.get("active_runtime")):
		return
	_serial += 1
	_pending = {"text": text, "serial": _serial, "at": Time.get_ticks_msec() * 0.001,
		"consumed": false}


func _on_reply(id: String, text: String) -> void:
	if is_instance_valid(main) and is_instance_valid(main.get("active_runtime")):
		_pending = {}
		return
	if _pending.is_empty() or bool(_pending.get("consumed", false)):
		return
	if id.is_empty() or text.strip_edges().is_empty():
		return
	if Time.get_ticks_msec() * 0.001 - float(_pending.get("at", 0.0)) > PENDING_AGE_S:
		_pending = {}
		return
	_pending["consumed"] = true
	var request := str(_pending.get("text", ""))
	var serial := int(_pending.get("serial", -1))
	var classifier: Variant = main.get("classifier") if is_instance_valid(main) else null
	if is_instance_valid(classifier) and classifier.has_method("classify_lover"):
		var key := "dialogue:%d" % serial
		var started: bool = bool(classifier.call("classify_lover", request, text, key,
			Callable(self, "_on_lover_result").bind(id, request, text, serial)))
		if started:
			_debug("lover dialogue request=\"%s\" reply=\"%s\"" % [
				request.left(120), text.left(120)])
			return
	var local := CONSENT.local_lover_intent(request, text)
	_debug("lover dialogue request=\"%s\" reply=\"%s\" result=%s source=local" % [
		request.left(120), text.left(120), local])
	_apply_result(local, "local", id, text, serial)


func _on_lover_result(intent: String, detail: String, id: String, request: String,
		reply: String, serial: int) -> void:
	if serial != _serial:
		return
	var source := "llm"
	if intent == "unclear" and not detail.is_empty():
		intent = CONSENT.local_lover_intent(request, reply)
		source = "local"
	_debug("lover dialogue request=\"%s\" reply=\"%s\" result=%s detail=%s source=%s" % [
		request.left(120), reply.left(120), intent, detail, source])
	_apply_result(intent, source, id, reply, serial)


func _apply_result(intent: String, source: String, id: String, reply: String, serial: int) -> void:
	if serial != _serial:
		return
	match intent:
		"lover_accept":
			_grant(id, reply)
		"lover_end":
			_end(id, reply)
		"lover_decline":
			_debug("lover offer declined %s" % id)
		_:
			_debug("lover dialogue no change %s result=%s source=%s" % [id, intent, source])


func _grant(id: String, reply: String) -> void:
	var runtime := _runtime(id)
	if not is_instance_valid(runtime) or not runtime.has_method("grant_sex_bond"):
		return
	var granted: bool = bool(runtime.call("grant_sex_bond", "dialogue", reply))
	_debug("lover bond dialogue %s granted=%s" % [id, str(granted)])


func _end(id: String, reply: String) -> void:
	var runtime := _runtime(id)
	if not is_instance_valid(runtime) or not runtime.has_method("end_sex_bond"):
		return
	var ended: bool = bool(runtime.call("end_sex_bond", "dialogue", reply))
	_debug("lover bond dialogue %s ended=%s" % [id, str(ended)])


func _runtime(id: String) -> Node:
	if id.is_empty() or not is_instance_valid(main):
		return null
	var pony := _pony(id)
	if not is_instance_valid(pony):
		return null
	if not main.has_method("runtime_for"):
		return null
	var runtime: Variant = main.call("runtime_for", pony)
	if is_instance_valid(runtime):
		return runtime
	return null


func _pony(id: String) -> Node3D:
	if id.is_empty() or not is_instance_valid(main):
		return null
	var game: Variant = main.get("game")
	if not is_instance_valid(game):
		return null
	var list: Variant = game.get("mares")
	if not list is Array:
		return null
	for node: Variant in list:
		if is_instance_valid(node) and node is Node3D and _pony_id(node) == id:
			return node as Node3D
	return null


func _pony_id(pony: Node) -> String:
	if not is_instance_valid(pony):
		return ""
	var id := str(pony.get_meta("relationship_id", ""))
	if id.is_empty():
		var identity: Variant = pony.get("identity")
		if identity != null:
			id = str(identity.get("id"))
	return id


func _debug(text: String) -> void:
	if is_instance_valid(main) and main.has_method("debug"):
		main.call("debug", text)
