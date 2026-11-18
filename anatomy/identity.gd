extends RefCounted
## Pure anatomy helpers: the shared body profile and the off-roster id list. It reads no Node,
## scene or settings file; `anatomy/service.gd` supplies the live values. The body profile itself
## is `shared/body_profile.gd`, so the act camera can measure the same body without importing this
## private module. The stable pony id is `shared/pony_id.gd`.
##
## The adult capability is not here: the eligibility facade owns it and the anatomy facade asks
## `eligible(pony, Target.ANATOMY)`.
##
## See `docs/anatomy.md` (`## Attachment and identity`).

const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")


## The princess body profile, or an empty array for an ordinary body.
static func body_profile(identity: Variant) -> Array:
	return BODY_PROFILE.body_profile(identity)


## The body-fit key a placement row resolves against.
static func body_fit_id(pony: Variant) -> String:
	return BODY_PROFILE.body_fit_id(pony)


## The profile of the body a pony is wearing now.
static func body_profile_for(pony: Variant) -> Array:
	return BODY_PROFILE.body_profile_for(pony)


## The typed rig of the body a pony is wearing now.
static func rig_profile_for(pony: Variant) -> BODY_PROFILE.RigProfile:
	return BODY_PROFILE.rig_for_pony(pony)


## Deduplicated ids that are not in the base roster. The caller owns the eligibility filter, the
## live-pony source and its ordering; this helper only filters and deduplicates.
static func off_roster_ids(ids: Array[String], base_ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id: String in ids:
		if id.is_empty() or id in base_ids or out.has(id):
			continue
		out.append(id)
	return out
