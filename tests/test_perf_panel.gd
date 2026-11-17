extends SceneTree
## The perf panel: the list height, the colour targets and the view's caption and clear.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_perf_panel.gd

const VIEW := preload("res://mods/unfplap/debug/perf_view.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


## One display row in the shape `shared/perf_tree.gd` emits plus the probe's worst call.
func row(key: String, depth: int, total: float, max_ms: float, calls: int,
		is_self := false, parent := "") -> Dictionary:
	return {
		"key": key,
		"depth": depth,
		"prefix": "",
		"self": is_self,
		"total": total,
		"max": max_ms,
		"calls": calls,
		"parent": parent,
	}


func run() -> void:
	_check_height()
	_check_totals()
	_check_heat()
	_check_calls()
	_check_view()
	print("PERF_PANEL_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("PERF_PANEL_PASS")
	quit(0 if failures == 0 else 1)


func _check_height() -> void:
	check(is_equal_approx(VIEW.height([]), VIEW.ROW_H),
		"an empty window keeps the permanent total row")
	check(is_equal_approx(VIEW.height([row("a", 0, 1.0, 0.1, 1)]), 2.0 * VIEW.ROW_H),
		"the total row and one tree row are two rows high")
	check(is_equal_approx(VIEW.height([
		row("a", 0, 3.0, 0.1, 1),
		row("b", 1, 2.0, 0.1, 1),
		row("self", 1, 1.0, 0.0, 0, true, "a"),
	]), 4.0 * VIEW.ROW_H), "the list is one row taller than its row count")


func _check_totals() -> void:
	var empty := VIEW.totals([])
	check(is_equal_approx(float(empty["avg"]), 0.0)
		and is_equal_approx(float(empty["max"]), 0.0),
		"an empty window totals zero")
	var total := VIEW.totals([
		row("runtime_physics", 0, 36.17, 0.42, 60),
		row("pose_tick", 1, 24.00, 0.38, 120),
		row("runtime_process", 0, 5.00, 0.51, 60),
	])
	check(is_equal_approx(float(total["avg"]), 41.17),
		"the total sums the roots, not their children")
	check(is_equal_approx(float(total["max"]), 0.51),
		"the total takes the window's worst call")


func _check_heat() -> void:
	check(VIEW.heat(0.0, VIEW.AVG_LIMIT).is_equal_approx(VIEW.GREEN),
		"an idle chunk is green")
	check(VIEW.heat(VIEW.AVG_LIMIT * 0.5, VIEW.AVG_LIMIT).is_equal_approx(VIEW.AMBER),
		"half the target is amber")
	check(VIEW.heat(VIEW.AVG_LIMIT, VIEW.AVG_LIMIT).is_equal_approx(VIEW.RED),
		"the target is red")
	check(VIEW.heat(VIEW.AVG_LIMIT * 3.0, VIEW.AVG_LIMIT).is_equal_approx(VIEW.RED),
		"past the target stays red")
	check(VIEW.heat(VIEW.MAX_LIMIT, VIEW.MAX_LIMIT).is_equal_approx(VIEW.RED),
		"the max column reddens at its own target")


func _check_calls() -> void:
	check(is_equal_approx(VIEW.per_frame(120, 60), 2.0), "calls divide by rendered frames")
	check(is_equal_approx(VIEW.per_frame(10, 0), 0.0), "a window with no frames reports no rate")
	check(VIEW.calls_heat(60, 60).is_equal_approx(VIEW.GREEN), "one call per frame is green")
	check(VIEW.calls_heat(120, 60).is_equal_approx(VIEW.RED), "two calls per frame is red")
	check(VIEW.calls_heat(90, 60).is_equal_approx(VIEW.AMBER),
		"one and a half calls per frame is amber")


func _check_view() -> void:
	var view: CanvasLayer = VIEW.new()
	root.add_child(view)
	var panel := view.get("_panel") as PanelContainer
	var caption := view.get("_caption") as Label
	var canvas := view.get("_canvas") as Control
	check(panel != null and not panel.visible, "the panel starts hidden")
	check(view.layer == 20, "the panel draws above the HUD")
	var entries := [
		row("runtime_physics", 0, 36.17, 0.42, 60),
		row("pose_tick", 1, 24.00, 0.38, 120),
		row("self", 1, 12.17, 0.0, 0, true, "runtime_physics"),
	]
	view.call("show_window", entries, {
		"pony": "twilight", "pose": "standing", "state": 3,
		"fps": 60, "frame_ms": 11.0, "phys_ms": 18.4, "tick": 1.11, "frames": 60,
	})
	check(panel.visible, "a window makes the panel visible")
	check(caption.text.contains("60 fps"), "the caption carries the frame rate")
	check(caption.text.contains("pony=twilight pose=standing state=3"),
		"the act caption names the pony, pose and state")
	check(is_equal_approx(canvas.custom_minimum_size.y, VIEW.height(entries)),
		"the list takes the window's row count")
	check(not caption.text.contains("Hz"), "the first window has no refresh rate")
	check(VIEW.caption({"runtimes": 4, "mares": 6, "fps": 60}).contains(
		"perf idle runtimes=4 mares=6"), "the idle caption names the runtime and mare counts")
	view.set("_last_shown_ms", maxi(0, Time.get_ticks_msec() - 1000))
	view.call("show_window", entries, {"runtimes": 4, "mares": 6, "fps": 30, "frames": 30})
	check(caption.text.contains("perf idle") and caption.text.contains("30 fps"),
		"the caption follows the idle probe")
	check(caption.text.contains("refresh") and caption.text.contains("Hz"),
		"a second window adds the measured refresh rate")
	view.call("clear")
	check(caption.text.is_empty(), "clear drops the caption")
	check(not panel.visible, "clear hides the panel")
	root.remove_child(view)
	view.free()
