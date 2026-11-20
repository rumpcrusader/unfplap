extends RefCounted
## Pure anatomy helpers: the shared body profile and the off-roster id list, without a Node,
## scene or settings read.
## The adult capability is not here; the eligibility facade owns it.
## See `docs/anatomy.md` (`## Attachment and identity`).

const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")


## The princess body profile, or an empty array for an ordinary body.
static func body_profile(identity: Resource) -> Array[float]:
	return _floats(BODY_PROFILE.body_profile(identity))


## The body-fit key a placement row resolves against.
static func body_fit_id(pony: Node) -> String:
	return BODY_PROFILE.body_fit_id(pony)


## The worn body's profile, from its form when one is stored.
static func body_profile_for(pony: Node) -> Array[float]:
	return _floats(BODY_PROFILE.body_profile_for(pony))


## The worn body's typed rig.
static func rig_profile_for(pony: Node) -> BODY_PROFILE.RigProfile:
	return BODY_PROFILE.rig_for_pony(pony)


## Off-roster ids, deduplicated; the caller owns the filter, the source and the order.
static func off_roster_ids(ids: Array[String], base_ids: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for id: String in ids:
		if id.is_empty() or id in base_ids or out.has(id):
			continue
		out.append(id)
	return out


static func _floats(values: Array) -> Array[float]:
	var out: Array[float] = []
	for value: Variant in values:
		out.append(float(value))
	return out
