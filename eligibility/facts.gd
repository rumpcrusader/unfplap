extends RefCounted
## Pure eligibility fact schema and identity predicates. This file has no scene access: the shell
## `eligibility/service.gd` builds the dictionary and the policy reads it.
##
## Facts are a per-call snapshot. They are never saved, cached across frames or added to the
## per-character profile. See `docs/eligibility.md`.

const PARTICIPATION := preload("res://mods/unfplap/shared/participation.gd")
const CONSENT := preload("res://mods/unfplap/shared/consent.gd")

## The pure age category. It matches the facade's public `Age` enum by value.
enum AgeKind { NONE, YOUNG, ADULT }

const KEYS := [
	"id", "has_identity", "is_player_pony", "is_filly", "is_stallion",
	"adult", "participation",
	"has_relationship", "registered_adult", "romance_eligible",
	"stage", "love_level", "willing",
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
		"participation": PARTICIPATION.defaults(),
		"has_relationship": false,
		"registered_adult": false,
		"romance_eligible": false,
		"stage": "",
		"love_level": -1,
		"willing": false,
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
		"consent": CONSENT.empty(),
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
## flag; `null` means the identity decides. Stallions are adults here; use `adult_mare` for the
## act-target, anatomy and tail predicate.
static func adult_pony(has_identity: bool, is_player_pony: bool, is_filly: bool,
		adult: Variant) -> bool:
	if not has_identity or is_player_pony:
		return false
	if adult is bool:
		return adult
	return not is_filly


## An adult mare is an adult pony that is not a stallion. This is the act target and the anatomy
## and tail seat target. The `adult` override changes age, not sex.
static func adult_mare(has_identity: bool, is_player_pony: bool, is_filly: bool,
		is_stallion: bool, adult: Variant) -> bool:
	if not adult_pony(has_identity, is_player_pony, is_filly, adult):
		return false
	return not is_stallion


## The witness age category, or `AgeKind.NONE` when she can be neither an adult nor a young
## witness. A provider's `adult` assertion wins over the identity flag in both directions.
static func age_kind(has_identity: bool, is_player_pony: bool, is_filly: bool,
		adult: Variant) -> int:
	if not has_identity or is_player_pony:
		return AgeKind.NONE
	if adult is bool and bool(adult):
		return AgeKind.ADULT
	if is_filly:
		return AgeKind.YOUNG
	if adult is bool:
		return AgeKind.NONE
	return AgeKind.ADULT
