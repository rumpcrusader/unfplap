extends RefCounted
## The act's frame-level presentation and the small values the live systems write back to it; no
## owner's rules live here.
##
## See `docs/runtime.md`, `docs/face.md`, `docs/readiness.md` and `docs/anatomy.md`.

const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")
const ACT_FACE := preload("res://mods/unfplap/shared/act_face.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/service.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")

var host: ACT_HOST = null
var context: ACT_CONTEXT = null
var session: ACT_SESSION = null
## The pose-settled diagnostic row, bound once so the per-frame log call allocates no callable.
var _diag := Callable()


func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT, session_in: ACT_SESSION) -> void:
	host = host_in
	context = context_in
	session = session_in
	_diag = Callable(self, "pose_diag_row")


## One presentation frame in the live states: the act clock, the blush, the wings and the
## integrations. The blush arc and the wings' stage read the same satisfaction.
func presentation(delta: float) -> void:
	if not is_instance_valid(host.pony):
		return
	session.advance_act_seconds(delta)
	if session.pose_family() == "bed":
		context.anatomy.bind(context.anatomy_host)
		context.anatomy.aim_eyes()
	var boop := GAME.boop_of(host.pony)
	if boop != null:
		GAME.sustain_blush(boop, ACT_FACE.blush_for(ACT_FACE.phase_for(session.state),
			context.readiness.satisfaction, session.feature("blush_arc")))
	PERF.begin("wings_tick")
	context.wings.tick(delta, str(context.pose.view().family), context.readiness.satisfaction,
		session.act_seconds())
	PERF.end("wings_tick")
	context.integrations.tick(delta)


## The render-time placement trace: the pose settle log with its one diagnostic row.
func log_settled() -> void:
	context.pose.log_settled(session.state, _diag)


## The posed Anon body's diagnostic row, or silence when the act has no Anon body.
func pose_diag_row() -> String:
	return context.anatomy.diag_row(context.camera.missionary_face_point(),
		context.camera.missionary_vulva_point())


## The presentation controllers' look write-back: the camera's captured look and the view mirror.
func set_look(yaw: float, pitch: float) -> void:
	context.camera.look_yaw = yaw
	context.camera.look_pitch = pitch
	context.facts.look_yaw = yaw
	context.facts.look_pitch = pitch


## The forced glance is the session's value; the view mirrors it for the controllers.
func set_forced_glance(side: String) -> void:
	session.forced_glance = side
	context.facts.forced_glance = side


func set_camera_basis_ready() -> void:
	context.camera.camera_basis_ready = true


## The fluid ground the anatomy bridge reads: the missionary bed top, else the pony's ground.
func fluid_ground_y() -> float:
	var ground: float = host.pony.global_position.y if is_instance_valid(host.pony) else 0.0
	if session.pose_family() != "bed" or context.view == null:
		return ground
	var top := context.view.bed_surface_top()
	return top if is_finite(top) else ground


## The anatomy service's visible shaft length, or zero when the part is not showing. The readiness
## stroke state turns zero into the nominal length, so the mouse feel is the same with it off.
func shaft_length_m() -> float:
	var service := PONIES.anatomy as ANATOMY
	if service == null:
		return 0.0
	var length := service.player_shaft_length_m()
	return length if length > 0.001 else 0.0


## The readiness meter's cue write-back into the view, then the dialogue owner's one admission.
func cue(mood_value: String, cue_value: String, is_override: bool) -> void:
	context.facts.mood = mood_value
	context.facts.cue = cue_value
	context.facts.cue_override = is_override
	context.dialogue.admit_cue(session.clock_s())


## The oral edge's speech stop: her authored line, the shared director turn and her own voice end
## once when the edge starts. The mouth shape follows through the separate viseme event.
func oral_speech_stop() -> void:
	context.dialogue.end_act(session.event_id, false)
	context.dialogue.stop_oral_turn(session.pony_id)
	stop_speech()


## Stop her own voice. `stop_speaking()` restores the rest viseme, so the oral turn re-asserts its
## mouth shape; the turn is the only owner of the open mouth.
func stop_speech() -> void:
	if not is_instance_valid(host.pony):
		return
	if GAME.pony_speaking(host.pony):
		GAME.stop_speaking(host.pony)
		context.anatomy.hold_oral_mouth()
