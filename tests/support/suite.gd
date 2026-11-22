extends SceneTree
## Base for every headless suite: the assertion helpers, the run/finish lifecycle and the result line.
## A suite extends this file, implements run(), and leaves the exit to finish().

var failures := 0
var checks := 0
## The deadline for run(); only the harness self-test lowers it in before().
var watchdog_seconds := 60.0
var _finished := false
var _start_ms := 0
var _end := "run"


func _initialize() -> void:
	_start_ms = Time.get_ticks_msec()
	_run_and_finish.call_deferred()


func _run_and_finish() -> void:
	before()
	# A run() that never returns fails here instead of leaving the runner without a result.
	var timer: SceneTreeTimer = create_timer(watchdog_seconds)
	timer.timeout.connect(_on_watchdog_timeout)
	await run()
	finish()


func _on_watchdog_timeout() -> void:
	if _finished:
		return
	_end = "watchdog"
	fail("run() did not finish")
	finish()


func before() -> void:
	pass


func teardown() -> void:
	pass


func run() -> void:
	fail("suite does not implement run()")


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		_report(text)


func check_eq(actual: Variant, expected: Variant, text: String) -> void:
	checks += 1
	if actual != expected:
		failures += 1
		_report("%s: expected %s, got %s" % [text, _show(expected), _show(actual)])


func check_ne(actual: Variant, unexpected: Variant, text: String) -> void:
	checks += 1
	if actual == unexpected:
		failures += 1
		_report("%s: did not expect %s" % [text, _show(unexpected)])


func check_approx(actual: float, expected: float, text: String, eps := 0.0001) -> void:
	checks += 1
	if not near(actual, expected, eps):
		failures += 1
		_report("%s: expected %s ± %s, got %s" % [text, _show(expected), _show(eps), _show(actual)])


func check_contains(haystack: Variant, needle: Variant, text: String) -> void:
	checks += 1
	var found := false
	if haystack is Dictionary:
		found = haystack.has(needle)
	elif haystack is Array:
		found = haystack.has(needle)
	elif haystack is String:
		found = haystack.contains(str(needle))
	else:
		found = str(haystack).contains(str(needle))
	if not found:
		failures += 1
		_report("%s: %s does not contain %s" % [text, _show(haystack), _show(needle)])


func check_empty(value: Variant, text: String) -> void:
	checks += 1
	var empty := false
	if value is String or value is StringName:
		empty = str(value).is_empty()
	elif value is Array:
		empty = value.is_empty()
	elif value is Dictionary:
		empty = value.is_empty()
	if not empty:
		failures += 1
		_report("%s: expected empty, got %s" % [text, _show(value)])


func check_size(value: Variant, expected: int, text: String) -> void:
	checks += 1
	var actual := -1
	if value is String or value is StringName:
		actual = str(value).length()
	elif value is Array:
		actual = value.size()
	elif value is Dictionary:
		actual = value.size()
	if actual != expected:
		failures += 1
		_report("%s: expected size %s, got %s" % [text, _show(expected), _show(actual)])


func check_same(actual: Variant, expected: Variant, text: String) -> void:
	checks += 1
	if not is_same(actual, expected):
		failures += 1
		_report("%s: expected the same object" % text)


func check_null(value: Variant, text: String) -> void:
	checks += 1
	if value != null:
		failures += 1
		_report("%s: expected null, got %s" % [text, _show(value)])


func check_not_null(value: Variant, text: String) -> void:
	checks += 1
	if value == null:
		failures += 1
		_report("%s: expected non-null" % text)


func fail(text: String) -> void:
	checks += 1
	failures += 1
	_report(text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func _show(value: Variant) -> String:
	var text: String = str(value)
	if value is String or value is StringName:
		text = "\"%s\"" % text
	return text.substr(0, 200)


func _report(text: String) -> void:
	var where := ""
	for frame in get_stack():
		var source: String = frame.get("source", "")
		if source.is_empty() or source.ends_with("tests/support/suite.gd"):
			continue
		where = " (%s:%d)" % [source, frame.get("line", 0)]
		break
	print("FAIL [%s] %s%s" % [_result_prefix(), text, where])


func finish() -> void:
	if _finished:
		return
	_finished = true
	teardown()
	if checks == 0:
		_end = "no-checks"
		fail("suite has no checks")
	print("%s_RESULT checks=%d failures=%d" % [_result_prefix(), checks, failures])
	_write_result()
	quit(0 if failures == 0 else 1)


func _write_result() -> void:
	# The runner's input: one line, and an absent or unwritable path leaves the print as the fallback.
	var path := OS.get_environment("UNFPLAP_SUITE_RESULT")
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	var seconds := float(Time.get_ticks_msec() - _start_ms) / 1000.0
	file.store_line("suite=%s label=%s checks=%d failures=%d seconds=%.3f end=%s" % [
		_suite_path(), _result_prefix(), checks, failures, seconds, _end])


func _suite_path() -> String:
	var script: Script = get_script()
	var path: String = script.resource_path
	var prefix := "res://mods/unfplap/tests/"
	if not path.begins_with(prefix):
		return path.get_file().get_basename()
	return path.trim_prefix(prefix).trim_suffix(".gd")


func _result_prefix() -> String:
	# Path-derived label; a directory prefix keeps sibling suites distinct.
	var script: Script = get_script()
	var path: String = script.resource_path
	var prefix := "res://mods/unfplap/tests/"
	if not path.begins_with(prefix):
		return path.get_file().get_basename()
	var parts: PackedStringArray = path.trim_prefix(prefix).trim_suffix(".gd").split("/")
	var topic: String = parts[parts.size() - 1].trim_prefix("test_")
	var dir: String = "_".join(parts.slice(0, parts.size() - 1))
	if dir.is_empty():
		return topic.to_upper()
	if topic == dir:
		return dir.to_upper()
	if topic.begins_with(dir + "_"):
		return topic.to_upper()
	return (dir + "_" + topic).to_upper()
