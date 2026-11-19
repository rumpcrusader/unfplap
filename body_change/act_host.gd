extends RefCounted
## The typed host boundary for one act's body-change handover. The runtime fills the named
## callbacks once; the handover reads live values through named methods and never sees a service
## locator.

var runtime_cb: Callable = Callable()
var pony_cb: Callable = Callable()
var id_cb: Callable = Callable()
var act_live_cb: Callable = Callable()
var restoring_cb: Callable = Callable()
var state_cb: Callable = Callable()
var event_id_cb: Callable = Callable()
var depth_cb: Callable = Callable()
var climaxes_cb: Callable = Callable()
var max_climaxes_cb: Callable = Callable()
var satisfaction_cb: Callable = Callable()
var cue_cb: Callable = Callable()
var pose_view_cb: Callable = Callable()
var start_pose_cb: Callable = Callable()
var shape_name_cb: Callable = Callable()
var reaction_line_cb: Callable = Callable()
var note_reaction_cb: Callable = Callable()
var add_heat_cb: Callable = Callable()
var cue_override_cb: Callable = Callable()
var set_face_cb: Callable = Callable()
var status_cb: Callable = Callable()
var now_cb: Callable = Callable()
var reaction_max_age_cb: Callable = Callable()
var log_cb: Callable = Callable()


static func _value(callback: Callable, fallback: Variant = null) -> Variant:
	return callback.call() if callback.is_valid() else fallback


func runtime() -> Node:
	var value: Variant = _value(runtime_cb)
	return value as Node if is_instance_valid(value) else null


func pony() -> Node3D:
	var value: Variant = _value(pony_cb)
	if not is_instance_valid(value) or not value is Node3D:
		return null
	return value


func id() -> String:
	return str(_value(id_cb, ""))


## True while the act can be suspended or asked for a form: posing in, active, climax or afterglow.
func act_live() -> bool:
	return bool(_value(act_live_cb, false))


func restoring() -> bool:
	return bool(_value(restoring_cb, false))


## The act's state value. The handover compares it with `shared/act_state.gd`; the runtime owns
## the enum's one writer.
func state() -> int:
	return int(_value(state_cb, 0))


## The act's event id, shared by the player's reactions and the reveal's memory marks.
func event_id() -> String:
	return str(_value(event_id_cb, ""))


func depth() -> float:
	return float(_value(depth_cb, 0.0))


func climaxes() -> int:
	return int(_value(climaxes_cb, 0))


func max_climaxes() -> int:
	return int(_value(max_climaxes_cb, 0))


func satisfaction() -> float:
	return float(_value(satisfaction_cb, 0.0))


func cue() -> String:
	return str(_value(cue_cb, ""))


func pose_view() -> Variant:
	return _value(pose_view_cb)


func start_pose_id() -> String:
	return str(_value(start_pose_cb, ""))


func shape_name(shape_id: String) -> String:
	if not shape_name_cb.is_valid():
		return shape_id
	return str(shape_name_cb.call(shape_id))


## Queue one reaction through the act's dialogue owner. The handover passes the memory reaction
## value and the validity closure; the runtime facade owns the line channel.
func reaction_line(reaction: int, event_id: String, fallback: String, valid: Callable) -> String:
	if not reaction_line_cb.is_valid():
		return ""
	return str(reaction_line_cb.call(reaction, event_id, fallback, valid))


func note_reaction(key: String, cue_text: String, until: float) -> void:
	if note_reaction_cb.is_valid():
		note_reaction_cb.call(key, cue_text, until)


## Add the reveal's heat through the readiness owner, which applies the act's cap.
func add_heat(amount: float) -> void:
	if add_heat_cb.is_valid():
		add_heat_cb.call(amount)


## Set the act's cue override; the runtime supplies its snapshot lifetime.
func set_cue_override(text: String) -> void:
	if cue_override_cb.is_valid():
		cue_override_cb.call(text)


## Apply the act's expression beat. The face owner supplies the lids for the act stage.
func set_face(smile: float) -> void:
	if set_face_cb.is_valid():
		set_face_cb.call(smile)


## One short toast for a named-form status note.
func status(text: String) -> void:
	if status_cb.is_valid():
		status_cb.call(text)


func now() -> float:
	return float(_value(now_cb, 0.0))


func reaction_max_age() -> float:
	return float(_value(reaction_max_age_cb, 0.0))


func log(text: String) -> void:
	if log_cb.is_valid():
		log_cb.call(text)
