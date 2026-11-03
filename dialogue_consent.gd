extends Node
## A verbal agreement to sex. Every player line that receives a pony reply is classified by the
## shared classifier; a clear "yes, now, here" leaves a standing offer for that mare until she
## moves or refuses. The Y action still appears only in the smack-flank aim zone.

const CONSENT := preload("res://mods/unfplap/consent_classifier.gd")
const PENDING_AGE_S := 20.0
const MOVE_CLEAR_M := 0.75

var main

var _director: Node
var _pending: Dictionary = {}
var _serial := 0
var _agreements: Dictionary = {}


func _ready() -> void:
	set_process(true)


func reset() -> void:
	_disconnect_director()
	_pending = {}
	_agreements.clear()
	_serial = 0


func _process(_delta: float) -> void:
	_ensure_director()
	_tick_agreements()


func scenario_for(pony: Node) -> String:
	if not is_instance_valid(pony):
		return ""
	var id := _pony_id(pony)
	if id.is_empty() or not _agreements.has(id):
		return ""
	if not _valid_agreement(pony, _agreements[id]):
		_clear(id, "moved")
		return ""
	return "dialogue"


func clear_for(pony: Node) -> void:
	if is_instance_valid(pony):
		_clear(_pony_id(pony), "act")
	_pending = {}
	_serial += 1


func clear_all() -> void:
	_agreements.clear()
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
	if is_instance_valid(classifier) and classifier.has_method("classify_dialogue"):
		var key := "dialogue:%d" % serial
		var started: bool = bool(classifier.call("classify_dialogue", request, text, key,
			Callable(self, "_on_dialogue_result").bind(id, request, text, serial)))
		if started:
			_debug("dialogue consent request=\"%s\" reply=\"%s\"" % [
				request.left(120), text.left(120)])
			return
	var local := CONSENT.local_dialogue_intent(request, text)
	_debug("dialogue consent request=\"%s\" reply=\"%s\" result=%s source=local" % [
		request.left(120), text.left(120), local])
	_apply_result(local, "local", id, request, text, serial)


func _on_dialogue_result(intent: String, detail: String, id: String, request: String,
		reply: String, serial: int) -> void:
	if serial != _serial:
		return
	var source := "llm"
	if intent == "unclear" and not detail.is_empty():
		intent = CONSENT.local_dialogue_intent(request, reply)
		source = "local"
	_debug("dialogue consent request=\"%s\" reply=\"%s\" result=%s detail=%s source=%s" % [
		request.left(120), reply.left(120), intent, detail, source])
	_apply_result(intent, source, id, request, reply, serial)


func _apply_result(intent: String, source: String, id: String, _request: String,
		_reply: String, serial: int) -> void:
	if serial != _serial:
		return
	if intent == "sex_accept":
		_agree(id)
	elif intent == "decline":
		_clear(id, "refused")
	else:
		_debug("dialogue agreement kept %s result=%s source=%s" % [id, intent, source])


func _agree(id: String) -> void:
	var pony := _pony(id)
	if not is_instance_valid(pony):
		return
	var status: Dictionary = pony.call("posture_status") if pony.has_method("posture_status") else {}
	if str(status.get("requested", "")) != "stand":
		return
	_agreements[id] = {
		"position": pony.global_position,
		"region": _region_of(pony.global_position),
		"posture": str(status.get("requested", "")),
	}
	_debug("dialogue agreement %s pos=%s region=%s" % [
		id, str(pony.global_position), str(_agreements[id].get("region", ""))])


func _tick_agreements() -> void:
	if _agreements.is_empty():
		return
	for id: String in _agreements.keys():
		var pony := _pony(id)
		if not is_instance_valid(pony):
			_clear(id, "gone")
			continue
		if not _valid_agreement(pony, _agreements[id]):
			_clear(id, "moved")


func _valid_agreement(pony: Node3D, row: Dictionary) -> bool:
	if not is_instance_valid(pony):
		return false
	if pony.global_position.distance_to(row.get("position", pony.global_position)) > MOVE_CLEAR_M:
		return false
	if _region_of(pony.global_position) != str(row.get("region", "")):
		return false
	if pony.has_method("posture_status"):
		var status: Dictionary = pony.call("posture_status")
		if str(status.get("requested", "")) != "stand":
			return false
	return true


func _clear(id: String, reason: String) -> void:
	if id.is_empty() or not _agreements.has(id):
		return
	_agreements.erase(id)
	_debug("dialogue agreement cleared %s reason=%s" % [id, reason])


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


func _region_of(at: Vector3) -> String:
	return str(WorldLayout.nearest(at).get("id", ""))


func _debug(text: String) -> void:
	if is_instance_valid(main) and main.has_method("debug"):
		main.call("debug", text)
