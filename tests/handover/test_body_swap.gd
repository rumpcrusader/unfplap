extends SceneTree
## The generic body-swap handover: suspend an act, adopt the runtime on a new body with the same
## stable id, rebuild the pose and resume, and keep `_end_session()` the only exit.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/handover/test_body_swap.gd
##
## The entry node is faked here because `main.gd` names the `Mods` autoload, which a `--script`
## suite cannot load. The pending-swap rules mirrored by `FakeMain` are also pinned in
## `tests/test_source_hygiene.gd` against the real entry.

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
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


class FakeSource extends Node:
	var changing := false
	var old_pony: Node = null
	var new_pony: Node = null
	var shape_id := ""
	var active_flag := true
	var shape := ""
	var asks := false
	var named := ""
	var note := ""
	var true_requests := 0
	var shape_requests: Array[String] = []
	var player_marks: Array[bool] = []
	var player_request := false

	func is_active() -> bool:
		return active_flag

	func handles_pony(_pony: Node) -> bool:
		return true

	func is_changing() -> bool:
		return changing

	func old_actor() -> Node:
		return old_pony if is_instance_valid(old_pony) else null

	func new_actor() -> Node:
		return new_pony if is_instance_valid(new_pony) else null

	func target() -> String:
		return shape_id

	func current_shape() -> String:
		return shape

	func claims_body(pony: Node) -> bool:
		return changing and is_instance_valid(new_pony) and pony == new_pony

	func poll() -> void:
		pass

	func source_name() -> String:
		return "fake"

	func asks_form_change(_text: String) -> bool:
		return asks

	func named_form(_text: String) -> String:
		return named

	func named_form_note(_text: String) -> String:
		return note

	func set_player_request(by_player: bool) -> void:
		player_request = by_player
		player_marks.append(by_player)

	func requested_by_player() -> bool:
		return player_request

	func request_true_form() -> bool:
		true_requests += 1
		shape_id = ""
		shape = ""
		changing = true
		return true

	func request_shape(shape: String) -> bool:
		shape_requests.append(shape)
		shape_id = shape
		shape = shape
		changing = true
		return true


class FakeMemory extends RefCounted:
	var impressions: Array = []
	var peaks: Array = []
	var notes: Array = []
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


## The talk turn the player's line arrives on. The runtime reads the same director fields the
## readiness service reads.
class FakeDirector extends Node:
	var _turn_id := 0
	var _player_text := ""
	var state := "idle"

	func _ready() -> void:
		add_to_group("conversation_director")


class FakeEligibility extends RefCounted:
	var allow := true

	func eligible(_pony: Variant, _target: int) -> bool:
		return allow


## The pending-swap half of `main.gd`, without the autoload dependency. The runtime is the code
## under test; this only routes the spawned body to it.
class FakeMain extends Node:
	var _runtimes: Dictionary = {}
	var _pending_swap: Dictionary = {}
	var active_runtime: Variant = null
	var eligibility: Variant = null
	var hud: Variant = null
	var player: Variant = null
	var game: Variant = null
	var anatomy: Variant = null
	var stock_smack: Variant = null
	var source: Variant = null
	var memory: Variant = null

	func begin_body_swap(runtime: Node, old_pony: Node, id: String, source: Variant,
			target: String) -> void:
		_pending_swap = {"runtime": runtime, "old_pony": old_pony, "id": id,
			"source": source, "target": target}
		if is_instance_valid(old_pony) and _runtimes.get(old_pony) == runtime:
			_runtimes.erase(old_pony)

	func clear_body_swap(runtime: Node) -> void:
		if _pending_swap.get("runtime") == runtime:
			_pending_swap = {}

	func body_swap_pending() -> bool:
		return not _pending_swap.is_empty()

	func shape_source_for(_pony: Node) -> Variant:
		if not _pending_swap.is_empty():
			return _pending_swap.get("source")
		return source

	func camera() -> Camera3D:
		return null

	func clear_active(runtime: Node) -> void:
		if active_runtime == runtime:
			active_runtime = null

	func allocate_serial() -> int:
		return 1

	func _on_pony(pony: Node) -> void:
		_adopt_pending_swap(pony)

	func adopt_pending_body(pony: Node) -> bool:
		return _adopt_pending_swap(pony)

	func _adopt_pending_swap(pony: Node) -> bool:
		if _pending_swap.is_empty() or not is_instance_valid(pony):
			return false
		var runtime: Variant = _pending_swap.get("runtime")
		if not is_instance_valid(runtime):
			_pending_swap = {}
			return false
		var source: Variant = _pending_swap.get("source")
		var claimed: bool = is_instance_valid(source) and source.has_method("claims_body") \
			and bool(source.call("claims_body", pony))
		if not claimed:
			var new_id := PONY_ID.from(str(pony.get_meta("relationship_id", "")),
				pony.get("identity"))
			if new_id != str(_pending_swap.get("id", "")):
				return false
		var old_pony: Variant = _pending_swap.get("old_pony")
		if is_instance_valid(old_pony) and _runtimes.get(old_pony) == runtime:
			_runtimes.erase(old_pony)
		_runtimes[pony] = runtime
		if runtime.get_parent() != pony:
			runtime.call("attach_to_body", pony)
		_pending_swap = {}
		runtime.call("adopt_body", pony)
		return true


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


## A live act without the start sequence: the handover is the code under test, not the gate.
func _fixture() -> Dictionary:
	var main := FakeMain.new()
	main.name = "FakeMain"
	root.add_child(main)
	var old_pony := _pony("Test Mare", "OldBody")
	root.add_child(old_pony)
	var runtime: Node = RUNTIME.new()
	runtime.name = "UnfplapRuntime"
	runtime.pony = old_pony
	runtime.main = main
	old_pony.add_child(runtime)
	main._runtimes[old_pony] = runtime
	main.active_runtime = runtime
	runtime._id = "test_mare"
	runtime._display_name = "Test Mare"
	runtime.pose_id = CATALOG.STANDING
	runtime.source = "test"
	runtime.state = RUNTIME.State.ACTIVE
	runtime.depth = 0.42
	runtime.penetration_m = 0.11
	runtime.pony_climaxes = 1
	runtime._event_id = "intimacy_test_mare_1"
	runtime._serial = 1
	runtime._preferences = SETTINGS.preferences("test_mare")
	runtime._features = {}
	var source := FakeSource.new()
	source.name = "FakeSource"
	root.add_child(source)
	source.old_pony = old_pony
	source.changing = false
	main.source = source
	return {"main": main, "runtime": runtime, "old": old_pony, "source": source}


func _free_fixture(made: Dictionary) -> void:
	var main: Variant = made["main"]
	var runtime: Variant = made["runtime"]
	var old: Variant = made["old"]
	var source: Variant = made["source"]
	if is_instance_valid(runtime) and runtime.get_parent() == main:
		runtime.queue_free()
	if is_instance_valid(old):
		old.queue_free()
	if is_instance_valid(source):
		source.queue_free()
	if is_instance_valid(main):
		main.queue_free()
	if is_instance_valid(runtime) and not runtime.is_queued_for_deletion():
		runtime.free()


func run() -> void:
	_check_handover()
	_check_ai_change()
	_check_failed_change()
	_check_source_gone()
	_check_watchdog()
	_check_invalid_shape()
	_check_world_close()
	_check_form_reveal()
	_check_shape_offer()
	_check_offer_gate()
	_check_hint_states()
	_check_failed_named_offer()
	_check_named_without_shape()
	_check_ai_change_keeps_offer()
	_check_late_adoption()
	_check_restore_change()
	_check_held_guard()
	print("BODY_SWAP_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


## One complete suspend → adopt → resume, then the one exit.
func _check_handover() -> void:
	var f := _fixture()
	var main: FakeMain = f["main"]
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	var source: FakeSource = f["source"]

	source.changing = true
	runtime._suspend_for_body_swap(source)
	check(runtime._suspended, "the act suspends")
	check(runtime.get_parent() == main, "the runtime leaves the old body for main")
	check(main.body_swap_pending(), "main records the pending swap")
	check(int(runtime.state) == RUNTIME.State.ACTIVE, "the act state survives suspension")
	check(absf(float(runtime.depth) - 0.42) < 0.0001, "depth survives suspension")
	check(int(runtime.pony_climaxes) == 1, "climaxes survive suspension")
	check(str(runtime._event_id) == "intimacy_test_mare_1", "the event id survives suspension")

	var new_pony := _pony("New Mare", "NewBody")
	root.add_child(new_pony)
	source.new_pony = new_pony
	main._on_pony(new_pony)
	check(not runtime._suspended, "the new body resumes the act")
	check(runtime.pony == new_pony, "the runtime owns the new body")
	check(runtime.get_parent() == new_pony, "the runtime moved under the new body")
	check(main._runtimes.get(new_pony) == runtime, "main maps the new body to the same runtime")
	check(not main._runtimes.has(old_pony), "the old body's map entry is gone")
	check(not main.body_swap_pending(), "the pending swap is cleared")
	check(int(runtime.state) == RUNTIME.State.ACTIVE, "the act state survives resume")
	check(absf(float(runtime.depth) - 0.42) < 0.0001, "depth survives resume")
	check(int(runtime.pony_climaxes) == 1, "climaxes survive resume")
	check(str(runtime._event_id) == "intimacy_test_mare_1", "the event id survives resume")
	check(str(runtime._display_name) == "New Mare", "the act takes the new display name")
	check(new_pony.has_meta("sex_active"), "the new body carries the act flag")
	var nav: FakeNav = new_pony.get_node("Navigator")
	check(nav.command_owner == "unfplap:test_mare", "the new navigator is claimed")
	check(runtime._pose_session.pony == new_pony, "the pose session binds the new body")
	var view: Variant = runtime._pose_session.view()
	check(view != null and str(view.id) == CATALOG.STANDING, "the pose is rebuilt at the act pose")
	check(runtime._pose_session.pose() != null and runtime._pose_session.basis_amount() > 0.99,
		"the rebuilt pose starts settled")

	runtime.force_stop()
	check(int(runtime.state) == RUNTIME.State.IDLE, "the one exit ends the act")
	check(main.active_runtime == null, "the one exit clears the active runtime")
	check(not new_pony.has_meta("sex_active"), "the one exit clears the new body's flag")
	check(runtime._hold.nav == null and runtime._hold.token.is_empty(),
		"the one exit gives up the act's navigator lease")
	_free_fixture(f)


## A change the source started on its own (her AI, not a `request_*` call): the live watcher
## suspends the act, adopts the new body and resumes without an exceptional event. A second
## change after the resume is a new pending swap.
func _check_ai_change() -> void:
	var f := _fixture()
	var main: FakeMain = f["main"]
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	var source: FakeSource = f["source"]
	main.memory = FakeMemory.new()
	source.shape = "fluttershy"
	# Nothing called request_shape: the source is already changing, as her own AI leaves it.
	source.changing = true
	runtime._swap_clock = 0.0
	runtime._body_swap_tick(0.1)
	check(runtime._suspended, "an AI-started change suspends the live act")
	check(runtime._swap_by_player == false, "an AI change is not the player's")
	var new_pony := _pony("New Mare", "AiBody")
	root.add_child(new_pony)
	source.new_pony = new_pony
	source.shape = "rarity"
	main._on_pony(new_pony)
	check(not runtime._suspended, "the AI change resumes on the new body")
	check(runtime.pony == new_pony, "the AI change keeps the act on the new body")
	check(not runtime._form_reveal_done, "an AI change is neutral")
	var memory: FakeMemory = main.memory
	check(memory.impressions.is_empty(), "an AI change writes no reveal memory")
	# A second change after the resume is a fresh handover, not a stale pending swap.
	source.old_pony = new_pony
	source.changing = true
	runtime._swap_clock = 0.0
	runtime._body_swap_tick(0.1)
	check(runtime._suspended, "a second change after resume suspends again")
	runtime.force_stop()
	check(not main.body_swap_pending(), "the one exit clears the repeated swap")
	_free_fixture(f)


## A change that stops with the old body alive resumes the same act on it.
func _check_failed_change() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	var source: FakeSource = f["source"]
	runtime._suspend_for_body_swap(source)
	source.changing = false
	runtime._body_swap_tick(0.1)
	check(not runtime._suspended, "a stopped change resumes")
	check(runtime.pony == old_pony, "the old body keeps the act")
	check(int(runtime.state) == RUNTIME.State.ACTIVE, "the state survives the failed change")
	check(absf(float(runtime.depth) - 0.42) < 0.0001, "depth survives the failed change")
	runtime.force_stop()
	_free_fixture(f)


## A source that goes inactive mid-change (the pack switched off) resumes the old body.
func _check_source_gone() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	var source: FakeSource = f["source"]
	runtime._suspend_for_body_swap(source)
	source.active_flag = false
	runtime._body_swap_tick(0.1)
	check(not runtime._suspended, "a source that goes inactive resumes the old body")
	check(runtime.pony == old_pony, "the old body keeps the act when the source is gone")
	check(int(runtime.state) == RUNTIME.State.ACTIVE, "the state survives a gone source")
	runtime.force_stop()
	_free_fixture(f)


## No new body and no old body: the watchdog ends through the one exit.
func _check_watchdog() -> void:
	var f := _fixture()
	var main: FakeMain = f["main"]
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	var source: FakeSource = f["source"]
	runtime._suspend_for_body_swap(source)
	old_pony.free()
	source.changing = true
	runtime._body_swap_tick(RUNTIME.BODY_SWAP_WATCHDOG_S + 1.0)
	check(int(runtime.state) == RUNTIME.State.IDLE, "the watchdog ends the act")
	check(main.active_runtime == null, "the watchdog clears the active runtime")
	check(not main.body_swap_pending(), "the watchdog clears the pending swap")
	_free_fixture(f)


## A new body that is not an adult mare ends cleanly instead of resuming.
func _check_invalid_shape() -> void:
	var f := _fixture()
	var main: FakeMain = f["main"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	var eligibility := FakeEligibility.new()
	eligibility.allow = false
	main.eligibility = eligibility
	runtime._suspend_for_body_swap(source)
	var new_pony := _pony("Young Shape", "YoungBody")
	root.add_child(new_pony)
	source.new_pony = new_pony
	main._on_pony(new_pony)
	check(int(runtime.state) == RUNTIME.State.IDLE, "an ineligible shape ends the act")
	check(main.active_runtime == null, "an ineligible shape clears the active runtime")
	check(not new_pony.has_meta("sex_active"), "an ineligible shape keeps no act flag")
	_free_fixture(f)


## Closing the world while the act is suspended is the same one exit, not a second teardown.
func _check_world_close() -> void:
	var f := _fixture()
	var main: FakeMain = f["main"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	runtime._suspend_for_body_swap(source)
	runtime.force_stop()
	check(int(runtime.state) == RUNTIME.State.IDLE, "a world close during a swap ends the act")
	check(not main.body_swap_pending(), "a world close clears the pending swap")
	_free_fixture(f)


## The player's own ask during a disguise: the handover resumes the same act and the one
## exceptional beat is recorded once, with the spike, the impression and the peak.
func _check_form_reveal() -> void:
	var f := _fixture()
	var main: FakeMain = f["main"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	main.memory = FakeMemory.new()
	var director := FakeDirector.new()
	director.name = "FakeDirector"
	root.add_child(director)
	source.shape = "fluttershy"
	source.asks = true
	director._turn_id = 1
	director._player_text = "show me the real you"
	runtime._talk_tick(0.016)
	check(source.true_requests == 1, "the ask starts a true-form change")
	check(source.player_request, "the ask marks the change as the player's")
	check(source.changing, "the source is changing after the ask")
	runtime._body_swap_tick(0.1)
	check(runtime._suspended, "the act suspends for the reveal")
	var new_pony := _pony("Test Mare", "TrueBody")
	root.add_child(new_pony)
	source.new_pony = new_pony
	source.shape = ""
	main._on_pony(new_pony)
	check(not runtime._suspended, "the reveal resumes the same act")
	check(runtime.pony == new_pony, "the reveal keeps the act on the new body")
	check(runtime._form_reveal_done, "the requested reveal is recorded once")
	check(float(runtime.satisfaction) >= RUNTIME.FORM_REVEAL_HEAT - 0.01,
		"the reveal spikes readiness")
	var memory: FakeMemory = main.memory
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
	var values: Dictionary = runtime._summary_values()
	check(bool(values.get("form_reveal", false)), "the summary sees the reveal")
	# Once per act: a second ask while disguised again does nothing.
	source.shape = "rarity"
	source.true_requests = 0
	director._turn_id = 2
	director._player_text = "show me the real you"
	runtime._talk_tick(0.016)
	check(source.true_requests == 0, "a second ask in the same act does nothing")
	runtime.force_stop()
	director.queue_free()
	_free_fixture(f)


## Her offer after a climax, and a named shape: the act resumes on the disguise with no
## exceptional beat.
func _check_shape_offer() -> void:
	var f := _fixture()
	var main: FakeMain = f["main"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	main.memory = FakeMemory.new()
	source.shape = ""
	runtime._shape_offer_tick()
	check(runtime._shape_offer_done and runtime._shape_offer_pending,
		"a true-form climax offers the shape change")
	runtime._form_hint_tick()
	check(str(runtime._form_hint) == RUNTIME.FORM_HINT_SHAPE, "the offer names the pony in the hint")
	var director := FakeDirector.new()
	director.name = "FakeDirector"
	root.add_child(director)
	source.named = "rarity"
	director._turn_id = 1
	director._player_text = "Rarity"
	runtime._talk_tick(0.016)
	check(source.shape_requests == ["rarity"], "the named mare starts the change")
	check(not runtime._shape_offer_pending, "the offer is consumed by the name")
	check(source.player_marks.has(true), "a named shape is the player's ask")
	runtime._body_swap_tick(0.1)
	check(runtime._suspended, "the named change suspends the act")
	var new_pony := _pony("Test Mare", "ShapeBody")
	root.add_child(new_pony)
	source.new_pony = new_pony
	source.shape = "rarity"
	main._on_pony(new_pony)
	check(not runtime._form_reveal_done, "a named shape is not an exceptional reveal")
	check(not runtime._shape_offer_pending, "the player's named shape spends the offer")
	var memory: FakeMemory = main.memory
	check(memory.impressions.is_empty(), "a named shape writes no reveal memory")
	check(memory.peaks.is_empty(), "a named shape records no reveal peak")
	runtime.force_stop()
	director.queue_free()
	_free_fixture(f)


## The offer gate and the act-HUD hint states.
func _check_offer_gate() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	source.shape = "rarity"
	runtime._shape_offer_tick()
	check(not runtime._shape_offer_done, "a disguise gets no shape offer")
	source.shape = ""
	runtime.pony_climaxes = 0
	runtime._shape_offer_tick()
	check(not runtime._shape_offer_done, "the offer waits for a climax")
	runtime.pony_climaxes = 1
	runtime._shape_offer_tick()
	check(runtime._shape_offer_done and runtime._shape_offer_pending,
		"the offer is made once after a climax")
	source.shape = "fluttershy"
	runtime._shape_offer_pending = false
	runtime._form_reveal_done = false
	runtime._form_hint_tick()
	check(str(runtime._form_hint) == RUNTIME.FORM_HINT_ASK,
		"a disguise invites the reveal ask")
	runtime._form_reveal_done = true
	runtime._form_hint_tick()
	check(str(runtime._form_hint).is_empty(), "a used reveal hides the hint")
	runtime._form_reveal_done = false
	runtime._shape_offer_pending = true
	runtime.force_stop()
	check(not runtime._shape_offer_pending, "the act end drops the pending offer")
	check(str(runtime._form_hint).is_empty(), "the act end hides the hint")
	_free_fixture(f)


## The cached hint is cleared by the state change, not only by the next ACTIVE tick.
func _check_hint_states() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	source.shape = "fluttershy"
	runtime._form_reveal_done = false
	runtime._form_hint_tick()
	check(str(runtime._form_hint) == RUNTIME.FORM_HINT_ASK, "a disguise invites the ask")
	runtime.state = RUNTIME.State.CLIMAX
	runtime._form_hint_tick()
	check(str(runtime._form_hint).is_empty(), "the climax state clears the hint")
	runtime.state = RUNTIME.State.AFTERGLOW
	runtime._form_hint_tick()
	check(str(runtime._form_hint).is_empty(), "the afterglow state clears the hint")
	runtime.state = RUNTIME.State.RESTORE
	runtime._form_hint_tick()
	check(str(runtime._form_hint).is_empty(), "the restore state clears the hint")
	runtime.state = RUNTIME.State.ACTIVE
	runtime._form_hint_tick()
	check(str(runtime._form_hint) == RUNTIME.FORM_HINT_ASK, "the active state restores the ask")
	runtime.force_stop()
	_free_fixture(f)


## A named shape whose handover fails puts the offer back instead of spending it.
func _check_failed_named_offer() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	var source: FakeSource = f["source"]
	source.shape = ""
	runtime._shape_offer_tick()
	check(runtime._shape_offer_pending, "the offer is pending before the name")
	var director := FakeDirector.new()
	director.name = "FakeDirector"
	root.add_child(director)
	source.named = "rarity"
	director._turn_id = 1
	director._player_text = "Rarity"
	runtime._talk_tick(0.016)
	check(source.shape_requests == ["rarity"], "the named mare starts the change")
	check(not runtime._shape_offer_pending, "the name consumes the offer")
	runtime._swap_clock = 0.0
	runtime._body_swap_tick(0.1)
	check(runtime._suspended, "the named change suspends the act")
	source.changing = false
	runtime._body_swap_tick(0.1)
	check(not runtime._suspended, "the failed named change resumes the old body")
	check(runtime.pony == old_pony, "the old body keeps the act")
	check(runtime._shape_offer_pending, "a failed named change puts the offer back")
	check(str(runtime._form_hint) == RUNTIME.FORM_HINT_SHAPE, "the hint returns with the offer")
	runtime.force_stop()
	director.queue_free()
	_free_fixture(f)


## A player-named change whose new body reports no shape is neutral, not a reveal. The offer is
## still the player's choice, so it is spent.
func _check_named_without_shape() -> void:
	var f := _fixture()
	var main: FakeMain = f["main"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	main.memory = FakeMemory.new()
	source.shape = ""
	runtime._shape_offer_tick()
	var director := FakeDirector.new()
	director.name = "FakeDirector"
	root.add_child(director)
	source.named = "rarity"
	director._turn_id = 1
	director._player_text = "Rarity"
	runtime._talk_tick(0.016)
	runtime._body_swap_tick(0.1)
	check(runtime._suspended, "the named change suspends the act")
	var new_pony := _pony("Test Mare", "EmptyShapeBody")
	root.add_child(new_pony)
	source.new_pony = new_pony
	source.shape = ""
	main._on_pony(new_pony)
	check(not runtime._form_reveal_done, "a named change with no shape is not a reveal")
	var memory: FakeMemory = main.memory
	check(memory.impressions.is_empty(), "a named change with no shape writes no reveal memory")
	check(not runtime._shape_offer_pending, "the player's named shape spends the offer")
	runtime.force_stop()
	director.queue_free()
	_free_fixture(f)


## Her own AI changes shape while the player's post-climax offer waits: the neutral handover
## keeps the offer. The shape the player names still spends it.
func _check_ai_change_keeps_offer() -> void:
	var f := _fixture()
	var main: FakeMain = f["main"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	source.shape = ""
	runtime._shape_offer_tick()
	check(runtime._shape_offer_pending, "the offer is pending before her change")
	source.changing = true
	runtime._swap_clock = 0.0
	runtime._body_swap_tick(0.1)
	check(runtime._suspended, "her own change suspends the offered act")
	var ai_body := _pony("Test Mare", "AiOfferBody")
	root.add_child(ai_body)
	source.new_pony = ai_body
	source.shape = "fluttershy"
	source.changing = false
	main._on_pony(ai_body)
	check(not runtime._suspended, "her own change resumes the act")
	check(runtime._shape_offer_pending, "her own change keeps the player's offer")
	runtime._form_hint_tick()
	check(str(runtime._form_hint) == RUNTIME.FORM_HINT_SHAPE,
		"the hint still names the player's offer")
	var director := FakeDirector.new()
	director.name = "FakeDirector"
	root.add_child(director)
	source.named = "rarity"
	director._turn_id = 1
	director._player_text = "Rarity"
	runtime._talk_tick(0.016)
	check(source.shape_requests == ["rarity"], "the player's name reaches the source")
	check(source.player_marks.has(true), "the player's name is marked as the player's")
	check(not runtime._shape_offer_pending, "the player's named shape spends the offer")
	runtime.force_stop()
	director.queue_free()
	_free_fixture(f)


## The source clears its changing state before the new body's spawn reaches the entry. The
## watcher keeps the act suspended for the grace, then the entry adopts the body the source still
## reports; no second runtime attaches to it.
func _check_late_adoption() -> void:
	var f := _fixture()
	var main: FakeMain = f["main"]
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	var source: FakeSource = f["source"]
	source.changing = true
	runtime._suspend_for_body_swap(source)
	var late_pony := _pony("Late Mare", "LateBody")
	root.add_child(late_pony)
	source.new_pony = late_pony
	source.changing = false
	runtime._body_swap_tick(RUNTIME.BODY_SWAP_ADOPT_GRACE_S * 0.5)
	check(runtime._suspended, "a late body keeps the act suspended")
	check(runtime.pony == old_pony, "the old body is not resumed while the new body exists")
	check(not main._runtimes.has(late_pony), "no runtime attaches to the late body yet")
	runtime._body_swap_tick(RUNTIME.BODY_SWAP_ADOPT_GRACE_S)
	check(not runtime._suspended, "the entry adopts the late body after the grace")
	check(runtime.pony == late_pony, "the act resumes on the late body")
	check(runtime.get_parent() == late_pony, "the runtime moves under the late body")
	check(main._runtimes.get(late_pony) == runtime, "the late body maps to the same runtime")
	check(main._runtimes.size() == 1, "the late adoption creates no second runtime")
	runtime.force_stop()
	_free_fixture(f)


## Her own change can start while the act is already restoring. The restore finishes through the
## one exit; the change is not suspended and leaves no pending swap or stale source.
func _check_restore_change() -> void:
	var f := _fixture()
	var main: FakeMain = f["main"]
	var runtime: Node = f["runtime"]
	var source: FakeSource = f["source"]
	runtime.state = RUNTIME.State.RESTORE
	runtime._restore_left = RUNTIME.RESTORE_SECONDS
	var other := _pony("Other Mare", "OtherBody")
	root.add_child(other)
	source.changing = true
	source.old_pony = other
	runtime._body_swap_tick(0.1)
	check(int(runtime.state) == RUNTIME.State.RESTORE,
		"another body's change leaves the restore alone")
	check(not main.body_swap_pending(), "another body's change records no pending swap")
	source.old_pony = runtime.pony
	runtime._body_swap_tick(0.1)
	check(int(runtime.state) == RUNTIME.State.IDLE,
		"the act pony's change during restore finishes the act")
	check(not runtime._suspended, "a change during restore never suspends")
	check(not main.body_swap_pending(), "a change during restore records no pending swap")
	check(runtime._swap_source == null, "the one exit drops the swap source")
	check(main.active_runtime == null, "the one exit clears the active runtime")
	other.queue_free()
	_free_fixture(f)


## A body another system is holding refuses the player's request instead of leaving a held body.
func _check_held_guard() -> void:
	var f := _fixture()
	var runtime: Node = f["runtime"]
	var old_pony: FakePony = f["old"]
	old_pony.held = true
	var result: Dictionary = runtime.request_form_change(true, "", true)
	check(not bool(result.get("ok", false)), "a held body refuses a form request")
	check(str(result.get("reason", "")) == "she is held", "the refusal names the hold")
	old_pony.held = false
	runtime.force_stop()
	_free_fixture(f)
