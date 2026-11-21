extends "res://mods/unfplap/tests/support/suite.gd"
## Pure eligibility identity: adults, capability targets, the typed identity record and witness
## age. No world or user:// file is touched.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/eligibility/test_eligibility.gd

const FACTS := preload("res://mods/unfplap/eligibility/facts.gd")
const POLICY := preload("res://mods/unfplap/eligibility/policy.gd")
const IDENTITY_RECORD := preload("res://mods/unfplap/eligibility/identity_record.gd")



func facts(over: Dictionary = {}) -> Dictionary:
	var out := FACTS.empty()
	out["id"] = "rarity"
	out["has_identity"] = true
	out["is_player_pony"] = false
	out["is_filly"] = false
	out["is_stallion"] = false
	out["has_relationship"] = true
	out["registered_adult"] = true
	out["romance_eligible"] = true
	out["stage"] = "dating"
	out["love_level"] = 2
	out["willing"] = true
	out["promiscuity"] = "any"
	out["player_young"] = false
	out["player_pony"] = false
	out["cycle_phase"] = "normal"
	out["cycle_allows"] = true
	out["heat"] = false
	out["history"] = {
		"tier": "steady", "hurt": 0, "comfort": 0,
		"blocks_start": false, "blocks_offers": false, "offer_weight": 0.7,
	}
	out["consent"] = {"public": false, "anal": true, "oral": true}
	for key: Variant in over.keys():
		var name := str(key)
		if out[name] is Dictionary and over[key] is Dictionary:
			var merged: Dictionary = (out[name] as Dictionary).duplicate(true)
			for sub: Variant in (over[key] as Dictionary).keys():
				merged[str(sub)] = (over[key] as Dictionary)[sub]
			out[name] = merged
		else:
			out[name] = over[key]
	return out


func run() -> void:
	check(POLICY.adult_pony(facts()), "an identified adult pony")
	check(POLICY.adult_mare(facts()), "an adult mare")
	check(not POLICY.adult_mare(facts({"is_stallion": true})),
		"stallion is not an adult mare")
	check(not POLICY.adult_pony(facts({"is_filly": true})), "filly is not adult")
	check(not POLICY.adult_pony(facts({"is_player_pony": true})),
		"player pony is not a target")
	# The pure predicate takes values, so the live rule has exactly one definition.
	check(FACTS.adult_mare(true, false, false, false, null),
		"the pure predicate accepts an adult mare")
	check(not FACTS.adult_mare(true, false, false, true, null),
		"the pure predicate rejects a stallion")
	check(not FACTS.adult_pony(false, false, false, null),
		"the pure predicate needs an identity")

	# Capability targets: an adult mare plus the named participation veto. An empty key is the
	# identity-only character target, which must keep an opted-out mare editable.
	var mare := facts()
	check(POLICY.participates(mare, "acts"), "an adult mare is an act target")
	check(POLICY.participates(mare, "anatomy") and POLICY.participates(mare, "tail"),
		"an adult mare is an anatomy and tail target")
	check(POLICY.participates(mare, ""), "the character target has no participation veto")
	check(not POLICY.participates(facts({"participation": {"acts": false}}), "acts"),
		"the act target respects the participation veto")
	check(POLICY.participates(facts({"participation": {"acts": false}}), ""),
		"an opt-out keeps the character target")
	check(not POLICY.participates(facts({"is_stallion": true}), "acts"),
		"a stallion is no target")
	check(not POLICY.participates(facts({"has_identity": false}), "acts"),
		"no identity is no target")

	# The typed record answers the same predicate without a facts dictionary.
	var typed := IDENTITY_RECORD.IdentityRecord.new()
	typed.id = "rarity"
	typed.has_identity = true
	typed.participation = {"acts": true, "anatomy": true, "tail": true}
	check(POLICY.participates_identity(typed, "acts"), "the typed record is an act target")
	check(POLICY.participates_identity(typed, ""), "the typed record has a character target")
	typed.participation = {"acts": false}
	check(not POLICY.participates_identity(typed, "acts"),
		"the typed record respects the participation veto")
	check(POLICY.participates_identity(typed, ""), "an opt-out keeps the typed character target")
	typed.participation = {}
	typed.is_stallion = true
	check(not POLICY.participates_identity(typed, ""), "a stallion is no typed target")
	typed.is_stallion = false
	typed.has_eligible_assertion = true
	typed.eligible = false
	check(not POLICY.participates_identity(typed, ""), "a provider veto closes the typed record")
	check(not POLICY.participates_identity(null, ""), "no record is no target")

	# Witness age categories. A provider's `eligible` assertion wins over the identity flag.
	check(POLICY.age_kind(mare) == FACTS.AgeKind.ADULT,
		"an adult mare witnesses as an adult")
	check(POLICY.age_kind(facts({"is_filly": true})) == FACTS.AgeKind.YOUNG,
		"a filly witnesses as young")
	check(POLICY.age_kind(facts({"is_filly": true, "eligible": true})) == FACTS.AgeKind.ADULT,
		"a provider's eligible assertion makes a filly an adult witness")
	check(POLICY.age_kind(facts({"eligible": false})) == FACTS.AgeKind.NONE,
		"a vetoed adult is neither an adult nor a young witness")
	check(POLICY.age_kind(facts({"is_player_pony": true})) == FACTS.AgeKind.NONE,
		"the player pony is not a witness")

	if failures == 0:
		print("ELIGIBILITY_PASS")
	finish()
