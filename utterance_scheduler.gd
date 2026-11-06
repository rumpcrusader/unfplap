extends RefCounted
## Pure admission policy for unprompted act lines. No scene access, no director access.
##
## One instance per act. The runtime owns the director call, the prompt text and the memory
## lookup; this module only decides whether a cue may become a line and which line owns the
## single slot. Reaction lines take the same slot, bypassing the pacing gates but keeping the
## 18 s shared gap and the release hold.

const UTTERANCE := preload("res://mods/unfplap/utterance.gd")

const CLOSE_AT := 65.0
const WANTING_AT := 40.0
## A base cue must hold still this long before it can become a line.
const CUE_STABLE_S := 2.0
## An event cue (liked/disliked touch or talk) is a moment, not a trend; it only needs to settle
## inside its 2.5 s override lifetime.
const CUE_OVERRIDE_STABLE_S := 0.5
const CUE_GAP_MIN_S := 8.0
const CUE_GAP_MAX_S := 30.0
## Mod-owned generated lines wait this long after the previous line was accepted, even when the
## director is free. Other systems keep their own scheduling.
const UTTERANCE_MIN_GAP_S := 18.0
## Demand lines ("She wants…"/"She needs…") get their own budget and repeat lock.
const DEMAND_LINE_GAP_S := 28.0
const DEMAND_REPEAT_S := 45.0
## A queued line that has not reached audio by this age is stale. The runtime drops it.
const CUE_MAX_AGE_S := 20.0
## Keep the slot reserved briefly after speech stops, so a split TTS reply cannot be interrupted.
const RELEASE_HOLD_S := 1.0

var cue_gap := 12.0
## Debug-overridable pacing. The constants above are the defaults; runtime.gd pushes the
## `cues.*` tunables into these fields at act start and on a live settings edit.
var base_stable_s := CUE_STABLE_S
var override_stable_s := CUE_OVERRIDE_STABLE_S
var utterance_gap_s := UTTERANCE_MIN_GAP_S
var demand_gap_s := DEMAND_LINE_GAP_S
var demand_repeat_s := DEMAND_REPEAT_S
var max_age_s := CUE_MAX_AGE_S
var release_hold_s := RELEASE_HOLD_S
## Why the last `admit_cue()` call returned false, for the runtime's debug log.
var last_reason := ""

var _last_cue_seen := ""
var _cue_changed_at := -1000.0
var _last_cue_text := ""
var _last_cue_line_at := -1000.0
var _last_utterance_at := -1000.0
var _last_demand_text := ""
var _last_demand_at := -1000.0
var _pending_key := ""
var _pending_kind := ""
var _pending_cue := ""
var _pending_until := 0.0
var _pending_at := 0.0
var _pending_override := false
var _done_key := ""
var _done_at := 0.0


func reset(now: float, gap: float) -> void:
	cue_gap = clampf(gap, CUE_GAP_MIN_S, CUE_GAP_MAX_S)
	_last_cue_seen = ""
	_cue_changed_at = now
	_last_cue_text = ""
	_last_cue_line_at = -1000.0
	_last_utterance_at = -1000.0
	_last_demand_text = ""
	_last_demand_at = -1000.0
	last_reason = ""
	_clear_slot()


## Her readiness band. Presentation only; the HUD and the cue prompt share it.
static func mood_for(readiness: float, overwhelmed: float) -> String:
	if overwhelmed > 0.0:
		return "overwhelmed"
	if readiness >= CLOSE_AT:
		return "close"
	if readiness >= WANTING_AT:
		return "wanting"
	return "warming"


## The base cue text from the taste axes. No units, no numbers, third person like the HUD.
static func base_cue(taste: Dictionary, overwhelmed: float, readiness: float,
		intensity: String, pattern: String) -> String:
	if overwhelmed > 0.0:
		return "She's overwhelmed."
	if readiness >= CLOSE_AT:
		return "She is close."
	var wanted_intensity := str(taste.get("intensity", "firm"))
	var intensity_match := not intensity.is_empty() and intensity == wanted_intensity
	if not intensity.is_empty() and not intensity_match:
		if wanted_intensity == "soft":
			return "She wants it softer."
		if wanted_intensity == "rough":
			return "She wants it harder."
		return "She wants it firmer." if intensity == "soft" else "She wants it softer."
	var wanted_pattern := str(taste.get("pattern", "steady"))
	var pattern_match := not pattern.is_empty() and pattern == wanted_pattern
	if not pattern.is_empty() and not pattern_match:
		match wanted_pattern:
			"teasing":
				return "She wants to be teased."
			"quick":
				return "She wants it quicker."
		return "She wants a steadier rhythm."
	if intensity_match and pattern_match:
		return "She likes that."
	return "She wants you to keep going."


static func is_demand(text: String) -> bool:
	return UTTERANCE.is_demand(text)


## True when no line owns the slot and none is waiting out its release hold.
func channel_free() -> bool:
	return _pending_key.is_empty() and _done_key.is_empty()


## Track when the visible cue last changed. Call every ACTIVE tick before `admit_cue`.
func observe_cue(now: float, cue: String) -> void:
	if cue == _last_cue_seen:
		return
	_last_cue_seen = cue
	_cue_changed_at = now


## Demand lines get the longer budget and a same-text repeat lock. Non-demands only use the
## shared utterance gap.
func demand_blocked(cue: String, now: float) -> bool:
	if not is_demand(cue):
		return false
	if now - _last_demand_at < demand_gap_s:
		return true
	return cue == _last_demand_text and now - _last_demand_at < demand_repeat_s


## Whether a cue may become a line. Pure: call `note_cue_queued` only after the director accepts.
## `last_reason` holds the blocking gate for the runtime's debug log.
func admit_cue(now: float, cue: String, is_override: bool) -> bool:
	last_reason = ""
	if not channel_free():
		last_reason = "channel"
		return false
	if cue == _last_cue_text:
		last_reason = "repeat"
		return false
	var stable := override_stable_s if is_override else base_stable_s
	if now - _cue_changed_at < stable:
		last_reason = "stable"
		return false
	if now - _last_cue_line_at < cue_gap:
		last_reason = "cue_gap"
		return false
	if now - _last_utterance_at < utterance_gap_s:
		last_reason = "utterance_gap"
		return false
	if demand_blocked(cue, now):
		last_reason = "demand"
		return false
	return true


func note_cue_queued(now: float, key: String, cue: String, demand: bool, is_override := false) -> void:
	_last_cue_text = cue
	_last_cue_line_at = now
	_last_utterance_at = now
	if demand:
		_last_demand_text = cue
		_last_demand_at = now
	_begin_slot(key, "cue", cue, now + max_age_s)
	_pending_override = is_override
	_pending_at = now


## Reactions always take the slot; they are not paced like cues, but they reset the shared gap so
## a cue does not follow immediately.
func note_reaction_queued(now: float, key: String, cue: String, until: float) -> void:
	_last_utterance_at = now
	_begin_slot(key, "reaction", cue, until)
	_pending_override = false
	_pending_at = now


func pending_key() -> String:
	return _pending_key


func pending_kind() -> String:
	return _pending_kind


func pending_until() -> float:
	return _pending_until


func pending_since() -> float:
	return _pending_at


func pending_cue() -> String:
	return _pending_cue


func pending_override() -> bool:
	return _pending_override


## The director reports the final sentence delivered. Keep the slot until speech actually stops.
## The delivered row is observed every frame, so only the first report sets the finish clock; a
## later repeat must not restart the release hold.
func note_finished(now: float, key: String) -> void:
	if key.is_empty() or key != _pending_key:
		return
	if _done_key == key:
		return
	_done_key = key
	_done_at = now


func release_ready(now: float) -> bool:
	return not _done_key.is_empty() and now - _done_at >= release_hold_s


func release() -> void:
	_clear_slot()


## The key whose age has run out, or "" while it is still fresh. The runtime decides whether the
## row is safe to drop (queued or generating) or must be left alone (already speaking).
func expired_key(now: float) -> String:
	if _pending_key.is_empty() or now <= _pending_until:
		return ""
	return _pending_key


func drop_pending() -> void:
	_clear_slot()


func _begin_slot(key: String, kind: String, cue: String, until: float) -> void:
	_pending_key = key
	_pending_kind = kind
	_pending_cue = cue
	_pending_until = until
	_done_key = ""
	_done_at = 0.0


func _clear_slot() -> void:
	_pending_key = ""
	_pending_kind = ""
	_pending_cue = ""
	_pending_until = 0.0
	_pending_at = 0.0
	_pending_override = false
	_done_key = ""
	_done_at = 0.0
