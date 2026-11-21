extends RefCounted
## The single seam between the anatomy modules and the live game scene.
## The API owns one and hands it to each module that reads the body.
## Contract: `docs/anatomy.md` (`## Rig contract`).

const GAME := preload("res://mods/unfplap/world/game.gd")


func identity_of(pony: Node) -> Resource:
	return GAME.identity_of(pony)


func skeleton_of(pony: Node) -> Skeleton3D:
	return GAME.skeleton_of(pony)


func body_of(pony: Node) -> MeshInstance3D:
	return GAME.body_of(pony)


func body_scale_of(pony: Node) -> float:
	return GAME.body_scale_of(pony)


func model_of(pony: Node) -> Node:
	return GAME.model_of(pony)


func hair_of(pony: Node) -> Node3D:
	return GAME.hair_of(pony)


func hair_skeleton_of(pony: Node) -> Skeleton3D:
	return GAME.hair_skeleton_of(pony)


func hair_link_of(pony: Node) -> Node:
	return GAME.hair_link_of(pony)


func dock_of(pony: Node) -> MeshInstance3D:
	return GAME.dock_of(pony)


func far_mesh_shown(pony: Node) -> bool:
	return GAME.far_mesh_shown(pony)


func eye_motion_of(pony: Node) -> Node:
	return GAME.eye_motion_of(pony)


func boop_of(pony: Node) -> Node:
	return GAME.boop_of(pony)


func head_of(pony: Node) -> Node:
	return GAME.head_of(pony)


func mouth_of(head: Node) -> Node:
	return GAME.mouth_of(head)


func head_skeleton_of(boop: Node) -> Skeleton3D:
	return GAME.head_skeleton_of(boop)


func nose_world(boop: Node) -> Vector3:
	return GAME.nose_world(boop)


func anon_body_of(player: Node) -> Node3D:
	return GAME.anon_body_of(player)


func hair_link_pelvis(pony: Node) -> Transform3D:
	return GAME.hair_link_pelvis(pony)


func hair_link_ready(pony: Node) -> bool:
	return GAME.hair_link_ready(pony)


func own_body_materials(pony: Node) -> void:
	GAME.own_body_materials(pony)


func set_viseme(mouth: Node, letter: String) -> void:
	GAME.set_viseme(mouth, letter)


func clear_viseme(mouth: Node) -> void:
	GAME.clear_viseme(mouth)


func aim_eyes(eye_motion: Node, target: Vector3) -> void:
	GAME.aim_eyes(eye_motion, target)


func notify_hair_link(pony: Node) -> void:
	GAME.notify_hair_link(pony)


func set_hair_link_pelvis(pony: Node, value: Transform3D) -> void:
	GAME.set_hair_link_pelvis(pony, value)


func set_near_mesh(pony: Node, on: bool) -> void:
	GAME.set_near_mesh(pony, on)
