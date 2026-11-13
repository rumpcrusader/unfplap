extends RefCounted
## Pure stable pony id: the relationship metadata first, then the identity id. Eligibility,
## runtime, preferences, placement, memory and the anatomy internals all key off this one rule.
##
## It takes plain values and reads no Node, scene or settings file. The node-shaped convenience
## stays on the owning facade (`anatomy/service.gd:pony_id()`). See `docs/eligibility.md`
## (`## Data ownership`).


static func from(meta_id: String, identity: Variant) -> String:
	if not meta_id.is_empty():
		return meta_id
	if identity == null:
		return ""
	var id: Variant = identity.get("id")
	return str(id) if id != null else ""
