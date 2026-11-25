extends "res://mods/unfplap/body_change/act_host.gd"
## The handover's value contract as the live runtime answers it: every read points at the runtime's
## own typed fields, and the swap seam is the act's swap module.

const ACT_NODE := preload("res://mods/unfplap/act/host.gd")
const ACT_SESSION := preload("res://mods/unfplap/act/session.gd")
const ACT_SWAP := preload("res://mods/unfplap/act/swap.gd")
const ACT_DIALOGUE := preload("res://mods/unfplap/dialogue/api.gd")
const READINESS := preload("res://mods/unfplap/readiness/api.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")

var host: ACT_NODE = null
var act: ACT_SESSION = null
## The swap module; `swap()` below is the port read, so the field cannot share its name.
var act_swap: ACT_SWAP = null
var readiness: READINESS = null
var dialogue: ACT_DIALOGUE = null


func swap() -> SWAP_PORT:
	return act_swap


func runtime() -> Node:
	return host.runtime()


func pony() -> Node3D:
	return host.pony_value() as Node3D


func id() -> String:
	return act.act_id()


func act_live() -> bool:
	return act.act_live()


func restoring() -> bool:
	return act.restoring()


func state() -> int:
	return act.state_value()


func event_id() -> String:
	return act.event_id_value()


func depth() -> float:
	return readiness.readout().depth


func climaxes() -> int:
	return readiness.readout().climaxes


func max_climaxes() -> int:
	return act.climax_limit()


func satisfaction() -> float:
	return readiness.readout().satisfaction


func cue() -> String:
	return readiness.readout().cue


func pose_view() -> Variant:
	return act.pose_view()


func start_pose_id() -> String:
	return act.start_id()


func shape_name(shape_id: String) -> String:
	return SETTINGS.character_name(shape_id)


func reaction_line(reaction: int, event_id: String, fallback: String,
		valid: ACT_DIALOGUE.Validity) -> String:
	return dialogue.reaction_line(reaction, event_id, fallback, valid)


func validity(rule: Callable) -> ACT_DIALOGUE.Validity:
	return ACT_DIALOGUE.Validity.of(rule)


func note_reaction(key: String, cue_text: String, until: float) -> void:
	dialogue.note_reaction(key, cue_text, until)


func add_heat(amount: float) -> void:
	readiness.heat(amount)


func set_cue_override(text: String) -> void:
	act.form_cue_override(text)


func set_face(smile: float) -> void:
	act.form_set_face(smile)


func status(text: String) -> void:
	act.form_status(text)


func now() -> float:
	return act.clock_s()


func reaction_max_age() -> float:
	return act.cue_reaction_max_age()
