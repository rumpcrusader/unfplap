extends SceneTree
## The typed act context: defaults, host callbacks and the runtime write-backs.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/act_facts/test_act_facts.gd

const FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const ANATOMY_FACTS := preload("res://mods/unfplap/anatomy/facts.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")

var failures := 0
var checks := 0


class Sink extends RefCounted:
	var perf_calls := 0
	var last_chunk := ""
	var last_usec := 0
	var log_text := ""
	var smack_calls := 0
	var look_yaw := 0.0
	var look_pitch := 0.0
	var glance := ""
	var basis_ready := 0
	var kiss_calls := 0
	var neck := Vector3(1.0, 2.0, 3.0)
	var touch_kind := ""
	var touch_calls := 0
	var impact_strength := 0.0
	var paused := false
	var restored := 0
	var mod_active := false

	func mod_on(_id: String) -> bool:
		return mod_active

	func note(chunk: String, usec: int) -> void:
		perf_calls += 1
		last_chunk = chunk
		last_usec = usec

	func write(text: String) -> void:
		log_text = text

	func smack() -> void:
		smack_calls += 1

	func look(yaw: float, pitch: float) -> void:
		look_yaw = yaw
		look_pitch = pitch

	func force_glance(side: String) -> void:
		glance = side

	func mark_ready() -> void:
		basis_ready += 1

	func controller() -> Variant:
		kiss_calls += 1
		return "kiss"

	func neck_point() -> Vector3:
		return neck

	func clock_now() -> float:
		return 7.5

	func touch_event(kind: String) -> void:
		touch_kind = kind
		touch_calls += 1

	func impact(strength: float) -> void:
		impact_strength = strength

	func pause(on: bool) -> void:
		paused = on

	func restore() -> void:
		restored += 1

	func host() -> Variant:
		return self


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
	check(facts.pose_view == null and facts.main == null,
		"the scene handles start absent")
	check(facts.mood == "" and facts.cue == "", "mood and cue start empty")
	check(facts.pony_climaxes == 0, "climaxes start at zero")
	check(is_zero_approx(facts.clock()), "the line clock starts at zero")
	check(not facts.director.is_valid(), "the director callback starts absent")
	check(not facts.now.is_valid(), "the clock callback starts absent")
	check(not facts.perf_note.is_valid(), "perf callback starts absent")
	check(not facts.log.is_valid(), "log callback starts absent")
	check(not facts.kiss.is_valid(), "kiss callback starts absent")
	check(not facts.neck_point.is_valid(), "neck callback starts absent")
	check(not facts.set_look.is_valid(), "look write-back starts absent")

	facts.perf("nothing", 5)
	facts.write_log("nothing")
	facts.smack_body_coat()
	facts.write_look(1.0, 2.0)
	facts.write_forced_glance("L")
	facts.mark_camera_basis_ready()
	check(facts.kiss_controller() == null, "absent kiss callback returns null")
	check(facts.neck_midpoint() == Vector3.INF, "absent neck callback returns infinity")

	var sink := Sink.new()
	facts.perf_note = Callable(sink, "note")
	facts.log = Callable(sink, "write")
	facts.body_coat_smack = Callable(sink, "smack")
	facts.set_look = Callable(sink, "look")
	facts.set_forced_glance = Callable(sink, "force_glance")
	facts.set_camera_basis_ready = Callable(sink, "mark_ready")
	facts.kiss = Callable(sink, "controller")
	facts.neck_point = Callable(sink, "neck_point")
	facts.now = Callable(sink, "clock_now")
	facts.perf("act_tick", 42)
	check(sink.perf_calls == 1 and sink.last_chunk == "act_tick" and sink.last_usec == 42,
		"the perf callback keeps the chunk and microseconds")
	facts.write_log("act line")
	check(sink.log_text == "act line", "the log callback receives the line")
	facts.smack_body_coat()
	check(sink.smack_calls == 1, "the smack callback receives one call")
	facts.write_look(0.4, -0.2)
	check(is_equal_approx(sink.look_yaw, 0.4) and is_equal_approx(sink.look_pitch, -0.2),
		"the look write-back keeps yaw and pitch")
	facts.write_forced_glance("R")
	check(sink.glance == "R", "the glance write-back keeps the side")
	facts.mark_camera_basis_ready()
	check(sink.basis_ready == 1, "the basis write-back fires once")
	check(facts.kiss_controller() == "kiss" and sink.kiss_calls == 1,
		"the kiss callback returns the controller")
	check(facts.neck_midpoint() == sink.neck, "the neck callback returns the point")
	check(is_equal_approx(facts.clock(), 7.5), "the clock callback supplies the act clock")

	check(not facts.on_touch.is_valid() and not facts.on_smack.is_valid(),
		"the readiness callbacks start absent")
	facts.touch("caress")
	facts.smack_hit(0.4)
	facts.pause_face(true)
	facts.restore_face()
	check(facts.driver_host() == null, "an absent pose host returns null")
	check(not facts.mod_active("kissing"), "an absent mod gate reads as inactive")
	check(facts.standing_camera_controller() == null, "an absent camera callback returns null")
	check(facts.pose_driver() == null, "an absent pose driver returns null")
	facts.on_touch = Callable(sink, "touch_event")
	facts.on_smack = Callable(sink, "impact")
	facts.mod_enabled = Callable(sink, "mod_on")
	facts.pause_face_turn = Callable(sink, "pause")
	facts.restore_face_turn = Callable(sink, "restore")
	facts.pose_host = Callable(sink, "host")
	facts.touch("kiss")
	check(sink.touch_calls == 1 and sink.touch_kind == "kiss",
		"the touch callback receives the kind")
	facts.smack_hit(0.25)
	check(is_equal_approx(sink.impact_strength, 0.25), "the smack callback receives the strength")
	facts.pause_face(true)
	check(sink.paused, "the face-turn pause callback receives the force flag")
	facts.restore_face()
	check(sink.restored == 1, "the face-turn restore callback fires once")
	check(not facts.mod_active("kissing"), "the mod gate reports an inactive mod")
	sink.mod_active = true
	check(facts.mod_active("kissing"), "the mod gate reports an active mod")
	check(facts.driver_host() == sink, "the pose host callback returns the host")
	check(is_equal_approx(facts.physics_delta, 0.016), "the physics delta starts at 60 Hz")

	var view: RefCounted = VIEW.new()
	facts.pose_view = view
	check(is_same(facts.pose_view, view), "the pose view is carried as one object")
	facts.pose_view = null
	check(facts.pose_view == null, "the pose view clears")

	# The anatomy context shares the host-callback boundary: an unbound call is a no-op and a
	# bound one receives the chunk, the log line and the smack.
	var anatomy_facts := ANATOMY_FACTS.new()
	anatomy_facts.perf("nothing", 5)
	anatomy_facts.write_log("nothing")
	anatomy_facts.smack_body_coat()
	var anatomy_sink := Sink.new()
	anatomy_facts.perf_note = Callable(anatomy_sink, "note")
	anatomy_facts.log = Callable(anatomy_sink, "write")
	anatomy_facts.body_coat_smack = Callable(anatomy_sink, "smack")
	anatomy_facts.perf("anatomy_tick", 42)
	check(anatomy_sink.perf_calls == 1 and anatomy_sink.last_chunk == "anatomy_tick"
		and anatomy_sink.last_usec == 42,
		"the anatomy perf callback keeps the chunk and microseconds")
	anatomy_facts.write_log("attached")
	check(anatomy_sink.log_text == "attached", "the anatomy log callback receives the line")
	anatomy_facts.smack_body_coat()
	check(anatomy_sink.smack_calls == 1, "the anatomy smack callback receives one call")
	anatomy_facts.perf_note = Callable()
	anatomy_facts.log = Callable()
	anatomy_facts.body_coat_smack = Callable()
	anatomy_facts.perf("nothing", 5)
	anatomy_facts.write_log("nothing")
	anatomy_facts.smack_body_coat()

	print("ACT_FACTS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACT_FACTS_PASS")
	quit(0 if failures == 0 else 1)
