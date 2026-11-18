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


## A visible tail that is not on either game skeleton: an integration sets the pony's
## `tail_pose_root` metadata (or property) to the `Node3D` whose transform carries it. The tail
## modifiers rotate and restore that node instead of the bone chain.
static func custom_root(pony: Variant) -> Node3D:
	if not is_instance_valid(pony):
		return null
	var value: Variant = null
	if pony.has_method("get_meta"):
		value = pony.get_meta("tail_pose_root", null)
	if not value is Node3D:
		value = pony.get("tail_pose_root")
	return value as Node3D if is_instance_valid(value) else null


## The tail direction in a custom root's own space, from the root's skeleton when it has one.
## A root without bones keeps the model's rearward axis.
static func root_direction(root: Node3D) -> Vector3:
	var skeleton := root as Skeleton3D
	if skeleton != null and skeleton.get_bone_count() > 1:
		var first := skeleton.get_bone_global_pose(0).origin
		var last := skeleton.get_bone_global_pose(skeleton.get_bone_count() - 1).origin
		var direction: Vector3 = last - first
		if direction.length_squared() > 0.000001:
			return direction.normalized()
	return Vector3.BACK


static func _bones(skeleton: Skeleton3D, names: Array[String]) -> Array[int]:
	var result: Array[int] = []
	for name: String in names:
		var bone := skeleton.find_bone(name)
		if bone >= 0:
			result.append(bone)
	return result
