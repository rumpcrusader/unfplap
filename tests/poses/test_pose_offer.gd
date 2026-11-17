extends SceneTree
## The typed pose offer and the one start path: defaults, validity, the blocked record, the
## cancel/scope/auto fields, and `main.start_pose_offer()`'s outcome table.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_pose_offer.gd

const MAIN := preload("res://mods/unfplap/main.gd")
const POSE_OFFER := preload("res://mods/unfplap/shared/pose_offer.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")

var failures := 0
var checks := 0


class FakePony extends Node3D:
	pass


class FakeRuntime extends Node:
	var gate: Dictionary = {}
	var start_result := true
	var starts := 0
	var refusals := 0
	var last_start: Array = []
	var agreement_result := 0
	var agreement_handles: Array = []

	func start_agreement(handle: Variant) -> int:
		agreement_handles.append(handle)
		return agreement_result

	func start_verdict(_pose: String, _source: String, _bed: Variant) -> Dictionary:
		return gate

	func start(pose: String, bed: Variant, source: String, _gate: Dictionary) -> bool:
		starts += 1
		last_start = [pose, bed, source]
		return start_result

	func refuse_from_history(_pose: String, _source: String, _bed: Variant) -> bool:
		refusals += 1
		return true


class FakeClassifier extends Node:
	var scopes: Array[String] = []

	func cancel_scope(scope: String) -> void:
		scopes.append(scope)


class FakeNegotiation extends Node:
	var live: Variant = null
	var reports: Array = []

	func handle() -> Variant:
		return live

	func report(_handle: Variant, started: bool) -> void:
		reports.append(started)


class FakeHud extends Node:
	var toasts: Array[String] = []

	func toast(text: String, _seconds := 2.0) -> void:
		toasts.append(text)

	func hide_prompt() -> void:
		pass


class Counter extends RefCounted:
	var count := 0

	func bump() -> void:
		count += 1


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	_check_handle()
	_check_start_path()
	_check_sources()
	print("POSE_OFFER_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("POSE_OFFER_PASS")
	quit(0 if failures == 0 else 1)


func _check_handle() -> void:
	var offer := POSE_OFFER.new()
	check(offer.runtime == null and offer.pony == null and offer.pose.is_empty(),
		"a new offer is empty")
	check(not offer.valid(), "an empty offer is not valid")
	check(offer.blocked.is_empty() and offer.blocked_hint().is_empty(),
		"a new offer is playable")
	check(not offer.auto and not offer.pending and offer.scope.is_empty(),
		"a new offer stores no trigger policy")
	check(not offer.cancel.is_valid(), "a new offer has no cleanup callback")
	var runtime := FakeRuntime.new()
	var pony := FakePony.new()
	offer.runtime = runtime
	offer.pony = pony
	check(not offer.valid(), "a runtime and pony without a pose is not valid")
	offer.pose = "missionary"
	check(offer.valid(), "a runtime, pony and pose is a valid handle")
	offer.trigger = "debug"
	offer.auto = true
	offer.pending = true
	offer.scope = "dialogue:"
	var counter := Counter.new()
	offer.cancel = Callable(counter, "bump")
	offer.cancel.call()
	check(counter.count == 1, "the owner cleanup is a callable and runs once")
	check(offer.trigger == "debug" and offer.auto and offer.pending
		and offer.scope == "dialogue:", "the trigger policy round-trips")
	offer.blocked = {"hint": "Needs a footstool", "need": 2,
		"toast": "Find 2 footstools in a house."}
	check(offer.blocked_hint() == "Needs a footstool", "the blocked hint is the recorded text")
	check(int(offer.blocked.get("need", 0)) == 2, "the blocked record keeps the need count")
	runtime.free()
	pony.free()


func _check_start_path() -> void:
	var main: Node = MAIN.new()
	root.add_child(main)
	var hud := FakeHud.new()
	main.hud = hud
	var classifier := FakeClassifier.new()
	main.classifier = classifier

	var runtime := FakeRuntime.new()
	var pony := FakePony.new()
	root.add_child(runtime)
	root.add_child(pony)

	# A blocked offer shows its toast and starts nothing.
	var blocked := _offer(runtime, pony)
	blocked.blocked = {"hint": "Needs a footstool", "need": 1,
		"toast": "Find a footstool in a house."}
	check(not bool(main.call("start_pose_offer", blocked)),
		"a blocked offer does not start")
	check(runtime.starts == 0 and hud.toasts == ["Find a footstool in a house."],
		"a blocked offer shows the recorded toast once")

	# A history refusal closes the offer and reports the refusal as handled.
	var history := _offer(runtime, pony)
	var history_cancel := Counter.new()
	history.cancel = Callable(history_cancel, "bump")
	runtime.gate = {"attempt": false, "history_refuse": true}
	check(bool(main.call("start_pose_offer", history)),
		"a history refusal reports that it happened")
	check(history_cancel.count == 1 and runtime.refusals == 1 and runtime.starts == 0,
		"a history refusal closes the owner before refusing")
	check(main.get("_offer") == null, "a history refusal clears the hint")

	# A buck refusal closes the owner and runs the push, not the act.
	var buck := _offer(runtime, pony)
	var buck_cancel := Counter.new()
	buck.cancel = Callable(buck_cancel, "bump")
	runtime.gate = {"attempt": false, "buck_refuse": true}
	check(not bool(main.call("start_pose_offer", buck)), "a buck refusal starts nothing")
	check(buck_cancel.count == 1 and runtime.starts == 1 and runtime.last_start[0] == "missionary",
		"a buck refusal closes the owner and starts the refusal path")

	# A transient failed gate keeps the owner and the hint alive.
	var transient := _offer(runtime, pony)
	var transient_cancel := Counter.new()
	transient.cancel = Callable(transient_cancel, "bump")
	runtime.gate = {"attempt": false, "buck_refuse": false, "rows": []}
	check(not bool(main.call("start_pose_offer", transient)),
		"a transient failed gate starts nothing")
	check(transient_cancel.count == 0, "a transient failed gate keeps the accepted offer")

	# An attempt closes the owner, starts the act and cancels the offer's classifier scope.
	var accepted := _offer(runtime, pony)
	var accepted_cancel := Counter.new()
	accepted.cancel = Callable(accepted_cancel, "bump")
	accepted.scope = "dialogue:"
	runtime.gate = {"attempt": true}
	runtime.starts = 0
	check(bool(main.call("start_pose_offer", accepted)), "an attempt starts the act")
	check(accepted_cancel.count == 1 and runtime.starts == 1,
		"an attempt closes the owner before the start")
	check(classifier.scopes == ["dialogue:"], "an attempt cancels the offer's classifier scope")
	check(main.get("_offer") == null, "a successful start clears the hint")

	# A failed start still closed the handoff: the offer is handed off and the hint clears.
	var failed := _offer(runtime, pony)
	var failed_cancel := Counter.new()
	failed.cancel = Callable(failed_cancel, "bump")
	failed.scope = "dialogue:"
	runtime.gate = {"attempt": true}
	runtime.start_result = false
	classifier.scopes.clear()
	check(not bool(main.call("start_pose_offer", failed)), "a failed start returns false")
	check(failed_cancel.count == 1 and classifier.scopes.is_empty(),
		"a failed start keeps the owner closed and cancels no scope")
	check(main.get("_offer") == null, "a failed start clears the hint")
	runtime.start_result = true

	# A live Agreement is consumed through the scene-only start: WAIT keeps the hint and the
	# Agreement, STARTED and FAILED clear the hint. The runtime reports the result.
	var negotiation := FakeNegotiation.new()
	main.negotiation = negotiation
	negotiation.live = {"pony": pony, "option": null}
	var agreement := _offer(runtime, pony)
	agreement.trigger = "agreement"
	main.set("_offer", agreement)
	runtime.agreement_result = RUNTIME.AGREEMENT_WAIT
	check(not bool(main.call("start_pose_offer", agreement)),
		"a waiting Agreement does not start")
	check(main.get("_offer") == agreement, "a waiting Agreement keeps the hint")
	check(runtime.agreement_handles.size() == 1,
		"the Agreement handle reaches the runtime")
	runtime.agreement_result = RUNTIME.AGREEMENT_STARTED
	check(bool(main.call("start_pose_offer", agreement)),
		"a ready Agreement starts through the scene-only path")
	check(main.get("_offer") == null, "a started Agreement clears the hint")
	check(runtime.starts == 0, "the Agreement start does not use the policy start path")
	negotiation.live = null
	check(not bool(main.call("start_pose_offer", agreement)),
		"a missing Agreement handle starts nothing")

	# An invalid handle is a no-op.
	check(not bool(main.call("start_pose_offer", POSE_OFFER.new())),
		"an invalid offer starts nothing")

	root.remove_child(main)
	main.free()
	negotiation.free()
	runtime.free()
	pony.free()


func _offer(runtime: Node, pony: Node3D) -> POSE_OFFER:
	var offer := POSE_OFFER.new()
	offer.runtime = runtime
	offer.pony = pony
	offer.pose = "missionary"
	offer.source = "bed_side"
	return offer


func _check_sources() -> void:
	var text := FileAccess.get_file_as_string("res://mods/unfplap/shared/pose_offer.gd")
	check(not text.is_empty(), "shared/pose_offer.gd is readable")
	for token: String in ["get_tree(", "SETTINGS", "FileAccess", "preload(", "extends Node"]:
		check(not text.contains(token), "shared/pose_offer.gd stays data: %s" % token)
