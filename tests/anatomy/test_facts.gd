extends SceneTree
## The typed anatomy context: defaults and the optional host callbacks.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/anatomy/test_facts.gd

const FACTS := preload("res://mods/unfplap/anatomy/facts.gd")

var failures := 0
var checks := 0


class Sink extends RefCounted:
	var perf_calls := 0
	var last_chunk := ""
	var last_usec := 0
	var log_text := ""
	var smack_calls := 0

	func note(chunk: String, usec: int) -> void:
		perf_calls += 1
		last_chunk = chunk
		last_usec = usec

	func write(text: String) -> void:
		log_text = text

	func smack() -> void:
		smack_calls += 1


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var facts := FACTS.new()
	check(facts.state == 0, "state starts idle")
	check(facts.pose_id == "", "pose starts empty")
	check(is_zero_approx(facts.depth), "depth starts at zero")
	check(is_zero_approx(facts.penetration_m), "penetration starts at zero")
	check(facts.climaxes == 0, "climaxes start at zero")
	check(is_equal_approx(facts.size_scale, 1.0), "size scale starts at one")
	check(is_equal_approx(facts.auto_pace, 1.0), "auto pace starts at one")
	check(facts.bed_frame == null, "bed frame starts null")
	check(facts.cycle_phase == "normal", "cycle starts normal")
	check(not facts.perf_note.is_valid(), "perf callback starts absent")
	check(not facts.perf_on, "perf gate starts off")
	check(not facts.log.is_valid(), "log callback starts absent")
	check(not facts.body_coat_smack.is_valid(), "smack callback starts absent")

	facts.perf("nothing", 5)
	facts.write_log("nothing")
	facts.smack_body_coat()
	check(true, "absent callbacks are no-ops")

	var sink := Sink.new()
	facts.perf_note = Callable(sink, "note")
	facts.log = Callable(sink, "write")
	facts.body_coat_smack = Callable(sink, "smack")
	facts.perf("anatomy_tick", 42)
	check(sink.perf_calls == 1, "the perf callback receives one call")
	check(sink.last_chunk == "anatomy_tick" and sink.last_usec == 42,
		"the perf callback keeps the chunk and microseconds")
	facts.write_log("attached")
	check(sink.log_text == "attached", "the log callback receives the line")
	facts.smack_body_coat()
	check(sink.smack_calls == 1, "the smack callback receives one call")

	print("ANATOMY_FACTS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ANATOMY_FACTS_PASS")
	quit(0 if failures == 0 else 1)
