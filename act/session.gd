extends RefCounted
## The act's one state, timer, clock and value owner. One per pony, created once and reset per act.
## It writes `state` through `_set_state()`; the runtime keeps the transition bodies and the side
## effects and asks this owner for the timer verdict, the clock values and the act's own values.
##
## See `docs/runtime.md`.

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const ACT_NODE := preload("res://mods/unfplap/act/host.gd")
const ACT_CONTEXT := preload("res://mods/unfplap/act/context.gd")
const PLACEMENT := preload("res://mods/unfplap/poses/placement.gd")
const POSE_SESSION := preload("res://mods/unfplap/poses/service.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const RELATIONSHIP_CUE := preload("res://mods/unfplap/shared/relationship_cue.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const DEBUG_PONY := preload("res://mods/unfplap/debug/pony.gd")
const BODY_CHANGE_POLICY := preload("res://mods/unfplap/shared/body_change_policy.gd")
const FACE := preload("res://mods/unfplap/face/service.gd")

const READINESS_MAX := 100.0

const State := ACT_STATE.State

const CLIMAX_SECONDS := 5.0
const POSE_IN_SECONDS := 0.6
const RESTORE_SECONDS := 0.4
## The scene gate's running-check cadence while the act is live.
const CHECK_SECONDS := 0.25

## The ordered tick's transition verbs. `tick_timers()` only counts down; the runtime applies the
## verb through its transition body.
const PHASE_NONE := 0
const ENTER_ACTIVE := 1
const FINISH_CLIMAX := 2
const FINISH_RESTORE := 3

## Bound once by the runtime. All are per-pony and outlive one act.
var host: ACT_NODE = null
var context: ACT_CONTEXT = null
## The ordered start ledger. Set once by the runtime; `begin()` is its one entry.
var start: Variant = null
## The act view composition. Bound once with the start ledger; the live settings pass refreshes it.
var view: Variant = null

## The act's settings snapshot. This module is its only writer; the act tunables are read through
## `snapshot.<name>`, never copied into a second field. A zeroed snapshot stands in until the first
## act, so an idle read sees the same zero values the old fields defaulted to.
var snapshot: SETTINGS.ActSnapshot = SETTINGS.ActSnapshot.new()
## The snapshot's climax limit and mode, read by the climax and face rules.
var max_pony_climaxes := 0
var climax_mode := ""
## The camera mode, cached with the rest because the render write runs every rendered frame.
var eye_camera_mode := false

## The live act state. `_set_state()` is the only writer.
var state: int = State.IDLE

## The act's own values, written at the start boundary and read by the view, the idle schedule,
## the scene gate and the ledgers. `pony_id` is the stable id; `display_name` is the presented
## form's name.
var pose_id := ""
var source := ""
var bed: Node3D = null
var event_id := ""
## The act's serial from `ponies`' allocator; `event_id` embeds it.
var serial := 0
var pony_id := ""
var display_name := "the pony"
var preferences: Dictionary = {}
var act_prompts: Dictionary = {}
var features: Dictionary = {}
var player_pony := false
var presentation_config: Dictionary = {}
var profile: Dictionary = {}
var caress_quality := ""
var forced_glance := ""
## Act-scope bookkeeping the ledgers read: what this act borrowed, what it finalized, and the
## values the aftercare plan is built from. `finalized` makes the post-act bookkeeping one-shot.
var posture_owned := false
var finalized := false
var stopped_by_her := false
var aftercare_min := 0
var cue_gap := 0.0
var first_time := false
var act_spoken_at := -1e9
## The last generated climax reaction line, so it can be extended while she speaks.
var climax_reaction_key := ""
## A cancelled act: the summary and the early-stop line read it.
var ended_early := false
## The estrus heat signal, resolved once per tick and carried in the HUD card.
var cycle_heat := false
## The resume re-reads the snapshot on the live shape; that is not a settings edit.
var preserve_auto_shape := false

## The `POSING_IN` timer: the pose settles into the act after this many seconds.
var _pose_in_left := 0.0
var _climax_left := 0.0
var _restore_left := 0.0
## The 0.25 s running-check accumulator.
var _check_clock := 0.0
## The `CLIMAX` state's 0..1 progress, read by the shot camera.
var _climax_progress := 0.0
## Processed-time clock. It only advances while the runtime ticks, so a paused tree freezes the
## act timing; it is never reset between acts.
var _clock_s := 0.0
var _act_seconds := 0.0


func bind(host_in: ACT_NODE, context_in: ACT_CONTEXT) -> void:
	host = host_in
	context = context_in


## Start one act. The ledger owns the recipe and the order; the session only enters it.
func begin(pose: String, bed_in: Variant, act_source: String, skip_presentation := false) -> bool:
	if start == null:
		return false
	return bool(start.run(pose, bed_in, act_source, skip_presentation))


## The one state writer. The scene gate's live values follow every transition.
func _set_state(next: int) -> void:
	state = next
	refresh_gate()


## Rebind the scene gate's body and pose session and push the act values it reads.
func refresh_gate() -> void:
	if context == null or context.gate == null:
		return
	var pony_node: Variant = host.pony if host != null else null
	context.gate.bind(pony_node, context.pose)
	context.gate.configure(state, pony_id, features)


## Elapsed act time, in seconds. The view reads it; `reset_act()` clears it.
func act_seconds() -> float:
	return _act_seconds


## The processed-time clock. It is monotonic across acts.
func clock_s() -> float:
	return _clock_s


## One act feature flag from the snapshot. Unknown flags read as off.
func feature(name: String) -> bool:
	return bool(features.get(name, false))


## The start spec row, read from the act's start pose id.
func start_row() -> Dictionary:
	return POSE_SPECS.spec(pose_id)


## The start spec's family. Start-time decisions read this before the view exists.
func start_family() -> String:
	return str(start_row().get("family", ""))


## The start spec's settings group. The internal poses share the standing group.
func start_group() -> String:
	return str(start_row().get("settings_group", ""))


## The pose build's live values. The start ledger and the body-swap rebuild both build from this
## one record, so a pose id and a scene value can never come from two readers.
func pose_values(pose: String, look: Vector3, camera_at: Vector3, size_name: String) -> POSE_SESSION.ActPose:
	var values := POSE_SESSION.ActPose.new()
	var target := pose if not pose.is_empty() else pose_id
	values.pose_id = str(POSE_SPECS.spec(target).get("id", ""))
	values.id = pony_id
	values.features = features
	values.bed = bed
	values.presentation = presentation_config
	values.pose_config = context.pose.pose_config
	values.look_point = look
	values.camera_position = camera_at
	values.size_name = size_name
	return values


## The presented body's name for the act caption and dialogue. The form's presentation name wins;
## the identity's display name is the fallback. The stable id stays the act's id: a borrowed shape
## still belongs to the same relationship, preferences and history.
func adopt_display_name(form: BODY_FORM.BodyForm, body: Variant) -> void:
	var presented := form.form_name.strip_edges() if form != null else ""
	if presented.is_empty() and is_instance_valid(body):
		var identity: Variant = body.get("identity")
		var display: Variant = identity.get("display_name") if identity != null else null
		presented = str(display).strip_edges() if display != null else ""
	display_name = presented if not presented.is_empty() else pony_id


## Re-read the stable identity from the presented body. True once an id exists; the scene gate
## follows every read so a late `relationship_id` reaches the offer rows. The id is the key for
## preferences, poses, prompts and memory; it is never derived twice.
func refresh_identity() -> bool:
	# A body freed during teardown must not reach the typed identity read; keep the last id.
	var identity: PONIES.Identity = PONIES.Identity.new()
	if is_instance_valid(host.pony):
		identity = PONIES.identity_of(host.pony)
	if not identity.id.is_empty():
		pony_id = identity.id
	if pony_id.is_empty():
		refresh_gate()
		return false
	context.pose.id = pony_id
	adopt_display_name(context.handover.form(), host.pony)
	refresh_gate()
	return true


## The live pose family, or the start spec's family before the first view fill. The start-time
## rules read this before the view exists.
func pose_family() -> String:
	var live: Variant = context.pose.view() if context.pose != null else null
	var family := str(live.family) if live != null else ""
	return family if not family.is_empty() else start_family()


func refresh_view() -> void:
	if view != null:
		view.refresh(context.facts, self)


## The placement handle's live act values. The start adapter and the body swap both place Anon
## from this one record.
func placement_values(form: BODY_FORM.BodyForm = null) -> PLACEMENT.ActBind:
	var values := PLACEMENT.ActBind.new()
	values.pony = host.pony
	values.player = WORLD.player if is_instance_valid(WORLD.player) else null
	values.bed = bed
	values.stool = context.stool
	values.form = form
	values.body_form = context.handover.form() if context.handover != null else null
	values.id = pony_id
	var gaps: Variant = context.pose.pose_config.get("gaps", {})
	values.gaps = gaps if gaps is Dictionary else {}
	values.camera = context.camera
	values.anatomy = PONIES.anatomy
	values.player_pony = player_pony
	values.headset_view = WORLD.headset_view()
	values.log = host.log_sink
	return values


func state_name() -> String:
	match state:
		State.POSING_IN:
			return "POSING_IN"
		State.ACTIVE:
			return "ACTIVE"
		State.CLIMAX:
			return "CLIMAX"
		State.AFTERGLOW:
			return "AFTERGLOW"
		State.RESTORE:
			return "RESTORE"
	return "IDLE"


## Start-of-act reset. The session itself is reused; only the act's own timers and elapsed time
## clear. The processed-time clock stays monotonic across acts.
func reset_act() -> void:
	_act_seconds = 0.0
	clear_phase()


## Clear the phase timers after a stop that did not run the restore timer.
func clear_phase() -> void:
	_pose_in_left = 0.0
	_climax_left = 0.0
	_restore_left = 0.0
	_check_clock = 0.0
	_climax_progress = 0.0


## Advance the act's processed-time clock. A negative frame delta is clamped to zero.
func tick_clock(delta: float) -> void:
	_clock_s += maxf(0.0, delta)


func advance_act_seconds(delta: float) -> void:
	_act_seconds += delta


## The 0.25 s running-check cadence. True only on the tick that crosses the interval.
func consume_check_clock(delta: float) -> bool:
	_check_clock += delta
	if _check_clock < CHECK_SECONDS:
		return false
	_check_clock = 0.0
	return true


func refresh_climax_progress() -> void:
	_climax_progress = clampf(1.0 - _climax_left / CLIMAX_SECONDS, 0.0, 1.0)


## Advance the one active transition timer. The caller owns what each verb does.
func tick_timers(delta: float) -> int:
	match state:
		State.POSING_IN:
			_pose_in_left -= delta
			if _pose_in_left <= 0.0:
				return ENTER_ACTIVE
		State.CLIMAX:
			_climax_left -= delta
			if _climax_left <= 0.0:
				return FINISH_CLIMAX
		State.RESTORE:
			_restore_left -= delta
			if _restore_left <= 0.0:
				return FINISH_RESTORE
	return PHASE_NONE


func enter_active() -> void:
	_set_state(State.ACTIVE)


func begin_pose_in() -> void:
	_set_state(State.POSING_IN)
	_pose_in_left = POSE_IN_SECONDS


func enter_climax() -> void:
	_set_state(State.CLIMAX)
	_climax_left = CLIMAX_SECONDS
	_climax_progress = 0.0


func enter_afterglow() -> void:
	_set_state(State.AFTERGLOW)


func begin_restore() -> void:
	_set_state(State.RESTORE)
	_restore_left = RESTORE_SECONDS


func finish_restore() -> void:
	enter_idle()


func enter_idle() -> void:
	_set_state(State.IDLE)
	_pose_in_left = 0.0
	_climax_left = 0.0
	_restore_left = 0.0
	_climax_progress = 0.0


## Snapshot every tunable the act reads per stroke or per frame. `apply_live_settings()` re-runs
## it so a settings edit applies without a new act.
func snapshot_settings() -> void:
	# The start spec's settings group selects the pose presentation block; an internal pose
	# (`standing_test`, `standing_oral`) has no block of its own and must never be passed here.
	snapshot = SETTINGS.act_snapshot(start_group())
	features = snapshot.features
	context.readiness.configure_thrust(snapshot.thrust_pixels_per_cm, snapshot.thrust_up,
		snapshot.thrust_travel, snapshot.pelvis_gap_m)
	max_pony_climaxes = snapshot.max_pony_climaxes
	context.readiness.configure_auto(snapshot.auto_pace, snapshot.auto_max_depth,
		snapshot.auto_curve, snapshot.auto_min_depth, preserve_auto_shape)
	context.reactions.configure({
		"jiggle": snapshot.jiggle,
		"pose_family": start_family(),
		"size_scale": context.camera.jiggle_size_scale(),
		"climax_seconds": CLIMAX_SECONDS,
	})
	context.camera.configure(snapshot.camera_thrust)
	context.readiness.configure(preferences, snapshot.cue_override_seconds,
		snapshot.cue_overwhelmed_s, snapshot.touch_cooldown_s, snapshot.talk_cooldown_s,
		snapshot.receptive_seconds)
	presentation_config = snapshot.presentation
	climax_mode = snapshot.climax_mode
	eye_camera_mode = str(SETTINGS.camera_mode.get_value()) == "eye"
	caress_quality = snapshot.caress_quality
	_configure_utterance_scheduler()
	refresh_gate()


## Re-read the settings tab's live-editable values during an act. Feature installs/removals are
## idempotent so repeated edits do not stack modifiers. Returns the perf flag the runtime caches.
func apply_live_settings() -> bool:
	# Snapshot before the IDLE early return too, so the act tunables apply as soon as they are
	# edited rather than only at the next act start.
	var perf := LOG.debug_logs and LOG.debug_perf
	# Read the pre-edit mute before the snapshot replaces `features`: a live Ponese mute edit is
	# only visible as a change against the value the act started with.
	var previous_mute := feature("mute_ponese_audio")
	snapshot_settings()
	if context.handover != null and context.handover.suspended:
		# The resume re-reads the snapshot and rebuilds the body-bound services; an edit during
		# the flame must not touch a released pose or the old body.
		return perf
	if state == State.IDLE:
		# The idle standing presentation has its own live values, so a settings edit reaches it
		# before the act-only work is skipped.
		refresh_view()
		context.presentation.apply_live_settings()
		# integration: the anatomy feature is live outside acts too.
		_anatomy_refresh()
		return perf
	_anatomy_refresh()
	refresh_view()
	context.integrations.apply_live_settings()
	context.reactions.apply_radius()
	if pose_family() == "standing":
		context.kiss.apply_live_settings()
		context.pose.sync_standing_config(presentation_config)
		context.presentation.apply_live_settings()
	elif pose_family() == "bed":
		context.pose.sync_missionary_config()
	# A running edge's target snapshot follows the same edit; the start pose's config sync above
	# stays for the compatibility readers.
	context.pose.apply_live_settings()
	if not pony_id.is_empty():
		preferences = SETTINGS.preferences(pony_id)
	_refresh_live_modifiers()
	context.face.ensure_bound(host.pony, host.node)
	context.face.sync_settings(feature("face_debug"))
	if previous_mute != feature("mute_ponese_audio"):
		_refresh_live_voice()
	if is_instance_valid(HUD.instance):
		sync_hud()
		HUD.instance.update_from(context.facts)
	return perf


func _refresh_live_modifiers() -> void:
	if not is_instance_valid(host.pony):
		return
	var skeleton_value: Variant = host.pony.get("skeleton")
	if not skeleton_value is Skeleton3D:
		return
	context.pose.refresh_modifiers(features)
	if pose_family() == "standing":
		context.standing_anon.refresh_palm()
	elif pose_family() == "bed":
		context.anatomy.bind(context.anatomy_host)
		context.anatomy.refresh_palm()


## A live voice-policy edit: give the player its saved volume back, then apply the new policy.
func _refresh_live_voice() -> void:
	if host.node == null or not host.node.is_inside_tree():
		return
	if not is_instance_valid(context.audio):
		return
	context.audio.restore_voice_policy()
	context.audio.apply_voice_policy(feature("mute_ponese_audio"), host.pony, pony_id)


func _anatomy_refresh() -> void:
	context.anatomy.bind(context.anatomy_host)
	context.anatomy.refresh()


## Push the debug talk/cue pacing settings into the pure scheduler.
func _configure_utterance_scheduler() -> void:
	context.dialogue.configure({
		"base_stable": snapshot.cue_base_stable_s,
		"override_stable": snapshot.cue_override_stable_s,
		"utterance_gap": snapshot.cue_utterance_gap_s,
		"demand_gap": snapshot.cue_demand_gap_s,
		"demand_repeat": snapshot.cue_demand_repeat_s,
		"max_age": snapshot.cue_max_age_s,
		"release_hold": snapshot.cue_release_hold_s,
	})


## The HUD card's live values through the view.
func sync_hud() -> void:
	view.sync_hud(context.facts, self, max_pony_climaxes, cycle_heat, pose_family())


## A fresh act's stroke, auto, presentation and dialogue state. The settings snapshot is already
## applied; this clears only the act's own counters.
func reset_thrust_state() -> void:
	context.readiness.reset_thrust()
	context.readiness.reset_auto()
	context.standing_anon.reset_phase()
	context.standing_camera.reset_depth()
	context.facts.standing_sway_offset = Vector3.ZERO
	context.readiness.reset(preferences)
	clear_phase()
	context.afterglow.reset()
	context.dialogue.reset(clock_s(), cue_gap)
	_configure_utterance_scheduler()
	act_spoken_at = -1e9
	ended_early = false


## The scene values the summary scores. The history facade owns the shape; the session owns the
## act values it reads.
func summary_values() -> Dictionary:
	return {
		"pony_id": pony_id,
		"event_id": event_id,
		"preferences": preferences,
		"seconds": act_seconds(),
		"thrusts": context.readiness.act_thrusts,
		"pony_climaxes": context.readiness.pony_climaxes,
		"talk_liked": context.readiness.act_liked_talk,
		"talk_dislikes": context.readiness.act_talk_dislikes,
		"touches_liked": context.readiness.act_liked_touch,
		"touch_dislikes": context.readiness.act_touch_dislikes,
		"player_lines": context.readiness.act_player_lines,
		"intensity_total": context.readiness.act_intensity_total,
		"intensity_right": context.readiness.act_intensity_right,
		"pattern_total": context.readiness.act_pattern_total,
		"pattern_right": context.readiness.act_pattern_right,
		"ended_early": ended_early,
		"stopped_by_her": stopped_by_her,
		"form_reveal": context.handover.reveal_done,
	}


## Score and store the act's summary. The summary service owns the grade and the prose.
func commit_summary(real_act: bool) -> void:
	context.summary.commit_summary(real_act, context.summary.summary_context(summary_values()))


## Store the strongest clean act per mare. The history system owns the eligibility and the text.
func record_peak_memory() -> void:
	context.summary.record_peak_memory({
		"pony_id": pony_id,
		"event_id": event_id,
		"satisfaction": context.readiness.peak_satisfaction,
		"both_matches": context.readiness.act_both_matches,
		"dislikes": context.readiness.act_dislikes,
		"liked_touch": context.readiness.act_liked_touch,
		"liked_talk": context.readiness.act_liked_talk,
		"player_talk": context.readiness.last_player_talk,
		"her_at": context.dialogue.last_spoken_at(),
		"her_line": context.dialogue.last_spoken_line(),
	}, act_spoken_at)


## The live act values the rejoin decisions need, read fresh on every check.
func rest_context() -> Dictionary:
	return {
		"serial": serial,
		"state": state,
		"player_pony": player_pony,
		"headset": WORLD.headset_view(),
		"summary": context.summary.summary,
		"satisfaction": context.readiness.satisfaction,
		"aftercare_min": aftercare_min,
	}


## Bind the face owner to the presented body once; every act beat and face write goes through it.
func bind_face() -> void:
	_face()


func _face() -> void:
	context.face.ensure_bound(host.pony, host.node)


## One warning, close or act moment. The session gathers the act values; the face owner applies
## the beat table.
func face_beat(moment: String) -> void:
	_face()
	var ctx := {
		"first_time": first_time,
		"tolerance": str(preferences.get("tolerance", "normal")),
	}
	if moment == "climax":
		ctx["climax_mode"] = climax_mode
		ctx["quality"] = climax_quality_inputs()
	elif moment == "afterglow":
		ctx["summary"] = context.summary.summary
	context.face.act_beat(moment, ctx, feature("face_debug"))


## The act's smile and lids with an optional hold; the face owner owns the timer.
func set_face(smile: float, lids: float, hold_seconds := 0.0) -> void:
	_face()
	context.face.set_face(smile, lids, hold_seconds)


## Clear the act's smile and lids.
func clear_face() -> void:
	_face()
	context.face.clear_face()


## The act owns the lids outside a kiss. Set at every transition, then reasserted late so a
## climax return or fluster peek cannot leave her wide-eyed while leaning.
func eyes_tick() -> void:
	_face()
	context.face.eyes_tick({
		"state": state,
		"close_rewarded": context.afterglow.close_rewarded,
		"eyes_active": context.kiss.eyes_active(),
	})


## The act's phase name for the face table.
func act_phase() -> String:
	match state:
		State.POSING_IN:
			return "posing_in"
		State.ACTIVE:
			return "active"
		State.CLIMAX:
			return "climax"
		State.AFTERGLOW:
			return "afterglow"
	return ""


## Live presentation score for the auto climax face; it never writes the summary or history.
func climax_quality_inputs() -> Dictionary:
	_face()
	return context.face.climax_quality({
		"intensity_total": context.readiness.act_intensity_total,
		"intensity_right": context.readiness.act_intensity_right,
		"pattern_total": context.readiness.act_pattern_total,
		"pattern_right": context.readiness.act_pattern_right,
		"both_matches": context.readiness.act_both_matches,
		"liked_touch": context.readiness.act_liked_touch,
		"liked_talk": context.readiness.act_liked_talk,
		"touch_dislikes": context.readiness.act_touch_dislikes,
		"talk_dislikes": context.readiness.act_talk_dislikes,
		"distress": context.readiness.distress(),
		"preferences": preferences,
		"overwhelmed": context.readiness.overwhelmed > 0.0,
	})


func set_act_face(face_id: String, hold_s: float) -> bool:
	_face()
	context.face.debug_enabled = feature("face_debug")
	return context.face.set_act_face(face_id, hold_s)


func end_act_face() -> void:
	_face()
	context.face.debug_enabled = feature("face_debug")
	context.face.end_face()


func sync_act_face_settings() -> void:
	_face()
	context.face.sync_settings(feature("face_debug"))


## Debug preview: set one base-game face on the current act. A speaking line still wins.
func force_act_face(face_id: String) -> bool:
	_face()
	context.face.debug_enabled = feature("face_debug")
	return context.face.force_face(face_id)


## Debug view for the "Show act face" action.
func act_face_rows() -> Array[String]:
	_face()
	var base_mood := ""
	if is_instance_valid(WORLD.game) and not pony_id.is_empty():
		var facts: MEMORY.CueFacts = MEMORY.instance.cue_facts(pony_id, event_id)
		base_mood = facts.mood
	return context.face.rows({
		"state": state,
		"hud_mood": context.readiness.mood,
		"base_mood": base_mood,
		"climax_mode": climax_mode,
		"blush_arc": feature("blush_arc"),
	})


func start_upset(mood_value: String) -> void:
	_face()
	context.face.start_upset(mood_value)


func end_upset() -> void:
	_face()
	context.face.end_upset()


## The pose frame the live family reads: the bed frame or the ground frame.
func sync_pose_frame() -> void:
	if pose_family() == "bed":
		context.pose.sync_bed_frame()
	else:
		context.pose.sync_ground_frame()


## The render-time pose write, with the camera's eye mode and the live body scale.
func pose_render_write() -> void:
	var body_scale: Variant = host.pony.get("body_scale") if is_instance_valid(host.pony) else null
	context.pose.render_write({
		"bed_frame": context.pose.bed_frame,
		"body_scale": float(body_scale) if body_scale != null else 1.0,
		"size_name": context.facts.size_name,
		"eye_camera_active": context.camera.free_camera_active and eye_camera_mode,
	})


## Dispatch the act shot through the camera facade. The facts are refreshed first so the shot
## reads this frame's lean and look.
func apply_camera_motion() -> void:
	if context.handover != null and context.handover.suspended:
		return
	refresh_view()
	sync_hud()
	if context.camera.motion_ready():
		context.camera.apply_motion()


## The start's one talk-turn reset: readiness and the handover keep their own last-turn state.
func remember_talk_turn() -> void:
	var director: Node = _director()
	context.readiness.remember_talk_turn(director)
	context.handover.remember_talk_turn(director)


func _director() -> Node:
	var tree: SceneTree = host.tree()
	return tree.get_first_node_in_group("conversation_director") if tree != null else null


## The oral edge's speech stop: her authored line, the shared director turn and her own voice end
## once when the edge starts. The mouth shape follows through the separate viseme event.
func oral_speech_stop() -> void:
	context.dialogue.end_act(event_id, false)
	stop_oral_turn()
	stop_speech()


## Interrupt the shared director only when it is driving this mare, so a bystander's turn is not
## cut by her mouth being busy.
func stop_oral_turn() -> void:
	var director: Node = _director()
	if director == null or not director.has_method("interrupt"):
		return
	if str(director.get("state")) == "idle":
		return
	if str(director.get("_current")) != pony_id:
		return
	director.call("interrupt")


## Stop her own voice. `stop_speaking()` restores the rest viseme, so the oral turn re-asserts its
## mouth shape; the turn is the only owner of the open mouth.
func stop_speech() -> void:
	if not is_instance_valid(host.pony):
		return
	if host.pony.has_method("is_speaking") and bool(host.pony.call("is_speaking")):
		if host.pony.has_method("stop_speaking"):
			host.pony.call("stop_speaking")
		context.anatomy.hold_oral_mouth()


## The `oral` command: request the standing oral pose, or the return edge when it is already
## active. The per-mare consent string is passed only when the anatomy service says yes; the
## feature is checked by the edge requirements, not here.
func toggle_anatomy_oral() -> void:
	var live: Variant = context.pose.view()
	var from_id := str(live.id) if live != null else ""
	var target := CATALOG.STANDING_ORAL if from_id == CATALOG.STANDING else CATALOG.STANDING
	var request := {}
	var consent := false
	var service: Variant = PONIES.anatomy
	if service != null and service.has_method("consent") and target == CATALOG.STANDING_ORAL:
		consent = bool(service.call("consent", host.pony, "oral"))
		if consent:
			request["consent"] = "oral"
	var result: Dictionary = context.pose.request_pose(target, "oral", _pose_request(request))
	if bool(result.get("ok", false)):
		host.log("oral pose %s -> %s: ok" % [from_id, target])
		return
	host.log("oral pose %s -> %s refused: %s (%s)" % [
		from_id, target, str(result.get("code", "")), str(result.get("reason", ""))])
	if target == CATALOG.STANDING_ORAL and not consent:
		oral_status("%s is not into that" % display_name)
	elif service != null:
		oral_status(str(result.get("reason", "")))


func _pose_request(extra: Dictionary) -> Dictionary:
	var request := extra.duplicate()
	if not request.has("act_state"):
		request["act_state"] = state
	if not request.has("features"):
		request["features"] = features
	return request


## The oral refusal line through the pose service's host callback, or the anatomy status when the
## callback is absent.
func oral_status(text: String) -> void:
	var pose_session: Variant = context.pose
	if pose_session != null and pose_session.oral_status.is_valid():
		pose_session.oral_status.call(text)
	else:
		anatomy_status(text)


func toggle_anatomy_hole() -> void:
	context.anatomy.bind(context.anatomy_host)
	context.anatomy.toggle_hole()


func anatomy_status(text: String, seconds := 2.0) -> void:
	context.anatomy.bind(context.anatomy_host)
	context.anatomy.status(text, seconds)


## The live act values the debug status line reads. The debug pony helper owns the scene gather;
## the act's session values are the act's own.
func debug_context() -> Dictionary:
	return DEBUG_PONY.context(host.pony, pony_id, {
		"state": state,
		"presenting": context.presentation.presentation_active(),
		"cuddle": context.gate.cuddle_active(),
		"max_pony_climaxes": max_pony_climaxes,
		"satisfaction": context.readiness.satisfaction,
		"pony_climaxes": context.readiness.pony_climaxes,
		"last_intensity": context.readiness.last_intensity,
		"last_pattern": context.readiness.last_pattern,
		"cue": context.readiness.cue,
		"thrust_up": context.readiness.up_is_deep,
		"penetration_m": context.readiness.penetration_m,
		"penetration_reach": context.readiness.reach(),
		"preferences": PREFERENCES.describe(preferences),
		"voice_status_line": context.audio.voice_status_line(pony_id),
	})


## Live context for the normal dialogue prompt. The entry node joins the game's
## `pony_prompt_notes` group and forwards to the active runtime for that pony.
func prompt_note() -> String:
	refresh_identity()
	var form: Variant = context.handover.form()
	return context.dialogue.prompt_note({
		"state": state,
		"warm": context.face.warm_note,
		"history": _history_note(),
		"beat": context.afterglow.beat,
		"relation": _relationship_note(),
		"caressing": context.hands.any_active(),
		"leaning": context.camera.lean_forward >= 0.35 or context.camera.lean_action_active \
			or context.kiss.leaning_close(),
		"missionary": pose_family() == "bed",
		"form_source": context.handover.source() != null,
		"form_name": form.form_name.strip_edges() if form != null else "",
		"form_borrowed": form != null and not form.is_own(),
	})


func _history_note() -> String:
	var row := ACT_HISTORY.effective_row(ACT_HISTORY.section(), pony_id, ACT_HISTORY.day_now())
	return ACT_HISTORY.prompt_note(row)


## Short private relationship facts for normal dialogue. Empty outside a relationship runtime.
func _relationship_note() -> String:
	if not is_instance_valid(WORLD.game):
		return ""
	refresh_identity()
	return RELATIONSHIP_CUE.note(MEMORY.instance.cue_facts(pony_id, event_id).to_dict())


## The after-act summary and the peak record, in one place.
func commit_afterglow() -> void:
	if not is_instance_valid(WORLD.game):
		return
	commit_summary(true)
	record_peak_memory()
	for row: MEMORY.Witness in MEMORY.instance.witnesses(pony_id, display_name, serial, host.pony):
		host.log("witness " + str(row.to_dict()))


## Both poses share the held afterglow; standing adds the close window and a slightly lifted tail.
func begin_afterglow() -> void:
	host.log("afterglow pose=%s pony=%s" % [pose_id, str(host.pony.name)])
	context.readiness.stop_auto()
	context.dialogue.end_act(event_id, true)
	# Bed afterglow keeps only lean and caress; standing keeps its kiss.
	if pose_family() != "standing":
		context.kiss.end_lean_kiss()
	commit_afterglow()
	enter_afterglow()
	context.handover.hint_tick()
	context.handover.dispatch_event(BODY_CHANGE_POLICY.ActEvent.AFTERGLOW)
	refresh_view()
	# The oral afterglow releases the mouth contact and keeps the turned pose. The pose row's
	# afterglow profile is passive, so no standing close window opens.
	context.pose.release_mouth_contact()
	context.integrations.afterglow()
	context.afterglow.bind_view(context.pose.view())
	context.afterglow.begin(context.summary.summary)
	context.readiness.cue = ""
	context.readiness.cue_override = ""
	context.readiness.cue_until = 0.0
	context.face.stare_release_until = 0.0
	set_face(0.85, FACE.AFTERGLOW_LIDS)
	face_beat("afterglow")
	apply_afterglow_presentation(context.afterglow.presentation())


## Apply the afterglow facade's presentation row in the built order: the pose weight, the tail,
## the HUD state, then the wings. The evaluator keeps its current pair, so the pose holds.
func apply_afterglow_presentation(row: Dictionary) -> void:
	if is_instance_valid(context.pose.pose()):
		context.pose.pose().target_amount = 1.0
		context.pose.pose().amount = 1.0
	context.pose.set_tail_target(float(row.get("tail_target", 0.35)))
	var flicks := int(row.get("tail_flicks", 0))
	if flicks > 0:
		context.pose.flick_tail(flicks)
	if is_instance_valid(HUD.instance):
		HUD.instance.set_state(str(row.get("hud_state", "AFTERGLOW")))
	if bool(row.get("wings", false)):
		context.wings.begin_afterglow()


## The standing close window elapsed. The facade decided the reward; the act presents it.
func on_stay_close(caressed: bool, reward: bool) -> void:
	if is_instance_valid(WORLD.game):
		var impression := MEMORY.Impression.new()
		impression.id = pony_id
		impression.event_id = event_id
		impression.slot = MEMORY.ImpressionSlot.STAY_CLOSE
		impression.mood = "happy" if reward else ""
		impression.romance = 1 if reward and caressed else 0
		MEMORY.instance.commit(impression)
	if not reward and caressed:
		if ACT_HISTORY.repair(ACT_HISTORY.section(), pony_id, 1, ACT_HISTORY.day_now()):
			ACT_HISTORY.save()
	set_face(0.9, FACE.AFTERGLOW_CLOSE_LIDS)
	context.reactions.hearts_burst()
	context.readiness.cue = ""


## The pony climax: one state transition and its presentation. The readiness meter decides when;
## this owner applies the act moment.
func climax() -> void:
	if state != State.ACTIVE:
		return
	context.readiness.pony_climaxes += 1
	host.log("pony climax=%d pose=%s pony=%s readiness=%.0f" % [
		context.readiness.pony_climaxes, str(start_row().get("id", "")),
		str(host.pony.name), context.readiness.satisfaction])
	enter_climax()
	context.readiness.mood = "climax"
	context.readiness.cue = "She is climaxing."
	context.readiness.set_cue_override("She is climaxing.", CLIMAX_SECONDS)
	context.handover.hint_tick()
	context.reactions.schedule_hearts()
	context.reactions.hearts_burst_at(context.reactions.dock_point())
	set_face(0.3, FACE.CLIMAX_LIDS)
	face_beat("climax")
	context.dialogue.end_act(event_id, true)
	if is_instance_valid(WORLD.game) and context.readiness.pony_climaxes == 1:
		MEMORY.instance.note(MEMORY.NoteKind.CLIMAXED, pony_id, event_id)
	queue_climax_reaction()
	context.audio.play_climax()
	# integration: her fluid hook.
	context.anatomy.on_climax()
	if is_instance_valid(HUD.instance):
		HUD.instance.set_state("CLIMAX")


## One generated climax line, or none when her mouth is busy or the roll is silent.
func queue_climax_reaction() -> void:
	var live: Variant = context.pose.view()
	if live != null and str(live.contact_kind) == "mouth":
		return
	if not is_instance_valid(WORLD.game):
		return
	var act_id := event_id
	var count := context.readiness.pony_climaxes
	var climax_id := "%s:pony_climax:%d" % [act_id, count]
	var expires := clock_s() + snapshot.cue_reaction_max_age_s
	var valid := func() -> bool:
		if not is_instance_valid(host.pony) or event_id != act_id \
				or context.readiness.pony_climaxes != count:
			return false
		if clock_s() <= expires:
			return true
		return MEMORY.instance.line_state(climax_reaction_key) == MEMORY.LineState.SPEAKING
	var key: String = context.dialogue.reaction_line(MEMORY.Reaction.CLIMAX, climax_id,
		"You have just climaxed. Say one short sentence, at most 12 words, in your own voice. Begin with [surprised], [happy] or [calm]. Staying quiet is fine.", valid)
	climax_reaction_key = key
	if key.is_empty():
		return
	context.dialogue.note_reaction(key, context.readiness.cue,
		clock_s() + snapshot.cue_reaction_max_age_s)
	host.log("utterance kind=reaction key=%s" % key)


## The first ACTIVE entry after the pose settles. Later returns from a climax are CLIMAX_END.
func enter_active_act() -> void:
	enter_active()
	context.handover.dispatch_event(BODY_CHANGE_POLICY.ActEvent.ACTIVE)


## The pony climax ends on its own. It returns to ACTIVE unless the configured limit was reached;
## afterglow is the player's choice, not the climax state's automatic exit.
func finish_climax() -> void:
	context.handover.dispatch_event(BODY_CHANGE_POLICY.ActEvent.CLIMAX_END)
	if max_pony_climaxes > 0 and context.readiness.pony_climaxes >= max_pony_climaxes:
		begin_afterglow()
		return
	enter_active()
	context.face.stare_release_until = 0.0
	set_face(0.45, FACE.ACT_LIDS)
	context.readiness.satisfaction = 0.0
	context.readiness.mood = "warming"
	context.readiness.cue = ""
	context.handover.hint_tick()
	context.readiness.cue_override = ""
	context.readiness.cue_until = 0.0
	context.readiness.overwhelmed = 0.0
	context.readiness.last_intensity = ""
	context.readiness.last_pattern = ""
	context.readiness.stroke_window.clear()
	context.readiness.last_stroke_at = -1000.0
	context.readiness.last_thrust_score_at = -1000.0
	context.readiness.receptive_until = 0.0
	var limit_text := "∞" if max_pony_climaxes <= 0 else str(max_pony_climaxes)
	host.log("pony climax end=%d/%s readiness=0" % [context.readiness.pony_climaxes, limit_text])
