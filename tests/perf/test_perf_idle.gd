extends SceneTree
## The idle perf aggregator: the gate, the window boundary, per-owner aggregation, the block text
## and the reset rules.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/perf/test_perf_idle.gd

const PERF_IDLE := preload("res://mods/unfplap/shared/perf_idle.gd")

var failures := 0
var checks := 0


class Sink extends RefCounted:
	var enabled := false
	var text := ""
	var calls := 0

	func is_enabled() -> bool:
		return enabled

	func counts() -> Dictionary:
		return {"runtimes": 4, "mares": 6}

	func write(line: String) -> void:
		calls += 1
		text = line


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var probe := PERF_IDLE.new()
	check(not probe.on(), "the probe starts off")
	probe.note("runtime", 10, "twilight")
	probe.tick(5.0)
	check(true, "absent callbacks are no-ops")

	var sink := Sink.new()
	probe.enabled = Callable(sink, "is_enabled")
	probe.counts = Callable(sink, "counts")
	probe.log = Callable(sink, "write")
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
	check(sink.text.contains("calls 2"), "the summary keeps the call count")
	check(sink.text.contains("10.00ms/s"), "the summary keeps the window total")
	check(sink.text.contains("5000.0us/call"), "the summary keeps the average call")
	check(sink.text.contains("max 9.00ms applejack"),
		"the summary keeps the worst call and its owner")

	probe.note("no_owner", 300)
	probe.tick(1.1)
	check(sink.text.contains("max 0.30ms -"), "a chunk without an owner prints a dash")

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
