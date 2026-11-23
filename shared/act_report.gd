extends RefCounted
## The two cross-mod act payloads: one live progress snapshot and one committed result. The
## human contract is `docs/api.md`.

const SCHEMA := 1

## One live act snapshot, built at a change and emitted as plain data.
class Progress extends RefCounted:
	var act_id := 0
	var state := ""
	var pony_id := ""
	var form_id := ""
	var pose := ""
	var duration_s := 0.0
	var mood := ""
	var climaxes: Dictionary = {}
	var heat := false

	func to_dict() -> Dictionary:
		return {
			"schema": SCHEMA,
			"act_id": act_id,
			"state": state,
			"pony_id": pony_id,
			"form_id": form_id,
			"pose": pose,
			"duration_s": duration_s,
			"mood": mood,
			"climaxes": climaxes.duplicate(true),
			"heat": heat,
		}


## The one committed outcome of an act, built where the summary is written.
class Result extends RefCounted:
	var act_id := 0
	var pony_id := ""
	var form_id := ""
	var forms: Array[String] = []
	var pose := ""
	var duration_s := 0.0
	var thrusts := 0
	var climaxes: Dictionary = {}
	var grade := ""
	var stop_reasons: Array[String] = []
	var outcome: Dictionary = {}

	func to_dict() -> Dictionary:
		return {
			"schema": SCHEMA,
			"act_id": act_id,
			"pony_id": pony_id,
			"form_id": form_id,
			"forms": forms.duplicate(),
			"pose": pose,
			"duration_s": duration_s,
			"thrusts": thrusts,
			"climaxes": climaxes.duplicate(true),
			"grade": grade,
			"stop_reasons": stop_reasons.duplicate(),
			"outcome": outcome.duplicate(true),
		}
