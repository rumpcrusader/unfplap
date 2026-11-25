extends RefCounted
## The act's settings boundary: one snapshot per act and one live re-apply. One per pony, owned by
## `act/session.gd`: the session is the only reader of the act tunables, through this module.
## Values arrive once per act and again on `apply_live()`, never per frame.

const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const REACTIONS_CONTEXT := preload("res://mods/unfplap/reactions/context.gd")
const ACT_HOST := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const CAMERA_CONFIG := preload("res://mods/unfplap/camera/config.gd")
const DIALOGUE := preload("res://mods/unfplap/dialogue/api.gd")

## The `CLIMAX` length the reaction window and the face beat read.
const CLIMAX_SECONDS := 5.0

## The one bulk snapshot; consumers read it at the use site, and a zeroed stand-in covers the
## time before the first act.
var snapshot: SETTINGS.ActSnapshot = SETTINGS.ActSnapshot.new()
## The typed reads the act itself makes from the snapshot, so no caller reaches into the raw
## settings document.
var features: Dictionary = {}
var presentation_config: Dictionary = {}
var max_pony_climaxes := 0
var climax_mode := ""

var host: ACT_HOST = null
var context: ACT_CONTEXT = null


func bind(host_in: ACT_HOST, context_in: ACT_CONTEXT) -> void:
	host = host_in
	context = context_in


## Snapshot every tunable the act reads while running and push it to its owners. `group` is the
## start spec's settings group: an internal pose has no block of its own and must never come here.
func snapshot_values(group: String, family: String) -> void:
	snapshot = SETTINGS.act_snapshot(group)
	features = snapshot.features
	max_pony_climaxes = snapshot.max_pony_climaxes
	var tuning := REACTIONS_CONTEXT.new()
	tuning.fill(snapshot.jiggle, family, context.camera.jiggle_size_scale(), CLIMAX_SECONDS)
	context.reactions.configure(tuning)
	context.camera.configure(CAMERA_CONFIG.Config.from_dict(snapshot.camera_thrust))
	presentation_config = snapshot.presentation
	climax_mode = snapshot.climax_mode
	configure_dialogue()


func debug_face() -> bool:
	return SETTINGS.face_debug.get_bool()


## The act's live body is released; the one resume re-reads the snapshot and rebuilds the
## body-bound services, so an edit during the flame must touch neither.
func suspended() -> bool:
	return context.handover != null and context.handover.suspended


## The live edit outside an act: the standing presentation has its own values, and the anatomy
## feature is live outside acts too.
func apply_idle_live() -> void:
	context.presentation.apply_live_settings()


## The live edit's pre-view half inside an act; anatomy subscribes to the change on its own.
func apply_act_live_pre() -> void:
	pass


## The live preference refresh for a live id, or an empty dictionary when there is none.
func live_preferences(pony_id: String) -> Dictionary:
	return SETTINGS.preferences(pony_id).raw() if not pony_id.is_empty() else {}


## The live edit's post-view half: the integrations, the pose family's config, the modifiers
## and the face. The audio owns its own mute subscription, so no voice step runs here.
func apply_act_live(family: String) -> void:
	context.integrations.apply_live_settings()
	context.reactions.apply_radius()
	if family == "standing":
		context.kiss.refresh_rows()
		context.presentation.apply_live_settings()
	# The live block, the presentation, a running edge's target and the modifiers in one call.
	context.pose.apply_live_settings()
	_refresh_live_modifiers(family)
	context.face.ensure_bound(host.pony, host.node)
	context.face.sync_settings(debug_face())


## Push the debug talk/cue pacing settings into the pure scheduler.
func configure_dialogue() -> void:
	var pacing := DIALOGUE.Pacing.new()
	pacing.base_stable = snapshot.cue_base_stable_s
	pacing.override_stable = snapshot.cue_override_stable_s
	pacing.utterance_gap = snapshot.cue_utterance_gap_s
	pacing.demand_gap = snapshot.cue_demand_gap_s
	pacing.demand_repeat = snapshot.cue_demand_repeat_s
	pacing.max_age = snapshot.cue_max_age_s
	pacing.release_hold = snapshot.cue_release_hold_s
	context.dialogue.configure(pacing)


## The standing body's own palm scale; the pose session's act body palm refresh is in its apply.
func _refresh_live_modifiers(family: String) -> void:
	if family == "standing" and is_instance_valid(host.pony):
		context.standing_anon.refresh_palm()
