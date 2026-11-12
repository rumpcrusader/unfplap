extends RefCounted
## Pure anatomy identity helpers: the stable pony id, the adult-mare attachment predicate, the
## princess body profile and the off-roster id list. It reads no Node, scene or settings file;
## `anatomy.gd` supplies the live values.
##
## See `docs/anatomy.md` (`## Attachment and identity`).

const FACTS := preload("res://mods/unfplap/eligibility/facts.gd")

## The princess body scale and placement anchor for a known character. A modded copy can set
## `character_id` to the canon pony whose body it uses; otherwise the identity id is the key.
const WINKING_BODIES := {
	"celestia": [0.853, 0.3329, 1.67],
	"luna": [0.596, 0.2265, 1.095],
}


## The mod's stable id for a pony: relationship metadata first, then the identity. This mirrors
## `runtime._read_id()` so placement and preferences key off the same value.
static func id_for(meta_id: String, identity: Variant) -> String:
	if not meta_id.is_empty():
		return meta_id
	return str(identity.get("id")) if identity != null else ""


## Every adult mare gets anatomy: the identity filly/stallion flags are the age gate, the
## player's own pony never gets it, and the pony needs a stable id for the per-mare placement. A
## provider's `adult` assertion overrides the identity's age flag; `null` means the identity decides.
static func eligible(identity: Variant, is_player_pony: bool, id: String,
		adult: Variant = null) -> bool:
	return FACTS.adult_mare_identity(identity, is_player_pony, adult) and not id.is_empty()


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


## Deduplicated eligible ids that are not in the base roster. The caller owns the live-pony
## source and its ordering; this helper only filters and deduplicates.
static func off_roster_ids(ids: Array[String], base_ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id: String in ids:
		if id.is_empty() or id in base_ids or out.has(id):
			continue
		out.append(id)
	return out
