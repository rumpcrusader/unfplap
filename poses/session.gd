extends RefCounted
## The act's pose session: the skeleton pose modifier, the authored missionary base, the bed
## frame, the extra modifiers (tail, tail lay, body sway, prone sway, ear twitch, chin debug),
## the bone snapshots and the pose diagnostics. The runtime owns the act state, the start order
## and the one teardown ledger; it binds this session and calls the render-time write.
## Contract: docs/poses.md.

const POSE := preload("res://mods/unfplap/poses/skeleton_pose.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const TAIL := preload("res://mods/unfplap/tail_pose.gd")
const TAIL_LAY := preload("res://mods/unfplap/tail_lay.gd")
const BODY_SWAY := preload("res://mods/unfplap/body_sway.gd")
const PRONE_SWAY := preload("res://mods/unfplap/prone_sway.gd")
const EAR_TWITCH := preload("res://mods/unfplap/ear_twitch.gd")
const CHIN_DEBUG := preload("res://mods/unfplap/chin_debug.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const MATTRESS := preload("res://world/life/couch/mattress.gd")

## The runtime node the scene modifiers log and perf through. It is the host boundary; the
## session never reads the runtime's fields.
var host: Variant = null
var pony: Variant = null

## The act's pose and identity.
var pose_id := ""
var id := ""
var features: Dictionary = {}
var bed_node: Variant = null
## Live pose config. The runtime reads it through its `_pose_cfg` property.
var pose_config: Dictionary = {}

## The pose modifier and the extra scene modifiers the act installs.
var pose_node: Node
var tail: Variant = null
var tail_lay: Node
var body_sway: SkeletonModifier3D
var prone_sway: SkeletonModifier3D
var ear_twitch: SkeletonModifier3D
var chin_modifier: SkeletonModifier3D

## Bed space for the authored pose. The runtime reads it through its `_bed_pose_frame` property.
var bed_frame: Variant = null
var bed_frame_source := Transform3D.IDENTITY
var bed_frame_source_saved := false

## Per-act log and rig-check caches.
var pose_logged := false
var pose_trace_frames := 0
var rig_checked := false
var rig_skeleton := 0
var rig_missing_bones: Array = []

## The pony's pre-act bone snapshot.
var saved_bones: Array[Transform3D] = []
var saved_hair: Array[Transform3D] = []
var saved_skeleton: Skeleton3D
var saved_hair_skeleton: Skeleton3D

## Host boundary. A missing callback is a no-op.
var log := Callable()


func bind(host_node: Variant, pony_node: Variant) -> void:
	host = host_node
	pony = pony_node


func set_pose_config(config: Dictionary) -> void:
	pose_config = config


## Build the pose for a fresh act. `context` carries `pose_id`, `id`, `features`, `bed`,
## `presentation`, `look_point` and `camera_position` from the runtime's start sequence.
func begin(context: Dictionary) -> void:
	pose_id = str(context.get("pose_id", ""))
	id = str(context.get("id", ""))
	features = context.get("features", {})
	bed_node = context.get("bed")
	pose_logged = false
	pose_trace_frames = 0
	var base: Variant = context.get("pose_config")
	pose_config = base if base is Dictionary else SETTINGS.pose(id, pose_id)
	var skeleton: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if skeleton is Skeleton3D:
		pose_node = POSE.new()
		pose_node.name = "UnfplapPose"
		pose_node.mare = pony
		pose_node.set("runtime", host)
		pose_node.mode = "standing" if pose_id == CATALOG.STANDING else "missionary"
		pose_node.pose_config = SETTINGS.pose(id, pose_id)
		var look: Variant = context.get("look_point")
		pose_node.look_point = look if look is Vector3 else pony.global_position
		pose_node.amount = 0.0
		pose_node.target_amount = 1.0
		if pose_id == CATALOG.MISSIONARY:
			bed_frame = missionary_pose_frame()
			bed_frame_source_saved = is_instance_valid(bed_node)
			if bed_frame_source_saved:
				bed_frame_source = (bed_node as Node3D).global_transform
			pose_node.authored = authored()
			pose_node.bed_frame = bed_frame
			log_base()
		(skeleton as Skeleton3D).add_child(pose_node)
		if pose_id == CATALOG.STANDING:
			if _feature("standing_body_sway"):
				_install_body_sway(skeleton)
			if _feature("thrust_ear_twitch"):
				_install_ear_twitch()
		elif _feature("missionary_body_motion"):
			_install_prone_sway(skeleton)
		keep_chin_last()
	if pose_id == CATALOG.MISSIONARY:
		_install_tail_lay()
	if pose_id != CATALOG.STANDING:
		return
	sync_standing_config(context.get("presentation", {}))
	var hair: Variant = pony.get("hair_skeleton")
	if hair is Skeleton3D:
		tail = TAIL.new()
		tail.name = "UnfplapTail"
		tail.mare = pony
		tail.runtime = host
		tail.aside_angle = float(pose_config.get("tail_aside", 0.55))
		tail.lift_angle = float(pose_config.get("tail_lift", 0.42))
		tail.amount = 0.0
		tail.target_amount = 1.0
		var side_anchor: Variant = context.get("camera_position")
		if not side_anchor is Vector3:
			side_anchor = Vector3.INF
		tail.call("choose_side", side_anchor)
		(hair as Skeleton3D).add_child(tail)


## The standing recipe reads these from pose_config every frame. Re-reading the character's pose
## first keeps the other pose overrides, then the presentation neck/head controls win.
func sync_standing_config(presentation: Dictionary) -> bool:
	if pose_id != CATALOG.STANDING or not is_instance_valid(pony):
		return false
	pose_config = SETTINGS.pose(id, CATALOG.STANDING)
	pose_config["chin_up_deg"] = float(presentation.get("chin_up_deg",
		SETTINGS.chin_up_deg.default))
	pose_config["neck_down_deg"] = float(presentation.get("neck_down_deg",
		SETTINGS.neck_down_deg.default))
	var tail_cfg: Variant = presentation.get("tail", {})
	if tail_cfg is Dictionary:
		pose_config["tail_aside"] = deg_to_rad(float((tail_cfg as Dictionary).get("yaw_deg",
			SETTINGS.yaw_deg.default)))
		pose_config["tail_lift"] = deg_to_rad(float((tail_cfg as Dictionary).get("pitch_deg",
			SETTINGS.tail_pitch_deg.default)))
	if is_instance_valid(pose_node):
		pose_node.pose_config = pose_config
	if is_instance_valid(tail):
		tail.aside_angle = float(pose_config.get("tail_aside", 0.55))
		tail.lift_angle = float(pose_config.get("tail_lift", 0.42))
	return true


## The missionary recipe reads these from pose_config every frame. Re-reading the character's
## pose keeps its nuzzle overrides live.
func sync_missionary_config() -> bool:
	if pose_id != CATALOG.MISSIONARY or not is_instance_valid(pony):
		return false
	pose_config = SETTINGS.pose(id, CATALOG.MISSIONARY)
	if is_instance_valid(pose_node):
		pose_node.pose_config = pose_config
		# The asset instance is shared, so the reload action reaches the live act.
		pose_node.authored = authored()
	return true


## The hand-authored missionary base pose. Parsed once for the process; the debug action rewrites
## the same instance in place, so a live act picks the new pose up on its next frame.
func authored() -> Variant:
	return AUTHORED.shared()


## The parsed authored pose, for the shot camera and the debug action.
func authored_asset() -> Variant:
	return authored()


## True when the missionary asset loaded. The act refuses to start otherwise: there is no fallback
## missionary pose any more.
func authored_ready() -> bool:
	return bool(authored().get("available"))


## Why the missionary pose asset is unusable, for the gate row and the start log.
func authored_reason() -> String:
	var asset: Variant = authored()
	if bool(asset.get("available")):
		return ""
	var why := str(asset.get("error"))
	return "pose_asset: %s" % (why if not why.is_empty() else "not loaded")


## The middle of the missionary bed's mattress top: the authored pose's origin in world space.
func missionary_origin() -> Vector3:
	if bed_frame is Transform3D:
		return (bed_frame as Transform3D).origin
	return pony.global_position if is_instance_valid(pony) else Vector3.ZERO


## Bed space for the authored pose: the middle of the real bed's mattress top, in the bed's axes,
## with the pillow end at -Z so the authored `+Z` (her head) points at the head of the bed. The
## pose is stored relative to this frame, so any bed size or yaw works; `null` leaves the
## correction stack in charge.
func missionary_pose_frame() -> Variant:
	if pose_id != CATALOG.MISSIONARY or not is_instance_valid(bed_node):
		return null
	var fallback: float = float(bed_node.get_meta("mattress_top", 0.6)) + float(bed_node.global_position.y)
	var points: Array[Vector3] = [bed_node.global_position]
	var top: float = MATTRESS.visible_top(bed_node, points, fallback)
	if not is_finite(top):
		return null
	var at: Vector3 = bed_node.global_position
	var basis: Basis = bed_node.global_basis.orthonormalized() * Basis(Vector3.UP, PI)
	return Transform3D(basis, Vector3(at.x, top, at.z))


## A bed can move under the act: the Cloudominium's CloudDrift moves it every 0.1 s from
## TimeOfDay.active_seconds. The authored pose, the act body, the camera shot and the anatomy
## placement are all bed-space, so carry them with the bed instead of leaving them at the world
## transform where the act started. The delta is rigid; the mattress top is not re-measured.
func sync_bed_frame() -> void:
	if pose_id != CATALOG.MISSIONARY or not is_instance_valid(bed_node) \
			or not bed_frame_source_saved or not bed_frame is Transform3D:
		return
	var now: Transform3D = bed_node.global_transform
	if now.is_equal_approx(bed_frame_source):
		return
	var delta: Transform3D = now * bed_frame_source.affine_inverse()
	bed_frame = delta * (bed_frame as Transform3D)
	bed_frame_source = now
	if is_instance_valid(pose_node):
		pose_node.bed_frame = bed_frame


## Snapshot before the act changes her posture or the pose writes bones.
func snapshot_bones() -> void:
	saved_bones.clear()
	saved_hair.clear()
	saved_skeleton = null
	saved_hair_skeleton = null
	if not is_instance_valid(pony):
		return
	var sk: Variant = pony.get("skeleton")
	if sk is Skeleton3D:
		saved_skeleton = sk as Skeleton3D
		for i in (saved_skeleton as Skeleton3D).get_bone_count():
			saved_bones.append((saved_skeleton as Skeleton3D).get_bone_pose(i))
	var hair: Variant = pony.get("hair_skeleton")
	if hair is Skeleton3D:
		saved_hair_skeleton = hair as Skeleton3D
		for i in (saved_hair_skeleton as Skeleton3D).get_bone_count():
			saved_hair.append((saved_hair_skeleton as Skeleton3D).get_bone_pose(i))


## Put every pony bone back before the game's animation re-poses her. The act's pose modifier is
## already freed when this runs, so nothing rewrites the act pose on top.
func restore_bones() -> void:
	if is_instance_valid(saved_skeleton) \
			and saved_bones.size() == saved_skeleton.get_bone_count():
		for i in saved_bones.size():
			saved_skeleton.set_bone_pose(i, saved_bones[i])
	if is_instance_valid(saved_hair_skeleton) \
			and saved_hair.size() == saved_hair_skeleton.get_bone_count():
		for i in saved_hair.size():
			saved_hair_skeleton.set_bone_pose(i, saved_hair[i])
	saved_bones.clear()
	saved_hair.clear()
	saved_skeleton = null
	saved_hair_skeleton = null


## The pose-owned state released before the runtime's cross-system teardown steps: the rig cache,
## the tail lay and the bed frame.
func release_start() -> void:
	rig_checked = false
	rig_skeleton = 0
	rig_missing_bones = []
	if is_instance_valid(tail_lay):
		tail_lay.call("restore_tail")
		tail_lay.queue_free()
	tail_lay = null
	bed_frame = null
	bed_frame_source_saved = false
	bed_frame_source = Transform3D.IDENTITY


## Drop the live-installed extra modifiers. The runtime calls this where it used to call
## `_remove_extra_modifiers()`.
func remove_modifiers() -> void:
	if is_instance_valid(body_sway):
		body_sway.queue_free()
	body_sway = null
	if is_instance_valid(prone_sway):
		prone_sway.queue_free()
	prone_sway = null
	if is_instance_valid(ear_twitch):
		ear_twitch.queue_free()
	ear_twitch = null


## Free the pose modifier and the standing tail. The runtime calls this last in `_free_pose()`.
func release_pose() -> void:
	if is_instance_valid(pose_node):
		pose_node.queue_free()
	pose_node = null
	if is_instance_valid(tail):
		tail.call("restore_tail")
		tail.queue_free()
	tail = null


## Install or remove the live-editable extra modifiers after a settings edit.
func refresh_modifiers(pose: String, feature_flags: Dictionary) -> void:
	pose_id = pose
	features = feature_flags
	if not is_instance_valid(pony):
		return
	var skeleton_value: Variant = pony.get("skeleton")
	if not skeleton_value is Skeleton3D:
		return
	var skeleton := skeleton_value as Skeleton3D
	if pose_id == CATALOG.STANDING:
		if _feature("standing_body_sway") and not is_instance_valid(body_sway):
			_install_body_sway(skeleton)
		elif not _feature("standing_body_sway") and is_instance_valid(body_sway):
			body_sway.queue_free()
			body_sway = null
		if _feature("thrust_ear_twitch") and not is_instance_valid(ear_twitch):
			_install_ear_twitch()
		elif not _feature("thrust_ear_twitch") and is_instance_valid(ear_twitch):
			ear_twitch.queue_free()
			ear_twitch = null
	elif pose_id == CATALOG.MISSIONARY:
		if _feature("missionary_body_motion") and not is_instance_valid(prone_sway):
			_install_prone_sway(skeleton)
		elif not _feature("missionary_body_motion") and is_instance_valid(prone_sway):
			prone_sway.queue_free()
			prone_sway = null


func _install_tail_lay() -> void:
	if not is_instance_valid(pony):
		return
	var hair: Variant = pony.get("hair_skeleton")
	if not hair is Skeleton3D:
		return
	tail_lay = TAIL_LAY.new()
	tail_lay.name = "UnfplapTailLay"
	tail_lay.mare = pony
	tail_lay.runtime = host
	(hair as Skeleton3D).add_child(tail_lay)


func _install_body_sway(skeleton: Skeleton3D) -> void:
	if not _feature("standing_body_sway"):
		return
	body_sway = BODY_SWAY.new()
	body_sway.name = "UnfplapBodySway"
	body_sway.set("mare", pony)
	body_sway.set("runtime", host)
	skeleton.add_child(body_sway)


func _install_prone_sway(skeleton: Skeleton3D) -> void:
	prone_sway = PRONE_SWAY.new()
	prone_sway.name = "UnfplapProneSway"
	prone_sway.set("mare", pony)
	prone_sway.set("runtime", host)
	skeleton.add_child(prone_sway)


func _install_ear_twitch() -> void:
	if not _feature("thrust_ear_twitch"):
		return
	var boop: Variant = pony.get("boop_node")
	var head: Variant = head_skeleton(boop)
	if not head is Skeleton3D:
		return
	ear_twitch = EAR_TWITCH.new()
	ear_twitch.name = "UnfplapEarTwitch"
	ear_twitch.set("mare", pony)
	ear_twitch.set("runtime", host)
	(head as Skeleton3D).add_child(ear_twitch)


## The head skeleton the ear twitch rides, or null.
func head_skeleton(boop: Variant) -> Variant:
	if boop == null:
		return null
	return boop.get("head_skeleton")


## The render-time pose write. The runtime calls this after the game's own writers so the
## authored missionary pose survives to the renderer.
func apply_render(skeleton: Skeleton3D) -> void:
	if is_instance_valid(pose_node):
		pose_node.call("apply_render", skeleton)


func trigger_ear_twitch(impact: float) -> void:
	if is_instance_valid(ear_twitch):
		ear_twitch.call("try_trigger", impact)


func set_tail_target(value: float) -> void:
	if is_instance_valid(tail):
		tail.target_amount = value


func flick_tail(count: int) -> void:
	if is_instance_valid(tail):
		tail.call("flick", count)


func pose() -> Variant:
	return pose_node


func basis_amount() -> float:
	return float(pose_node.get("amount")) if is_instance_valid(pose_node) else 0.0


## Which missionary base is in charge and why. One dictionary so the log, the settled line and the
## debug action cannot drift apart.
func base_info() -> Dictionary:
	var asset: Variant = authored()
	var bones: Variant = asset.get("pony_bones")
	var info := {
		"base": "none",
		"reason": "",
		"version": int(asset.get("version")),
		"bones": (bones as Dictionary).size() if bones is Dictionary else 0,
		"available": bool(asset.get("available")),
		"error": str(asset.get("error")),
		"frame": bed_frame,
		"shots": bool(asset.get("has_shots")),
		"asset": asset,
	}
	if pose_id != CATALOG.MISSIONARY:
		info["reason"] = "pose=%s" % pose_id
	elif not bool(info["available"]):
		info["reason"] = authored_reason()
	elif not bed_frame is Transform3D:
		info["reason"] = "no bed frame"
	else:
		info["base"] = "authored"
	return info


## The authored body bones the live rig lacks. The pose writes only the bones it holds, so a missing
## one leaves the game's pose on that link and the chain above it reads broken; the act refuses to
## start. Cached per skeleton instance, because the gate polls every frame.
func rig_missing() -> Array:
	var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not sk is Skeleton3D:
		return []
	var skeleton := sk as Skeleton3D
	var instance := skeleton.get_instance_id()
	if rig_checked and instance == rig_skeleton:
		return rig_missing_bones
	rig_checked = true
	rig_skeleton = instance
	var missing: Variant = authored().call("missing_bones", skeleton)
	rig_missing_bones = missing if missing is Array else []
	return rig_missing_bones


## The gate row's reason, naming the first few bones and counting the rest.
func rig_reason(missing: Array) -> String:
	if missing.is_empty():
		return ""
	var names: PackedStringArray = []
	for i in mini(3, missing.size()):
		names.append(str(missing[i]))
	var text := "pose_rig: missing %s" % ", ".join(names)
	if missing.size() > 3:
		text += " (+%d more)" % (missing.size() - 3)
	return text


## Render-time placement trace, two lines per act: printed from idle, after every physics and process
## writer, so it reads the pose the renderer is about to use. `root` is the armature bone the authored
## placement is written to; `wanted` is that pose carried into the live bed frame.
func idle_sample(state: int) -> void:
	if pose_trace_frames >= 2 or pose_id != CATALOG.MISSIONARY or state == 0:
		return
	if not is_instance_valid(pose_node) or basis_amount() < 0.9:
		return
	var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not sk is Skeleton3D:
		return
	var skeleton := sk as Skeleton3D
	var root := int(pose_node.get("diag_root"))
	var hips := skeleton.find_bone("pony_hips")
	var g := skeleton.global_transform
	var render_root := g * skeleton.get_bone_global_pose(root) if root >= 0 else Transform3D.IDENTITY
	var render_hips := g * skeleton.get_bone_global_pose(hips) if hips >= 0 else Transform3D.IDENTITY
	var wanted_root: Transform3D = pose_node.get("diag_root_wanted")
	var wanted_hips: Transform3D = pose_node.get("diag_hips_wanted")
	var animation: Variant = pony.get("animation")
	var clip := ""
	var playing := false
	if animation is AnimationPlayer:
		clip = (animation as AnimationPlayer).current_animation
		playing = (animation as AnimationPlayer).is_playing()
	_write_log("pose trace f=%d root=%d:%s asset_root=%d trace=%d mode=%d clip=%s playing=%s G=%s" % [
		pose_trace_frames, root, str(pose_node.get("diag_root_name")), int(pose_node.get("diag_asset_root")),
		int(pose_node.get("diag_trace")), skeleton.modifier_callback_mode_process, clip, str(playing),
		str(g)])
	_write_log("pose trace f=%d root start=%s after=%s render=%s wanted=%s d=%.3f/%.3f | hips start=%s render=%s wanted=%s d=%.3f" % [
		pose_trace_frames, str(pose_node.get("diag_root_start")), str(pose_node.get("diag_root_after")),
		str(render_root), str(wanted_root),
		render_root.origin.distance_to(wanted_root.origin),
		_transform_angle(render_root, wanted_root),
		str(pose_node.get("diag_hips_start")), str(render_hips), str(wanted_hips),
		render_hips.origin.distance_to(wanted_hips.origin)])
	pose_trace_frames += 1


## Degrees between two transforms' bases, for the trace.
func _transform_angle(a: Transform3D, b: Transform3D) -> float:
	return rad_to_deg(a.basis.orthonormalized().get_rotation_quaternion().angle_to(
		b.basis.orthonormalized().get_rotation_quaternion()))


## Rig, modifier and posture diagnostics: which skeleton the modifier drives, which skeleton every
## mesh is actually bound to, whether the pose survives between frames, and who else is near the bed.
func diagnostics(skeleton: Skeleton3D, info: Dictionary) -> Array:
	var rows: Array = []
	var modifier: Variant = pose_node
	var parent: Node = modifier.get_parent() if is_instance_valid(modifier) else null
	rows.append("modifier=%s parent=%s match=%s frames=%d weight=%.2f base=%s readback=%.2f°" % [
		"yes" if is_instance_valid(modifier) else "no",
		"%s@%s" % [str(parent.name), str(parent.get_instance_id())] if parent != null else "none",
		"yes" if parent == skeleton else "NO", int(_num(modifier.get("diag_frames"))) if is_instance_valid(modifier) else 0,
		_num(modifier.get("diag_last_weight")) if is_instance_valid(modifier) else 0.0,
		str(modifier.get("diag_last_base")) if is_instance_valid(modifier) else "",
		_num(modifier.get("diag_readback_deg")) if is_instance_valid(modifier) else 0.0])
	var modifiers: Array[String] = []
	for child: Node in skeleton.get_children():
		if child is SkeletonModifier3D:
			var active: Variant = child.get("active")
			var influence: Variant = child.get("influence")
			modifiers.append("%s%s%s" % [
				str(child.name),
				(" active=%s" % str(active)) if active != null else "",
				(" inf=%.2f" % float(influence)) if influence is float else ""])
	rows.append("skeleton modifiers=%d [%s]" % [modifiers.size(), ", ".join(modifiers)])
	rows.append("hips write check: after_write=%.2f° readback=%.2f° (%s)" % [
		_num(modifier.get("diag_after_write_deg")) if is_instance_valid(modifier) else 0.0,
		_num(modifier.get("diag_readback_deg")) if is_instance_valid(modifier) else 0.0,
		"write lands, survives" if is_instance_valid(modifier)
			and _num(modifier.get("diag_after_write_deg")) < 1.0
			and _num(modifier.get("diag_readback_deg")) < 1.0
		else "write lands, lost by next frame" if is_instance_valid(modifier)
			and _num(modifier.get("diag_after_write_deg")) < 1.0
		else "write does not land"])
	rows.append("pony_skeleton=%s@%s actor=%s paused=%s visible=%s" % [
		str(skeleton.name), str(skeleton.get_instance_id()), str(pony.global_position),
		str(pony.get("motion_paused")), str(pony.visible)])
	var posture: Variant = pony.get("posture")
	if posture != null:
		rows.append("posture kind=%s requested=%s phase=%s progress=%.2f ready=%s clip=%s refusal=%s" % [
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
		rows.append("mesh_skeleton=%s meshes=%d sample=%s visible=%s hips=%s" % [
			("%s@%s" % [str((target as Node).name), str(instance)]) if target is Node else "none",
			int(entry["count"]), str(entry["sample"]), str(entry["visible"]), str(hips)])
	# Live hips pose vs the authored quaternion: proves whether the modifier's write is what lives.
	var asset: Variant = info.get("asset")
	var hips_bone := skeleton.find_bone("pony_hips")
	if hips_bone >= 0 and asset != null:
		var entry: Variant = (asset.get("pony_bones") as Dictionary).get("pony_hips")
		if entry is Dictionary:
			var wanted: Quaternion = (entry as Dictionary)["rotation"]
			var live := skeleton.get_bone_pose_rotation(hips_bone)
			rows.append("hips_pose live=%s authored=%s delta=%.1f°" % [
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
				str(other.call("posture_status").get("requested", "?")), str(hips_at)])
	rows.append("nearby=%d %s" % [nearest.size(), "; ".join(nearest)])
	return rows


## Multi-row pose diagnostic for the debug action: base source, asset state, bed frame and where
## the live pose actually put her (world and bed space).
func state_rows(state: int) -> Array:
	var info := base_info()
	var frame: Variant = info["frame"]
	var rows: Array = []
	rows.append("pony=%s pose=%s state=%d weight=%.2f" % [
		str(pony.name) if is_instance_valid(pony) else "?", pose_id, state, basis_amount()])
	rows.append("base=%s reason=%s asset=v%d %s bones=%d missing=%s shots=%s error=%s" % [
		str(info["base"]), str(info["reason"]),
		int(info["version"]), "ok" if bool(info["available"]) else "error", int(info["bones"]),
		str(rig_missing()), "yes" if bool(info["shots"]) else "no", str(info["error"])])
	rows.append("bed_frame=%s scale=%.2f" % [
		str(frame) if frame is Transform3D else "null", body_scale()])
	var sk: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not sk is Skeleton3D:
		return rows
	var skeleton := sk as Skeleton3D
	rows.append_array(diagnostics(skeleton, info))
	var space := Transform3D.IDENTITY
	if frame is Transform3D:
		space = (frame as Transform3D).affine_inverse()
	for pair: Array in [["hips", "pony_hips"], ["neck", "pony_neck1"], ["neck_mid", "pony_neck2"],
			["head", "pony_head"], ["hoof_l", "pony_hoof_L"], ["hoof_r", "pony_hoof_R"]]:
		var bone := skeleton.find_bone(str(pair[1]))
		if bone < 0:
			continue
		var world := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		var bed := space * world
		rows.append("%s world=(%.3f,%.3f,%.3f) bed=(%.3f,%.3f,%.3f)" % [
			str(pair[0]), world.x, world.y, world.z, bed.x, bed.y, bed.z])
	return rows


## The base line written once when the act builds its pose.
func log_base() -> void:
	if pose_id != CATALOG.MISSIONARY:
		return
	var info := base_info()
	var frame: Variant = info["frame"]
	var missing := rig_missing()
	_write_log("missionary base=%s reason=%s asset=v%d %s bones=%d missing=%d shots=%s frame=%s scale=%.2f" % [
		str(info["base"]), str(info["reason"]), int(info["version"]),
		"ok" if bool(info["available"]) else "error", int(info["bones"]),
		missing.size(), "yes" if bool(info["shots"]) else "no",
		str(frame) if frame is Transform3D else "null", body_scale()])
	if not missing.is_empty():
		_write_log("missionary rig %s" % rig_reason(missing))


## One line with where the pose actually put her, in world and bed space, once the weight settles.
func log_settled(state: int, anon_diag: Callable) -> void:
	if pose_logged or pose_id != CATALOG.MISSIONARY or state == 0:
		return
	if basis_amount() < 0.9:
		return
	pose_logged = true
	if not is_instance_valid(pony):
		return
	var sk: Variant = pony.get("skeleton")
	if not sk is Skeleton3D:
		return
	var skeleton := sk as Skeleton3D
	var space := Transform3D.IDENTITY
	if bed_frame is Transform3D:
		space = (bed_frame as Transform3D).affine_inverse()
	var parts: Array[String] = []
	for pair: Array in [["hips", "pony_hips"], ["neck", "pony_neck1"], ["head", "pony_head"],
			["hoof_l", "pony_hoof_L"], ["hoof_r", "pony_hoof_R"]]:
		var bone := skeleton.find_bone(str(pair[1]))
		if bone < 0:
			continue
		var world := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		var bed := space * world
		parts.append("%s=w%s/b(%.3f,%.3f,%.3f)" % [
			str(pair[0]), str(world), bed.x, bed.y, bed.z])
	_write_log("missionary settled base=%s weight=%.2f %s" % [
		str(base_info()["base"]), basis_amount(), " ".join(parts)])
	for row: Variant in diagnostics(skeleton, base_info()):
		_write_log("missionary diag %s" % str(row))
	if anon_diag.is_valid():
		var text := str(anon_diag.call())
		if not text.is_empty():
			_write_log("anon diag %s" % text)


## Attach the debug chin modifier and set its pitch. The runtime's debug action owns the angle and
## the log; this session owns the modifier that must stay after every pose modifier.
func set_chin(degrees: float) -> void:
	var skeleton: Variant = pony.get("skeleton") if is_instance_valid(pony) else null
	if not skeleton is Skeleton3D:
		return
	if not is_instance_valid(chin_modifier) or chin_modifier.get_parent() != skeleton:
		if is_instance_valid(chin_modifier):
			chin_modifier.queue_free()
		chin_modifier = CHIN_DEBUG.new()
		chin_modifier.name = "UnfplapChinDebug"
		chin_modifier.set("mare", pony)
		(skeleton as Skeleton3D).add_child(chin_modifier)
	chin_modifier.set("chin_deg", degrees)
	keep_chin_last()


## Keep the debug chin modifier after every pose modifier, so an act cannot overwrite the debug
## head pitch.
func keep_chin_last() -> void:
	if not is_instance_valid(chin_modifier):
		return
	var parent := chin_modifier.get_parent()
	if parent is Skeleton3D:
		(parent as Skeleton3D).move_child(chin_modifier, parent.get_child_count() - 1)


## Absolute body scale from the rig's own pivot, 1.0 when the pony is gone.
func body_scale() -> float:
	var value: Variant = pony.get("body_scale") if is_instance_valid(pony) else null
	return float(value) if value != null else 1.0


func _feature(name: String) -> bool:
	return bool(features.get(name, false))


## Numeric read of a Variant property without tripping over a missing one.
func _num(value: Variant, fallback := 0.0) -> float:
	return float(value) if value is float or value is int else fallback


func _write_log(text: String) -> void:
	if log.is_valid():
		log.call(text)
