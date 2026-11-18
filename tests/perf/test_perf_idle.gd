extends SceneTree
## The idle perf aggregator: the gate, the window boundary, per-owner aggregation, the tree block
## text and the reset rules.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/perf/test_perf_idle.gd

const PERF_IDLE := preload("res://mods/unfplap/shared/perf_idle.gd")

var failures := 0
var checks := 0


class Sink extends RefCounted:
	var enabled := false
	var text := ""
	var calls := 0
	var panel_entries: Array = []
	var panel_info: Dictionary = {}
	var panel_calls := 0

	func is_enabled() -> bool:
		return enabled

	func counts() -> Dictionary:
		return {"runtimes": 4, "mares": 6}

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


## The block line that names `key`.
func row(text: String, key: String) -> String:
	for line: String in text.split("\n"):
		if line.contains(key):
			return line
	return ""


## The whitespace-separated token after `label` in one row.
func token(line: String, label: String) -> String:
	var parts := line.split(" ", false)
	var at := parts.find(label)
	return str(parts[at + 1]) if at >= 0 and at + 1 < parts.size() else ""


## The keys the panel received, in display order.
func keys(entries: Array) -> Array:
	var out: Array = []
	for entry: Dictionary in entries:
		out.append(str(entry["key"]))
	return out


## The row for one chunk key, or an empty dictionary.
func panel_row(entries: Array, key: String) -> Dictionary:
	for entry: Dictionary in entries:
		if str(entry["key"]) == key:
			return entry
	return {}


func run() -> void:
	var probe := PERF_IDLE.new()
	check(not probe.on(), "the probe starts off")
	probe.note("runtime", 10, "twilight")
	probe.tick(5.0)

	var text_only := Sink.new()
	text_only.enabled = true
	var bare := PERF_IDLE.new()
	bare.enabled = Callable(text_only, "is_enabled")
	bare.counts = Callable(text_only, "counts")
	bare.log = Callable(text_only, "write")
	bare.note("runtime", 10)
	bare.tick(1.1)
	check(text_only.calls == 1 and text_only.panel_calls == 0,
		"an unbound panel sink still prints the block")

	var sink := Sink.new()
	probe.enabled = Callable(sink, "is_enabled")
	probe.counts = Callable(sink, "counts")
	probe.log = Callable(sink, "write")
	probe.show = Callable(sink, "panel")
	probe.note("runtime", 10, "twilight")
	probe.tick(5.0)
	check(sink.calls == 0, "a disabled probe never prints")

	sink.enabled = true
	probe.note("runtime_process", 4000, "twilight")
	probe.note("runtime_process", 2000, "rarity")
	probe.note("zzz_slow", 9000, "applejack")
	probe.note("zzz_slow", 1000, "fluttershy")
	probe.tick(0.5)
	check(sink.calls == 0, "the window waits for its boundary")
	probe.tick(0.6)
	check(sink.calls == 1, "one block prints at the boundary")
	check(sink.text.begins_with("perf idle runtimes=4 mares=6"),
		"the header names the runtime and mare counts")
	check(sink.text.contains("fps=") and sink.text.contains("frame=")
		and sink.text.contains("phys=") and sink.text.contains("tick="),
		"the header carries the engine frame, physics and tick facts")
	check(sink.text.find("zzz_slow") < sink.text.find("runtime_process"),
		"rows sort by total time, largest first")
	check(token(row(sink.text, "zzz_slow"), "calls") == "2",
		"the summary keeps the call count")
	check(sink.text.contains("10.00ms/s"), "the summary keeps the window total")
	check(sink.text.contains("5000.0us/call"), "the summary keeps the average call")
	check(sink.text.contains("max") and sink.text.contains("9.00ms applejack"),
		"the summary keeps the worst call and its owner")
	check(sink.panel_calls == 1, "one panel window per printed block")
	check(keys(sink.panel_entries) == ["zzz_slow", "runtime_process"],
		"the panel receives the block's rows in order")
	check(int(sink.panel_info.get("runtimes", 0)) == 4
		and int(sink.panel_info.get("mares", 0)) == 6,
		"the panel receives the idle header counts")
	check(sink.panel_info.has("fps") and sink.panel_info.has("frame_ms")
		and sink.panel_info.has("phys_ms") and sink.panel_info.has("tick"),
		"the panel receives the engine frame facts")
	check(int(sink.panel_info.get("frames", 0)) >= 1,
		"the panel receives the window's rendered frames")
	check(is_equal_approx(float(panel_row(sink.panel_entries, "zzz_slow").get("max", 0.0)), 9.0),
		"the panel receives each row's worst call")

	probe.note("no_owner", 300)
	probe.tick(1.1)
	check(sink.text.contains("0.30ms -"), "a chunk without an owner prints a dash")

	probe.reset()
	probe.tick(1.1)
	check(sink.calls == 3, "the next window prints again")
	check(not sink.text.contains("zzz_slow"), "reset drops the previous window's rows")

	sink.enabled = false
	probe.note("stale", 500, "twilight")
	probe.tick(1.1)
	check(sink.calls == 3, "the gate off never prints")
	sink.enabled = true
	probe.note("fresh", 700, "rarity")
	probe.tick(1.1)
	check(sink.calls == 4, "the probe prints again after the gate returns")
	check(sink.text.contains("fresh"), "the new window keeps its own chunk")
	check(not sink.text.contains("stale"), "the gate off cleared the stale window")

	print("PERF_IDLE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("PERF_IDLE_PASS")
	quit(0 if failures == 0 else 1)
