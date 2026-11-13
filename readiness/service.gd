extends RefCounted
## Act readiness: her satisfaction, mood and cue, the stroke score, touch/talk input and the
## counters the act summary reads. The runtime owns the act state and supplies the clock, the
## climax transition, the face beats, the tolerance meter and the cue admission; this module owns
## only the scoring state. See docs/readiness.md.

const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const UTTERANCE_SCHEDULER := preload("res://mods/unfplap/lines/utterance_scheduler.gd")
const AUTO_THRUST := preload("res://mods/unfplap/readiness/auto_thrust.gd")
const AUTO_PANEL := preload("res://mods/unfplap/readiness/auto_panel.gd")

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
const STATE_ACTIVE := 2
const STATE_CLIMAX := 3

## Public act state, forwarded by the runtime.
var satisfaction := 0.0
var mood := "warming"
var cue := ""
var pony_climaxes := 0

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
var override_seconds := 10.0
var overwhelmed_seconds := 1.2
var touch_cooldown := 4.0
var talk_cooldown := 8.0
var receptive_seconds := 8.0

## Host boundary. Missing callbacks are no-ops.
var log := Callable()
var clock := Callable()
## The runtime's `State` value.
var state := Callable()
var on_climax := Callable()
var on_close := Callable()
var on_face := Callable()
var on_anatomy_react := Callable()
var tolerance_dislike := Callable()
var tolerance_like := Callable()
var tolerance_event := Callable()
var heat_cycle := Callable()
## `(mood, cue, is_override)` after the cue changed. The runtime syncs its act view and admits.
var on_cue := Callable()

## Auto thrust and the hold-X layer. The runtime reads the keys and applies the returned depth,
## so the stroke still runs through one tracker and scores like the mouse.
var auto_thrust: RefCounted = AUTO_THRUST.new()
var auto_panel: RefCounted = AUTO_PANEL.new()
var auto_on := false
## The act's `auto_thrust.*` snapshot, pushed by the runtime.
var auto_default_pace := 1.0
var auto_default_depth := 0.5
var auto_default_min := 0.0
var auto_default_shape := "cosine"


## The runtime forwards the public values; these are the auto readouts.
func auto_active() -> bool:
	return auto_on and _state_in([STATE_ACTIVE, STATE_CLIMAX])


## Snapshot the auto defaults once per act and on every live settings apply. The live shape
## follows the setting, matching the old runtime behaviour.
func configure_auto(pace: float, max_depth: float, shape: String, min_depth: float) -> void:
	auto_default_pace = pace
	auto_default_depth = max_depth
	auto_default_min = min_depth
	auto_default_shape = shape if AUTO_THRUST.SHAPES.has(shape) else "cosine"
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
	_log("auto thrust %s pace=%.2f/s depth=%.0f%%" % [
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


## The hold-X layer. The runtime supplies the key states and the current depth; the layer owns
## tap/hold, the grace and the key repeats. Returns the actions the runtime still has to carry out
## (the shape cycle is a settings write).
func auto_panel_tick(delta: float, x_down: bool, keys: Array,
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
	# One line per player adjustment, never per frame: the policy ticks every physics frame.
	if not actions.is_empty():
		_log("auto layer %s min=%.0f%% max=%.0f%% pace=%.2f/s" % [
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
		_log("auto shape %s" % auto_thrust.shape)


func auto_pace() -> float:
	return auto_thrust.pace


func auto_min_depth() -> float:
	return auto_thrust.min_depth


func auto_max_depth() -> float:
	return auto_thrust.max_depth



## Start a fresh act. The configuration fields set by `configure()` survive.
func reset(profile: Dictionary) -> void:
	preferences = profile
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


func configure(profile: Dictionary, override_s: float, overwhelmed_s: float,
		touch_cd: float, talk_cd: float, receptive_s: float) -> void:
	preferences = profile
	override_seconds = override_s
	overwhelmed_seconds = overwhelmed_s
	touch_cooldown = touch_cd
	talk_cooldown = talk_cd
	receptive_seconds = receptive_s


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
		_log("readiness=%.0f mood=%s" % [satisfaction, mood])


func set_cue_override(text: String, seconds := -1.0) -> void:
	if seconds < 0.0:
		seconds = override_seconds
	cue = text
	cue_override = text
	cue_until = _now() + maxf(0.0, seconds)


## Only real thrusts update the pattern window and score. Upward strokes, tiny jitter and
## pullbacks are presentation only.
func stroke(event: Dictionary) -> void:
	if not _state_in([STATE_ACTIVE, STATE_CLIMAX]):
		return
	if int(event.get("direction", 0)) <= 0:
		return
	if not bool(event.get("thrust", false)):
		return
	act_thrusts += 1
	if _state() == STATE_CLIMAX:
		# The player can keep thrusting through her climax; only the score stays off.
		return
	last_stroke = event.duplicate(true)
	last_stroke_at = _now()
	stroke_window.append(last_stroke)
	while stroke_window.size() > 4:
		stroke_window.pop_front()
	# The preference axis is the stroke's depth; the physical strength stays the audio/foley
	# impact value. Keeping the two axes independent lets the player choose depth and tempo.
	last_intensity = PREFERENCES.intensity_for_travel(float(event.get("travel", 0.0)))
	last_pattern = PREFERENCES.pattern_for(stroke_window)
	_log("thrust stroke travel=%.2f speed=%.2f peak=%.2f strength=%.2f intensity=%s pattern=%s readiness=%.0f" % [
		float(event.get("travel", 0.0)), float(event.get("speed", 0.0)),
		float(event.get("peak_speed", 0.0)), float(event.get("strength", 0.0)),
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
	_log("thrust score intensity=%s pattern=%s both=%s heat=%.2f readiness=%.0f" % [
		last_intensity, last_pattern, str(intensity_match and pattern_match),
		heat, satisfaction])


## Readiness never decays on its own. Real thrusts add the chunks in `_score_thrust`; only a
## disliked touch/talk subtracts. This tick clears stale thrust memory and updates cues.
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


## One real action per call, including the tolerance meter. Continuous inputs must emit discrete
## events: a held caress calls this once per touch interval, never once per physics tick, or a
## liked caress would erase all distress every frame.
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
		event = _tolerance_dislike(kind)
	elif kind in preferences.get("touch", []):
		_tolerance_like(kind)
	var now := _now()
	# One shared scoring cooldown: alternating caress/kiss/smack must not bypass the cap.
	if now - last_touch_at < touch_cooldown:
		_tolerance_event(event)
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
		_log("touch like kind=%s readiness=%.0f" % [kind, satisfaction])
	elif kind in preferences.get("dislikes", []):
		act_dislikes += 1
		add_heat(-TOUCH_HEAT)
		overwhelmed = overwhelmed_seconds
		if on_face.is_valid():
			on_face.call("overwhelmed")
		set_cue_override("She doesn't like that.")
		_log("touch dislike kind=%s readiness=%.0f" % [kind, satisfaction])
	# A neutral touch sets no override; the live base cue stays on screen.
	_tolerance_event(event)


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
		event = _tolerance_dislike(category)
	elif category in preferences.get("talk", []):
		_tolerance_like(category)
	var now := _now()
	if now - last_talk_at < talk_cooldown:
		_tolerance_event(event)
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
		_log("talk like category=%s readiness=%.0f" % [category, satisfaction])
	elif category in preferences.get("dislikes", []):
		act_dislikes += 1
		add_heat(-TALK_HEAT)
		overwhelmed = overwhelmed_seconds
		if on_face.is_valid():
			on_face.call("overwhelmed")
		set_cue_override("She didn't like that.")
		_log("talk dislike category=%s readiness=%.0f" % [category, satisfaction])
	else:
		set_cue_override("She listens.")
	_tolerance_event(event)


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


func _tolerance_dislike(kind: String) -> Dictionary:
	if not tolerance_dislike.is_valid():
		return {}
	var result: Variant = tolerance_dislike.call(kind)
	return result if result is Dictionary else {}


func _tolerance_like(kind: String) -> void:
	if tolerance_like.is_valid():
		tolerance_like.call(kind)


func _tolerance_event(event: Dictionary) -> void:
	if tolerance_event.is_valid():
		tolerance_event.call(event)


func _state() -> int:
	return int(state.call()) if state.is_valid() else 0


func _state_in(values: Array) -> bool:
	return _state() in values


func _now() -> float:
	return float(clock.call()) if clock.is_valid() else 0.0


func _log(text: String) -> void:
	if log.is_valid():
		log.call(text)
