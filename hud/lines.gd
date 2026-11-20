extends RefCounted
## Pure act HUD text: cue, readiness, auto readout and `End` tint.
## Contract: `docs/hud.md`

## The act-key hint's `End` shade: one step per climax, capped below full so only the earned afterglow
## caress turns it fully pink.
const Y_END_TINT_MAX := 0.75

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const STATE_ACTIVE := ACT_STATE.State.ACTIVE
const STATE_CLIMAX := ACT_STATE.State.CLIMAX
const STATE_AFTERGLOW := ACT_STATE.State.AFTERGLOW


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


## The second readout line; afterglow moves the summary here.
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


## The cue/hearts line from the typed act view.
static func cue_line_for(view: Variant, show_readouts: bool) -> String:
	return cue_line(int(view.state), int(view.pony_climaxes), int(view.max_pony_climaxes),
		str(view.cue), str(view.close_hint), str(view.summary_hud), show_readouts)


## The readiness/preference line from the typed act view.
static func readiness_line_for(view: Variant, show_readouts: bool) -> String:
	return readiness_line(int(view.state), show_readouts, str(view.last_intensity),
		str(view.last_pattern), str(view.preferences.get("intensity", "firm")),
		str(view.preferences.get("pattern", "steady")), bool(view.cycle_heat),
		str(view.close_hint), str(view.summary_hud))


## The auto readout from the typed act view, or "" while manual.
static func auto_text_for(view: Variant, shape_label: String) -> String:
	if not bool(view.auto_on):
		return ""
	return auto_text(float(view.auto_min_depth), float(view.auto_max_depth),
		float(view.auto_pace), shape_label)


## The control card's `End` tint from the typed act view's raw fields.
static func y_pink_for(view: Variant) -> float:
	var pose_view: Variant = view.pose_view
	var standing := pose_view != null and str(pose_view.family) == "standing"
	return y_pink(standing, int(view.state) == STATE_AFTERGLOW, bool(view.close_earned),
		int(view.pony_climaxes), int(view.max_pony_climaxes))
