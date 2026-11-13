extends SceneTree
## The per-act anatomy bridge: host callbacks, facts sync, action gates, aim/gaze, placement and
## the act/controller lifecycle.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_act_bridge.gd

const BRIDGE := preload("res://mods/unfplap/anatomy/act_bridge.gd")
const FACTS := preload("res://mods/unfplap/anatomy/facts.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

const STATE_IDLE := 0
const STATE_ACTIVE := 2
const STATE_CLIMAX := 3

var failures := 0
var checks := 0


class FakeAct extends Node:
	var oral := false
	var pull_out := false
	var toggles: Array[String] = []
	var withdraws := 0
	var climaxes := 0
	var finishes := 0
	var afterglow_ticks := 0
	var ends := 0
	var teardowns := 0
	var facing_value: Variant = null
	var normal: Variant = Vector3.ZERO
	var point: Variant = Vector3.ZERO
	var rear: Variant = Vector3.ZERO
	var pose_configs: Array = []

	func pose_config(cfg: Dictionary) -> void:
		pose_configs.append(cfg)

	func toggle_hole(_state: int) -> void:
		toggles.append("hole")

	func toggle_oral(_state: int) -> void:
		toggles.append("oral")

	func toggle_finish(_state: int) -> void:
		toggles.append("finish")

	func oral_active() -> bool:
		return oral

	func pull_out_selected() -> bool:
		return pull_out

	func withdraw() -> void:
		withdraws += 1

	func on_climax() -> void:
		climaxes += 1

	func on_finish() -> void:
		finishes += 1

	func afterglow_tick(_delta: float, _facts: Variant) -> void:
		afterglow_ticks += 1

	func facing() -> Variant:
		return facing_value

	func opening_normal() -> Variant:
		return normal

	func hole_point() -> Variant:
		return point

	func hole_rear() -> Variant:
		return rear

	func end() -> void:
		ends += 1

	func teardown() -> void:
		teardowns += 1


class FakeController extends Node:
	var refreshes := 0
	var live := 0
	var reacts := 0
	var ends := 0
	var detaches := 0

	func refresh() -> void:
		refreshes += 1

	func apply_live() -> void:
		live += 1

	func react() -> void:
		reacts += 1

	func end_act() -> void:
		ends += 1

	func detach() -> void:
		detaches += 1


class FakeReactions extends RefCounted:
	var bindings: Array = []

	func bind_scene(pony_node: Variant, controller: Variant) -> void:
		bindings.append([pony_node, controller])


class FakeService extends RefCounted:
	var detaches := 0

	func detach_controller(_pony: Variant) -> void:
		detaches += 1

	func controller_for(_pony: Variant, _runtime: Variant) -> Variant:
		return null

	func eligible(_pony: Variant, _target: int) -> bool:
		return true


class FakeMissionaryAnon extends Node:
	var installed: Variant = null
	var applied := 0

	func install(context: Variant) -> bool:
		installed = context
		return true

	func apply(_frame: Transform3D, _body_scale: float) -> void:
		applied += 1


class FakeHost extends RefCounted:
	var values: Dictionary = {}
	var state := STATE_IDLE
	var pose_id := ""
	var depth := 0.0
	var penetration := 0.0
	var reach := 0.2
	var climaxes := 0
	var size := 1.0
	var pace := 1.0
	var fluid := 0.0
	var bed: Variant = null
	var cycle := "normal"
	var facing_calls: Array = []
	var camera_calls := 0
	var statuses: Array = []
	var thrusts: Array = []
	var penetration_values: Array = []

	func call_host(key: String) -> Variant:
		match key:
			"state":
				return state
			"pose_id":
				return pose_id
			"depth":
				return depth
			"penetration_m":
				return penetration
			"penetration_reach":
				return reach
			"climaxes":
				return climaxes
			"size_scale":
				return size
			"auto_pace":
				return pace
			"fluid_ground_y":
				return fluid
			"cycle_phase":
				return cycle
			"bed_frame":
				return bed
		return values.get(key, null)

	func anatomy_facing(basis: Basis, amount: float) -> void:
		facing_calls.append([basis, amount])

	func anatomy_status(text: String, seconds := 2.0) -> void:
		statuses.append([text, seconds])

	func thrust_move(amount: float, _now: float) -> void:
		thrusts.append(amount)

	func set_penetration_m(value: float) -> void:
		penetration_values.append(value)

	func camera() -> Variant:
		camera_calls += 1
		return null

	func now_s() -> float:
		return 0.0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _host(host: FakeHost, extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {
		"state": Callable(host, "call_host").bind("state"),
		"pose_id": Callable(host, "call_host").bind("pose_id"),
		"depth": Callable(host, "call_host").bind("depth"),
		"penetration_m": Callable(host, "call_host").bind("penetration_m"),
		"penetration_reach": Callable(host, "call_host").bind("penetration_reach"),
		"climaxes": Callable(host, "call_host").bind("climaxes"),
		"size_scale": Callable(host, "call_host").bind("size_scale"),
		"auto_pace": Callable(host, "call_host").bind("auto_pace"),
		"fluid_ground_y": Callable(host, "call_host").bind("fluid_ground_y"),
		"cycle_phase": Callable(host, "call_host").bind("cycle_phase"),
		"bed_frame": Callable(host, "call_host").bind("bed_frame"),
		"anatomy_facing": Callable(host, "anatomy_facing"),
		"status": Callable(host, "anatomy_status"),
		"thrust_move": Callable(host, "thrust_move"),
		"set_penetration_m": Callable(host, "set_penetration_m"),
		"missionary_camera": Callable(host, "camera"),
		"now_s": Callable(host, "now_s"),
	}
	out.merge(extra, true)
	return out


func run() -> void:
	_check_bind_and_facts()
	_check_gates()
	_check_action_reads()
	_check_vectors()
	_check_lifecycle()
	_check_host_callbacks()
	_check_vr()
	print("ANATOMY_ACT_BRIDGE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ANATOMY_ACT_BRIDGE_PASS")
	quit(0 if failures == 0 else 1)


func _check_bind_and_facts() -> void:
	var host := FakeHost.new()
	var bridge: RefCounted = BRIDGE.new()
	bridge.bind(_host(host))
	check(bridge.facts is FACTS, "the bridge owns the typed facts")
	check(bridge.available() == false, "no controller starts unavailable")
	check(bridge.act_available() == false, "no act starts unavailable")
	host.state = STATE_ACTIVE
	host.pose_id = CATALOG.STANDING
	host.depth = 0.5
	host.penetration = 0.1
	host.climaxes = 2
	host.size = 1.2
	host.pace = 1.5
	host.fluid = 0.3
	host.cycle = "heat"
	host.bed = "bed"
	var facts: RefCounted = bridge.context()
	check(facts.state == STATE_ACTIVE, "context writes the state")
	check(facts.pose_id == CATALOG.STANDING, "context writes the pose")
	check(is_equal_approx(facts.depth, 0.5), "context writes the depth")
	check(is_equal_approx(facts.penetration_m, 0.1), "context writes the penetration")
	check(facts.climaxes == 2, "context writes the climax count")
	check(is_equal_approx(facts.size_scale, 1.2), "context writes the size scale")
	check(is_equal_approx(facts.auto_pace, 1.5), "context writes the auto pace")
	check(is_equal_approx(facts.fluid_ground_y, 0.3), "context writes the fluid ground")
	check(facts.cycle_phase == "heat", "context writes the cycle phase")
	check(facts.bed_frame == "bed", "context writes the bed frame")


func _check_gates() -> void:
	var host := FakeHost.new()
	var bridge: RefCounted = BRIDGE.new()
	bridge.bind(_host(host))
	host.state = STATE_ACTIVE
	host.pose_id = CATALOG.STANDING
	var act := FakeAct.new()
	bridge.act = act
	check(bridge.act_available(), "an assigned act is available")

	# The three action gates are feature-gated; the test turns them on and restores them after.
	var holes_on := SETTINGS.anatomy_holes.get_bool()
	var oral_on := SETTINGS.anatomy_oral.get_bool()
	var finish_on := SETTINGS.anatomy_finish.get_bool()
	SETTINGS.anatomy_holes.set_bool(true)
	SETTINGS.anatomy_oral.set_bool(true)
	SETTINGS.anatomy_finish.set_bool(true)
	act.oral = false
	check(bridge.oral_ready(), "oral is ready in standing active")
	check(bridge.hole_ready(), "hole is ready in standing active")
	check(bridge.finish_ready(), "finish is ready in active")
	check(bridge.actions_ready(), "any live gate opens the action set")
	act.oral = true
	check(not bridge.hole_ready(), "oral blocks the hole gate")
	host.state = STATE_IDLE
	check(not bridge.oral_ready(), "oral is not ready outside active")
	check(not bridge.finish_ready(), "finish is not ready outside active")
	check(not bridge.actions_ready(), "no live gate closes the action set")
	act.oral = false
	bridge.toggle_hole()
	bridge.toggle_oral()
	bridge.toggle_finish()
	check(act.toggles == ["hole", "oral", "finish"], "the toggles reach the act")
	SETTINGS.anatomy_holes.set_bool(holes_on)
	SETTINGS.anatomy_oral.set_bool(oral_on)
	SETTINGS.anatomy_finish.set_bool(finish_on)
	act.free()
	bridge.act = null
	bridge.bind(_host(host))


func _check_action_reads() -> void:
	var host := FakeHost.new()
	var bridge: RefCounted = BRIDGE.new()
	bridge.bind(_host(host))
	var act := FakeAct.new()
	bridge.act = act
	act.oral = true
	check(bridge.oral_active(), "oral active reads the act")
	act.oral = false
	check(not bridge.oral_active(), "oral inactive reads the act")
	act.pull_out = true
	check(bridge.finish_pull_out(), "pull out reads the act")
	bridge.withdraw()
	bridge.on_climax()
	bridge.on_finish()
	bridge.afterglow_tick(0.1)
	check(act.withdraws == 1, "withdraw reaches the act")
	check(act.climaxes == 1, "on_climax reaches the act")
	check(act.finishes == 1, "on_finish reaches the act")
	check(act.afterglow_ticks == 1, "afterglow_tick reaches the act")
	act.free()
	bridge.act = null


func _check_vectors() -> void:
	var host := FakeHost.new()
	var bridge: RefCounted = BRIDGE.new()
	bridge.bind(_host(host))
	var act := FakeAct.new()
	bridge.act = act
	act.normal = Vector3(0.0, 0.0, 1.0)
	act.point = Vector3(1.0, 2.0, 3.0)
	act.rear = Vector3(0.0, 0.0, -1.0)
	check(bridge.normal() == Vector3(0.0, 0.0, 1.0), "normal reads the act")
	check(bridge.opening() == Vector3(1.0, 2.0, 3.0), "opening reads the act")
	check(bridge.rear() == Vector3(0.0, 0.0, -1.0), "rear reads the act")
	act.normal = "bad"
	act.point = "bad"
	act.rear = "bad"
	check(bridge.normal() == Vector3.ZERO, "a bad normal is zero")
	check(bridge.opening() == Vector3.ZERO, "a bad opening is zero")
	check(bridge.rear() == Vector3.ZERO, "a bad rear is zero")
	act.free()
	bridge.act = null


func _check_lifecycle() -> void:
	var host := FakeHost.new()
	var controller := FakeController.new()
	var bridge: RefCounted = BRIDGE.new()
	bridge.bind(_host(host, {"reactions": Callable()}))
	bridge.controller = controller
	check(bridge.available(), "a controller is available")
	bridge.apply_live()
	check(controller.live == 1, "apply_live reaches the controller")
	bridge.react()
	check(controller.reacts == 1, "react reaches the controller")
	var act := FakeAct.new()
	bridge.act = act
	bridge.pose_config({"a": 1})
	check(act.pose_configs.size() == 1, "pose_config reaches the per-act handle")
	bridge.act = null
	bridge.pose_config({"b": 2})
	check(act.pose_configs.size() == 1, "pose_config without an act is a no-op")
	bridge.act = act
	bridge.end()
	check(controller.ends == 1, "end closes the controller act")
	check(act.ends == 0, "the controller owns the act close")
	check(not bridge.act_available(), "end clears the act handle")
	controller.free()
	bridge.controller = null
	host.values["main"] = null
	var line: String = bridge.place("text")
	check(line == "Anatomy is not attached.", "place without a controller reports it")
	var direct := FakeAct.new()
	bridge.act = direct
	bridge.end()
	check(direct.ends == 1 and direct.teardowns == 1, "with no controller the bridge closes the act")


## The host callbacks that take arguments are raw callables, not zero-argument value reads: the
## reactions scene bind, the standing facing override, the status label and the missionary body.
func _check_host_callbacks() -> void:
	var host := FakeHost.new()
	var reactions := FakeReactions.new()
	var service := FakeService.new()
	var missionary := FakeMissionaryAnon.new()
	var pony := Node3D.new()
	root.add_child(pony)
	var act_facts := FACTS.new()
	host.values["pony"] = pony
	host.values["reactions"] = reactions
	host.values["anatomy_service"] = service
	host.values["eligibility_service"] = service
	host.values["act_facts"] = act_facts
	var bridge: RefCounted = BRIDGE.new()
	bridge.bind(_host(host, {
		"pony": Callable(host, "call_host").bind("pony"),
		"reactions": Callable(host, "call_host").bind("reactions"),
		"anatomy_service": Callable(host, "call_host").bind("anatomy_service"),
		"eligibility_service": Callable(host, "call_host").bind("eligibility_service"),
		"act_facts": Callable(host, "call_host").bind("act_facts"),
	}))
	bridge.refresh()
	check(reactions.bindings.size() == 1, "the refresh binds the reactions scene")
	if not reactions.bindings.is_empty():
		check(reactions.bindings[0][0] == pony, "the reactions facade receives her node")
	bridge.facing(Basis.IDENTITY, 0.5)
	check(host.facing_calls.size() == 1, "the standing facing override reaches the host")
	if not host.facing_calls.is_empty():
		check(is_equal_approx(float(host.facing_calls[0][1]), 0.5),
			"the facing override carries its amount")
	bridge.status("Anatomy", 1.5)
	check(host.statuses.size() == 1, "the status label reaches the host")
	if not host.statuses.is_empty():
		check(str(host.statuses[0][0]) == "Anatomy", "the status carries its text")
	bridge.set_missionary_anon(missionary)
	check(bridge.install_missionary_anon(), "the missionary body installs")
	check(missionary.installed == act_facts, "the missionary body receives the typed act view")
	bridge.set_missionary_anon(null)
	missionary.free()
	root.remove_child(pony)
	pony.free()


func _check_vr() -> void:
	var host := FakeHost.new()
	var bridge: RefCounted = BRIDGE.new()
	bridge.bind(_host(host))
	host.state = STATE_ACTIVE
	host.depth = 0.4
	host.reach = 0.2
	bridge.vr_depth(0.8)
	check(host.thrusts.size() == 1, "vr_depth feeds the thrust move")
	check(host.penetration_values.size() == 1, "vr_depth writes the penetration")
	check(is_equal_approx(host.penetration_values[0], 0.08), "vr_depth scales the depth")
	host.state = STATE_IDLE
	bridge.vr_depth(0.2)
	check(host.thrusts.size() == 1, "vr_depth ignores a non-act state")
