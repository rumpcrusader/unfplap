extends RefCounted
## Pure act-taste profile and ACTIVE-stage classifiers. No scene access.
##
## A mare's taste has two continuous axes (intensity and pattern), concrete touch/talk
## likes, how quickly she warms, and how much readiness she recovers after a climax.
## Readiness is accumulated by the runtime; this file only validates the profile and
## classifies the player's input.

const INTENSITIES := ["soft", "firm", "rough"]
const PATTERNS := ["steady", "teasing", "quick"]
const TOUCHES := ["smack", "caress", "kiss"]
const TALKS := ["praise", "reassurance", "dirty", "curious", "playful"]
const WARMTHS := ["quick", "normal", "slow"]
const RECOVERY_MIN := 0
const RECOVERY_MAX := 80
const RECOVERY_DEFAULT := 20

const DEFAULTS := {
	"intensity": "firm",
	"pattern": "steady",
	"touch": [],
	"dislikes": [],
	"talk": [],
	"warmth": "normal",
	"recovery": RECOVERY_DEFAULT,
	"notes": "",
}

## Strength is travel x peak-speed factor from thrust.gd, clamped 0..1.
const SOFT_MAX := 0.33
const FIRM_MAX := 0.66
## The pattern classifier is intentionally a small, readable window, not a curve fit.
const PATTERN_MIN_STROKES := 3
const TEASE_TRAVEL := 0.38
const TEASE_DURATION := 0.75
const QUICK_DURATION := 0.42
const QUICK_TRAVEL := 0.62


static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


## Merge an arbitrary taste block with the defaults and validate it. Unknown values fall back
## to the neutral default rather than failing an act.
static func resolve(raw: Variant) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	if raw is Dictionary:
		out = _merge(out, raw)
	out["intensity"] = _enum(str(out.get("intensity", "firm")).to_lower(), INTENSITIES, "firm")
	out["pattern"] = _enum(str(out.get("pattern", "steady")).to_lower(), PATTERNS, "steady")
	out["touch"] = _clean_list(out.get("touch"), TOUCHES)
	out["dislikes"] = _clean_list(out.get("dislikes"), TOUCHES + TALKS)
	out["talk"] = _clean_list(out.get("talk"), TALKS)
	out["warmth"] = _enum(str(out.get("warmth", "normal")).to_lower(), WARMTHS, "normal")
	out["recovery"] = clampi(int(out.get("recovery", RECOVERY_DEFAULT)), RECOVERY_MIN, RECOVERY_MAX)
	out["notes"] = str(out.get("notes", "")).strip_edges()
	# A liked item cannot also be disliked.
	var dislikes: Array = []
	for key: Variant in out["dislikes"]:
		if not (key in out["touch"] or key in out["talk"]):
			dislikes.append(key)
	out["dislikes"] = dislikes
	return out


## "soft", "firm" or "rough" from a closed stroke's strength.
static func intensity_for(strength: float) -> String:
	var value := clampf(strength, 0.0, 1.0)
	if value < SOFT_MAX:
		return "soft"
	if value < FIRM_MAX:
		return "firm"
	return "rough"


## Classify the last few inward strokes as one rhythm. Needs at least three strokes; the
## runtime treats an empty result as "no pattern yet" and only scores the intensity axis.
static func pattern_for(strokes: Array) -> String:
	if strokes.size() < PATTERN_MIN_STROKES:
		return ""
	var travel_total := 0.0
	var duration_total := 0.0
	for index in strokes.size():
		var stroke: Variant = strokes[index]
		if not stroke is Dictionary:
			return ""
		var travel := float((stroke as Dictionary).get("travel", 0.0))
		var duration := maxf(0.001, float((stroke as Dictionary).get("duration", 0.001)))
		travel_total += travel
		duration_total += duration
	var count := float(strokes.size())
	var mean_travel := travel_total / count
	var mean_duration := duration_total / count
	if mean_travel < TEASE_TRAVEL and mean_duration > TEASE_DURATION:
		return "teasing"
	if mean_duration < QUICK_DURATION and mean_travel < QUICK_TRAVEL:
		return "quick"
	return "steady"


## One short category for the player's words. Returns "" when nothing matches. This is a
## classifier, not a parser: the AI still writes her reply, and the category only decides
## whether the line landed with her taste.
static func classify_talk(text: String) -> String:
	var lower := text.to_lower().strip_edges()
	if lower.is_empty():
		return ""
	if _has_any(lower, ["are you okay", "you okay", "with me", "safe", "gentle", "slow down",
			"careful", "look at me", "you alright", "too much"]):
		return "reassurance"
	if _has_any(lower, ["good girl", "brat", "tease", "beg", "maybe", "proud of you"]):
		return "playful"
	if _has_any(lower, ["love you", "beautiful", "perfect", "amazing", "pretty", "gorgeous",
			"best", "proud", "wonderful", "good girl", "so good"]):
		return "praise"
	if _has_any(lower, ["how ", "what ", "tell me", "do you", "feel", "like it", "want me",
			"what do you"]):
		return "curious"
	if _has_any(lower, ["want", "more", "harder", "please", "inside", "take", "mine", "need"]):
		return "dirty"
	if lower.contains("?"):
		return "curious"
	return ""


## Human-readable private taste for the utterance prompt. No numbers, no units.
static func describe(taste: Dictionary) -> String:
	var parts: PackedStringArray = []
	parts.append("intensity: %s" % str(taste.get("intensity", "firm")))
	parts.append("rhythm: %s" % str(taste.get("pattern", "steady")))
	var touch := _names(taste.get("touch", []))
	if not touch.is_empty():
		parts.append("likes touch: %s" % touch)
	var dislikes := _names(taste.get("dislikes", []))
	if not dislikes.is_empty():
		parts.append("dislikes: %s" % dislikes)
	var talk := _names(taste.get("talk", []))
	if not talk.is_empty():
		parts.append("likes talk: %s" % talk)
	var warmth := str(taste.get("warmth", "normal"))
	if warmth != "normal":
		parts.append("warmth: %s" % warmth)
	var recovery := int(taste.get("recovery", RECOVERY_DEFAULT))
	if recovery >= 30:
		parts.append("recovers quickly after climax")
	elif recovery <= 12:
		parts.append("needs coaxing after climax")
	var notes := str(taste.get("notes", "")).strip_edges()
	if not notes.is_empty():
		parts.append("attitude: " + notes)
	return "\n".join(parts)


static func warmth_scale(taste: Dictionary) -> float:
	match str(taste.get("warmth", "normal")):
		"quick":
			return 1.25
		"slow":
			return 0.8
	return 1.0


static func _enum(value: String, allowed: Array, fallback: String) -> String:
	return value if value in allowed else fallback


static func _clean_list(value: Variant, allowed: Array) -> Array:
	var out: Array = []
	if not value is Array:
		return out
	for item: Variant in value:
		var key := str(item).to_lower()
		if key in allowed and not out.has(key):
			out.append(key)
	return out


static func _names(value: Variant) -> String:
	if not value is Array or (value as Array).is_empty():
		return ""
	var names: PackedStringArray = []
	for item: Variant in value:
		names.append(str(item))
	return ", ".join(names)


static func _has_any(text: String, needles: Array) -> bool:
	for needle: String in needles:
		if text.contains(needle):
			return true
	return false


static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for key: Variant in over:
		var value: Variant = over[key]
		if value is Dictionary and out.get(key) is Dictionary:
			out[key] = _merge(out[key], value)
		else:
			out[key] = value
	return out
