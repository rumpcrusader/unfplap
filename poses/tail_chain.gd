extends RefCounted
## The visible tail chain for a pony. Devkit mares carry the tail on the hair skeleton as
## `mTail1..6`; fitted exports such as the princesses skin it to the body skeleton as
## `pony_tail_01..05`. The pose modifiers use whichever chain the skeleton owns. Contract:
## `docs/poses.md`.

## The devkit hair tail, root first.
const HAIR_NAMES: Array[String] = ["mTail1", "mTail2", "mTail3", "mTail4", "mTail5", "mTail6"]
## The native body tail on fitted exports, root first.
const BODY_NAMES: Array[String] = ["pony_tail_01", "pony_tail_02", "pony_tail_03",
	"pony_tail_04", "pony_tail_05"]


## The chain on one skeleton: `{"bones": Array[int], "hair": bool}`. Hair wins when both exist,
## so a devkit mare never loses its visible tail to the native body bones.
static func chain(skeleton: Skeleton3D) -> Dictionary:
	var hair := _bones(skeleton, HAIR_NAMES)
	if not hair.is_empty():
		return {"bones": hair, "hair": true}
	return {"bones": _bones(skeleton, BODY_NAMES), "hair": false}


## The skeleton that owns the visible tail and its chain, or `{}` when neither exists.
static func resolve(pony: Variant) -> Dictionary:
	if not is_instance_valid(pony):
		return {}
	var hair_skeleton: Variant = pony.get("hair_skeleton")
	if hair_skeleton is Skeleton3D:
		var hair: Dictionary = chain(hair_skeleton as Skeleton3D)
		if not (hair["bones"] as Array).is_empty():
			return {"skeleton": hair_skeleton, "bones": hair["bones"], "hair": true}
	var body_skeleton: Variant = pony.get("skeleton")
	if body_skeleton is Skeleton3D:
		var body: Dictionary = chain(body_skeleton as Skeleton3D)
		if not (body["bones"] as Array).is_empty():
			return {"skeleton": body_skeleton, "bones": body["bones"], "hair": false}
	return {}


static func _bones(skeleton: Skeleton3D, names: Array[String]) -> Array[int]:
	var result: Array[int] = []
	for name: String in names:
		var bone := skeleton.find_bone(name)
		if bone >= 0:
			result.append(bone)
	return result
