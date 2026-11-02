extends SkeletonModifier3D
## SkeletonModifier3D driver. Pose-specific numbers and bone steps live in
## `missionary_recipe.gd` / `horse_recipe.gd`; shared bone access lives in `pose_rig.gd`.

const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const RIG := preload("res://mods/unfplap/poses/pose_rig.gd")
const MISSIONARY := preload("res://mods/unfplap/poses/missionary_recipe.gd")
const HORSE := preload("res://mods/unfplap/poses/horse_recipe.gd")

const DEBUG_POSE1_DUMP := true

var mare: Node3D
var mode := "pose1"
var afterglow_pose := CATALOG.MISSIONARY
var look_point := Vector3.ZERO
var head_back := 0.0
var kiss := 0.0
var amount := 0.0
var target_amount := 0.0
var head_roll := 0.0
var climaxing := false
var pose_config: Dictionary = {}

var _rig = RIG.new()
var _missionary = MISSIONARY.new()
var _horse = HORSE.new()
var _debug_dumped := false
var _clock := 0.0


func _ready() -> void:
	_cache()


func _cache() -> void:
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(mare):
		return
	if not _rig.cached:
		_rig.cache(mare, sk)


func _process_modification_with_delta(delta: float) -> void:
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
	var state := {
		"look_point": look_point,
		"head_roll": head_roll,
		"head_back": head_back,
		"kiss": kiss,
		"climaxing": climaxing,
		"clock": _clock,
		"config": pose_config,
	}
	if mode == "pose2":
		_horse.apply(_rig, sk, weight, state)
	elif mode == "afterglow" and afterglow_pose == CATALOG.MISSIONARY:
		_missionary.apply(_rig, sk, weight, state)
		_dump_if_needed(sk, weight)
	else:
		_missionary.apply(_rig, sk, weight, state)
		_dump_if_needed(sk, weight)


func _dump_if_needed(sk: Skeleton3D, weight: float) -> void:
	if not DEBUG_POSE1_DUMP or _debug_dumped or weight <= 0.9:
		return
	_debug_dumped = true
	var body := _rig.forward_axis(sk)
	body.y = 0.0
	if body.length_squared() > 0.0001:
		body = body.normalized()
	var rows := PackedStringArray()
	rows.append("root=%s mare=%s scale=%.2f roll pelvis=%.1f° chest=%.1f°" % [
		str(sk.global_basis), str(mare.global_basis), float(mare.body_scale),
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
	var text := "[unfplap] POSE1"
	for row: String in rows:
		text += "\n\t" + row
	print(text)
