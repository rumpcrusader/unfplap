extends RefCounted
## integration: per-mare participation. Which unfplap capabilities a mare takes part in.
##
## It is subtractive: a `true` value means "does not veto", never "grants". A provider's `adult`
## assertion is a separate provider-only field in the same profile block. The `profile` block
## lives in the character template: `characters.<id>.profile.participation` and, for a provider,
## `adult` at the top level. See `docs/eligibility.md`.

## The capability keys. One table drives validation, the Characters form and the API.
const KEYS := ["acts", "anatomy", "tail"]
const LABELS := {
	"acts": "Acts",
	"anatomy": "Anatomy",
	"tail": "Tail",
}


## The built-in default: every capability is allowed.
static func defaults() -> Dictionary:
	var out: Dictionary = {}
	for key: String in KEYS:
		out[key] = true
	return out


## A complete profile with the provider's partial values applied over the defaults.
static func resolve(over: Variant) -> Dictionary:
	var out := defaults()
	if over is Dictionary:
		for key: String in KEYS:
			if (over as Dictionary).has(key):
				var value: Variant = (over as Dictionary)[key]
				if value is bool:
					out[key] = bool(value)
	return out


## Only the known keys, as booleans. A wrong type is dropped.
static func clean(values: Variant) -> Dictionary:
	var out: Dictionary = {}
	if values is Dictionary:
		for key: String in KEYS:
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
