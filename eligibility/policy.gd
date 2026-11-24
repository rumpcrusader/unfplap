extends RefCounted
## Pure eligibility capability predicates over plain values; `facts.gd` owns the adulthood
## decision. No Node, scene, Time, Settings or file access.

const FACTS := preload("res://mods/unfplap/eligibility/facts.gd")
const IDENTITY_RECORD := preload("res://mods/unfplap/eligibility/identity_record.gd")


static func adult_mare(facts: Dictionary) -> bool:
	return FACTS.adult_mare(bool(facts.get("has_identity", false)),
		bool(facts.get("is_player_pony", false)), bool(facts.get("is_filly", false)),
		bool(facts.get("is_stallion", false)), facts.get("eligible", null))


## Adult mare plus the target's participation veto; no key means identity alone.
## The Characters selector needs that, so an opted-out mare can be re-enabled.
static func participates(facts: Dictionary, key := "") -> bool:
	if not adult_mare(facts):
		return false
	if key.is_empty():
		return true
	return bool((facts.get("participation", {}) as Dictionary).get(key, true))


## The same read over the cached typed identity record, with no facts dictionary.
static func participates_identity(record: IDENTITY_RECORD.IdentityRecord, key := "") -> bool:
	if record == null:
		return false
	if not FACTS.adult_mare(record.has_identity, record.is_player_pony, record.is_filly,
			record.is_stallion, record.eligible_assertion()):
		return false
	if key.is_empty():
		return true
	return bool(record.participation.get(key, true))
