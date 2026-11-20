extends Node
## One shared, bounded mod classifier. It owns one LLM client and one queue, so the negotiation
## calls never race each other or the director's dialogue request. The caller owns the schema and
## parses the reply; this only bounds the request and the deadline.

const LLM := preload("res://world/ai/llm_client.gd")
const AI_CONFIG := preload("res://world/ai/ai_config.gd")

const DEADLINE_SECONDS := 8.0
const MAX_QUEUE := 4
## The negotiation calls answer JSON: one short answer or an option index; the caller owns it.
## The budget keeps private-reasoning room, because a model that exhausts it emits no JSON.
const NEGOTIATION_LIMITS := {
	"purpose": "unfplap_negotiation", "input_bytes": 4096, "output_tokens": 64,
	"reasoning_room": 768, "max_attempts": 1,
}

var client: Node
var _timer: Timer
var _director: Node
var _configured := false
var _queue: Array[Dictionary] = []
var _active: Dictionary = {}
var _serial := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.process_callback = Timer.TIMER_PROCESS_IDLE
	_timer.ignore_time_scale = true
	add_child(_timer)
	_timer.timeout.connect(_timeout)


func setup(section: Dictionary, status_path: String = "") -> bool:
	if not is_instance_valid(client):
		client = LLM.new()
		client.name = "UnfplapClassifierLlm"
		add_child(client)
	client.configure(section)
	client.status_path = status_path
	_configured = not str(section.get("base_url", "")).is_empty() \
		and not str(section.get("model", "")).is_empty()
	return _configured


## Configure from the current director once; a different director reconfigures.
func configure_from(director: Node) -> bool:
	if not is_instance_valid(director):
		return false
	var config: Variant = director.get("config")
	if config == null or not AI_CONFIG.ai_enabled(config):
		return false
	if _director == director and _configured:
		return true
	if not director.has_method("_llm_section"):
		return false
	var section: Dictionary = director.call("_llm_section")
	if section.is_empty():
		return false
	var status_path := ""
	var llm: Variant = director.get("llm")
	if is_instance_valid(llm):
		status_path = str(llm.get("status_path"))
	_director = director
	return setup(section, status_path)


## True when a bounded request can be sent now: a configured director and client. A consumer
## checks it before forming an offer, so a disabled model is not a toast on every line.
func available() -> bool:
	return _ensure_configured()


## One raw bounded completion: the caller owns the schema and parses the text.
## `done` receives the raw reply and the provider error.
func complete_raw(system: String, payload: Dictionary, key: String, done: Callable) -> bool:
	if not _ensure_configured() or not done.is_valid():
		return false
	if system.is_empty() or key.is_empty():
		return false
	return _enqueue({
		"key": key, "system": system,
		"messages": [{"role": "user", "content": JSON.stringify(payload)}],
		"limits": NEGOTIATION_LIMITS, "done": done,
	})


func cancel_key(key: String) -> void:
	if key.is_empty():
		return
	if not _active.is_empty() and str(_active.get("key", "")) == key:
		_cancel_active()
	for i: int in range(_queue.size() - 1, -1, -1):
		if str(_queue[i].get("key", "")) == key:
			_queue.remove_at(i)
	_start_next()


func cancel_scope(prefix: String) -> void:
	if prefix.is_empty():
		return
	if not _active.is_empty() and str(_active.get("key", "")).begins_with(prefix):
		_cancel_active()
	for i: int in range(_queue.size() - 1, -1, -1):
		if str(_queue[i].get("key", "")).begins_with(prefix):
			_queue.remove_at(i)
	_start_next()


func cancel_all() -> void:
	_cancel_active()
	_queue.clear()


func cancel() -> void:
	cancel_all()


func _ensure_configured() -> bool:
	if _configured and is_instance_valid(_director):
		return true
	if not is_instance_valid(_director) and is_inside_tree():
		_director = get_tree().get_first_node_in_group("conversation_director")
	return configure_from(_director)


func _enqueue(job: Dictionary) -> bool:
	if _queue.size() >= MAX_QUEUE:
		return false
	_queue.append(job)
	_start_next()
	return true


func _start_next() -> void:
	if not _active.is_empty() or _queue.is_empty() or not _configured:
		return
	if not is_instance_valid(client):
		return
	_active = _queue.pop_front()
	_serial += 1
	var generation := _serial
	_active["serial"] = generation
	_timer.start(DEADLINE_SECONDS)
	var accepted: bool = client.complete_limited(str(_active.get("system", "")),
		_active.get("messages", []),
		func(reply: String, error: String) -> void:
			if generation != _serial:
				return
			_finish(reply, error),
		_active.get("limits", NEGOTIATION_LIMITS))
	if not accepted:
		_finish("", "client_busy")


func _timeout() -> void:
	if is_instance_valid(client):
		client.cancel()
	_finish("", "timeout")


func _finish(reply: String, error: String) -> void:
	if _active.is_empty():
		return
	if is_instance_valid(_timer):
		_timer.stop()
	var job := _active
	_active = {}
	_serial += 1
	var done: Callable = job.get("done", Callable())
	if done.is_valid():
		done.call(reply, error)
	_start_next()


func _cancel_active() -> void:
	if _active.is_empty():
		return
	if is_instance_valid(_timer):
		_timer.stop()
	if is_instance_valid(client):
		client.cancel()
	_active = {}
	_serial += 1


func _exit_tree() -> void:
	cancel_all()
