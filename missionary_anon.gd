extends Node
## The act's Anon body: the game's own desktop `AnonBody`, placed in bed space and posed from the
## asset's `anon` block. He is a puppet for the act: his body IK, desktop pose driver and his own
## `_process` are turned off and his bones are written at render time, exactly like the pony's, so
## nothing else on his rig wins. The act never moves his player node: only this body is placed on
## the bed.
##
## The asset carries every bone of his rig, so the file is the whole pose (see `poses/pose_lab.gd`).

const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const MOTION := preload("res://mods/unfplap/act_motion.gd")
const HIP := preload("res://mods/unfplap/anon_hip_thrust.gd")
const RIG := preload("res://mods/unfplap/poses/pose_rig.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")

## The lean hinges his whole upper body at this joint: chest, neck, head, shoulders, arms and hands
## follow as one, while the hips, thighs and legs keep the authored pose and the stroke, so the
## lower body still thrusts. The camera is his head, so this is also what moves the act view.
const LEAN_HINGE := "Spine"
## Share of the stroke offset lifted straight up, so the pelvis rides up her body instead of only
## driving along the mattress.
const HIP_UP_SHARE := 0.25
## The eye-to-mouth offset human Anon uses (`player/player_mouth.gd`), camera-local metres at
## scale 1. The kiss and her gaze aim at this, never at the standing player rig.
const MOUTH_OFFSET := Vector3(0.0, -0.07, -0.02)

var runtime: Node
var main: Variant
var avatar: Node3D
var skeleton: Skeleton3D
## True once a body was found and is being driven by this controller.
var active := false

var _body_ik: SkeletonModifier3D
var _body_ik_was_active := true
var _leg_hide: SkeletonModifier3D
var _leg_hide_influence := 0.0
var _driver: Variant
var _avatar_visible := true
var _avatar_process := Node.PROCESS_MODE_INHERIT
var _avatar_processing := true
var _avatar_transform := Transform3D.IDENTITY
var _scale := Vector3.ONE
## The game's own eye offset from the head bone. `anon_body.gd` puts the camera at the head joint
## offset by `head_offset` (less `desktop_body_forward`) and turns it by `REST_FACING`, and
## `valve_body_ik.gd` turns the head bone to `target * rest`, so the bone-to-camera rotation is
## `rest⁻¹ * REST_FACING`. Built from those values rather than read off the live camera: the live
## camera is still the reclined bed view when the act installs.
var _eye_rel := Transform3D.IDENTITY
var _eye_saved := false
## The eye this frame, cached right after the authored write and the lean. `HeadHide` collapses
## the head bone later in the frame, and the head mesh (which also holds the hands) is never hidden,
## so the camera has to read the pose we wrote rather than the collapsed bone.
var _eye_world := Transform3D.IDENTITY
var _eye_cached := false
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
	_avatar_processing = avatar.is_processing()
	_avatar_transform = avatar.transform
	_scale = avatar.scale
	# His own drivers: the desktop pose driver poses the torso and the body IK the limbs. Both are
	# parked for the act; the pose we write is the only pose.
	_driver = avatar.get("desktop_pose_driver")
	avatar.set("desktop_pose_driver", null)
	# Only the body IK is parked: it is the *pose driver* (it builds his body from the player camera
	# markers, i.e. the standing body). Every hider stays on: they only hide parts.
	var ik: Variant = avatar.get("_body_ik")
	if not is_instance_valid(ik):
		ik = avatar.find_child("BodyIK", true, false)
	if ik is SkeletonModifier3D:
		_body_ik = ik as SkeletonModifier3D
		_body_ik_was_active = _body_ik.active
		_body_ik.active = false
	# His own `_process` drives the IK targets, the height feedback, the finger curl and `LegHide`.
	# The act writes all of that itself; left running, the mattress-height camera reads as a crouch
	# (`seated`) and the game collapses his legs, and `_update_fists` rewrites the authored fingers
	# every frame. Only that node's process stops: the skeleton and its modifiers keep updating.
	avatar.set_process(false)
	# The legs are part of the authored pose: never let the last seated state collapse them. The
	# modifier stays active, just at zero.
	var leg_hide: Variant = avatar.find_child("LegHide", true, false)
	if leg_hide is SkeletonModifier3D:
		_leg_hide = leg_hide as SkeletonModifier3D
		_leg_hide_influence = float(_leg_hide.get("influence"))
		_leg_hide.set("influence", 0.0)
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
	_eye_cached = false
	# The head mesh is never hidden: `head_smd` holds the head **and the hands**, so hiding it is
	# what removes the palms. The game's `HeadHide` collapses only the head bone, which hides the
	# head vertices and leaves the hands; the eye is cached before that collapse each frame.
	avatar.visible = true
	active = true
	return true


func remove() -> void:
	active = false
	_eye_cached = false
	if is_instance_valid(_leg_hide):
		_leg_hide.set("influence", _leg_hide_influence)
	if is_instance_valid(_body_ik):
		_body_ik.active = _body_ik_was_active
	_leg_hide = null
	_body_ik = null
	if is_instance_valid(avatar):
		avatar.set("desktop_pose_driver", _driver)
		# The act wrote his world placement every frame; put the rig back exactly where the
		# presentation left it, then hand it back.
		avatar.transform = _avatar_transform
		avatar.set_process(_avatar_processing)
		avatar.visible = _avatar_visible
		avatar.process_mode = _avatar_process
		_log("anon restore transform=%s process=%s leg=%.2f" % [
			str(_avatar_transform.origin), str(_avatar_processing), _leg_hide_influence])
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
			# Own the scale too: the stock hiders multiply/overwrite it each modifier pass and rely
			# on the animation to reset it. Without this the factor compounds and the body stretches
			# or collapses. Parts they hide stay hidden by their own bones, not by ours.
			skeleton.set_bone_pose_scale(bone, skeleton.get_bone_rest(bone).basis.get_scale())
	# The attached alignment asks for the pelvis offset that puts the shaft in her; the authored
	# path adds to it. Both reach the hips first and fade out up the spine, with the neck, head and
	# planted legs pinned, so his shoulders and the camera move much less than his pelvis.
	var offset: Vector3 = bed_frame.basis * (stroke * body_scale) + _hip_offset()
	if offset.length_squared() > 0.0000001:
		offset += Vector3.UP * (offset.length() * HIP_UP_SHARE)
	_apply_hip_motion(offset)
	_note_hip_offset(offset)
	_apply_lean(placed)
	_cache_eye()


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


## Tilt the whole upper body about the Spine joint: the base debug lean plus the act's W/S/Q/E
## lean, leaving his hips and legs on the authored pose so the lower body still thrusts. The view
## is his head, so this is what moves the camera.
func _apply_lean(placed: Transform3D) -> void:
	if not is_instance_valid(runtime) or not is_instance_valid(skeleton):
		return
	var forward: Variant = runtime.call("shot_lean_forward")
	var side: Variant = runtime.get("_lean_view_side")
	var lean_forward := float(forward) if forward is float or forward is int else 0.0
	var lean_side := float(side) if side is float or side is int else 0.0
	var scale: Variant = runtime.call("_lean_size_scale")
	var lean_scale := float(scale) if scale is float or scale is int else 1.0
	# Positive leans him back: the eyes lift off her and the camera clears the belly. The debug
	# setting is signed and unbounded, so the direction can be flipped live in the lab. W then tips
	# the same hinge forward/down toward her, S back/up.
	var base := deg_to_rad(SETTINGS.upper_lean_deg.get_num())
	var pitch := -base + deg_to_rad(MOTION.LEAN_PITCH_DEG * 3.0) * lean_forward * lean_scale
	var yaw := -deg_to_rad(MOTION.LEAN_SIDE_YAW_DEG * 4.0) * lean_side * lean_scale
	if absf(pitch) < 0.00001 and absf(yaw) < 0.00001:
		return
	if not _lean_logged:
		_lean_logged = true
		_log("anon lean base=%.1f fwd=%.2f side=%.2f scale=%.2f pitch=%.1f°" % [
			rad_to_deg(base), lean_forward, lean_side, lean_scale, rad_to_deg(pitch)])
	# His body is lying, so the nod and the turn are the bed's own axes: nod along the mattress,
	# turn about the mattress normal. Both are converted into skeleton space once.
	var to_sk := skeleton.global_basis.inverse()
	var nod := (to_sk * placed.basis.x).normalized()
	var turn := (to_sk * placed.basis.y).normalized()
	var bone := skeleton.find_bone(LEAN_HINGE)
	if bone < 0:
		return
	# Rotating the *global* pose about the skeleton-space axis hinges everything above the joint.
	# Pre-multiplying the bone's local pose instead applies the axis in the parent's frame, and his
	# hips are rotated ~90° here, so W/S yawed the view sideways instead of nodding it.
	var pose: Transform3D = skeleton.get_bone_global_pose(bone)
	pose.basis = Basis(nod, pitch) * Basis(turn, yaw) * pose.basis
	RIG.set_global(skeleton, bone, pose)


## The act camera's transform: his posed head plus the game's own eye offset. Reads the eye cached
## by `apply()` for this frame, before the game's `HeadHide` collapses the head bone.
func eye_transform() -> Variant:
	if not active or not _eye_cached:
		return null
	return _eye_world


## His eye in world space, for her gaze and the aim diagnostics.
func eye_point() -> Vector3:
	var eye: Variant = eye_transform()
	return (eye as Transform3D).origin if eye is Transform3D else Vector3.INF


## His mouth in world space: the eye plus the game's own eye-to-mouth offset. The kiss and her gaze
## must aim at the authored body, never at the standing player rig the game camera still sits on.
func mouth_point() -> Vector3:
	var eye: Variant = eye_transform()
	if not (eye is Transform3D) or not (eye as Transform3D).origin.is_finite():
		return Vector3.INF
	var scale := 1.0
	if is_instance_valid(runtime) and runtime.has_method("_anon_height_scale"):
		scale = float(runtime.call("_anon_height_scale"))
	return (eye as Transform3D).origin + (eye as Transform3D).basis * (MOUTH_OFFSET * scale)


## Read the eye from the bone we just wrote, never from the head after `HeadHide` has collapsed it.
func _cache_eye() -> void:
	_eye_cached = false
	if not is_instance_valid(skeleton) or not _eye_saved:
		return
	var head := skeleton.find_bone("Head")
	if head < 0:
		return
	var head_world := skeleton.global_transform * skeleton.get_bone_global_pose(head)
	if not head_world.is_finite():
		return
	var eye := head_world * _eye_rel
	if not eye.is_finite():
		return
	_eye_world = eye
	_eye_cached = true


## One debug line per act: his body scale, the bones that are not at rest, what is still driving
## him, and where the eye actually points. A stretch names the bone here instead of guessing.
func diag_row(face: Vector3, vulva: Vector3) -> String:
	if not is_instance_valid(avatar) or not is_instance_valid(skeleton):
		return "inactive"
	var world := avatar.global_transform.basis.get_scale()
	var lo := INF
	var hi := 0.0
	var odd: Array[String] = []
	for i in skeleton.get_bone_count():
		var s := skeleton.get_bone_pose_scale(i)
		var m := maxf(absf(s.x), maxf(absf(s.y), absf(s.z)))
		if m > 0.01:
			lo = minf(lo, m)
			hi = maxf(hi, m)
		if (m > 1.5 or (m < 0.5 and m > 0.01)) and odd.size() < 6:
			odd.append("%s=%.2f" % [skeleton.get_bone_name(i), m])
	var row := "avatar_scale=(%.2f,%.2f,%.2f) bone_scale=%.2f..%.2f process=%s body_ik=%s legs=%.2f" % [
		world.x, world.y, world.z, lo if lo < INF else 0.0, hi,
		str(avatar.is_processing()),
		str(_body_ik.active) if is_instance_valid(_body_ik) else "null",
		float(_leg_hide.get("influence")) if is_instance_valid(_leg_hide) else -1.0]
	if not odd.is_empty():
		row += " odd=[%s]" % ", ".join(odd)
	var part: Variant = main.get("anon_part") if is_instance_valid(main) else null
	if part != null and part.has_method("showing") and bool(part.call("showing")):
		var part_scale: Variant = part.call("debug_scale") if part.has_method("debug_scale") else null
		if part_scale is Vector3:
			row += " part_scale=(%.2f,%.2f,%.2f)" % [
				(part_scale as Vector3).x, (part_scale as Vector3).y, (part_scale as Vector3).z]
	var eye: Variant = eye_transform()
	if eye is Transform3D:
		var at := (eye as Transform3D).origin
		var fwd: Vector3 = -(eye as Transform3D).basis.z.normalized()
		if face.is_finite() and at.distance_squared_to(face) > 0.0001:
			row += " eye_face=%.0f°" % rad_to_deg(fwd.angle_to((face - at).normalized()))
		if vulva.is_finite() and at.distance_squared_to(vulva) > 0.0001:
			row += " eye_vulva=%.0f°" % rad_to_deg(fwd.angle_to((vulva - at).normalized()))
	return row


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
