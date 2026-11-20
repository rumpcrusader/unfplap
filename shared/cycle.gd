extends RefCounted
## integration: each mare's monthly cycle, in game days:
## a week of heat, then two days turned off. Her id sets where she is in it, so ponies are not all
## in step and each keeps the same dates. The phase is derived, never saved.

const DEFAULTS_DATA := preload("res://mods/unfplap/shared/defaults_data.gd")
const PROMPT_TEXT := preload("res://mods/unfplap/shared/prompt_text.gd")

const HEAT := "heat"
const DIESTRUS := "diestrus"
const NORMAL := "normal"

const MONTH_DAYS := 30.0
const HEAT_DAYS := 7.0
const DIESTRUS_DAYS := 2.0

## Idle heat display: one wink every configured gap, sometimes in a burst. The roll is 5%
## triple, 25% double and 70% single.
const WINK_TRIPLE_BELOW := 0.05
const WINK_DOUBLE_BELOW := 0.30

## Debug-only session overrides, by pony id. Never saved, and honoured even with the feature off so
## the lab can test heat and diestrus without waiting in-game days.
static var _overrides: Dictionary = {}


## Stable per-mare offset in days, so the whole town does not cycle together.
static func offset(id: String) -> float:
	return float(absi(id.hash()) % int(MONTH_DAYS))


## Phase for a position in the cycle, wrapped at MONTH_DAYS.
static func phase_at(at: float) -> String:
	var day := fposmod(at, MONTH_DAYS)
	if day < HEAT_DAYS:
		return HEAT
	if day < HEAT_DAYS + DIESTRUS_DAYS:
		return DIESTRUS
	return NORMAL


## Phase for a world day and mare id.
static func phase(day: float, id: String) -> String:
	return phase_at(day + offset(id))


## She starts and offers sex in heat and normal, but not in diestrus.
static func allows_sex(phase_name: String) -> bool:
	return phase_name != DIESTRUS


## Seconds until the next idle heat wink. A reversed pair is sorted, so the two settings cannot
## produce an invalid range.
static func wink_interval(min_s: float, max_s: float) -> float:
	return randf_range(minf(min_s, max_s), maxf(min_s, max_s))


## Wink count for one idle burst. `roll` is a 0..1 random value.
static func wink_burst_count(roll: float) -> int:
	if roll < WINK_TRIPLE_BELOW:
		return 3
	if roll < WINK_DOUBLE_BELOW:
		return 2
	return 1


## Private note for the normal dialogue prompt. Empty in normal.
static func prompt_note(phase_name: String) -> String:
	if phase_name != HEAT and phase_name != DIESTRUS:
		return ""
	var rows: Dictionary = DEFAULTS_DATA.prompts_block("cycle")
	return PROMPT_TEXT.render(str(rows.get(phase_name, "")), {})


## The debug override in force for one pony, or "" when the automatic cycle owns the phase.
static func override_for(id: String) -> String:
	return str(_overrides.get(id, ""))


## Set one pony's session override, or clear it with "". Any other value is ignored.
static func set_override(id: String, phase_name: String) -> void:
	if phase_name in [HEAT, DIESTRUS, NORMAL]:
		_overrides[id] = phase_name
	elif phase_name.is_empty():
		_overrides.erase(id)
