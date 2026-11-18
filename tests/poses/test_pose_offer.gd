extends SceneTree
## The typed pose offer: the empty handle, validity, the blocked record and the trigger policy
## round-trip. The start path that consumes the offer is the offer service's; its outcomes are
## `tests/offer/test_start.gd`.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_pose_offer.gd

const POSE_OFFER := preload("res://mods/unfplap/shared/pose_offer.gd")

var failures := 0
var checks := 0


class FakePony extends Node3D:
	pass


class FakeRuntime extends Node:
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
