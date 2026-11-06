extends RefCounted
## integration: ported from PonyPussyParadise cycle.gd. Each mare's monthly cycle, in game days:
## a week of heat, then two days turned off. Her id sets where she is in it, so ponies are not all
## in step and each keeps the same dates. The phase is derived, never saved.

const HEAT := "heat"
const DIESTRUS := "diestrus"
const NORMAL := "normal"

const MONTH_DAYS := 30.0
const HEAT_DAYS := 7.0
const DIESTRUS_DAYS := 2.0


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


## Private note for the normal dialogue prompt. Empty in normal.
static func prompt_note(phase_name: String) -> String:
	match phase_name:
		HEAT:
			return "- You are in heat this week. You are restless and warm, it is hard to think about much else, and you want Anon more than usual. Let it colour how you act around him."
		DIESTRUS:
			return "- Your heat has just ended and you are completely turned off for a couple of days. You feel irritable and touchy, and you turn down anything sexual, though you are still fond of Anon."
	return ""
