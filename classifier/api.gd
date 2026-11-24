extends "res://mods/unfplap/shared/service.gd"
## Service: classifier
## Scope: world
## Contract: docs/classifier.md
## The one bounded model transport: one client, one queue, one deadline and one cancellable call.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const _MAX_QUEUE := 4


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


## The caller's result sink; the transport invokes it once with the answer and the failure.
class Reply:
	var done: Callable = Callable()

	static func of(handler: Callable) -> Reply:
		var out := Reply.new()
		out.done = handler
		return out


## One queued or active call. `cancel()` drops it; a cancelled call never calls its reply.
class Call extends RefCounted:
	var _cancel: Callable = Callable()

	func cancel() -> void:
		if _cancel.is_valid():
			_cancel.call()


## One queued call's frozen values; the caller's definition may change after `run`.
class _Job extends RefCounted:
	var id := ""
	var instruction := ""
	var input_bytes := 0
	var output_tokens := 0
	var reasoning_room := 0
	var max_attempts := 1
	var deadline_s := 8.0
	var priority := 0
	var utterance := ""
	var done: Callable = Callable()


var _client: Node = null
var _timer: Timer
var _director: WORLD.Director = null
var _configured := false
var _test_client := false
var _queue: Array[_Job] = []
var _active: _Job = null
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
	_client = client_node
	_test_client = is_instance_valid(client_node)
	_configured = _test_client


## True while the live director's model configuration allows a call.
func available() -> bool:
	return _ensure_configured()


## One bounded call. Null means nothing could start; `reply` gets the text and error once.
func run(definition: Definition, utterance: String, reply: Reply) -> Call:
	if not _valid(definition) or utterance.is_empty():
		return null
	if reply == null or not reply.done.is_valid():
		return null
	if not _ensure_configured():
		return null
	if _queue.size() >= _MAX_QUEUE:
		LOG.debug("classifier queue full id=%s", [definition.id])
		return null
	var job := _Job.new()
	job.id = definition.id
	job.instruction = definition.instruction
	job.input_bytes = definition.input_bytes
	job.output_tokens = definition.output_tokens
	job.reasoning_room = definition.reasoning_room
	job.max_attempts = definition.max_attempts
	job.deadline_s = definition.deadline_s
	job.priority = definition.priority
	job.utterance = utterance
	job.done = reply.done
	var call := Call.new()
	call._cancel = Callable(self, "_cancel_call").bind(job)
	_enqueue(job)
	return call


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
		return is_instance_valid(_client)
	var director := WORLD.director()
	if not is_instance_valid(director):
		return false
	if _configured and is_instance_valid(_client) and _director == director:
		return true
	var config := director.llm_config()
	if not config.enabled or config.section.is_empty():
		return false
	if not is_instance_valid(_client):
		_client = director.new_llm()
		_client.name = "UnfplapClassifierLlm"
		add_child(_client)
	_client.configure(config.section)
	_client.status_path = config.status_path
	_director = director
	_configured = true
	return true


func _enqueue(job: _Job) -> void:
	var index := _queue.size()
	while index > 0 and _queue[index - 1].priority < job.priority:
		index -= 1
	_queue.insert(index, job)
	call_deferred("_start_next")


func _start_next() -> void:
	if _active != null or _queue.is_empty() or not _configured:
		return
	if not is_instance_valid(_client):
		return
	_active = _queue.pop_front()
	_serial += 1
	var generation := _serial
	_timer.start(_active.deadline_s)
	var limits := {
		"purpose": _active.id,
		"input_bytes": _active.input_bytes,
		"output_tokens": _active.output_tokens,
		"reasoning_room": _active.reasoning_room,
		"max_attempts": _active.max_attempts,
	}
	var accepted: bool = _client.complete_limited(_active.instruction,
		[{"role": "user", "content": _active.utterance}],
		func(reply: String, error: String) -> void:
			if generation != _serial:
				return
			_finish(reply, error),
		limits)
	if not accepted:
		_finish("", "client_busy")


func _timeout() -> void:
	if is_instance_valid(_client):
		_client.cancel()
	_finish("", "timeout")


func _finish(reply: String, error: String) -> void:
	if _active == null:
		return
	if is_instance_valid(_timer):
		_timer.stop()
	var job := _active
	_active = null
	_serial += 1
	if job.done.is_valid():
		job.done.call(reply, error)
	call_deferred("_start_next")


func _cancel_call(job: _Job) -> void:
	if job == null:
		return
	if job == _active:
		_cancel_active()
		call_deferred("_start_next")
		return
	var index := _queue.find(job)
	if index >= 0:
		_queue.remove_at(index)


func _cancel_active() -> void:
	if _active == null:
		return
	if is_instance_valid(_timer):
		_timer.stop()
	if is_instance_valid(_client):
		_client.cancel()
	_active = null
	_serial += 1


## Clear the active and queued calls.
func _cancel_all() -> void:
	_cancel_active()
	_queue.clear()


## Both world hooks drop the live calls; the queue is per world.
func on_world(_host: Node) -> void:
	on_world_closed()


## A world close drops the live calls and the director view; the client stays.
func on_world_closed() -> void:
	_cancel_all()
	_director = null


## The entry is leaving: drop the calls, the director view and the client reference.
func shutdown() -> void:
	_cancel_all()
	_director = null
	_configured = false
	_test_client = false
	_client = null


func _exit_tree() -> void:
	_cancel_all()
