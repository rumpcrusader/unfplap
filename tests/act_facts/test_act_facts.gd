extends SceneTree
## The typed act context: defaults, host callbacks and the runtime write-backs.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/act_facts/test_act_facts.gd

const FACTS := preload("res://mods/unfplap/act_facts.gd")

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
	var offer_ok := true
	var paused := false
	var restored := 0

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

	func offer(_pose: String, _source: String, _bed: Variant) -> bool:
		return offer_ok

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
	check(facts.pose_id == "", "pose starts empty")
	check(facts.source == "", "source starts empty")
	check(is_zero_approx(facts.satisfaction), "satisfaction starts at zero")
	check(facts.mood == "" and facts.cue == "", "mood and cue start empty")
	check(facts.pony_climaxes == 0, "climaxes start at zero")
	check(is_zero_approx(facts.depth) and is_zero_approx(facts.penetration_m),
		"stroke values start at zero")
	check(is_equal_approx(facts.penetration_reach, 0.2), "reach starts at the nominal shaft")
	check(is_equal_approx(facts.size_scale, 1.0), "size scale starts at one")
	check(not facts.player_pony and not facts.headset_view, "view flags start false")
	check(facts.bed_frame == null, "bed frame starts null")
	check(facts.main == null and facts.pony == null and facts.camera == null
		and facts.pose == null, "scene handles start null")
	check(facts.event_id == "" and facts.pony_id == "", "line ids start empty")
	check(facts.features.is_empty() and facts.preferences.is_empty(),
		"feature and preference blocks start empty")
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
	check(true, "absent callbacks are no-ops")

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
	check(true, "absent readiness and scene-hold callbacks are no-ops")
	check(facts.driver_host() == null, "an absent pose host returns null")
	check(not facts.offer_allowed("standing", ""), "an absent offer gate refuses")
	check(facts.standing_camera_controller() == null, "an absent camera callback returns null")
	check(facts.pose_driver() == null, "an absent pose driver returns null")
	facts.on_touch = Callable(sink, "touch_event")
	facts.on_smack = Callable(sink, "impact")
	facts.can_offer = Callable(sink, "offer")
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
	check(facts.offer_allowed("standing", "") and sink.offer_ok, "the offer gate answers the caller")
	sink.offer_ok = false
	check(not facts.offer_allowed("standing", ""), "a closed offer gate refuses")
	check(facts.driver_host() == sink, "the pose host callback returns the host")
	check(is_equal_approx(facts.physics_delta, 0.016), "the physics delta starts at 60 Hz")

	print("ACT_FACTS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACT_FACTS_PASS")
	quit(0 if failures == 0 else 1)
