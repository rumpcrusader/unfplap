extends SceneTree
## The typed pose offer and the one start path: defaults, validity, the blocked record, the
## cancel/scope/auto fields, `main.start_pose_offer()`'s outcome table and the private
## Agreement auto-start's fresh privacy sample.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_pose_offer.gd

## Loaded at run time: `main.gd` names the game's `Mods` autoload, which the `--script`
## compiler cannot see at preload time. The autoload node exists before the suite runs.
var MAIN: Variant = null
const POSE_OFFER := preload("res://mods/unfplap/shared/pose_offer.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const PRIVACY := preload("res://mods/unfplap/privacy/service.gd")

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
	var hotkey_starts := 0
	var hotkey_result := true

	func force_stop() -> void:
		pass

	func start_agreement(handle: Variant, _skip_presentation := false) -> int:
		agreement_handles.append(handle)
		return agreement_result

	func agreement_offer_ready(_handle: Variant, _skip_presentation := false) -> bool:
		return true

	func start_hotkey(_pose: String, _bed: Variant, _source: String) -> bool:
		hotkey_starts += 1
		return hotkey_result

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

	func cancel_all() -> void:
		pass


class FakeNegotiation extends Node:
	var live: Variant = null
	var reports: Array = []
	var cancels: Array = []
	var interrupts := 0
	var locked := false
	var match: Variant = null

	func handle() -> Variant:
		return live

	func report(_handle: Variant, started: bool) -> void:
		reports.append(started)

	func cancel(handle: Variant, reason: String) -> bool:
		cancels.append([handle, reason])
		live = null
		return true

	func is_locked() -> bool:
		return locked

	func hotkey_handle(_runtime: Node, _option: Variant) -> Variant:
		return match

	func interrupt_for_hotkey() -> void:
		interrupts += 1

	func reset() -> void:
		live = null
		locked = false


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
	_check_agreement_auto_start()
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
	MAIN = load("res://mods/unfplap/main.gd")
	check(MAIN != null, "main.gd loads with the game autoloads")
	if MAIN == null:
		return
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
	check(runtime.starts == 0 and runtime.hotkey_starts == 0,
		"a blocked offer starts neither path")
	check(hud.toasts == ["Find a footstool in a house."],
		"a blocked offer shows the recorded toast once")

	# The hotkey's immediate attempt: Base clearance plus scene-only rows, no policy gate.
	var hotkey := _offer(runtime, pony)
	runtime.hotkey_result = true
	main.set("_offer", hotkey)
	check(bool(main.call("start_pose_offer", hotkey)), "the hotkey starts an immediate attempt")
	check(runtime.hotkey_starts == 1 and runtime.starts == 0,
		"the hotkey uses the scene-only path, not the policy start")
	check(main.get("_offer") == null, "a started hotkey clears the hint")
	runtime.hotkey_result = false
	check(not bool(main.call("start_pose_offer", hotkey)),
		"a blocked hotkey starts nothing")
	runtime.hotkey_result = true

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

	# A live Agreement's exact match skips the presentation and consumes the handle.
	negotiation.live = {"pony": pony, "option": null}
	negotiation.match = negotiation.live
	var matching := _offer(runtime, pony)
	main.set("_offer", matching)
	runtime.agreement_result = RUNTIME.AGREEMENT_STARTED
	var hotkey_before := runtime.hotkey_starts
	check(bool(main.call("start_pose_offer", matching)),
		"a matching Agreement starts from the hotkey")
	check(runtime.hotkey_starts == hotkey_before,
		"a matching Agreement is not a hotkey attempt")
	check(main.get("_offer") == null, "a matching Agreement clears the hint")
	negotiation.live = null
	negotiation.match = null

	# A live negotiation without an Agreement is interrupted before the attempt.
	negotiation.locked = true
	runtime.hotkey_result = true
	check(bool(main.call("start_pose_offer", hotkey)), "the hotkey runs after a negotiation")
	check(negotiation.interrupts == 1, "an active negotiation is interrupted")
	negotiation.locked = false

	# A live Agreement with a different option is interrupted; the attempt still runs.
	negotiation.live = {"pony": pony, "option": null}
	runtime.hotkey_result = true
	check(bool(main.call("start_pose_offer", hotkey)), "a different Agreement is interrupted")
	check(negotiation.interrupts == 2, "the different Agreement is interrupted")
	negotiation.live = null

	# An invalid handle is a no-op.
	check(not bool(main.call("start_pose_offer", POSE_OFFER.new())),
		"an invalid offer starts nothing")

	root.remove_child(main)
	main.free()
	negotiation.free()
	runtime.free()
	pony.free()


func _check_agreement_auto_start() -> void:
	if MAIN == null:
		return
	var main: Node = MAIN.new()
	root.add_child(main)
	main.hud = FakeHud.new()
	var runtime := FakeRuntime.new()
	var pony := FakePony.new()
	root.add_child(runtime)
	root.add_child(pony)
	main.set("_runtimes", {pony: runtime})
	var negotiation := FakeNegotiation.new()
	main.negotiation = negotiation
	main.privacy = PRIVACY.new()
	var option := POSE_OPTIONS.Option.new()
	option.pose = "missionary"
	option.source = "bed_side"
	var handle := {"pony": pony, "option": option, "private": true}
	negotiation.live = handle

	# A private Agreement whose fresh sample is public is cancelled, not started.
	main.set("_agreement_clock", 0.25)
	main.call("_tick_agreement_auto_start", 0.0)
	check(negotiation.cancels.size() == 1
		and str(negotiation.cancels[0][1]) == "privacy",
		"a private auto-start cancels when the fresh sample is public")
	check(runtime.agreement_handles.is_empty(),
		"a cancelled private auto-start starts no act")

	# A public Agreement takes no privacy sample and starts.
	handle.private = false
	negotiation.live = handle
	runtime.agreement_result = RUNTIME.AGREEMENT_STARTED
	main.set("_agreement_clock", 0.25)
	main.call("_tick_agreement_auto_start", 0.0)
	check(runtime.agreement_handles.size() == 1,
		"a public Agreement auto-starts without a privacy sample")
	check(negotiation.cancels.size() == 1, "the public auto-start does not cancel")

	# The hotkey's exact match starts at once and does not sample the provider.
	negotiation.live = handle
	negotiation.match = handle
	var offer := _offer(runtime, pony)
	check(bool(main.call("start_pose_offer", offer)), "the exact hotkey match starts")
	check(negotiation.cancels.size() == 1, "the hotkey match does not resample privacy")
	check(runtime.agreement_handles.size() == 2, "the hotkey match consumes the Agreement")

	root.remove_child(runtime)
	root.remove_child(pony)
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
