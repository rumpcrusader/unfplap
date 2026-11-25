extends "res://mods/unfplap/tests/support/suite.gd"
## The typed act context: defaults, host callbacks and the runtime write-backs.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/act_facts/test_act_facts.gd

const FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const ANATOMY_ACT := preload("res://mods/unfplap/anatomy/act.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")



class Sink extends RefCounted:
	var smack_calls := 0
	var look_yaw := 0.0
	var look_pitch := 0.0
	var glance := ""
	var basis_ready := 0
	var neck := Vector3(1.0, 2.0, 3.0)
	var touch_kind := ""
	var touch_calls := 0
	var anatomy_reacts := 0
	var impact_strength := 0.0
	var paused := false
	var restored := 0
	var mod_active := false

	func mod_on(_id: String) -> bool:
		return mod_active

	func smack() -> void:
		smack_calls += 1

	func look(yaw: float, pitch: float) -> void:
		look_yaw = yaw
		look_pitch = pitch

	func force_glance(side: String) -> void:
		glance = side

	func mark_ready() -> void:
		basis_ready += 1

	func neck_point() -> Vector3:
		return neck

	func clock_now() -> float:
		return 7.5

	func touch_event(kind: String) -> void:
		touch_kind = kind
		touch_calls += 1

	func impact(strength: float) -> void:
		impact_strength = strength

	func react() -> void:
		anatomy_reacts += 1

	func pause(on: bool) -> void:
		paused = on

	func restore() -> void:
		restored += 1

	func host() -> Variant:
		return self


func run() -> void:
	var facts := FACTS.new()
	check(facts.state == 0, "state starts idle")
	check(facts.pose_view == null and facts.pony == null,
		"the scene handles start absent")
	check(facts.mood == "" and facts.cue == "", "mood and cue start empty")
	check(facts.pony_climaxes == 0, "climaxes start at zero")
	check(is_zero_approx(facts.clock()), "the line clock starts at zero")
	check(not facts.director.is_valid(), "the director callback starts absent")
	check(not facts.now.is_valid(), "the clock callback starts absent")
	check(is_zero_approx(facts.kiss_amount) and not facts.kiss_active
		and is_zero_approx(facts.kiss_side), "the kiss mirrors start clear")
	check(is_zero_approx(facts.lean_drop_m) and is_zero_approx(facts.lean_distance_m),
		"the kiss lean mirrors start clear")
	check(not facts.neck_point.is_valid(), "neck callback starts absent")
	check(not facts.set_look.is_valid(), "look write-back starts absent")

	facts.write_look(1.0, 2.0)
	facts.write_forced_glance("L")
	facts.mark_camera_basis_ready()
	check(facts.neck_midpoint() == Vector3.INF, "absent neck callback returns infinity")

	var sink := Sink.new()
	facts.set_look = Callable(sink, "look")
	facts.set_forced_glance = Callable(sink, "force_glance")
	facts.set_camera_basis_ready = Callable(sink, "mark_ready")
	facts.neck_point = Callable(sink, "neck_point")
	facts.now = Callable(sink, "clock_now")
	facts.write_look(0.4, -0.2)
	check(is_equal_approx(sink.look_yaw, 0.4) and is_equal_approx(sink.look_pitch, -0.2),
		"the look write-back keeps yaw and pitch")
	facts.write_forced_glance("R")
	check(sink.glance == "R", "the glance write-back keeps the side")
	facts.mark_camera_basis_ready()
	check(sink.basis_ready == 1, "the basis write-back fires once")
	check(facts.neck_midpoint() == sink.neck, "the neck callback returns the point")
	check(is_equal_approx(facts.clock(), 7.5), "the clock callback supplies the act clock")

	check(not facts.on_caress.is_valid() and not facts.on_kiss.is_valid()
		and not facts.on_smack.is_valid() and not facts.on_anatomy_react.is_valid(),
		"the touch callbacks start absent")
	facts.touch("caress")
	facts.smack_hit(0.4)
	facts.pause_face(true)
	facts.restore_face()
	check(facts.driver_host() == null, "an absent pose host returns null")
	check(not facts.mod_active("kissing"), "an absent mod gate reads as inactive")
	check(facts.view_controller() == null, "an absent view callback returns null")
	check(facts.pose_driver() == null, "an absent pose driver returns null")
	facts.on_caress = Callable(sink, "touch_event").bind("caress")
	facts.on_kiss = Callable(sink, "touch_event").bind("kiss")
	facts.on_smack = Callable(sink, "touch_event").bind("smack")
	facts.on_anatomy_react = Callable(sink, "react")
	facts.on_smack_hit = Callable(sink, "impact")
	facts.mod_enabled = Callable(sink, "mod_on")
	facts.pause_face_turn = Callable(sink, "pause")
	facts.restore_face_turn = Callable(sink, "restore")
	facts.pose_host = Callable(sink, "host")
	facts.touch("kiss")
	check(sink.touch_calls == 1 and sink.touch_kind == "kiss",
		"a kiss reaches its own verb")
	check(sink.anatomy_reacts == 1, "a kiss reacts the anatomy mesh")
	facts.touch("caress")
	check(sink.touch_calls == 2 and sink.touch_kind == "caress",
		"a caress reaches its own verb")
	check(sink.anatomy_reacts == 1, "a caress reacts no anatomy")
	facts.touch("smack")
	check(sink.touch_calls == 3 and sink.anatomy_reacts == 2,
		"a smack reaches the meter and the anatomy")
	facts.touch("unknown")
	check(sink.touch_calls == 3, "an unknown kind dispatches nothing")
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

	finish()
