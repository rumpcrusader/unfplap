extends Node
## The act's Anon body: the game's own desktop `AnonBody`, placed in bed space and posed from the
## asset's `anon` block. The act parks his drivers and writes his bones at render time so nothing
## else on his rig wins; the asset carries every bone, and only this body is placed, not his node.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const MOTION := preload("res://mods/unfplap/shared/act_motion.gd")
const HIP := preload("res://mods/unfplap/poses/anon_hip_thrust.gd")
const RIG := preload("res://mods/unfplap/poses/pose_rig.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const REACH_PLAN := preload("res://mods/unfplap/shared/hands_reach_plan.gd")
const PALM_SCALE := preload("res://mods/unfplap/shared/hands_scale.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")

## The lean joint: everything above it follows as one, while the hips, thighs and legs keep the
## authored pose and the stroke. The camera is his head, so the lean also moves the act view.
const LEAN_HINGE := "Spine"
## Share of the stroke offset lifted straight up, so the pelvis rides up her body instead of only
## driving along the mattress.
const HIP_UP_SHARE := 0.25
## The eye-to-mouth offset human Anon uses (`player/player_mouth.gd`), camera-local metres at
## scale 1. The kiss and her gaze aim at this, never at the standing player rig.
const MOUTH_OFFSET := Vector3(0.0, -0.07, -0.02)
## A caress hold eases the palm off the mattress and back, so it never snaps through her body or
## leaves the hand floating when the act ends.
const HOLD_BLEND_S := 0.35
const HOLD_RELEASE_S := 0.35

## The typed act view. Every live value and callback comes through it; the runtime node is never
## read directly.
var facts: ACT_FACTS
var avatar: Node3D
var skeleton: Skeleton3D
## True once a body was found and is being driven by this controller.
var active := false
## The `anon` retarget state: the weight and profile are cached without moving him.
var anon_profile := ""
var anon_weight := 1.0
## The authored asset pair the service bound. Outside an edge both point at the live asset; during
## a blend they are the source and the target.
var from_asset: AUTHORED = null
var to_asset: AUTHORED = null
var asset_weight := 1.0

var _body_ik: SkeletonModifier3D
var _body_ik_was_active := true
var _leg_hide: SkeletonModifier3D
var _leg_hide_influence := 0.0
var _driver: Node
var _avatar_processing := true
var _avatar_transform := Transform3D.IDENTITY
## Every bone's local transform before the act, put back whole: the authored pose keeps its stretched
## positions and the game re-poses rotations after the act but not every bone position.
var _saved_bones: Array[Transform3D] = []
var _scale := Vector3.ONE
## The eye relative to the head bone, built from the body's own exports rather than read off the
## live camera, which is still the reclined bed view when the act installs.
var _eye_rel := Transform3D.IDENTITY
var _eye_saved := false
## The eye this frame, cached right after the authored write and the lean: `HeadHide` collapses the
## head bone later, so the camera must read the pose we wrote, not the collapsed bone.
var _eye_world := Transform3D.IDENTITY
var _eye_cached := false
var _lean_logged := false
var _indices: Dictionary = {}
var _index_skeleton := 0
## The union of the two authored bone blocks, resolved once per skeleton for the pair blend.
var _asset_indices: Dictionary = {}
var _asset_index_skeleton := 0
var _reach_log_state: Dictionary = {}
## Caress hand holds, keyed "left"/"right". `hands/api.gd` supplies a world frame; the
## start and release blends keep the arm from teleporting on and off the mattress.
var _holds: Dictionary = {}
var _hold_from: Dictionary = {}
var _hold_started: Dictionary = {}
var _releases: Dictionary = {}
var _release_from: Dictionary = {}
var _release_started: Dictionary = {}
## The palm-to-hand-bone offset per side, from the game's `AnonBody` exports. The caress target
## and the plant frames are palm frames; the arm solve writes the wrist bone.
var _hand_offsets: Dictionary = {}
## Regular-arm pole state while a caress holds a hand, keyed "left"/"right".
var _arm_poles: Dictionary = {}
var _arm_axes: Dictionary = {}
var _palm_scale: PALM_SCALE


func install(context: ACT_FACTS) -> bool:
	facts = context
	if not is_instance_valid(WORLD.game) or not is_instance_valid(WORLD.player):
		return false
	avatar = WORLD.player.find_child("AnonBody", true, false) as Node3D
	if not is_instance_valid(avatar):
		return false
	skeleton = avatar.find_child("Skeleton3D", true, false) as Skeleton3D
	if not is_instance_valid(skeleton):
		return false
	_avatar_processing = avatar.is_processing()
	_avatar_transform = avatar.transform
	_hand_offsets.clear()
	for side: String in ["left", "right"]:
		var offset_key := "left_hand_offset" if side == "left" else "right_hand_offset"
		var offset_value: Variant = avatar.get(offset_key)
		if offset_value is Transform3D and (offset_value as Transform3D).is_finite():
			_hand_offsets[side] = offset_value
		else:
			# The game's measured default: the controller/palm frame is 7 cm ahead of the wrist.
			var side_sign := -1.0 if side == "left" else 1.0
			_hand_offsets[side] = Transform3D(
				Basis(Vector3(0, 0, side_sign), Vector3(side_sign, 0, 0), Vector3(0, 1, 0)),
				Vector3(0.0, 0.0, 0.07))
	_saved_bones.clear()
	for i in skeleton.get_bone_count():
		_saved_bones.append(skeleton.get_bone_pose(i))
	_scale = avatar.scale
	_install_palm_scale()
	# His own drivers: the desktop pose driver poses the torso and the body IK the limbs. Both are
	# parked for the act; the pose we write is the only pose.
	_driver = WORLD.anon().pose_driver()
	WORLD.anon().set_pose_driver(null)
	# Only the body IK is parked: it is the *pose driver* (it builds his body from the player camera
	# markers, i.e. the standing body). Every hider stays on: they only hide parts.
	var ik: Variant = avatar.get("_body_ik")
	if not is_instance_valid(ik):
		ik = avatar.find_child("BodyIK", true, false)
	if ik is SkeletonModifier3D:
		_body_ik = ik as SkeletonModifier3D
		_body_ik_was_active = _body_ik.active
		_body_ik.active = false
	# His own `_process` drives the IK targets, height feedback, finger curl and `LegHide`; the act
	# writes all of that itself, so the mattress-height camera would read as a crouch, the legs
	# would collapse and the fists would overwrite the authored fingers. The skeleton keeps updating.
	avatar.set_process(false)
	# The legs are part of the authored pose: never let the last seated state collapse them. The
	# modifier stays active, just at zero.
	var leg_hide: Variant = avatar.find_child("LegHide", true, false)
	if leg_hide is SkeletonModifier3D:
		_leg_hide = leg_hide as SkeletonModifier3D
		_leg_hide_influence = _leg_hide.influence
		_leg_hide.influence = 0.0
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
	# Nothing here hides the head mesh: `head_smd` also holds the hands, so hiding it removes the
	# palms. The game collapses only the head bone, dropping the head vertices and leaving the
	# hands; the eye is cached before that happens each frame.
	avatar.visible = true
	active = true
	return true


func remove() -> void:
	active = false
	_eye_cached = false
	_remove_palm_scale()
	if is_instance_valid(_leg_hide):
		_leg_hide.influence = _leg_hide_influence
	if is_instance_valid(_body_ik):
		_body_ik.active = _body_ik_was_active
	_leg_hide = null
	_body_ik = null
	if is_instance_valid(avatar):
		WORLD.anon().set_pose_driver(_driver)
		# The act wrote his world placement every frame; put the rig back exactly where the
		# presentation left it, then hand it back.
		avatar.transform = _avatar_transform
		avatar.set_process(_avatar_processing)
		# Visibility and process mode are the presentation's hold, already released by the frame;
		# restoring the parked snapshot here would freeze his own pose driver for good.
		if is_instance_valid(skeleton) and _saved_bones.size() == skeleton.get_bone_count():
			for i in skeleton.get_bone_count():
				skeleton.set_bone_pose(i, _saved_bones[i])
		LOG.debug("anon restore transform=%s process=%s leg=%.2f", [
			str(_avatar_transform.origin), str(_avatar_processing), _leg_hide_influence])
	_saved_bones.clear()
	avatar = null
	skeleton = null
	_indices.clear()
	_index_skeleton = 0
	_asset_indices.clear()
	_asset_index_skeleton = 0
	_reach_log_state.clear()
	_holds.clear()
	_hold_from.clear()
	_hold_started.clear()
	_releases.clear()
	_release_from.clear()
	_release_started.clear()
	_hand_offsets.clear()
	_arm_poles.clear()
	_arm_axes.clear()
	anon_profile = ""
	anon_weight = 1.0
	from_asset = null
	to_asset = null
	asset_weight = 1.0


## The `anon` channel's retarget hook. A held channel keeps the body; a switch names the authored
## profile and a blend carries the live edge weight. A3.5 caches them; A5's authored pose reads them.
func pose_changed(profile := "", weight := 1.0) -> void:
	var next_profile := str(profile)
	var next_weight := clampf(weight, 0.0, 1.0)
	if next_profile == anon_profile and is_equal_approx(next_weight, anon_weight):
		return
	anon_profile = next_profile
	anon_weight = next_weight


## The base channel drives the same weight the edge view carries. It never changes the profile.
func set_weight(weight: float) -> void:
	var next_weight := clampf(weight, 0.0, 1.0)
	if is_equal_approx(next_weight, anon_weight):
		return
	anon_weight = next_weight


## The authored asset pair and its blend weight, bound by the pose service every fan-out, so an
## unchanged pair is a no-op and never touches the avatar, the eye cache or the hand holds.
func set_pose_assets(from_value: AUTHORED, to_value: AUTHORED, weight: float) -> void:
	var next_weight := clampf(weight, 0.0, 1.0)
	if is_same(from_value, from_asset) and is_same(to_value, to_asset) \
			and is_equal_approx(next_weight, asset_weight):
		return
	from_asset = from_value
	to_asset = to_value
	asset_weight = next_weight


## Place and pose him from the asset pair once per displayed frame: the authored bones first, then
## the lean on top, or the asset would wipe it. A blend evaluates and mixes both sides.
func apply(bed_frame: Transform3D, body_scale: float) -> void:
	if not active or not is_instance_valid(avatar) or not is_instance_valid(skeleton):
		return
	var live: AUTHORED = to_asset if asset_weight >= 1.0 else from_asset
	if live == null:
		live = from_asset if to_asset == null else to_asset
	if live == null:
		# A suite or a pre-D2 caller that never set the pair keeps the process-wide asset.
		live = AUTHORED.shared()
	if not live.available:
		return
	var v7 := live.version >= 7
	var pair := _asset_pair_ready()
	var placed: Transform3D
	if pair:
		placed = blend_placement(_placed_asset(from_asset, bed_frame, body_scale),
			_placed_asset(to_asset, bed_frame, body_scale), asset_weight)
		if not placed.is_finite():
			return
	else:
		var placement: Transform3D
		if v7:
			if live.active_anon_mode() != "act_body":
				return
			placement = live.active_anon_transform()
		else:
			placement = live.anon_frame
		if v7:
			# The anchor/contact rule: the Anon origin scales about her hips anchor and rides the
			# contact lift; his basis is unchanged.
			var world := bed_frame * placement
			placed = Transform3D(world.basis,
				live.place_origin(world.origin, bed_frame, body_scale))
		else:
			placement.origin *= body_scale
			placed = bed_frame * placement
	# Being human, his body keeps its own scale and only his placement follows her size. The debug
	# `Anon size match` blends that body toward hers: 0 human, 1 uniform with her.
	var body := _scale
	var match_factor := clampf(SETTINGS.anon_size_match.get_num(), 0.0, 1.0)
	if match_factor > 0.0:
		body = _scale * lerpf(1.0, body_scale, match_factor)
	avatar.global_transform = Transform3D(placed.basis * Basis.from_scale(body), placed.origin)
	# The presentation parks the body every tick (invisible, processing off); the act needs it shown
	# and its skeleton updating, and its own IK/driver are already neutralised.
	if not avatar.visible:
		avatar.visible = true
	if avatar.process_mode != Node.PROCESS_MODE_INHERIT:
		avatar.process_mode = Node.PROCESS_MODE_INHERIT
	var plants := {}
	if pair:
		var from_bones: Dictionary = from_asset.active_anon_bones()
		var to_bones: Dictionary = to_asset.active_anon_bones()
		_cache_asset_indices(from_bones, to_bones)
		blend_anon_bones(skeleton, from_bones, to_bones, asset_weight, _asset_indices)
	else:
		var bones: Dictionary = live.active_anon_bones() if v7 else live.anon_bones
		if not bones.is_empty():
			_cache_indices(bones)
			if v7:
				live.apply_bones(skeleton, bones, 1.0)
			else:
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
	# The authored hand frames, before the lean moves them: the plant keeps their height and lets
	# only X/Z slide.
	for side: String in ["Left", "Right"]:
		var hand := skeleton.find_bone(side + "Hand")
		if hand >= 0 and skeleton.find_bone(side + "UpperArm") >= 0 \
				and skeleton.find_bone(side + "LowerArm") >= 0:
			plants[side] = skeleton.get_bone_global_pose(hand)
	# The attached alignment asks for the pelvis offset that puts the shaft in her. It reaches the
	# hips first and fades out up the spine, with the neck, head and planted legs pinned, so his
	# shoulders and the camera move much less than his pelvis.
	var offset: Vector3 = _hip_offset()
	if offset.length_squared() > 0.0000001:
		offset += Vector3.UP * (offset.length() * HIP_UP_SHARE)
	_apply_hip_motion(offset)
	_note_hip_offset(offset)
	_apply_lean(placed)
	_place_hands(plants, placed)
	_cache_eye()


## True when both bound sides are v7 act-body assets: the pair blend owns both placements and both
## bone blocks. A v6 read path and a mixed pair keep the live side's single path.
func _asset_pair_ready() -> bool:
	if from_asset == null or to_asset == null:
		return false
	if from_asset.version < 7 or to_asset.version < 7:
		return false
	if from_asset.active_anon_mode() != "act_body":
		return false
	return to_asset.active_anon_mode() == "act_body"


## One side's placed act body: the bed frame times the authored Anon transform, with the origin
## carried through the same anchor/contact rule as the single path.
func _placed_asset(asset: AUTHORED, bed_frame: Transform3D, body_scale: float) -> Transform3D:
	var world: Transform3D = bed_frame * asset.active_anon_transform()
	return Transform3D(world.basis, asset.place_origin(world.origin, bed_frame, body_scale))


## Blend two world placements: the basis slerps and the origin lerps. A non-finite side returns
## the other, so a broken asset cannot put him at infinity.
static func blend_placement(from: Transform3D, to: Transform3D, weight: float) -> Transform3D:
	if not from.is_finite():
		return to
	if not to.is_finite():
		return from
	var blend := clampf(weight, 0.0, 1.0)
	return Transform3D(
		from.basis.orthonormalized().slerp(to.basis.orthonormalized(), blend),
		from.origin.lerp(to.origin, blend))


## Blend the two v7 local-rest bone blocks at the edge weight; a bone on only one side uses that
## side, and a missing bone or a non-finite pair is skipped rather than written.
static func blend_anon_bones(sk: Skeleton3D, from_bones: Dictionary, to_bones: Dictionary,
		weight: float, indices: Dictionary = {}) -> void:
	if sk == null:
		return
	var blend := clampf(weight, 0.0, 1.0)
	for key: Variant in from_bones:
		_blend_anon_bone(sk, str(key), from_bones, to_bones, blend, indices)
	for key: Variant in to_bones:
		if from_bones.has(key) or from_bones.has(str(key)):
			continue
		_blend_anon_bone(sk, str(key), from_bones, to_bones, blend, indices)


static func _blend_anon_bone(sk: Skeleton3D, name: String, from_bones: Dictionary,
		to_bones: Dictionary, weight: float, indices: Dictionary) -> void:
	var bone := int(indices[name]) if indices.has(name) else sk.find_bone(name)
	if bone < 0:
		return
	var from_entry: Variant = from_bones.get(name)
	var to_entry: Variant = to_bones.get(name)
	if not (from_entry is Dictionary) and not (to_entry is Dictionary):
		return
	var from_local: Transform3D
	var to_local: Transform3D
	var has_from := from_entry is Dictionary
	var has_to := to_entry is Dictionary
	if has_from:
		from_local = _anon_local(sk, bone, from_entry as Dictionary)
		if not from_local.is_finite():
			return
	if has_to:
		to_local = _anon_local(sk, bone, to_entry as Dictionary)
		if not to_local.is_finite():
			return
	var local: Transform3D
	if has_from and has_to:
		local = blend_placement(from_local, to_local, weight)
	elif has_from:
		local = from_local
	else:
		local = to_local
	if not local.is_finite():
		return
	sk.set_bone_pose_rotation(bone, local.basis.orthonormalized().get_rotation_quaternion())
	sk.set_bone_pose_position(bone, local.origin)
	sk.set_bone_pose_scale(bone, sk.get_bone_rest(bone).basis.get_scale())


## One v7 entry's local-rest pose: `rest.basis * delta` and `rest.basis * position + rest.origin`.
static func _anon_local(sk: Skeleton3D, bone: int, entry: Dictionary) -> Transform3D:
	var rest := sk.get_bone_rest(bone)
	var rotation_value: Variant = entry.get("rotation", Quaternion.IDENTITY)
	var position_value: Variant = entry.get("position", Vector3.ZERO)
	var rotation: Quaternion = rotation_value if rotation_value is Quaternion else Quaternion.IDENTITY
	var position: Vector3 = position_value if position_value is Vector3 else Vector3.ZERO
	return Transform3D(rest.basis * Basis(rotation), rest.basis * position + rest.origin)


## Carry the pelvis on the stroke: the hips take the whole offset, the waist a graded share, and the
## neck, head and planted legs are restored. Moving his whole body swung the eye on every thrust.
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


## Tilt the upper body about the Spine joint by the debug lean plus the act's W/S/Q/E lean, leaving
## his hips and legs on the authored pose so the lower body still thrusts under the tilt.
func _apply_lean(placed: Transform3D) -> void:
	if facts == null or not is_instance_valid(skeleton):
		return
	var lean_forward: float = facts.shot_lean_forward
	var lean_side: float = facts.lean_view_side
	var lean_scale: float = facts.lean_size_scale
	# Positive lean pitches his chest down onto her; negative lifts it.
	var pitch := deg_to_rad(MOTION.LEAN_PITCH_DEG * 3.0) * lean_forward * lean_scale
	var yaw := -deg_to_rad(MOTION.LEAN_SIDE_YAW_DEG * 4.0) * lean_side * lean_scale
	if absf(pitch) < 0.00001 and absf(yaw) < 0.00001:
		return
	if not _lean_logged:
		_lean_logged = true
		LOG.debug("anon lean fwd=%.2f side=%.2f scale=%.2f pitch=%.1f°", [
			lean_forward, lean_side, lean_scale, rad_to_deg(pitch)])
	# His body is lying, so the nod and the turn are the bed's own axes: nod along the mattress,
	# turn about the mattress normal. Both are converted into skeleton space once.
	var to_sk := skeleton.global_basis.inverse()
	var nod := (to_sk * placed.basis.x).normalized()
	var turn := (to_sk * placed.basis.y).normalized()
	var bone := skeleton.find_bone(LEAN_HINGE)
	if bone < 0:
		return
	# Rotate the *global* pose about the skeleton-space axis, so everything above the joint hinges
	# together. Pre-multiplying the bone's local pose applies that axis in its parent's frame, and
	# here his hips lie rotated ~90°, so a nod came out as a sideways yaw of the view.
	var pose: Transform3D = skeleton.get_bone_global_pose(bone)
	pose.basis = Basis(nod, pitch) * Basis(turn, yaw) * pose.basis
	RIG.set_global(skeleton, bone, pose)


## The caress controller drives one hand onto her chest/belly through this world-space hold. The
## act's palm stays on the coat while his shoulders move with the thrust and lean.
func set_hold_target(side: String, world: Transform3D, _kind := "rub") -> void:
	if side not in ["left", "right"] or not world.is_finite():
		return
	if not _holds.has(side):
		_hold_from[side] = hand_frame(side)
		_hold_started[side] = Time.get_ticks_msec()
		_arm_poles.erase(side)
		_arm_axes.erase(side)
		_releases.erase(side)
		_release_from.erase(side)
		_release_started.erase(side)
	_holds[side] = world


## Release the palm back to the authored mattress frame instead of leaving it in the air.
func clear_hold_target(side: String) -> void:
	if not _holds.has(side):
		return
	_releases[side] = true
	_release_from[side] = hand_frame(side)
	_release_started[side] = Time.get_ticks_msec()
	_arm_poles.erase(side)
	_arm_axes.erase(side)
	_holds.erase(side)
	_hold_from.erase(side)
	_hold_started.erase(side)


## The hand's current palm frame, which the caress target and the release share: undo both the hand
## offset and the hand's rest basis, because the arm solve sets the bone to `target * rest`.
func hand_frame(side := "right") -> Transform3D:
	if not active or not is_instance_valid(skeleton):
		return Transform3D.IDENTITY
	var hand := skeleton.find_bone("LeftHand" if side == "left" else "RightHand")
	if hand < 0:
		return Transform3D.IDENTITY
	var bone := skeleton.global_transform * skeleton.get_bone_global_pose(hand)
	return bone_to_palm(bone, _hand_offset(side), _hand_rest_basis(side))


## The game's controller/palm frame and the wrist bone differ by the hand offset and the hand's
## rest basis (`bone = (palm * offset) * rest`). The caress blend and the arm solve share this.
static func palm_to_bone(palm: Transform3D, offset: Transform3D,
		rest_basis := Basis.IDENTITY) -> Transform3D:
	return (palm * offset) * Transform3D(rest_basis, Vector3.ZERO)


static func bone_to_palm(bone: Transform3D, offset: Transform3D,
		rest_basis := Basis.IDENTITY) -> Transform3D:
	return (bone * Transform3D(rest_basis, Vector3.ZERO).affine_inverse()) * offset.affine_inverse()


func _hand_rest_basis(side: String) -> Basis:
	if not is_instance_valid(skeleton):
		return Basis.IDENTITY
	var hand := skeleton.find_bone("LeftHand" if side == "left" else "RightHand")
	if hand < 0:
		return Basis.IDENTITY
	return skeleton.get_bone_global_rest(hand).basis.orthonormalized()


func _hand_offset(side: String) -> Transform3D:
	var value: Variant = _hand_offsets.get(side)
	return value if value is Transform3D else Transform3D.IDENTITY


## World reach of one hand, for the caress controller's reach-aware path. The wrist chain is
## upper + lower; the palm sits one hand-offset farther, so the palm can reach that much more.
func caress_reach(hand_side: String) -> Dictionary:
	if not is_instance_valid(skeleton):
		return {}
	var name := "Left" if hand_side == "left" else "Right"
	var upper := skeleton.find_bone(name + "UpperArm")
	var lower := skeleton.find_bone(name + "LowerArm")
	var hand := skeleton.find_bone(name + "Hand")
	if upper < 0 or lower < 0 or hand < 0:
		return {}
	var shoulder: Vector3 = skeleton.global_transform \
		* skeleton.get_bone_global_pose(upper).origin
	var reach_scale := skeleton.global_transform.basis.get_scale().x
	return {
		"origin": shoulder,
		"upper": skeleton.get_bone_pose_position(lower).length() * reach_scale,
		"lower": skeleton.get_bone_pose_position(hand).length() * reach_scale,
		"hand": _hand_offset(hand_side).origin.length() * reach_scale,
	}


## Keep the palms planted while the body thrusts and leans, unless a caress holds one on her; every
## path ends in the same two-bone solve, which preserves the elbow plane and the authored hand scale.
func refresh_palm() -> void:
	_install_palm_scale()


func _install_palm_scale() -> void:
	_remove_palm_scale()
	if not is_instance_valid(skeleton) or facts == null:
		return
	var factor: float = facts.palm_scale_factor
	if is_equal_approx(factor, 1.0):
		return
	_palm_scale = PALM_SCALE.new()
	_palm_scale.name = "UnfplapMissionaryPalmScale"
	_palm_scale.skeleton = skeleton
	_palm_scale.factor = factor
	_palm_scale.process_priority = 10
	skeleton.add_child(_palm_scale)


func _remove_palm_scale() -> void:
	if is_instance_valid(_palm_scale):
		_palm_scale.active = false
		_palm_scale.restore()
		_palm_scale.queue_free()
	_palm_scale = null


func _place_hands(plants: Dictionary, placed: Transform3D) -> void:
	if plants.is_empty() or not is_instance_valid(skeleton):
		return
	var now := Time.get_ticks_msec()
	var skel_inv := skeleton.global_transform.affine_inverse()
	var body_basis := (skel_inv.basis * placed.basis).orthonormalized()
	for side: Variant in plants.keys():
		var name := str(side)
		var key := name.to_lower()
		var hand := skeleton.find_bone(name + "Hand")
		if hand < 0:
			continue
		var authored: Transform3D = plants[side]
		var rest_basis := _hand_rest_basis(key)
		if _holds.has(key):
			var live: Variant = _holds.get(key)
			if not live is Transform3D or not (live as Transform3D).is_finite():
				continue
			var from: Transform3D = live
			var saved: Variant = _hold_from.get(key)
			if saved is Transform3D and (saved as Transform3D).is_finite():
				from = saved
			var started := int(_hold_started.get(key, now))
			var t := clampf(float(now - started) / (HOLD_BLEND_S * 1000.0), 0.0, 1.0)
			var hold_target := _blend_frame(from, live, t)
			var hold_local := skel_inv * palm_to_bone(hold_target, _hand_offset(key), rest_basis)
			var target_basis := (skel_inv.basis * hold_target.basis).orthonormalized()
			_solve_hand(name, hold_local.origin,
				hold_local.basis.orthonormalized().scaled(authored.basis.get_scale()),
				true, body_basis, key, target_basis)
			continue
		if _releases.has(key):
			var dest := bone_to_palm(skeleton.global_transform * authored,
				_hand_offset(key), rest_basis)
			var from := dest
			var saved: Variant = _release_from.get(key)
			if saved is Transform3D and (saved as Transform3D).is_finite():
				from = saved
			var started := int(_release_started.get(key, now))
			var t := clampf(float(now - started) / (HOLD_RELEASE_S * 1000.0), 0.0, 1.0)
			var release_target := _blend_frame(from, dest, t)
			var release_local := skel_inv * palm_to_bone(release_target,
				_hand_offset(key), rest_basis)
			_solve_hand(name, release_local.origin,
				release_local.basis.orthonormalized().scaled(authored.basis.get_scale()))
			if t >= 1.0:
				_releases.erase(key)
				_release_from.erase(key)
				_release_started.erase(key)
			continue
		# The planted palm: hold the authored world height, let X/Z slide with the stroke.
		var current_world := skeleton.global_transform * skeleton.get_bone_global_pose(hand)
		var authored_world := skeleton.global_transform * authored
		var plant_target := skel_inv * Vector3(current_world.origin.x, authored_world.origin.y,
			current_world.origin.z)
		_solve_hand(name, plant_target, authored.basis)


## Two-bone arm solve to a skeleton-space wrist target; the hand keeps the supplied basis so the
## palm stays flat. A held caress passes `natural` to use the game's regular elbow pole instead.
func _solve_hand(name: String, target: Vector3, hand_basis: Basis, natural := false,
		body_basis := Basis.IDENTITY, pole_key := "",
		pole_target_basis := Basis.IDENTITY) -> void:
	if not is_instance_valid(skeleton):
		return
	var upper := skeleton.find_bone(name + "UpperArm")
	var lower := skeleton.find_bone(name + "LowerArm")
	var hand := skeleton.find_bone(name + "Hand")
	if upper < 0 or lower < 0 or hand < 0:
		return
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var lower_offset := skeleton.get_bone_pose_position(lower)
	var hand_offset := skeleton.get_bone_pose_position(hand)
	var upper_len := lower_offset.length()
	var lower_len := hand_offset.length()
	if upper_len < 0.001 or lower_len < 0.001:
		return
	# Only the caressing hand may shift its shoulder or stretch. The two planted palms keep the
	# authored arm and mattress contact.
	var caress := natural
	var stretch := 1.0
	if caress:
		PERF.begin("caress_arm")
		var shoulder_cap := maxf(float(SETTINGS.caress_reach_shoulder_m.get_num()), 0.0)
		var plan := REACH_PLAN.plan(shoulder, upper_len, lower_len, target, 1.0,
			shoulder_cap, 0.0)
		shoulder = plan["shoulder_origin"]
		target = plan["target"]
		stretch = float(plan.get("stretch", 1.0))
		if bool(SETTINGS.caress_debug.get_bool()):
			var key := pole_key if not pole_key.is_empty() else name
			var reachable := bool(plan.get("reachable", true))
			var state := "ok" if reachable else "clamped"
			if str(_reach_log_state.get(key, "")) != state:
				_reach_log_state[key] = state
				LOG.debug("caress arm side=%s %s shoulder=%.3f body=%.3f distance=%.3f max=%.3f stretch=%.2f", [
					key, state, float(plan.get("shoulder_shift", 0.0)),
					float(plan.get("body_shift", 0.0)), float(plan.get("distance", 0.0)),
					float(plan.get("max_reach", 0.0)), stretch])
	var upper_len_eff := upper_len * stretch
	var lower_len_eff := lower_len * stretch
	var to_target := target - shoulder
	var raw := to_target.length()
	if raw < 0.001:
		if caress:
			PERF.end("caress_arm")
		return
	var dir := to_target / raw
	var distance := clampf(raw, absf(upper_len_eff - lower_len_eff) + 0.001,
		upper_len_eff + lower_len_eff - 0.001)
	var cos_a := clampf((upper_len_eff * upper_len_eff + distance * distance
		- lower_len_eff * lower_len_eff) / (2.0 * upper_len_eff * distance), -1.0, 1.0)
	var bend := acos(cos_a)
	var pole := Vector3.ZERO
	if natural and not pole_key.is_empty():
		var outward_sign := 1.0 if pole_key == "left" else -1.0
		pole = _arm_pole(pole_key, shoulder, target, body_basis, outward_sign,
			get_process_delta_time(), pole_target_basis)
	else:
		# Carry the elbow plane from the current arm; fall back to the bed's up then its side.
		pole = skeleton.get_bone_global_pose(lower).origin - shoulder
		pole -= dir * pole.dot(dir)
		if pole.length() < 0.001:
			var up := (skeleton.global_transform.affine_inverse().basis * Vector3.UP).normalized()
			pole = up - dir * up.dot(dir)
		if pole.length() < 0.001:
			pole = Vector3.RIGHT - dir * Vector3.RIGHT.dot(dir)
	pole = pole.normalized()
	var elbow := shoulder + (dir * cos(bend) + pole * sin(bend)) * upper_len_eff
	var upper_g := skeleton.get_bone_global_pose(upper)
	var upper_axis := (upper_g.basis * lower_offset).normalized()
	var upper_basis := upper_g.basis.orthonormalized() if natural else upper_g.basis
	var upper_origin := shoulder if caress else upper_g.origin
	var q1 := Quaternion(upper_axis, (elbow - shoulder).normalized())
	RIG.set_global(skeleton, upper, Transform3D(Basis(q1) * upper_basis, upper_origin))
	var lower_g := skeleton.get_bone_global_pose(lower)
	var lower_axis := (lower_g.basis * hand_offset).normalized()
	var q2 := Quaternion(lower_axis, (target - lower_g.origin).normalized())
	RIG.set_global(skeleton, lower,
		Transform3D(Basis(q2) * lower_g.basis.orthonormalized(), lower_g.origin))
	RIG.set_global(skeleton, hand, Transform3D(hand_basis, target))
	if caress:
		PERF.end("caress_arm")


## The game's regular desktop arm pole: the elbow bends below the shoulder-to-wrist line with room
## beside the ribs. Carrying the previous plane stops a nearly straight arm from flipping.
func _arm_pole(key: String, shoulder: Vector3, target: Vector3, body_basis: Basis,
		outward_sign: float, delta: float, target_basis: Basis) -> Vector3:
	var axis := target - shoulder
	if axis.length_squared() < 0.000001:
		axis = _arm_axes.get(key, body_basis.z)
	axis = axis.normalized()
	var down := -body_basis.y
	var outward := body_basis.x * outward_sign
	var back := -body_basis.z
	var preferred := down + outward * 0.30 + back * 0.18 + target_basis.y * 0.08
	var desired := preferred - axis * preferred.dot(axis)
	var previous: Vector3 = _arm_poles.get(key, Vector3.ZERO)
	if previous.length_squared() > 0.0:
		var old_axis: Vector3 = _arm_axes.get(key, axis)
		var transport := Quaternion(old_axis, axis) if old_axis.dot(axis) > -0.9999 \
			else Quaternion(previous, PI)
		previous = transport * previous
		previous = (previous - axis * previous.dot(axis)).normalized()
	if desired.length_squared() < 0.0001:
		desired = previous
	if desired.length_squared() < 0.0001:
		desired = outward - axis * outward.dot(axis)
	if desired.length_squared() < 0.0001:
		desired = back - axis * back.dot(axis)
	desired = desired.normalized()
	if previous.length_squared() > 0.0:
		var angle := atan2(axis.dot(previous.cross(desired)), previous.dot(desired))
		var dt := clampf(delta, 0.0, 0.1)
		var step := clampf(angle * (1.0 - exp(-dt / 0.10)), -PI * dt, PI * dt)
		desired = previous.rotated(axis, step).normalized()
	_arm_axes[key] = axis
	_arm_poles[key] = desired
	return desired


## Ease a wrist from one palm frame to another, slerping the basis so the palm plane turns with the
## coat instead of snapping. World bases carry Anon's scale, so both sides are orthonormalized.
static func _blend_frame(from: Transform3D, to: Transform3D, t: float) -> Transform3D:
	if not from.is_finite():
		return to
	if not to.is_finite():
		return from
	var eased := smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))
	return Transform3D(
		from.basis.orthonormalized().slerp(to.basis.orthonormalized(), eased),
		from.origin.lerp(to.origin, eased))


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
	var scale: float = facts.anon_height_scale if facts != null else 1.0
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
		_leg_hide.influence if is_instance_valid(_leg_hide) else -1.0]
	if not odd.is_empty():
		row += " odd=[%s]" % ", ".join(odd)
	var anon: Variant = facts.anon if facts != null else null
	if anon != null and anon.showing():
		var part_scale: Vector3 = anon.debug_scale()
		if part_scale.is_finite():
			row += " part_scale=(%.2f,%.2f,%.2f)" % [
				part_scale.x, part_scale.y, part_scale.z]
	var eye: Variant = eye_transform()
	if eye is Transform3D:
		var at := (eye as Transform3D).origin
		var fwd: Vector3 = -(eye as Transform3D).basis.z.normalized()
		if face.is_finite() and at.distance_squared_to(face) > 0.0001:
			row += " eye_face=%.0f°" % rad_to_deg(fwd.angle_to((face - at).normalized()))
		if vulva.is_finite() and at.distance_squared_to(vulva) > 0.0001:
			row += " eye_vulva=%.0f°" % rad_to_deg(fwd.angle_to((vulva - at).normalized()))
	return row


## The pelvis offset the attached alignment asked for this frame, in world space.
func _hip_offset() -> Vector3:
	var anon: Variant = facts.anon if facts != null else null
	return anon.hip_offset() if anon != null else Vector3.ZERO


## Tell the part the offset was applied, so next frame it measures from the moved body.
func _note_hip_offset(offset: Vector3) -> void:
	var anon: Variant = facts.anon if facts != null else null
	if anon != null:
		anon.note_hip_offset(offset)


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


## The union of the two authored blocks' bone indices, resolved once per skeleton. The shipped
## assets carry the same rig, so the second pass is normally empty.
func _cache_asset_indices(from_bones: Dictionary, to_bones: Dictionary) -> void:
	var id := skeleton.get_instance_id()
	if id == _asset_index_skeleton and not _asset_indices.is_empty():
		return
	_asset_indices.clear()
	for key: Variant in from_bones:
		var name := str(key)
		var bone := skeleton.find_bone(name)
		if bone >= 0:
			_asset_indices[name] = bone
	for key: Variant in to_bones:
		var name := str(key)
		if _asset_indices.has(name):
			continue
		var bone := skeleton.find_bone(name)
		if bone >= 0:
			_asset_indices[name] = bone
	_asset_index_skeleton = id
