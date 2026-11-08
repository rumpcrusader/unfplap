extends Node
## The act's Anon body: the game's own desktop `AnonBody`, placed in bed space and posed from the
## asset's `anon` block. He is a puppet for the act — his body IK and desktop pose driver are turned
## off and his bones are written at render time, exactly like the pony's, so nothing else on his rig
## wins. The act never moves his player node: only this body is placed on the bed.
##
## The asset carries every bone of his rig, so the file is the whole pose (see `poses/pose_lab.gd`).

const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const MOTION := preload("res://mods/unfplap/act_motion.gd")
const HIP := preload("res://mods/unfplap/anon_hip_thrust.gd")
const RIG := preload("res://mods/unfplap/poses/pose_rig.gd")

## The upper-body chain the lean bends, with the share of the lean each bone takes. Everything below
## the spine stays with the authored pose.
const LEAN_CHAIN := [["Spine", 0.20], ["Chest", 0.30], ["UpperChest", 0.20], ["Neck", 0.15],
	["Head", 0.15]]
## Share of the stroke offset lifted straight up, so the pelvis rides up her body instead of only
## driving along the mattress.
const HIP_UP_SHARE := 0.25

var runtime: Node
var main: Variant
var avatar: Node3D
var skeleton: Skeleton3D
## True once a body was found and is being driven by this controller.
var active := false

var _body_ik: SkeletonModifier3D
var _body_ik_was_active := true
var _head_mesh: MeshInstance3D
var _head_mesh_visible := true
var _driver: Variant
var _avatar_visible := true
var _avatar_process := Node.PROCESS_MODE_INHERIT
var _scale := Vector3.ONE
## The game's own eye offset from the head bone. `anon_body.gd` puts the camera at the head joint
## offset by `head_offset` (less `desktop_body_forward`) and turns it by `REST_FACING`, and
## `valve_body_ik.gd` turns the head bone to `target * rest`, so the bone-to-camera rotation is
## `rest⁻¹ * REST_FACING`. Built from those values rather than read off the live camera: the live
## camera is still the reclined bed view when the act installs.
var _eye_rel := Transform3D.IDENTITY
var _eye_saved := false
var _eye_logged := false
var _lean_logged := false
var _indices: Dictionary = {}
var _index_skeleton := 0


func install(runtime_node: Node) -> bool:
	runtime = runtime_node
	main = runtime.get("main") if is_instance_valid(runtime) else null
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return false
	avatar = main.player.find_child("AnonBody", true, false) as Node3D
	if not is_instance_valid(avatar):
		return false
	skeleton = avatar.find_child("Skeleton3D", true, false) as Skeleton3D
	if not is_instance_valid(skeleton):
		return false
	_avatar_visible = avatar.visible
	_avatar_process = avatar.process_mode
	_scale = avatar.scale
	# His own drivers: the desktop pose driver poses the torso and the body IK the limbs. Both are
	# parked for the act; the pose we write is the only pose.
	_driver = avatar.get("desktop_pose_driver")
	avatar.set("desktop_pose_driver", null)
	# Only the body IK is parked: it is the *pose driver* (it builds his body from the player camera
	# markers, i.e. the standing body), and its head step slerps a basis the head hider collapses,
	# which spams "must be normalized". Every hider stays on: they only hide parts.
	var ik: Variant = avatar.get("_body_ik")
	if not is_instance_valid(ik):
		ik = avatar.find_child("BodyIK", true, false)
	if ik is SkeletonModifier3D:
		_body_ik = ik as SkeletonModifier3D
		_body_ik_was_active = _body_ik.active
		_body_ik.active = false
	# The desktop eye relative to the head bone, from the body's own values. `REST_FACING` is a
	# 180° yaw, so its inverse is itself.
	var offset: Variant = avatar.get("head_offset")
	var head_offset: Vector3 = offset if offset is Vector3 else Vector3(0, -0.089, 0.083)
	var forward: Variant = avatar.get("desktop_body_forward")
	if forward is float or forward is int:
		head_offset.z -= float(forward)
	var scale_value: Variant = avatar.get("model_scale")
	var model_scale := float(scale_value) if scale_value is float or scale_value is int else 1.0
	var head := skeleton.find_bone("Head")
	var rest := skeleton.get_bone_global_rest(head).basis.orthonormalized() if head >= 0 \
		else Basis.IDENTITY
	var facing := rest.inverse() * Basis(Vector3.UP, PI)
	_eye_rel = Transform3D(facing, -(facing * head_offset * model_scale))
	_eye_saved = true
	# Sanity check with the game still driving him: `valve_body_ik` sets the head bone to
	# `target * rest`, so undoing that with `rest⁻¹` must give the head target's own basis.
	var marker: Variant = avatar.get("_head_target")
	if head >= 0 and marker is Node3D:
		var bone_basis := (skeleton.global_transform
			* skeleton.get_bone_global_pose(head)).basis.orthonormalized()
		var predicted := bone_basis * rest.inverse()
		_log("anon eye check err=%.1f°" % rad_to_deg(
			predicted.get_rotation_quaternion().angle_to(
				(marker as Node3D).global_basis.orthonormalized().get_rotation_quaternion())))
	# The game hides the first-person head by collapsing a bone, and may already have done it before
	# this ran. A zero scale leaves a bone with no basis: the eye camera loses its pitch, the head
	# link places the visible head from garbage, and the lean turns to NaN. The head mesh is hidden
	# below instead, and every collapsed bone gets its rest scale back.
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_pose_scale(i).length_squared() < 0.0001:
			skeleton.set_bone_pose_scale(i, skeleton.get_bone_rest(i).basis.get_scale())
	var mesh: Variant = avatar.find_child("head_smd", true, false)
	if mesh is MeshInstance3D:
		_head_mesh = mesh as MeshInstance3D
		_head_mesh_visible = _head_mesh.visible
		_head_mesh.visible = false
	avatar.visible = true
	active = true
	return true


func remove() -> void:
	active = false
	if is_instance_valid(_head_mesh):
		_head_mesh.visible = _head_mesh_visible
	if is_instance_valid(_body_ik):
		_body_ik.active = _body_ik_was_active
	_head_mesh = null
	_body_ik = null
	if is_instance_valid(avatar):
		avatar.set("desktop_pose_driver", _driver)
		avatar.visible = _avatar_visible
		avatar.process_mode = _avatar_process
	avatar = null
	skeleton = null
	_indices.clear()
	_index_skeleton = 0


## Place and pose him from the asset, once per displayed frame. The authored bones are written
## first, then the stroke and the lean on top of them, or the asset would wipe both.
func apply(bed_frame: Transform3D, body_scale: float) -> void:
	if not active or not is_instance_valid(avatar) or not is_instance_valid(skeleton):
		return
	var pose: Variant = AUTHORED.shared()
	if not bool(pose.get("available")):
		return
	var placement: Transform3D = pose.get("anon_frame")
	# The authored stroke path (`anon.travel`, pulled out to fully in) moves his *pelvis*, not his
	# body: his head is the act camera, so sliding the whole body would swing the view on every
	# thrust. Graded below with the alignment offset.
	var stroke := Vector3.ZERO
	if pose.has_method("travel_at"):
		var travel: Variant = pose.call("travel_at", _depth())
		if travel is Transform3D:
			stroke = (travel as Transform3D).origin - placement.origin
	placement.origin *= body_scale
	var placed: Transform3D = bed_frame * placement
	avatar.global_transform = Transform3D(placed.basis * Basis.from_scale(_scale), placed.origin)
	# The presentation parks the body every tick (invisible, processing off); the act needs it shown
	# and its skeleton updating, and its own IK/driver are already neutralised.
	if not avatar.visible:
		avatar.visible = true
	if avatar.process_mode != Node.PROCESS_MODE_INHERIT:
		avatar.process_mode = Node.PROCESS_MODE_INHERIT
	var bones: Dictionary = pose.get("anon_bones")
	if not bones.is_empty():
		_cache_indices(bones)
		for key: Variant in _indices:
			var entry: Variant = bones.get(key)
			if not (entry is Dictionary):
				continue
			var bone := int(_indices[key])
			skeleton.set_bone_pose_rotation(bone, (entry as Dictionary)["rotation"])
			skeleton.set_bone_pose_position(bone, (entry as Dictionary)["position"])
	# The attached alignment asks for the pelvis offset that puts the shaft in her; the authored
	# path adds to it. Both reach the hips first and fade out up the spine, with the neck, head and
	# planted legs pinned, so his shoulders and the camera move much less than his pelvis.
	var offset: Vector3 = bed_frame.basis * (stroke * body_scale) + _hip_offset()
	if offset.length_squared() > 0.0000001:
		offset += Vector3.UP * (offset.length() * HIP_UP_SHARE)
	_apply_hip_motion(offset)
	_note_hip_offset(offset)
	_apply_lean(placed)


## Carry the pelvis on the stroke: the hips take the whole offset, the waist a graded share, and the
## neck, head and both planted legs are restored so the knees and the view stay put (`anon_hip_thrust`
## grades). Moving his whole body instead swung the eye on every thrust.
func _apply_hip_motion(offset_world: Vector3) -> void:
	if offset_world.length_squared() < 0.0000001 or not is_instance_valid(skeleton):
		return
	var hips := skeleton.find_bone("Hips")
	if hips < 0:
		return
	var local := skeleton.global_basis.inverse() * offset_world
	var before := {}
	for name: String in HIP.GRADES:
		var bone := skeleton.find_bone(name)
		if bone >= 0:
			before[name] = skeleton.get_bone_global_pose(bone)
	var pinned := {}
	for name: String in HIP.PINNED:
		var bone := skeleton.find_bone(name)
		if bone >= 0:
			pinned[name] = skeleton.get_bone_global_pose(bone)
	var hip_pose: Transform3D = skeleton.get_bone_global_pose(hips)
	hip_pose.origin += local
	RIG.set_global(skeleton, hips, hip_pose)
	for name: String in HIP.GRADES:
		if not before.has(name):
			continue
		var pose: Transform3D = before[name]
		pose.origin += local * float(HIP.GRADES[name])
		RIG.set_global(skeleton, skeleton.find_bone(name), pose)
	for name: String in HIP.PINNED:
		if pinned.has(name):
			RIG.set_global(skeleton, skeleton.find_bone(name), pinned[name])


## Bend his chest and neck with the act's lean, leaving his hips and legs on the authored pose. The
## view is his head, so this is what makes leaning move the camera.
func _apply_lean(placed: Transform3D) -> void:
	if not is_instance_valid(runtime) or not is_instance_valid(skeleton):
		return
	var forward: Variant = runtime.call("shot_lean_forward")
	var side: Variant = runtime.get("_lean_view_side")
	var lean_forward := float(forward) if forward is float or forward is int else 0.0
	var lean_side := float(side) if side is float or side is int else 0.0
	if absf(lean_forward) < 0.001 and absf(lean_side) < 0.001:
		return
	var scale: Variant = runtime.call("_lean_size_scale")
	var lean_scale := float(scale) if scale is float or scale is int else 1.0
	if not _lean_logged:
		_lean_logged = true
		_log("anon lean fwd=%.2f side=%.2f scale=%.2f" % [
			lean_forward, lean_side, lean_scale])
	# His body is lying, so the nod and the turn are the bed's own axes: nod along the mattress,
	# turn about the mattress normal. Both are converted into skeleton space once.
	var to_sk := skeleton.global_basis.inverse()
	var nod := (to_sk * placed.basis.x).normalized()
	var turn := (to_sk * placed.basis.y).normalized()
	var pitch := -deg_to_rad(MOTION.LEAN_PITCH_DEG * 3.0) * lean_forward * lean_scale
	var yaw := -deg_to_rad(MOTION.LEAN_SIDE_YAW_DEG * 4.0) * lean_side * lean_scale
	for entry: Array in LEAN_CHAIN:
		var bone := skeleton.find_bone(str(entry[0]))
		if bone < 0:
			continue
		var share := float(entry[1])
		# Rotate the *global* pose about the skeleton-space axis. Pre-multiplying the bone's local
		# pose instead applies the axis in the parent's frame, and his hips are rotated ~90° here,
		# so W/S yawed the view sideways instead of nodding it.
		var pose: Transform3D = skeleton.get_bone_global_pose(bone)
		pose.basis = Basis(nod, pitch * share) * Basis(turn, yaw * share) * pose.basis
		RIG.set_global(skeleton, bone, pose)


## The act camera's transform: his posed head plus the game's own eye offset.
func eye_transform() -> Variant:
	if not active or not is_instance_valid(skeleton):
		return null
	var head := skeleton.find_bone("Head")
	if head < 0:
		return null
	var head_world := skeleton.global_transform * skeleton.get_bone_global_pose(head)
	if not _eye_saved:
		return head_world
	var eye := head_world * _eye_rel
	if not _eye_logged:
		_eye_logged = true
		_log("anon eye head=%s facing=%s offset=%s eye=%s" % [
			str(head_world), str(head_world.basis * Basis(Vector3.UP, PI)),
			str(_eye_rel.origin), str(eye)])
	return eye


func _log(text: String) -> void:
	if is_instance_valid(runtime) and runtime.has_method("_log"):
		runtime.call("_log", text)


## The act's depth, 0 (pulled out) to 1 (full).
func _depth() -> float:
	var value: Variant = runtime.get("depth") if is_instance_valid(runtime) else null
	return clampf(float(value), 0.0, 1.0) if value is float or value is int else 0.0


## The pelvis offset the attached alignment asked for this frame, in world space.
func _hip_offset() -> Vector3:
	var part: Variant = main.get("anon_part") if is_instance_valid(main) else null
	if part == null or not bool(part.call("showing")):
		return Vector3.ZERO
	var wanted: Variant = part.call("hip_offset_wanted")
	if wanted is Vector3 and (wanted as Vector3).is_finite():
		return wanted
	return Vector3.ZERO


## Tell the part the offset was applied, so next frame it measures from the moved body.
func _note_hip_offset(offset: Vector3) -> void:
	var part: Variant = main.get("anon_part") if is_instance_valid(main) else null
	if part != null and bool(part.call("showing")):
		part.set("hip_offset_applied", offset)


## Bone indices are stable for the life of the skeleton, so resolve the names once per skeleton.
func _cache_indices(bones: Dictionary) -> void:
	var id := skeleton.get_instance_id()
	if id == _index_skeleton and not _indices.is_empty():
		return
	_indices.clear()
	for key: Variant in bones:
		var bone := skeleton.find_bone(str(key))
		if bone >= 0:
			_indices[str(key)] = bone
	_index_skeleton = id
