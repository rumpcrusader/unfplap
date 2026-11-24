extends RefCounted
## The pose diagnostics: the base record, the debug rows and the settled log.

const BASE_INFO := preload("res://mods/unfplap/poses/pose_base_info.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")


## Which missionary base is in charge and why, in one record so the log, the settled line and the
## debug action cannot drift apart.
static func base_info(session: Variant) -> BASE_INFO:
	var info := BASE_INFO.new()
	var live_id: String = session._live_spec_id()
	var asset: AUTHORED = session._readiness_asset()
	info.asset = asset
	info.bones = asset.pony_bones.size()
	info.available = asset.available
	info.error = asset.error
	info.frame = session._pose_frame()
	info.frame_kind = str(session._view.frame)
	info.shots = asset.has_shots
	info.asset_path = session._asset_path_for(live_id)
	info.live_path = info.asset_path
	info.target_path = session._asset_path_for(session._target_id) \
		if session._target_spec != null else info.live_path
	info.asset_frame = asset.frame
	info.variant = asset.variant
	if live_id.is_empty():
		info.reason = "pose="
	elif info.live_path.is_empty():
		info.reason = "pose=%s" % live_id
	elif not asset.available:
		info.reason = session.readiness().asset_verdict(live_id).reason
	elif not session._has_frame(info.frame):
		info.reason = "no %s frame" % str(session._view.frame)
	elif not asset.usable(str(session._view.frame)):
		info.reason = session.readiness().asset_verdict(live_id).reason
	else:
		info.base = "authored"
	return info


## Render-time placement trace, printed from idle after every writer of the frame so it reads the
## pose the renderer is about to use; `diag_root` is the armature bone the placement is written to.
static func trace_sample(session: Variant, state: int, handle: Variant) -> void:
	var pony: Variant = session._pony()
	if handle._trace_frames >= 2 or str(session._view.frame) != "bed" or state == 0:
		return
	var pose_node: Variant = session._pose_node
	if not is_instance_valid(pose_node) or session._basis_amount() < 0.9:
		return
	var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not sk is Skeleton3D:
		return
	var skeleton := sk as Skeleton3D
	var root: int = pose_node.diag_root
	var hips := skeleton.find_bone("pony_hips")
	var g := skeleton.global_transform
	var render_root := g * skeleton.get_bone_global_pose(root) if root >= 0 else Transform3D.IDENTITY
	var render_hips := g * skeleton.get_bone_global_pose(hips) if hips >= 0 else Transform3D.IDENTITY
	var wanted_root: Transform3D = pose_node.diag_root_wanted
	var wanted_hips: Transform3D = pose_node.diag_hips_wanted
	var animation: Variant = pony.get("animation")
	var clip := ""
	var playing := false
	if animation is AnimationPlayer:
		clip = (animation as AnimationPlayer).current_animation
		playing = (animation as AnimationPlayer).is_playing()
	LOG.debug("pose trace f=%d root=%d:%s asset_root=%d trace=%d mode=%d clip=%s playing=%s G=%s", [
		handle._trace_frames, root, str(pose_node.diag_root_name), pose_node.diag_asset_root,
		pose_node.diag_trace, skeleton.modifier_callback_mode_process, clip, str(playing),
		str(g)])
	LOG.debug("pose trace f=%d root start=%s after=%s render=%s wanted=%s d=%.3f/%.3f | hips start=%s render=%s wanted=%s d=%.3f", [
		handle._trace_frames, str(pose_node.diag_root_start), str(pose_node.diag_root_after),
		str(render_root), str(wanted_root),
		render_root.origin.distance_to(wanted_root.origin),
		_transform_angle(render_root, wanted_root),
		str(pose_node.diag_hips_start), str(render_hips), str(wanted_hips),
		render_hips.origin.distance_to(wanted_hips.origin)])
	handle._trace_frames += 1


## Degrees between two transforms' bases, for the trace.
static func _transform_angle(a: Transform3D, b: Transform3D) -> float:
	return rad_to_deg(a.basis.orthonormalized().get_rotation_quaternion().angle_to(
		b.basis.orthonormalized().get_rotation_quaternion()))


## Rig, modifier and posture diagnostics: which skeleton the modifier drives, which skeleton every
## mesh is actually bound to, whether the pose survives between frames, and who else is near the bed.
static func rows(session: Variant, skeleton: Skeleton3D, info: BASE_INFO) -> Array[String]:
	var pony: Variant = session._pony()
	var out: Array[String] = []
	var modifier: Variant = session._pose_node
	var parent: Node = modifier.get_parent() if is_instance_valid(modifier) else null
	out.append("modifier=%s parent=%s match=%s frames=%d weight=%.2f base=%s readback=%.2f°" % [
		"yes" if is_instance_valid(modifier) else "no",
		"%s@%s" % [str(parent.name), str(parent.get_instance_id())] if parent != null else "none",
		"yes" if parent == skeleton else "NO", modifier.diag_frames if is_instance_valid(modifier) else 0,
		modifier.diag_last_weight if is_instance_valid(modifier) else 0.0,
		modifier.diag_last_base if is_instance_valid(modifier) else "",
		modifier.diag_readback_deg if is_instance_valid(modifier) else 0.0])
	var modifiers: Array[String] = []
	for child: Node in skeleton.get_children():
		if child is SkeletonModifier3D:
			var active: Variant = child.get("active")
			var influence: Variant = child.get("influence")
			modifiers.append("%s%s%s" % [
				str(child.name),
				(" active=%s" % str(active)) if active != null else "",
				(" inf=%.2f" % float(influence)) if influence is float else ""])
	out.append("skeleton modifiers=%d [%s]" % [modifiers.size(), ", ".join(modifiers)])
	out.append("hips write check: after_write=%.2f° readback=%.2f° (%s)" % [
		modifier.diag_after_write_deg if is_instance_valid(modifier) else 0.0,
		modifier.diag_readback_deg if is_instance_valid(modifier) else 0.0,
		"write lands, survives" if is_instance_valid(modifier)
			and modifier.diag_after_write_deg < 1.0
			and modifier.diag_readback_deg < 1.0
		else "write lands, lost by next frame" if is_instance_valid(modifier)
			and modifier.diag_after_write_deg < 1.0
		else "write does not land"])
	out.append("pony_skeleton=%s@%s actor=%s paused=%s visible=%s" % [
		str(skeleton.name), str(skeleton.get_instance_id()), str(pony.global_position),
		str(pony.get("motion_paused")), str(pony.visible)])
	var posture: Variant = pony.get("posture")
	if posture != null:
		out.append("posture kind=%s requested=%s phase=%s progress=%.2f ready=%s clip=%s refusal=%s" % [
			str(posture.get("kind")), str(posture.get("requested")), str(posture.get("phase")),
			_num(posture.get("progress")), str(posture.get("ready")), str(posture.get("clip")),
			str(posture.get("refusal"))])
	# Every mesh's own skeleton: a mesh bound elsewhere would follow the game's animation instead of
	# the pose modifier.
	var groups: Dictionary = {}
	for node: Node in pony.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var target: Node = mesh.get_node_or_null(mesh.skeleton) if not mesh.skeleton.is_empty() else null
		var instance := target.get_instance_id() if target != null else 0
		if not groups.has(instance):
			groups[instance] = {"count": 0, "sample": str(mesh.name), "visible": false, "target": target}
		var entry: Dictionary = groups[instance]
		entry["count"] = int(entry["count"]) + 1
		entry["visible"] = bool(entry["visible"]) or mesh.is_visible_in_tree()
	for instance: Variant in groups:
		var entry: Dictionary = groups[instance]
		var target: Variant = entry["target"]
		var hips := Vector3.INF
		if target is Skeleton3D:
			var bone := (target as Skeleton3D).find_bone("pony_hips")
			if bone >= 0:
				hips = (target as Skeleton3D).global_transform * (target as Skeleton3D).get_bone_global_pose(bone).origin
		out.append("mesh_skeleton=%s meshes=%d sample=%s visible=%s hips=%s" % [
			("%s@%s" % [str((target as Node).name), str(instance)]) if target is Node else "none",
			int(entry["count"]), str(entry["sample"]), str(entry["visible"]), str(hips)])
	# Live hips pose vs the authored quaternion: proves whether the modifier's write is what lives.
	var asset: AUTHORED = info.asset
	var hips_bone := skeleton.find_bone("pony_hips")
	if hips_bone >= 0 and asset != null:
		var entry: Variant = asset.pony_bones.get("pony_hips")
		if entry is Dictionary:
			var wanted: Quaternion = (entry as Dictionary)["rotation"]
			var live := skeleton.get_bone_pose_rotation(hips_bone)
			out.append("hips_pose live=%s authored=%s delta=%.1f°" % [
				str(live), str(wanted), rad_to_deg(live.angle_to(wanted))])
	# Nearby ponies, so a body on the bed can be identified as someone else.
	var nearest: Array = []
	var tree: SceneTree = pony.get_tree() if is_instance_valid(pony) else null
	if tree != null:
		for node: Node in tree.get_nodes_in_group("ai_characters"):
			var other := node as Node3D
			if other == null or other == pony:
				continue
			var distance := other.global_position.distance_to(pony.global_position)
			if distance > 4.0:
				continue
			var other_sk: Variant = other.get("skeleton")
			var hips_at := Vector3.INF
			if other_sk is Skeleton3D:
				var b := (other_sk as Skeleton3D).find_bone("pony_hips")
				if b >= 0:
					hips_at = (other_sk as Skeleton3D).global_transform * (other_sk as Skeleton3D).get_bone_global_pose(b).origin
			nearest.append("%s d=%.1f posture=%s hips=%s" % [
				str(other.name), distance,
				WORLD.pony(other).posture_requested(), str(hips_at)])
	out.append("nearby=%d %s" % [nearest.size(), "; ".join(nearest)])
	return out


## Multi-row pose diagnostic for the debug action: base source, asset state, bed frame and where
## the live pose actually put her (world and bed space).
static func state_rows(session: Variant, state: int) -> Array[String]:
	var pony: Variant = session._pony()
	var info := base_info(session)
	var frame: Transform3D = info.frame
	var out: Array[String] = []
	out.append("pony=%s pose=%s state=%d weight=%.2f" % [
		str(pony.name) if is_instance_valid(pony) else "?", str(session._view.id), state,
		session._basis_amount()])
	out.append("base=%s reason=%s %s path=%s frame=%s variant=%s bones=%d missing=%s shots=%s error=%s" % [
		info.base, info.reason, "ok" if info.available else "error",
		info.asset_path, info.asset_frame, info.variant, info.bones,
		str(session.readiness().rig_verdict("").missing), "yes" if info.shots else "no", info.error])
	var target_path := info.target_path
	if not target_path.is_empty() and target_path != info.asset_path:
		out.append("target=%s" % target_path)
	out.append("frame=%s kind=%s scale=%.2f" % [
		str(frame) if session._has_frame(frame) else "null", info.frame_kind,
		_body_scale(session)])
	var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not sk is Skeleton3D:
		return out
	var skeleton := sk as Skeleton3D
	out.append_array(rows(session, skeleton, info))
	var space := Transform3D.IDENTITY
	if session._has_frame(frame):
		space = frame.affine_inverse()
	for pair: Array in [["hips", "pony_hips"], ["neck", "pony_neck1"], ["neck_mid", "pony_neck2"],
			["head", "pony_head"], ["hoof_l", "pony_hoof_L"], ["hoof_r", "pony_hoof_R"]]:
		var bone := skeleton.find_bone(str(pair[1]))
		if bone < 0:
			continue
		var world := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		var bed := space * world
		out.append("%s world=(%.3f,%.3f,%.3f) bed=(%.3f,%.3f,%.3f)" % [
			str(pair[0]), world.x, world.y, world.z, bed.x, bed.y, bed.z])
	return out


## The base line written once when the act builds its pose.
static func log_base(session: Variant) -> void:
	var info := base_info(session)
	var frame: Transform3D = info.frame
	var missing: Array[String] = session.readiness().rig_verdict("").missing
	LOG.debug("pose base=%s reason=%s %s path=%s frame=%s variant=%s bones=%d missing=%d shots=%s frame_pose=%s scale=%.2f", [
		info.base, info.reason,
		"ok" if info.available else "error", info.asset_path,
		info.asset_frame, info.variant, info.bones,
		missing.size(), "yes" if info.shots else "no",
		str(frame) if session._has_frame(frame) else "null", _body_scale(session)])
	if not missing.is_empty():
		LOG.debug("pose rig %s", [session.readiness().rig_verdict("").reason])


## One line with where the pose actually put her, in world and bed space, once the weight settles.
static func log_settled(session: Variant, state: int, anon_diag: Callable, handle: Variant) -> void:
	var pony: Variant = session._pony()
	if handle._pose_logged or str(session._view.frame) != "bed" or state == 0:
		return
	if session._basis_amount() < 0.9:
		return
	handle._pose_logged = true
	if not is_instance_valid(pony):
		return
	var sk: Variant = pony.get("skeleton")
	if not sk is Skeleton3D:
		return
	var skeleton := sk as Skeleton3D
	var space := Transform3D.IDENTITY
	var bed: Variant = session._bed_frame
	if bed is Transform3D:
		space = (bed as Transform3D).affine_inverse()
	var parts: Array[String] = []
	for pair: Array in [["hips", "pony_hips"], ["neck", "pony_neck1"], ["head", "pony_head"],
			["hoof_l", "pony_hoof_L"], ["hoof_r", "pony_hoof_R"]]:
		var bone := skeleton.find_bone(str(pair[1]))
		if bone < 0:
			continue
		var world := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		var at := space * world
		parts.append("%s=w%s/b(%.3f,%.3f,%.3f)" % [
			str(pair[0]), str(world), at.x, at.y, at.z])
	LOG.debug("missionary settled base=%s weight=%.2f %s", [
		base_info(session).base, session._basis_amount(), " ".join(parts)])
	for row: String in rows(session, skeleton, base_info(session)):
		LOG.debug("missionary diag %s", [str(row)])
	if anon_diag.is_valid():
		var text := str(anon_diag.call())
		if not text.is_empty():
			LOG.debug("anon diag %s", [text])


## Absolute body scale from the rig's own pivot, 1.0 when the pony is gone.
static func _body_scale(session: Variant) -> float:
	var pony: Variant = session._pony()
	var value: Variant = pony.get("body_scale") if is_instance_valid(pony) else null
	return float(value) if value != null else 1.0


## Numeric read of a Variant property without tripping over a missing one.
static func _num(value: Variant, fallback := 0.0) -> float:
	return float(value) if value is float or value is int else fallback
