extends RefCounted
## One face moment's values, plus the typed shapes `shared/act_face.gd` answers with.
## Contract: `docs/face.md`.

## The live climax shape's inputs, gathered from the readiness meter. The facade owns the shape.
class ClimaxQuality extends RefCounted:
	var intensity_total := 0.0
	var intensity_right := 0.0
	var pattern_total := 0.0
	var pattern_right := 0.0
	var both_matches := 0.0
	var liked_touch := 0.0
	var liked_talk := 0.0
	var dislikes_total := 0
	var distress := 0.0
	var seeks_touch := false
	var seeks_talk := false
	var overwhelmed := false

	## The scorer's input dictionary; the interchange stops at this edge.
	func to_dict() -> Dictionary:
		return {
			"intensity_total": intensity_total,
			"intensity_right": intensity_right,
			"pattern_total": pattern_total,
			"pattern_right": pattern_right,
			"both_matches": both_matches,
			"liked_touch": liked_touch,
			"liked_talk": liked_talk,
			"dislikes_total": dislikes_total,
			"distress": distress,
			"seeks_touch": seeks_touch,
			"seeks_talk": seeks_talk,
			"overwhelmed": overwhelmed,
		}


## One act summary as the face reads it. `present` is false until a real summary fills it.
class Summary extends RefCounted:
	var present := false
	var stopped := false
	var tolerance := "normal"
	var severe := false
	var early := false
	var grade := "neutral"
	var mood := ""
	var reward := false
	var positive := false

	## Parse the scorer's dictionary once, at the face's edge.
	static func from_dict(value: Dictionary) -> Summary:
		var out := Summary.new()
		if value.is_empty():
			return out
		out.present = true
		out.stopped = bool(value.get("stopped", false))
		out.tolerance = str(value.get("tolerance", "normal"))
		out.severe = bool(value.get("severe", false))
		out.early = bool(value.get("early", false))
		out.grade = str(value.get("grade", "neutral"))
		out.mood = str(value.get("mood", ""))
		out.reward = bool(value.get("reward", false))
		out.positive = bool(value.get("positive", false))
		return out

	## The scorer's dictionary; an absent summary answers an empty one.
	func to_dict() -> Dictionary:
		if not present:
			return {}
		return {
			"stopped": stopped,
			"tolerance": tolerance,
			"severe": severe,
			"early": early,
			"grade": grade,
			"mood": mood,
			"reward": reward,
			"positive": positive,
		}


## The climax style's debug counters, for the debug log only.
class StyleDebug extends RefCounted:
	var score := 0.0
	var motion := 0.0
	var both := 0.0
	var affection := 0.0
	var engagement := 0.0
	var penalty := 0.0

	static func from_dict(value: Dictionary) -> StyleDebug:
		var out := StyleDebug.new()
		out.score = float(value.get("score", 0.0))
		out.motion = float(value.get("motion", 0.0))
		out.both = float(value.get("both", 0.0))
		out.affection = float(value.get("affection", 0.0))
		out.engagement = float(value.get("engagement", 0.0))
		out.penalty = float(value.get("penalty", 0.0))
		return out


## One moment's face plan. An empty plan means no act face for this moment.
class Plan extends RefCounted:
	var face := ""
	var hold_s := 0.0
	var fluster_s := 0.0
	var release_stare := false
	var style := ""
	var score := 0.0
	var style_debug: StyleDebug = null

	## Parse the pure planner's dictionary once, at the face's edge.
	static func from_dict(value: Dictionary) -> Plan:
		var out := Plan.new()
		out.face = str(value.get("face", ""))
		out.hold_s = float(value.get("hold_s", 0.0))
		out.fluster_s = float(value.get("fluster_s", 0.0))
		out.release_stare = bool(value.get("release_stare", false))
		out.style = str(value.get("style", ""))
		out.score = float(value.get("score", 0.0))
		var debug: Variant = value.get("style_debug", {})
		out.style_debug = StyleDebug.from_dict(debug if debug is Dictionary else {})
		return out


## The beat context, the lid tick and the debug row all read these fields.
var first_time := false
var tolerance := "normal"
var mode := "auto"
var quality: ClimaxQuality = null
var summary: Summary = null
var state := 0
var close_rewarded := false
var eyes_active := false
var hud_mood := ""
var base_mood := ""
var blush_arc := true
var stopped := false
var satisfied := 0.0
var aftercare_min := 10.0


## The dictionary `shared/act_face.gd` reads for this moment; the interchange stops at this edge.
func plan_data(moment: String) -> Dictionary:
	var data: Dictionary = {"first_time": first_time, "tolerance": tolerance}
	if moment == "climax":
		data["mode"] = mode
		data["quality"] = quality.to_dict() if quality != null else {}
	elif moment == "afterglow":
		data["summary"] = summary.to_dict() if summary != null else {}
	return data
