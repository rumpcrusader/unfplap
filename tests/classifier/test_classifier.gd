extends "res://mods/unfplap/tests/support/suite.gd"
## The bounded model transport: the queue, priority, deadline, cancellation, client-busy and the
## world-close sweep, against a fake client. No model.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/classifier/test_classifier.gd

const CLASSIFIER := preload("res://mods/unfplap/classifier/api.gd")


class FakeClient extends Node:
	var calls: Array = []
	var cancelled := 0
	var can_answer := true
	var reply := ""
	var error := ""
	var status_path := ""

	func configure(_section: Dictionary) -> void:
		pass

	func complete_limited(system: String, messages: Array, done: Callable,
			limits: Dictionary) -> bool:
		if not can_answer:
			return false
		calls.append({"system": system, "messages": messages, "done": done, "limits": limits})
		return true

	func cancel() -> void:
		cancelled += 1

	func answer(reply_text: String = "", error_text: String = "") -> void:
		var row: Dictionary = calls[-1]
		(row["done"] as Callable).call(reply_text, error_text)


var _service: CLASSIFIER
var _client: FakeClient


func before() -> void:
	_service = CLASSIFIER.new()
	_service.name = "UnfplapClassifier"
	root.add_child(_service)
	_client = FakeClient.new()
	root.add_child(_client)
	_service.setup(_client)


func teardown() -> void:
	if is_instance_valid(_service):
		root.remove_child(_service)
		_service.free()
	if is_instance_valid(_client):
		root.remove_child(_client)
		_client.free()


func run() -> void:
	await _check_call()
	await _check_refusals()
	await _check_priority()
	await _check_cancel()
	await _check_deadline()
	await _check_world_close()
	finish()


func _definition(id: String, priority := 0) -> CLASSIFIER.Definition:
	var out := CLASSIFIER.Definition.new()
	out.id = id
	out.instruction = "instruction " + id
	out.priority = priority
	return out


func _check_call() -> void:
	check(_service.available(), "a fake client makes the transport available")
	var got: Array = []
	var call := _service.run(_definition("one"), "hello")
	check(call != null, "a call starts")
	call.done.connect(func(reply: String, error: String) -> void: got.append([reply, error]))
	await process_frame
	check(_client.calls.size() == 1, "the client receives the call")
	var row: Dictionary = _client.calls[0]
	check(str(row["system"]) == "instruction one", "the definition instruction is the system text")
	check(str((row["messages"] as Array)[0]["content"]) == "hello", "the utterance is the user text")
	check(str((row["limits"] as Dictionary).get("purpose", "")) == "one",
		"the definition id labels the call")
	_client.answer("reply", "")
	check(got.size() == 1 and got[0][0] == "reply" and got[0][1] == "",
		"the call emits its one reply")
	await process_frame


func _check_refusals() -> void:
	check(_service.run(null, "hello") == null, "a null definition is refused")
	var empty := CLASSIFIER.Definition.new()
	empty.id = "empty"
	check(_service.run(empty, "hello") == null, "an empty instruction is refused")
	check(_service.run(_definition("two"), "") == null, "an empty utterance is refused")

	_client.can_answer = false
	var got: Array = []
	var call := _service.run(_definition("busy"), "hello")
	check(call != null, "the call is accepted before the client answers")
	call.done.connect(func(reply: String, error: String) -> void: got.append([reply, error]))
	await process_frame
	check(got.size() == 1 and got[0][1] == "client_busy", "a busy client reports client_busy")
	_client.can_answer = true
	await process_frame


func _check_priority() -> void:
	_client.calls.clear()
	var low := _service.run(_definition("low-first"), "one")
	await process_frame
	var high := _service.run(_definition("high", 10), "two")
	var low2 := _service.run(_definition("low-second"), "three")
	check(low != null and high != null and low2 != null, "the three calls are queued")
	_client.answer("first", "")
	await process_frame
	check(_client.calls.size() == 2, "the next call starts")
	check(str((_client.calls[-1]["limits"] as Dictionary).get("purpose", "")) == "high",
		"the higher priority runs first")
	_client.answer("second", "")
	await process_frame
	check(str((_client.calls[-1]["limits"] as Dictionary).get("purpose", "")) == "low-second",
		"the lower priority keeps its FIFO order")
	_client.answer("third", "")
	await process_frame


func _check_cancel() -> void:
	_client.calls.clear()
	var got: Array = []
	var active := _service.run(_definition("active"), "one")
	var queued := _service.run(_definition("queued"), "two")
	active.done.connect(func(reply: String, error: String) -> void: got.append([reply, error]))
	queued.done.connect(func(reply: String, error: String) -> void: got.append([reply, error]))
	await process_frame
	check(_client.calls.size() == 1, "only the active call starts")
	queued.cancel()
	active.cancel()
	await process_frame
	check(_client.cancelled == 1, "the active request is cancelled")
	check(got.is_empty(), "a cancelled call never emits")

	_client.calls.clear()
	_client.cancelled = 0
	var first := _service.run(_definition("first"), "one")
	var second := _service.run(_definition("second"), "two")
	await process_frame
	_service.cancel_all()
	check(_client.cancelled == 1, "cancel_all cancels the active request")
	check(first != null and second != null, "both handles exist")
	await process_frame


func _check_deadline() -> void:
	_client.calls.clear()
	_client.cancelled = 0
	var short := _definition("short")
	short.deadline_s = 0.01
	var got: Array = []
	var call := _service.run(short, "one")
	call.done.connect(func(reply: String, error: String) -> void: got.append([reply, error]))
	await process_frame
	await create_timer(0.05).timeout
	check(_client.cancelled == 1, "the deadline cancels the client")
	check(got.size() == 1 and got[0][1] == "timeout", "the deadline reports timeout")
	await process_frame


func _check_world_close() -> void:
	_client.calls.clear()
	_client.cancelled = 0
	var got: Array = []
	var call := _service.run(_definition("world"), "one")
	call.done.connect(func(reply: String, error: String) -> void: got.append([reply, error]))
	await process_frame
	_service.on_world_closed()
	check(_client.cancelled == 1, "a world close cancels the active request")
	check(got.is_empty(), "a world close emits no reply")
	await process_frame
