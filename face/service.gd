extends RefCounted
## The act's single face owner: the beat table, the line-face rule and the held post-act face.
## Scene values arrive from the runtime; this facade never reads its node.
##
## Contract: `docs/face.md`.

const ACT_FACE := preload("res://mods/unfplap/shared/act_face.gd")
const MOOD_FACE := preload("res://mods/unfplap/face/mood_face.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const READINESS := preload("res://mods/unfplap/readiness/service.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")

## The act values one face moment reads. The session fills one instance per pony; this facade
## owns the beat table and the shape it is given.
class ActValues extends RefCounted:
	var state := 0
	var pony_id := ""
	var event_id := ""
	var first_time := false
	var tolerance := "normal"
	var climax_mode := ""
	var summary: Dictionary = {}
	var blush_arc := false

## The live climax shape's inputs. The readiness meter owns the counters; this facade owns the
## shape `shared/act_face.gd` reads. Presentation only: it never writes the summary or history.
class ActQuality extends RefCounted:
	var intensity_total := 0.0
	var intensity_right := 0.0
	var pattern_total := 0.0
	var pattern_right := 0.0
	var both_matches := 0.0
	var liked_touch := 0.0
	var liked_talk := 0.0
	var dislikes_total := 0
	var distress := 0.0
	var seeks_touch := false
	var seeks_talk := false
	var overwhelmed := false

## The act's eyelid values, applied outside a kiss. Afterglow reads the close variant when the
## close window was rewarded.
const ACT_LIDS := 0.45
const CLIMAX_LIDS := 0.0
const AFTERGLOW_LIDS := 0.9
const AFTERGLOW_CLOSE_LIDS := 0.95
## The act states the lids answer. The runtime owns the enum; these are its values.
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const STATE_POSING_IN := ACT_STATE.State.POSING_IN
const STATE_ACTIVE := ACT_STATE.State.ACTIVE
const STATE_CLIMAX := ACT_STATE.State.CLIMAX
const STATE_AFTERGLOW := ACT_STATE.State.AFTERGLOW
const LOG := preload("res://mods/unfplap/shared/log.gd")

## The face the act set. A spoken line face always wins until it ends.
var act_face := ""
## While this clock is in the future the act releases the stare (a warm climax or the kiss).
var stare_release_until := 0.0
## True while the act's own stare is released, so a reassert happens only once per release.
var act_eyes_released := false
## The held post-act face node, or null.
var mood_face: Node = null
## The hold timer behind `set_face()`, parented to the host and freed by `shutdown()`.
var face_timer: Timer = null
## The warm prompt note that goes with a positive post-act face.
var warm_note := false
## Mirrors `features.face_debug` for the facade's own logs.
var debug_enabled := false
var pony: Variant = null
## The node the mood face and its hold timer are parented under.
var host: Node = null

var clock := Callable()


## Bind the pony and the runtime host once the runtime is ready.
func bind(pony_in: Variant, host_in: Node) -> void:
	pony = pony_in
	host = host_in


## Bind the act's presented body once; every call site can ask instead of holding the rule. A suite
## that builds a face without entering the tree binds it on its first call this way.
func ensure_bound(pony_in: Node, host_in: Node) -> void:
	if pony != pony_in or host != host_in:
		bind(pony_in, host_in)


## The act's smile and lids, with an optional hold that clears it again. The timer is created on
## the first call and parented to the host, so a facade built without a tree simply skips the hold.
func set_face(smile: float, lids: float, hold_seconds := 0.0) -> void:
	if not is_instance_valid(pony):
		return
	var expressions: Variant = pony.get("expressions")
	if expressions == null:
		return
	if expressions.has_method("touch"):
		expressions.call("touch", "unfplap_state", smile, 0.0)
	if expressions.has_method("stare"):
		expressions.call("stare", true, lids)
	if hold_seconds > 0.0:
		var timer := _timer()
		if is_instance_valid(timer):
			timer.start(hold_seconds)


## Clear the act's smile and lids. A held timer is stopped first.
func clear_face() -> void:
	if is_instance_valid(face_timer):
		face_timer.stop()
	if not is_instance_valid(pony):
		return
	var expressions: Variant = pony.get("expressions")
	if expressions == null:
		return
	if expressions.has_method("stare"):
		expressions.call("stare", false)
	if expressions.has_method("release_touch"):
		expressions.call("release_touch", "unfplap_state")


## The act's lids from the session's typed values; the runtime sets them at every transition and
## calls this late in the tick.
func eyes_for(state_value: int, close_rewarded: bool, eyes_active: bool) -> void:
	eyes_tick({"state": state_value, "close_rewarded": close_rewarded,
		"eyes_active": eyes_active})


## Outside a kiss the act owns the lids, reasserted on every tick.
func eyes_tick(context: Dictionary) -> void:
	if not is_instance_valid(pony):
		return
	var expressions: Variant = pony.get("expressions")
	if expressions == null:
		return
	if bool(context.get("eyes_active", false)) or _now() < stare_release_until:
		if not act_eyes_released:
			if expressions.has_method("stare"):
				expressions.call("stare", false)
			act_eyes_released = true
		return
	act_eyes_released = false
	var lids := -1.0
	match int(context.get("state", 0)):
		STATE_POSING_IN, STATE_ACTIVE:
			lids = ACT_LIDS
		STATE_CLIMAX:
			lids = CLIMAX_LIDS
		STATE_AFTERGLOW:
			lids = AFTERGLOW_CLOSE_LIDS if bool(context.get("close_rewarded", false)) \
				else AFTERGLOW_LIDS
	if lids < 0.0:
		return
	if expressions.has_method("stare"):
		expressions.call("stare", true, lids)


## One act moment, with the debug flag applied before the beat table runs. The runtime gathers the
## act values in `context`; the facade owns the beat table.
func act_beat(moment: String, context: Dictionary, debug: bool) -> void:
	debug_enabled = debug
	beat(moment, context)


## One act moment from the session's typed act values. The facade gathers the climax shape from
## the meter and owns the beat table; the session keeps only its own values.
func act_beat_for(moment: String, values: ActValues, readiness: READINESS, debug: bool) -> void:
	var context := {
		"first_time": values.first_time,
		"tolerance": values.tolerance,
	}
	if moment == "climax":
		context["climax_mode"] = values.climax_mode
		context["quality"] = _quality_dict(quality_for(readiness))
	elif moment == "afterglow":
		context["summary"] = values.summary
	act_beat(moment, context, debug)


## The live climax shape's inputs, gathered from the readiness meter.
func quality_for(readiness: READINESS) -> ActQuality:
	var values := ActQuality.new()
	var touch_dislikes := 0
	for count: Variant in readiness.act_touch_dislikes.values():
		touch_dislikes += int(count)
	values.intensity_total = float(readiness.act_intensity_total)
	values.intensity_right = float(readiness.act_intensity_right)
	values.pattern_total = float(readiness.act_pattern_total)
	values.pattern_right = float(readiness.act_pattern_right)
	values.both_matches = float(readiness.act_both_matches)
	values.liked_touch = float(readiness.act_liked_touch)
	values.liked_talk = float(readiness.act_liked_talk)
	values.dislikes_total = touch_dislikes + readiness.act_talk_dislikes
	values.distress = readiness.distress()
	values.seeks_touch = PREFERENCES.seeks_touch(readiness.preferences)
	values.seeks_talk = PREFERENCES.seeks_talk(readiness.preferences)
	values.overwhelmed = readiness.overwhelmed > 0.0
	return values


## The act-face rows for Show data's ACT section. The game's cue mood is read here; the state,
## the HUD mood and the flags come from the session and the meter.
func act_rows(values: ActValues, readiness: READINESS) -> Array[String]:
	var base_mood := ""
	if is_instance_valid(WORLD.game) and not values.pony_id.is_empty():
		base_mood = MEMORY.instance.cue_facts(values.pony_id, values.event_id).mood
	return rows({
		"state": values.state,
		"hud_mood": readiness.mood,
		"base_mood": base_mood,
		"climax_mode": values.climax_mode,
		"blush_arc": values.blush_arc,
	})


## Drop the stare release without touching the act face. A climax return and the afterglow start
## re-assert the lids after it.
func release_stare() -> void:
	stare_release_until = 0.0


func _quality_dict(values: ActQuality) -> Dictionary:
	return {
		"intensity_total": values.intensity_total,
		"intensity_right": values.intensity_right,
		"pattern_total": values.pattern_total,
		"pattern_right": values.pattern_right,
		"both_matches": values.both_matches,
		"liked_touch": values.liked_touch,
		"liked_talk": values.liked_talk,
		"dislikes_total": values.dislikes_total,
		"distress": values.distress,
		"seeks_touch": values.seeks_touch,
		"seeks_talk": values.seeks_talk,
		"overwhelmed": values.overwhelmed,
	}


## Live presentation score for the auto climax face. The runtime gathers its counters; the facade
## owns the shape `shared/act_face.gd` reads. Never writes the summary or the history.
func climax_quality(context: Dictionary) -> Dictionary:
	var touch_dislikes := 0
	var counts: Variant = context.get("touch_dislikes", {})
	if counts is Dictionary:
		for count: Variant in (counts as Dictionary).values():
			touch_dislikes += int(count)
	var preferences: Dictionary = _dict(context.get("preferences"))
	return {
		"intensity_total": float(context.get("intensity_total", 0.0)),
		"intensity_right": float(context.get("intensity_right", 0.0)),
		"pattern_total": float(context.get("pattern_total", 0.0)),
		"pattern_right": float(context.get("pattern_right", 0.0)),
		"both_matches": float(context.get("both_matches", 0.0)),
		"liked_touch": float(context.get("liked_touch", 0.0)),
		"liked_talk": float(context.get("liked_talk", 0.0)),
		"dislikes_total": touch_dislikes + int(context.get("talk_dislikes", 0)),
		"distress": float(context.get("distress", 0.0)),
		"seeks_touch": PREFERENCES.seeks_touch(preferences),
		"seeks_talk": PREFERENCES.seeks_talk(preferences),
		"overwhelmed": bool(context.get("overwhelmed", false)),
	}


## The hold timer, created on first use under the host.
func _timer() -> Timer:
	if is_instance_valid(face_timer):
		return face_timer
	if not _host_ok():
		return null
	face_timer = Timer.new()
	face_timer.name = "UnfplapFaceTimer"
	face_timer.one_shot = true
	face_timer.timeout.connect(clear_face)
	host.add_child(face_timer)
	return face_timer


## One act moment; the runtime gathers its context.
func beat(moment: String, context: Dictionary) -> void:
	if not is_instance_valid(pony):
		return
	var data := {
		"first_time": bool(context.get("first_time", false)),
		"tolerance": str(context.get("tolerance", "normal")),
	}
	if moment == "climax":
		data["mode"] = str(context.get("climax_mode", "auto"))
		data["quality"] = context.get("quality", {})
	elif moment == "afterglow":
		data["summary"] = context.get("summary", {})
	var plan := ACT_FACE.plan_for(moment, data)
	if plan.is_empty():
		return
	var face := str(plan.get("face", ""))
	if face.is_empty():
		if moment in ["climax", "afterglow"]:
			end_face()
		if moment == "climax" and debug_enabled:
			var empty_debug: Dictionary = _dict(plan.get("style_debug"))
			LOG.debug("act face moment=climax style=%s score=%.2f face=wide", [
				str(plan.get("style", "wide")), float(empty_debug.get("score", 0.0))])
		return
	set_act_face(face, float(plan.get("hold_s", 0.0)))
	var fluster_s := float(plan.get("fluster_s", 0.0))
	if fluster_s > 0.0 and is_instance_valid(pony):
		var expressions: Variant = pony.get("expressions")
		if expressions != null and expressions.has_method("fluster"):
			expressions.call("fluster", fluster_s, true)
	if bool(plan.get("release_stare", false)):
		stare_release_until = _now() + float(plan.get("hold_s", 0.0)) + 0.9
	if debug_enabled:
		if moment == "climax":
			var style_data: Dictionary = _dict(plan.get("style_debug"))
			LOG.debug("act face moment=climax style=%s score=%.2f motion=%.2f both=%.2f affection=%.2f engagement=%.2f penalty=%.2f face=%s", [
				str(plan.get("style", "")), float(style_data.get("score", 0.0)),
				float(style_data.get("motion", 0.0)), float(style_data.get("both", 0.0)),
				float(style_data.get("affection", 0.0)),
				float(style_data.get("engagement", 0.0)),
				float(style_data.get("penalty", 0.0)), face])
		else:
			LOG.debug("act face moment=%s face=%s hold=%.1f", [
				moment, face, float(plan.get("hold_s", 0.0))])


## Set one face, or refuse when a line owns the expression; returns whether it applied.
func set_act_face(face: String, hold_s: float) -> bool:
	if not is_instance_valid(pony) or not ACT_FACE.valid_face(face):
		return false
	var expressions: Variant = pony.get("expressions")
	if expressions == null or not is_instance_valid(expressions) \
			or not expressions.has_method("set_dialogue"):
		return false
	var current := dialogue_face()
	if not current.is_empty() and current != act_face:
		if debug_enabled:
			LOG.debug("act face skip face=%s owner=line current=%s", [face, current])
		return false
	expressions.call("set_dialogue", face)
	if hold_s > 0.0 and expressions.has_method("finish_dialogue"):
		expressions.call("finish_dialogue", hold_s)
	act_face = face
	if debug_enabled:
		LOG.debug("act face set face=%s hold=%.1f", [face, hold_s])
	return true


## Drop the act's own face and leave any line face alone.
func end_face() -> void:
	stare_release_until = 0.0
	if act_face.is_empty():
		return
	if is_instance_valid(pony):
		var expressions: Variant = pony.get("expressions")
		if expressions != null and is_instance_valid(expressions) \
				and expressions.has_method("clear_dialogue") \
				and dialogue_face() == act_face:
			expressions.call("clear_dialogue")
			if debug_enabled:
				LOG.debug("act face clear face=%s", [act_face])
	act_face = ""


## The face the director's line holds right now, or empty.
func dialogue_face() -> String:
	if not is_instance_valid(pony):
		return ""
	var expressions: Variant = pony.get("expressions")
	if expressions == null or not is_instance_valid(expressions):
		return ""
	var value: Variant = expressions.get("dialogue_face")
	if value is String:
		return value
	return ""


## Apply the live debug flag; act faces play either way, and the post-act face is independent.
func sync_settings(debug: bool) -> void:
	debug_enabled = debug


## Debug preview: set one base-game face on the current act. A speaking line still wins.
func force_face(face: String) -> bool:
	return set_act_face(face, 3.0)


## Debug view for the "Show act face" action. Context: `state`, `hud_mood`, `base_mood`,
## `climax_mode`, `blush_arc`.
func rows(context: Dictionary) -> Array[String]:
	var result: Array[String] = []
	result.append("pony=%s state=%d hud_mood=%s base_mood=%s" % [
		str(pony.name) if is_instance_valid(pony) else "?", int(context.get("state", 0)),
		str(context.get("hud_mood", "")), str(context.get("base_mood", ""))])
	result.append("act_face=%s dialogue_face=%s stare_release=%.2f" % [
		act_face, dialogue_face(), maxf(0.0, stare_release_until - _now())])
	var fluster := 0.0
	if is_instance_valid(pony):
		var expressions: Variant = pony.get("expressions")
		if expressions != null and is_instance_valid(expressions):
			var value: Variant = expressions.get("fluster_amount")
			if value is float or value is int:
				fluster = float(value)
	result.append("climax_mode=%s blush_arc=%s fluster=%.2f" % [
		str(context.get("climax_mode", "auto")), str(context.get("blush_arc", true)), fluster])
	if is_instance_valid(mood_face):
		var left: Variant = mood_face.get("_left")
		result.append("mood_face face=%s mood=%s left=%.1f warm=%s" % [
			str(mood_face.get("face")), str(mood_face.get("mood")),
			float(left) if left is float or left is int else 0.0, str(warm_note)])
	else:
		result.append("mood_face none warm=%s" % str(warm_note))
	return result


## The post-act face and its warm note. A bad act shows the summary mood instead of a warm face.
func start_post_act(context: Dictionary) -> void:
	warm_note = false
	if bool(context.get("stopped", false)) or not is_instance_valid(pony) or not _host_ok():
		return
	var summary: Dictionary = _dict(context.get("summary"))
	var satisfied := float(context.get("satisfied", 0.0))
	var aftercare_min := float(context.get("aftercare_min", 10.0))
	var face := ""
	var mood := ""
	var blush := 0.0
	var warm := false
	if not summary.is_empty():
		face = ACT_FACE.face_for_summary_hold(summary)
		mood = str(summary.get("mood", ""))
		warm = bool(summary.get("reward", false)) and satisfied >= aftercare_min
		if warm:
			blush = 0.35
	elif satisfied >= aftercare_min:
		face = "relaxed"
		blush = 0.35
		warm = true
	if face.is_empty():
		return
	start_mood_face(mood, face, blush, warm)


## Hold one face for the mood's freshness. The node lives in `face/mood_face.gd`; this facade owns its
## lifetime and the warm-note flag.
func start_mood_face(mood: String, face: String, blush: float, warm_note_value: bool) -> void:
	if not _host_ok() or not is_instance_valid(pony) or face.is_empty():
		return
	if not ACT_FACE.valid_face(face):
		return
	end_mood_face()
	mood_face = MOOD_FACE.new()
	mood_face.name = "UnfplapMoodFace"
	mood_face.set("pony", pony)
	mood_face.set("mood", mood)
	mood_face.set("face", face)
	mood_face.set("blush", blush)
	mood_face.connect("finished", _on_mood_face_finished)
	warm_note = warm_note_value
	host.add_child(mood_face)


func _on_mood_face_finished(_reason: String) -> void:
	mood_face = null
	warm_note = false


func end_mood_face() -> void:
	if is_instance_valid(mood_face):
		if mood_face.is_connected("finished", _on_mood_face_finished):
			mood_face.disconnect("finished", _on_mood_face_finished)
		mood_face.call("_finish", "replaced")
	mood_face = null
	warm_note = false


## A partner stop holds the refusal face instead of the post-act face.
func start_upset(mood: String) -> void:
	start_mood_face(mood, str(ACT_FACE.MOOD_FACES.get(mood, "")), 0.0, false)


## Compatibility names used by the lab and the old call sites.
func end_upset() -> void:
	end_mood_face()


func end_satisfied() -> void:
	end_mood_face()


## Teardown: drop the held face and the act's own face.
func shutdown() -> void:
	end_face()
	if is_instance_valid(mood_face):
		mood_face.queue_free()
	mood_face = null
	if is_instance_valid(face_timer):
		face_timer.queue_free()
	face_timer = null
	act_eyes_released = false
	warm_note = false


func _host_ok() -> bool:
	return is_instance_valid(host) and host.is_inside_tree()


func _dict(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


func _now() -> float:
	return float(clock.call()) if clock.is_valid() else 0.0


