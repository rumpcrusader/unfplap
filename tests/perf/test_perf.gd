extends SceneTree
## The act perf probe: gates, the window boundary, the header facts and the summary text.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/perf/test_perf.gd

const PERF := preload("res://mods/unfplap/shared/perf.gd")

var failures := 0
var checks := 0


class Sink extends RefCounted:
	var enabled := false
	var active := true
	var text := ""
	var calls := 0

	func is_enabled() -> bool:
		return enabled

	func is_active() -> bool:
		return active

	func header() -> Dictionary:
		return {
			"pony": "fluttershy",
			"pose": "standing",
			"state": 2,
			"near_mesh": true,
			"tier": "near",
			"wings": "held",
		}

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
	var probe := PERF.new()
	check(not probe.on(), "the probe starts off")
	probe.note("runtime", 10)
	probe.tick(5.0)
	check(true, "absent callbacks are no-ops")

	var sink := Sink.new()
	probe.enabled = Callable(sink, "is_enabled")
	probe.active = Callable(sink, "is_active")
	probe.header = Callable(sink, "header")
	probe.log = Callable(sink, "write")
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

	print("PERF_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("PERF_PASS")
	quit(0 if failures == 0 else 1)
