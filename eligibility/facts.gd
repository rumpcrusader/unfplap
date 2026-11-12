extends RefCounted
## Pure eligibility fact schema and identity predicates. This file has no scene access: the shell
## `eligibility.gd` builds the dictionary and the policy reads it.
##
## Facts are a per-call snapshot. They are never saved, cached across frames or added to the
## per-character profile. See `docs/eligibility.md`.

const KEYS := [
	"id", "has_identity", "is_player_pony", "is_filly", "is_stallion",
	"adult", "participation",
	"has_relationship", "registered_adult", "romance_eligible",
	"stage", "love_level", "willing", "stored_bond", "bond_stage",
	"promiscuity", "sex_start", "public_feature",
	"player_young", "player_pony",
	"cycle_phase", "cycle_allows", "heat",
	"history", "consent",
]


## A fresh fact dictionary with every key present. Nested dictionaries are new each call.
static func empty() -> Dictionary:
	return {
		"id": "",
		"has_identity": false,
		"is_player_pony": false,
		"is_filly": false,
		"is_stallion": false,
		"adult": null,
		"participation": {"acts": true, "anatomy": true, "tail": true},
		"has_relationship": false,
		"registered_adult": false,
		"romance_eligible": false,
		"stage": "",
		"love_level": -1,
		"willing": false,
		"stored_bond": false,
		"bond_stage": "",
		"promiscuity": "any",
		"sex_start": "try_luck",
		"public_feature": true,
		"player_young": true,
		"player_pony": false,
		"cycle_phase": "normal",
		"cycle_allows": false,
		"heat": false,
		"history": {
			"tier": "steady",
			"hurt": 0,
			"comfort": 0,
			"blocks_start": false,
			"blocks_offers": false,
			"offer_weight": 0.0,
		},
		"consent": {"public": false, "anal": false, "oral": false},
	}


## Merge a raw dictionary into the schema. Missing keys keep the empty defaults; nested
## dictionaries merge one level so a partial history or consent block stays usable.
static func normalize(raw: Variant) -> Dictionary:
	var out := empty()
	if not raw is Dictionary:
		return out
	var source: Dictionary = raw
	for key: Variant in source.keys():
		var name := str(key)
		if not out.has(name):
			continue
		var value: Variant = source[key]
		if out[name] is Dictionary and value is Dictionary:
			var merged: Dictionary = (out[name] as Dictionary).duplicate(true)
			for sub: Variant in (value as Dictionary).keys():
				merged[str(sub)] = (value as Dictionary)[sub]
			out[name] = merged
		else:
			out[name] = value
	return out


## An adult pony is any identified pony that is not a filly or colt (the game's `filly` age flag)
## and is not the player's own pony. A provider's `adult` assertion overrides the identity's age
## flag; `null` means the identity decides. Stallions are adults here; use `adult_mare_identity`
## for the act-target, anatomy and tail predicate.
static func adult_pony_identity(identity: Variant, is_player_pony := false,
		adult: Variant = null) -> bool:
	if identity == null or is_player_pony:
		return false
	if adult is bool:
		return adult
	return not bool(identity.get("filly"))


## An adult mare is an adult pony that is not a stallion. This is the act target and the anatomy
## and tail seat target. The `adult` override changes age, not sex.
static func adult_mare_identity(identity: Variant, is_player_pony := false,
		adult: Variant = null) -> bool:
	if not adult_pony_identity(identity, is_player_pony, adult):
		return false
	return not bool(identity.get("stallion"))


## True for the game's young age flag. Used for young witness wording, not for eligibility.
static func young_identity(identity: Variant) -> bool:
	return identity != null and bool(identity.get("filly"))
