extends RefCounted
## The shared body profile: the winking bodies' scale and placement anchor, the body-fit key that
## names the body a pony is wearing, and the entrance offset the standing act measures from. Pure:
## it reads only the identity and the pony metadata it is given.
##
## `RigProfile` is the typed rig a body form carries; the array accessors are the compatibility
## readers for the placement editor and the no-form fallback. The anatomy fit, the teats and the
## act camera read the presented `BodyForm`'s rig and fit, so a body-swapped pony is measured from
## the body that is actually rendered. See `docs/body_change.md`, `docs/anatomy.md`
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

## The ordinary body's rig id: the shared mare body's rear and scale one.
const ORDINARY_RIG := "ordinary"


## One body's rig: the scale and the rear anchor a physical system measures from. A body form
## carries this instead of an identity heuristic. `id` is `ordinary` or a `WINKING_BODIES` key.
class RigProfile extends RefCounted:
	var id: String
	var rear_y: float
	var rear_z: float
	var scale: float

	func _init(profile_id: String, anchor_y: float, anchor_z: float, body_size: float) -> void:
		id = profile_id
		rear_y = anchor_y
		rear_z = anchor_z
		scale = body_size

	## True when the body uses the shared mare body's own anchor.
	func is_ordinary() -> bool:
		return id == ORDINARY_RIG


## The profile for an identity, or an empty array for an ordinary body. A modded copy is matched by
## `character_id` first, then by its own identity id.
static func body_profile(identity: Variant) -> Array:
	return _profile(_identity_key(identity))


## The body-fit key a placement row resolves against. An integration sets `body_fit_id` on the pony
## when the visible body is not the identity's usual one; otherwise the identity's `character_id`
## names the copied body and the identity id is the last fallback.
static func body_fit_id(pony: Variant) -> String:
	if not is_instance_valid(pony):
		return ""
	var meta := str(pony.get_meta("body_fit_id", "")).strip_edges()
	if not meta.is_empty():
		return meta
	return _identity_key(pony.get("identity"))


## The profile of the body `pony` is wearing now: her body-fit key, so a disguise on a princess body
## fits that body and a princess wearing an ordinary body does not.
static func body_profile_for(pony: Variant) -> Array:
	var key := body_fit_id(pony)
	if key.is_empty():
		return []
	return _profile(key)


## The typed rig for a profile table key. An unknown key is the ordinary body.
static func rig_for_key(key: String) -> RigProfile:
	var profile: Variant = WINKING_BODIES.get(key, [])
	if profile is Array and (profile as Array).size() >= 3:
		return RigProfile.new(key, float(profile[0]), float(profile[1]), float(profile[2]))
	return ordinary_rig()


## The typed rig for an identity, with the same `character_id` then identity-id fallback.
static func rig_for_identity(identity: Variant) -> RigProfile:
	return rig_for_key(_identity_key(identity))


## The typed rig of the body a pony wears now, from her body-fit key.
static func rig_for_pony(pony: Variant) -> RigProfile:
	return rig_for_key(body_fit_id(pony))


## The shared mare body's rig: the anchor every standing gap and every princess profile uses.
static func ordinary_rig() -> RigProfile:
	return RigProfile.new(ORDINARY_RIG, WINKING_REAR_Y, WINKING_REAR_Z, 1.0)


## How far a body's entrance sits from the mare's every standing offset was tuned on, in world
## metres at the body's live scale: `(higher +, further back +)`. Zero for the ordinary rig.
static func entrance_offset_for(rig: RigProfile, body_scale: float) -> Vector2:
	if rig == null:
		return Vector2.ZERO
	var scale := maxf(body_scale, 0.1)
	return Vector2(rig.rear_y - WINKING_REAR_Y, rig.rear_z - WINKING_REAR_Z) * scale


static func _identity_key(identity: Variant) -> String:
	if identity == null:
		return ""
	var character: Variant = identity.get("character_id")
	var key := str(character) if character != null else ""
	if key.is_empty():
		var identity_id: Variant = identity.get("id")
		key = str(identity_id) if identity_id != null else ""
	return key


static func _profile(key: String) -> Array:
	var profile: Variant = WINKING_BODIES.get(key, [])
	return profile.duplicate() if profile is Array else []
