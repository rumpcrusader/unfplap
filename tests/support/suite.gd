extends SceneTree
## Base for every headless suite: counters, check(), the result line and the quit.
## A suite extends this file, implements run() and calls finish().

var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	pass

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)

func finish() -> void:
	print("%s_RESULT checks=%d failures=%d" % [_result_prefix(), checks, failures])
	quit(0 if failures == 0 else 1)

func _result_prefix() -> String:
	# Path-derived label, collapsing an overlap between the directory and the topic.
	var script: Script = get_script()
	var path: String = script.resource_path.trim_prefix("res://mods/unfplap/tests/")
	var parts: PackedStringArray = path.trim_suffix(".gd").split("/")
	var topic: String = parts[parts.size() - 1].trim_prefix("test_")
	if parts.size() == 1:
		return topic.to_upper()
	var dir: String = parts[0]
	if topic == dir:
		return dir.to_upper()
	if topic.begins_with(dir + "_"):
		return topic.to_upper()
	if dir.ends_with("_" + topic):
		return dir.to_upper()
	return (dir + "_" + topic).to_upper()
