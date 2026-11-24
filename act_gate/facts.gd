extends RefCounted
## Pure act-gate fact schema. The service builds the dictionary and the policy reads it; facts are
## a per-call snapshot, never cached or stored.

const PARTICIPATION := preload("res://mods/unfplap/shared/participation.gd")
const CONSENT := preload("res://mods/unfplap/shared/consent.gd")

const KEYS := [
	"id", "eligible", "adult", "participation",
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
		"eligible": null,
		"adult": false,
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
