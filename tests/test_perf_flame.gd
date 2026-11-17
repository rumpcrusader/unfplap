extends SceneTree
## The perf flame panel: the static bar geometry and the view's caption, legend and clear.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_perf_flame.gd

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


## One display row in the shape `shared/perf_tree.gd` emits.
func entry(key: String, depth: int, total: float, is_self := false, parent := "") -> Dictionary:
	return {
		"key": key,
		"depth": depth,
		"self": is_self,
		"total": total,
		"calls": 1,
		"parent": parent,
	}


func run() -> void:
	_check_flat()
	_check_nested()
	_check_overrun()
	_check_height()
	_check_view()
	print("PERF_FLAME_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("PERF_FLAME_PASS")
	quit(0 if failures == 0 else 1)


func _check_flat() -> void:
	var bars := VIEW.rects([
		entry("wide", 0, 30.0),
		entry("narrow", 0, 10.0),
	], 600.0)
	check(bars.size() == 2, "one bar per root")
	check(is_equal_approx(float(bars[0]["x"]), 0.0)
		and is_equal_approx(float(bars[0]["w"]), 450.0),
		"the largest root starts at the left and takes its share")
	check(is_equal_approx(float(bars[1]["x"]), 450.0)
		and is_equal_approx(float(bars[1]["w"]), 150.0),
		"the next root starts where the first ends")
	check(is_equal_approx(float(bars[0]["w"]) + float(bars[1]["w"]), 600.0),
		"the roots fill the graph width")
	check(VIEW.rects([], 600.0).is_empty(), "an empty window draws no bars")
	check(VIEW.rects([entry("only", 0, 5.0)], 0.0).is_empty(), "a zero width draws no bars")


func _check_nested() -> void:
	var bars := VIEW.rects([
		entry("root", 0, 100.0),
		entry("big", 1, 60.0),
		entry("leaf", 2, 30.0),
		entry("small", 1, 20.0),
		entry("self", 1, 20.0, true, "root"),
	], 600.0)
	check(bars.size() == 5, "every row keeps its bar")
	var root: Dictionary = bars[0]
	var big: Dictionary = bars[1]
	var leaf: Dictionary = bars[2]
	var small: Dictionary = bars[3]
	var residual: Dictionary = bars[4]
	check(is_equal_approx(float(root["w"]), 600.0), "a lone root fills the graph")
	check(is_equal_approx(float(big["w"]), 360.0), "a child takes its share of the parent")
	check(is_equal_approx(float(leaf["x"]), float(big["x"])),
		"a grandchild starts at its parent's left")
	check(float(leaf["x"]) + float(leaf["w"]) <= float(big["x"]) + float(big["w"]) + 0.01,
		"a grandchild stays inside its parent")
	check(is_equal_approx(float(small["x"]), float(big["x"]) + float(big["w"])),
		"siblings touch without overlapping")
	check(is_equal_approx(float(residual["x"]), float(small["x"]) + float(small["w"])),
		"the self row follows its siblings")
	check(is_equal_approx(float(residual["w"]), 120.0), "the self row takes the residual")
	check(is_equal_approx(float(residual["x"]) + float(residual["w"]), 600.0),
		"the children and self fill the parent's span")


func _check_overrun() -> void:
	var bars := VIEW.rects([
		entry("root", 0, 50.0),
		entry("a", 1, 60.0),
		entry("b", 1, 40.0),
	], 600.0)
	var root: Dictionary = bars[0]
	var first: Dictionary = bars[1]
	var second: Dictionary = bars[2]
	check(float(first["x"]) >= float(root["x"]),
		"an overrunning child starts inside its parent")
	check(float(first["x"]) + float(first["w"]) <= float(root["x"]) + float(root["w"]) + 0.01,
		"an overrunning child is clipped to the parent's span")
	check(float(second["x"]) >= float(first["x"]) + float(first["w"]) - 0.01,
		"the next sibling does not overlap the clipped child")
	check(float(second["x"]) + float(second["w"]) <= 600.01,
		"an overrun never spills into the next root")


func _check_height() -> void:
	var step := VIEW.ROW_H + VIEW.ROW_GAP
	check(is_equal_approx(VIEW.height([]), 0.0), "an empty window has no height")
	check(is_equal_approx(VIEW.height([entry("root", 0, 1.0)]), step),
		"a flat window is one row high")
	check(is_equal_approx(VIEW.height([
		entry("root", 0, 2.0),
		entry("child", 1, 1.0),
		entry("leaf", 2, 1.0),
	]), 3.0 * step), "a nested window is as high as its deepest level")


func _check_view() -> void:
	var view: CanvasLayer = VIEW.new()
	root.add_child(view)
	var panel := view.get("_panel") as PanelContainer
	var caption := view.get("_caption") as Label
	var canvas := view.get("_canvas") as Control
	var legend := view.get("_legend") as GridContainer
	check(panel != null and not panel.visible, "the panel starts hidden")
	check(view.layer == 20, "the panel draws above the HUD")
	var entries := [
		entry("root", 0, 100.0),
		entry("child", 1, 60.0),
		entry("self", 1, 40.0, true, "root"),
	]
	view.call("show_window", entries, {
		"pony": "twilight", "pose": "standing", "state": 3,
		"fps": 60, "frame_ms": 11.0, "phys_ms": 18.4, "tick": 1.11,
	})
	check(panel.visible, "a window makes the panel visible")
	check(caption.text.contains("60 fps"), "the caption carries the frame rate")
	check(caption.text.contains("pony=twilight pose=standing state=3"),
		"the act caption names the pony, pose and state")
	check(is_equal_approx(canvas.custom_minimum_size.y, VIEW.height(entries)),
		"the canvas takes the graph's height")
	check(legend.get_child_count() == VIEW.LEGEND_ROWS * 2, "the legend keeps its rows")
	var first := legend.get_child(0) as Label
	var first_value := legend.get_child(1) as Label
	check(first != null and first.text == "root", "the legend starts with the largest chunk")
	check(first_value != null and first_value.text == "100.00ms/s",
		"the legend prints the chunk's window total")
	check(VIEW.caption({"runtimes": 4, "mares": 6, "fps": 60}).contains(
		"perf idle runtimes=4 mares=6"), "the idle caption names the runtime and mare counts")
	view.call("show_window", entries, {"runtimes": 4, "mares": 6, "fps": 30})
	check(caption.text.contains("perf idle") and caption.text.contains("30 fps"),
		"the caption follows the idle probe")
	view.call("clear")
	check(caption.text.is_empty(), "clear drops the caption")
	check(not panel.visible, "clear hides the panel")
	root.remove_child(view)
	view.free()
