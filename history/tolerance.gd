extends RefCounted
## Pure per-act tolerance. A disliked touch/talk adds distress, a liked one subtracts, and slow
## time decay forgives a little. Warnings are one-shot per act; the stop threshold ends the act.
## No scene access.

const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

const DEFAULT_RULES := {
	"forgiving_warning": 4.0,
	"normal_warning_1": 1.0,
	"normal_warning_2": 4.0,
	"normal_stop": 10.0,
	"strict_warning": 1.0,
	"strict_stop": 3.0,
	"dislike_amount": 1.0,
	"like_relief": 1.0,
	"decay_seconds": 25.0,
	"decay_amount": 1.0,
	"normal_cooldown_s": 300.0,
	"strict_cooldown_s": 600.0,
}

var tier := "normal"
var distress := 0.0
var warning_stage := 0
var stopped := false
var last_dislike := ""
var _decay_left := 0.0


## The live setting behind each rule key, declared once so `rules()` needs no path strings.
static var _RULES := {
	"decay_amount": SETTINGS.tolerance_decay_amount,
	"decay_seconds": SETTINGS.decay_seconds,
	"dislike_amount": SETTINGS.dislike_amount,
	"forgiving_warning": SETTINGS.forgiving_warning,
	"like_relief": SETTINGS.like_relief,
	"normal_cooldown_s": SETTINGS.normal_cooldown_s,
	"normal_stop": SETTINGS.normal_stop,
	"normal_warning_1": SETTINGS.normal_warning_1,
	"normal_warning_2": SETTINGS.normal_warning_2,
	"strict_cooldown_s": SETTINGS.strict_cooldown_s,
	"strict_stop": SETTINGS.strict_stop,
	"strict_warning": SETTINGS.strict_warning,
}


static func rules() -> Dictionary:
	var out := DEFAULT_RULES.duplicate(true)
	for key: String in DEFAULT_RULES:
		if _RULES.has(key):
			out[key] = _RULES[key].get_num()
	return out


func reset(preferences: Dictionary) -> void:
	tier = PREFERENCES.tolerance_tier(str(preferences.get("tolerance", "normal")))
	distress = 0.0
	warning_stage = 0
	stopped = false
	last_dislike = ""
	_decay_left = 0.0


## Every actual disliked touch/talk adds to the meter and may produce a warning or a stop.
func observe_dislike(kind: String) -> Dictionary:
	if stopped:
		return {}
	last_dislike = kind
	distress += float(rules().get("dislike_amount", 1.0))
	return event()


## Every actual liked touch/talk buys back some tolerance. It never replays an old warning.
func observe_like(_kind: String) -> void:
	if stopped:
		return
	distress = maxf(0.0, distress - float(rules().get("like_relief", 1.0)))


## Slow forgiveness while the act continues. No warning is emitted by decay.
func tick(delta: float) -> void:
	if stopped:
		return
	var limits := rules()
	var period := float(limits.get("decay_seconds", 25.0))
	if period <= 0.0:
		return
	_decay_left += maxf(0.0, delta)
	while _decay_left >= period:
		_decay_left -= period
		distress = maxf(0.0, distress - float(limits.get("decay_amount", 1.0)))


func event() -> Dictionary:
	if stopped:
		return {}
	var limits := rules()
	match tier:
		"forgiving":
			if warning_stage < 1 and distress >= float(limits.get("forgiving_warning", 4.0)):
				warning_stage = 1
				return {"warning": 1, "distress": distress}
		"strict":
			if warning_stage < 1 and distress >= float(limits.get("strict_warning", 1.0)):
				warning_stage = 1
				return {"warning": 1, "distress": distress}
			if distress >= float(limits.get("strict_stop", 3.0)):
				stopped = true
				return {"stop": true, "distress": distress, "kind": last_dislike}
		_:
			if warning_stage < 1 and distress >= float(limits.get("normal_warning_1", 1.0)):
				warning_stage = 1
				return {"warning": 1, "distress": distress}
			if warning_stage < 2 and distress >= float(limits.get("normal_warning_2", 4.0)):
				warning_stage = 2
				return {"warning": 2, "distress": distress}
			if distress >= float(limits.get("normal_stop", 10.0)):
				stopped = true
				return {"stop": true, "distress": distress, "kind": last_dislike}
	return {}


## Sex-only cooldown after a stop. Forgiving never stops, so it has none.
func cooldown_seconds() -> float:
	var limits := rules()
	match tier:
		"strict":
			return float(limits.get("strict_cooldown_s", 600.0))
		"normal":
			return float(limits.get("normal_cooldown_s", 300.0))
		_:
			return 0.0
