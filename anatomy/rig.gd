extends RefCounted
## The single seam between the anatomy modules and the live world: every read goes through
## `world/api.gd` and its pony view. The API owns one and injects it into each module.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const DOCK_FIT := preload("res://mods/unfplap/shared/dock_fit.gd")


func identity_of(pony: Node) -> Resource:
	return WORLD.pony(pony).identity()


func skeleton_of(pony: Node) -> Skeleton3D:
	return WORLD.pony(pony).skeleton()


func body_of(pony: Node) -> MeshInstance3D:
	return WORLD.pony(pony).body()


func body_scale_of(pony: Node) -> float:
	return WORLD.pony(pony).body_scale()


func model_of(pony: Node) -> Node:
	return WORLD.pony(pony).model()


func hair_of(pony: Node) -> Node3D:
	return WORLD.pony(pony).hair()


func hair_skeleton_of(pony: Node) -> Skeleton3D:
	return WORLD.pony(pony).hair_skeleton()


func hair_link_of(pony: Node) -> Node:
	return WORLD.pony(pony).hair_link()


func dock_of(pony: Node) -> MeshInstance3D:
	return WORLD.pony(pony).dock()


func dock_anchor(pony: Node) -> Vector3:
	return WORLD.pony(pony).dock_anchor()


func dock_fit(pony: Node) -> DOCK_FIT:
	return WORLD.pony(pony).dock_fit()


func dock_fitted_mesh(pony: Node, fit: DOCK_FIT) -> ArrayMesh:
	return WORLD.pony(pony).dock_fitted_mesh(fit)


func dock_reach(pony: Node, mesh: ArrayMesh) -> ArrayMesh:
	return WORLD.pony(pony).dock_reach(mesh)


func far_mesh_shown(pony: Node) -> bool:
	return WORLD.pony(pony).far_mesh_shown()


func forget_far_mesh(pony: Node) -> void:
	WORLD.pony(pony).forget_far_mesh()


func exclude_from_outline(pony: Node, mesh: MeshInstance3D) -> void:
	WORLD.pony(pony).exclude_from_outline(mesh)


func eye_motion_of(pony: Node) -> Node:
	return WORLD.pony(pony).eye_motion()


func boop_of(pony: Node) -> Node:
	return WORLD.pony(pony).boop()


func head_of(pony: Node) -> Node:
	return WORLD.pony(pony).head()


func mouth_of(pony: Node) -> Node:
	return WORLD.pony(pony).mouth()


func head_skeleton_of(pony: Node) -> Skeleton3D:
	return WORLD.pony(pony).head_skeleton()


func nose_world(pony: Node) -> Vector3:
	return WORLD.pony(pony).nose_world()


func anon_body() -> Node3D:
	return WORLD.anon().body()


func hair_link_pelvis(pony: Node) -> Transform3D:
	return WORLD.pony(pony).hair_link_pelvis()


func hair_link_ready(pony: Node) -> bool:
	return WORLD.pony(pony).hair_link_ready()


func own_body_materials(pony: Node) -> void:
	WORLD.pony(pony).claim_body_materials()


func set_viseme(pony: Node, letter: String) -> void:
	WORLD.pony(pony).set_viseme(letter)


func clear_viseme(pony: Node) -> void:
	WORLD.pony(pony).clear_viseme()


func aim_eyes(pony: Node, target: Vector3) -> void:
	WORLD.pony(pony).aim_eyes(target)


func notify_hair_link(pony: Node) -> void:
	WORLD.pony(pony).notify_hair_link()


func set_hair_link_pelvis(pony: Node, value: Transform3D) -> void:
	WORLD.pony(pony).set_hair_link_pelvis(value)


func set_near_mesh(pony: Node, on: bool) -> void:
	WORLD.pony(pony).set_near_mesh(on)
