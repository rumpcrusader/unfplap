extends RefCounted
## Two-bone GPU skin for the standard OpenPonyDock.
##
## The dock is authored as a body-skinned mesh, not a second tail: its base belongs at the hair
## tail root and its outer end follows the first tail joint. This module rebuilds the fitted dock
## as a two-bind skinned mesh on the hair skeleton, so the engine does the blend every frame:
## `mPelvis` at the base, `mTail1` at the outer end, and the same smoothstep between them the old
## CPU follower used. There is no per-frame mesh rebuild.
##
## The mesh stays in the body skeleton's space. The bind poses convert body space into the hair
## skeleton's bind space (`bind = rest_pose^-1 * hair_global^-1 * body_global`), and the dock is
## parented under the hair skeleton. The instance translation carries the dock lift as a post-skin
## body-space Y offset, which is exactly what the old follower added after its blend.


## Body-space blend weight for every dock vertex: 0 at the base ring, 1 at the farthest vertex,
## smoothstepped along the cuff. Empty when the base ring does not describe a usable cuff.
static func weights_for(vertices: PackedVector3Array, ring: PackedInt32Array) -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	if vertices.is_empty() or ring.is_empty():
		return weights
	var base := Vector3.ZERO
	var count := 0
	for index: int in ring:
		if index >= 0 and index < vertices.size():
			base += vertices[index]
			count += 1
	if count == 0:
		return weights
	base /= float(count)
	var tip := base
	var far := 0.0
	for vertex: Vector3 in vertices:
		var distance := vertex.distance_squared_to(base)
		if distance > far:
			far = distance
			tip = vertex
	var length := base.distance_to(tip)
	if length < 0.001:
		return weights
	var axis := (tip - base) / length
	weights.resize(vertices.size())
	for index in vertices.size():
		var along := clampf((vertices[index] - base).dot(axis) / length, 0.0, 1.0)
		weights[index] = smoothstep(0.0, 1.0, along)
	for index: int in ring:
		if index >= 0 and index < weights.size():
			weights[index] = 0.0
	return weights


## The dock's local transform under the hair skeleton for one lift. It depends only on the two
## skeletons' global transforms, so a dock offset edit can rewrite it without rebuilding the mesh.
static func lift_transform(body: Skeleton3D, hair: Skeleton3D, dock_lift: float) -> Transform3D:
	var into_hair := hair.global_transform.affine_inverse() * body.global_transform
	return Transform3D(Basis.IDENTITY, into_hair.basis * Vector3(0.0, dock_lift, 0.0))


## Build the skinned dock mesh and skin. Returns
## {"mesh": ArrayMesh, "skin": Skin, "transform": Transform3D} or {} when the cuff or rig cannot
## be skinned. The transform is the dock's local transform under the hair skeleton: it carries
## `dock_lift` as a post-skin body-space offset.
static func build(mesh: ArrayMesh, body: Skeleton3D, hair: Skeleton3D,
		dock_lift: float) -> Dictionary:
	if mesh == null or mesh.get_surface_count() == 0:
		return {}
	if not is_instance_valid(body) or not is_instance_valid(hair):
		return {}
	var pelvis := hair.find_bone("mPelvis")
	var tail1 := hair.find_bone("mTail1")
	if pelvis < 0 or tail1 < 0:
		return {}
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ring: PackedInt32Array = mesh.get_meta("base_indices", PackedInt32Array())
	if vertices.is_empty() or ring.is_empty():
		return {}
	var weights := weights_for(vertices, ring)
	if weights.is_empty():
		return {}
	var bones := PackedInt32Array()
	var skin_weights := PackedFloat32Array()
	bones.resize(vertices.size() * 4)
	skin_weights.resize(vertices.size() * 4)
	for index in vertices.size():
		bones[index * 4] = 0
		bones[index * 4 + 1] = 1
		skin_weights[index * 4] = 1.0 - weights[index]
		skin_weights[index * 4 + 1] = weights[index]
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = skin_weights
	var skinned := ArrayMesh.new()
	skinned.add_surface_from_arrays(mesh.surface_get_primitive_type(0), arrays)
	skinned.surface_set_material(0, mesh.surface_get_material(0))
	skinned.surface_set_name(0, mesh.surface_get_name(0))
	for key: Variant in mesh.get_meta_list():
		skinned.set_meta(key, mesh.get_meta(key))
	# Body space -> hair bind space. The instance transform is the hair skeleton's global
	# transform, so the engine renders `hair_global * pose * bind * vertex`.
	var into_hair := hair.global_transform.affine_inverse() * body.global_transform
	var skin := Skin.new()
	skin.add_bind(pelvis, hair.get_bone_global_pose(pelvis).affine_inverse() * into_hair)
	skin.add_bind(tail1, hair.get_bone_global_pose(tail1).affine_inverse() * into_hair)
	# The old follower added the lift after the blend, in body space. Apply it through the dock's
	# local transform so it stays a post-skin body-space offset instead of rotating with the tail.
	var lift := lift_transform(body, hair, dock_lift)
	return {"mesh": skinned, "skin": skin, "transform": lift}
