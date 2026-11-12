extends RefCounted
## The act's single face owner: the beat table driven by the pure `act_face.gd`, the line-face
## ownership rule, the stare release, and the held post-act mood face node. The runtime owns the
## scene values (act state, summary, readiness counters, settings flags) and passes them in; this
## facade owns the face state and never reads the runtime node. Contract: `docs/face.md`.

const ACT_FACE := preload("res://mods/unfplap/act_face.gd")
const MOOD_FACE := preload("res://mods/unfplap/mood_face.gd")
const PREFERENCES := preload("res://mods/unfplap/preferences.gd")

## The act's eyelid values, applied outside a kiss. Afterglow reads the close variant when the
## close window was rewarded.
const ACT_LIDS := 0.45
const CLIMAX_LIDS := 0.0
const AFTERGLOW_LIDS := 0.9
const AFTERGLOW_CLOSE_LIDS := 0.95
## The act states the lids answer. The runtime owns the enum; these are its values.
const STATE_POSING_IN := 1
const STATE_ACTIVE := 2
const STATE_CLIMAX := 3
const STATE_AFTERGLOW := 4

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
## The runtime node that parents the mood face and receives its `runtime` field.
var host: Node = null

## Host boundary. Missing callbacks are no-ops.
var log := Callable()
var clock := Callable()


## Bind the pony and the runtime host once the runtime is ready.
func bind(pony_in: Variant, host_in: Node) -> void:
	pony = pony_in
	host = host_in


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


## The act owns the lids outside a kiss. The runtime sets them at every transition and calls this
## late in the tick so a climax return or fluster peek cannot leave her wide-eyed while leaning.
## Context: `state`, `close_rewarded`, `eyes_active`.
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


## One act moment, with the feature gate and the debug flag applied before the beat table runs.
## The runtime gathers the act values in `context`; the facade owns the gate.
func act_beat(moment: String, context: Dictionary, enabled: bool, debug: bool) -> void:
	debug_enabled = debug
	if not enabled:
		return
	beat(moment, context)


## Live presentation score for the auto climax face. The runtime gathers its counters; the facade
## owns the shape `act_face.gd` reads. Never writes the summary or the history.
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


## Apply the beat table for one moment. The context is gathered by the runtime:
## `enabled`, `debug`, `first_time`, `tolerance`, and `climax_mode`/`quality` or `summary`.
func beat(moment: String, context: Dictionary) -> void:
	if not bool(context.get("enabled", true)) or not is_instance_valid(pony):
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
			_write_log("act face moment=climax style=%s score=%.2f face=wide" % [
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
			_write_log("act face moment=climax style=%s score=%.2f motion=%.2f both=%.2f affection=%.2f engagement=%.2f penalty=%.2f face=%s" % [
				str(plan.get("style", "")), float(style_data.get("score", 0.0)),
				float(style_data.get("motion", 0.0)), float(style_data.get("both", 0.0)),
				float(style_data.get("affection", 0.0)),
				float(style_data.get("engagement", 0.0)),
				float(style_data.get("penalty", 0.0)), face])
		else:
			_write_log("act face moment=%s face=%s hold=%.1f" % [
				moment, face, float(plan.get("hold_s", 0.0))])


## Set one face unless a spoken line owns the expression. Returns whether it applied.
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
			_write_log("act face skip face=%s owner=line current=%s" % [face, current])
		return false
	expressions.call("set_dialogue", face)
	if hold_s > 0.0 and expressions.has_method("finish_dialogue"):
		expressions.call("finish_dialogue", hold_s)
	act_face = face
	if debug_enabled:
		_write_log("act face set face=%s hold=%.1f" % [face, hold_s])
	return true


## Clear only the face this owner set; a spoken line face is never cleared here.
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
				_write_log("act face clear face=%s" % act_face)
	act_face = ""


## The face a director line currently owns, or empty.
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


## The live settings gate. Turning act faces off ends the act's own face; the post-act mood face
## stays independent.
func sync_settings(enabled: bool, debug: bool) -> void:
	debug_enabled = debug
	if not enabled:
		end_face()


## Debug preview: set one base-game face on the current act. A speaking line still wins.
func force_face(face: String) -> bool:
	return set_act_face(face, 3.0)


## Debug view for the "Show act face" action. Context: `state`, `hud_mood`, `base_mood`,
## `act_faces`, `climax_mode`, `blush_arc`.
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
	result.append("act_faces=%s climax_mode=%s blush_arc=%s fluster=%.2f" % [
		str(context.get("act_faces", true)), str(context.get("climax_mode", "auto")),
		str(context.get("blush_arc", true)), fluster])
	if is_instance_valid(mood_face):
		var left: Variant = mood_face.get("_left")
		result.append("mood_face face=%s mood=%s left=%.1f warm=%s" % [
			str(mood_face.get("face")), str(mood_face.get("mood")),
			float(left) if left is float or left is int else 0.0, str(warm_note)])
	else:
		result.append("mood_face none warm=%s" % str(warm_note))
	return result


## The post-act face. A positive or non-early neutral act keeps a light, relaxed face and the warm
## prompt note; a bad act shows its summary mood instead. Context: `stopped`, `summary`,
## `satisfied`, `aftercare_min`.
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


## Hold one face for the mood's freshness. The node lives in `mood_face.gd`; this facade owns its
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
	mood_face.set("runtime", host)
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


## Free the held face and clear the act face when the runtime leaves the tree.
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


func _write_log(text: String) -> void:
	if log.is_valid():
		log.call(text)
