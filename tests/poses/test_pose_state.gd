extends SceneTree
## The pure pose state and edge math: the transition table, the request codes, the edge start and
## validation, the duration/constraint resolution, the channel weights and switches, the events,
## the completion and the reused arrays. Plain dictionaries only: no scene, no node, no autoload.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_pose_state.gd

const STATE := preload("res://mods/unfplap/poses/pose_state.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const SOURCE := "res://mods/unfplap/poses/pose_state.gd"

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	_check_next()
	_check_request_code()
	_check_requirement_code()
	_check_result()
	_check_start()
	_check_duration()
	_check_channels()
	_check_constraints()
	_check_events()
	_check_completion()
	_check_interrupt()
	_check_reuse()
	_check_base()
	_check_pure_source()

	print("POSE_STATE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("POSE_STATE_PASS")
	quit(0 if failures == 0 else 1)


## One valid edge dictionary; every check starts from its own copy.
func _edge() -> Dictionary:
	return {
		"version": 1,
		"id": "standing__standing_test",
		"from": "standing",
		"to": "standing_test",
		"phases": ["active"],
		"requires": {"features": [], "consent": "", "forms": [], "views": []},
		"duration": 0.6,
		"easing": "smoothstep",
		"channels": {
			"base": {"kind": "hold"},
			"presentation": {"kind": "switch", "at": 0.0, "profile": "standing_test"},
			"controls": {"kind": "switch", "at": 0.0, "set": "standing_test"},
		},
		"constraints": [],
		"events": [{"at": 0.0, "kind": "status", "value": "test"}],
		"interrupt": {"climax": "hold", "teardown": "abort"},
	}


func _run(edge: Dictionary) -> Variant:
	return STATE.start_edge(edge, "standing", "standing_test")


func _check_next() -> void:
	check(STATE.next(VIEW.IDLE, "begin") == VIEW.ENTERING, "begin enters")
	check(STATE.next(VIEW.ENTERING, "entered") == VIEW.STEADY, "entered settles")
	check(STATE.next(VIEW.STEADY, "request") == VIEW.TRANSITIONING, "request transitions")
	check(STATE.next(VIEW.TRANSITIONING, "complete") == VIEW.STEADY, "complete settles")
	check(STATE.next(VIEW.STEADY, "exit") == VIEW.EXITING, "exit leaves steady")
	check(STATE.next(VIEW.TRANSITIONING, "exit") == VIEW.EXITING, "exit aborts a transition")
	check(STATE.next(VIEW.ENTERING, "exit") == VIEW.EXITING, "exit leaves entering")
	check(STATE.next(VIEW.EXITING, "released") == VIEW.IDLE, "released returns to idle")
	check(STATE.next(VIEW.IDLE, "exit") == VIEW.IDLE, "idle cannot exit")
	check(STATE.next(VIEW.EXITING, "exit") == VIEW.EXITING, "exiting cannot exit again")
	check(STATE.next(VIEW.IDLE, "released") == VIEW.IDLE, "idle cannot release")
	check(STATE.next(VIEW.STEADY, "released") == VIEW.STEADY, "released outside exiting is a no-op")
	check(STATE.next(VIEW.STEADY, "begin") == VIEW.STEADY, "begin from a live state is a no-op")
	check(STATE.next(VIEW.TRANSITIONING, "begin") == VIEW.TRANSITIONING,
		"begin from a transition is a no-op")
	check(STATE.next(VIEW.STEADY, "entered") == VIEW.STEADY, "entered outside entering is a no-op")
	check(STATE.next(VIEW.TRANSITIONING, "request") == VIEW.TRANSITIONING,
		"request during a transition is a no-op")
	check(STATE.next(VIEW.STEADY, "complete") == VIEW.STEADY,
		"complete outside a transition is a no-op")
	check(STATE.next(VIEW.IDLE, "complete") == VIEW.IDLE, "complete in idle is a no-op")
	check(STATE.next(VIEW.STEADY, "unknown") == VIEW.STEADY, "an unknown event leaves the state")


func _check_request_code() -> void:
	check(STATE.request_code(VIEW.IDLE, 0, "standing", "standing", false,
		{"form_ok": false}) == "same", "same is checked before the phase")
	check(STATE.request_code(VIEW.TRANSITIONING, 2, "a", "a", true) == "same",
		"same is checked before busy")
	for phase: int in [1, 3, 4, 5]:
		check(STATE.request_code(VIEW.STEADY, phase, "standing", "standing_test", true) ==
			"bad_phase", "act phase %d refuses" % phase)
	check(STATE.request_code(VIEW.TRANSITIONING, 1, "standing", "standing_test", true) ==
		"bad_phase", "the act phase is checked before busy")
	check(STATE.request_code(VIEW.TRANSITIONING, 2, "standing", "standing_test", true) == "busy",
		"a transition is busy")
	check(STATE.request_code(VIEW.TRANSITIONING, 2, "a", "b", false) == "busy",
		"busy is checked before the edge")
	for pose: int in [VIEW.IDLE, VIEW.ENTERING, VIEW.EXITING]:
		check(STATE.request_code(pose, 2, "standing", "standing_test", true) == "not_steady",
			"pose state %d is not steady" % pose)
	check(STATE.request_code(VIEW.IDLE, 2, "a", "b", false) == "not_steady",
		"not_steady is checked before the edge")
	check(STATE.request_code(VIEW.STEADY, 2, "standing", "standing_test", false) == "no_edge",
		"a missing edge refuses")
	check(STATE.request_code(VIEW.STEADY, 2, "standing", "standing_test", false,
		{"form_ok": false}) == "no_edge", "no_edge is checked before the checks")
	check(STATE.request_code(VIEW.STEADY, 2, "standing", "standing_test", true,
		{"form_ok": false}) == "unsupported_form", "an unsupported form refuses")
	check(STATE.request_code(VIEW.STEADY, 2, "standing", "standing_test", true,
		{"view_ok": false}) == "unsupported_view", "an unsupported view refuses")
	check(STATE.request_code(VIEW.STEADY, 2, "standing", "standing_test", true,
		{"features_ok": false}) == "refused", "a missing feature refuses")
	check(STATE.request_code(VIEW.STEADY, 2, "standing", "standing_test", true,
		{"consent_ok": false}) == "refused", "a missing consent refuses")
	check(STATE.request_code(VIEW.STEADY, 2, "standing", "standing_test", true,
		{"asset_ok": false}) == "missing_asset", "a missing asset refuses")
	check(STATE.request_code(VIEW.STEADY, 2, "standing", "standing_test", true,
		{"locked": true}) == "locked", "a locked request refuses")
	check(STATE.request_code(VIEW.STEADY, 2, "standing", "standing_test", true) == "ok",
		"the default checks accept")
	check(STATE.request_code(VIEW.STEADY, 2, "standing", "standing_test", true,
		{"form_ok": true, "view_ok": true, "features_ok": true, "consent_ok": true,
			"asset_ok": true, "locked": false}) == "ok",
		"all explicit checks accept")
	check(STATE.request_code(VIEW.STEADY, 2, "standing", "standing_test", true,
		{"form_ok": false, "view_ok": false}) == "unsupported_form",
		"the form is checked before the view")
	check(STATE.request_code(VIEW.STEADY, 2, "standing", "standing_test", true,
		{"view_ok": false, "features_ok": false}) == "unsupported_view",
		"the view is checked before refusal")
	check(STATE.request_code(VIEW.STEADY, 2, "standing", "standing_test", true,
		{"features_ok": false, "asset_ok": false}) == "refused",
		"refusal is checked before the asset")
	check(STATE.request_code(VIEW.STEADY, 2, "standing", "standing_test", true,
		{"asset_ok": false, "locked": true}) == "missing_asset",
		"the asset is checked before the lock")


func _check_requirement_code() -> void:
	check(STATE.requirement_code({}) == "ok", "an edge without requirements passes")
	check(STATE.requirement_code({"requires": {}}) == "ok", "empty requirements pass")
	check(STATE.requirement_code({"requires": {"forms": [], "views": []}},
		{"form_ok": false, "view_ok": false}) == "ok",
		"empty form/view requirements ignore the flags")
	check(STATE.requirement_code({"requires": {"forms": ["human"]}}) == "ok",
		"a missing flag defaults true")
	var forms := {"requires": {"forms": ["human", "pony"]}}
	check(STATE.requirement_code(forms, {"form_ok": false}) == "unsupported_form",
		"a form requirement refuses")
	var views := {"requires": {"views": ["desktop", "vr"]}}
	check(STATE.requirement_code(views, {"view_ok": false}) == "unsupported_view",
		"a view requirement refuses")
	check(STATE.requirement_code({"requires": {"forms": ["human"], "views": ["vr"]}},
		{"form_ok": false, "view_ok": false}) == "unsupported_form",
		"the form requirement is checked before the view")
	check(STATE.requirement_code({"requires": {"views": ["vr"], "features": ["anatomy"]}},
		{"view_ok": false, "features_ok": false}) == "unsupported_view",
		"the view requirement is checked before refusal")
	check(STATE.requirement_code({"requires": {"features": ["anatomy"]}},
		{"features_ok": false}) == "refused", "a feature requirement refuses")
	check(STATE.requirement_code({"requires": {"consent": "bond"}},
		{"consent_ok": false}) == "refused", "a consent requirement refuses")
	check(STATE.requirement_code({"requires": {"features": ["anatomy"]}},
		{"consent_ok": false}) == "ok",
		"a feature requirement does not read the other flags")
	check(STATE.requirement_code({"requires": {"features": [], "consent": ""}},
		{"features_ok": false, "consent_ok": false}) == "ok",
		"empty feature and consent requirements pass")


func _check_result() -> void:
	var ok := STATE.result("ok")
	check(bool(ok.get("ok")) and str(ok.get("code")) == "ok", "ok accepts")
	check(str(ok.get("edge")) == "" and str(ok.get("reason")) == "",
		"an accepted result carries no edge or reason")
	var refused := STATE.result("no_edge", "standing__standing_test", "no authored edge")
	check(not bool(refused.get("ok")), "only ok accepts")
	check(str(refused.get("code")) == "no_edge", "the result keeps the code")
	check(str(refused.get("edge")) == "standing__standing_test", "the result keeps the edge")
	check(str(refused.get("reason")) == "no authored edge", "the result keeps the reason")
	check(ok.size() == 4, "the result stays small")


func _check_start() -> void:
	var edge := _edge()
	var run: Variant = _run(edge)
	check(run != null, "a valid edge starts")
	if run == null:
		return
	check(STATE.Run.start(_edge(), "standing", "standing_test") != null,
		"Run.start is usable without the wrapper")
	check(is_same(run.edge, edge), "the run keeps the edge by reference")
	check(run.id == "standing__standing_test", "the run keeps the edge id")
	check(run.from_id == "standing" and run.to_id == "standing_test",
		"the run keeps the edge endpoints")
	check(near(run.t, 0.0) and not run.complete(), "a fresh run has not started its clock")
	check(near(run.duration, 0.6), "the edge duration is the base")
	check(near(run.weight, 1.0), "a hold base starts at full weight")
	check(run.channel_weight("missing") == 0.0, "an unknown channel has no weight")
	var broken := _edge()
	broken.erase("id")
	check(_run(broken) == null, "an edge without an id is refused")
	broken = _edge()
	broken.erase("from")
	check(_run(broken) == null, "an edge without a from is refused")
	broken = _edge()
	broken.erase("to")
	check(_run(broken) == null, "an edge without a to is refused")
	broken = _edge()
	broken.erase("channels")
	check(_run(broken) == null, "an edge without channels is refused")
	check(_run(_edge()) != null, "the control edge still starts")
	check(STATE.start_edge(_edge(), "standing_test", "standing") == null,
		"a mismatched from/to is refused")
	broken = _edge()
	broken["channels"] = {"base": {"kind": "warp"}}
	check(_run(broken) == null, "an unknown channel kind is refused")
	broken = _edge()
	broken["channels"] = {"base": {}}
	check(_run(broken) == null, "a channel without a kind is refused")
	broken = _edge()
	broken["channels"] = {"base": {"kind": "hold"}, "controls": {"kind": "switch"}}
	check(_run(broken) == null, "a switch without at is refused")
	broken = _edge()
	broken["duration"] = "long"
	check(_run(broken) == null, "a non-number duration is refused")
	broken = _edge()
	broken["constraints"] = ["contact after base@0.5"]
	check(_run(broken) == null, "a constraint naming an unknown channel is refused")


func _check_duration() -> void:
	var edge := _edge()
	edge["channels"] = {"base": {"kind": "blend", "duration": 0.3}}
	var run: Variant = _run(edge)
	check(run != null and near(run.duration, 0.6), "the edge duration wins over a short channel")
	edge = _edge()
	edge["channels"] = {"base": {"kind": "blend", "start": 0.4, "duration": 0.5}}
	run = _run(edge)
	check(run != null and near(run.duration, 0.9), "a longer channel extends the duration")
	edge = _edge()
	edge["channels"] = {"base": {"kind": "hold"}, "controls": {"kind": "switch", "at": 1.2}}
	run = _run(edge)
	check(run != null and near(run.duration, 1.2), "a later switch extends the duration")
	edge = _edge()
	edge.erase("duration")
	edge["channels"] = {"base": {"kind": "blend", "duration": 0.8}}
	run = _run(edge)
	check(run != null and near(run.duration, 0.8), "per-channel durations resolve without an edge one")
	edge = _edge()
	edge.erase("duration")
	edge["channels"] = {"base": {"kind": "hold"}}
	check(_run(edge) == null, "a hold without any duration is refused")
	edge = _edge()
	edge.erase("duration")
	edge["channels"] = {"base": {"kind": "blend"}}
	check(_run(edge) == null, "a blend without any duration is refused")
	edge = _edge()
	edge["duration"] = 0.2
	edge["channels"] = {"base": {"kind": "blend", "duration": 0.1}}
	run = _run(edge)
	check(run != null and near(run.duration, 0.2), "the edge duration is a floor")


func _check_channels() -> void:
	var edge := _edge()
	edge["channels"] = {"base": {"kind": "hold"}}
	var run: Variant = _run(edge)
	check(run != null and near(run.channel_weight("base"), 1.0), "a hold starts settled")
	run.tick(0.1)
	check(near(run.channel_weight("base"), 1.0) and near(run.weight, 1.0),
		"a hold keeps full weight")
	edge = _edge()
	edge["duration"] = 1.0
	edge["channels"] = {"base": {"kind": "blend"}}
	run = _run(edge)
	check(near(run.channel_weight("base"), 0.0), "a blend starts at zero")
	run.tick(0.25)
	check(near(run.channel_weight("base"), 0.15625) and near(run.weight, 0.15625),
		"a smoothstep blend eases its quarter point")
	run.tick(0.25)
	check(near(run.channel_weight("base"), 0.5) and near(run.weight, 0.5),
		"a blend is half at its midpoint")
	run.tick(0.5)
	check(near(run.channel_weight("base"), 1.0) and near(run.weight, 1.0),
		"a blend settles at one")
	edge = _edge()
	edge["duration"] = 1.0
	edge["channels"] = {"base": {"kind": "delta"}}
	run = _run(edge)
	run.tick(0.5)
	check(near(run.channel_weight("base"), 0.5), "a delta eases like a blend")
	edge = _edge()
	edge["duration"] = 1.0
	edge["easing"] = "linear"
	edge["channels"] = {"base": {"kind": "blend"}}
	run = _run(edge)
	run.tick(0.25)
	check(near(run.channel_weight("base"), 0.25), "the edge easing applies")
	edge = _edge()
	edge["duration"] = 1.0
	edge["easing"] = "linear"
	edge["channels"] = {"base": {"kind": "blend", "easing": "smoothstep"}}
	run = _run(edge)
	run.tick(0.25)
	check(near(run.channel_weight("base"), 0.15625), "a channel easing wins over the edge's")
	edge = _edge()
	edge["duration"] = 1.0
	edge["channels"] = {"base": {"kind": "hold"},
		"controls": {"kind": "switch", "at": 0.5}}
	run = _run(edge)
	run.tick(0.4)
	check(run.switches().is_empty(), "a switch does not fire early")
	check(near(run.channel_weight("controls"), 0.0), "an unfired switch has no weight")
	run.tick(0.1)
	check(run.switches() == ["controls"], "a switch fires once")
	check(near(run.channel_weight("controls"), 1.0), "a fired switch has weight")
	run.tick(0.1)
	check(run.switches().is_empty(), "a switch does not fire twice")
	edge = _edge()
	edge["duration"] = 1.0
	edge["channels"] = {"base": {"kind": "hold"}, "lock": {"kind": "lock"}}
	run = _run(edge)
	check(near(run.channel_weight("lock"), 1.0), "a lock starts at full weight")
	run.tick(0.5)
	check(near(run.channel_weight("lock"), 1.0) and run.switches().is_empty(),
		"a lock is a signal, not a switch")
	edge = _edge()
	edge["duration"] = 1.0
	edge["channels"] = {"base": {"kind": "path"}}
	run = _run(edge)
	check(run != null, "a path is accepted")
	run.tick(0.5)
	check(run != null and near(run.channel_weight("base"), 0.5),
		"a path follows the blend math")


func _check_constraints() -> void:
	var edge := _edge()
	edge["duration"] = 1.2
	edge["channels"] = {"base": {"kind": "hold"},
		"contact": {"kind": "blend", "start": 0.2, "duration": 0.2}}
	edge["constraints"] = ["contact after base@0.55"]
	var run: Variant = _run(edge)
	check(run != null, "a valid constraint starts")
	if run != null:
		check(near(float(run._channels["contact"]["start"]), 0.55),
			"a constraint floors the channel start")
		run.tick(0.5)
		check(near(run.channel_weight("contact"), 0.0), "the floored channel has not started")
		run.tick(0.1)
		check(near(run.channel_weight("contact"), 0.15625),
			"the floored channel eases from its floor")
	edge = _edge()
	edge["duration"] = 1.2
	edge["channels"] = {"base": {"kind": "hold"}, "contact": {"kind": "blend", "duration": 0.2}}
	edge["constraints"] = ["contact after unknown@0.5"]
	check(_run(edge) == null, "a constraint naming an unknown other channel is refused")
	edge = _edge()
	edge["duration"] = 1.0
	edge["channels"] = {"a": {"kind": "blend"}, "b": {"kind": "blend"}}
	edge["constraints"] = ["a after b@1.0", "b after a@1.0"]
	check(_run(edge) == null, "a constraint cycle is refused")
	edge = _edge()
	edge["duration"] = 1.0
	edge["channels"] = {"a": {"kind": "blend"}}
	edge["constraints"] = ["a after a@1.0"]
	check(_run(edge) == null, "a self constraint is a cycle")
	edge = _edge()
	edge["duration"] = 1.0
	edge["channels"] = {"a": {"kind": "blend"}, "b": {"kind": "blend"},
		"c": {"kind": "blend"}}
	edge["constraints"] = ["b after a@0.2", "c after b@0.1"]
	run = _run(edge)
	check(run != null, "a constraint chain resolves")
	if run != null:
		check(near(float(run._channels["c"]["start"]), 0.3), "the chain floors through both links")
	edge = _edge()
	edge["constraints"] = ["contact base"]
	check(_run(edge) == null, "a malformed constraint is refused")
	edge = _edge()
	edge["constraints"] = ["contact after base@soon"]
	check(_run(edge) == null, "a non-number constraint delay is refused")


func _check_events() -> void:
	var edge := _edge()
	edge["duration"] = 1.0
	edge["channels"] = {"base": {"kind": "hold"}}
	edge["events"] = [
		{"at": 0.0, "kind": "status", "value": "zero"},
		{"at": 0.5, "kind": "status", "value": "mid_a"},
		{"at": 0.5, "kind": "status", "value": "mid_b"},
		{"at": 1.0, "kind": "status", "value": "end"},
	]
	var run: Variant = _run(edge)
	check(run != null, "an edge with events starts")
	if run == null:
		return
	var seen: Array = run.events()
	run.tick(0.0)
	check(run.events().size() == 1 and str(run.events()[0].get("value")) == "zero",
		"tick(0.0) fires the at-zero event")
	check(is_same(run.events(), seen), "the events array is reused")
	check(is_same(run.events()[0], edge["events"][0]), "a fired event is the edge's dictionary")
	run.tick(0.0)
	check(run.events().is_empty(), "an at-zero event does not fire twice")
	run.tick(0.25)
	check(run.events().is_empty(), "no event fires before its time")
	run.tick(0.25)
	check(run.events().size() == 2, "the mid events fire together")
	check(str(run.events()[0].get("value")) == "mid_a"
		and str(run.events()[1].get("value")) == "mid_b", "the events keep their authored order")
	run.tick(0.5)
	check(run.events().size() == 1 and str(run.events()[0].get("value")) == "end",
		"the last event fires once")
	run.tick(0.1)
	check(run.events().is_empty(), "a fired event does not fire again")
	check(is_same(run.events(), seen), "the events array stays the same instance")


func _check_completion() -> void:
	var edge := _edge()
	edge["duration"] = 1.0
	edge["channels"] = {"base": {"kind": "blend"}}
	var run: Variant = _run(edge)
	check(run != null, "a blend edge starts")
	if run == null:
		return
	check(not run.complete(), "a fresh run is not complete")
	run.tick(0.5)
	check(not run.complete(), "a run is not complete before its duration")
	run.tick(0.5)
	check(run.complete() and near(run.t, 1.0), "a run completes at its duration")
	run.tick(10.0)
	check(run.complete() and near(run.t, 1.0), "the clock is capped at the duration")
	check(run.events().is_empty(), "a tick after completion does not re-fire")
	edge = _edge()
	edge["duration"] = 0.5
	edge["channels"] = {"base": {"kind": "hold"}, "controls": {"kind": "switch", "at": 1.0}}
	run = _run(edge)
	check(run != null and near(run.duration, 1.0), "a later switch extends completion")
	if run != null:
		run.tick(0.75)
		check(not run.complete(), "the switch still holds the run open")
		run.tick(0.25)
		check(run.complete() and run.switches() == ["controls"], "the switch completes the run")
	edge = _edge()
	edge["duration"] = 0.5
	edge["channels"] = {"base": {"kind": "blend", "start": 0.8, "duration": 0.5}}
	run = _run(edge)
	check(run != null and near(run.duration, 1.3), "a late blend extends completion")
	if run != null:
		run.tick(1.0)
		check(not run.complete(), "the blend still holds the run open")
		run.tick(0.3)
		check(run.complete() and near(run.weight, 1.0), "the blend settles before completion")
	edge = _edge()
	edge["duration"] = 0.0
	edge["channels"] = {"base": {"kind": "hold"}}
	edge["events"] = []
	run = _run(edge)
	check(run != null and not run.complete(), "a zero-duration run still needs a tick")
	if run != null:
		run.tick(0.0)
		check(run.complete(), "a zero-duration run completes on tick(0.0)")


func _check_interrupt() -> void:
	var edge := _edge()
	edge.erase("interrupt")
	var run: Variant = _run(edge)
	check(run != null and run.interrupt_climax == "hold" and run.interrupt_teardown == "abort",
		"the interrupt policy defaults to hold/abort")
	edge = _edge()
	edge["interrupt"] = {"climax": "cut", "teardown": "hold"}
	run = _run(edge)
	check(run != null and run.interrupt_climax == "cut" and run.interrupt_teardown == "hold",
		"the edge interrupt override is copied")
	edge = _edge()
	edge["interrupt"] = {"teardown": "hold"}
	run = _run(edge)
	check(run != null and run.interrupt_climax == "hold" and run.interrupt_teardown == "hold",
		"a partial interrupt override keeps the default climax")
	edge = _edge()
	edge["duration"] = 0.5
	edge["channels"] = {"base": {"kind": "hold"}}
	edge["interrupt"] = {"climax": "hold", "teardown": "abort"}
	run = _run(edge)
	check(run != null, "an aborting edge starts")
	if run != null:
		run.tick(0.5)
		check(run.complete(), "the module completes regardless of the teardown policy")
		check(run.interrupt_teardown == "abort" and run.interrupt_climax == "hold",
			"the module does not act on the interrupt policy")


func _check_reuse() -> void:
	var edge := _edge()
	edge["duration"] = 1.0
	edge["channels"] = {"base": {"kind": "blend"}, "controls": {"kind": "switch", "at": 0.5}}
	var run: Variant = _run(edge)
	check(run != null, "the reuse edge starts")
	if run == null:
		return
	var events_ref: Array = run.events()
	var switches_ref: Array = run.switches()
	var base_ref: Dictionary = run._channels["base"]
	var order_ref: Array[String] = run._order
	run.tick(0.25)
	check(is_same(run.events(), events_ref) and is_same(run.switches(), switches_ref),
		"the event and switch arrays are the same instances")
	check(is_same(run._channels["base"], base_ref), "the channel record is reused")
	check(is_same(run._order, order_ref), "the channel order is reused")
	run.tick(0.5)
	check(is_same(run.events(), events_ref) and is_same(run.switches(), switches_ref),
		"the arrays survive a firing tick")
	check(is_same(run._channels["base"], base_ref), "the channel record survives a firing tick")


func _check_base() -> void:
	var edge := _edge()
	edge["duration"] = 0.5
	edge["channels"] = {"presentation": {"kind": "switch", "at": 0.0}}
	var run: Variant = _run(edge)
	check(run != null and near(run.weight, 1.0), "an absent base is fully weighted")
	edge = _edge()
	edge["duration"] = 0.5
	edge["channels"] = {"base": {"kind": "hold"}}
	run = _run(edge)
	check(run != null and near(run.weight, 1.0), "a hold base is fully weighted")
	edge = _edge()
	edge["duration"] = 1.0
	edge["channels"] = {"base": {"kind": "blend"}}
	run = _run(edge)
	check(run != null and near(run.weight, 0.0), "a blend base starts at zero")
	if run != null:
		run.tick(0.5)
		check(near(run.weight, 0.5), "a blend base follows its channel")
	edge = _edge()
	edge["duration"] = 1.0
	edge["channels"] = {"base": {"kind": "delta"}}
	run = _run(edge)
	check(run != null and near(run.weight, 0.0), "a delta base starts at zero")
	edge = _edge()
	edge["duration"] = 0.5
	edge["channels"] = {"base": {"kind": "lock"}}
	run = _run(edge)
	check(run != null and near(run.weight, 1.0), "a lock base is fully weighted")
	edge = _edge()
	edge["duration"] = 0.5
	edge["channels"] = {"base": {"kind": "hold"},
		"presentation": {"kind": "switch", "at": 0.0}}
	run = _run(edge)
	check(run != null and near(run.weight, 1.0), "a hold base with a switch starts full")
	if run != null:
		run.tick(0.0)
		check(run.switches() == ["presentation"] and near(run.weight, 1.0),
			"the switch fires without moving the hold weight")


func _check_pure_source() -> void:
	var source := FileAccess.get_file_as_string(SOURCE)
	check(not source.is_empty(), "poses/pose_state.gd exists")
	check(source.begins_with("extends RefCounted"), "the module is a RefCounted")
	for token: String in ["extends Node", "get_tree(", "FileAccess", "SETTINGS",
			"preload(\"res://world/",
			"preload(\"res://mods/unfplap/runtime.gd\")",
			"preload(\"res://mods/unfplap/main.gd\")",
			"preload(\"res://mods/unfplap/settings/service.gd\")",
			"preload(\"res://mods/unfplap/poses/service.gd\")",
			"_end_session", "release_pose", "leave_pose_start", "leave_pose_body",
			"_unlock_player"]:
		check(not source.contains(token), "the pose state stays pure: %s" % token)
	var stray_preloads := 0
	for line: String in source.split("\n"):
		if line.contains("preload(") and not line.contains("shared/pose_view.gd"):
			stray_preloads += 1
	check(stray_preloads == 0, "the only preload is the shared pose view")
	check(not source.contains("/service.gd\""), "the module preloads no service")
