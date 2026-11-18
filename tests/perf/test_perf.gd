extends SceneTree
## The act perf probe: gates, the window boundary, the header facts and the tree summary text.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/perf/test_perf.gd

const PERF := preload("res://mods/unfplap/shared/perf.gd")

var failures := 0
var checks := 0


class Sink extends RefCounted:
	var enabled := false
	var active := true
	var text := ""
	var calls := 0
	var panel_entries: Array = []
	var panel_info: Dictionary = {}
	var panel_calls := 0

	func is_enabled() -> bool:
		return enabled

	func is_active() -> bool:
		return active

	func header() -> Dictionary:
		return {
			"pony": "fluttershy",
			"pose": "standing",
			"state": 2,
			"lean": "0.40/0.00",
			"hands": "LR",
			"near_mesh": true,
			"tier": "near",
			"wings": "held",
		}

	func write(line: String) -> void:
		calls += 1
		text = line

	func panel(entries: Array, info: Dictionary) -> void:
		panel_calls += 1
		panel_entries = entries
		panel_info = info


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


## The keys the panel received, in display order.
func keys(entries: Array) -> Array:
	var out: Array = []
	for entry: Dictionary in entries:
		out.append(str(entry["key"]))
	return out


## The residual row of `parent`, or an empty dictionary.
func self_row(entries: Array, parent: String) -> Dictionary:
	for entry: Dictionary in entries:
		if bool(entry["self"]) and str(entry["parent"]) == parent:
			return entry
	return {}


## The row for one chunk key, or an empty dictionary.
func panel_row(entries: Array, key: String) -> Dictionary:
	for entry: Dictionary in entries:
		if str(entry["key"]) == key:
			return entry
	return {}


func run() -> void:
	var probe := PERF.new()
	check(not probe.on(), "the probe starts off")
	probe.note("runtime", 10)
	probe.tick(5.0)

	var text_only := Sink.new()
	text_only.enabled = true
	var bare := PERF.new()
	bare.enabled = Callable(text_only, "is_enabled")
	bare.active = Callable(text_only, "is_active")
	bare.header = Callable(text_only, "header")
	bare.log = Callable(text_only, "write")
	bare.note("runtime", 10)
	bare.tick(1.1)
	check(text_only.calls == 1 and text_only.panel_calls == 0,
		"an unbound panel sink still prints the text block")

	var sink := Sink.new()
	probe.enabled = Callable(sink, "is_enabled")
	probe.active = Callable(sink, "is_active")
	probe.header = Callable(sink, "header")
	probe.log = Callable(sink, "write")
	probe.show = Callable(sink, "panel")
	probe.note("runtime", 10)
	probe.tick(5.0)
	check(sink.calls == 0, "a disabled probe never prints")

	sink.enabled = true
	sink.active = false
	probe.note("runtime", 10)
	probe.tick(5.0)
	check(sink.calls == 0, "an idle act never prints")

	sink.active = true
	probe.note("pose_tick", 2000)
	probe.note("pose_tick", 1000)
	probe.tick(0.5)
	check(sink.calls == 0, "the window waits for its boundary")
	probe.tick(0.6)
	check(sink.calls == 1, "one summary prints at the boundary")
	check(sink.text.begins_with("perf pony=fluttershy pose=standing state=2"),
		"the header names the pony, pose and state")
	check(sink.text.contains("near_mesh=true tier=near wings=held"),
		"the header carries the mesh, tier and wing state")
	check(sink.text.contains("lean=0.40/0.00 hands=LR"),
		"the header carries the lean and the latched hands")
	check(sink.text.contains("phys="), "the summary carries the sampled physics time")
	check(sink.text.contains("draws=") and sink.text.contains("prims="),
		"the summary carries the renderer's draw calls and primitives")
	check(sink.text.contains("tick="), "the summary carries physics frames per frame")
	check(sink.text.contains("pose_tick"), "the summary lists the recorded chunk")
	check(sink.text.contains("max") and sink.text.contains("2.00ms"),
		"the summary keeps the worst call")
	check(sink.text.contains("calls 2"), "the summary keeps the call count")

	probe.reset()
	probe.tick(1.1)
	check(sink.calls == 2, "the next window prints again")
	check(not sink.text.contains("pose_tick"), "reset drops the previous window's rows")

	probe.time("kiss_tick", Time.get_ticks_usec())
	probe.tick(1.1)
	check(sink.text.contains("kiss_tick"), "time() records the chunk elapsed time")

	probe.reset()
	probe.note("runtime_physics", 5000)
	probe.note("pose_tick", 2000)
	probe.note("pose_fanout", 1500)
	probe.note("unknown_chunk", 300)
	probe.tick(1.1)
	check(sink.panel_entries.size() == sink.text.split("\n").size() - 1,
		"the panel receives the same rows the block prints")
	check(keys(sink.panel_entries).has("pose_fanout")
		and keys(sink.panel_entries).has("unknown_chunk"),
		"the panel receives the noted chunks")
	var residual_row := self_row(sink.panel_entries, "runtime_physics")
	check(not residual_row.is_empty()
		and is_equal_approx(float(residual_row.get("total", 0.0)), 1.5),
		"the panel receives the parent's self residual")
	check(str(sink.panel_info.get("pony", "")) == "fluttershy",
		"the panel receives the header facts")
	check(sink.panel_info.has("fps") and sink.panel_info.has("frame_ms")
		and sink.panel_info.has("phys_ms") and sink.panel_info.has("tick"),
		"the panel receives the engine frame facts")
	check(int(sink.panel_info.get("frames", 0)) >= 1,
		"the panel receives the window's rendered frames")
	check(is_equal_approx(float(panel_row(sink.panel_entries, "pose_tick").get("max", 0.0)), 2.0),
		"the panel receives each row's worst call")

	print("PERF_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("PERF_PASS")
	quit(0 if failures == 0 else 1)
