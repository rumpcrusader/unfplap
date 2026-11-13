extends SkeletonModifier3D
## SkeletonModifier3D driver. Pose-specific numbers and bone steps live in
## `missionary_recipe.gd` / `standing_recipe.gd`; shared bone access lives in `pose_rig.gd`.

const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const RIG := preload("res://mods/unfplap/poses/pose_rig.gd")
const MISSIONARY := preload("res://mods/unfplap/poses/missionary_recipe.gd")
const STANDING := preload("res://mods/unfplap/poses/standing_recipe.gd")

var mare: Node3D
## Host boundary: the pose writes no scene value back; it only reports a timed chunk and a
## debug line. A pose built without a context is silent.
var perf := Callable()
var log := Callable()
var mode := "missionary"
var afterglow_pose := CATALOG.MISSIONARY
var look_point := Vector3.ZERO
var head_back := 0.0
var kiss := 0.0
var amount := 0.0
var target_amount := 0.0
var climaxing := false
var pose_config: Dictionary = {}
## Hand-authored base pose (poses/authored_pose.gd) and the bed space it is placed in. A null
## asset or a missing frame leaves the recipe's correction stack as the fallback.
var authored: Variant = null
var bed_frame: Variant = null

var _rig = RIG.new()
var _missionary = MISSIONARY.new()
var _standing = STANDING.new()
var _debug_dumped := false
var _clock := 0.0
## Act diagnostics (Show pose state / the settled log): frames this modifier ran, the last weight
## and base, and how far the live hips pose drifted from what the previous frame wrote. A readback
## near zero means our writes survive to the next modification pass; anything else means something
## overwrote the pose between them.
var diag_frames := 0
var diag_readback_deg := 0.0
## Angle between the authored hips rotation and what the skeleton holds immediately after the
## modifier wrote it. Near zero means the write landed; large means the write itself is not taking.
var diag_after_write_deg := 0.0
## Placement trace: the armature bone (the pose's skeleton placement) and the hips, in world space,
## at the start of our pass, right after the write, and - read by the runtime at render time - again
## after every physics and process writer. The authored targets are carried into the live bed frame
## here, so the three readings compare directly against `wanted`.
var diag_root := -1
var diag_asset_root := -1
var diag_root_name := ""
var diag_root_start := Transform3D.IDENTITY
var diag_root_after := Transform3D.IDENTITY
var diag_root_wanted := Transform3D.IDENTITY
var diag_hips_start := Transform3D.IDENTITY
var diag_hips_after := Transform3D.IDENTITY
var diag_hips_wanted := Transform3D.IDENTITY
var diag_trace := 0
var diag_last_weight := 0.0
var diag_last_base := ""
var _diag_wrote := false
var _diag_wrote_hips := Quaternion.IDENTITY


func _ready() -> void:
	_cache()


func _cache() -> void:
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(mare):
		return
	if not _rig.cached:
		_rig.cache(mare, sk)


func _process_modification_with_delta(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_apply(delta)
	if perf.is_valid():
		perf.call("pose_recipe", Time.get_ticks_usec() - started)


func _apply(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(mare):
		return
	if not _rig.cached:
		_cache()
	var speed := 0.6 if target_amount > amount else 0.4
	amount = move_toward(amount, target_amount, delta / maxf(speed, 0.01))
	if amount <= 0.001:
		return
	var weight := smoothstep(0.0, 1.0, amount)
	_clock += delta
	diag_frames += 1
	diag_last_weight = weight
	if _diag_wrote and _rig.hips >= 0:
		diag_readback_deg = rad_to_deg(_diag_wrote_hips.angle_to(sk.get_bone_pose_rotation(_rig.hips)))
	_write(sk, weight, true)


## Apply the pose once more, outside the modifier pass and after every other writer of the frame.
## The game re-poses this rig after our modifier pass (the clip tier's `enter`/`leave`, the posture
## and the solver), so the modifier's write is not what the renderer sees; this is. The blend
## `amount` is not advanced here: the modifier pass owns the ramp and the clock.
func apply_render(sk: Skeleton3D) -> void:
	if sk == null or not is_instance_valid(mare):
		return
	if not _rig.cached:
		_cache()
	if amount <= 0.001:
		return
	_write(sk, smoothstep(0.0, 1.0, amount), false)


func _write(sk: Skeleton3D, weight: float, trace: bool) -> void:
	var mare_scale: Variant = mare.get("body_scale")
	var state := {
		"look_point": look_point,
		"head_back": head_back,
		"kiss": kiss,
		"climaxing": climaxing,
		"clock": _clock,
		"config": pose_config,
		"authored": authored,
		"bed_frame": bed_frame,
		"body_scale": float(mare_scale) if mare_scale != null else 1.0,
	}
	diag_last_base = "authored" if authored != null and bed_frame is Transform3D \
		and bool(authored.get("available")) else "none"
	var tracing := trace and diag_trace < 3 and weight > 0.9 and authored != null \
		and bool(authored.get("available")) and bed_frame is Transform3D
	if tracing:
		_trace_before(sk, state)
	if mode == "standing":
		_standing.apply(_rig, sk, weight, state)
	elif mode == "afterglow" and afterglow_pose == CATALOG.MISSIONARY:
		_missionary.apply(_rig, sk, weight, state)
		_dump_if_needed(sk, weight)
	else:
		_missionary.apply(_rig, sk, weight, state)
		_dump_if_needed(sk, weight)
	if _rig.hips >= 0:
		_diag_wrote_hips = sk.get_bone_pose_rotation(_rig.hips)
		_diag_wrote = true
		if authored != null and bool(authored.get("available")):
			var entries: Variant = authored.get("pony_bones")
			var entry: Variant = (entries as Dictionary).get("pony_hips") if entries is Dictionary else null
			if entry is Dictionary:
				diag_after_write_deg = rad_to_deg(_diag_wrote_hips.angle_to(
					(entry as Dictionary)["rotation"]))
	if tracing:
		var g := sk.global_transform
		if diag_root >= 0:
			diag_root_after = g * sk.get_bone_global_pose(diag_root)
		if _rig.hips >= 0:
			diag_hips_after = g * sk.get_bone_global_pose(_rig.hips)
		diag_trace += 1


## The armature bone: the top of the chain `pony_hips` hangs from. Worked out here as well as through
## the asset, so the trace shows whether both agree at runtime.
func _trace_root(sk: Skeleton3D) -> int:
	var bone := sk.find_bone("pony_hips")
	while bone >= 0:
		var parent := sk.get_bone_parent(bone)
		if parent < 0:
			return bone
		bone = parent
	return -1


func _trace_before(sk: Skeleton3D, state: Dictionary) -> void:
	var g := sk.global_transform
	diag_root = _trace_root(sk)
	diag_asset_root = -1
	if authored != null and authored.has_method("root_bone"):
		diag_asset_root = int(authored.call("root_bone", sk))
	diag_root_name = sk.get_bone_name(diag_root) if diag_root >= 0 else "none"
	if diag_root >= 0:
		diag_root_start = g * sk.get_bone_global_pose(diag_root)
	if _rig.hips >= 0:
		diag_hips_start = g * sk.get_bone_global_pose(_rig.hips)
	var frame: Transform3D = bed_frame
	var placement: Variant = authored.get("pony_frame")
	if placement is Transform3D:
		var scaled: Transform3D = placement
		scaled.origin *= float(state.get("body_scale", 1.0))
		diag_root_wanted = frame * scaled
	var entries: Variant = authored.get("pony_bones")
	var entry: Variant = (entries as Dictionary).get("pony_hips") if entries is Dictionary else null
	if entry is Dictionary:
		diag_hips_wanted = diag_root_wanted * Transform3D(
			Basis((entry as Dictionary)["rotation"]), (entry as Dictionary)["position"])


## Degrees between her pelvis up and the world up.
func sk_body_up(sk: Skeleton3D) -> float:
	var bone := sk.find_bone("pony_hips")
	if bone < 0:
		return 0.0
	var up := (sk.global_basis * sk.get_bone_global_pose(bone).basis.y).normalized()
	return rad_to_deg(up.angle_to(Vector3.UP))


func _dump_if_needed(sk: Skeleton3D, weight: float) -> void:
	if _debug_dumped or weight <= 0.9:
		return
	_debug_dumped = true
	var body := _rig.forward_axis(sk)
	body.y = 0.0
	if body.length_squared() > 0.0001:
		body = body.normalized()
	var rows := PackedStringArray()
	rows.append("base=%s root=%s mare=%s scale=%.2f" % [
		diag_last_base, str(sk.global_basis), str(mare.global_basis), float(mare.body_scale)])
	var chain: Array[int] = []
	if _rig.hips >= 0:
		chain.append(_rig.hips)
	chain.append_array(_rig.spine)
	chain.append_array(_rig.neck)
	var parts: PackedStringArray = []
	for i: int in chain.size():
		var bone := chain[i]
		if bone < 0 or i + 1 >= chain.size():
			continue
		var origin := sk.get_bone_global_pose(bone).origin
		var next := sk.get_bone_global_pose(chain[i + 1]).origin
		var direction := next - origin
		if direction.length_squared() < 0.000001:
			continue
		direction = direction.normalized()
		parts.append("%s %.0f°" % [sk.get_bone_name(bone).trim_prefix("pony_"),
			rad_to_deg(direction.angle_to(body))])
	rows.append("chain %s (deviation from body axis)" % " | ".join(parts))
	var boop: Variant = mare.get("boop_node")
	var hs: Variant = boop.get("head_skeleton") if boop != null else null
	if hs is Skeleton3D:
		var head_bone := (hs as Skeleton3D).find_bone("mHead")
		if head_bone >= 0:
			var head_pose := (hs as Skeleton3D).get_bone_global_pose(head_bone)
			rows.append("head mHead origin=%s dir=%s" % [
				str(head_pose.origin), str(head_pose.basis.z)])
			var head_world := (hs as Skeleton3D).global_transform * head_pose
			var facing := head_world.basis.z.normalized()
			var to_look := look_point - head_world.origin
			var aim := 180.0
			if to_look.length_squared() > 0.0001:
				aim = rad_to_deg(facing.angle_to(to_look.normalized()))
			var roll := 0.0
			var level := Vector3.UP - facing * Vector3.UP.dot(facing)
			if level.length_squared() > 0.0001:
				roll = rad_to_deg(head_world.basis.y.normalized().signed_angle_to(
					level.normalized(), facing))
			rows.append("head aim=%.1f° roll=%.1f° look=%s" % [aim, roll, str(look_point)])
		else:
			rows.append("head mHead missing")
	else:
		rows.append("head_skeleton unavailable")
	# Her body's own up against the world's: a rolled pose reads as lying on her side.
	rows.append("body up=%.0f°" % sk_body_up(sk))
	var text := "MISSIONARY"
	for row: String in rows:
		text += "\n\t" + row
	# The runtime's `log` callback is the one debug gate (Enable debug). A pose without a
	# context has no console owner and stays silent.
	if log.is_valid():
		log.call(text)
