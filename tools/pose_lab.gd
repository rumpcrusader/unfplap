@tool
extends Node3D
## Missionary pose lab. Dev tool only; it never ships.
##
## The **scene** is the authoring source: `Pony`, `Bed` and one Anon rig are saved in it and you
## pose the skeletons with the editor's Skeleton3D bone gizmo. **Save pose** exports the pose to
## `poses/missionary_pose.json`, bed-relative, and that JSON is the only thing the game reads.
## Never edit the JSON by hand; export it again instead.
##
## A scene that has no rigs yet builds a fresh set once (pony, stand-in bed, camera and `Anon3`)
## and seeds it from the JSON, so the lab also works from an empty scene.
##
## The JSON is the source of truth for the runtime. The runtime never reads this script.

const PONY_MESH := preload("res://world/characters/hybrid_mare/body.glb")
const ANON_RIG := preload("res://player/anon_body.tscn")

const DEFAULT_POSE_PATH := "res://mods/unfplap/poses/missionary_pose.json"
const POSE_VERSION := 5
## The authored camera positions of the act's shot, node name -> shot key: the neutral start (lean
## 0), the pulled-back S end, the forward W end (the kiss), and the two side leans. Only the
## positions are exported; the runtime aims them at her live face and vulva.
const SHOT_NODES := [
	["ShotStart", "start"],
	["ShotBack", "back"],
	["ShotFront", "front"],
	["ShotLeft", "left"],
	["ShotRight", "right"],
]
## The rig exported under the JSON's `anon` key. Anon1 and Anon2 were early floor drafts.
const ANON_EXPORT_NAME := "Anon3"
const TARGET_NAMES := ["HipsTarget", "HeadTarget", "LeftHandTarget", "RightHandTarget",
	"LeftFootTarget", "RightFootTarget"]

## Bones the runtime bakes for the missionary body. Everything else (head, lids, eyes, ears, wings,
## feathers, mane, tail, jaw) is owned by the game or the act at runtime, and a saved scene can
## carry animation leftovers in those that are not part of the pose. The chain order matters:
## hips -> flank -> femur -> tibia -> legLower -> tarsal -> hoof, and spine3 -> shoulder ->
## upperArm -> lowerArm -> wrist -> hand -> finger.
const PONY_BONES := [
	"pony_hips",
	"pony_spine1", "pony_spine2", "pony_spine3",
	"pony_neck1", "pony_neck2",
	"pony_flank_L", "pony_femur_L", "pony_tibia_L", "pony_legLower_L", "pony_tarsal_L",
	"pony_hoof_L",
	"pony_flank_R", "pony_femur_R", "pony_tibia_R", "pony_legLower_R", "pony_tarsal_R",
	"pony_hoof_R",
	"pony_shoulder_L", "pony_upperArm_L", "pony_lowerArm_L", "pony_wrist_L", "pony_hand_L",
	"pony_finger_L",
	"pony_shoulder_R", "pony_upperArm_R", "pony_lowerArm_R", "pony_wrist_R", "pony_hand_R",
	"pony_finger_R",
]

@export var pose_path := DEFAULT_POSE_PATH
## Used only when a fresh stand-in bed is built; an adopted scene bed keeps its own box.
@export var mattress_top := 0.65
@export var bed_size := Vector3(1.6, 0.55, 2.2)
@export var show_colliders := false
@export var show_skeleton := false

@export_tool_button("Save pose") var save_pose: Callable = _save_pose
@export_tool_button("Load pose") var load_pose: Callable = _load_pose
@export_tool_button("Reset") var reset: Callable = _reset
@export_tool_button("Capture") var capture: Callable = _capture
@export_tool_button("Show colliders") var toggle_colliders: Callable = _toggle_colliders
@export_tool_button("Show skeleton") var toggle_skeleton: Callable = _toggle_skeleton
@export_tool_button("Select pony skeleton") var select_skeleton: Callable = _select_skeleton
@export_tool_button("Select Anon skeleton") var select_anon_skeleton: Callable = _select_anon_skeleton
@export_tool_button("Select Anon2 skeleton") var select_anon2_skeleton: Callable = _select_anon2_skeleton
@export_tool_button("Select Anon3 skeleton") var select_anon3_skeleton: Callable = _select_anon3_skeleton
@export_tool_button("Pose help") var pose_help: Callable = _print_pose_help
@export_tool_button("Fit pony to bed") var fit_button: Callable = _fit_pony_to_bed
@export_tool_button("Mirror Anon targets") var mirror_button: Callable = _mirror_anon_targets
@export_tool_button("Add shot cameras") var shot_cameras_button: Callable = _add_shot_cameras

var _pony: Node3D
var _pony_skel: Skeleton3D
var _anons: Array[Node3D] = []
var _anon_skels: Array[Skeleton3D] = []
var _anon_iks: Array[SkeletonModifier3D] = []
var _bed: Node3D
var _camera: Camera3D
var _built := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_adopt_or_build()
	# The JSON is the source of truth: the scene keeps only the rig roots and the shot cameras,
	# because Godot discards instance-child overrides when it saves the scene. Opening it therefore
	# always applies the exported pose and shot positions. **Save pose** is what writes them back.
	_load_pose()
	call_deferred("_editor_ready")


## Opens the bottom Skeleton panel and prints the pose steps. Godot 4.5 has no
## "Pose" button: posing means selecting a bone and rotating it in the viewport.
## It does not steal the selection, because that would hide the tool buttons in
## the Inspector; "Select pony skeleton" is the explicit way to jump there.
func _editor_ready() -> void:
	if not Engine.is_editor_hint():
		return
	_print_pose_help()


func _print_pose_help() -> void:
	print("[poselab] POSING: Godot 4.5 has no 'Pose' button.")
	print("[poselab]   1. Select a bone in the bottom Skeleton panel's bone list.")
	print("[poselab]   2. Leave the Skeleton panel's 'Edit' toggle OFF (that edits rest bones).")
	print("[poselab]   3. In the 3D viewport press R and drag a gizmo ring to rotate the bone.")
	print("[poselab]   4. Save the scene, then click 'Save pose' to export the JSON.")
	print("[poselab] ANON: pose his bones the same way; 'Select Anon3 skeleton' jumps there.")
	print("[poselab]       Only body bones are exported for the pony; the game owns the head,")
	print("[poselab]       ears, lids, wings, mane and tail.")
	print("[poselab] 'Fit pony to bed' drops her onto the mattress after you move her.")


## Adopts the rigs saved in the scene. The scene is the authoring source, so opening it must never
## strip or rebuild anything. Returns true when a fresh set had to be built.
func _adopt_or_build() -> bool:
	if _built:
		return false
	_pony = get_node_or_null("Pony") as Node3D
	_bed = get_node_or_null("Bed") as Node3D
	_camera = get_node_or_null("Camera") as Camera3D
	_pony_skel = _find_skel(_pony) if _pony != null else null
	_anons.clear()
	_anon_skels.clear()
	_anon_iks.clear()
	for child in get_children():
		if not child.name.begins_with("Anon"):
			continue
		var rig := child as Node3D
		if rig == null or rig.name == "AnonBody":
			continue
		_hold_anon(rig)
	_built = true
	if _pony != null and _bed != null:
		print("[poselab] adopted scene rigs: pony=%s anons=%d" % [
			str(_pony_skel), _anons.size()])
		return false
	_build_fresh()
	return true


## Builds the rigs a blank scene is missing. Only used when the scene carries none.
func _build_fresh() -> void:
	if _pony == null:
		_pony = PONY_MESH.instantiate()
		_pony.name = "Pony"
		add_child(_pony)
		_own(_pony)
		_pony_skel = _find_skel(_pony)
	if _anons.is_empty():
		var rig: Node3D = ANON_RIG.instantiate()
		rig.name = ANON_EXPORT_NAME
		add_child(rig)
		_own(rig)
		_hold_anon(rig)
	if _bed == null:
		_bed = _make_bed()
		add_child(_bed)
		_own(_bed)
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera"
		add_child(_camera)
		_own(_camera)
		_camera.position = Vector3(0.0, 1.6, 3.0)
	print("[poselab] built fresh pony=%s bones=%d anons=%d" % [
		str(_pony_skel), _pony_skel.get_bone_count() if _pony_skel != null else -1,
		_anons.size()])


## Registers one Anon rig. Its own controller rewrites the IK targets every frame, which would
## overwrite everything posed here; stop its process but keep the script so its `_ready` setup
## (mesh visibility) still runs.
func _hold_anon(rig: Node3D) -> void:
	rig.set_process(false)
	rig.set_physics_process(false)
	_anons.append(rig)
	_anon_skels.append(_find_skel(rig))
	_anon_iks.append(rig.find_child("BodyIK", true, false) as SkeletonModifier3D)


## Solves the game's BodyIK from its targets. Only works outside the editor: the
## script is not a tool script, so the editor holds a placeholder. The authored
## pose is baked into bone rotations and the targets are kept for the runtime.
func _solve_anon_ik(quiet: bool = false, index: int = 0) -> void:
	if Engine.is_editor_hint() or index < 0 or index >= _anon_iks.size():
		return
	var ik: SkeletonModifier3D = _anon_iks[index]
	var sk: Skeleton3D = _anon_skels[index]
	if ik == null or sk == null:
		return
	ik.call("_process_modification")
	sk.force_update_all_bone_transforms()
	if not quiet:
		print("[poselab] solved %s IK" % _anons[index].name)


## Shifts the pony so her lowest mesh point sits on the mattress top. The skinned
## mesh AABB ignores bone poses, so this is an approximation for the body only.
func _fit_pony_to_bed() -> void:
	if _pony == null:
		return
	var box := _pony_world_aabb()
	if not box.has_volume():
		print("[poselab] no pony mesh bounds")
		return
	var at := _global_of(_pony)
	at.origin.y += _mattress_y() - box.position.y
	_set_global(_pony, at)
	print("[poselab] pony fitted to y=%.3f" % at.origin.y)


## Mirrors the left hand and foot targets onto the right ones across each rig's
## centre plane (local X = 0). The rig's body centre is its origin, so the
## mirror is a pure lateral reflection: x -> -x, y and z stay. The user poses the
## left side and the right follows; the rig itself never moves.
func _mirror_anon_targets() -> void:
	if _anons.is_empty():
		print("[poselab] no Anons to mirror")
		return
	for rig in _anons:
		if rig == null:
			continue
		for pair in [["LeftHandTarget", "RightHandTarget"], ["LeftFootTarget", "RightFootTarget"]]:
			var left := rig.find_child(pair[0], true, false) as Node3D
			var right := rig.find_child(pair[1], true, false) as Node3D
			if left == null or right == null:
				continue
			var mirrored: Vector3 = left.position
			mirrored.x = -mirrored.x
			right.position = mirrored
	print("[poselab] mirrored Anon targets (left -> right) across local X=0")


func _pony_world_aabb() -> AABB:
	var box := AABB()
	var first := true
	for node in _pony.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var local: AABB = mesh.mesh.get_aabb()
		var world: AABB = mesh.global_transform * local
		box = world if first else box.merge(world)
		first = false
	return box


## In the editor the instantiated nodes only appear in the Scene dock and can be
## selected with the gizmo when they carry the edited scene's owner. The glb is
## body → RainbowDashRig_001 → Skeleton3D, so this has to walk the whole tree or
## the Skeleton3D stays hidden inside the sub-scene. The sub-scene also needs
## "editable children" on or the editor keeps its internals collapsed.
func _own(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	var root := get_tree().edited_scene_root
	if root == null or root == node:
		return
	node.owner = root
	if not node.scene_file_path.is_empty():
		node.set_editable_instance(node, true)
	for child in node.get_children():
		_own(child)


func _find_skel(node: Node) -> Skeleton3D:
	for child in node.find_children("*", "Skeleton3D", true, false):
		return child as Skeleton3D
	return null


func _make_bed() -> Node3D:
	var bed := StaticBody3D.new()
	bed.name = "Bed"
	var mesh := MeshInstance3D.new()
	mesh.name = "BedMesh"
	var box := BoxMesh.new()
	box.size = bed_size
	mesh.mesh = box
	bed.add_child(mesh)
	var shape := CollisionShape3D.new()
	shape.name = "BedShape"
	var box_shape := BoxShape3D.new()
	box_shape.size = bed_size
	shape.shape = box_shape
	bed.add_child(shape)
	bed.position = Vector3(0.0, mattress_top - bed_size.y * 0.5, 0.0)
	return bed


## World transform without the scene tree. `Node3D.global_transform` returns identity (and logs
## an error) outside the tree, and the headless export deliberately instantiates the scene
## without adding it, so the parent chain is composed here instead.
func _global_of(node: Node3D) -> Transform3D:
	var chain: Array[Node3D] = []
	var current: Node = node
	while current is Node3D:
		chain.push_front(current as Node3D)
		current = current.get_parent()
	var out := Transform3D.IDENTITY
	for item in chain:
		out *= item.transform
	return out


## The same for writing, in the node's own parent space.
func _set_global(node: Node3D, value: Transform3D) -> void:
	var parent := node.get_parent() as Node3D
	node.transform = value if parent == null else _global_of(parent).affine_inverse() * value


## The stand-in bed's box, from the mesh so an adopted scene bed keeps its own.
func _bed_world_size() -> Vector3:
	if _bed != null:
		var mesh := _bed.get_node_or_null("BedMesh") as MeshInstance3D
		if mesh != null and mesh.mesh is BoxMesh:
			return (mesh.mesh as BoxMesh).size
	return bed_size


## World height of the stand-in bed's top surface.
func _mattress_y() -> float:
	if _bed == null:
		return mattress_top
	var size := _bed_world_size()
	if size == Vector3.ZERO:
		return mattress_top
	return (_global_of(_bed) * Vector3(0.0, size.y * 0.5, 0.0)).y


## The pose space every exported transform is written in: origin at the middle of the mattress
## top, axes the bed's own, `+Z` her head direction. The runtime maps it onto the real bed.
func _pose_frame() -> Transform3D:
	if _bed == null:
		return Transform3D(Basis.IDENTITY, Vector3(0.0, mattress_top, 0.0))
	var bed_xform := _global_of(_bed)
	var at := bed_xform.origin
	return Transform3D(bed_xform.basis.orthonormalized(), Vector3(at.x, _mattress_y(), at.z))


## Creates any missing shot cameras at a first guess worked out from the pose: start over her
## chest, back over her pelvis, front at her face for the kiss, and the two side leans beside the
## start. Drag them where you want and save the scene.
func _add_shot_cameras() -> void:
	if _pony_skel == null:
		print("[poselab] no pony skeleton to place the shots from")
		return
	var neck := _bone_world(_pony_skel, "pony_neck1", "pony_neck2")
	var hips := _bone_world(_pony_skel, "pony_hips")
	var head := _bone_world(_pony_skel, "pony_head")
	if not neck.is_finite() or not hips.is_finite() or not head.is_finite():
		print("[poselab] cannot read the neck, hips and head")
		return
	# Her rump is the opposite way from the head: in the lab's bed space that is -Z.
	var rump := Vector3(0.0, 0.0, -1.0)
	var start := neck + Vector3.UP * 0.35 + rump * 0.75
	var guesses := {
		"start": [start, neck],
		"back": [hips + Vector3.UP * 0.35 + rump * 0.35, hips + Vector3.UP * 0.10],
		"front": [head + rump * 0.40 + Vector3.UP * 0.20, head],
		"left": [start + Vector3.LEFT * 0.35, neck],
		"right": [start + Vector3.RIGHT * 0.35, neck],
	}
	var added: Array[String] = []
	for entry: Array in SHOT_NODES:
		var node_name := str(entry[0])
		if get_node_or_null(node_name) != null:
			continue
		var guess: Array = guesses[str(entry[1])]
		_make_shot(node_name, guess[0], guess[1])
		added.append(node_name)
	if added.is_empty():
		print("[poselab] all shot cameras already exist")
	else:
		print("[poselab] added %s; drag them and save the scene" % ", ".join(added))


func _make_shot(name: String, at: Vector3, look_at: Vector3) -> Node3D:
	var shot := Camera3D.new()
	shot.name = name
	shot.fov = 75.0
	add_child(shot)
	_own(shot)
	var basis := Basis.looking_at((look_at - at).normalized(), Vector3.UP)
	_set_global(shot, Transform3D(basis, at))
	return shot


## World origin between two bones (or of the first one when the second is missing).
func _bone_world(sk: Skeleton3D, first: String, second := "") -> Vector3:
	var a := sk.find_bone(first)
	if a < 0:
		return Vector3.INF
	var at := sk.global_transform * sk.get_bone_global_pose(a).origin
	if second.is_empty():
		return at
	var b := sk.find_bone(second)
	if b < 0:
		return at
	return (at + sk.global_transform * sk.get_bone_global_pose(b).origin) * 0.5


func _save_pose() -> void:
	if _pony == null or _pony_skel == null:
		push_error("PoseLab: nothing to save")
		return
	var frame := _pose_frame()
	var size := _bed_world_size()
	var data := {
		"version": POSE_VERSION,
		"frame": {
			"origin": "middle of the mattress top",
			"axes": "bed axes; +Z is the direction her head points",
		},
		"bed": {
			"size": _vec_to_str(size),
			"mattress_top": _mattress_y(),
		},
		"pony": {
			"transform": _transform_to_str(frame.affine_inverse() * _global_of(_pony)),
			"bones": _save_bones(_pony_skel, PONY_BONES),
		},
	}
	var rig := _export_anon()
	if rig != null:
		var index := _anons.find(rig)
		data["anon"] = {
			"rig": str(rig.name),
			"transform": _transform_to_str(frame.affine_inverse() * _global_of(rig)),
			"bones": _save_bones(_anon_skels[index], []),
		}
	var shots := {}
	for entry: Array in SHOT_NODES:
		var node := get_node_or_null(str(entry[0])) as Node3D
		if node != null:
			shots[str(entry[1])] = _transform_to_str(frame.affine_inverse() * _global_of(node))
	if shots.is_empty():
		print("[poselab] no shot cameras in the scene; the act shot stays pose-derived")
	else:
		data["shots"] = shots
	if (data["pony"]["bones"] as Dictionary).is_empty():
		push_error("PoseLab: the rig is at rest; load the pose before saving it")
		print("[poselab] refusing to save an empty pose (the scene rig is at its rest pose)")
		return
	var text := JSON.stringify(data, "\t")
	var file := FileAccess.open(pose_path, FileAccess.WRITE)
	if file == null:
		push_error("PoseLab: cannot write %s" % pose_path)
		return
	file.store_string(text)
	print("[poselab] saved %s (pony bones=%d)" % [
		pose_path, (data["pony"]["bones"] as Dictionary).size()])


## The rig exported under `anon`. Defaults to ANON_EXPORT_NAME, then the first rig present.
func _export_anon() -> Node3D:
	for rig in _anons:
		if rig.name == ANON_EXPORT_NAME:
			return rig
	return _anons[0] if not _anons.is_empty() else null


func _load_pose() -> void:
	if not FileAccess.file_exists(pose_path):
		print("[poselab] no pose at %s" % pose_path)
		return
	var text := FileAccess.get_file_as_string(pose_path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("PoseLab: bad JSON in %s" % pose_path)
		return
	var data: Dictionary = parsed as Dictionary
	var version := int(data.get("version", 3))
	var frame := _pose_frame()
	# Version 3 stored world transforms; version 4 stores them in the bed frame.
	var space := frame if version >= POSE_VERSION else Transform3D.IDENTITY
	if _pony != null and data.get("pony") is Dictionary:
		var pony: Dictionary = data["pony"]
		_set_global(_pony, space * _str_to_transform(str(pony.get("transform", ""))))
		_load_bones(_pony_skel, pony.get("bones", {}))
	var rig := _export_anon()
	if rig != null:
		var block: Dictionary = {}
		if data.get("anon") is Dictionary:
			block = data["anon"]
		elif data.get("anon3") is Dictionary:
			block = data["anon3"]
		elif data.get("anon1") is Dictionary:
			block = data["anon1"]
		if not block.is_empty():
			var index := _anons.find(rig)
			_set_global(rig, space * _str_to_transform(str(block.get("transform", ""))))
			_load_targets(rig, block.get("targets", {}))
			_load_bones(_anon_skels[index], block.get("bones", {}))
	var shot_data: Variant = data.get("shots")
	if shot_data is Dictionary:
		for entry: Array in SHOT_NODES:
			var node := get_node_or_null(str(entry[0])) as Node3D
			var key := str(entry[1])
			if node == null or not (shot_data as Dictionary).has(key):
				continue
			_set_global(node, space * _str_to_transform(str((shot_data as Dictionary)[key])))
	if _camera != null and data.get("camera") is Dictionary and version < POSE_VERSION:
		var cam: Dictionary = data["camera"]
		_set_global(_camera, _str_to_transform(str(cam.get("transform", ""))))
		_camera.fov = float(cam.get("fov", _camera.fov))
	print("[poselab] loaded %s (version %d)" % [pose_path, version])


func _reset() -> void:
	if _pony != null:
		for ap in _pony.find_children("*", "AnimationPlayer", true, false):
			(ap as AnimationPlayer).stop()
	# Reset to the imported rest pose. Writing identity rotations would collapse
	# the mesh, because the glb bakes the rest transform into the bone pose.
	if _pony_skel != null:
		_pony_skel.reset_bone_poses()
		_pony_skel.force_update_all_bone_transforms()
	for sk in _anon_skels:
		if sk != null:
			sk.reset_bone_poses()
			sk.force_update_all_bone_transforms()
	print("[poselab] reset to rest pose")


func _capture() -> void:
	# In the editor the viewport may not render. Capture the JSON now; the editor
	# screenshot is the user's own. The game's capture path is separate.
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var dir := "user://poselab_capture"
	DirAccess.make_dir_recursive_absolute(dir)
	_save_pose()
	var out := dir.path_join("pose_%s.json" % stamp)
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file != null:
		file.store_string(FileAccess.get_file_as_string(pose_path))
	print("[poselab] capture saved to %s" % out)


func _toggle_colliders() -> void:
	show_colliders = not show_colliders
	for node in find_children("*", "CollisionShape3D", true, false):
		(node as CollisionShape3D).visible = show_colliders
	print("[poselab] colliders=%s" % str(show_colliders))


func _toggle_skeleton() -> void:
	show_skeleton = not show_skeleton
	for node in find_children("*", "Skeleton3D", true, false):
		var sk := node as Skeleton3D
		sk.visible = show_skeleton
		for child in sk.get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).visible = show_skeleton
	print("[poselab] skeleton=%s" % str(show_skeleton))


## Selects the pony Skeleton3D in the editor so the bottom Skeleton panel opens
## without hunting through the expanded sub-scene.
func _select_skeleton() -> void:
	if not Engine.is_editor_hint():
		return
	if _pony_skel == null:
		print("[poselab] no pony skeleton")
		return
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(_pony_skel)
	print("[poselab] selected %s" % _pony_skel.name)


func _select_anon_by_name(name: String) -> void:
	if not Engine.is_editor_hint():
		return
	for rig in _anons:
		if rig.name != name:
			continue
		var index := _anons.find(rig)
		if _anon_skels[index] == null:
			print("[poselab] no %s skeleton" % name)
			return
		var selection := EditorInterface.get_selection()
		selection.clear()
		selection.add_node(_anon_skels[index])
		print("[poselab] selected %s" % _anon_skels[index].name)
		return
	print("[poselab] no %s in this scene" % name)


func _select_anon_skeleton() -> void:
	_select_anon_by_name("Anon1")


func _select_anon2_skeleton() -> void:
	_select_anon_by_name("Anon2")


func _select_anon3_skeleton() -> void:
	_select_anon_by_name("Anon3")


## Saves only bones that differ from rest, as a delta pose instead of a dump of all imported rest
## transforms. `allowed` limits the export to the body bones the runtime bakes; empty means every
## changed bone (the Anon rig).
func _save_bones(sk: Skeleton3D, allowed: Array) -> Dictionary:
	var out := {}
	if sk == null:
		return out
	for i in sk.get_bone_count():
		var name := sk.get_bone_name(i)
		if not allowed.is_empty() and not allowed.has(name):
			continue
		var pose_rot := sk.get_bone_pose_rotation(i)
		var pose_pos := sk.get_bone_pose_position(i)
		var rest := sk.get_bone_rest(i)
		# absf(dot) so q and -q count as the same rotation; angle_to would report
		# a near-full turn for the double cover and save untouched bones.
		if absf(pose_rot.dot(rest.basis.get_rotation_quaternion())) > 0.99999 \
				and pose_pos.distance_to(rest.origin) < 0.0001:
			continue
		out[name] = {
			"rotation": _quat_to_str(pose_rot),
			"position": _vec_to_str(pose_pos),
		}
	return out


func _load_bones(sk: Skeleton3D, bones: Variant) -> void:
	if sk == null:
		return
	sk.reset_bone_poses()
	if not bones is Dictionary:
		return
	for bone in (bones as Dictionary):
		var i := sk.find_bone(str(bone))
		if i < 0:
			continue
		var entry: Dictionary = (bones as Dictionary)[bone]
		sk.set_bone_pose_rotation(i, _str_to_quat(str(entry.get("rotation", ""))))
		sk.set_bone_pose_position(i, _str_to_vec(str(entry.get("position", ""))))
	sk.force_update_all_bone_transforms()


## Old version-3 files also carried the six IK target markers. Version 4 derives the Anon pose
## from his bones, so the runtime no longer needs them; it still reads them for old files.
func _load_targets(rig: Node3D, targets: Variant) -> void:
	if not targets is Dictionary:
		return
	for name in (targets as Dictionary):
		var target := rig.find_child(str(name), true, false)
		if target is Node3D:
			(target as Node3D).global_transform = _str_to_transform(str((targets as Dictionary)[name]))


func _transform_to_str(value: Transform3D) -> String:
	return var_to_str(value)


func _str_to_transform(value: String) -> Transform3D:
	if value.is_empty():
		return Transform3D.IDENTITY
	var parsed: Variant = str_to_var(value)
	return parsed if parsed is Transform3D else Transform3D.IDENTITY


func _vec_to_str(value: Vector3) -> String:
	return var_to_str(value)


func _str_to_vec(value: String) -> Vector3:
	if value.is_empty():
		return Vector3.ZERO
	var parsed: Variant = str_to_var(value)
	return parsed if parsed is Vector3 else Vector3.ZERO


func _quat_to_str(value: Quaternion) -> String:
	return var_to_str(value)


func _str_to_quat(value: String) -> Quaternion:
	if value.is_empty():
		return Quaternion.IDENTITY
	var parsed: Variant = str_to_var(value)
	return parsed if parsed is Quaternion else Quaternion.IDENTITY
