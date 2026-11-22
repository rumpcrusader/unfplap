extends RefCounted
## Service: world
## Contract: docs/world.md
## Scope: world
## Import: world/api.gd only
## One pony's body reads and writes, bound to her node.

const GAME := preload("res://mods/unfplap/world/game.gd")

var _pony: Node


func _init(pony: Node) -> void:
	_pony = pony


func _bound() -> Node:
	return _pony


## Her identity resource; null when the body has none.
func identity() -> Resource:
	return GAME.identity_of(_pony)


## True when her identity carries wings.
func has_wings() -> bool:
	return GAME.identity_has_wings(GAME.identity_of(_pony))


func skeleton() -> Skeleton3D:
	return GAME.skeleton_of(_pony)


func head() -> Node:
	return GAME.head_of(_pony)


## Her head's mouth rig, which takes the viseme and expression writes.
func mouth() -> Node:
	return GAME.mouth_of(GAME.head_of(_pony))


func hair() -> Node3D:
	return GAME.hair_of(_pony)


func hair_skeleton() -> Skeleton3D:
	return GAME.hair_skeleton_of(_pony)


func model() -> Node:
	return GAME.model_of(_pony)


func body() -> MeshInstance3D:
	return GAME.body_of(_pony)


func dock() -> MeshInstance3D:
	return GAME.dock_of(_pony)


## Where the tail mount sits on the dock.
func dock_anchor() -> Vector3:
	return GAME.dock_tail_anchor(_pony)


## The live dock fit, or null while the game has none.
func dock_fit() -> GAME.DockFit:
	return GAME.dock_fit(_pony)


## The mesh a dock fit renders; the fit is a value the game hands out.
func dock_fitted_mesh(fit: GAME.DockFit) -> ArrayMesh:
	return GAME.dock_fitted_mesh(fit)


## A dock mesh reached onto her rump.
func dock_reach(mesh: ArrayMesh) -> ArrayMesh:
	return GAME.dock_reach_rump(mesh, _pony)


## The dock's rump height for one body name and vertex height.
func dock_rump_z(body_name: String, y: float) -> float:
	return GAME.dock_rump_z(body_name, y)


## Copy her own body materials onto the flank patch.
func claim_body_materials() -> void:
	GAME.own_body_materials(_pony)


func hair_link() -> Node:
	return GAME.hair_link_of(_pony)


func hair_link_ready() -> bool:
	return GAME.hair_link_ready(_pony)


func hair_link_pelvis() -> Transform3D:
	return GAME.hair_link_pelvis(_pony)


func set_hair_link_pelvis(value: Transform3D) -> void:
	GAME.set_hair_link_pelvis(_pony, value)


func notify_hair_link() -> void:
	GAME.notify_hair_link(_pony)


func far_mesh_shown() -> bool:
	return GAME.far_mesh_shown(_pony)


func set_near_mesh(on: bool) -> void:
	GAME.set_near_mesh(_pony, on)


func forget_far_mesh() -> void:
	GAME.forget_far_mesh(_pony)


func eye_motion() -> Node:
	return GAME.eye_motion_of(_pony)


## Her blush sustainer, which takes the burst and the celebrate op.
func boop() -> Node:
	return GAME.boop_of(_pony)


func body_scale() -> float:
	return GAME.body_scale_of(_pony)


func set_body_scale(scale: float) -> void:
	GAME.set_body_scale(_pony, scale)


## Keep one of her meshes out of the game's outline pass.
func exclude_from_outline(mesh: MeshInstance3D) -> void:
	GAME.exclude_from_outline(mesh)


func head_skeleton() -> Skeleton3D:
	return GAME.head_skeleton_of(GAME.boop_of(_pony))


func set_viseme(letter: String) -> void:
	GAME.set_viseme(mouth(), letter)


func clear_viseme() -> void:
	GAME.clear_viseme(mouth())


## The point on `node` that answers for her mouth; the stock affection answers it while she is held.
func mouth_point(node: Node) -> Vector3:
	return GAME.mouth_point(node)


func skull_world() -> Vector3:
	return GAME.skull_world(GAME.boop_of(_pony))


func nose_world() -> Vector3:
	return GAME.nose_world(GAME.boop_of(_pony))


func muzzle_world() -> Vector3:
	return GAME.muzzle_world(GAME.boop_of(_pony))


func eye_transform() -> Transform3D:
	return GAME.eye_transform(_pony)


func listen_point() -> Vector3:
	return GAME.listen_point(_pony)


## Turn her secondary gaze toward `angles`; the gaze object is the one that owns the turn.
func look_toward(secondary: Object, angles: Vector3, weight: float) -> bool:
	return GAME.look_toward(secondary, angles, weight)


func aim_eyes(target: Vector3) -> void:
	GAME.aim_eyes(GAME.eye_motion_of(_pony), target)


## Clamp a bone basis through her joint limits.
func joint_constrain(limits: Object, bone: int, basis: Basis) -> Basis:
	return GAME.joint_constrain(limits, bone, basis)


func is_held() -> bool:
	return GAME.is_held(_pony)


func grounded() -> bool:
	return GAME.grounded(_pony)


func posture_requested() -> String:
	return GAME.posture_requested(_pony)


func request_posture(posture: String) -> void:
	GAME.request_posture(_pony, posture)


func interruption_reason() -> String:
	return GAME.interruption_reason(_pony)


func stop_speaking() -> void:
	GAME.stop_speaking(_pony)


func speaking() -> bool:
	return GAME.pony_speaking(_pony)


func set_motion_paused(paused: bool) -> void:
	GAME.set_motion_paused(_pony, paused)
