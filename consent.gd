extends RefCounted
## integration: per-mare consent for the optional anatomy actions. Public consent is opt-in: no
## mare offers sex with others around until the player enables it for her. Anal and oral are
## deterministic from her id so a fresh save always gives the same mare the same answer until the
## player edits it.

const ANAL_PERCENT := 60
const ORAL_PERCENT := 75


static func defaults(id: String) -> Dictionary:
	return {
		"public": false,
		"anal": absi((id + "anal").hash()) % 100 < ANAL_PERCENT,
		"oral": absi((id + "oral").hash()) % 100 < ORAL_PERCENT,
	}


static func resolve(id: String, over: Variant) -> Dictionary:
	var out := defaults(id)
	if over is Dictionary:
		for key: String in ["public", "anal", "oral"]:
			if (over as Dictionary).has(key):
				out[key] = bool((over as Dictionary)[key])
	return out


static func value(id: String, key: String) -> bool:
	return bool(defaults(id).get(key, false))


static func clean(values: Variant) -> Dictionary:
	var out: Dictionary = {}
	if values is Dictionary:
		for key: String in ["public", "anal", "oral"]:
			if (values as Dictionary).has(key):
				out[key] = bool((values as Dictionary)[key])
	return out
