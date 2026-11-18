extends RefCounted
## The shared body profile: the winking bodies' scale and placement anchor, the body-fit key that
## names the body a pony is wearing, and the entrance offset the standing act measures from. Pure:
## it reads only the identity and the pony metadata it is given.
##
## The anatomy fit, the teats and the act camera all read this one module, so a body-swapped pony
## is measured from the body that is actually rendered. See `docs/anatomy.md`
## (`## Attachment and identity`) and `docs/camera.md` (`## Standing camera`).

## The princess body scale and placement anchor for a known character: `[anchor y, anchor z, size]`.
## A modded copy can set `character_id` to the canon pony whose body it uses; otherwise the identity
## id is the key.
const WINKING_BODIES := {
	"celestia": [0.853, 0.3329, 1.67],
	"luna": [0.596, 0.2265, 1.095],
}

## The shared mare body's anatomy anchor. Every princess profile and every standing gap is measured
## from it.
const WINKING_REAR_Y := 0.541
const WINKING_REAR_Z := 0.2961


## The profile for an identity, or an empty array for an ordinary body. A modded copy is matched by
## `character_id` first, then by its own identity id.
static func body_profile(identity: Variant) -> Array:
	if identity == null:
		return []
	var character: Variant = identity.get("character_id")
	var key := str(character) if character != null else ""
	if key.is_empty():
		var identity_id: Variant = identity.get("id")
		key = str(identity_id) if identity_id != null else ""
	return _profile(key)


## The body-fit key a placement row resolves against. An integration sets `body_fit_id` on the pony
## when the visible body is not the identity's usual one; otherwise the identity's `character_id`
## names the copied body and the identity id is the last fallback.
static func body_fit_id(pony: Variant) -> String:
	if not is_instance_valid(pony):
		return ""
	var meta := str(pony.get_meta("body_fit_id", "")).strip_edges()
	if not meta.is_empty():
		return meta
	var identity: Variant = pony.get("identity")
	if identity == null:
		return ""
	var character: Variant = identity.get("character_id")
	var key := str(character) if character != null else ""
	if key.is_empty():
		var identity_id: Variant = identity.get("id")
		key = str(identity_id) if identity_id != null else ""
	return key


## The profile of the body `pony` is wearing now: her body-fit key, so a disguise on a princess body
## fits that body and a princess wearing an ordinary body does not.
static func body_profile_for(pony: Variant) -> Array:
	var key := body_fit_id(pony)
	if key.is_empty():
		return []
	return _profile(key)


## How far her entrance sits from the mare's every standing offset was tuned on, in world metres at
## her live body scale: `(higher +, further back +)`. Zero for an ordinary body.
static func entrance_offset(pony: Variant) -> Vector2:
	var profile := body_profile_for(pony)
	if profile.size() < 2:
		return Vector2.ZERO
	var scale_value: Variant = pony.get("body_scale")
	var scale := maxf(float(scale_value), 0.1) if scale_value != null else 1.0
	return Vector2(float(profile[0]) - WINKING_REAR_Y,
		float(profile[1]) - WINKING_REAR_Z) * scale


static func _profile(key: String) -> Array:
	var profile: Variant = WINKING_BODIES.get(key, [])
	return profile.duplicate() if profile is Array else []
