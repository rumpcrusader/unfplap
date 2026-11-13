extends RefCounted
## Pure anatomy helpers: the princess body profile and the off-roster id list. It reads no Node,
## scene or settings file; `anatomy/service.gd` supplies the live values. The stable pony id is
## `shared/pony_id.gd`.
##
## The adult capability is not here: the eligibility facade owns it and the anatomy facade asks
## `eligible(pony, Target.ANATOMY)`.
##
## See `docs/anatomy.md` (`## Attachment and identity`).

## The princess body scale and placement anchor for a known character. A modded copy can set
## `character_id` to the canon pony whose body it uses; otherwise the identity id is the key.
const WINKING_BODIES := {
	"celestia": [0.853, 0.3329, 1.67],
	"luna": [0.596, 0.2265, 1.095],
}


## The princess body profile, or an empty array for an ordinary body. A modded copy is matched by
## `character_id` first, then by its own identity id.
static func body_profile(identity: Variant) -> Array:
	if identity == null:
		return []
	var character: Variant = identity.get("character_id")
	var key := str(character) if character != null else ""
	if key.is_empty():
		var identity_id: Variant = identity.get("id")
		key = str(identity_id) if identity_id != null else ""
	var profile: Variant = WINKING_BODIES.get(key, [])
	return profile.duplicate() if profile is Array else []


## Deduplicated ids that are not in the base roster. The caller owns the eligibility filter, the
## live-pony source and its ordering; this helper only filters and deduplicates.
static func off_roster_ids(ids: Array[String], base_ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id: String in ids:
		if id.is_empty() or id in base_ids or out.has(id):
			continue
		out.append(id)
	return out
