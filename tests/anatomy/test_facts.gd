extends SceneTree
## The typed anatomy context: defaults and the optional host callbacks.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/anatomy/test_facts.gd

const FACTS := preload("res://mods/unfplap/anatomy/facts.gd")
const ACT := preload("res://mods/unfplap/anatomy/act.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")

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
	check(facts.pose_view == null, "pose view starts absent")
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

	check(facts.contact_kind() == "" and facts.family() == "" and facts.frame() == "",
		"a null view has no contact, family or frame")
	check(not facts.mouth_contact() and not facts.face_contact()
		and not facts.bed_pose() and not facts.missionary(),
		"a null view matches no contact or pose predicate")

	var view: Variant = VIEW.new()
	view.family = "bed"
	view.frame = "bed"
	view.contact_kind = "mouth"
	facts.pose_view = view
	check(facts.contact_kind() == "mouth" and facts.mouth_contact(),
		"the mouth contact reads the view")
	check(not facts.face_contact(), "the mouth contact is not the face contact")
	check(facts.family() == "bed" and facts.missionary(),
		"the bed family is the missionary pose")
	check(facts.frame() == "bed" and facts.bed_pose(),
		"the bed frame carries the part inset")
	view.contact_kind = "face"
	check(facts.face_contact() and not facts.mouth_contact(),
		"the face contact reads the view")
	view.family = "standing"
	view.frame = "ground"
	view.contact_kind = "opening"
	check(facts.contact_kind() == "opening" and facts.family() == "standing"
		and facts.frame() == "ground", "the standing opening carries its family and frame")
	check(not facts.mouth_contact() and not facts.face_contact()
		and not facts.bed_pose() and not facts.missionary(),
		"a standing opening matches no contact or bed predicate")

	var act: Node = ACT.new()
	var kept := FACTS.new()
	act.set("_facts", kept)
	act.call("reset")
	check(is_same(act.get("_facts"), kept), "reset keeps the context it was given")
	act.free()

	print("ANATOMY_FACTS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ANATOMY_FACTS_PASS")
	quit(0 if failures == 0 else 1)
