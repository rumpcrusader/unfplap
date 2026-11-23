extends RefCounted
## One act's summary as the afterglow reads it; the scorer's dictionary is parsed at this edge.

## False until a real summary fills the record; an absent summary answers an empty dictionary.
var present := false
var grade := "neutral"
var mood := ""
var reward := false
var positive := false
var stopped := false
var severe := false
var early := false
var tolerance := "normal"


## Parse the scorer's dictionary once, at the phase's edge.
func fill(value: Dictionary) -> void:
	present = not value.is_empty()
	if not present:
		return
	grade = str(value.get("grade", "neutral"))
	mood = str(value.get("mood", ""))
	reward = bool(value.get("reward", false))
	positive = bool(value.get("positive", false))
	stopped = bool(value.get("stopped", false))
	severe = bool(value.get("severe", false))
	early = bool(value.get("early", false))
	tolerance = str(value.get("tolerance", "normal"))


## The scorer's dictionary for the afterglow beat pool; an absent summary answers an empty one.
func to_dict() -> Dictionary:
	if not present:
		return {}
	return {
		"grade": grade,
		"mood": mood,
		"reward": reward,
		"positive": positive,
		"stopped": stopped,
		"severe": severe,
		"early": early,
		"tolerance": tolerance,
	}
