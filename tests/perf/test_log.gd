extends SceneTree
## The shared log module: the debug switches, the block text, the idle window's one block a second
## and the lazily created panel.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/perf/test_log.gd

const LOG := preload("res://mods/unfplap/shared/log.gd")

var failures := 0
var checks := 0


class Sink extends RefCounted:
	var lines: Array[String] = []

	func write(text: String) -> void:
		lines.append(text)

	func runtime_count() -> int:
		return 2

	func mare_count() -> int:
		return 3


class ActState extends RefCounted:
	var running := false

	func is_running() -> bool:
		return running


func _initialize() -> void:
	run.call_deferred()


## The two switch reads the entry binds: always on.
class Switch extends RefCounted:
	func read() -> bool:
		return true


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


## A fresh module: both switches off, no sink, no act, no parent.
func _reset_module() -> void:
	LOG.debug_logs = false
	LOG.debug_perf = false
	LOG.debug_read = Callable()
	LOG.perf_read = Callable()
	LOG.act_running = Callable()
	LOG.runtime_count = Callable()
	LOG.mare_count = Callable()
	LOG.sink = Callable()
	LOG.detach()


func run() -> void:
	_check_gate()
	_check_block()
	_check_idle_window()
	_check_panel()
	print("LOG_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("LOG_PASS")
	quit(0 if failures == 0 else 1)


func _check_gate() -> void:
	_reset_module()
	var sink := Sink.new()
	LOG.sink = Callable(sink, "write")
	LOG.debug("hidden")
	check(sink.lines.is_empty(), "a line is silent with debug logs off")
	LOG.debug_logs = true
	LOG.debug("shown")
	check(sink.lines == ["shown"], "a line reaches the sink with debug logs on")
	var host_callable := Callable(LOG, "debug")
	check(host_callable.is_valid(), "the module is a valid line sink for a host field")
	host_callable.call("through the callable")
	check(sink.lines.size() == 2 and sink.lines[1] == "through the callable",
		"a host callable prints through the same switch and sink")


func _check_block() -> void:
	_reset_module()
	var sink := Sink.new()
	LOG.sink = Callable(sink, "write")
	LOG.debug_logs = true
	LOG.block("DATA Applejack", ["gate=open", "", "pony=applejack"])
	check(sink.lines.size() == 1, "one block is one line entry")
	check(sink.lines[0] == "DATA Applejack\n\tgate=open\n\tpony=applejack",
		"a block is the title, then one tab-indented row each, empty rows dropped")


func _check_idle_window() -> void:
	_reset_module()
	var sink := Sink.new()
	var act := ActState.new()
	LOG.sink = Callable(sink, "write")
	LOG.runtime_count = Callable(sink, "runtime_count")
	LOG.mare_count = Callable(sink, "mare_count")
	LOG.act_running = Callable(act, "is_running")
	check(not LOG.idle_on(), "the idle probe is off with both switches off")
	LOG.debug_logs = true
	LOG.debug_perf = true
	check(LOG.idle_on(), "both switches on and no act is the idle gate")
	LOG.note("runtime_process", 4000, "twilight")
	check(LOG.tick(0.5), "the frame reports the idle gate on")
	check(sink.lines.is_empty(), "the window waits for its boundary")
	check(LOG.tick(0.6), "the second frame still reports the gate")
	check(sink.lines.size() == 1, "one block prints at the one-second boundary")
	if not sink.lines.is_empty():
		var text := sink.lines[0]
		check(text.begins_with("perf idle runtimes=2 mares=3"),
			"the header carries the counts the entry installed")
		check(text.contains("runtime_process"), "the block keeps the noted chunk")
	check(LOG.tick(0.5), "the gate stays on after a print")
	check(sink.lines.size() == 1, "the next window starts empty")
	act.running = true
	check(not LOG.idle_on(), "an act turns the idle probe off")
	LOG.note("stale", 900, "twilight")
	check(not LOG.tick(1.2), "an act reports the idle gate off")
	check(sink.lines.size() == 1, "no block prints inside an act")
	act.running = false
	LOG.note("fresh", 700, "rarity")
	LOG.tick(1.1)
	check(sink.lines.size() == 2, "the probe prints again after the act")
	check(not sink.lines[1].contains("stale"), "the act cleared the stale window")


func _check_panel() -> void:
	_reset_module()
	var host := Node.new()
	host.name = "LogHost"
	root.add_child(host)
	LOG.debug_logs = true
	LOG.debug_perf = true
	LOG.perf_block([], {})
	check(host.get_node_or_null("UnfplapPerfView") == null,
		"a window without a parent creates no panel")
	# The entry binds the two switch reads before it attaches the sink. A plain object method,
	# never a lambda: Godot corrupts the heap at exit when a runtime lambda sits in a static var.
	var switches := Switch.new()
	LOG.debug_read = Callable(switches, "read")
	LOG.perf_read = Callable(switches, "read")
	LOG.attach(host)
	check(LOG.debug_logs and LOG.debug_perf, "attaching the sink reads the two switches")
	LOG.debug_perf = false
	LOG.perf_block([], {})
	check(host.get_node_or_null("UnfplapPerfView") == null,
		"perf logs off creates no panel")
	LOG.debug_perf = true
	check(host.get_node_or_null("UnfplapPerfView") == null, "the panel is created lazily")
	LOG.perf_block([], {"runtimes": 1, "mares": 2})
	var panel: Node = host.get_node_or_null("UnfplapPerfView")
	check(panel != null, "the first printed window creates the panel under the entry")
	if panel != null:
		var card: Node = panel.get_node_or_null("PerfViewRoot/PerfPanel")
		check(panel is CanvasLayer and card != null and card.visible,
			"the panel shows its window")
		check(str(panel.call("caption", panel.get("_info"))).begins_with(
			"perf idle runtimes=1 mares=2"), "the panel receives the window facts")
		LOG.clear_panel()
		check(card != null and not card.visible, "clear hides the panel")
	LOG.detach()
	# The entry frees its own children: the module keeps no reference to a freed panel.
	if panel != null:
		host.remove_child(panel)
		panel.free()
	LOG.perf_block([], {})
	check(host.get_node_or_null("UnfplapPerfView") == null,
		"a detached module creates no panel")
	host.queue_free()
