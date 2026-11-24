extends "res://mods/unfplap/tests/support/suite.gd"
## The authored pose edges: the typed validator, the documents' requirement and policy rows and
## the edge run. Plain dictionaries and `FileAccess` only: no scene, no node, no autoload.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_pose_edge.gd

const SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const TRANSITION_SPEC := preload("res://mods/unfplap/poses/transition_spec.gd")
const STATE := preload("res://mods/unfplap/poses/pose_state.gd")

const FORWARD := "standing__standing_test"
const REVERSE := "standing_test__standing"
const FORWARD_PATH := "res://mods/unfplap/poses/transitions/standing__standing_test.json"
const REVERSE_PATH := "res://mods/unfplap/poses/transitions/standing_test__standing.json"
const ORAL_FORWARD_PATH := "res://mods/unfplap/poses/transitions/standing__standing_oral.json"
const ORAL_REVERSE_PATH := "res://mods/unfplap/poses/transitions/standing_oral__standing.json"
const FACESIT_FORWARD_PATH := "res://mods/unfplap/poses/transitions/missionary__bed_facesit.json"
const FACESIT_REVERSE_PATH := "res://mods/unfplap/poses/transitions/bed_facesit__missionary.json"


func run() -> void:
	_check_runs()
	_check_oral_documents()
	_check_oral_runs()
	_check_facesit_documents()
	_check_facesit_runs()
	_check_rejections()
	_check_shapes()
	if failures == 0:
		print("POSE_EDGE_PASS")
	finish()


func _read(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {}
	var data: Variant = parser.data
	return data as Dictionary if data is Dictionary else {}


func _document(edge_id: String) -> Dictionary:
	return _read(FORWARD_PATH) if edge_id == FORWARD else _read(REVERSE_PATH)


func _forward() -> Dictionary:
	return _read(FORWARD_PATH)


func _mutated(changes: Dictionary) -> Dictionary:
	var data := _forward()
	for key: String in changes.keys():
		data[key] = changes[key]
	return data


func _without(key: String) -> Dictionary:
	var data := _forward()
	data.erase(key)
	return data


func _with_requires(key: String, value: Variant) -> Dictionary:
	var data := _forward()
	var requires: Dictionary = data.get("requires", {})
	requires[key] = value
	return data


func _with_channel(name: String, value: Variant) -> Dictionary:
	var data := _forward()
	var channels: Dictionary = data.get("channels", {})
	channels[name] = value
	return data


func _errors(data: Dictionary, edge_id := FORWARD) -> Array[String]:
	return TRANSITION_SPEC.errors(edge_id, data, SPECS.SPECS)


func _rejects(data: Dictionary, text: String, edge_id := FORWARD) -> void:
	check(not _errors(data, edge_id).is_empty(), text)


## One synthetic raw spec row for the endpoint-table checks.
func _row(name: String, template: String, forms: Array, views: Array) -> Dictionary:
	var row: Dictionary = SPECS.spec(template).duplicate(true)
	row["id"] = name
	row["forms"] = forms
	row["views"] = views
	return row


func _check_runs() -> void:
	var forward := _forward()
	var run: Variant = STATE.start_edge(forward, SPECS.STANDING, SPECS.STANDING_TEST)
	check(run != null, "the forward edge starts")
	if run != null:
		check(near(run.duration, 0.6), "the forward clock is the edge duration")
		check(near(run.weight, 1.0), "the held base is fully weighted")
		check(near(run.channel_weight("base"), 1.0), "the base channel holds")
		check(near(run.channel_weight("anon"), 1.0), "the anon channel holds")
		check(near(run.channel_weight("controls"), 0.0), "the controls switch waits")
		run.tick(0.0)
		check(run.events().size() == 1, "the forward status event fires at zero")
		if run.events().size() == 1:
			var event: Dictionary = run.events()[0]
			check(str(event.get("kind", "")) == "status", "the forward event is a status")
			check(str(event.get("value", "")) == "test", "the forward status value is test")
		var names: Array = run.switches().duplicate()
		names.sort()
		check(names == ["controls", "presentation"], "the forward switches fire together")
		check(near(run.channel_weight("controls"), 1.0), "the controls switch has weight")
		check(near(run.channel_weight("presentation"), 1.0), "the presentation switch has weight")
		run.tick(0.6)
		check(run.complete(), "the forward edge completes at its duration")
		check(near(run.t, 0.6), "the forward clock stops at its duration")
		run.tick(0.6)
		check(run.events().is_empty(), "a completed forward edge fires no event")
		check(run.switches().is_empty(), "a completed forward edge fires no switch")
	var reverse := _document(REVERSE)
	var reverse_channels: Dictionary = reverse.get("channels", {})
	var controls: Dictionary = reverse_channels.get("controls", {})
	var presentation: Dictionary = reverse_channels.get("presentation", {})
	check(str(controls.get("set", "")) == SPECS.STANDING,
		"the reverse controls switch points at standing")
	check(str(presentation.get("profile", "")) == SPECS.STANDING,
		"the reverse presentation switch points at standing")
	var backward: Variant = STATE.start_edge(reverse, SPECS.STANDING_TEST, SPECS.STANDING)
	check(backward != null, "the reverse edge starts")
	if backward != null:
		backward.tick(0.0)
		check(backward.events().size() == 1, "the reverse status event fires at zero")
		if backward.events().size() == 1:
			var event: Dictionary = backward.events()[0]
			check(str(event.get("kind", "")) == "status", "the reverse event is a status")
			check(str(event.get("value", "")) == "standing", "the reverse status value is standing")
		var reverse_names: Array = backward.switches().duplicate()
		reverse_names.sort()
		check(reverse_names == ["controls", "presentation"], "the reverse switches fire together")
		backward.tick(0.6)
		check(backward.complete(), "the reverse edge completes at its duration")


func _check_oral_documents() -> void:
	var forward := _read(ORAL_FORWARD_PATH)
	var reverse := _read(ORAL_REVERSE_PATH)
	var requires: Dictionary = forward.get("requires", {})
	check(requires.get("features") == ["anatomy_oral"],
		"the oral forward edge needs the anatomy feature")
	check(str(requires.get("consent", "")) == "oral", "the oral forward edge needs consent")
	var reverse_requires: Dictionary = reverse.get("requires", {})
	check(not reverse_requires.has("consent"),
		"the oral reverse edge never asks for consent again")
	var channels: Dictionary = forward.get("channels", {})
	var lock: Dictionary = channels.get("controls", {})
	check(str(lock.get("kind", "")) == "lock", "the oral forward controls are a lock")
	check(lock.get("allow") == ["oral", "pose_back", "end"],
		"the oral lock allows oral, pose_back and end")
	var reverse_channels: Dictionary = reverse.get("channels", {})
	check(str((reverse_channels.get("audio", {}) as Dictionary).get("profile", "")) == "standing",
		"the oral reverse audio returns to the standing speech profile")


func _check_oral_runs() -> void:
	var forward := _read(ORAL_FORWARD_PATH)
	var run: Variant = STATE.start_edge(forward, SPECS.STANDING, SPECS.STANDING_ORAL)
	check(run != null, "the oral forward edge starts")
	if run == null:
		return
	check(near(run.duration, 1.6), "the oral forward clock is 1.6 s")
	check(near(run.weight, 0.0), "the oral forward base starts at zero")
	run.tick(0.0)
	var events: Array = run.events()
	check(events.size() == 2, "the oral forward fires the speech stop and the viseme at zero")
	if events.size() == 2:
		check(str(events[0].get("kind", "")) == "speech_stop",
			"the oral forward stops speech first")
		check(str(events[1].get("kind", "")) == "viseme"
			and str(events[1].get("value", "")) == "D",
			"the oral forward opens the D viseme second")
	check(not run.switches().has("contact"), "the oral forward contact waits for its switch")
	run.tick(0.45)
	check(run.switches().is_empty(), "the contact has not switched before 0.9")
	check(run.channel_weight("base") > 0.0 and run.channel_weight("base") < 1.0,
		"the oral forward base eases through the edge")
	run.tick(0.45)
	check(run.switches() == ["contact"], "the oral forward contact switches at 0.9")
	check(run.channel_weight("contact") == 1.0, "the contact switch reports its weight")
	run.tick(0.7)
	check(run.complete(), "the oral forward completes at its duration")
	check(run.events().size() == 1 and str(run.events()[0].get("kind", "")) == "status",
		"the oral forward reports its status on the completing tick")
	run.tick(0.1)
	check(run.events().is_empty(), "a completed oral edge fires no second event")

	var reverse := _read(ORAL_REVERSE_PATH)
	var back: Variant = STATE.start_edge(reverse, SPECS.STANDING_ORAL, SPECS.STANDING)
	check(back != null, "the oral reverse edge starts")
	if back == null:
		return
	back.tick(0.0)
	check(back.switches().has("contact"),
		"the oral reverse releases the mouth contact at zero")
	check(back.events().is_empty(), "the oral reverse has no zero event")
	back.tick(1.6)
	check(back.complete(), "the oral reverse completes at its duration")
	var late: Array = back.events()
	check(late.size() == 1 and str(late[0].get("kind", "")) == "status",
		"the oral reverse reports the standing status at the end")
	var allowed: Array = (reverse["channels"] as Dictionary)["controls"]["allow"]
	check(allowed == ["end"], "the oral reverse lock allows only end")


func _check_facesit_documents() -> void:
	var forward := _read(FACESIT_FORWARD_PATH)
	var reverse := _read(FACESIT_REVERSE_PATH)
	var requires: Dictionary = forward.get("requires", {})
	check(requires.get("forms") == ["human"], "the face-sit forward edge needs human Anon")
	check(requires.get("views") == ["desktop"], "the face-sit forward edge needs a desktop view")
	check(not requires.has("features") and not requires.has("consent"),
		"the face-sit forward edge has no feature or consent row")
	var channels: Dictionary = forward.get("channels", {})
	check(str((channels.get("anon", {}) as Dictionary).get("profile", "")) == "facesit",
		"the face-sit forward anon profile")
	check(str((channels.get("camera", {}) as Dictionary).get("kind", "")) == "hold",
		"the face-sit forward camera holds the source shots")
	var lock: Dictionary = channels.get("controls", {})
	check(str(lock.get("kind", "")) == "lock", "the face-sit forward controls are a lock")
	check(lock.get("allow") == ["end"], "the face-sit forward lock allows only end")
	check(str((channels.get("presentation", {}) as Dictionary).get("to", "")) == "missionary",
		"the face-sit forward presentation stays missionary")
	check(forward.get("constraints") == ["contact after base@0.55"],
		"the face-sit forward contact is floored after the base")
	var reverse_requires: Dictionary = reverse.get("requires", {})
	check(reverse_requires.get("forms") == ["human"] and reverse_requires.get("views") == ["desktop"],
		"the face-sit reverse edge asks for both forms and views")
	check(not reverse_requires.has("features") and not reverse_requires.has("consent"),
		"the face-sit reverse edge has no feature or consent row")
	var reverse_channels: Dictionary = reverse.get("channels", {})
	check((reverse_channels.get("controls", {}) as Dictionary).get("allow") == ["end"],
		"the face-sit reverse lock allows only end")
	check(str((reverse_channels.get("presentation", {}) as Dictionary).get("to", "")) == "missionary",
		"the face-sit reverse presentation switches back at zero")


func _check_facesit_runs() -> void:
	var forward := _read(FACESIT_FORWARD_PATH)
	var run: Variant = STATE.start_edge(forward, SPECS.MISSIONARY, SPECS.BED_FACESIT)
	check(run != null, "the face-sit forward edge starts")
	if run == null:
		return
	check(near(run.duration, 1.6), "the face-sit forward clock is 1.6 s")
	check(near(run.weight, 0.0), "the face-sit forward base starts at zero")
	run.tick(0.0)
	check(run.switches() == ["presentation"],
		"the face-sit forward presentation switches at zero")
	check(not run.switches().has("contact"), "the face-sit forward contact waits for its switch")
	run.tick(0.45)
	check(run.switches().is_empty(), "the face-sit contact has not switched before 0.9")
	check(run.channel_weight("base") > 0.0 and run.channel_weight("base") < 1.0,
		"the face-sit forward base eases through the edge")
	run.tick(0.45)
	check(run.switches() == ["contact"], "the face-sit forward contact switches at 0.9")
	run.tick(0.7)
	check(run.complete(), "the face-sit forward completes at its duration")
	check(run.events().size() == 1 and str(run.events()[0].get("kind", "")) == "status"
		and str(run.events()[0].get("value", "")) == "facesit",
		"the face-sit forward reports its status on the completing tick")
	run.tick(0.1)
	check(run.events().is_empty(), "a completed face-sit edge fires no second event")

	var reverse := _read(FACESIT_REVERSE_PATH)
	var back: Variant = STATE.start_edge(reverse, SPECS.BED_FACESIT, SPECS.MISSIONARY)
	check(back != null, "the face-sit reverse edge starts")
	if back == null:
		return
	back.tick(0.0)
	check(back.switches().has("contact"), "the face-sit reverse restores the opening at zero")
	check(back.switches().has("presentation"), "the face-sit reverse presentation returns at zero")
	check(back.events().is_empty(), "the face-sit reverse has no zero event")
	back.tick(1.2)
	check(back.complete(), "the face-sit reverse completes at its duration")
	var late: Array = back.events()
	check(late.size() == 1 and str(late[0].get("kind", "")) == "status"
		and str(late[0].get("value", "")) == "missionary",
		"the face-sit reverse reports the missionary status at the end")


func _check_rejections() -> void:
	_rejects(_mutated({"version": 2}), "a wrong version is rejected")
	check(not TRANSITION_SPEC.errors("other", _forward(), SPECS.SPECS).is_empty(),
		"a filename/id mismatch is rejected")
	_rejects(_without("from"), "a missing from is rejected")
	_rejects(_mutated({"from": ""}), "an empty from is rejected")
	_rejects(_without("to"), "a missing to is rejected")
	_rejects(_mutated({"to": ""}), "an empty to is rejected")
	_rejects(_without("channels"), "missing channels are rejected")
	_rejects(_mutated({"channels": {}}), "empty channels are rejected")
	var wrong_pair := _mutated({"id": "standing__other"})
	_rejects(wrong_pair, "an id that is not from__to is rejected", "standing__other")
	var same_pose := _mutated({"id": "standing__standing", "to": SPECS.STANDING})
	_rejects(same_pose, "from equal to to is rejected", "standing__standing")
	var table := {
		"a": _row("a", SPECS.STANDING, ["human"], ["desktop"]),
		"b": _row("b", SPECS.MISSIONARY, ["human"], ["desktop"]),
	}
	var unknown := _mutated({"id": "a__missing", "from": "a", "to": "missing"})
	check(not TRANSITION_SPEC.errors("a__missing", unknown, table).is_empty(),
		"an unknown endpoint is rejected")
	var cross := _mutated({"id": "a__b", "from": "a", "to": "b"})
	check(not TRANSITION_SPEC.errors("a__b", cross, table).is_empty(),
		"a cross-family endpoint is rejected")
	_rejects(_with_requires("unknown", true), "an unknown requires key is rejected")
	_rejects(_with_requires("forms", ["unicorn"]), "an unknown form is rejected")
	_rejects(_with_requires("views", ["phone"]), "an unknown view is rejected")
	_rejects(_with_requires("forms", ["human", "human"]), "a duplicate form is rejected")
	_rejects(_with_requires("views", ["desktop", "desktop"]), "a duplicate view is rejected")
	_rejects(_with_requires("features", ["", "anatomy"]), "an empty feature is rejected")
	_rejects(_with_requires("consent", 3), "a non-string consent is rejected")
	_rejects(_with_requires("mood", "always"), "an unknown requires key is rejected")
	var support_table := {
		"a": _row("a", SPECS.STANDING, ["human"], ["desktop"]),
		"b": _row("b", SPECS.STANDING, ["pony"], ["vr"]),
	}
	var form_doc := _mutated({"id": "a__b", "from": "a", "to": "b"})
	(form_doc["requires"] as Dictionary)["forms"] = ["human"]
	check(not TRANSITION_SPEC.errors("a__b", form_doc, support_table).is_empty(),
		"a form an endpoint does not support is rejected")
	var view_doc := _mutated({"id": "a__b", "from": "a", "to": "b"})
	(view_doc["requires"] as Dictionary)["views"] = ["vr"]
	check(not TRANSITION_SPEC.errors("a__b", view_doc, support_table).is_empty(),
		"a view an endpoint does not support is rejected")
	_rejects(_mutated({"duration": -1.0}), "a negative duration is rejected")
	_rejects(_mutated({"duration": "long"}), "a non-number duration is rejected")
	_rejects(_mutated({"easing": "bounce"}), "an unknown easing is rejected")
	_rejects(_with_channel("warp", {"kind": "hold"}), "an unknown channel is rejected")
	_rejects(_with_channel("base", {"kind": "warp"}), "an unknown channel kind is rejected")
	_rejects(_with_channel("controls", {"kind": "switch"}), "a switch without at is rejected")
	_rejects(_with_channel("controls", {"kind": "switch", "at": -1.0}),
		"a negative switch at is rejected")
	_rejects(_with_channel("controls", {"kind": "switch", "at": 0.0, "set": 4}),
		"a non-string switch payload is rejected")
	_rejects(_with_channel("base", {"kind": "blend", "start": -1.0}),
		"a negative blend start is rejected")
	_rejects(_with_channel("base", {"kind": "blend", "start": 0.0, "duration": -1.0}),
		"a negative blend duration is rejected")
	_rejects(_with_channel("base", {"kind": "blend", "easing": "bounce"}),
		"an unknown channel easing is rejected")
	_rejects(_with_channel("base", {"kind": "lock", "allow": "thrust"}),
		"a non-array lock allow is rejected")
	_rejects(_with_channel("base", {"kind": "lock", "block": [3]}),
		"a non-string lock block entry is rejected")
	_rejects(_with_channel("base", {"kind": "lock", "set": 3}),
		"a non-string lock set is rejected")
	var no_duration := _mutated({"events": [], "constraints": [],
		"channels": {"base": {"kind": "blend"}}})
	no_duration.erase("duration")
	_rejects(no_duration, "a blend without a duration is rejected")
	_rejects(_mutated({"constraints": ["warp after base@1"]}),
		"an unknown constraint channel is rejected")
	_rejects(_mutated({"constraints": [3]}), "a non-string constraint is rejected")
	var cycle := _mutated({"duration": 1.0, "events": [], "constraints": [
		"controls after presentation@1", "presentation after controls@1"],
		"channels": {
			"controls": {"kind": "blend", "duration": 1.0},
			"presentation": {"kind": "blend", "duration": 1.0},
		}})
	_rejects(cycle, "a constraint cycle is rejected")
	_rejects(_mutated({"events": [
		{"at": 0.5, "kind": "status", "value": "late"},
		{"at": 0.0, "kind": "status", "value": "early"},
	]}), "unsorted events are rejected")
	_rejects(_mutated({"events": [{"at": 0.0, "kind": "sound"}]}),
		"an unknown event kind is rejected")
	_rejects(_mutated({"events": [{"at": 0.0, "kind": "status"}]}),
		"a status without a value is rejected")
	_rejects(_mutated({"events": [{"at": 0.0, "kind": "viseme", "value": ""}]}),
		"a viseme without a value is rejected")
	_rejects(_mutated({"events": [{"at": -1.0, "kind": "speech_stop"}]}),
		"a negative event at is rejected")
	check(TRANSITION_SPEC.from_dict(FORWARD, _mutated({"version": 2}), SPECS.SPECS) == null,
		"from_dict refuses an invalid document")


func _check_shapes() -> void:
	var path_edge := _mutated({"duration": 0.5, "events": [], "constraints": [],
		"channels": {"base": {"kind": "path"}}})
	var path_errors := _errors(path_edge)
	check(path_errors.is_empty(), "a path edge with a duration is valid: %s" % str(path_errors))
	var path_run: Variant = STATE.start_edge(path_edge, SPECS.STANDING, SPECS.STANDING_TEST)
	check(path_run != null, "a path edge starts")
	if path_run != null:
		path_run.tick(0.25)
		check(near(path_run.channel_weight("base"), 0.5), "a path follows the blend math")
	var hold_edge := _mutated({"duration": 0.1, "events": [], "constraints": [],
		"channels": {"base": {"kind": "hold"}}})
	check(_errors(hold_edge).is_empty(), "a hold-only edge with a duration is valid")
	var no_duration := hold_edge.duplicate(true)
	no_duration.erase("duration")
	check(not _errors(no_duration).is_empty(), "a hold-only edge without a duration is rejected")
	var timed := _mutated({"events": [], "constraints": [],
		"channels": {"base": {"kind": "blend", "duration": 0.4},
			"controls": {"kind": "switch", "at": 0.2}}})
	timed.erase("duration")
	check(_errors(timed).is_empty(), "per-channel timings resolve without an edge duration")
	check(_errors(_without("requires")).is_empty(), "a missing requires block is valid")
	check(_errors(_without("events")).is_empty(), "a missing events block is valid")
	check(_errors(_without("constraints")).is_empty(), "a missing constraints block is valid")
	check(_errors(_mutated({"comment": "additive"})).is_empty(),
		"an unknown top-level key is additive")
	check(_errors(_with_channel("base", {"kind": "hold", "note": "additive"})).is_empty(),
		"an unknown channel payload key is additive")
