extends RefCounted
## integration: per-mare participation. Which unfplap capabilities a mare takes part in.
##
## It is subtractive: a `true` value means "does not veto", never "grants". The block lives in the
## character template, beside a provider's `eligible` assertion.

## The capability keys. One table drives the capability reads and the Characters form.
const KEYS := ["acts", "anatomy"]
## Accepted, validated and returned, but no capability reads them: retired keys stay in the API.
const DEPRECATED_KEYS := ["tail"]
const LABELS := {
	"acts": "Acts",
	"anatomy": "Anatomy",
}


## Every key a profile may carry, capability and deprecated.
static func all_keys() -> Array[String]:
	var out: Array[String] = []
	out.append_array(KEYS)
	out.append_array(DEPRECATED_KEYS)
	return out


## The built-in default: every capability is allowed.
static func defaults() -> Dictionary:
	var out: Dictionary = {}
	for key: String in all_keys():
		out[key] = true
	return out


## A complete profile with the provider's partial values applied over the defaults.
static func resolve(over: Variant) -> Dictionary:
	var out := defaults()
	if over is Dictionary:
		for key: String in all_keys():
			if (over as Dictionary).has(key):
				var value: Variant = (over as Dictionary)[key]
				if value is bool:
					out[key] = bool(value)
	return out


## Only the known keys, as booleans. A wrong type is dropped.
static func clean(values: Variant) -> Dictionary:
	var out: Dictionary = {}
	if values is Dictionary:
		for key: String in all_keys():
			if (values as Dictionary).has(key):
				var value: Variant = (values as Dictionary)[key]
				if value is bool:
					out[key] = bool(value)
	return out


## True when a capability is allowed. A missing key means the default.
static func allows(profile: Dictionary, key: String) -> bool:
	var value: Variant = profile.get(key, true)
	if not value is bool:
		return true
	return bool(value)
