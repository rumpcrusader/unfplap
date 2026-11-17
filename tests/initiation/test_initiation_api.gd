extends SceneTree
## The reduced proactive service: Base clearance, the placeable options, the reasoning, the walk,
## the ask line and the Mare-offer handoff, against a fake director bridge, privacy and runtime.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/initiation/test_initiation_api.gd

const INIT := preload("res://mods/unfplap/initiation/service.gd")
const PRIVACY := preload("res://mods/unfplap/privacy/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


class FakeView extends RefCounted:
	var form := "human"
	var view := "desktop"


class FakeEligibility extends RefCounted:
	var act := true
	var relationship := true

	func eligible(_pony: Node, _target: int) -> bool:
		return act

	func relationship_ok(_pony: Node) -> bool:
		return relationship


class FakeMain extends Node:
	var player: Node3D
	var game: Node
	var runtimes: Dictionary = {}
	var eligibility: Variant
	var view := FakeView.new()
	var debug_lines: Array[String] = []
	var offer: Dictionary = {}
	var handoff_ok := true
	var offer_target_value: Variant = null

	func runtime_for(pony: Node) -> Node:
		var runtime: Variant = runtimes.get(pony)
		return runtime if is_instance_valid(runtime) else null

	func menu_open() -> bool:
		return false

	func camera() -> Camera3D:
		return null

	func bed_occupied(_bed: Node3D, _target: Node) -> bool:
		return false

	func debug(text: String) -> void:
		debug_lines.append(text)

	func form_view() -> Variant:
		return view

	func context_facts(_pony: Node) -> Dictionary:
		return {"willingness": true, "history": {"offer_weight": 0.7}}

	func form_mare_offer(fields: Dictionary) -> bool:
		offer = fields
		return handoff_ok

	func offer_target() -> Variant:
		return offer_target_value


class FakeGame extends Node:
	var mares: Array = []
	var world_context: Node
	var headset_view := false


class FakeWorldContext extends Node:
	var records: Array = []

	func record(kind: String, text: String, ids: Array, _audience: Array, key: String) -> void:
		records.append({"kind": kind, "text": text, "ids": ids, "key": key})


class FakeNavigator extends Node:
	var reserved_by := ""
	var command_owner := ""
	var wander_enabled := true
	var command_speed_limit: Variant = INF
	var command_pace_target: Variant = -1.0
	var _has_target := false
	var goal: Variant = null

	func stay() -> void:
		_has_target = false

	func command_support(point: Vector3) -> Vector3:
		return point

	func command_destination(point: Vector3, _gait: String) -> bool:
		goal = point
		_has_target = true
		return true


class FakePony extends Node3D:
	var identity: Dictionary = {"filly": false, "stallion": false}
	var sleeping := false


class FakeRuntime extends Node:
	var pony: Node3D
	var state := 0
	var cuddle := false
	var bed_under: Node3D = null
	var hard_ok := true
	var phase := "normal"
	var scene_reasons: Array = []

	func scene_only_verdict(_pose: String, _source: String, _bed: Variant,
			_frozen: Variant) -> Dictionary:
		return {"hard_ok": hard_ok, "ok": hard_ok, "transient": [], "reasons": scene_reasons}

	func cuddle_active() -> bool:
		return cuddle

	func find_bed_under() -> Node3D:
		return bed_under

	func cycle_phase() -> String:
		return phase


class FakePrivacy extends PRIVACY:
	var private := true

	func setup(_main_node: Node) -> void:
		pass

	func offer_private(_except: Node = null) -> bool:
		return private

	func cuddle_private(_pony: Node) -> bool:
		return private


class FakeAdapter extends Node:
	var quiet_reason_value := ""
	var reason_reply := "{\"offer\":false}"
	var reason_error := ""
	var greeting_ok := true
	var greetings: Array = []
	var queued: Array = []
	var cancelled: Array = []
	var situations: Array = []
	var reason_payloads: Array = []
	var auto := true

	func quiet_reason(_gap: float) -> String:
		return quiet_reason_value

	func quiet(_gap: float) -> bool:
		return quiet_reason_value == ""

	func begin_greeting(id: String, context: String) -> bool:
		greetings.append([id, context])
		return greeting_ok

	func queue(id: String, purpose: String, key: String, _valid: Callable,
			_priority: bool) -> bool:
		queued.append([id, purpose, key])
		return true

	func cancel_keys(keys: Array) -> void:
		cancelled.append_array(keys)

	func record_situation(text: String, ids: Array, key: String) -> void:
		situations.append({"text": text, "ids": ids, "key": key})

	func complete_raw(_system: String, payload: Dictionary, _scope: String,
			done: Callable) -> bool:
		reason_payloads.append(payload)
		if auto:
			done.call(reason_reply, reason_error)
		return true

	func cancel_scope(scope: String) -> void:
		cancelled.append(scope)


class FakeTerminal extends RefCounted:
	var pony: Node = null
	var pony_id := ""
	var outcome := 0
	var reason := ""
	var trigger := 0
	var cooldown_s := 0.0


func _fixture() -> Dictionary:
	var main := FakeMain.new()
	var game := FakeGame.new()
	var context := FakeWorldContext.new()
	var player := Node3D.new()
	var target := FakePony.new()
	target.name = "Rarity"
	target.set_meta("relationship_id", "rarity")
	var nav := FakeNavigator.new()
	nav.name = "Navigator"
	target.add_child(nav)
	var runtime := FakeRuntime.new()
	runtime.pony = target
	var eligibility := FakeEligibility.new()
	var adapter := FakeAdapter.new()
	var privacy := FakePrivacy.new()
	game.world_context = context
	game.mares = [target]
	main.player = player
	main.game = game
	main.eligibility = eligibility
	main.runtimes[target] = runtime
	main.offer_target_value = target
	for node: Node in [game, player, target, runtime, adapter]:
		root.add_child(node)
	root.add_child(main)
	var service := INIT.new()
	service.name = "UnfplapInitiation"
	service.call("setup", main, privacy, adapter)
	root.add_child(service)
	return {"main": main, "game": game, "context": context, "player": player,
		"target": target, "nav": nav, "runtime": runtime, "eligibility": eligibility,
		"adapter": adapter, "privacy": privacy, "service": service}


func _free(made: Dictionary) -> void:
	for key: String in ["service", "main", "game", "player", "target", "runtime", "adapter"]:
		var node: Node = made[key]
		root.remove_child(node)
		node.free()


func _debug_count(main: FakeMain, text: String) -> int:
	var count := 0
	for line: String in main.debug_lines:
		if line == text:
			count += 1
	return count


func run() -> void:
	_check_force()
	_check_clearance_and_options()
	_check_reasoning()
	_check_handoff_failure()
	_check_cuddle()
	_check_outcome_and_reset()
	_check_scan_logs()
	print("INITIATION_API_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("INITIATION_API_PASS")
	quit(0 if failures == 0 else 1)


func _check_force() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var runtime: FakeRuntime = made["runtime"]
	var main: FakeMain = made["main"]
	var nav: FakeNavigator = made["nav"]
	var context: FakeWorldContext = made["context"]
	var adapter: FakeAdapter = made["adapter"]
	var target: FakePony = made["target"]
	target.global_position = Vector3.ZERO
	var forced: INIT.ForceResult = service.force(runtime, CATALOG.STANDING)
	check(forced.ok, "force starts a standing offer")
	check(forced.id == "rarity" and forced.pose == CATALOG.STANDING,
		"the force result names the mare and the pose")
	check(nav.command_owner == "unfplap:request:rarity",
		"the ask owns the navigator")
	check(not nav.wander_enabled and not nav._has_target, "the ask holds her still")
	check(not main.offer.is_empty(), "the offer is handed to the negotiation")
	check(str(main.offer.get("hold_token", "")) == "unfplap:request:rarity",
		"the handoff carries the request lease")
	check(bool(main.offer.get("private", false)), "a quiet house forms a private offer")
	check(bool(main.offer.get("cuddle", true)) == false, "a standing offer is not a cuddle")
	check(adapter.greetings.size() == 1 and adapter.greetings[0][0] == "rarity",
		"the ask line opens with the greeting")
	check(adapter.situations.size() == 1 and adapter.situations[0]["key"].ends_with(":situation"),
		"the ask records one situation")
	check(service.debug_rows(target).size() > 0, "the request rows render")
	# The negotiation owns the lease after the handoff; the fake negotiator ends it here.
	check(nav.command_owner == "unfplap:request:rarity",
		"a handed-off ask leaves the lease to the negotiation")
	nav.command_owner = ""
	nav.wander_enabled = true

	# A fallback queue path when the greeting cannot open the line.
	service.reset()
	check(nav.command_owner.is_empty() and nav.wander_enabled,
		"reset leaves the released lease untouched")
	adapter.greeting_ok = false
	adapter.queued.clear()
	var asked: INIT.ForceResult = service.force(runtime, CATALOG.STANDING)
	check(asked.ok, "force still asks without a greeting")
	check(adapter.queued.size() == 1 and str(adapter.queued[0][2]).ends_with(":ask"),
		"the fallback ask key names the request")
	adapter.greeting_ok = true

	# A distant Anon starts the walk, not the ask.
	service.reset()
	nav.command_owner = ""
	nav.wander_enabled = true
	adapter.greetings.clear()
	adapter.queued.clear()
	target.global_position = Vector3(10.0, 0.0, 0.0)
	var walking: INIT.ForceResult = service.force(runtime, CATALOG.STANDING)
	check(walking.ok, "force starts a distant walk")
	check(nav.command_owner.begins_with("unfplap:request:rarity") and nav._has_target,
		"the walk owns the navigator and has a route")
	check(adapter.greetings.is_empty() and adapter.queued.is_empty(),
		"a distant walk has not asked yet")
	target.global_position = Vector3(2.0, 0.0, 0.0)
	service.tick(0.0)
	check(not nav._has_target, "arriving stops the walk")
	check(adapter.greetings.is_empty(), "the arrival still settles")
	_free(made)


func _check_clearance_and_options() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var runtime: FakeRuntime = made["runtime"]
	var eligibility: FakeEligibility = made["eligibility"]
	var main: FakeMain = made["main"]
	eligibility.relationship = false
	var rejected: INIT.ForceResult = service.force(runtime, CATALOG.STANDING)
	check(not rejected.ok and rejected.reject.contains("clearance:relationship"),
		"a failed Base clearance rejects the offer")
	eligibility.relationship = true
	runtime.state = 1
	var busy: INIT.ForceResult = service.force(runtime)
	check(not busy.ok and busy.reject.contains("state=1"), "force reports the runtime state")
	runtime.state = 0
	var missing: INIT.ForceResult = service.force(null)
	check(not missing.ok and missing.reject == "no_runtime", "force rejects a missing runtime")
	var internal_pose: INIT.ForceResult = service.force(runtime, CATALOG.STANDING_ORAL)
	check(not internal_pose.ok and internal_pose.reject.contains("pose:standing_oral"),
		"an internal pose is never offered")
	main.view.view = "vr"
	var vr_bed: INIT.ForceResult = service.force(runtime, CATALOG.MISSIONARY)
	check(not vr_bed.ok and vr_bed.reject.contains("pose:missionary"),
		"a pose the display cannot place is never offered")
	main.view.view = "desktop"
	runtime.hard_ok = false
	runtime.scene_reasons = ["affection"]
	var blocked: INIT.ForceResult = service.force(runtime, CATALOG.STANDING)
	check(not blocked.ok and blocked.reject.contains("scene:affection"),
		"a hard scene row rejects the formation")
	runtime.hard_ok = true
	_free(made)


func _check_reasoning() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var runtime: FakeRuntime = made["runtime"]
	var adapter: FakeAdapter = made["adapter"]
	var main: FakeMain = made["main"]
	var target: FakePony = made["target"]
	target.global_position = Vector3.ZERO
	adapter.reason_reply = "{\"offer\":false}"
	service.tick(0.5)
	check(adapter.reason_payloads.size() == 1, "the scan runs one reasoning call")
	var payload: Dictionary = adapter.reason_payloads[0]
	check((payload.get("options", []) as Array).size() == 1,
		"the scan sends the one placeable option")
	check((payload.get("context", {}) as Dictionary).get("willing") == true,
		"the reasoning payload carries Context")
	check(main.offer.is_empty(), "a no-offer reasoning forms nothing")

	service.reset()
	main.debug_lines.clear()
	adapter.reason_payloads.clear()
	service.tick(0.5)
	check(_debug_count(main, "request reasoning no id=rarity") == 1,
		"a reasoning no is logged and applies the pacing")

	# Clear the stamped cooldown so the next scan may reason again.
	service.clear_cooldown(target)
	adapter.reason_payloads.clear()
	adapter.reason_reply = "{\"offer\":true,\"option\":0}"
	service.tick(0.5)
	check(not main.offer.is_empty(), "a reasoning yes forms the offer")
	check(adapter.greetings.size() == 1, "the reasoning yes asks")
	_free(made)


func _check_handoff_failure() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var runtime: FakeRuntime = made["runtime"]
	var main: FakeMain = made["main"]
	var nav: FakeNavigator = made["nav"]
	var adapter: FakeAdapter = made["adapter"]
	main.handoff_ok = false
	var result: INIT.ForceResult = service.force(runtime, CATALOG.STANDING)
	check(not result.ok, "a refused handoff forms no offer")
	check(nav.command_owner.is_empty(), "a refused handoff releases the request lease")
	check(adapter.greetings.is_empty(), "a refused handoff speaks no ask line")
	check("\n".join(PackedStringArray(service.debug_rows(made["target"]))).contains("retry left="),
		"a refused handoff sets the short retry")
	_free(made)


func _check_cuddle() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var runtime: FakeRuntime = made["runtime"]
	var main: FakeMain = made["main"]
	var nav: FakeNavigator = made["nav"]
	var bed := Node3D.new()
	root.add_child(bed)
	runtime.cuddle = true
	runtime.bed_under = bed
	var result: INIT.ForceResult = service.force(runtime)
	check(result.ok, "a cuddle offer forms")
	check(bool(main.offer.get("cuddle", false)), "the handoff marks the cuddle")
	check(str(main.offer.get("hold_token", "x")).is_empty(),
		"the cuddle handoff carries no navigator lease")
	check(nav.command_owner.is_empty(), "the cuddle keeps the session's navigator")
	service.reset()
	root.remove_child(bed)
	bed.free()
	_free(made)


func _check_outcome_and_reset() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var target: FakePony = made["target"]
	var terminal := FakeTerminal.new()
	terminal.pony_id = "rarity"
	terminal.outcome = 2
	terminal.reason = ""
	terminal.cooldown_s = 120.0
	service.on_negotiation_outcome(terminal)
	check("\n".join(PackedStringArray(service.debug_rows(target))).contains("cooldown ready="),
		"the outcome updates the pacing rows")
	var retry := FakeTerminal.new()
	retry.pony_id = "rarity"
	retry.reason = "privacy"
	retry.cooldown_s = 0.0
	service.on_negotiation_outcome(retry)
	var rows := "\n".join(PackedStringArray(service.debug_rows(target)))
	check(rows.contains("retry left=") and not rows.contains("retry left=none"),
		"a no-cooldown outcome sets the short retry")
	check(not service.clear_cooldown(null), "clear_cooldown rejects a missing mare")
	check(service.clear_cooldown(target), "clear_cooldown accepts a known mare")
	_free(made)


func _check_scan_logs() -> void:
	var made := _fixture()
	var service: Node = made["service"]
	var adapter: FakeAdapter = made["adapter"]
	var main: FakeMain = made["main"]
	adapter.quiet_reason_value = "chat"
	service.tick(0.5)
	check(_debug_count(main, "request scan quiet reason=chat") == 1,
		"a recent chat logs one quiet reason")
	service.tick(0.5)
	check(_debug_count(main, "request scan quiet reason=chat") == 1,
		"the same quiet reason logs once")
	_free(made)
