extends SceneTree
## The per-act anatomy bridge: host callbacks, facts sync, action gates, aim/gaze, placement and
## the act/controller lifecycle.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_act_bridge.gd

const BRIDGE := preload("res://mods/unfplap/anatomy/act_bridge.gd")
const ACT_HOST := preload("res://mods/unfplap/anatomy/act_host.gd")
const FACTS := preload("res://mods/unfplap/anatomy/facts.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

const STATE_IDLE := 0
const STATE_ACTIVE := 2
const STATE_CLIMAX := 3

var failures := 0
var checks := 0


class FakeAct extends Node:
	var toggles: Array[String] = []
	var climaxes := 0
	var afterglow_ticks := 0
	var ends := 0
	var teardowns := 0
	var hold_mouths := 0
	var normal: Variant = Vector3.ZERO
	var point: Variant = Vector3.ZERO
	var rear: Variant = Vector3.ZERO
	var mouth: Variant = Vector3(0.0, 1.2, 0.4)
	var visemes: Array[String] = []

	func toggle_hole(_state: int) -> void:
		toggles.append("hole")

	func hold_oral_mouth() -> void:
		hold_mouths += 1

	func set_oral_viseme(letter: String) -> void:
		visemes.append(letter)

	func oral_mouth_point() -> Variant:
		return mouth

	func on_climax() -> void:
		climaxes += 1

	func afterglow_tick(_delta: float, _facts: Variant) -> void:
		afterglow_ticks += 1

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
	var refreshes := 0
	var removed := 0
	var active := true
	var mouth: Variant = Vector3(0.0, 1.1, 0.2)

	func refresh_palm() -> void:
		refreshes += 1

	func mouth_point() -> Variant:
		return mouth

	func diag_row(_face: Vector3, _vulva: Vector3) -> String:
		return "body"

	func remove() -> void:
		removed += 1


class FakeHost extends RefCounted:
	var values: Dictionary = {}
	var state := STATE_IDLE
	var pose_view: Variant = null
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
			"pose_view":
				return pose_view
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


## The pose read model the anatomy context mirrors.
func _view(family: String) -> RefCounted:
	var view: RefCounted = VIEW.new()
	view.family = family
	return view


func _host(host: FakeHost, extra: Dictionary = {}) -> ACT_HOST:
	var out := ACT_HOST.new()
	out.state_cb = Callable(host, "call_host").bind("state")
	out.pose_view_cb = Callable(host, "call_host").bind("pose_view")
	out.depth_cb = Callable(host, "call_host").bind("depth")
	out.penetration_m_cb = Callable(host, "call_host").bind("penetration_m")
	out.penetration_reach_cb = Callable(host, "call_host").bind("penetration_reach")
	out.climaxes_cb = Callable(host, "call_host").bind("climaxes")
	out.size_scale_cb = Callable(host, "call_host").bind("size_scale")
	out.auto_pace_cb = Callable(host, "call_host").bind("auto_pace")
	out.fluid_ground_y_cb = Callable(host, "call_host").bind("fluid_ground_y")
	out.cycle_phase_cb = Callable(host, "call_host").bind("cycle_phase")
	out.bed_frame_cb = Callable(host, "call_host").bind("bed_frame")
	out.status_cb = Callable(host, "anatomy_status")
	out.thrust_move_cb = Callable(host, "thrust_move")
	out.set_penetration_m_cb = Callable(host, "set_penetration_m")
	out.missionary_camera_cb = Callable(host, "camera")
	out.now_s_cb = Callable(host, "now_s")
	for key: String in extra:
		match key:
			"pony":
				out.pony_cb = extra[key]
			"runtime":
				out.runtime_cb = extra[key]
			"reactions":
				out.reactions_cb = extra[key]
			"anatomy_service":
				out.anatomy_service_cb = extra[key]
			"eligibility_service":
				out.eligibility_service_cb = extra[key]
			"vr_scene":
				out.vr_scene_cb = extra[key]
	return out


func run() -> void:
	_check_bind_and_facts()
	_check_gates()
	_check_action_reads()
	_check_face()
	_check_vectors()
	_check_lifecycle()
	_check_host_callbacks()
	_check_vr()
	_check_vr_start()
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
	host.pose_view = _view("standing")
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
	check(is_same(facts.pose_view, host.pose_view), "context writes the pose view")
	check(is_equal_approx(facts.depth, 0.5), "context writes the depth")
	check(is_equal_approx(facts.penetration_m, 0.1), "context writes the penetration")
	check(facts.climaxes == 2, "context writes the climax count")
	check(is_equal_approx(facts.size_scale, 1.2), "context writes the size scale")
	check(is_equal_approx(facts.auto_pace, 1.5), "context writes the auto pace")
	check(is_equal_approx(facts.fluid_ground_y, 0.3), "context writes the fluid ground")
	check(facts.cycle_phase == "heat", "context writes the cycle phase")
	check(facts.bed_frame == "bed", "context writes the bed frame")
	var contact: Variant = _view("standing")
	contact.contact_kind = "mouth"
	bridge.pose_changed(contact)
	check(bridge.contact_family == "standing" and bridge.contact_kind == "mouth",
		"the pose change carries the contact family and kind")


func _check_gates() -> void:
	var host := FakeHost.new()
	var bridge: RefCounted = BRIDGE.new()
	bridge.bind(_host(host))
	host.state = STATE_ACTIVE
	host.pose_view = _view("standing")
	var act := FakeAct.new()
	bridge.act = act
	check(bridge.act_available(), "an assigned act is available")

	# The action gates are feature-gated; the test turns them on and restores them after.
	var holes_on := SETTINGS.anatomy_holes.get_bool()
	var oral_on := SETTINGS.anatomy_oral.get_bool()
	SETTINGS.anatomy_holes.set_bool(true)
	SETTINGS.anatomy_oral.set_bool(true)
	host.pose_view = _view("standing")
	check(bridge.oral_ready(), "oral is ready in standing active")
	check(bridge.hole_ready(), "hole is ready in standing active")
	check(bridge.actions_ready(), "any live gate opens the action set")
	host.pose_view.contact_kind = "mouth"
	check(not bridge.hole_ready(), "the mouth contact blocks the hole gate")
	host.pose_view.contact_kind = "opening"
	host.state = STATE_IDLE
	check(not bridge.oral_ready(), "oral is not ready outside active")
	check(not bridge.actions_ready(), "no live gate closes the action set")
	bridge.toggle_hole()
	check(act.toggles == ["hole"], "the toggle reaches the act")
	SETTINGS.anatomy_holes.set_bool(holes_on)
	SETTINGS.anatomy_oral.set_bool(oral_on)
	act.free()
	bridge.act = null
	bridge.bind(_host(host))


func _check_action_reads() -> void:
	var host := FakeHost.new()
	var bridge: RefCounted = BRIDGE.new()
	bridge.bind(_host(host))
	var act := FakeAct.new()
	bridge.act = act
	bridge.hold_oral_mouth()
	check(act.hold_mouths == 1, "hold_oral_mouth reaches the act")
	bridge.set_oral_viseme("D")
	bridge.set_oral_viseme("")
	check(act.visemes == ["D", ""], "the viseme event reaches the act")
	check(bridge.mouth_point().is_equal_approx(Vector3(0.0, 1.2, 0.4)),
		"the bridge exposes the provider's mouth point")
	bridge.on_climax()
	bridge.afterglow_tick(0.1)
	check(act.climaxes == 1, "on_climax reaches the act")
	check(act.afterglow_ticks == 1, "afterglow_tick reaches the act")
	bridge.act = null
	check(bridge.mouth_point() == Vector3.ZERO, "no act returns no mouth point")
	act.free()


## The face contact's provider and gates: the act body's authored mouth is the anchor, and a face
## view refuses the hole and finish actions until the contact returns to the opening.
func _check_face() -> void:
	var host := FakeHost.new()
	var bridge: RefCounted = BRIDGE.new()
	bridge.bind(_host(host))
	check(bridge.face_point() == Vector3.INF, "no body has no face point")
	var body := FakeMissionaryAnon.new()
	bridge.set_missionary_anon(body)
	check(bridge.face_point().is_equal_approx(body.mouth as Vector3),
		"the face point is the act body's mouth")
	body.active = false
	check(bridge.face_point() == Vector3.INF, "an inactive body has no face point")
	body.active = true
	body.mouth = Vector3(INF, 0.0, 0.0)
	check(bridge.face_point() == Vector3.INF, "a non-finite face point is INF")
	body.mouth = Vector3(0.0, 1.1, 0.2)
	host.state = STATE_ACTIVE
	host.pose_view = _view("bed")
	var act := FakeAct.new()
	bridge.act = act
	var holes_on := SETTINGS.anatomy_holes.get_bool()
	SETTINGS.anatomy_holes.set_bool(true)
	host.pose_view.contact_kind = "face"
	check(not bridge.hole_ready(), "the face contact blocks the hole gate")
	host.pose_view.contact_kind = "opening"
	check(bridge.hole_ready(), "the opening contact restores the hole gate")
	SETTINGS.anatomy_holes.set_bool(holes_on)
	bridge.act = null
	bridge.set_missionary_anon(null)
	check(bridge.face_point() == Vector3.INF, "a cleared body has no face point")
	act.free()
	body.free()


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
	host.pose_view = _view("bed")
	bridge.apply_live()
	check(controller.live == 1, "apply_live reaches the controller")
	check(bridge.facts.pose_view != null and bridge.facts.pose_view.family == "bed",
		"apply_live refreshes the pose view before the controller reads it")
	host.pose_view = null
	bridge.apply_live()
	check(controller.live == 2, "apply_live reaches the controller again")
	check(bridge.facts.pose_view == null,
		"the end-of-act refresh clears the pose view the controller sees")
	bridge.react()
	check(controller.reacts == 1, "react reaches the controller")
	var act := FakeAct.new()
	bridge.act = act
	bridge.end()
	check(controller.ends == 1, "end closes the controller act")
	check(act.ends == 0, "the controller owns the act close")
	check(not bridge.act_available(), "end clears the act handle")
	controller.free()
	bridge.controller = null
	host.values["main"] = null
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
	host.values["pony"] = pony
	host.values["reactions"] = reactions
	host.values["anatomy_service"] = service
	host.values["eligibility_service"] = service
	var bridge: RefCounted = BRIDGE.new()
	bridge.bind(_host(host, {
		"pony": Callable(host, "call_host").bind("pony"),
		"reactions": Callable(host, "call_host").bind("reactions"),
		"anatomy_service": Callable(host, "call_host").bind("anatomy_service"),
		"eligibility_service": Callable(host, "call_host").bind("eligibility_service"),
	}))
	bridge.refresh()
	check(reactions.bindings.size() == 1, "the refresh binds the reactions scene")
	if not reactions.bindings.is_empty():
		check(reactions.bindings[0][0] == pony, "the reactions facade receives her node")
	bridge.status("Anatomy", 1.5)
	check(host.statuses.size() == 1, "the status label reaches the host")
	if not host.statuses.is_empty():
		check(str(host.statuses[0][0]) == "Anatomy", "the status carries its text")
	bridge.set_missionary_anon(missionary)
	bridge.refresh_palm()
	check(missionary.refreshes == 1, "the bridge refreshes the opaque palm scale")
	check(bridge.diag_row(Vector3.ZERO, Vector3.ZERO) == "body",
		"the bridge reads the opaque diagnostic row")
	check(bridge.missionary_anon_body() == missionary, "the bridge exposes the opaque handle")
	bridge.end()
	check(missionary.removed == 1, "the bridge restores the service-owned body")
	check(is_instance_valid(missionary) and missionary.get_parent() == null,
		"the bridge never frees the handle it was given")
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


## The bridge wires the VR controller from the runtime's scene dictionary; it never searches the
## player scene itself.
func _check_vr_start() -> void:
	var host := FakeHost.new()
	var bridge: RefCounted = BRIDGE.new()
	var runtime := Node.new()
	root.add_child(runtime)
	var player := Node3D.new()
	var avatar := Node3D.new()
	avatar.name = "AnonBody"
	var camera := XRCamera3D.new()
	var origin := XROrigin3D.new()
	player.add_child(avatar)
	player.add_child(camera)
	player.add_child(origin)
	root.add_child(player)
	host.values["runtime"] = runtime
	var scene := {
		"player": player,
		"avatar": avatar,
		"camera": camera,
		"origin": origin,
		"hip_target": null,
	}
	bridge.bind(_host(host, {
		"runtime": Callable(host, "call_host").bind("runtime"),
		"vr_scene": func() -> Variant: return scene,
	}))
	bridge.vr_start()
	check(is_instance_valid(bridge.vr_act), "vr_start builds the controller from the host scene")
	if is_instance_valid(bridge.vr_act):
		check(bridge.vr_act.get("player") == player, "the controller receives the player")
		check(bridge.vr_act.get("camera") == camera, "the controller receives the camera")
		check(bridge.vr_act.get("origin") == origin, "the controller receives the origin")
		check(bridge.vr_act.get_parent() == runtime, "the runtime parents the controller")
	bridge.vr_stop()
	check(not is_instance_valid(bridge.vr_act), "vr_stop drops the controller")
	bridge.bind(_host(host))
	bridge.vr_start()
	check(not is_instance_valid(bridge.vr_act), "a missing scene builds no controller")
	runtime.free()
	player.free()
