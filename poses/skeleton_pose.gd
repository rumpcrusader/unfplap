extends SkeletonModifier3D
## SkeletonModifier3D evaluator for one pose pair and the live edge weight.

const RIG := preload("res://mods/unfplap/poses/pose_rig.gd")
const DRIVER := preload("res://mods/unfplap/poses/pose_driver.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const MISSIONARY := preload("res://mods/unfplap/poses/missionary_recipe.gd")
const STANDING := preload("res://mods/unfplap/poses/standing_recipe.gd")
const STANDING_ORAL := preload("res://mods/unfplap/poses/standing_oral_recipe.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")

## The typed live mode. `MODE_SINGLE` runs the one-driver fast path; `MODE_BLEND` evaluates both
## bases, blends the captured transforms and applies the overlays once.
const MODE_SINGLE := 0
const MODE_BLEND := 1

const MISSIONARY_PATH := "poses/missionary_recipe.gd"
const STANDING_PATH := "poses/standing_recipe.gd"
const STANDING_ORAL_PATH := "poses/standing_oral_recipe.gd"
## The shipped procedural drivers, by the spec's `driver`/`delta` path. A suite may inject fakes
## through `driver_objects`.
const DRIVERS := {
	MISSIONARY_PATH: MISSIONARY,
	STANDING_PATH: STANDING,
	STANDING_ORAL_PATH: STANDING_ORAL,
}

var mare: Node3D
## The live effective mode: typed, with no "afterglow" value.
var mode := MODE_SINGLE
## The resolved pair. Paths are the service's effective driver/delta paths, configs are by
## reference, and a second `set_pose()` with the same pair keeps the same objects.
var from_driver := ""
var to_driver := ""
var from_delta := ""
var to_delta := ""
## Path -> driver object. Seeded with the two shipped drivers; the suite may inject fakes.
var driver_objects: Dictionary = {}
var look_point := Vector3.ZERO
var head_back := 0.0
var amount := 0.0
var target_amount := 0.0
var climaxing := false
var pose_config: Dictionary = {}
## Hand-authored base pose and the space it is placed in. A null asset or a missing frame leaves
## the recipe's correction stack as the fallback.
var authored: AUTHORED = null
## The face contact's world-space correction, written by the session's face driver and applied by
## the recipe to the armature root. Zero on every other contact.
var contact_offset := Vector3.ZERO
## The authored assets of the two sides. A pair with different assets blends even when driver and
## config match; a null side reuses the live asset.
var from_authored: AUTHORED = null
var to_authored: AUTHORED = null
var bed_frame: Variant = null
## The ground frame for a ground pose: the pony root's basis and position at pose start.
var ground_frame: Variant = null
## The live size name, for the asset's variant selection.
var size_name := ""

var _rig = RIG.new()
var _missionary = MISSIONARY.new()
var _standing = STANDING.new()
## The resolved pair: the driver/delta objects for each side and the two config references.
var _from_driver_obj: DRIVER = null
var _to_driver_obj: DRIVER = null
var _from_delta_obj: DRIVER = null
var _to_delta_obj: DRIVER = null
var _from_config: Dictionary = {}
var _to_config: Dictionary = {}
var _blend_weight := 1.0
var _single := true
## Scratch transforms for the two-base blend, sized once per bone count; a blend then allocates
## nothing per frame.
var _pre: Array[Transform3D] = []
var _from_pose: Array[Transform3D] = []
var _to_pose: Array[Transform3D] = []
var _debug_dumped := false
var _clock := 0.0
# Act diagnostics: frames run, last weight and base, and hips drift since the last write. A near
# zero readback means our writes survive the next modification pass. Anything else means another
# writer overwrote the pose in between.
var diag_frames := 0
var diag_readback_deg := 0.0
## Angle between the authored hips rotation and what the skeleton holds immediately after the
## modifier wrote it. Near zero means the write landed; large means the write itself is not taking.
var diag_after_write_deg := 0.0
## Placement trace: the armature bone and the hips in world space, before our write, right after
## it and again at render time. The readings are carried into the live bed frame, so they compare.
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


func _init() -> void:
	driver_objects[MISSIONARY_PATH] = _missionary
	driver_objects[STANDING_PATH] = _standing


## The service's resolved pair, configs by reference; a same-pair call keeps the same objects.
## The trailing assets are the two sides' authored documents.
func set_pose(from_path: String, to_path: String, from_delta_path: String, to_delta_path: String,
		from_config: Dictionary, to_config: Dictionary,
		from_asset: AUTHORED = null, to_asset: AUTHORED = null) -> void:
	from_driver = from_path
	to_driver = to_path
	from_delta = from_delta_path
	to_delta = to_delta_path
	_from_config = from_config
	_to_config = to_config
	from_authored = from_asset
	to_authored = to_asset
	_from_driver_obj = _driver(from_driver)
	_to_driver_obj = _driver(to_driver)
	_from_delta_obj = _driver(from_delta)
	_to_delta_obj = _driver(to_delta)
	_single = from_driver == to_driver and from_delta == to_delta \
		and _configs_equal(from_config, to_config) and is_same(from_authored, to_authored)
	mode = MODE_SINGLE if _single else MODE_BLEND
	_blend_weight = 1.0
	var sk := get_skeleton()
	if sk != null:
		_resize_buffers(sk)


## The live edge weight, 0..1. The single path keeps its pose ramp (`amount`); the blend reads
## this value from the render pass.
func set_weight(weight: float) -> void:
	_blend_weight = clampf(weight, 0.0, 1.0)


## The driver object for one effective path. The two shipped drivers are seeded in `_init()`;
## another path is instantiated once from `DRIVERS` and cached. An unknown or empty path is null.
func _driver(path: String) -> DRIVER:
	if path.is_empty():
		return null
	if driver_objects.has(path):
		return driver_objects[path] as DRIVER
	var script: Variant = DRIVERS.get(path)
	if script == null:
		return null
	var made: DRIVER = (script as GDScript).new()
	driver_objects[path] = made
	return made


## The two flat pose configs, compared by keys, values and the nested `gaps` dictionary. Equal
## configs are what makes the debug pair's move a single-path hold.
func _configs_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key: Variant in a:
		if not b.has(key):
			return false
		if not _values_equal(a[key], b[key]):
			return false
	return true


func _values_equal(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		return _configs_equal(a as Dictionary, b as Dictionary)
	if (a is float or a is int) and (b is float or b is int):
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	return a == b


func _ready() -> void:
	_cache()


func _cache() -> void:
	var sk := get_skeleton()
	if sk == null or not is_instance_valid(mare):
		return
	if not _rig.cached:
		_rig.cache(mare, sk)


func _process_modification_with_delta(delta: float) -> void:
	PERF.begin("pose_recipe")
	_apply(delta)
	PERF.end("pose_recipe")


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


## Re-apply the pose outside the modifier pass, after every other writer of the frame. The
## renderer sees this write; `amount` still advances only in the modifier pass.
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
		"climaxing": climaxing,
		"clock": _clock,
		"config": _from_config,
		"authored": authored,
		"contact_offset": contact_offset,
		"bed_frame": bed_frame,
		"ground_frame": ground_frame,
		"size_name": size_name,
		"body_scale": float(mare_scale) if mare_scale != null else 1.0,
	}
	if mode == MODE_SINGLE:
		diag_last_base = "authored" if authored != null and _frame() is Transform3D \
			and authored.available else "none"
	else:
		diag_last_base = "blend"
	var tracing := mode == MODE_SINGLE and trace and diag_trace < 3 and weight > 0.9 \
		and authored != null and authored.available and _frame() is Transform3D
	if tracing:
		_trace_before(sk, state)
	if mode == MODE_SINGLE:
		_write_single(sk, weight, state)
	else:
		_write_blend(sk, state)
	if _rig.hips >= 0:
		_diag_wrote_hips = sk.get_bone_pose_rotation(_rig.hips)
		_diag_wrote = true
		if authored != null and authored.available:
			var entries := authored.pony_bones
			var entry: Variant = entries.get("pony_hips") if entries is Dictionary else null
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


## The one-driver fast path: the recipe's whole-pose `apply()` with the pose ramp, unless the pose
## carries a delta, in which case the base, the procedural delta and the overlay run in that order.
func _write_single(sk: Skeleton3D, weight: float, state: Dictionary) -> void:
	state["config"] = _from_config
	var driver := _from_driver_obj
	if driver == null:
		return
	if from_delta.is_empty():
		driver.apply(_rig, sk, weight, state)
	else:
		var applied := true
		if driver.splits_base():
			applied = driver.apply_base(_rig, sk, weight, state)
		else:
			driver.apply(_rig, sk, weight, state)
		if applied:
			_apply_delta(_from_delta_obj, sk, weight, state)
		driver.apply_overlay(_rig, sk, weight, state)
	if from_driver == MISSIONARY_PATH:
		_dump_if_needed(sk, weight)


## The two-base form: capture the pre-pose, evaluate each side at full weight, blend the captured
## transforms, then run the overlays once.
func _write_blend(sk: Skeleton3D, state: Dictionary) -> void:
	_resize_buffers(sk)
	_capture(sk, _pre)
	state["config"] = _from_config
	state["authored"] = from_authored if from_authored != null else authored
	_apply_base_side(_from_driver_obj, _from_delta_obj, sk, state)
	_capture(sk, _from_pose)
	_restore(sk, _pre)
	state["config"] = _to_config
	state["authored"] = to_authored if to_authored != null else authored
	_apply_base_side(_to_driver_obj, _to_delta_obj, sk, state)
	_capture(sk, _to_pose)
	_restore(sk, _pre)
	var blend := clampf(_blend_weight, 0.0, 1.0)
	_blend_bones(sk, blend)
	# The overlays read the config, not the asset; the state stays on the to side until the blend
	# pass is over, then the post-write diagnostics see the live asset again.
	state["config"] = _from_config
	_apply_overlay_side(_from_driver_obj, 1.0 - blend, sk, state)
	state["config"] = _to_config
	_apply_overlay_side(_to_driver_obj, blend, sk, state)
	state["authored"] = authored


func _apply_base_side(driver: DRIVER, delta: DRIVER, sk: Skeleton3D, state: Dictionary) -> void:
	if driver == null:
		return
	var applied := true
	if driver.splits_base():
		applied = driver.apply_base(_rig, sk, 1.0, state)
	else:
		driver.apply(_rig, sk, 1.0, state)
	if applied:
		_apply_delta(delta, sk, 1.0, state)


func _apply_overlay_side(driver: DRIVER, weight: float, sk: Skeleton3D,
		state: Dictionary) -> void:
	if driver == null:
		return
	driver.apply_overlay(_rig, sk, weight, state)


func _apply_delta(delta: DRIVER, sk: Skeleton3D, weight: float, state: Dictionary) -> void:
	if delta == null:
		return
	delta.apply_delta(_rig, sk, weight, state)


## Blend the two captured local poses at the edge weight. Rotation slerps, scale and origin lerp;
## a non-finite result is dropped instead of written.
func _blend_bones(sk: Skeleton3D, weight: float) -> void:
	var count := mini(_from_pose.size(), _to_pose.size())
	count = mini(count, sk.get_bone_count())
	for i: int in count:
		var from: Transform3D = _from_pose[i]
		var to: Transform3D = _to_pose[i]
		var rotation: Basis = from.basis.orthonormalized().slerp(to.basis.orthonormalized(), weight)
		var scale := from.basis.get_scale().lerp(to.basis.get_scale(), weight)
		var blended := Transform3D(rotation.scaled(scale), from.origin.lerp(to.origin, weight))
		if not _finite_transform(blended):
			continue
		sk.set_bone_pose(i, blended)


func _finite_transform(value: Transform3D) -> bool:
	return value.origin.is_finite() and value.basis.x.is_finite() \
		and value.basis.y.is_finite() and value.basis.z.is_finite()


func _resize_buffers(sk: Skeleton3D) -> void:
	var count := sk.get_bone_count()
	if _pre.size() == count and _from_pose.size() == count and _to_pose.size() == count:
		return
	_pre.resize(count)
	_from_pose.resize(count)
	_to_pose.resize(count)


func _capture(sk: Skeleton3D, into: Array[Transform3D]) -> void:
	var count := sk.get_bone_count()
	if into.size() != count:
		into.resize(count)
	for i: int in count:
		into[i] = sk.get_bone_pose(i)


func _restore(sk: Skeleton3D, from: Array[Transform3D]) -> void:
	var count := mini(sk.get_bone_count(), from.size())
	for i: int in count:
		sk.set_bone_pose(i, from[i])


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
	if authored != null:
		diag_asset_root = authored.root_bone(sk)
	diag_root_name = sk.get_bone_name(diag_root) if diag_root >= 0 else "none"
	if diag_root >= 0:
		diag_root_start = g * sk.get_bone_global_pose(diag_root)
	if _rig.hips >= 0:
		diag_hips_start = g * sk.get_bone_global_pose(_rig.hips)
	var frame: Transform3D = _frame()
	var body_scale := float(state.get("body_scale", 1.0))
	diag_root_wanted = authored.placed_root(frame, body_scale)
	var entries := authored.pony_bones
	var entry: Variant = entries.get("pony_hips") if entries is Dictionary else null
	if entry is Dictionary:
		var local := Transform3D(Basis((entry as Dictionary)["rotation"]), (entry as Dictionary)["position"])
		if _rig.hips >= 0:
			local = sk.get_bone_rest(_rig.hips) * local
		diag_hips_wanted = diag_root_wanted * local


## The live pose space: the bed frame when it is set, otherwise the ground frame.
func _frame() -> Variant:
	if bed_frame is Transform3D:
		return bed_frame
	return ground_frame


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
	LOG.debug(text)
