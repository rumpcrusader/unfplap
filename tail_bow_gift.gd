extends Node
## Giving the satin tail bow in conversation. Anon says he has one for her, her reply decides,
## and a clear yes ties it on. The spoken offer is matched locally; her answer goes through the
## shared classifier (`consent_classifier.gd`) with a short local fallback.
##
## The gifted bow is an ordinary worn accessory: its state lives in `Mods.state("unfplap")`, it
## is re-attached to every pony that wears one, and a reconcile pass ties or unties it whenever
## the saved state and the actual mesh disagree. Asking her to take it off uses the same rail.

const TAIL_BOW := preload("res://mods/unfplap/tail_bow.gd")

const PENDING_AGE_S := 25.0
const RECONCILE_S := 1.0
const BOW_WORDS := "\\b(?:(?:tail|hair)\\s*)?(?:bow|bows|ribbon)\\b"
const TAKE_WORDS := "(?:take|remove|untie|undo|slip|get)\\b[^.?!]{0,24}\\b(?:off|out)\\b|\\b(?:remove|off)\\b"
const GIVE_WORDS := "(?:for you|for your|got you|gotcha|bought|made you|have a|have this|here is|here's|heres|this is|give|gift|present|wear|put (?:it|this|that) on|try (?:it|this) on|want one)"
const ACCEPT_WORDS := ["yes", "please", "thank", "love", "lovely", "beautiful", "pretty", "cute",
	"adorable", "sure", "okay", "ok", "alright", "i will", "i'll", "i'd love", "perfect",
	"wonderful", "sweet", "of course", "absolutely", "yes please"]
const DECLINE_WORDS := ["no", "not", "never", "later", "why", "stop", "don't", "do not",
	"wouldn't", "not now", "not today", "no thanks", "no thank you"]

var main

var _director: Node
var _pending: Dictionary = {}
var _serial := 0
var _reconcile := 0.0
static var _regex: Dictionary = {}


func _ready() -> void:
	set_process(true)


func reset() -> void:
	_disconnect_director()
	_pending = {}
	_serial += 1
	_reconcile = 0.0


func _process(delta: float) -> void:
	_ensure_director()
	_reconcile -= delta
	if _reconcile > 0.0:
		return
	_reconcile = RECONCILE_S
	reconcile()


## Ties or unties every saved bow so the mesh matches the worn record, and picks up ponies that
## entered the world after the gift.
func reconcile() -> void:
	var enabled := TAIL_BOW.feature_on()
	for pony: Node3D in _ponies():
		var id := TAIL_BOW.worn_id(pony)
		if id.is_empty():
			continue
		var worn := enabled and TAIL_BOW.wears_id(id)
		var attached := is_instance_valid(TAIL_BOW.piece(pony))
		if worn and not attached:
			TAIL_BOW.attach(pony)
		elif attached and not worn:
			TAIL_BOW.detach(pony)


## Rebuild every worn bow so a settings edit (size, offset, dye) applies at once.
func refresh() -> void:
	if not TAIL_BOW.feature_on():
		reconcile()
		return
	for pony: Node3D in _ponies():
		if TAIL_BOW.wears(pony):
			TAIL_BOW.refresh(pony)


## Which spoken offer this line is: "give", "take" or "".
static func offer_kind(text: String) -> String:
	var line := text.to_lower().strip_edges()
	if line.is_empty() or not _matches(line, BOW_WORDS):
		return ""
	if _matches(line, TAKE_WORDS):
		return "take"
	if _matches(line, GIVE_WORDS):
		return "give"
	return ""


## Clear yes or no in her reply, for when the classifier is unavailable.
static func local_answer(text: String) -> String:
	var line := text.to_lower().strip_edges()
	if line.is_empty():
		return "unclear"
	for word: String in DECLINE_WORDS:
		if line.begins_with(word + " ") or line == word or line.begins_with(word + ","):
			return "decline"
	for word: String in ACCEPT_WORDS:
		if line.begins_with(word) or line.contains(" " + word) or line.begins_with(word + ","):
			return "accept"
	return "unclear"


func _ensure_director() -> void:
	if is_instance_valid(_director) or not is_inside_tree():
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
	if _in_act():
		return
	var kind := offer_kind(text)
	if kind.is_empty():
		_pending = {}
		return
	_serial += 1
	_pending = {"text": text.strip_edges(), "kind": kind, "serial": _serial,
		"at": Time.get_ticks_msec() * 0.001}


func _on_reply(id: String, text: String) -> void:
	if _pending.is_empty() or _in_act():
		_pending = {}
		return
	if id.is_empty() or text.strip_edges().is_empty():
		return
	if Time.get_ticks_msec() * 0.001 - float(_pending.get("at", 0.0)) > PENDING_AGE_S:
		_pending = {}
		return
	var pony := _pony(id)
	if not is_instance_valid(pony):
		_pending = {}
		return
	var kind := str(_pending.get("kind", ""))
	var offer := str(_pending.get("text", ""))
	var serial := int(_pending.get("serial", -1))
	_pending = {}
	if not _offerable(pony, kind):
		return
	if not _willing(pony):
		_debug("tail bow: %s is not willing" % id)
		return
	var classifier: Variant = main.get("classifier") if is_instance_valid(main) else null
	if is_instance_valid(classifier) and classifier.has_method("classify_agreement"):
		var key := "bow:%d" % serial
		var started: bool = bool(classifier.call("classify_agreement", offer, text, key,
			Callable(self, "_on_answer").bind(id, kind, text, serial)))
		if started:
			_debug("tail bow: offer=\"%s\" reply=\"%s\"" % [offer.left(120), text.left(120)])
			return
	_apply(local_answer(text), "local", id, kind, text, serial)


func _on_answer(intent: String, detail: String, id: String, kind: String, reply: String,
		serial: int) -> void:
	if serial != _serial:
		return
	var source := "llm"
	if intent == "unclear" and not detail.is_empty():
		intent = local_answer(reply)
		source = "local"
	_debug("tail bow: answer=%s detail=%s source=%s" % [intent, detail, source])
	_apply(intent, source, id, kind, reply, serial)


func _apply(intent: String, source: String, id: String, kind: String, _reply: String,
		serial: int) -> void:
	if serial != _serial:
		return
	if intent != "accept":
		_debug("tail bow: %s declined (%s)" % [id, source])
		return
	var pony := _pony(id)
	if not is_instance_valid(pony):
		return
	if kind == "take":
		_take(pony, id)
	else:
		_give(pony, id)


func _give(pony: Node3D, id: String) -> void:
	TAIL_BOW.set_worn(id, true)
	TAIL_BOW.attach(pony)
	var expressions: Variant = pony.get("expressions")
	if expressions != null and expressions.has_method("fluster"):
		expressions.fluster(1.2)
	_bonds_experience(id, "tail_bow_gift")
	_record("gift", "Anon gave you a satin tail bow, and you are wearing it at the base of your tail.", id)
	_debug("tail bow: %s now wears it" % id)


func _take(pony: Node3D, id: String) -> void:
	TAIL_BOW.set_worn(id, false)
	TAIL_BOW.detach(pony)
	_record("gift", "Anon untied the satin tail bow from the base of your tail and kept it.", id)
	_debug("tail bow: %s no longer wears it" % id)


func _offerable(pony: Node3D, kind: String) -> bool:
	if not TAIL_BOW.feature_on():
		return false
	var identity: Variant = pony.get("identity")
	if identity != null and bool(identity.get("filly")):
		return false
	var id := TAIL_BOW.worn_id(pony)
	if id.is_empty():
		return false
	if kind == "take":
		return TAIL_BOW.wears_id(id)
	return not TAIL_BOW.wears_id(id)


## The base game's gift willingness: her own AI anger or an asked-for boundary turns the gift down.
func _willing(pony: Node3D) -> bool:
	var bonds := _bonds()
	if bonds == null:
		return true
	var id := TAIL_BOW.worn_id(pony)
	if id.is_empty():
		return true
	var record: Dictionary = bonds.call("record_for", id)
	var cooldowns: Variant = record.get("cooldowns", {})
	var boundary := float((cooldowns as Dictionary).get("boundary", 0.0)) \
		if cooldowns is Dictionary else 0.0
	return float(bonds.call("anger", id)) < 35.0 and float(bonds.call("now")) >= boundary


func _bonds() -> Node:
	if not is_instance_valid(main) or not is_instance_valid(main.get("game")):
		return null
	var game: Node = main.get("game")
	var context: Variant = game.get("world_context")
	if context == null:
		return null
	var bonds: Variant = context.get("player_bonds")
	return bonds as Node if bonds is Node else null


func _bonds_experience(id: String, tag: String) -> void:
	var bonds := _bonds()
	if bonds == null:
		return
	bonds.call("experience", id, "gift", "%s_%d" % [tag, Time.get_ticks_usec()])


func _record(kind: String, text: String, id: String) -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.get("game")):
		return
	var game: Node = main.get("game")
	var context: Variant = game.get("world_context")
	if context != null and context.has_method("record"):
		context.call("record", kind, text, [id, "player"], [id, "player"])


func _ponies() -> Array:
	var list: Array = []
	if not is_instance_valid(main) or not is_instance_valid(main.get("game")):
		return list
	var game: Node = main.get("game")
	var mares: Variant = game.get("mares")
	if not mares is Array:
		return list
	for node: Variant in mares:
		if is_instance_valid(node) and node is Node3D:
			list.append(node as Node3D)
	return list


func _pony(id: String) -> Node3D:
	for pony: Node3D in _ponies():
		if TAIL_BOW.worn_id(pony) == id:
			return pony
	return null


func _in_act() -> bool:
	return is_instance_valid(main) and is_instance_valid(main.get("active_runtime"))


func _debug(text: String) -> void:
	if is_instance_valid(main) and main.has_method("debug"):
		main.call("debug", text)


static func _matches(line: String, pattern: String) -> bool:
	var regex: RegEx = _regex.get(pattern)
	if regex == null:
		regex = RegEx.new()
		if regex.compile(pattern) != OK:
			return false
		_regex[pattern] = regex
	return regex.search(line) != null
