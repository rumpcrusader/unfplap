extends RefCounted
## Pure eligibility fact schema and identity predicates.
## The shell builds the dictionary and the policy reads it; this file has no scene access.
## Facts are a per-call snapshot, never cached or stored. See `docs/eligibility.md`.

const PARTICIPATION := preload("res://mods/unfplap/shared/participation.gd")
const CONSENT := preload("res://mods/unfplap/shared/consent.gd")

## The pure age category. It matches the facade's public `Age` enum by value.
enum AgeKind { NONE, YOUNG, ADULT }

const KEYS := [
	"id", "has_identity", "is_player_pony", "is_filly", "is_stallion",
	"eligible", "participation",
	"has_relationship", "registered_adult", "romance_eligible",
	"stage", "love_level", "willing",
	"promiscuity",
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
		"eligible": null,
		"participation": PARTICIPATION.defaults(),
		"has_relationship": false,
		"registered_adult": false,
		"romance_eligible": false,
		"stage": "",
		"love_level": -1,
		"willing": false,
		"promiscuity": "any",
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


## An adult: an identified body that is no filly or colt, and not the player's own.
## A provider's assertion overrides the age flag; stallions still count as adults.
static func adult_pony(has_identity: bool, is_player_pony: bool, is_filly: bool,
		eligible: Variant) -> bool:
	if not has_identity or is_player_pony:
		return false
	if eligible is bool:
		return eligible
	return not is_filly


## An adult mare is an adult pony that is not a stallion. This is the act target and the anatomy
## and tail seat target. The `eligible` override changes age, not sex.
static func adult_mare(has_identity: bool, is_player_pony: bool, is_filly: bool,
		is_stallion: bool, eligible: Variant) -> bool:
	if not adult_pony(has_identity, is_player_pony, is_filly, eligible):
		return false
	return not is_stallion


## None when she is neither a witness adult nor a young one.
## The provider assertion beats the identity flag either way.
static func age_kind(has_identity: bool, is_player_pony: bool, is_filly: bool,
		eligible: Variant) -> int:
	if not has_identity or is_player_pony:
		return AgeKind.NONE
	if eligible is bool and bool(eligible):
		return AgeKind.ADULT
	if is_filly:
		return AgeKind.YOUNG
	if eligible is bool:
		return AgeKind.NONE
	return AgeKind.ADULT
