extends RefCounted
## Persistent anatomy shape state: the winking mesh, the closed/idle/fill/grip drive, Anon's
## shaft mask and the V2 anal keys. It owns the tweens on the anatomy node and exposes the
## opening queries the act and coat use.
##
## See `docs/anatomy.md` (`## Act anatomy`).

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const GEOMETRY := preload("res://mods/unfplap/anatomy/geometry.gd")

const WINKING_OPENING := Vector3(0.0, -0.012, 0.02)
const ANAL_OPENING := Vector3(0.0, 0.071, 0.019)
const LIP_OUTER_FACTOR := 3.0
const WINKING_CUT_DEPTH := 0.07
const WINKING_CUT_FILLED := 0.9

var pony: Node3D
var host: Node
var mesh: MeshInstance3D
var _v2_anal := false

var _anal_local := 0.0
var _anal_mouth := GEOMETRY.V2_ANAL_RING_BASE
var _shaft_pivot := Vector3.ZERO
var _shaft_axis := Vector3.ZERO
var _shaft_length := 0.0
var _shaft_radii := PackedFloat32Array()
var _closed := 1.0
var _rest := 1.0
var _wink_amount := 0.0
var _idle_wink := false
var _fill := 0.0
var _wide := 0.0
var _hole_target := 0.0
var _lip_radius := GEOMETRY.WINKING_LIP_RADIUS
var _tween: Tween


func setup(pony_node: Node3D, host_node: Node) -> void:
	pony = pony_node
	host = host_node


func set_mesh(mesh_node: MeshInstance3D, is_v2: bool) -> void:
	mesh = mesh_node
	_v2_anal = is_v2
	_anal_mouth = GEOMETRY.V2_ANAL_RING_BASE
	_anal_local = 0.0
	_lip_radius = _measure_lip_radius()
	_apply_winking_shape()
	_apply_anal_shape(0.0)


func clear_mesh() -> void:
	mesh = null
	_v2_anal = false
	_anal_local = 0.0
	_anal_mouth = GEOMETRY.V2_ANAL_RING_BASE
	_lip_radius = GEOMETRY.WINKING_LIP_RADIUS
	_closed = 1.0
	_rest = 1.0
	_wink_amount = 0.0
	_idle_wink = false
	_fill = 0.0
	_wide = 0.0
	_hole_target = 0.0
	if _tween != null:
		_tween.kill()
	_tween = null


func winking_mesh() -> MeshInstance3D:
	return mesh


func anal_mesh() -> MeshInstance3D:
	return mesh if _v2_anal else null


func v2_anal() -> bool:
	return _v2_anal


func lip_radius() -> float:
	return _lip_radius


func anal_local() -> float:
	return _anal_local


func anal_mouth() -> Vector3:
	return _anal_mouth


func hole_target() -> float:
	return _hole_target


func wink_amount() -> float:
	return _wink_amount


func fill() -> float:
	return _fill


func wide() -> float:
	return _wide


func tween_running() -> bool:
	return _tween != null and _tween.is_running()


## Test/debug snapshot of the shape state; the controller's forwarding methods keep the public
## shape API stable while the system is split.
## Reapply the blend shapes and the shader cut after the material is rebuilt.
func refresh_winking() -> void:
	_apply_winking_shape()


## Reapply the current anal keys after the mesh or material is rebuilt.
func refresh_anal() -> void:
	_apply_anal_shape(_anal_local)


## Apply a local penetration radius directly. Used by the V2 shape tests and the debug path.
func apply_anal_local(local: float) -> void:
	_apply_anal_shape(local)


func state() -> Dictionary:
	return {
		"closed": _closed,
		"rest": _rest,
		"wink": _wink_amount,
		"idle_wink": _idle_wink,
		"fill": _fill,
		"wide": _wide,
		"hole_target": _hole_target,
		"lip_radius": _lip_radius,
		"anal_local": _anal_local,
		"anal_mouth": _anal_mouth,
		"v2_anal": _v2_anal,
	}


func hole_local(mix: float) -> Vector3:
	var anal := _anal_mouth if _v2_anal else ANAL_OPENING
	var t := clampf(mix, 0.0, 1.0)
	var local := WINKING_OPENING.lerp(anal, t)
	if _v2_anal and is_instance_valid(mesh):
		var scale := maxf(mesh.global_transform.basis.get_scale().y, 0.0001)
		local += Vector3(0.0, SETTINGS.anal_aim_mm.get_num() / 1000.0 * t / scale, 0.0)
	return local


func hole_point(mix := 0.0) -> Vector3:
	if not is_instance_valid(mesh):
		return Vector3.ZERO
	var point := mesh.global_transform * WINKING_OPENING
	if not _v2_anal:
		return point
	var t := clampf(mix, 0.0, 1.0)
	var anal := mesh.global_transform * _anal_mouth
	anal += mesh.global_transform.basis.y.normalized() \
		* (SETTINGS.anal_aim_mm.get_num() / 1000.0)
	return point.lerp(anal, t)


func hole_rear(_mix := 0.0) -> Vector3:
	if not is_instance_valid(mesh):
		return Vector3.BACK
	return mesh.global_basis.z.normalized()


func set_closed(value: float) -> void:
	_idle_wink = false
	_closed = clampf(value, 0.0, 1.0)
	_apply_winking_shape()


## Idle heat crossfade: 0 is resting closed, 1 is the authored open shape. The `closed` shape
## carries the lips; the V2 `wink` shape adds the clitoral accent. The depth cut stays out of the
## idle rest: it pulls the pink interior toward the camera, and the clitoris sits in that mask, so
## a partial cut drags it out through the lips.
func set_idle_wink(amount: float) -> void:
	_wink_amount = clampf(amount, 0.0, 1.0)
	_idle_wink = true
	_closed = 1.0 - _wink_amount
	_apply_winking_shape()


func drive(closed: float) -> void:
	_idle_wink = false
	_wink_amount = 0.0
	_rest = clampf(closed, 0.0, 1.0)
	if _tween != null:
		_tween.kill()
	set_closed(_rest)


func animate(target: float, seconds: float) -> void:
	if not is_instance_valid(mesh) or not is_instance_valid(host):
		return
	_idle_wink = false
	_wink_amount = 0.0
	_rest = clampf(target, 0.0, 1.0)
	if _tween != null:
		_tween.kill()
	_apply_winking_shape()
	_tween = host.create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(set_closed, _closed, _rest, seconds)


func wink(count := 1, seconds := 0.45) -> void:
	if not is_instance_valid(mesh) or not is_instance_valid(host):
		return
	_idle_wink = false
	var peak := 0.25 if _rest > 0.5 else 0.85
	if _tween != null:
		_tween.kill()
	_tween = host.create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var from := _closed
	for _i in count:
		_tween.tween_method(set_closed, from, peak, seconds * 0.5)
		_tween.tween_method(set_closed, peak, _rest, seconds * 0.5)
		from = _rest


## Idle heat wink. Each beat gets its own depth and timing, so a double or triple never reads as
## one repeated motion. `on_peak` runs at the first beat's peak, when the clitoris has finished
## travelling outward, instead of at the start of the opening.
func wink_burst(count: int, discharge_count: int, rest_open: float,
		on_peak: Callable) -> void:
	if not is_instance_valid(mesh) or not is_instance_valid(host):
		return
	if _tween != null:
		_tween.kill()
	# AFTERGLOW/RESTORE can still hold the act's grip. Clear it so the idle wink reads as a wink.
	if _fill > 0.0 or _wide > 0.0:
		clear_part()
	var open_a := clampf(SETTINGS.wink_open_min.get_num(), 0.0, 1.0)
	var open_b := clampf(SETTINGS.wink_open_max.get_num(), 0.0, 1.0)
	var open_min := minf(open_a, open_b)
	var open_max := maxf(open_a, open_b)
	var timing := maxf(SETTINGS.wink_timing.get_num(), 0.01)
	_tween = host.create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var from := _wink_amount
	for i in count:
		var peak := randf_range(open_min, open_max)
		var opening := _tween.tween_method(set_idle_wink, from, peak,
			randf_range(0.18, 0.38) * timing)
		opening.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		if i == 0 and discharge_count > 0 and on_peak.is_valid():
			_tween.tween_callback(on_peak.bind(discharge_count))
		_tween.tween_interval(randf_range(0.08, 0.18) * timing)
		var closing := _tween.tween_method(set_idle_wink, peak, rest_open,
			randf_range(0.22, 0.45) * timing)
		closing.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		if i < count - 1:
			_tween.tween_interval(randf_range(0.08, 0.18) * timing)
		from = rest_open


## Missionary can use its own hug hack; every other pose keeps the anatomy setting.
func _vulva_hug_mm(missionary: bool) -> float:
	if missionary:
		return SETTINGS.vulva_hug_mm_for(SETTINGS.pony_size_name())
	return SETTINGS.vulva_hug_mm.get_num()


## Open the lips to the shaft's actual radius. `shaft_radius` is world metres; the mesh works in
## local units, so it is converted with the mesh scale and solved against the measured lip radius:
## the lip band is remapped from the rim out to `lip_outer`, so the opening reaches exactly that
## radius while the outer silhouette keeps its shape.
func set_grip(shaft_radius: float, missionary: bool) -> void:
	_wide = maxf(shaft_radius, 0.0)
	if not is_instance_valid(mesh):
		return
	var material := mesh.get_surface_override_material(0) as ShaderMaterial
	if material == null:
		return
	var scale := maxf(mesh.global_transform.basis.get_scale().x, 0.0001)
	var hug := _vulva_hug_mm(missionary) / 1000.0 if shaft_radius > 0.0 else 0.0
	var local := maxf(shaft_radius + hug, 0.0) / scale
	_hole_target = local
	# No blend shape at all: it scales the whole mesh. The shader opens the hole by translating
	# the rim band outward to the measured shaft radius.
	var shape := mesh.find_blend_shape_by_name("stretch")
	if shape >= 0:
		mesh.set_blend_shape_value(shape, 0.0)
	material.set_shader_parameter("hole_target", local)


## Publish Anon's shaft so the shader can project any vertex that ends up inside it back onto the
## surface. `radii` are world metres, sampled evenly from base to tip.
func set_shaft(pivot: Vector3, axis: Vector3, length: float, radii: PackedFloat32Array) -> void:
	_shaft_pivot = pivot
	_shaft_axis = axis
	_shaft_length = length
	_shaft_radii = radii
	_push_shaft(mesh)


func _push_shaft(target: MeshInstance3D) -> void:
	if not is_instance_valid(target):
		return
	var material := target.get_surface_override_material(0) as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("shaft_pivot", _shaft_pivot)
	material.set_shader_parameter("shaft_axis", _shaft_axis)
	material.set_shader_parameter("shaft_length", _shaft_length)
	material.set_shader_parameter("shaft_radii", _shaft_radii)


func clear_shaft() -> void:
	var zeros := PackedFloat32Array()
	zeros.resize(8)
	set_shaft(Vector3.ZERO, Vector3.ZERO, 0.0, zeros)


func set_fill(fill: float) -> void:
	_fill = clampf(fill, 0.0, 1.0)
	_apply_winking_shape()


func _apply_winking_shape() -> void:
	if not is_instance_valid(mesh):
		return
	var shape := mesh.find_blend_shape_by_name("closed")
	if shape >= 0:
		mesh.set_blend_shape_value(shape, _closed)
	var wink_shape := mesh.find_blend_shape_by_name("wink")
	if wink_shape >= 0:
		mesh.set_blend_shape_value(wink_shape, _wink_amount)
	var material := mesh.get_surface_override_material(0) as ShaderMaterial
	if material != null:
		# The depth cut is the act's shaft opening only. The idle wink drives `closed` too, so
		# keep the cut fully off while the idle crossfade owns the shapes.
		var open := 0.0 if _idle_wink else smoothstep(0.0, 0.4, 1.0 - _closed)
		var filled := lerpf(1.0, WINKING_CUT_FILLED, smoothstep(0.5, 1.0, _fill))
		material.set_shader_parameter("cut_depth", WINKING_CUT_DEPTH * open * filled
			* mesh.global_transform.basis.get_scale().x)


## Drive the V2 anal blend shapes from the real shaft radius. Each key starts where the
## previous one ends, so the hole grows continuously into the overstretch and extreme scales.
func set_anal_grip(shaft_radius: float) -> void:
	if not is_instance_valid(mesh) or not _v2_anal:
		return
	var scale := maxf(mesh.global_transform.basis.get_scale().x, 0.0001)
	var hug := SETTINGS.anal_hug_mm.get_num() / 1000.0 if shaft_radius > 0.0 else 0.0
	_anal_local = maxf(shaft_radius + hug, 0.0) / scale
	_apply_anal_shape(_anal_local)


## Set the four anal keys and the independent ponut scale key. The ponut key is a 2x
## ponut-only scale with a boundary falloff, so the ring, vulva and opening stay put. The
## extreme key carries its own whole-patch 2x scale and fades the ponut key out.
func _apply_anal_shape(local: float) -> void:
	if not is_instance_valid(mesh) or not _v2_anal:
		return
	var weights := GEOMETRY.anal_ring_weights(local, SETTINGS.anal_scale.get_num())
	_anal_mouth = GEOMETRY.anal_ring_centre(weights)
	for pair: Array in [["anal_open", "open"], ["anal_stretch", "stretch"],
			["anal_overstretch", "over"], ["anal_extreme", "extreme"],
			["ponut_scale", "ponut"]]:
		var index := mesh.find_blend_shape_by_name(str(pair[0]))
		if index >= 0:
			mesh.set_blend_shape_value(index, float(weights.get(str(pair[1]), 0.0)))


## Kept for the act's call order; the old cup's cut depth is gone and the shape keys do the work.
func set_anal_shape(_fill: float, _wide := 0.0) -> void:
	pass


func react() -> void:
	if is_instance_valid(mesh):
		wink(2)


func clear_part() -> void:
	set_fill(0.0)
	set_grip(0.0, false)
	set_anal_grip(0.0)
	_apply_winking_shape()


func _measure_lip_radius() -> float:
	return GEOMETRY.stable_lip_radius(
		_measure_ring_radius(mesh, WINKING_OPENING, GEOMETRY.WINKING_LIP_RADIUS))


func _measure_ring_radius(target: MeshInstance3D, centre: Vector3, fallback: float) -> float:
	if not is_instance_valid(target) or target.mesh == null:
		return fallback
	var arrays := target.mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return fallback
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return fallback
	const STEP := 0.002
	const BINS := 40
	var bin_counts := PackedInt32Array()
	bin_counts.resize(BINS)
	for v: Vector3 in verts:
		var radius := Vector2(v.x - centre.x, v.y - centre.y).length()
		var bin := int(radius / STEP)
		if bin >= 0 and bin < BINS:
			bin_counts[bin] += 1
	var peak := 0
	for bin: int in BINS:
		peak = maxi(peak, bin_counts[bin])
	if peak == 0:
		return fallback
	# Walk inward from the densest band until the density collapses: that edge is the rim.
	var dense := int(float(peak) * 0.25)
	var rim_bin := 0
	for bin: int in BINS:
		if bin_counts[bin] >= dense:
			rim_bin = bin
			break
	return maxf(float(rim_bin) * STEP, 0.004)
