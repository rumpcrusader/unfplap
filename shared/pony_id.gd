extends RefCounted
## Pure stable pony id: the relationship metadata first, then the identity id. Eligibility,
## runtime, preferences, placement, memory and the anatomy internals all key off this one rule.
##
## It takes plain values and reads no Node, scene or settings file.


static func from(meta_id: String, identity: Variant) -> String:
	if not meta_id.is_empty():
		return meta_id
	if identity == null:
		return ""
	var id: Variant = identity.get("id")
	return str(id) if id != null else ""


## One body's stable id, read from its relationship metadata and identity.
static func of(pony: Node) -> String:
	if not is_instance_valid(pony):
		return ""
	return from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))


## Deduplicated ids outside a base roster. The caller owns the filter and the order.
static func off_roster(ids: Array[String], base_ids: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for id: String in ids:
		if id.is_empty() or id in base_ids or out.has(id):
			continue
		out.append(id)
	return out
