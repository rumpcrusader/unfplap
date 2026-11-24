extends "res://mods/unfplap/shared/service.gd"
## Service: classifier
## Scope: world
## Contract: docs/classifier.md
## The one bounded model transport: one client, one queue, one deadline and one cancellable call.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const MAX_QUEUE := 4
const LIMITS := {
	"purpose": "unfplap_classifier", "input_bytes": 4096, "output_tokens": 64,
	"reasoning_room": 768, "max_attempts": 1,
}


## One classifier's instruction and bounds. The owner sets `id` and `instruction`; the rest have
## defaults. Plain data: no constructor.
class Definition:
	var id: String
	var instruction: String
	var input_bytes := 4096
	var output_tokens := 64
	var reasoning_room := 768
	var max_attempts := 1
	var deadline_s := 8.0
	var priority := 0


## One queued or active call. Connect `done` for the reply; `cancel()` drops it, and a cancelled
## call never emits.
class Call extends RefCounted:
	signal done(reply: String, error: String)
	var definition: Definition = null
	var utterance := ""
	var serial := 0
	var _cancel: Callable = Callable()

	func cancel() -> void:
		if _cancel.is_valid():
			_cancel.call(self)


var client: Node = null
var _timer: Timer
var _director: WORLD.Director = null
var _configured := false
var _test_client := false
var _queue: Array[Call] = []
var _active: Call = null
var _serial := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.process_callback = Timer.TIMER_PROCESS_IDLE
	_timer.ignore_time_scale = true
	add_child(_timer)
	_timer.timeout.connect(_timeout)


## A suite seam: a fake client replaces the live one; the entry never calls it.
func setup(client_node: Node) -> void:
	client = client_node
	_test_client = is_instance_valid(client_node)
	_configured = _test_client


## True while the live director's model configuration allows a call.
func available() -> bool:
	return _ensure_configured()


## One bounded call. Null means nothing could start; the returned handle reports through `done`.
## A cancelled call is silent.
func run(definition: Definition, utterance: String) -> Call:
	if not _valid(definition) or utterance.is_empty():
		return null
	if not _ensure_configured():
		return null
	if _queue.size() >= MAX_QUEUE:
		LOG.debug("classifier queue full id=%s", [definition.id])
		return null
	var call := Call.new()
	call.definition = definition
	call.utterance = utterance
	call._cancel = Callable(self, "_cancel_call")
	_enqueue(call)
	return call


## Drop every request; the world-close and shutdown path.
func cancel_all() -> void:
	_cancel_active()
	_queue.clear()


func _valid(definition: Definition) -> bool:
	if definition == null:
		return false
	if definition.id.is_empty() or definition.instruction.is_empty():
		LOG.error("classifier definition has no id or instruction")
		return false
	if definition.input_bytes <= 0 or definition.output_tokens <= 0 \
			or definition.reasoning_room < 0 or definition.max_attempts < 1 \
			or definition.deadline_s <= 0.0:
		LOG.error("classifier definition bounds are invalid id=%s", [definition.id])
		return false
	return true


func _ensure_configured() -> bool:
	if _test_client:
		return is_instance_valid(client)
	var director := WORLD.director()
	if not is_instance_valid(director):
		return false
	if _configured and is_instance_valid(client) and _director == director:
		return true
	var config := director.llm_config()
	if not config.enabled or config.section.is_empty():
		return false
	if not is_instance_valid(client):
		client = director.new_llm()
		client.name = "UnfplapClassifierLlm"
		add_child(client)
	client.configure(config.section)
	client.status_path = config.status_path
	_director = director
	_configured = true
	return true


func _enqueue(call: Call) -> void:
	var index := _queue.size()
	while index > 0 and _queue[index - 1].definition.priority < call.definition.priority:
		index -= 1
	_queue.insert(index, call)
	call_deferred("_start_next")


func _start_next() -> void:
	if _active != null or _queue.is_empty() or not _configured:
		return
	if not is_instance_valid(client):
		return
	_active = _queue.pop_front()
	_serial += 1
	var generation := _serial
	_active.serial = generation
	_timer.start(_active.definition.deadline_s)
	var limits := LIMITS.duplicate()
	limits["purpose"] = _active.definition.id
	limits["input_bytes"] = _active.definition.input_bytes
	limits["output_tokens"] = _active.definition.output_tokens
	limits["reasoning_room"] = _active.definition.reasoning_room
	limits["max_attempts"] = _active.definition.max_attempts
	var accepted: bool = client.complete_limited(_active.definition.instruction,
		[{"role": "user", "content": _active.utterance}],
		func(reply: String, error: String) -> void:
			if generation != _serial:
				return
			_finish(reply, error),
		limits)
	if not accepted:
		_finish("", "client_busy")


func _timeout() -> void:
	if is_instance_valid(client):
		client.cancel()
	_finish("", "timeout")


func _finish(reply: String, error: String) -> void:
	if _active == null:
		return
	if is_instance_valid(_timer):
		_timer.stop()
	var call := _active
	_active = null
	_serial += 1
	call.done.emit(reply, error)
	call_deferred("_start_next")


func _cancel_call(call: Call) -> void:
	if call == null:
		return
	if call == _active:
		_cancel_active()
		call_deferred("_start_next")
		return
	var index := _queue.find(call)
	if index >= 0:
		_queue.remove_at(index)


func _cancel_active() -> void:
	if _active == null:
		return
	if is_instance_valid(_timer):
		_timer.stop()
	if is_instance_valid(client):
		client.cancel()
	_active = null
	_serial += 1


## Both world hooks drop the live calls; the queue is per world.
func on_world(_host: Node) -> void:
	on_world_closed()


func on_world_closed() -> void:
	cancel_all()
	_director = null


func shutdown() -> void:
	cancel_all()
	_director = null
	_configured = false
	_test_client = false
	client = null


func _exit_tree() -> void:
	cancel_all()
