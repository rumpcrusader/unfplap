extends SceneTree
## The generic body-swap handover: suspend an act, adopt the runtime on a new body with the same
## stable id, rebuild the pose and resume, and keep `_end_session()` the only exit.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/handover/test_body_swap.gd
##
## The registry, the pending swap and the adoption are the real `ponies` service; only the
## runtime's host handle and the body-change service are faked here, because `main.gd` itself
## names the `Mods` autoload, which a `--script` suite cannot load.

const WORLD := preload("res://mods/unfplap/world/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const HYBRID_NEAR_MESH := preload("res://world/characters/hybrid_mare/hybrid_near_mesh.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const SUMMARY := preload("res://mods/unfplap/summary/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_CHANGE_SERVICE := preload("res://mods/unfplap/body_change/service.gd")
const BODY_CHANGE_ACT := preload("res://mods/unfplap/body_change/act.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")
const POLICY := preload("res://mods/unfplap/shared/body_change_policy.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")

var failures := 0
var checks := 0


class FakeIdentity extends Resource:
	var id := ""
	var display_name := ""


class FakeNav extends Node:
	var reserved_by := ""
	var command_owner := ""
	var wander_enabled := true

	func stay() -> void:
		pass


class FakePony extends Node3D:
	var identity: Variant = null
	var shading_version := 3
	var head_width := 1.0
	var head_width_factor := 1.0
	var reference_face_enabled := false
	var skeleton: Skeleton3D = null
	var posture: Variant = null
	var face_turn_rate := 0.45
	var sleeping := false
	var body_scale := 1.0
	var held := false
	var posture_requests: Array[String] = []

	func posture_status() -> Dictionary:
		return {"requested": "stand", "settled": true}

	func is_held() -> bool:
		return held

	func grounded() -> bool:
		return true

	func action_interruption_reason() -> String:
		return ""

	func request_posture(name: String) -> bool:
		posture_requests.append(name)
		return true

	func reset_motion(transform: Transform3D) -> void:
		global_transform = transform


class FakePlayer extends Node3D:
	var _stand_eye := 1.6
	var _eye_height := 1.6
	var seat: Variant = null
	var form_driver: Variant = null

	func eye_height() -> float:
		return _stand_eye

	func _set_eye_y(value: float) -> void:
		_stand_eye = value
		_eye_height = value


class FakeVocal extends Node:
	var _players: Dictionary = {}

	func play(_id: String, _kind: String, _at: Node3D, _volume_db := -30.0) -> bool:
		return false


class FakeSource extends "res://mods/unfplap/body_change/source.gd":
	var changing := false:
		set(value):
			changing = value
			if value:
				_ensure_change()
			else:
				_settle_change()
	var old_pony: Node = null
	var new_pony: Node = null:
		set(value):
			new_pony = value
			if change != null:
				change.next_body = value as Node3D
				_notify()
	var shape_id := ""
	var active_flag := true
	var shape := ""
	var form_name := ""
	var asks := false
	var named := ""
	var note := ""
	var true_requests := 0
	var shape_requests: Array[String] = []
	var poll_calls := 0
	var change: BODY_CHANGE = null
	var service: BODY_CHANGE_SERVICE = null
	var policy_value: POLICY = null

	func source_id() -> String:
		return "fake"

	func is_active() -> bool:
		return active_flag

	func handles_pony(_pony: Node3D) -> bool:
		return true

	func change_in_progress() -> bool:
		return changing

	func active_change() -> BODY_CHANGE:
		return change

	func target_form_id() -> String:
		return shape_id

	func presented_form_id(_body: Node3D) -> String:
		return shape.strip_edges()

	func policy() -> POLICY:
		return policy_value

	func claims_body(pony: Node3D) -> bool:
		return changing and is_instance_valid(new_pony) and pony == new_pony

	func poll() -> void:
		poll_calls += 1

	func asks_form_change(_text: String) -> bool:
		return asks

	func named_form(_text: String) -> String:
		return named

	func named_form_note(_text: String) -> String:
		return note

	func request_form(_body: Node3D, form_id: String, origin: BODY_CHANGE.Origin) -> bool:
		shape_requests.append(form_id)
		_begin(form_id, origin)
		return true

	func request_own_form(_body: Node3D, origin: BODY_CHANGE.Origin) -> bool:
		true_requests += 1
		_begin("", origin)
		shape = ""
		return true

	func prepare_body(body: Node3D, change: BODY_CHANGE) -> BODY_FORM.BodyForm:
		if change != null and change.state == BODY_CHANGE.State.REQUESTED:
			change.state = BODY_CHANGE.State.PREPARING
		var form := BODY_FORM.default_form(body)
		if change != null and not change.target_form_id.is_empty():
			form.form_id = change.target_form_id
			form.fit_id = change.target_form_id
		if not form_name.is_empty():
			form.form_name = form_name
		return form

	func _begin(form_id: String, origin: BODY_CHANGE.Origin) -> void:
		shape_id = form_id
		shape = form_id
		change = null
		changing = true
		if change != null:
			change.origin = origin
			_notify()

	func _ensure_change() -> void:
		var old_body: Node3D = old_pony as Node3D
		if change == null or change.state in [BODY_CHANGE.State.SETTLED, BODY_CHANGE.State.FAILED] \
				or change.previous_body != old_body:
			change = BODY_CHANGE.new()
			change.source = self
			change.origin = BODY_CHANGE.Origin.AI
			change.previous_body = old_body
			change.target_form_id = shape_id
			change.state = BODY_CHANGE.State.REQUESTED
		_notify()

	func _settle_change() -> void:
		if change == null or change.state in [BODY_CHANGE.State.SETTLED, BODY_CHANGE.State.FAILED]:
			return
		change.state = BODY_CHANGE.State.SETTLED if is_instance_valid(change.next_body) \
			else BODY_CHANGE.State.FAILED
		_notify()

	func _notify() -> void:
		if service != null:
			service.notify_source_changed(self)


## The provider's typed offer/reveal policy, with observable calls and a snapshot of the runtime's
## context. The runtime is the code under test; this is the provider side of the contract.
class FakePolicy extends "res://mods/unfplap/shared/body_change_policy.gd":
	var prompt := "Offer the shape."
	var heat := 30.0
	var peak := 150.0
	var cue := "She shows you the real her."
	var memory_kind := "form_reveal"
	var offer_calls := 0
	var prompt_calls := 0
	var accepted_calls := 0
	var reveal_calls := 0
	var events: Array[int] = []
	var last_offer: Dictionary = {}
	var last_accepted: Dictionary = {}
	var last_reveal: Dictionary = {}
	var last_event: Dictionary = {}

	func on_act_event(event: POLICY.ActEvent, context: POLICY.BodyChangeActContext) -> void:
		events.append(int(event))
		last_event = _snapshot(context)

	func should_offer(context: POLICY.BodyChangeActContext) -> bool:
		offer_calls += 1
		last_offer = _snapshot(context)
		return context.act_active and context.form != null and context.form.is_own() \
			and context.pony_climaxes >= 1 and not context.offer_pending \
			and not context.reveal_used

	func offer_prompt() -> String:
		prompt_calls += 1
		return prompt

	func on_offer_accepted(context: POLICY.BodyChangeActContext) -> POLICY.BodyChangeEffects:
		accepted_calls += 1
		last_accepted = _snapshot(context)
		return POLICY.BodyChangeEffects.new()

	func on_reveal(context: POLICY.BodyChangeActContext) -> POLICY.BodyChangeEffects:
		reveal_calls += 1
		last_reveal = _snapshot(context)
		var effects := POLICY.BodyChangeEffects.new()
		effects.heat = heat
		effects.peak = peak
		effects.cue = cue
		effects.memory_kind = memory_kind
		return effects

	func _snapshot(context: POLICY.BodyChangeActContext) -> Dictionary:
		return {
			"pony_id": context.pony_id,
			"own": context.form != null and context.form.is_own(),
			"has_change": context.change != null,
			"origin": int(context.origin),
			"state": int(context.state),
			"offer_pending": context.offer_pending,
			"reveal_used": context.reveal_used,
			"by_player": context.by_player,
			"pony_climaxes": context.pony_climaxes,
			"max_climaxes": context.max_climaxes,
			"act_active": context.act_active,
		}


class FakeMemory extends RefCounted:
	var impressions: Array = []
	var peaks: Array = []
	var notes: Array = []
	var lines: Array = []
	var _service: Variant = MEMORY.new()

	func form_reveal_impression(id: String, event_id: String) -> Variant:
		return _service.call("form_reveal_impression", id, event_id)

	func form_reveal_peak(id: String, event_id: String, score: float) -> Variant:
		return _service.call("form_reveal_peak", id, event_id, score)

	func commit(impression: Variant) -> void:
		impressions.append(impression)

	func record_peak(peak: Variant) -> void:
		peaks.append(peak)

	func note(kind: int, id: String, event_id: String) -> void:
		notes.append({"kind": kind, "id": id, "event_id": event_id})

	func cancel_act(_event_id: String, _keep_speaking := true) -> int:
		return 0

	func cancel_line(_key: String) -> void:
		pass

	func line_state(_key: String) -> int:
		return 0

	func cue_facts(_id: String, _event_id: String) -> MEMORY.CueFacts:
		return MEMORY.CueFacts.new()

	func line(request: MEMORY.LineRequest) -> MEMORY.Line:
		var out := MEMORY.Line.new()
		lines.append(request)
		out.key = "line:%d" % lines.size()
		out.queued = true
		return out

	func observers(_pony: Variant) -> Array:
		return []

	func witnesses(_id: String, _name: String, _serial: int, _pony: Variant) -> Array:
		return []


## The talk turn the player's line arrives on. The runtime reads the same director fields the
## readiness service reads.
class FakeDirector extends Node:
	var _turn_id := 0
	var _player_text := ""
	var state := "idle"

	func _ready() -> void:
		add_to_group("conversation_director")


class FakeEligibility extends ELIGIBILITY:
	var allow := true

	func eligible(_pony: Node, _target: ELIGIBILITY.Target = ELIGIBILITY.Target.ACT) -> bool:
		return allow


## The runtime's host handle: the scene services it reads and nothing the registry owns. The
## registry, the pending swap and the adoption are the real `ponies` service.
class FakeHost extends Node:
	var headset_view := false
	var eligibility: Variant = null
	var hud: Variant = null
	var player: Variant = null
	var game: Variant = null
	var anatomy: Variant = null
	var stock_smack: Variant = null
	var source: Variant = null
	var memory: Variant = null
	var body_change: Variant = null

	func camera() -> Camera3D:
		return null


## A service with only the player handshake: the body swap must clear the old body's offset even
## when no anatomy controller is available.
class FakePlayerAnatomy extends Node:
	var reset_calls := 0

	## The registry's two bind calls: a body takes a runtime and its tail is seated.
	func bind(_pony: Node, _runtime: Node) -> Node:
		return null

	func tail_ready(_pony: Node) -> void:
		pass

	func controller_for(_pony: Node, _runtime: Node) -> Node:
		return null

	func player_reset_pelvis() -> void:
		reset_calls += 1


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _pony(display_name: String, node_name := "Pony") -> FakePony:
	var pony := FakePony.new()
	pony.name = node_name
	var identity := FakeIdentity.new()
	identity.id = "test_mare"
	identity.display_name = display_name
	pony.identity = identity
	pony.skeleton = Skeleton3D.new()
	pony.skeleton.name = "Skeleton3D"
	pony.add_child(pony.skeleton)
	pony.posture = Node.new()
	pony.add_child(pony.posture)
	var nav := FakeNav.new()
	nav.name = "Navigator"
	pony.add_child(nav)
	return pony


## A live act without the start sequence: the handover is the code under test, not the gate. The
## old body joins the registry through the real attach path, before the body-change service exists,
## so the fixture keeps the act's form store empty like a running world does at spawn.
func _fixture() -> Dictionary:
	PONIES.shutdown()
	var host := FakeHost.new()
	host.name = "FakeHost"
	root.add_child(host)
	var old_pony := _pony("Test Mare", "OldBody")
	root.add_child(old_pony)
	var runtime: Node = RUNTIME.new()
	runtime.name = "UnfplapRuntime"
	runtime.pony = old_pony
	old_pony.add_child(runtime)
	runtime.act.pony_id = "test_mare"
	runtime.act.pony_id = "test_mare"
	runtime.act.display_name = "Test Mare"
	runtime.act.pose_id = CATALOG.STANDING
	runtime.act.source = "test"
	runtime.act._set_state(ACT_STATE.State.ACTIVE)
	runtime._bundle.readiness.depth = 0.42
	runtime._bundle.readiness.penetration_m = 0.11
	runtime._bundle.readiness.pony_climaxes = 1
	runtime.act.max_pony_climaxes = 3
	runtime.act.event_id = "intimacy_test_mare_1"
	runtime.act.serial = 1
	runtime.act.preferences = SETTINGS.preferences("test_mare")
	runtime.act.features = {}
	runtime._bundle.handover.set_form_hint_debug(true)
	WORLD.bind_world(host)
	MEMORY.instance = FakeMemory.new()
	PONIES.factory = func(_pony_node: Node) -> Node: return runtime
	PONIES.attach(old_pony)
	PONIES.set_active(runtime)
	var body_change := BODY_CHANGE_SERVICE.new()
	body_change.name = "FakeBodyChange"
	body_change.call("setup")
	host.add_child(body_change)
	host.body_change = body_change
	PONIES.body_change = body_change
	var source := FakeSource.new()
	source.name = "FakeSource"
	root.add_child(source)
	source.old_pony = old_pony
	source.service = body_change
	source.changing = false
	var policy := FakePolicy.new()
	source.policy_value = policy
	host.source = source
	body_change.call("register_source", source)
	# The service builds its own bindings from the facades the entry hands it; this fixture has
	# none, so the chain is the runtime and LOD links an idle or live act runs on.
	body_change.call("wire", null, null, null)
	return {"host": host, "runtime": runtime, "old": old_pony, "source": source,
		"body_change": body_change, "policy": policy}


func _free_fixture(made: Dictionary) -> void:
	var host: Variant = made["host"]
	var runtime: Variant = made["runtime"]
	var old: Variant = made["old"]
	var source: Variant = made["source"]
	PONIES.shutdown()
	if is_instance_valid(runtime) and not runtime.is_queued_for_deletion():
		runtime.free()
	if is_instance_valid(old):
		old.free()
	if is_instance_valid(source):
		source.free()
	if is_instance_valid(host):
		host.free()


func run() -> void:
	_check_observation()
	_check_handover()
	_check_auto_survives_swap()
	_check_vocal_cache()
	_check_form_display_name()
	_check_policy_events()
	_check_ai_change()
	_check_failed_change()
	_check_source_gone()
	_check_watchdog()
	_check_invalid_shape()
	_check_world_close()
	_check_form_reveal()
	_check_shape_offer()
	_check_named_shape_gate()
	_check_watchdog_with_body()
	_check_offer_gate()
	_check_no_player_hint()
	_check_hint_states()
	_check_failed_named_offer()
	_check_named_without_shape()
	_check_ai_change_keeps_offer()
	_check_late_adoption()
	_check_restore_change()
	_check_held_guard()
	_check_idle_body_binding()
	_check_same_node_refresh()
	_check_origins()
	print("BODY_SWAP_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


## The watcher reads the service at the existing cadence and never pumps the provider. The
## provider's own observation is the only pack read.
func _check_observation() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	source.poll_calls = 0
	runtime._bundle.handover.clock = 0.0
	runtime.act.swap.tick(0.1)
	check(not runtime.act.suspended(), "no change leaves the act live")
	check(source.poll_calls == 0, "the watcher never polls the provider")
	source.changing = true
	runtime._bundle.handover.clock = BODY_CHANGE_ACT.BODY_SWAP_POLL_S * 0.5
	runtime.act.swap.tick(BODY_CHANGE_ACT.BODY_SWAP_POLL_S * 0.1)
	check(not runtime.act.suspended(), "the watcher reads the change only at its cadence")
	runtime.act.swap.tick(BODY_CHANGE_ACT.BODY_SWAP_POLL_S)
	check(runtime.act.suspended(), "the announced change suspends on the cadence tick")
	check(PONIES.body_swap_pending(), "the suspend records one pending swap")
	runtime.act.swap.tick(0.1)
	check(PONIES.body_swap_pending(), "a suspended tick does not start a second handover")
	check(source.poll_calls == 0, "the suspended wait never polls the provider either")
	runtime.act.force_stop()
	_free_fixture(f)


## One complete suspend → adopt → resume, then the one exit.
func _check_handover() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	var source: FakeSource = f["source"]
	var anatomy := FakePlayerAnatomy.new()
	PONIES.anatomy = anatomy
	host.anatomy = anatomy

	source.changing = true
	runtime.act.swap.suspend(source.active_change())
	check(runtime.act.suspended(), "the act suspends")
	check(runtime.get_parent() == host, "the runtime leaves the old body for the host")
	check(PONIES.body_swap_pending(), "ponies records the pending swap")
	check(int(runtime.act.state) == ACT_STATE.State.ACTIVE, "the act state survives suspension")
	check(absf(float(runtime._bundle.readiness.depth) - 0.42) < 0.0001, "depth survives suspension")
	check(int(runtime._bundle.readiness.pony_climaxes) == 1, "climaxes survive suspension")
	check(str(runtime.act.event_id) == "intimacy_test_mare_1", "the event id survives suspension")

	var new_pony := _pony("New Mare", "NewBody")
	root.add_child(new_pony)
	source.new_pony = new_pony
	PONIES.attach(new_pony)
	runtime.act.swap.tick(0.1)
	check(not runtime.act.suspended(), "the new body resumes the act")
	check(anatomy.reset_calls >= 1, "the new body clears the part's old pelvis handshake")
	check(runtime.pony == new_pony, "the runtime owns the new body")
	check(runtime.get_parent() == new_pony, "the runtime moved under the new body")
	check(PONIES.runtime_for(new_pony) == runtime, "ponies maps the new body to the same runtime")
	check(PONIES.runtime_for(old_pony) == null, "the old body's map entry is gone")
	check(not PONIES.body_swap_pending(), "the pending swap is cleared")
	check(int(runtime.act.state) == ACT_STATE.State.ACTIVE, "the act state survives resume")
	check(absf(float(runtime._bundle.readiness.depth) - 0.42) < 0.0001, "depth survives resume")
	check(int(runtime._bundle.readiness.pony_climaxes) == 1, "climaxes survive resume")
	check(str(runtime.act.event_id) == "intimacy_test_mare_1", "the event id survives resume")
	check(str(runtime.act.display_name) == "New Mare", "the act takes the new display name")
	check(new_pony.has_meta("sex_active"), "the new body carries the act flag")
	var nav: FakeNav = new_pony.get_node("Navigator")
	check(nav.command_owner == "unfplap:test_mare", "the new navigator is claimed")
	check(runtime._bundle.pose.pony == new_pony, "the pose session binds the new body")
	var view: Variant = runtime._bundle.pose.view()
	check(view != null and str(view.id) == CATALOG.STANDING, "the pose is rebuilt at the act pose")
	check(runtime._bundle.pose.pose() != null and runtime._bundle.pose.basis_amount() > 0.99,
		"the rebuilt pose starts settled")

	runtime.act.force_stop()
	check(int(runtime.act.state) == ACT_STATE.State.IDLE, "the one exit ends the act")
	check(not PONIES.act_running(), "the one exit clears the active runtime")
	check(not new_pony.has_meta("sex_active"), "the one exit clears the new body's flag")
	check(runtime._bundle.hold.nav == null and runtime._bundle.hold.token.is_empty(),
		"the one exit gives up the act's navigator lease")
	_free_fixture(f)
	anatomy.free()


## A transform interrupts the automatic stroke for the new pose but keeps its live settings and
## resumes it on the adopted body at the same depth.
func _check_auto_survives_swap() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	runtime._bundle.readiness.configure_auto(1.5, 0.8, "cosine", 0.2)
	runtime._bundle.readiness.auto_thrust.pace = 2.75
	runtime._bundle.readiness.auto_thrust.min_depth = 0.3
	runtime._bundle.readiness.auto_thrust.max_depth = 0.7
	runtime._bundle.readiness.auto_set_shape("saw")
	runtime._bundle.readiness.toggle_auto(runtime._bundle.readiness.depth)
	check(runtime._bundle.readiness.auto_active(), "auto is on before the swap")
	source.changing = true
	runtime.act.swap.suspend(source.active_change())
	check(not runtime._bundle.readiness.auto_active(), "the swap interrupts the running stroke")
	var new_pony := _pony("Auto Mare", "AutoBody")
	root.add_child(new_pony)
	source.new_pony = new_pony
	PONIES.attach(new_pony)
	runtime.act.swap.tick(0.1)
	check(runtime._bundle.readiness.auto_active(), "auto resumes after the adopted body")
	check(absf(runtime._bundle.readiness.auto_pace() - 2.75) < 0.0001,
		"auto keeps its pace across the swap")
	check(absf(runtime._bundle.readiness.auto_min_depth() - 0.3) < 0.0001,
		"auto keeps its bottom depth across the swap")
	check(absf(runtime._bundle.readiness.auto_max_depth() - 0.7) < 0.0001,
		"auto keeps its peak depth across the swap")
	check(runtime._bundle.readiness.auto_shape() == "saw", "auto keeps its shape across the swap")
	check(not runtime._bundle.handover.auto_on, "the pending auto restore is cleared")
	_free_fixture(f)


## The base game's vocal cache must not keep a freed player from the old body. The audio facade
## clears only the act's stable id and leaves every valid entry alone.
func _check_vocal_cache() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	runtime.act.pony_id = "test_mare"
	runtime.act.pony_id = "test_mare"
	var audio: Node = runtime._bundle.audio.service()
	audio.bind(null, "test_mare", null)
	var vocal := FakeVocal.new()
	root.add_child(vocal)
	var freed := Node3D.new()
	vocal._players["test_mare"] = freed
	freed.free()
	var kept := Node3D.new()
	root.add_child(kept)
	vocal._players["kept"] = kept
	audio.prune_freed_vocal(vocal)
	check(not vocal._players.has("test_mare"), "a freed vocal cache entry is cleared")
	check(vocal._players.get("kept") == kept, "another id's valid player is left alone")
	vocal._players["test_mare"] = kept
	audio.prune_freed_vocal(vocal)
	check(vocal._players.has("test_mare"), "a valid cached player is kept")
	vocal.free()
	kept.free()
	_free_fixture(f)


## The presented form's name drives the act caption, not the identity's display name. The stable
## id and event stay the act's; an empty form name falls back to the identity display name.
func _check_form_display_name() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	var body_change: BODY_CHANGE_SERVICE = f["body_change"]
	source.form_name = "Borrowed Form"
	check(bool(runtime.act.request_form_change(false, "rarity", true).get("ok", false)),
		"a player-named borrowed form starts")
	runtime.act.swap.suspend(source.active_change())
	var new_pony := _pony("Identity Name", "BorrowedBody")
	root.add_child(new_pony)
	source.new_pony = new_pony
	source.shape = "rarity"
	PONIES.attach(new_pony)
	runtime.act.swap.tick(0.1)
	check(not runtime.act.suspended(), "the borrowed form resumes the act")
	check(str(runtime.act.display_name) == "Borrowed Form",
		"the act caption takes the presented form's name")
	check(str(runtime._bundle.facts.display_name) == "Borrowed Form",
		"the act facts carry the presented form's name")
	check(str(runtime.act.pony_id) == "test_mare", "the borrowed form keeps the stable pony id")
	check(str(runtime.act.event_id) == "intimacy_test_mare_1",
		"the borrowed form keeps the act's event id")
	var stored := body_change.form_for(new_pony)
	check(stored != null and stored.form_name == "Borrowed Form",
		"the service stores the presented form's name")
	var note := str(runtime.act.prompt_note())
	check(note.contains("Borrowed Form") and note.contains("not your own body"),
		"the dialogue note names the borrowed body")
	var previous_revision := stored.revision if stored != null else 0
	runtime.act._set_state(ACT_STATE.State.IDLE)
	var fallback := body_change.default_form(new_pony)
	fallback.form_name = ""
	fallback.revision = previous_revision + 1
	body_change.apply_form(new_pony, fallback)
	check(str(runtime.act.display_name) == "Identity Name",
		"an empty form name falls back to the identity display name")
	check(str(runtime._bundle.facts.display_name) == "Identity Name",
		"the fallback reaches the act facts")
	check(str(runtime.act.prompt_note()).contains("your own body"),
		"the dialogue note follows the return to the own body")
	_free_fixture(f)


## Every generic act milestone reaches the provider policy through the runtime's one dispatch
## helper, in the act's own order.
func _check_policy_events() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	var policy: FakePolicy = f["policy"]
	host.memory = FakeMemory.new()
	MEMORY.instance = host.memory
	runtime.act._set_state(ACT_STATE.State.POSING_IN)
	runtime.act.enter_active_act()
	runtime.act._set_state(ACT_STATE.State.CLIMAX)
	runtime._bundle.readiness.pony_climaxes = 1
	runtime.act.finish_climax()
	runtime.act.begin_afterglow()

	source.shape = ""
	var named: Dictionary = runtime.act.request_form_change(false, "rarity", true)
	check(bool(named.get("ok", false)), "a player-named change starts after the afterglow entry")
	runtime.act.swap.suspend(source.active_change())
	var named_body := _pony("Named Identity", "NamedBody")
	root.add_child(named_body)
	source.new_pony = named_body
	source.shape = "rarity"
	PONIES.attach(named_body)
	runtime.act.swap.tick(0.1)
	check(not runtime.act.suspended(), "the named change resumes")
	source.changing = false

	source.old_pony = named_body
	source.shape = ""
	var reveal: Dictionary = runtime.act.request_form_change(true, "", true)
	check(bool(reveal.get("ok", false)), "a player-requested reveal starts")
	runtime.act.swap.suspend(source.active_change())
	var own_body := _pony("Own Identity", "OwnBody")
	root.add_child(own_body)
	source.new_pony = own_body
	PONIES.attach(own_body)
	runtime.act.swap.tick(0.1)
	check(not runtime.act.suspended(), "the reveal resumes")

	var expected: Array[int] = [
		int(POLICY.ActEvent.ACTIVE), int(POLICY.ActEvent.CLIMAX_END),
		int(POLICY.ActEvent.AFTERGLOW), int(POLICY.ActEvent.OFFER_ACCEPTED),
		int(POLICY.ActEvent.FORM_SETTLED), int(POLICY.ActEvent.REVEALED),
		int(POLICY.ActEvent.FORM_SETTLED),
	]
	check(policy.events == expected, "the policy receives the six act milestones in order")
	check(int(policy.last_event.get("origin", -1)) == int(BODY_CHANGE.Origin.PLAYER),
		"the settled form event carries the player's origin")
	runtime.act.force_stop()
	_free_fixture(f)


## A change the source started on its own (her AI, not a `request_*` call): the live watcher
## suspends the act, adopts the new body and resumes without an exceptional event. A second
## change after the resume is a new pending swap.
func _check_ai_change() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	var source: FakeSource = f["source"]
	host.memory = FakeMemory.new()
	MEMORY.instance = host.memory
	source.shape = "fluttershy"
	# Nothing called request_form: the source is already changing, as her own AI leaves it.
	source.changing = true
	runtime._bundle.handover.clock = 0.0
	runtime.act.swap.tick(0.1)
	check(runtime.act.suspended(), "an AI-started change suspends the live act")
	check(runtime._bundle.handover.change.origin == BODY_CHANGE.Origin.AI, "an AI change is not the player's")
	var new_pony := _pony("New Mare", "AiBody")
	root.add_child(new_pony)
	source.new_pony = new_pony
	source.shape = "rarity"
	PONIES.attach(new_pony)
	check(runtime.act.suspended(), "the AI change waits for the new body's shape")
	source.changing = false
	runtime.act.swap.tick(0.1)
	check(not runtime.act.suspended(), "the AI change resumes on the new body")
	check(runtime.pony == new_pony, "the AI change keeps the act on the new body")
	check(not runtime._bundle.handover.reveal_done, "an AI change is neutral")
	var memory: FakeMemory = host.memory
	check(memory.impressions.is_empty(), "an AI change writes no reveal memory")
	# A second change after the resume is a fresh handover, not a stale pending swap.
	source.old_pony = new_pony
	source.changing = true
	runtime._bundle.handover.clock = 0.0
	runtime.act.swap.tick(0.1)
	check(runtime.act.suspended(), "a second change after resume suspends again")
	runtime.act.force_stop()
	check(not PONIES.body_swap_pending(), "the one exit clears the repeated swap")
	_free_fixture(f)


## A change that stops with the old body alive resumes the same act on it.
func _check_failed_change() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	var source: FakeSource = f["source"]
	source.changing = true
	runtime.act.swap.suspend(source.active_change())
	source.changing = false
	runtime.act.swap.tick(0.1)
	check(not runtime.act.suspended(), "a stopped change resumes")
	check(runtime.pony == old_pony, "the old body keeps the act")
	check(int(runtime.act.state) == ACT_STATE.State.ACTIVE, "the state survives the failed change")
	check(absf(float(runtime._bundle.readiness.depth) - 0.42) < 0.0001, "depth survives the failed change")
	runtime.act.force_stop()
	_free_fixture(f)


## A source that goes inactive mid-change (the pack switched off) resumes the old body.
func _check_source_gone() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	var source: FakeSource = f["source"]
	source.changing = true
	runtime.act.swap.suspend(source.active_change())
	source.active_flag = false
	runtime.act.swap.tick(0.1)
	check(not runtime.act.suspended(), "a source that goes inactive resumes the old body")
	check(runtime.pony == old_pony, "the old body keeps the act when the source is gone")
	check(int(runtime.act.state) == ACT_STATE.State.ACTIVE, "the state survives a gone source")
	runtime.act.force_stop()
	_free_fixture(f)


## No new body and no old body: the watchdog ends through the one exit.
func _check_watchdog() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	var source: FakeSource = f["source"]
	source.changing = true
	runtime.act.swap.suspend(source.active_change())
	old_pony.free()
	runtime.act.swap.tick(BODY_CHANGE_ACT.BODY_SWAP_WATCHDOG_S + 1.0)
	check(int(runtime.act.state) == ACT_STATE.State.IDLE, "the watchdog ends the act")
	check(not PONIES.act_running(), "the watchdog clears the active runtime")
	check(not PONIES.body_swap_pending(), "the watchdog clears the pending swap")
	_free_fixture(f)


## A new body that is not an adult mare ends cleanly instead of resuming.
func _check_invalid_shape() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	var eligibility := FakeEligibility.new()
	eligibility.allow = false
	host.eligibility = eligibility
	PONIES.eligibility = eligibility
	source.changing = true
	runtime.act.swap.suspend(source.active_change())
	var new_pony := _pony("Young Shape", "YoungBody")
	root.add_child(new_pony)
	source.new_pony = new_pony
	PONIES.attach(new_pony)
	check(int(runtime.act.state) == ACT_STATE.State.IDLE, "an ineligible shape ends the act")
	check(not PONIES.act_running(), "an ineligible shape clears the active runtime")
	check(not new_pony.has_meta("sex_active"), "an ineligible shape keeps no act flag")
	_free_fixture(f)


## Closing the world while the act is suspended is the same one exit, not a second teardown.
func _check_world_close() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	source.changing = true
	runtime.act.swap.suspend(source.active_change())
	runtime.act.force_stop()
	check(int(runtime.act.state) == ACT_STATE.State.IDLE, "a world close during a swap ends the act")
	check(not PONIES.body_swap_pending(), "a world close clears the pending swap")
	_free_fixture(f)


## The player's own ask during a disguise: the handover resumes the same act and the one
## exceptional beat is recorded once, with the spike, the impression and the peak.
func _check_form_reveal() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	var policy: FakePolicy = f["policy"]
	host.memory = FakeMemory.new()
	MEMORY.instance = host.memory
	var director := FakeDirector.new()
	director.name = "FakeDirector"
	root.add_child(director)
	source.shape = "fluttershy"
	source.asks = true
	director._turn_id = 1
	director._player_text = "show me the real you"
	runtime.act.ticker.talk(0.016)
	check(source.true_requests == 1, "the ask starts a true-form change")
	check(source.active_change().origin == BODY_CHANGE.Origin.PLAYER,
		"the ask marks the change as the player's")
	check(source.changing, "the source is changing after the ask")
	runtime.act.swap.tick(0.1)
	check(runtime.act.suspended(), "the act suspends for the reveal")
	var new_pony := _pony("Test Mare", "TrueBody")
	root.add_child(new_pony)
	source.new_pony = new_pony
	source.shape = ""
	PONIES.attach(new_pony)
	runtime.act.swap.tick(0.1)
	check(not runtime.act.suspended(), "the reveal resumes the same act")
	check(runtime.pony == new_pony, "the reveal keeps the act on the new body")
	check(runtime._bundle.handover.reveal_done, "the requested reveal is recorded once")
	check(policy.reveal_calls == 1, "the reveal asks the provider policy once")
	check(int(policy.last_reveal.get("origin", -1)) == int(BODY_CHANGE.Origin.PLAYER),
		"the reveal context is the player's origin")
	check(bool(policy.last_reveal.get("by_player", false)),
		"the reveal context marks the player")
	check(bool(policy.last_reveal.get("has_change", false)),
		"the reveal context carries the typed change")
	check(not bool(policy.last_reveal.get("reveal_used", true)),
		"the reveal context is read before the once-per-act mark")
	check(float(runtime._bundle.readiness.satisfaction) >= policy.heat - 0.01,
		"the reveal spikes readiness by the policy's heat")
	check(runtime._bundle.readiness.cue_override == policy.cue,
		"the reveal cue comes from the policy")
	var memory: FakeMemory = host.memory
	check(memory.impressions.size() == 1, "the reveal writes one special impression")
	if not memory.impressions.is_empty():
		var impression: Variant = memory.impressions[0]
		check(int(impression.slot) == MEMORY.ImpressionSlot.FORM_REVEAL,
			"the impression uses the reveal slot")
		check(str(impression.thought).contains("not the shape"),
			"the private thought says he wanted her")
		check(not str(impression.event_text).contains(" you "),
			"the reveal event has no second-person body")
	check(memory.peaks.size() == 1, "the reveal records one peak")
	if not memory.peaks.is_empty():
		check(is_equal_approx(float(memory.peaks[0].score), policy.peak),
			"the reveal peak uses the policy's score")
	var values: SUMMARY.ActInput = runtime.act.act_input()
	check(values.form_reveal, "the summary sees the reveal")
	# Once per act: a second ask while disguised again does nothing.
	source.shape = "rarity"
	source.true_requests = 0
	director._turn_id = 2
	director._player_text = "show me the real you"
	runtime.act.ticker.talk(0.016)
	check(source.true_requests == 0, "a second ask in the same act does nothing")
	check(policy.reveal_calls == 1, "the used reveal asks no second time")
	runtime.act.force_stop()
	director.queue_free()
	_free_fixture(f)


## Her offer after a climax, and a named shape: the act resumes on the disguise with no
## exceptional beat.
func _check_shape_offer() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	var policy: FakePolicy = f["policy"]
	host.memory = FakeMemory.new()
	MEMORY.instance = host.memory
	source.shape = ""
	runtime._bundle.handover.offer_tick()
	check(runtime._bundle.handover.offer_done and runtime._bundle.handover.offer_pending,
		"a true-form climax offers the shape change")
	check(policy.offer_calls == 1, "the offer tick asks the policy once")
	check(policy.prompt_calls == 1, "the offer prompt comes from the policy")
	check(bool(policy.last_offer.get("act_active", false)),
		"the offer context is the active stage")
	check(int(policy.last_offer.get("pony_climaxes", -1)) == 1,
		"the offer context carries the climax count")
	check(int(policy.last_offer.get("max_climaxes", -1)) == runtime.act.max_pony_climaxes,
		"the offer context carries the act's climax cap")
	check(int(policy.last_offer.get("origin", -1)) == int(BODY_CHANGE.Origin.PROVIDER),
		"the offer context is the provider's origin")
	check(bool(policy.last_offer.get("own", false)), "the offer context uses the own form")
	check(not bool(policy.last_offer.get("offer_pending", true)),
		"the offer context is read before the offer is marked")
	runtime._bundle.handover.offer_tick()
	check(policy.offer_calls == 1, "a made offer is not asked again")
	runtime._bundle.handover.hint_tick()
	check(str(runtime._bundle.handover.form_hint_log) == BODY_CHANGE_ACT.FORM_HINT_SHAPE,
		"the offer names the pony in the debug log")
	check(str(runtime._bundle.handover.form_hint()).is_empty(), "the offer stays off the HUD")
	var director := FakeDirector.new()
	director.name = "FakeDirector"
	root.add_child(director)
	source.named = "rarity"
	director._turn_id = 1
	director._player_text = "Rarity"
	runtime.act.ticker.talk(0.016)
	check(source.shape_requests == ["rarity"], "the named mare starts the change")
	check(not runtime._bundle.handover.offer_pending, "the offer is consumed by the name")
	check(source.active_change().origin == BODY_CHANGE.Origin.PLAYER,
		"a named shape is the player's ask")
	runtime.act.swap.tick(0.1)
	check(runtime.act.suspended(), "the named change suspends the act")
	var new_pony := _pony("Test Mare", "ShapeBody")
	root.add_child(new_pony)
	source.new_pony = new_pony
	source.shape = "rarity"
	PONIES.attach(new_pony)
	runtime.act.swap.tick(0.1)
	check(not runtime._bundle.handover.reveal_done, "a named shape is not an exceptional reveal")
	check(not runtime._bundle.handover.offer_pending, "the player's named shape spends the offer")
	check(policy.accepted_calls == 1, "the named shape asks the accepted-offer policy")
	check(int(policy.last_accepted.get("origin", -1)) == int(BODY_CHANGE.Origin.PLAYER),
		"the accepted offer context is the player's origin")
	var memory: FakeMemory = host.memory
	check(memory.impressions.is_empty(), "a named shape writes no reveal memory")
	check(memory.peaks.is_empty(), "a named shape records no reveal peak")
	runtime.act.force_stop()
	director.queue_free()
	_free_fixture(f)


## A named shape waits for the new body's variant before resuming. The player's offer is spent
## only once the shape is on the body, and the adopted body's LOD is rebuilt during the wait.
func _check_named_shape_gate() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	source.shape = ""
	runtime._bundle.handover.offer_tick()
	check(runtime._bundle.handover.offer_pending, "the offer is pending before the name")
	var director := FakeDirector.new()
	director.name = "FakeDirector"
	root.add_child(director)
	source.named = "rarity"
	director._turn_id = 1
	director._player_text = "Rarity"
	runtime.act.ticker.talk(0.016)
	runtime.act.swap.tick(0.1)
	check(runtime.act.suspended(), "the named change suspends the act")
	check(runtime._bundle.handover.change.target_form_id == "rarity", "the target survives the suspension")
	var new_pony := _pony("Test Mare", "ShapeGateBody")
	root.add_child(new_pony)
	source.new_pony = new_pony
	source.shape = ""
	var near_key: String = HYBRID_NEAR_MESH.key(new_pony)
	HYBRID_NEAR_MESH.cache[near_key] = true
	PONIES.attach(new_pony)
	check(runtime.act.suspended(), "the new body binds without resuming")
	check(runtime.pony == new_pony, "the runtime owns the new body during the wait")
	check(runtime.get_parent() == new_pony, "the runtime moves under the new body")
	check(not PONIES.body_swap_pending(), "the adoption clears the pending swap")
	check(not HYBRID_NEAR_MESH.cache.has(near_key), "the adopted body's LOD is rebuilt")
	runtime.act.swap.tick(0.1)
	check(runtime.act.suspended(), "a missing shape keeps the act suspended")
	source.shape = "rarity"
	runtime.act.swap.tick(0.1)
	check(not runtime.act.suspended(), "the target shape resumes the act")
	check(int(runtime.act.state) == ACT_STATE.State.ACTIVE, "the act state survives the shape wait")
	check(absf(float(runtime._bundle.readiness.depth) - 0.42) < 0.0001, "depth survives the shape wait")
	check(not runtime._bundle.handover.offer_pending, "the player's named shape spends the offer")
	runtime.act.force_stop()
	director.queue_free()
	_free_fixture(f)


## The new body exists but never reports the shape before the watchdog: the act resumes on the
## adult body and the failed shape restores the offer instead of ending through the exit.
func _check_watchdog_with_body() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	source.shape = ""
	runtime._bundle.handover.offer_tick()
	var director := FakeDirector.new()
	director.name = "FakeDirector"
	root.add_child(director)
	source.named = "rarity"
	director._turn_id = 1
	director._player_text = "Rarity"
	runtime.act.ticker.talk(0.016)
	runtime.act.swap.tick(0.1)
	var new_pony := _pony("Test Mare", "WatchdogShapeBody")
	root.add_child(new_pony)
	source.new_pony = new_pony
	source.shape = ""
	PONIES.attach(new_pony)
	check(runtime.act.suspended(), "the watchdog body adopts suspended")
	check(runtime.pony == new_pony, "the watchdog body is the new body")
	runtime.act.swap.tick(BODY_CHANGE_ACT.BODY_SWAP_WATCHDOG_S + 1.0)
	check(not runtime.act.suspended(), "the watchdog resumes a body that never took the shape")
	check(runtime.pony == new_pony, "the watchdog keeps the adopted body")
	check(int(runtime.act.state) == ACT_STATE.State.ACTIVE, "the watchdog does not end a live body")
	check(runtime._bundle.handover.offer_pending, "the failed watchdog shape restores the offer")
	runtime.act.force_stop()
	director.queue_free()
	_free_fixture(f)


## The offer gate and the act-HUD hint states.
func _check_offer_gate() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	var body_change: BODY_CHANGE_SERVICE = f["body_change"]
	source.shape = "rarity"
	var borrowed := body_change.default_form(runtime.pony)
	borrowed.form_id = "rarity"
	borrowed.fit_id = "rarity"
	body_change.apply_form(runtime.pony, borrowed)
	runtime._bundle.handover.offer_tick()
	check(not runtime._bundle.handover.offer_done, "a disguise gets no shape offer")
	source.shape = ""
	var own := body_change.default_form(runtime.pony)
	own.revision = borrowed.revision + 1
	body_change.apply_form(runtime.pony, own)
	runtime._bundle.readiness.pony_climaxes = 0
	runtime._bundle.handover.offer_tick()
	check(not runtime._bundle.handover.offer_done, "the offer waits for a climax")
	runtime._bundle.readiness.pony_climaxes = 1
	runtime._bundle.handover.offer_tick()
	check(runtime._bundle.handover.offer_done and runtime._bundle.handover.offer_pending,
		"the offer is made once after a climax")
	source.shape = "fluttershy"
	runtime._bundle.handover.offer_pending = false
	runtime._bundle.handover.reveal_done = false
	runtime._bundle.handover.hint_tick()
	check(str(runtime._bundle.handover.form_hint_log) == BODY_CHANGE_ACT.FORM_HINT_ASK,
		"a disguise invites the reveal ask in the debug log")
	check(str(runtime._bundle.handover.form_hint()).is_empty(), "the reveal ask stays off the HUD")
	runtime._bundle.handover.reveal_done = true
	runtime._bundle.handover.hint_tick()
	check(str(runtime._bundle.handover.form_hint_log).is_empty(), "a used reveal hides the debug log")
	check(str(runtime._bundle.handover.form_hint()).is_empty(), "a used reveal hides the HUD hint")
	runtime._bundle.handover.reveal_done = false
	runtime._bundle.handover.offer_pending = true
	runtime.act.force_stop()
	check(not runtime._bundle.handover.offer_pending, "the act end drops the pending offer")
	check(str(runtime._bundle.handover.form_hint_log).is_empty(), "the act end hides the debug log")
	check(str(runtime._bundle.handover.form_hint()).is_empty(), "the act end hides the HUD hint")
	_free_fixture(f)


## A release never publishes the form hint: the player finds the reveal and the gift by probing
## her, not by a HUD row that names the dialogue channel.
func _check_no_player_hint() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	runtime._bundle.handover.set_form_hint_debug(false)
	source.shape = ""
	runtime._bundle.handover.offer_tick()
	runtime._bundle.handover.hint_tick()
	check(runtime._bundle.handover.offer_pending, "the offer is still made")
	check(str(runtime._bundle.handover.form_hint()).is_empty(), "the release offer publishes no hint")
	source.shape = "fluttershy"
	runtime._bundle.handover.offer_pending = false
	runtime._bundle.handover.reveal_done = false
	runtime._bundle.handover.hint_tick()
	check(str(runtime._bundle.handover.form_hint()).is_empty(), "a disguise publishes no reveal hint")
	runtime._bundle.handover.set_form_hint_debug(true)
	runtime._bundle.handover.hint_tick()
	check(str(runtime._bundle.handover.form_hint_log) == BODY_CHANGE_ACT.FORM_HINT_ASK,
		"debug mode can name the ask in the log")
	check(str(runtime._bundle.handover.form_hint()).is_empty(), "debug mode still publishes no HUD hint")
	runtime.act.force_stop()
	_free_fixture(f)


## The cached hint is cleared by the state change, not only by the next ACTIVE tick.
func _check_hint_states() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	source.shape = "fluttershy"
	runtime._bundle.handover.reveal_done = false
	runtime._bundle.handover.hint_tick()
	check(str(runtime._bundle.handover.form_hint_log) == BODY_CHANGE_ACT.FORM_HINT_ASK,
		"a disguise invites the ask in the debug log")
	runtime.act._set_state(ACT_STATE.State.CLIMAX)
	runtime._bundle.handover.hint_tick()
	check(str(runtime._bundle.handover.form_hint_log).is_empty(), "the climax state clears the debug log")
	runtime.act._set_state(ACT_STATE.State.AFTERGLOW)
	runtime._bundle.handover.hint_tick()
	check(str(runtime._bundle.handover.form_hint_log).is_empty(), "the afterglow state clears the debug log")
	runtime.act._set_state(ACT_STATE.State.RESTORE)
	runtime._bundle.handover.hint_tick()
	check(str(runtime._bundle.handover.form_hint_log).is_empty(), "the restore state clears the debug log")
	runtime.act._set_state(ACT_STATE.State.ACTIVE)
	runtime._bundle.handover.hint_tick()
	check(str(runtime._bundle.handover.form_hint_log) == BODY_CHANGE_ACT.FORM_HINT_ASK,
		"the active state restores the debug log")
	check(str(runtime._bundle.handover.form_hint()).is_empty(), "the HUD hint stays empty through every state")
	runtime.act.force_stop()
	_free_fixture(f)


## A named shape whose handover fails puts the offer back instead of spending it.
func _check_failed_named_offer() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	var source: FakeSource = f["source"]
	source.shape = ""
	runtime._bundle.handover.offer_tick()
	check(runtime._bundle.handover.offer_pending, "the offer is pending before the name")
	var director := FakeDirector.new()
	director.name = "FakeDirector"
	root.add_child(director)
	source.named = "rarity"
	director._turn_id = 1
	director._player_text = "Rarity"
	runtime.act.ticker.talk(0.016)
	check(source.shape_requests == ["rarity"], "the named mare starts the change")
	check(not runtime._bundle.handover.offer_pending, "the name consumes the offer")
	runtime._bundle.handover.clock = 0.0
	runtime.act.swap.tick(0.1)
	check(runtime.act.suspended(), "the named change suspends the act")
	source.changing = false
	runtime.act.swap.tick(0.1)
	check(not runtime.act.suspended(), "the failed named change resumes the old body")
	check(runtime.pony == old_pony, "the old body keeps the act")
	check(runtime._bundle.handover.offer_pending, "a failed named change puts the offer back")
	runtime._bundle.handover.set_form_hint_debug(true)
	runtime._bundle.handover.hint_tick()
	runtime._bundle.handover.hint_tick()
	check(str(runtime._bundle.handover.form_hint_log) == BODY_CHANGE_ACT.FORM_HINT_SHAPE,
		"the hint returns with the offer in the debug log")
	check(str(runtime._bundle.handover.form_hint()).is_empty(), "the offer stays off the HUD")
	runtime.act.force_stop()
	director.queue_free()
	_free_fixture(f)


## A player-named change whose new body never reports the shape is a failed change: the act
## resumes on the body but the offer comes back, so the player can name another shape.
func _check_named_without_shape() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	host.memory = FakeMemory.new()
	MEMORY.instance = host.memory
	source.shape = ""
	runtime._bundle.handover.offer_tick()
	var director := FakeDirector.new()
	director.name = "FakeDirector"
	root.add_child(director)
	source.named = "rarity"
	director._turn_id = 1
	director._player_text = "Rarity"
	runtime.act.ticker.talk(0.016)
	runtime.act.swap.tick(0.1)
	check(runtime.act.suspended(), "the named change suspends the act")
	var new_pony := _pony("Test Mare", "EmptyShapeBody")
	root.add_child(new_pony)
	source.new_pony = new_pony
	source.shape = ""
	PONIES.attach(new_pony)
	check(runtime.act.suspended(), "a new body with no shape does not resume")
	source.changing = false
	runtime.act.swap.tick(0.1)
	check(not runtime.act.suspended(), "the settled failed shape resumes the new body")
	check(runtime.pony == new_pony, "the failed shape keeps the new body")
	check(not runtime._bundle.handover.reveal_done, "a named change with no shape is not a reveal")
	var memory: FakeMemory = host.memory
	check(memory.impressions.is_empty(), "a named change with no shape writes no reveal memory")
	check(runtime._bundle.handover.offer_pending, "a failed named shape restores the offer")
	runtime._bundle.handover.set_form_hint_debug(true)
	runtime._bundle.handover.hint_tick()
	runtime._bundle.handover.hint_tick()
	check(str(runtime._bundle.handover.form_hint_log) == BODY_CHANGE_ACT.FORM_HINT_SHAPE,
		"the hint returns with the offer in the debug log")
	check(str(runtime._bundle.handover.form_hint()).is_empty(), "the offer stays off the HUD")
	runtime.act.force_stop()
	director.queue_free()
	_free_fixture(f)


## Her own AI changes shape while the player's post-climax offer waits: the neutral handover
## keeps the offer. The shape the player names still spends it.
func _check_ai_change_keeps_offer() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	source.shape = ""
	runtime._bundle.handover.offer_tick()
	check(runtime._bundle.handover.offer_pending, "the offer is pending before her change")
	source.changing = true
	runtime._bundle.handover.clock = 0.0
	runtime.act.swap.tick(0.1)
	check(runtime.act.suspended(), "her own change suspends the offered act")
	var ai_body := _pony("Test Mare", "AiOfferBody")
	root.add_child(ai_body)
	source.new_pony = ai_body
	source.shape = "fluttershy"
	source.changing = false
	PONIES.attach(ai_body)
	runtime.act.swap.tick(0.1)
	check(not runtime.act.suspended(), "her own change resumes the act")
	check(runtime._bundle.handover.offer_pending, "her own change keeps the player's offer")
	runtime._bundle.handover.set_form_hint_debug(true)
	runtime._bundle.handover.hint_tick()
	check(str(runtime._bundle.handover.form_hint_log) == BODY_CHANGE_ACT.FORM_HINT_SHAPE,
		"the debug log still names the player's offer")
	check(str(runtime._bundle.handover.form_hint()).is_empty(), "the player's offer stays off the HUD")
	var director := FakeDirector.new()
	director.name = "FakeDirector"
	root.add_child(director)
	source.named = "rarity"
	director._turn_id = 1
	director._player_text = "Rarity"
	runtime.act.ticker.talk(0.016)
	check(source.shape_requests == ["rarity"], "the player's name reaches the source")
	check(source.active_change().origin == BODY_CHANGE.Origin.PLAYER,
		"the player's name is marked as the player's")
	check(not runtime._bundle.handover.offer_pending, "the player's named shape spends the offer")
	runtime.act.force_stop()
	director.queue_free()
	_free_fixture(f)


## The source clears its changing state before the new body's spawn reaches the entry. The
## watcher keeps the act suspended for the grace, then the entry adopts the body the source still
## reports; no second runtime attaches to it.
func _check_late_adoption() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	var source: FakeSource = f["source"]
	source.changing = true
	runtime.act.swap.suspend(source.active_change())
	var late_pony := _pony("Late Mare", "LateBody")
	root.add_child(late_pony)
	source.new_pony = late_pony
	source.changing = false
	runtime.act.swap.tick(BODY_CHANGE_ACT.BODY_SWAP_ADOPT_GRACE_S * 0.5)
	check(runtime.act.suspended(), "a late body keeps the act suspended")
	check(runtime.pony == old_pony, "the old body is not resumed while the new body exists")
	check(PONIES.runtime_for(late_pony) == null, "no runtime attaches to the late body yet")
	runtime.act.swap.tick(BODY_CHANGE_ACT.BODY_SWAP_ADOPT_GRACE_S)
	check(not runtime.act.suspended(), "the entry adopts the late body after the grace")
	check(runtime.pony == late_pony, "the act resumes on the late body")
	check(runtime.get_parent() == late_pony, "the runtime moves under the late body")
	check(PONIES.runtime_for(late_pony) == runtime, "the late body maps to the same runtime")
	check(PONIES.live_ponies().size() == 1, "the late adoption creates no second runtime")
	runtime.act.force_stop()
	_free_fixture(f)


## Her own change can start while the act is already restoring. The restore finishes through the
## one exit; the change is not suspended and leaves no pending swap or stale source.
func _check_restore_change() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	runtime.act._set_state(ACT_STATE.State.RESTORE)
	runtime.act._restore_left = ACT_SESSION.RESTORE_SECONDS
	var other := _pony("Other Mare", "OtherBody")
	root.add_child(other)
	source.old_pony = other
	source.changing = true
	runtime.act.swap.tick(0.1)
	check(int(runtime.act.state) == ACT_STATE.State.RESTORE,
		"another body's change leaves the restore alone")
	check(not PONIES.body_swap_pending(), "another body's change records no pending swap")
	source.old_pony = runtime.pony
	source.changing = true
	runtime.act.swap.tick(0.1)
	check(int(runtime.act.state) == ACT_STATE.State.IDLE,
		"the act pony's change during restore finishes the act")
	check(not runtime.act.suspended(), "a change during restore never suspends")
	check(not PONIES.body_swap_pending(), "a change during restore records no pending swap")
	check(runtime._bundle.handover.change == null, "the one exit drops the typed swap change")
	check(not PONIES.act_running(), "the one exit clears the active runtime")
	other.queue_free()
	_free_fixture(f)


## A body another system is holding refuses the player's request instead of leaving a held body.
func _check_held_guard() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	old_pony.held = true
	var result: Dictionary = runtime.act.request_form_change(true, "", true)
	check(not bool(result.get("ok", false)), "a held body refuses a form request")
	check(str(result.get("reason", "")) == "she is held", "the refusal names the hold")
	old_pony.held = false
	runtime.act.force_stop()
	_free_fixture(f)


## A form change on an idle body binds the runtime's systems without an act resume or an exit.
func _check_idle_body_binding() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	var body_change: BODY_CHANGE_SERVICE = f["body_change"]
	runtime.act._set_state(ACT_STATE.State.IDLE)
	runtime.act.pose_id = ""
	runtime.act.source = ""
	var own := body_change.default_form(old_pony)
	body_change.apply_form(old_pony, own)
	check(int(runtime.act.state) == ACT_STATE.State.IDLE, "an idle form bind leaves the state idle")
	check(not runtime.act.suspended(), "an idle form bind never suspends")
	check(runtime.pony == old_pony, "the idle body keeps its runtime")
	check(runtime._bundle.pose.pony == old_pony, "the idle form bind binds the pose session")
	check(runtime._bundle.face.pony == old_pony, "the idle form bind binds the face")
	check(PONIES.live_ponies().size() == 1, "the idle form bind creates no second runtime")
	check(is_zero_approx(runtime._bundle.camera.camera_target_eye),
		"an idle form bind applies no act eye override")
	var revised := body_change.default_form(old_pony)
	revised.form_id = "rarity"
	revised.fit_id = "rarity"
	revised.form_name = "Idle Borrowed Form"
	revised.revision = 1
	body_change.apply_form(old_pony, revised)
	check(int(runtime.act.state) == ACT_STATE.State.IDLE, "a same-node revision keeps the idle state")
	check(body_change.form_for(old_pony) == revised, "the idle body takes the revised form")
	check(str(runtime.act.display_name) == "Idle Borrowed Form",
		"an idle form revision takes the presented form's name")
	check(str(runtime._bundle.facts.display_name) == "Idle Borrowed Form",
		"the idle act facts carry the presented form's name")
	check(not runtime.act.suspended() and not PONIES.body_swap_pending(),
		"a same-node revision never starts a swap")
	_free_fixture(f)


## A live act's same-node revision refreshes the eye, pose and camera without a resume.
func _check_same_node_refresh() -> void:
	var f := _fixture()
	var host: FakeHost = f["host"]
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	var body_change: BODY_CHANGE_SERVICE = f["body_change"]
	var player := FakePlayer.new()
	player.name = "FakePlayer"
	host.add_child(player)
	host.player = player
	WORLD.bind_player(host.player)
	var base := body_change.default_form(old_pony)
	body_change.apply_form(old_pony, base)
	var revised := body_change.default_form(old_pony)
	revised.form_id = "rarity"
	revised.fit_id = "rarity"
	revised.rig = BODY_PROFILE.RigProfile.new("test_low",
		BODY_PROFILE.WINKING_REAR_Y - 0.14, BODY_PROFILE.WINKING_REAR_Z, 1.0)
	revised.body_scale = 1.0
	revised.revision = 1
	body_change.apply_form(old_pony, revised)
	check(int(runtime.act.state) == ACT_STATE.State.ACTIVE,
		"a live same-node revision keeps the act state")
	check(not runtime.act.suspended() and not PONIES.body_swap_pending(),
		"a live same-node revision starts no swap")
	check(not PONIES.body_swap_pending(), "a live same-node revision starts no handover")
	check(runtime._bundle.pose.pony == old_pony, "the live revision keeps the pose bound")
	check(runtime._bundle.camera.camera_target_eye > 0.0,
		"the live revision refreshes the eye target")
	check(body_change.form_for(old_pony) == revised, "the live body takes the revised form")
	var first_target := float(runtime._bundle.camera.camera_target_eye)
	var revised_two := BODY_FORM.default_form(old_pony)
	revised_two.form_id = "rarity"
	revised_two.fit_id = "rarity"
	revised_two.rig = BODY_PROFILE.RigProfile.new("test_low",
		BODY_PROFILE.WINKING_REAR_Y - 0.14, BODY_PROFILE.WINKING_REAR_Z, 1.0)
	revised_two.body_scale = 1.0
	revised_two.revision = 2
	body_change.apply_form(old_pony, revised_two)
	check(absf(float(runtime._bundle.camera.camera_target_eye) - first_target) < 0.0001,
		"a second revision does not compound the standing eye")
	runtime.act.force_stop()
	_free_fixture(f)


## The runtime forwards the request origin unchanged: provider and player are distinct.
func _check_origins() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	var provider: Dictionary = runtime.act.request_form_change(false, "rarity", false)
	check(bool(provider.get("ok", false)), "a provider-origin form request starts")
	check(source.active_change().origin == BODY_CHANGE.Origin.PROVIDER,
		"a provider-origin request keeps its origin")
	source.changing = false
	runtime._bundle.handover.clock = 0.0
	runtime.act.swap.tick(0.1)
	var player: Dictionary = runtime.act.request_form_change(false, "rarity", true)
	check(bool(player.get("ok", false)), "a player-origin form request starts")
	check(source.active_change().origin == BODY_CHANGE.Origin.PLAYER,
		"a player-origin request keeps its origin")
	source.changing = false
	runtime.act.force_stop()
	_free_fixture(f)
