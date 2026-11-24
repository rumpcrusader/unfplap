extends Node
## Service: readiness
## Scope: pony
## Contract: docs/readiness.md
## Act readiness: her satisfaction, mood and cue, the stroke score, touch/talk input, the
## neglect-tolerance meter and the counters the act summary reads.

const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const UTTERANCE_SCHEDULER := preload("res://mods/unfplap/dialogue/utterance_scheduler.gd")
const AUTO_THRUST := preload("res://mods/unfplap/readiness/auto_thrust.gd")
const AUTO_PANEL := preload("res://mods/unfplap/readiness/auto_panel.gd")
const TOLERANCE := preload("res://mods/unfplap/readiness/tolerance.gd")
const THRUST_STATE := preload("res://mods/unfplap/readiness/thrust_state.gd")
const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
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
const STATE_ACTIVE := ACT_STATE.State.ACTIVE
const STATE_CLIMAX := ACT_STATE.State.CLIMAX
## The face moment a disliked touch or talk presents; `shared/act_face.gd` owns the beat itself.
const FACE_OVERWHELMED := "overwhelmed"


## The per-mare preference profile readiness reads, resolved at the act boundary.
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


## One tolerance decision, presented on the runtime's next tick. The empty decision is shared, so
## a quiet frame allocates nothing.
class Decision extends RefCounted:
	var warning := 0
	var stop := false
	var distress := 0.0
	var kind := ""

	## The edge: the pure meter reports a plain document, empty when nothing happened.
	static func from_dict(event: Dictionary) -> Decision:
		var out := Decision.new()
		if event.is_empty():
			return out
		out.warning = int(event.get("warning", 0))
		out.stop = bool(event.get("stop", false))
		out.distress = float(event.get("distress", 0.0))
		out.kind = str(event.get("kind", ""))
		return out

	func is_empty() -> bool:
		return warning <= 0 and not stop


## Public act state, forwarded by the runtime.
var satisfaction := 0.0
var mood := "warming"
var cue := ""
var pony_climaxes := 0

## The pure per-act tolerance meter and the decision the runtime presents on its next tick.
var tolerance: TOLERANCE = null
var _tolerance_pending: Decision = null
## Returned while nothing is pending, so the frame path allocates no record.
var _no_decision := Decision.new()
## A paused Debug-panel request, consumed by the runtime on its next tick.
var debug_request := ""

## The live scoring window.
var last_intensity := ""
var last_pattern := ""
var last_touch := ""
var last_talk := ""
var stroke_window: Array[Dictionary] = []
var last_stroke: Dictionary = {}
var last_stroke_at := -1000.0
var last_thrust_score_at := -1000.0
var last_touch_at := -1000.0
var last_talk_at := -1000.0
var last_talk_turn := -1
var receptive_until := 0.0
var overwhelmed := 0.0
var cue_override := ""
var cue_until := 0.0
var close_notified := false

## Act summary counters.
var peak_satisfaction := 0.0
var act_both_matches := 0
var act_dislikes := 0
var act_liked_touch := 0
var act_liked_talk := 0
var last_player_talk := ""
var act_touch_counts: Dictionary = {}
var act_touch_dislikes: Dictionary = {}
var act_talk_dislikes := 0
var act_player_lines := 0
var act_thrusts := 0
var act_intensity_total := 0
var act_intensity_right := 0
var act_pattern_total := 0
var act_pattern_right := 0

## Per-act configuration.
var preferences: Dictionary = {}
var override_seconds: float
var overwhelmed_seconds: float
var touch_cooldown: float
var talk_cooldown: float
var receptive_seconds: float

var clock := Callable()
## The runtime's `State` value.
var state := Callable()
var on_climax := Callable()
var on_close := Callable()
var on_face := Callable()
var on_anatomy_react := Callable()
var heat_cycle := Callable()
## `(mood, cue, is_override)` after the cue changed. The runtime syncs its act view and admits.
var on_cue := Callable()

## Auto thrust and the hold-X layer. The runtime reads the keys and applies the returned depth,
## so the stroke still runs through one tracker and scores like the mouse.
var auto_thrust: AUTO_THRUST = AUTO_THRUST.new()
var auto_panel: AUTO_PANEL = AUTO_PANEL.new()
var auto_on := false
## The act's `auto_thrust.*` snapshot, pushed by the runtime.
var auto_default_pace: float
var auto_default_depth: float
var auto_default_min: float
var auto_default_shape: String

## The act's stroke and penetration state. Its tracker is the only stroke authority; the mouse,
## auto thrust and the anatomy bridge all feed this one object.
var _thrust: THRUST_STATE = THRUST_STATE.new()
## Host reads for the depth scale. The runtime supplies his visible shaft length and the live
## pose family; a missing callback falls back to the nominal length.
var shaft_length := Callable()
var pose_family := Callable()

## The runtime forwards the public stroke values; HUD and presentation read them here.
var depth: float:
	get:
		return _thrust.depth
	set(value):
		_thrust.depth = value
var penetration_m: float:
	get:
		return _thrust.penetration_m
	set(value):
		_thrust.penetration_m = value
var thrust_travel: float:
	get:
		return _thrust.travel
var up_is_deep: bool:
	get:
		return _thrust.up_is_deep


## The act's depth scale, pushed once per act and again on every live settings apply.
func configure_thrust(pixels_per_cm: float, up_is_deep_in: bool, travel: float,
		pelvis_gap_m: float) -> void:
	_thrust.shaft_length = shaft_length
	_thrust.pose_family = pose_family
	_thrust.configure(pixels_per_cm, up_is_deep_in, travel, pelvis_gap_m)


## A fresh act: the tracker, the public depth and the physical penetration go back to rest.
func reset_thrust() -> void:
	_thrust.reset()


func shaft_length_m() -> float:
	return _thrust.shaft_length_m()


func reach() -> float:
	return _thrust.reach()


## Mouse motion as hip travel in metres. Input still owns the event; the scale and orientation
## are the act's.
func mouse_travel(dy_pixels: float) -> float:
	return _thrust.mouse_travel(dy_pixels)


func live_strength(now: float) -> float:
	return _thrust.live_strength(now)


## Move the measured depth and return the strokes it closed or bottomed.
func move(amount: float, now: float) -> Array[THRUST_STATE.StrokeEvent]:
	return _thrust.move(amount, now)


## One idle tracker frame: a held bottom or a timed-out stroke produces its event here.
func stroke_tick(now: float) -> Array[THRUST_STATE.StrokeEvent]:
	return _thrust.tick(now)


func set_penetration(target_m: float, now: float) -> Array[THRUST_STATE.StrokeEvent]:
	return _thrust.set_penetration(target_m, now)


## One auto frame: the generated depth through the same tracker, or no events while auto is off.
func auto_advance(delta: float, now: float) -> Array[THRUST_STATE.StrokeEvent]:
	var next_depth := auto_step(delta)
	if is_nan(next_depth):
		return []
	var events: Array[THRUST_STATE.StrokeEvent] = _thrust.move(next_depth - _thrust.depth, now)
	_thrust.penetration_m = _thrust.depth * _thrust.reach()
	return events


## One impact in the live one-second rate window.
func note_impact() -> void:
	var now := _now()
	thrust_times.append(now)
	while not thrust_times.is_empty() and now - float(thrust_times[0]) > 1.0:
		thrust_times.pop_front()


## The runtime forwards the public values; these are the auto readouts.
func auto_active() -> bool:
	return auto_on and _state_in([STATE_ACTIVE, STATE_CLIMAX])


## Snapshot the auto defaults once per act and on every live settings apply. A body swap keeps the
## shape the act chose with `Z`, because that snapshot is not a settings edit.
func configure_auto(pace: float, max_depth: float, shape: String, min_depth: float,
		keep_shape := false) -> void:
	auto_default_pace = pace
	auto_default_depth = max_depth
	auto_default_min = min_depth
	if keep_shape:
		return
	auto_default_shape = shape
	auto_thrust.set_shape(auto_default_shape)


## A fresh act: the generator returns to its settings defaults and the layer closes.
func reset_auto() -> void:
	auto_on = false
	auto_thrust.reset(auto_default_pace, auto_default_depth, auto_default_shape,
		auto_default_min)
	auto_panel.reset()


func stop_auto() -> void:
	auto_on = false
	auto_thrust.stop()
	auto_panel.close()


## X toggles auto in ACTIVE/CLIMAX. `current_depth` starts the machine where the hand left it.
func toggle_auto(current_depth: float) -> bool:
	if not _state_in([STATE_ACTIVE, STATE_CLIMAX]):
		return auto_on
	auto_on = not auto_on
	if auto_on:
		auto_thrust.begin(current_depth)
	else:
		auto_thrust.stop()
	LOG.debug("auto thrust %s pace=%.2f/s depth=%.0f%%", [
		"on" if auto_on else "off", auto_thrust.pace, auto_thrust.max_depth * 100.0])
	return auto_on


## One auto frame: the next depth, or NAN while auto is off. The runtime applies the depth.
func auto_step(delta: float) -> float:
	if not auto_on:
		return NAN
	return auto_thrust.step(delta)


## One wheel notch while auto owns the stroke.
func auto_wheel(direction: int) -> void:
	if not auto_on or not _state_in([STATE_ACTIVE, STATE_CLIMAX]):
		return
	auto_thrust.nudge_pace(float(direction) * AUTO_THRUST.PACE_STEP)


func auto_panel_open() -> bool:
	return auto_panel.open


## The hold-X layer: consumes the input service's key states and returns the actions it applied,
## so one log line lands per adjustment rather than per frame.
func auto_panel_tick(delta: float, x_down: bool, keys: Array[bool],
		current_depth: float) -> Array[String]:
	if not _state_in([STATE_ACTIVE, STATE_CLIMAX]):
		auto_panel.reset()
		return []
	var actions: Array[String] = auto_panel.tick(delta, x_down, keys, auto_on)
	for action: String in actions:
		match action:
			"toggle":
				toggle_auto(current_depth)
			"min_up", "min_down":
				auto_thrust.nudge_min(AUTO_PANEL.DEPTH_STEP if action == "min_up"
					else -AUTO_PANEL.DEPTH_STEP)
			"max_up", "max_down":
				auto_thrust.nudge_depth(AUTO_PANEL.DEPTH_STEP if action == "max_up"
					else -AUTO_PANEL.DEPTH_STEP)
			"pace_up", "pace_down":
				auto_thrust.nudge_pace(AUTO_PANEL.PACE_STEP if action == "pace_up"
					else -AUTO_PANEL.PACE_STEP)
			"shape_next":
				auto_cycle_shape()
	if not actions.is_empty():
		LOG.debug("auto layer %s min=%.0f%% max=%.0f%% pace=%.2f/s", [
			",".join(actions), auto_thrust.min_depth * 100.0, auto_thrust.max_depth * 100.0,
			auto_thrust.pace])
	return actions


## The generator value. The runtime maps it to the settings label for the HUD.
func auto_shape() -> String:
	return auto_thrust.shape


func auto_set_shape(name: String) -> void:
	auto_default_shape = name
	var before: String = auto_thrust.shape
	auto_thrust.set_shape(name)
	if auto_thrust.shape != before:
		LOG.debug("auto shape %s", [auto_thrust.shape])


## `Z` in the layer: next stroke shape, written to settings so an experiment survives the act.
func auto_cycle_shape() -> void:
	var next: String = AUTO_THRUST.next_shape(auto_thrust.shape)
	SETTINGS.curve.set_choice(next)
	auto_set_shape(next)


func auto_pace() -> float:
	return auto_thrust.pace


func auto_min_depth() -> float:
	return auto_thrust.min_depth


func auto_max_depth() -> float:
	return auto_thrust.max_depth


## Start a fresh act. The configuration fields set by `configure()` survive.
func reset(profile: Profile) -> void:
	preferences = profile.to_dict()
	pony_climaxes = 0
	last_intensity = ""
	last_pattern = ""
	last_touch = ""
	last_talk = ""
	stroke_window.clear()
	last_stroke.clear()
	last_stroke_at = -1000.0
	last_thrust_score_at = -1000.0
	last_touch_at = -1000.0
	last_talk_at = -1000.0
	last_talk_turn = -1
	receptive_until = 0.0
	overwhelmed = 0.0
	cue_override = ""
	cue_until = 0.0
	close_notified = false
	peak_satisfaction = 0.0
	act_both_matches = 0
	act_dislikes = 0
	act_liked_touch = 0
	act_liked_talk = 0
	last_player_talk = ""
	act_touch_counts.clear()
	act_touch_dislikes.clear()
	act_talk_dislikes = 0
	act_player_lines = 0
	act_thrusts = 0
	act_intensity_total = 0
	act_intensity_right = 0
	act_pattern_total = 0
	act_pattern_right = 0
	_tolerance_controller().reset(profile.tolerance)
	_tolerance_pending = null
	debug_request = ""


func configure(profile: Profile, override_s: float, overwhelmed_s: float,
		touch_cd: float, talk_cd: float, receptive_s: float) -> void:
	preferences = profile.to_dict()
	override_seconds = override_s
	overwhelmed_seconds = overwhelmed_s
	touch_cooldown = touch_cd
	talk_cooldown = talk_cd
	receptive_seconds = receptive_s


## The pony's climax moment: one count, her climax mood and cue, and the log line. The session
## owns the state transition and the presentation order.
func begin_climax(pose_id: String, pony_name: String, climax_seconds: float) -> int:
	pony_climaxes += 1
	mood = "climax"
	set_cue_override("She is climaxing.", climax_seconds)
	LOG.debug("pony climax=%d pose=%s pony=%s readiness=%.0f", [
		pony_climaxes, pose_id, pony_name, satisfaction])
	return pony_climaxes


## The climax effect ended and the act returns to ACTIVE: the meter, the stroke memory and the
## cues restart from zero. `max_climaxes` is the configured limit, for the log line only.
func end_climax(max_climaxes: int) -> void:
	satisfaction = 0.0
	mood = "warming"
	cue = ""
	cue_override = ""
	cue_until = 0.0
	overwhelmed = 0.0
	last_intensity = ""
	last_pattern = ""
	stroke_window.clear()
	last_stroke_at = -1000.0
	last_thrust_score_at = -1000.0
	receptive_until = 0.0
	var limit_text := "∞" if max_climaxes <= 0 else str(max_climaxes)
	LOG.debug("pony climax end=%d/%s readiness=0", [pony_climaxes, limit_text])


func clear_cues() -> void:
	cue = ""
	cue_override = ""
	cue_until = 0.0


## Each real thrust lands as a discrete chunk. Matching both axes is best, one axis still
## helps, and a mismatch makes no progress. This is what makes thrusting essential.
func add_heat(amount: float) -> void:
	if is_zero_approx(amount):
		return
	var before := int(satisfaction)
	satisfaction = clampf(satisfaction + amount, 0.0, READINESS_MAX)
	if satisfaction > peak_satisfaction:
		peak_satisfaction = satisfaction
	if int(satisfaction) != before and (int(satisfaction) == 0 or int(satisfaction) % 10 == 0):
		LOG.debug("readiness=%.0f mood=%s", [satisfaction, mood])


## The typed reads the host-callback bindings use: the meter, the stroke depth and the climax count.
func satisfaction_value() -> float:
	return satisfaction


func cue_value() -> String:
	return cue


func depth_value() -> float:
	return depth


func penetration_m_value() -> float:
	return penetration_m


func climax_count() -> int:
	return pony_climaxes


## The afterglow's decay write. The meter's range is this module's rule, not the caller's.
func write_satisfaction(value: float) -> void:
	satisfaction = clampf(value, 0.0, READINESS_MAX)


func set_cue_override(text: String, seconds := -1.0) -> void:
	if seconds < 0.0:
		seconds = override_seconds
	cue = text
	cue_override = text
	cue_until = _now() + maxf(0.0, seconds)


## Only real thrusts update the pattern window and score. Upward strokes, tiny jitter and
## pullbacks are presentation only.
func stroke(event: THRUST_STATE.StrokeEvent) -> void:
	if not _state_in([STATE_ACTIVE, STATE_CLIMAX]):
		return
	if event.direction <= 0:
		return
	if not event.thrust:
		return
	act_thrusts += 1
	if _state() == STATE_CLIMAX:
		# The player can keep thrusting through her climax; only the score stays off.
		return
	last_stroke = {
		"travel": event.travel,
		"duration": event.duration,
		"speed": event.speed,
		"peak_speed": event.peak_speed,
		"strength": event.strength,
	}
	last_stroke_at = _now()
	stroke_window.append(last_stroke)
	while stroke_window.size() > 4:
		stroke_window.pop_front()
	# The preference axis is the stroke's depth; the physical strength stays the audio/foley
	# impact value. Keeping the two axes independent lets the player choose depth and tempo.
	last_intensity = PREFERENCES.intensity_for_travel(event.travel)
	last_pattern = PREFERENCES.pattern_for(stroke_window)
	LOG.debug("thrust stroke travel=%.2f speed=%.2f peak=%.2f strength=%.2f intensity=%s pattern=%s readiness=%.0f", [
		event.travel, event.speed, event.peak_speed, event.strength,
		last_intensity, last_pattern, satisfaction])
	score_thrust()


func score_thrust() -> void:
	if _state() != STATE_ACTIVE:
		return
	var now := _now()
	if now - last_thrust_score_at < THRUST_SCORE_MIN_INTERVAL:
		return
	last_thrust_score_at = now
	var wanted_intensity := str(preferences.get("intensity", "firm"))
	var wanted_pattern := str(preferences.get("pattern", "steady"))
	var intensity_match := not last_intensity.is_empty() and last_intensity == wanted_intensity
	var pattern_match := not last_pattern.is_empty() and last_pattern == wanted_pattern
	act_intensity_total += 1
	if intensity_match:
		act_intensity_right += 1
	if not last_pattern.is_empty():
		act_pattern_total += 1
		if pattern_match:
			act_pattern_right += 1
	if intensity_match and pattern_match:
		act_both_matches += 1
	var heat := THRUST_HEAT_NONE
	if intensity_match and pattern_match:
		heat = THRUST_HEAT_BOTH
	elif intensity_match or pattern_match:
		heat = THRUST_HEAT_ONE
	if heat > 0.0:
		heat *= PREFERENCES.warmth_scale(preferences)
		if now < receptive_until:
			heat *= RECEPTIVE_BOOST
		if heat_cycle.is_valid() and bool(heat_cycle.call()):
			heat *= HEAT_READINESS
		add_heat(heat)
	LOG.debug("thrust score intensity=%s pattern=%s both=%s heat=%.2f readiness=%.0f", [
		last_intensity, last_pattern, str(intensity_match and pattern_match),
		heat, satisfaction])


## The meter only moves on an action: real thrusts add, a disliked touch/talk subtracts, and time
## alone changes nothing. This tick clears stale thrust memory and updates the cue.
func tick(delta: float) -> void:
	if _state() != STATE_ACTIVE:
		return
	if satisfaction >= PONY_CLIMAX_AT:
		_climax()
		return
	if not close_notified and satisfaction >= UTTERANCE_SCHEDULER.CLOSE_AT:
		close_notified = true
		if on_close.is_valid():
			on_close.call()
	var now := _now()
	if now - last_stroke_at > STROKE_MEMORY_S:
		last_intensity = ""
		last_pattern = ""
		stroke_window.clear()
	if overwhelmed > 0.0:
		overwhelmed = maxf(0.0, overwhelmed - delta)
	if satisfaction >= PONY_CLIMAX_AT:
		_climax()
		return
	mood = UTTERANCE_SCHEDULER.mood_for(satisfaction, overwhelmed)
	if not cue_override.is_empty() and now < cue_until:
		cue = cue_override
	else:
		cue_override = ""
		cue = UTTERANCE_SCHEDULER.base_cue(preferences, overwhelmed, satisfaction,
			last_intensity, last_pattern)
	if on_cue.is_valid():
		on_cue.call(mood, cue, not cue_override.is_empty())


## One real action per call, including the tolerance meter. A held caress must call this once per
## touch interval, never per frame, or every frame would erase all distress.
func touch(kind: String) -> void:
	if _state() != STATE_ACTIVE:
		return
	# integration: a kiss or an act smack makes the anatomy mesh react.
	if on_anatomy_react.is_valid() and kind in ["kiss", "smack"]:
		on_anatomy_react.call()
	act_touch_counts[kind] = int(act_touch_counts.get(kind, 0)) + 1
	var event: Dictionary = {}
	if kind in preferences.get("dislikes", []):
		act_touch_dislikes[kind] = int(act_touch_dislikes.get(kind, 0)) + 1
		event = _observe_dislike(kind)
	elif kind in preferences.get("touch", []):
		_observe_like(kind)
	var now := _now()
	# One shared scoring cooldown: alternating caress/kiss/smack must not bypass the cap.
	if now - last_touch_at < touch_cooldown:
		_queue_tolerance(event)
		return
	last_touch_at = now
	last_touch = kind
	if kind in preferences.get("touch", []):
		act_liked_touch += 1
		if satisfaction < ASSIST_CAP:
			add_heat(minf(TOUCH_HEAT, ASSIST_CAP - satisfaction))
			set_cue_override("She likes that.")
		else:
			set_cue_override("She needs more than your hands.")
		receptive_until = now + receptive_seconds
		LOG.debug("touch like kind=%s readiness=%.0f", [kind, satisfaction])
	elif kind in preferences.get("dislikes", []):
		act_dislikes += 1
		add_heat(-TOUCH_HEAT)
		overwhelmed = overwhelmed_seconds
		if on_face.is_valid():
			on_face.call(FACE_OVERWHELMED)
		set_cue_override("She doesn't like that.")
		LOG.debug("touch dislike kind=%s readiness=%.0f", [kind, satisfaction])
	# A neutral touch sets no override; the live base cue stays on screen.
	_queue_tolerance(event)


## The player's own words are a concrete input. The AI still writes her reply; this only
## decides whether the line landed with her preference.
func talk(text: String) -> void:
	if _state() != STATE_ACTIVE:
		return
	var category := PREFERENCES.classify_talk(text)
	if category.is_empty():
		return
	var event: Dictionary = {}
	if category in preferences.get("dislikes", []):
		act_talk_dislikes += 1
		event = _observe_dislike(category)
	elif category in preferences.get("talk", []):
		_observe_like(category)
	var now := _now()
	if now - last_talk_at < talk_cooldown:
		_queue_tolerance(event)
		return
	last_talk_at = now
	last_talk = category
	if category in preferences.get("talk", []):
		act_liked_talk += 1
		if satisfaction < ASSIST_CAP:
			add_heat(minf(TALK_HEAT, ASSIST_CAP - satisfaction))
			set_cue_override("She likes that.")
		else:
			set_cue_override("She needs you to move.")
		receptive_until = now + receptive_seconds
		LOG.debug("talk like category=%s readiness=%.0f", [category, satisfaction])
	elif category in preferences.get("dislikes", []):
		act_dislikes += 1
		add_heat(-TALK_HEAT)
		overwhelmed = overwhelmed_seconds
		if on_face.is_valid():
			on_face.call(FACE_OVERWHELMED)
		set_cue_override("She didn't like that.")
		LOG.debug("talk dislike category=%s readiness=%.0f", [category, satisfaction])
	else:
		set_cue_override("She listens.")
	_queue_tolerance(event)


## Watch the director for a new player turn. No new control: the game's T key already
## produces the text/mic turn. Talk is scored when it actually happens.
func talk_tick(director: Node) -> void:
	if _state() != STATE_ACTIVE:
		return
	if director != null:
		var turn := int(director.get("_turn_id"))
		var text := str(director.get("_player_text"))
		if turn != last_talk_turn:
			last_talk_turn = turn
			if not text.strip_edges().is_empty():
				last_player_talk = text.strip_edges()
				act_player_lines += 1
				talk(text)


func remember_talk_turn(director: Node) -> void:
	if director == null:
		last_talk_turn = -1
		return
	last_talk_turn = int(director.get("_turn_id"))


func thrusts_per_second() -> float:
	var now := _now()
	var count := 0
	for at: Variant in thrust_times:
		if now - float(at) <= 1.0:
			count += 1
	return float(count)


## The runtime appends one timestamp per impact; this is the one-second rate window.
var thrust_times: Array[float] = []


func _climax() -> void:
	if on_climax.is_valid():
		on_climax.call()


## The meter is created lazily so a suite can build the facade without a profile.
func _tolerance_controller() -> TOLERANCE:
	if tolerance == null:
		tolerance = TOLERANCE.new()
	return tolerance


## One meter frame. The runtime calls this in POSING_IN and ACTIVE.
func tolerance_tick(delta: float) -> void:
	if tolerance != null:
		tolerance.tick(delta)


## Every actual disliked touch/talk adds to the meter and may produce a warning or a stop.
func _observe_dislike(kind: String) -> Dictionary:
	return _tolerance_controller().observe_dislike(kind)


## Every actual liked touch/talk buys back some tolerance. It never replays an old warning.
func _observe_like(kind: String) -> void:
	if tolerance != null:
		tolerance.observe_like(kind)


## The decision the runtime presents on its next tick, or empty. One decision per frame.
func take_tolerance_decision() -> Decision:
	if _tolerance_pending == null:
		return _no_decision
	var decision := _tolerance_pending
	_tolerance_pending = null
	return decision


func distress() -> float:
	return float(tolerance.distress) if tolerance != null else 0.0


func last_dislike() -> String:
	return str(tolerance.last_dislike) if tolerance != null else ""


## Debug actions run from the paused settings page; the request is consumed on the next frame.
func request_debug(kind: String) -> void:
	debug_request = kind


## Take and clear one pending debug request.
func take_debug() -> String:
	var action := debug_request
	debug_request = ""
	return action


func _queue_tolerance(event: Dictionary) -> void:
	if event.is_empty():
		return
	_tolerance_pending = Decision.from_dict(event)


func _state() -> int:
	return int(state.call()) if state.is_valid() else 0


func _state_in(values: Array) -> bool:
	return _state() in values


func _now() -> float:
	return float(clock.call()) if clock.is_valid() else 0.0


