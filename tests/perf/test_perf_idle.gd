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


func run() -> void:
	var probe := PERF_IDLE.new()
	check(not probe.on(), "the probe starts off")
	probe.note("runtime", 10, "twilight")
	probe.tick(5.0)
	check(true, "absent callbacks are no-ops")

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
	check(sink.text.contains("\nzzz_slow"), "a chunk without a parent is a root")
	check(sink.panel_calls == 1, "one panel window per printed block")
	check(keys(sink.panel_entries) == ["zzz_slow", "runtime_process"],
		"the panel receives the block's rows in order")
	check(int(sink.panel_info.get("runtimes", 0)) == 4
		and int(sink.panel_info.get("mares", 0)) == 6,
		"the panel receives the idle header counts")
	check(sink.panel_info.has("fps") and sink.panel_info.has("frame_ms")
		and sink.panel_info.has("phys_ms") and sink.panel_info.has("tick"),
		"the panel receives the engine frame facts")

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

	probe.reset()
	probe.note("entry_process", 7000)
	probe.note("offer_scan", 3850)
	probe.note("offer_gate", 3530)
	probe.note("offer_cone", 170)
	probe.tick(1.1)
	check(sink.text.contains("\nentry_process"),
		"the outermost chunk is a root, without a glyph")
	check(sink.text.find("entry_process") < sink.text.find("offer_scan"),
		"a parent prints before its children")
	check(sink.text.contains("│  ├─ offer_gate"),
		"a grandchild continues its parent's column")
	check(sink.text.find("offer_gate") < sink.text.find("offer_cone"),
		"children sort largest total first")
	check(sink.text.contains("│  └─ self") and sink.text.contains("\n└─ self"),
		"each parent's unmeasured cost is its own self row")
	check(sink.text.contains("0.15ms/s") and sink.text.contains("3.15ms/s"),
		"the self rows carry the residual time")

	probe.reset()
	probe.note("entry_process", 12000)
	probe.note("offer_scan", 5000)
	probe.note("offer_gate", 4800)
	probe.note("offer_rows", 4200)
	probe.note("offer_policy", 600)
	probe.note("entry_hint", 3000)
	probe.note("entry_negotiation", 900)
	probe.note("entry_initiation", 400)
	probe.note("entry_watch", 100)
	probe.note("entry_caption", 50)
	probe.tick(1.1)
	check(row(sink.text, "entry_hint").begins_with("├─ "),
		"the entry body's chunks nest under entry_process")
	check(row(sink.text, "entry_caption").begins_with("└─ "),
		"the smallest entry chunk closes its level")
	check(row(sink.text, "offer_rows").begins_with("│  │  ├─ "),
		"the gate's rows and policy nest two levels under the scan")
	check(sink.text.find("offer_rows") < sink.text.find("offer_policy"),
		"the gate prints its measured split in total order")
	check(sink.text.contains("2.55ms/s"), "the entry body keeps its own residual row")

	print("PERF_IDLE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("PERF_IDLE_PASS")
	quit(0 if failures == 0 else 1)
