extends SkeletonModifier3D
## SkeletonModifier3D driver. Pose-specific numbers and bone steps live in
## `missionary_recipe.gd` / `standing_recipe.gd`; shared bone access lives in `pose_rig.gd`.

const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const RIG := preload("res://mods/unfplap/poses/pose_rig.gd")
const MISSIONARY := preload("res://mods/unfplap/poses/missionary_recipe.gd")
const STANDING := preload("res://mods/unfplap/poses/standing_recipe.gd")

const DEBUG_MISSIONARY_DUMP := true

var mare: Node3D
var runtime: Node
var mode := "missionary"
var afterglow_pose := CATALOG.MISSIONARY
var look_point := Vector3.ZERO
var head_back := 0.0
var kiss := 0.0
var amount := 0.0
var target_amount := 0.0
var head_roll := 0.0
var climaxing := false
var pose_config: Dictionary = {}
## Hand-authored base pose (poses/authored_pose.gd) and the bed space it is placed in. A null
## asset or a missing frame leaves the recipe's correction stack as the fallback.
var authored: Variant = null
var bed_frame: Variant = null
var authored_on := true

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
	if is_instance_valid(runtime):
		runtime.call("perf_note", "pose_recipe", Time.get_ticks_usec() - started)


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
	var mare_scale: Variant = mare.get("body_scale")
	var state := {
		"look_point": look_point,
		"head_roll": head_roll,
		"head_back": head_back,
		"kiss": kiss,
		"climaxing": climaxing,
		"clock": _clock,
		"config": pose_config,
		"authored": authored,
		"authored_on": authored_on,
		"bed_frame": bed_frame,
		"body_scale": float(mare_scale) if mare_scale != null else 1.0,
	}
	diag_last_base = "stack"
	if authored != null and authored_on and bed_frame is Transform3D \
			and bool(authored.get("available")):
		diag_last_base = "authored"
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


func _dump_if_needed(sk: Skeleton3D, weight: float) -> void:
	if not DEBUG_MISSIONARY_DUMP or _debug_dumped or weight <= 0.9:
		return
	_debug_dumped = true
	var body := _rig.forward_axis(sk)
	body.y = 0.0
	if body.length_squared() > 0.0001:
		body = body.normalized()
	var rows := PackedStringArray()
	var base := "stack"
	if authored != null and authored_on and bed_frame is Transform3D \
			and bool(authored.get("available")):
		base = "authored"
	rows.append("base=%s root=%s mare=%s scale=%.2f roll pelvis=%.1f° chest=%.1f°" % [
		base, str(sk.global_basis), str(mare.global_basis), float(mare.body_scale),
		rad_to_deg(_missionary.last_roll), rad_to_deg(_missionary.last_chest_roll)])
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
		else:
			rows.append("head mHead missing")
	else:
		rows.append("head_skeleton unavailable")
	var text := "[unfplap] MISSIONARY"
	for row: String in rows:
		text += "\n\t" + row
	print(text)
