extends SceneTree
## The shared perf tree layout: roots, nesting, glyph prefixes, per-level order and the residual
## self rows.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/perf/test_perf_tree.gd

const TREE := preload("res://mods/unfplap/shared/perf_tree.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


## The display text of each row, in order: the glyph prefix and the key.
func lines(entries: Array) -> Array:
	var out: Array = []
	for entry: Dictionary in entries:
		out.append(str(entry["prefix"]) + str(entry["key"]))
	return out


func run() -> void:
	check(TREE.layout({}, {}).is_empty(), "an empty window lays out no rows")

	var flat := TREE.layout({"b": [2.0, 1], "a": [6.0, 2]}, {})
	check(lines(flat) == ["a", "b"], "roots sort largest total first")
	check(not flat[0]["self"] and str(flat[0]["parent"]).is_empty(),
		"a root is a measured row without a parent")

	var nested := TREE.layout({
		"a": [10.0, 5],
		"b": [6.0, 3],
		"c": [2.0, 1],
	}, {"b": "a", "c": "b"})
	check(lines(nested) == ["a", "├─ b", "│  ├─ self", "│  └─ c", "└─ self"],
		"children nest under their parent and keep its column open")
	check(int(nested[1]["depth"]) == 1 and int(nested[3]["depth"]) == 2,
		"the depth counts the nesting levels")
	check(float(nested[2]["total"]) == 4.0 and bool(nested[2]["self"]),
		"a parent's unmeasured cost is its own row")
	check(str(nested[2]["parent"]) == "b" and int(nested[2]["calls"]) == 0,
		"a self row names its parent and has no calls")
	check(float(nested[4]["total"]) == 4.0, "the root's residual is its own cost")

	var orphan := TREE.layout({"x": [3.0, 1]}, {"x": "missing"})
	check(lines(orphan) == ["x"], "a parent absent from the window makes a root")

	var over := TREE.layout({"a": [1.0, 1], "b": [3.0, 1]}, {"b": "a"})
	check(lines(over) == ["a", "└─ b"], "children larger than the parent print no residual")

	var noise := TREE.layout({"a": [1.0, 1], "b": [0.995, 1]}, {"b": "a"})
	check(lines(noise) == ["a", "└─ b"], "a residual under 10us prints no row")

	var leaf := TREE.layout({"a": [1.0, 1]}, {})
	check(lines(leaf) == ["a"], "a leaf has no self row")

	print("PERF_TREE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("PERF_TREE_PASS")
	quit(0 if failures == 0 else 1)
