extends RefCounted
## Pure eligibility fact schema: the identity half and the adulthood predicates.
## The shell builds the dictionary and the policy reads it; this file has no scene access.
## Facts are a per-call snapshot, never cached or stored. See `docs/eligibility.md`.

const PARTICIPATION := preload("res://mods/unfplap/shared/participation.gd")

## The pure age category. It matches the facade's public `Age` enum by value.
enum AgeKind { NONE, YOUNG, ADULT }


## A fresh identity fact dictionary. The participation block is new each call.
static func empty() -> Dictionary:
	return {
		"id": "",
		"has_identity": false,
		"is_player_pony": false,
		"is_filly": false,
		"is_stallion": false,
		"eligible": null,
		"participation": PARTICIPATION.defaults(),
	}


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
