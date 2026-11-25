extends Node
## Scope: pony
## The act's readiness loop: the measured stroke, her satisfaction, mood and cue, the climax count,
## the touch and talk input and the neglect-tolerance meter. It owns one act's state and nothing
## after it; the score, the history and the impression are `summary`'s, the automatic stroke is
## `auto_thrust`'s.

const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const UTTERANCE_SCHEDULER := preload("res://mods/unfplap/dialogue/utterance_scheduler.gd")
const TOLERANCE := preload("res://mods/unfplap/readiness/tolerance.gd")
const THRUST_STATE := preload("res://mods/unfplap/readiness/thrust_state.gd")
const ACT_METER := preload("res://mods/unfplap/shared/act_meter.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const READINESS_MAX := 100.0
const PONY_CLIMAX_AT := READINESS_MAX
const THRUST_HEAT_BOTH := 1.4
const THRUST_HEAT_ONE := 0.7
const THRUST_HEAT_NONE := 0.0
const HEAT_READINESS := 1.6
const RECEPTIVE_BOOST := 1.25
const THRUST_SCORE_MIN_INTERVAL := 0.2
const ASSIST_CAP := 60.0
const TOUCH_HEAT := 6.0
const TALK_HEAT := 6.0
const STROKE_MEMORY_S := 1.2
## The run-down after the act lasts this long; the phase and the HUD read the falling value
## meanwhile.
const DRAIN_SECONDS := 30.0
## The act's own phases: before the pose settles, the scoring window, her climax and the end.
const PHASE_IDLE := 0
const PHASE_STARTED := 1
const PHASE_ACTIVE := 2
const PHASE_CLIMAX := 3
const PHASE_ENDED := 4

## Full readiness while the act is active, emitted at the end of the call that filled the meter.
signal climaxed()
## The close threshold was crossed, once per act.
signal close_reached()
## A disliked touch or talk landed; she is overwhelmed now.
signal overwhelmed()
## The cue changed; `override` is a reaction line rather than the asking base cue.
signal cue_changed(mood: String, text: String, override: bool)
## Her patience moved; a stop is the only decision the act acts on.
signal tolerance(warning: int, stop: bool, distress: float, kind: String)
## A stroke closed on an idle frame and needs the same fan-out as an input one; the depth did not
## change, so there is no withdrawal slide.
signal strokes(events: Array[THRUST_STATE.StrokeEvent])


## The act's own live reads, taken at use. Nothing else is handed in.
class Deps extends RefCounted:
	func _init(shaft_in: Callable, pose_family_in: Callable, in_heat_in: Callable) -> void:
		shaft = shaft_in
		pose_family = pose_family_in
		in_heat = in_heat_in

	## His visible shaft length in metres, 0 when no body is showing.
	var shaft: Callable
	## The live pose family, for the nominal length when he is not showing.
	var pose_family: Callable
	## Whether she is in heat right now.
	var in_heat: Callable


## One act's live state. The service writes this one instance in place and every caller reads it; it
## is never allocated per frame and no other writer exists.
class Readout extends RefCounted:
	var satisfaction := 0.0
	## Warming is where an act starts; a fresh readout never shows an empty mood to the HUD.
	var mood := "warming"
	var cue := ""
	var cue_override := false
	var overwhelmed := false
	var climaxes := 0
	var distress := 0.0
	var last_dislike := ""
	var seeks_touch := false
	var seeks_talk := false
	var last_intensity := ""
	var last_pattern := ""
	var last_touch := ""
	var last_talk := ""
	## The tracker depth as a share of his reach.
	var depth := 0.0
	## The physical penetration in metres, derived from the share and the reach.
	var penetration_m := 0.0
	var up_is_deep := false
	## The configured stroke travel, a share of the reach.
	var travel := 0.0
	var reach_m := 0.0
	var shaft_m := 0.0
	## The physical strength at the last sample, for the impact and the foley.
	var strength := 0.0
	## Impacts in the live one-second window.
	var rate := 0.0
	## Seconds since the last real inward stroke; the kissing integration's activity gate reads it.
	var seconds_since_stroke := 0.0


## The per-mare preference profile the meter reads for the act. A caller shapes it from her stored
## document before the act starts; the meter never re-reads it during the act.
class Profile extends RefCounted:
	var intensity := "firm"
	var pattern := "steady"
	var warmth := "normal"
	var tolerance := "normal"
	var touch: Array[String] = []
	var talk: Array[String] = []
	var dislikes: Array[String] = []

	## The edge: the player's saved preferences merged over the template arrive as a dictionary.
	static func from_dict(raw: Dictionary) -> Profile:
		var out := Profile.new()
		out.intensity = str(raw.get("intensity", "firm"))
		out.pattern = str(raw.get("pattern", "steady"))
		out.warmth = str(raw.get("warmth", "normal"))
		out.tolerance = str(raw.get("tolerance", "normal"))
		out.touch = _names(raw.get("touch", []))
		out.talk = _names(raw.get("talk", []))
		out.dislikes = _names(raw.get("dislikes", []))
		return out

	## The dictionary the pure preference and cue modules take.
	func to_dict() -> Dictionary:
		return {
			"intensity": intensity, "pattern": pattern, "warmth": warmth,
			"tolerance": tolerance, "touch": touch.duplicate(), "talk": talk.duplicate(),
			"dislikes": dislikes.duplicate(),
		}

	static func _names(value: Variant) -> Array[String]:
		var out: Array[String] = []
		if not value is Array:
			return out
		for item: Variant in value:
			out.append(str(item))
		return out


## The one readout instance; it survives every act and is reset, never replaced.
var _readout := Readout.new()
## The act's live reads, wired once by the runtime composition.
var _deps: Deps = null
var _profile := Profile.new()
var _preferences: Dictionary = {}
var _phase := PHASE_IDLE
## The service's own clock, advanced by its tick: the stroke tracker and the cue age read it.
var _clock := 0.0
var _drain_rate := 0.0
var _peak_satisfaction := 0.0
var _overwhelmed_left := 0.0
var _receptive_until := 0.0
var _cue_until := 0.0
var _last_stroke_at := -1000.0
var _last_thrust_score_at := -1000.0
var _last_touch_at := -1000.0
var _last_talk_at := -1000.0
var _close_notified := false
var _climax_signalled := false
## The cue the act last heard; the readout is written ahead of it by a direct cue.
var _published_mood := ""
var _published_text := ""
var _published_override := false
var _last_stroke: Dictionary = {}
var _stroke_window: Array[Dictionary] = []
var _impacts: Array[float] = []
var _tolerance: TOLERANCE = null
var _touch_counts: Dictionary = {}
var _touch_dislikes: Dictionary = {}
var _act_thrusts := 0
var _act_both_matches := 0
var _act_dislikes := 0
var _act_liked_touch := 0
var _act_liked_talk := 0
var _act_talk_dislikes := 0
var _act_player_lines := 0
var _act_intensity_total := 0
var _act_intensity_right := 0
var _act_pattern_total := 0
var _act_pattern_right := 0
var _last_player_talk := ""
## The act's stroke and penetration state. Its tracker is the only stroke authority; the mouse,
## auto thrust and the anatomy bridge all feed this one object.
var _thrust: THRUST_STATE = THRUST_STATE.new()


## Hand the service the act's live reads; the runtime composition is the only caller.
func wire(deps: Deps) -> void:
	_deps = deps
	_thrust.shaft_length = deps.shaft
	_thrust.pose_family = deps.pose_family


## The act's start: her profile for this act, a fresh meter, the tracker at rest. No scoring yet;
## the tolerance meter runs from here.
func start_act(profile: Profile) -> void:
	_profile = profile
	_preferences = _profile.to_dict()
	_phase = PHASE_STARTED
	_clock = 0.0
	_readout.satisfaction = 0.0
	_readout.mood = "warming"
	_readout.cue = ""
	_readout.cue_override = false
	_readout.overwhelmed = false
	_readout.climaxes = 0
	_readout.distress = 0.0
	_readout.last_dislike = ""
	_readout.seeks_touch = PREFERENCES.seeks_touch(_preferences)
	_readout.seeks_talk = PREFERENCES.seeks_talk(_preferences)
	_readout.last_intensity = ""
	_readout.last_pattern = ""
	_readout.last_touch = ""
	_readout.last_talk = ""
	_readout.strength = 0.0
	_readout.rate = 0.0
	_readout.seconds_since_stroke = 0.0
	_peak_satisfaction = 0.0
	_drain_rate = 0.0
	_overwhelmed_left = 0.0
	_receptive_until = 0.0
	_cue_until = 0.0
	_last_stroke_at = -1000.0
	_last_thrust_score_at = -1000.0
	_last_touch_at = -1000.0
	_last_talk_at = -1000.0
	_close_notified = false
	_climax_signalled = false
	_published_mood = ""
	_published_text = ""
	_published_override = false
	_last_stroke.clear()
	_stroke_window.clear()
	_impacts.clear()
	_touch_counts.clear()
	_touch_dislikes.clear()
	_act_thrusts = 0
	_act_both_matches = 0
	_act_dislikes = 0
	_act_liked_touch = 0
	_act_liked_talk = 0
	_act_talk_dislikes = 0
	_act_player_lines = 0
	_act_intensity_total = 0
	_act_intensity_right = 0
	_act_pattern_total = 0
	_act_pattern_right = 0
	_last_player_talk = ""
	_tolerance_controller().reset(_profile.tolerance)
	_thrust.reset()
	_sync_scale()


## The pose settled; the scoring window opens.
func activate() -> void:
	if _phase == PHASE_STARTED:
		_phase = PHASE_ACTIVE


## His hand moved by this share of his reach; the strokes it closed or bottomed come back.
func stroke(move: float) -> Array[THRUST_STATE.StrokeEvent]:
	var events: Array[THRUST_STATE.StrokeEvent] = []
	if not _live() or is_zero_approx(move):
		return events
	events = _thrust.move(move, _clock)
	_after_move(events)
	return events


## Put him at this physical penetration, from a hand or the anatomy bridge.
func set_penetration(meters: float) -> Array[THRUST_STATE.StrokeEvent]:
	var events: Array[THRUST_STATE.StrokeEvent] = []
	if not _live():
		return events
	events = _thrust.set_penetration(meters, _clock)
	_after_move(events)
	return events


func caress() -> void:
	_touch("caress")


func kiss() -> void:
	_touch("kiss")


func smack() -> void:
	_touch("smack")


## The player's own words; her preference taxonomy stays in here.
func talk(text: String) -> void:
	if _phase != PHASE_ACTIVE:
		return
	var line := text.strip_edges()
	if not line.is_empty():
		_last_player_talk = line
		_act_player_lines += 1
	var category := PREFERENCES.classify_talk(text)
	if category.is_empty():
		return
	var event: Dictionary = {}
	if _profile.dislikes.has(category):
		_act_talk_dislikes += 1
		event = _observe_dislike(category)
	elif _profile.talk.has(category):
		_observe_like(category)
	var now := _clock
	if now - _last_talk_at < SETTINGS.talk_cooldown_seconds.get_num():
		_report_tolerance(event)
		return
	_last_talk_at = now
	_readout.last_talk = category
	if _profile.talk.has(category):
		_act_liked_talk += 1
		_cue("She likes that." if _readout.satisfaction < ASSIST_CAP
			else "She needs you to move.", SETTINGS.override_seconds.get_num())
		_receptive_until = now + SETTINGS.receptive_seconds.get_num()
		if _readout.satisfaction < ASSIST_CAP:
			heat(minf(TALK_HEAT, ASSIST_CAP - _readout.satisfaction))
		LOG.debug("talk like category=%s readiness=%.0f", [category, _readout.satisfaction])
	elif _profile.dislikes.has(category):
		_act_dislikes += 1
		heat(-TALK_HEAT)
		_overwhelmed_left = SETTINGS.overwhelmed_seconds.get_num()
		_readout.overwhelmed = _overwhelmed_left > 0.0
		_cue("She didn't like that.", SETTINGS.override_seconds.get_num())
		overwhelmed.emit()
		LOG.debug("talk dislike category=%s readiness=%.0f", [
			category, _readout.satisfaction])
	else:
		_cue("She listens.", SETTINGS.override_seconds.get_num())
	_report_tolerance(event)


## Her cue for this many seconds; the act's own lines, a warning and a form's line come in here.
func cue(text: String, seconds: float) -> void:
	if _phase == PHASE_IDLE or _phase == PHASE_ENDED:
		return
	_cue(text, seconds)


## The body change's provider-supplied warmth, the one reward that is not a stroke.
func heat(amount: float) -> void:
	if is_zero_approx(amount) or _phase == PHASE_IDLE or _phase == PHASE_ENDED:
		return
	_write_satisfaction(_readout.satisfaction + amount)
	_check_thresholds()


## The act's climax span opened; the span is the act's. The count, her mood and her cue follow.
func begin_climax(span: float) -> void:
	if _phase != PHASE_ACTIVE:
		return
	_phase = PHASE_CLIMAX
	_readout.climaxes += 1
	_readout.mood = "climax"
	_cue("She is climaxing.", span)
	LOG.debug("pony climax=%d readiness=%.0f", [_readout.climaxes, _readout.satisfaction])


## The span ended; the meter goes back to zero, or the act has already moved on.
func end_climax() -> void:
	if _phase != PHASE_CLIMAX:
		return
	_phase = PHASE_ACTIVE
	_readout.satisfaction = 0.0
	_readout.mood = "warming"
	_readout.cue = ""
	_readout.cue_override = false
	_readout.overwhelmed = false
	_readout.last_intensity = ""
	_readout.last_pattern = ""
	_overwhelmed_left = 0.0
	_cue_until = 0.0
	_last_stroke_at = -1000.0
	_last_thrust_score_at = -1000.0
	_receptive_until = 0.0
	_climax_signalled = false
	_stroke_window.clear()
	LOG.debug("pony climax end=%d readiness=0", [_readout.climaxes])


## The act is over: the meter, the input and the tracker stop, and her satisfaction drains on its
## own. A later start ends any drain still running.
func end_act() -> void:
	if _phase == PHASE_IDLE or _phase == PHASE_ENDED:
		return
	_phase = PHASE_ENDED
	_drain_rate = maxf(0.0, _readout.satisfaction) / DRAIN_SECONDS
	_readout.cue = ""
	_readout.cue_override = false
	_readout.overwhelmed = false
	_readout.strength = 0.0
	_overwhelmed_left = 0.0
	_cue_until = 0.0
	_thrust.reset()
	_sync_scale()
	LOG.debug("act end readiness=%.0f", [_readout.satisfaction])


## Her live state, the same instance every call.
func readout() -> Readout:
	return _readout


## The act's counter record, copied for the one snapshot `summary` scores.
func take_meter() -> ACT_METER:
	var out := ACT_METER.new()
	out.thrusts = _act_thrusts
	out.pony_climaxes = _readout.climaxes
	out.talk_liked = _act_liked_talk
	out.talk_dislikes = _act_talk_dislikes
	out.touches_liked = _act_liked_touch
	out.touch_dislikes = _touch_dislikes.duplicate(true)
	out.player_lines = _act_player_lines
	out.intensity_total = _act_intensity_total
	out.intensity_right = _act_intensity_right
	out.pattern_total = _act_pattern_total
	out.pattern_right = _act_pattern_right
	out.peak_satisfaction = _peak_satisfaction
	out.both_matches = _act_both_matches
	out.dislikes = _act_dislikes
	out.liked_touch = _act_liked_touch
	out.liked_talk = _act_liked_talk
	out.player_talk = _last_player_talk
	return out


## The private tick: the act never drives it. With no act start or no wiring it does nothing.
func _process(delta: float) -> void:
	if _phase == PHASE_IDLE or _deps == null:
		return
	_tick(delta)


func _tick(delta: float) -> void:
	_clock += maxf(0.0, delta)
	if _phase == PHASE_ENDED:
		_drain(delta)
		return
	_tolerance_controller().tick(delta)
	_sync_tolerance()
	if _phase != PHASE_ACTIVE:
		_sync_scale()
		return
	_readout.seconds_since_stroke = maxf(0.0, _clock - _last_stroke_at)
	if _readout.seconds_since_stroke > STROKE_MEMORY_S:
		_readout.last_intensity = ""
		_readout.last_pattern = ""
		_stroke_window.clear()
	if _overwhelmed_left > 0.0:
		_overwhelmed_left = maxf(0.0, _overwhelmed_left - delta)
		_readout.overwhelmed = _overwhelmed_left > 0.0
	_sync_scale()
	_flush_tracker()
	if _phase != PHASE_ACTIVE:
		return
	_publish_cue()
	if not _climax_signalled and _readout.satisfaction >= PONY_CLIMAX_AT:
		_climax_signalled = true
		climaxed.emit()


## The run-down after the act: a linear fall, the same shape the afterglow used to own.
func _drain(delta: float) -> void:
	if _drain_rate <= 0.0 or _readout.satisfaction <= 0.0:
		return
	_readout.satisfaction = maxf(0.0, _readout.satisfaction - _drain_rate * delta)


## A held bottom or a timed-out stroke closes here; the act's fan-out receives it as one signal.
func _flush_tracker() -> void:
	_readout.strength = _thrust.live_strength(_clock)
	_count_rate()
	var events: Array[THRUST_STATE.StrokeEvent] = _thrust.tick(_clock)
	if events.is_empty():
		return
	_after_move(events)
	strokes.emit(events)


## Mirror the act's live readout after a move: the depth scale, the impacts and the score.
func _after_move(events: Array[THRUST_STATE.StrokeEvent]) -> void:
	_thrust.sync_penetration()
	_sync_scale()
	for event: THRUST_STATE.StrokeEvent in events:
		if event.kind == "impact":
			_note_impact()
		elif event.direction > 0 and event.thrust:
			_score_stroke(event)


func _note_impact() -> void:
	while not _impacts.is_empty() and _clock - _impacts[0] > 1.0:
		_impacts.pop_front()
	_impacts.append(_clock)
	_readout.rate = float(_impacts.size())


func _count_rate() -> void:
	var in_window := 0
	for at: float in _impacts:
		if _clock - at <= 1.0:
			in_window += 1
	_readout.rate = float(in_window)


## Only real thrusts update the pattern window and score. Upward strokes, tiny jitter and
## pullbacks are presentation only.
func _score_stroke(event: THRUST_STATE.StrokeEvent) -> void:
	_act_thrusts += 1
	if _phase != PHASE_ACTIVE:
		# The player can keep thrusting through her climax; only the score stays off.
		return
	_last_stroke = {
		"travel": event.travel,
		"duration": event.duration,
		"speed": event.speed,
		"peak_speed": event.peak_speed,
		"strength": event.strength,
	}
	_last_stroke_at = _clock
	_stroke_window.append(_last_stroke)
	while _stroke_window.size() > 4:
		_stroke_window.pop_front()
	# The preference axis is the stroke's depth; the physical strength stays the audio/foley
	# impact value. Keeping the two axes independent lets the player choose depth and tempo.
	_readout.last_intensity = PREFERENCES.intensity_for_travel(event.travel)
	_readout.last_pattern = PREFERENCES.pattern_for(_stroke_window)
	LOG.debug("thrust stroke travel=%.2f speed=%.2f peak=%.2f strength=%.2f intensity=%s pattern=%s readiness=%.0f", [
		event.travel, event.speed, event.peak_speed, event.strength,
		_readout.last_intensity, _readout.last_pattern, _readout.satisfaction])
	_score_axes()


## Matching both axes is best, one axis still helps, and a mismatch makes no progress.
func _score_axes() -> void:
	var now := _clock
	if now - _last_thrust_score_at < THRUST_SCORE_MIN_INTERVAL:
		return
	_last_thrust_score_at = now
	var intensity_match := not _readout.last_intensity.is_empty() \
		and _readout.last_intensity == _profile.intensity
	var pattern_match := not _readout.last_pattern.is_empty() \
		and _readout.last_pattern == _profile.pattern
	_act_intensity_total += 1
	if intensity_match:
		_act_intensity_right += 1
	if not _readout.last_pattern.is_empty():
		_act_pattern_total += 1
		if pattern_match:
			_act_pattern_right += 1
	if intensity_match and pattern_match:
		_act_both_matches += 1
	var chunk := THRUST_HEAT_NONE
	if intensity_match and pattern_match:
		chunk = THRUST_HEAT_BOTH
	elif intensity_match or pattern_match:
		chunk = THRUST_HEAT_ONE
	if chunk > 0.0:
		chunk *= PREFERENCES.warmth_scale(_preferences)
		if now < _receptive_until:
			chunk *= RECEPTIVE_BOOST
		if _deps != null and _deps.in_heat.is_valid() and bool(_deps.in_heat.call()):
			chunk *= HEAT_READINESS
		heat(chunk)
	LOG.debug("thrust score intensity=%s pattern=%s both=%s heat=%.2f readiness=%.0f", [
		_readout.last_intensity, _readout.last_pattern,
		str(intensity_match and pattern_match), chunk, _readout.satisfaction])


## The two thresholds a full or close meter crosses, in the order the act presents them.
func _check_thresholds() -> void:
	if _phase != PHASE_ACTIVE:
		return
	if _readout.satisfaction >= PONY_CLIMAX_AT:
		if not _climax_signalled:
			_climax_signalled = true
			climaxed.emit()
		return
	if not _close_notified and _readout.satisfaction >= UTTERANCE_SCHEDULER.CLOSE_AT:
		_close_notified = true
		close_reached.emit()


func _write_satisfaction(value: float) -> void:
	var before := int(_readout.satisfaction)
	_readout.satisfaction = clampf(value, 0.0, READINESS_MAX)
	if _readout.satisfaction > _peak_satisfaction:
		_peak_satisfaction = _readout.satisfaction
	if int(_readout.satisfaction) != before \
			and (int(_readout.satisfaction) == 0 or int(_readout.satisfaction) % 10 == 0):
		LOG.debug("readiness=%.0f mood=%s", [_readout.satisfaction, _readout.mood])


## Her mood and cue from the meter and the live axes; the act hears it only when it changes.
func _publish_cue() -> void:
	var mood := UTTERANCE_SCHEDULER.mood_for(_readout.satisfaction, _overwhelmed_left)
	var override := _readout.cue_override and _clock < _cue_until
	var text := _readout.cue
	if not override:
		text = UTTERANCE_SCHEDULER.base_cue(_preferences, _overwhelmed_left,
			_readout.satisfaction, _readout.last_intensity, _readout.last_pattern)
	var changed := mood != _published_mood or override != _published_override \
		or text != _published_text
	_readout.mood = mood
	_readout.cue = text
	_readout.cue_override = override
	if not changed:
		return
	_published_mood = mood
	_published_text = text
	_published_override = override
	cue_changed.emit(mood, text, override)


## One real action per call, including the tolerance meter. A held caress must call this once per
## touch interval, never per frame, or every frame would erase all distress.
func _touch(kind: String) -> void:
	if _phase != PHASE_ACTIVE:
		return
	_touch_counts[kind] = int(_touch_counts.get(kind, 0)) + 1
	var event: Dictionary = {}
	if _profile.dislikes.has(kind):
		_touch_dislikes[kind] = int(_touch_dislikes.get(kind, 0)) + 1
		event = _observe_dislike(kind)
	elif _profile.touch.has(kind):
		_observe_like(kind)
	var now := _clock
	# One shared scoring cooldown: alternating caress/kiss/smack must not bypass the cap.
	if now - _last_touch_at < SETTINGS.touch_cooldown_seconds.get_num():
		_report_tolerance(event)
		return
	_last_touch_at = now
	_readout.last_touch = kind
	if _profile.touch.has(kind):
		_act_liked_touch += 1
		_cue("She likes that." if _readout.satisfaction < ASSIST_CAP
			else "She needs more than your hands.", SETTINGS.override_seconds.get_num())
		_receptive_until = now + SETTINGS.receptive_seconds.get_num()
		if _readout.satisfaction < ASSIST_CAP:
			heat(minf(TOUCH_HEAT, ASSIST_CAP - _readout.satisfaction))
		LOG.debug("touch like kind=%s readiness=%.0f", [kind, _readout.satisfaction])
	elif _profile.dislikes.has(kind):
		_act_dislikes += 1
		heat(-TOUCH_HEAT)
		_overwhelmed_left = SETTINGS.overwhelmed_seconds.get_num()
		_readout.overwhelmed = _overwhelmed_left > 0.0
		_cue("She doesn't like that.", SETTINGS.override_seconds.get_num())
		overwhelmed.emit()
		LOG.debug("touch dislike kind=%s readiness=%.0f", [kind, _readout.satisfaction])
	# A neutral touch sets no override; the live base cue stays on screen.
	_report_tolerance(event)


func _cue(text: String, seconds: float) -> void:
	_readout.cue = text
	_readout.cue_override = not text.is_empty()
	_cue_until = _clock + maxf(0.0, seconds)


func _observe_dislike(kind: String) -> Dictionary:
	var event := _tolerance_controller().observe_dislike(kind)
	_sync_tolerance()
	return event


func _observe_like(kind: String) -> void:
	_tolerance_controller().observe_like(kind)
	_sync_tolerance()


## One meter decision per input; the act's consent owner is the only consumer.
func _report_tolerance(event: Dictionary) -> void:
	if event.is_empty():
		return
	tolerance.emit(int(event.get("warning", 0)), bool(event.get("stop", false)),
		float(event.get("distress", 0.0)), str(event.get("kind", "")))


func _sync_tolerance() -> void:
	_readout.distress = float(_tolerance.distress)
	_readout.last_dislike = _tolerance.last_dislike


## The depth scale, read at use so a live settings edit lands on the next sample.
func _sync_scale() -> void:
	_readout.shaft_m = _thrust.shaft_length_m()
	_readout.reach_m = _thrust.reach()
	_readout.travel = SETTINGS.travel.get_num()
	_readout.up_is_deep = SETTINGS.orientation.get_choice() == "up"
	_readout.depth = _thrust.depth
	_readout.penetration_m = _thrust.penetration_m


func _live() -> bool:
	return _phase == PHASE_ACTIVE or _phase == PHASE_CLIMAX


## The meter is created lazily so a suite can build the facade without a profile.
func _tolerance_controller() -> TOLERANCE:
	if _tolerance == null:
		_tolerance = TOLERANCE.new()
	return _tolerance
