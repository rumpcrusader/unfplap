extends RefCounted
## Pure act HUD text: the cue/hearts line, the readiness/preference line, the auto readout and the
## `End` tint. `hud/service.gd` renders the card; the runtime gathers the live values and calls these.
## Contract: `docs/hud.md`.

## The Y hint's `End` shade: one step per climax, capped below full so only the earned afterglow
## caress turns it fully pink.
const Y_END_TINT_MAX := 0.75

const STATE_ACTIVE := 2
const STATE_CLIMAX := 3
const STATE_AFTERGLOW := 4


## Hearts, cue, then the close/summary segment. The close prompt is kept in afterglow even when
## the optional readouts are off.
static func cue_line(state: int, pony_climaxes: int, max_climaxes: int, cue_text: String,
		close_text: String, summary_hud: String, show_readouts: bool) -> String:
	if state not in [STATE_ACTIVE, STATE_CLIMAX, STATE_AFTERGLOW]:
		return ""
	var hearts := "❤ %d/∞" % pony_climaxes if max_climaxes <= 0 \
		else "❤ %d/%d" % [pony_climaxes, max_climaxes]
	var parts: PackedStringArray = [hearts]
	var text := cue_text.strip_edges()
	var closing := state == STATE_AFTERGLOW
	if closing:
		if not close_text.is_empty():
			text = close_text
		elif not summary_hud.is_empty():
			text = summary_hud
	if show_readouts or closing:
		parts.append(text if not text.is_empty() else "—")
	return " | ".join(parts)


## Separate readiness/preference line under the cue. In the afterglow it carries the act summary
## when the cue already shows the standing close prompt.
static func readiness_line(state: int, readouts: bool, last_intensity: String,
		last_pattern: String, want_intensity: String, want_pattern: String, heat: bool,
		close_text: String, summary_hud: String) -> String:
	if state == STATE_AFTERGLOW:
		if summary_hud.is_empty() or close_text.is_empty():
			return ""
		return summary_hud
	if not readouts or state not in [STATE_ACTIVE, STATE_CLIMAX]:
		return ""
	var have_intensity := last_intensity if not last_intensity.is_empty() else "—"
	var have_pattern := last_pattern if not last_pattern.is_empty() else "—"
	var line := "Wants: %s & %s | You: %s & %s" % [
		want_intensity, want_pattern, have_intensity, have_pattern]
	return line + " | In heat" if heat else line


## The auto settings readout under the readiness line. Empty while manual.
static func auto_text(min_depth: float, max_depth: float, pace: float,
		shape_name: String) -> String:
	return "Auto · %d–%d%% · %.2f/s · %s" % [
		roundi(min_depth * 100.0), roundi(max_depth * 100.0), pace, shape_name]


## Pink shade for the control card's `End`. The standing afterglow caress earns full pink.
static func y_pink(standing: bool, afterglow: bool, close_earned: bool, pony_climaxes: int,
		max_climaxes: int) -> float:
	if standing and afterglow and close_earned:
		return 1.0
	var reference := float(max_climaxes) if max_climaxes > 0 else 3.0
	return clampf(float(pony_climaxes) / reference, 0.0, 1.0) * Y_END_TINT_MAX


## One hold-X layer row's live text.
static func auto_panel_label(kind: String, min_depth: float, max_depth: float, pace: float,
		shape_name: String) -> String:
	match kind:
		"min":
			return "Min depth %d%%" % roundi(min_depth * 100.0)
		"max":
			return "Max depth %d%%" % roundi(max_depth * 100.0)
		"pace":
			return "Pace %.2f/s" % pace
		"shape":
			return "Shape: %s" % shape_name
	return ""
