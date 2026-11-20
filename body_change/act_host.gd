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
## The suspend/resume steps the handover executes in order. Each is one act operation; the act
## owns the order, this host owns how each reaches the live systems.
var attach_to_world_cb: Callable = Callable()
var release_carry_cb: Callable = Callable()
var release_contacts_cb: Callable = Callable()
var remember_auto_cb: Callable = Callable()
var release_act_body_cb: Callable = Callable()
var release_scene_cb: Callable = Callable()
var free_pose_cb: Callable = Callable()
var restore_camera_cb: Callable = Callable()
var stop_breath_cb: Callable = Callable()
var resume_body_cb: Callable = Callable()
var prepare_anatomy_act_cb: Callable = Callable()
var apply_resume_settings_cb: Callable = Callable()
var rebind_reactions_cb: Callable = Callable()
var set_act_pose_config_cb: Callable = Callable()
var rebuild_act_pose_cb: Callable = Callable()
var sync_start_config_cb: Callable = Callable()
var reset_visual_for_form_cb: Callable = Callable()
var reset_player_pelvis_cb: Callable = Callable()
var reset_lean_cb: Callable = Callable()
var prepare_start_camera_cb: Callable = Callable()
var open_camera_cb: Callable = Callable()
var hide_avatar_cb: Callable = Callable()
var reset_wings_cb: Callable = Callable()
var claim_nav_cb: Callable = Callable()
var pause_face_turn_cb: Callable = Callable()
var reset_face_cb: Callable = Callable()
var apply_voice_policy_cb: Callable = Callable()
var apply_pose_change_cb: Callable = Callable()
var apply_anatomy_live_cb: Callable = Callable()
var begin_integrations_cb: Callable = Callable()
var sync_hud_cb: Callable = Callable()
var resume_auto_cb: Callable = Callable()
## The same-node revision: rebind every body-bound system for a revised form, without a resume.
var rebind_body_cb: Callable = Callable()
var prepare_standing_camera_cb: Callable = Callable()
var new_body_adult_cb: Callable = Callable()


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


## Move the live runtime under the world before the old body is freed. The runtime owns the
## reparent and its own swapping flag.
func attach_to_world() -> void:
	_call(attach_to_world_cb)


## Release a body another system holds. False means the release failed and the swap continues.
func release_carry() -> bool:
	return bool(_value(release_carry_cb, false))


## The old body's contact state: the kiss and the hands must not survive the flame.
func release_contacts() -> void:
	_call(release_contacts_cb)


## Record the auto stroke's on/off state, then stop it for the release.
func remember_auto() -> void:
	_call(remember_auto_cb)


## The act body: the wings release and the anatomy act closes.
func release_act_body() -> void:
	_call(release_act_body_cb)


## The navigator lease and the standing face-turn hold.
func release_scene() -> void:
	_call(release_scene_cb)


## The one pose ledger plus the bone restore, in the act's order.
func release_swap_pose() -> void:
	_call(free_pose_cb)


func restore_camera() -> void:
	_call(restore_camera_cb)


func stop_breath() -> void:
	_call(stop_breath_cb)


## Bind the adopted body to the pose, face and act view, and wake it.
func resume_body() -> void:
	_call(resume_body_cb)


## Refresh the new body's persistent anatomy controller and open its act handle.
func prepare_anatomy_act() -> void:
	_call(prepare_anatomy_act_cb)


## Re-read the settings snapshot on the adopted body without treating the live shape as an edit.
func apply_resume_settings() -> void:
	_call(apply_resume_settings_cb)


func rebind_reactions() -> void:
	_call(rebind_reactions_cb)


func set_act_pose_config() -> void:
	_call(set_act_pose_config_cb)


## The new skeleton takes the live pose again; the runtime supplies the pose id.
func rebuild_act_pose() -> void:
	_call(rebuild_act_pose_cb)


func sync_start_config() -> void:
	_call(sync_start_config_cb)


func reset_visual_for_form() -> void:
	_call(reset_visual_for_form_cb)


func reset_player_pelvis() -> void:
	_call(reset_player_pelvis_cb)


func reset_lean() -> void:
	_call(reset_lean_cb)


func prepare_start_camera() -> void:
	_call(prepare_start_camera_cb)


## The act camera open. The runtime starts the VR act when the shot asks for it.
func open_camera() -> void:
	_call(open_camera_cb)


func hide_avatar() -> void:
	_call(hide_avatar_cb)


func reset_wings() -> void:
	_call(reset_wings_cb)


func claim_nav() -> void:
	_call(claim_nav_cb)


func pause_face_turn() -> void:
	_call(pause_face_turn_cb)


## The act lids: clear, then the steady act face.
func reset_face() -> void:
	_call(reset_face_cb)


func apply_voice_policy() -> void:
	_call(apply_voice_policy_cb)


func apply_pose_change() -> void:
	_call(apply_pose_change_cb)


func apply_anatomy_live() -> void:
	_call(apply_anatomy_live_cb)


func begin_integrations() -> void:
	_call(begin_integrations_cb)


func sync_hud() -> void:
	_call(sync_hud_cb)


## Restore the preserved auto stroke when the act is live again.
func resume_auto() -> void:
	_call(resume_auto_cb)


## A revised form on the same presented body: one idempotent rebind of every body-bound system.
func rebind_body() -> void:
	_call(rebind_body_cb)


func prepare_standing_camera() -> void:
	_call(prepare_standing_camera_cb)


func new_body_adult() -> bool:
	return bool(_value(new_body_adult_cb, true))


func _call(callback: Callable, args: Array = []) -> void:
	if callback.is_valid():
		callback.callv(args)
