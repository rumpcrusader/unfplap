extends RefCounted
## The Pantyhose & Panties cloth jiggle: makes one worn node follow one pony's live `FlankTouch`
## wobble through six per-node instance uniforms the copied shaders displace their vertices with.
##
## The coat is the only simulator. This helper reads the `jiggle_*` uniforms `FlankTouch` writes
## into a live `_jiggle_targets` material every frame and carries them into the worn node's own
## model space, so the cloth moves by the coat's world displacement in the same frame instead of
## running a second spring that can land out of phase.
##
## The world adapter calls `begin_frame()` once per garment pass, `sample(pony)` for each tracked
## node (the pony's wobble is read once and cached for the rest of the pass) and `apply(node)` for
## every worn node of a pony that is wobbling; `clear(node)` and `reset()` undo it. Every read of
## the game's `FlankTouch` is duck-typed and guarded, so a renamed field, a missing target or a
## malformed value leaves the cloth rigid instead of raising an error. No dictionary is allocated
## per frame.
##
## See `docs/integrations.md` (`## Pantyhose & Panties`).

## The stock `flank_jiggle.gdshaderinc` spread, in the target mesh's local units.
const DEFAULT_RADIUS_M := 0.12
## Below this a basis carries no usable scale.
const MIN_SCALE := 0.000001

var _pony_id := 0
var _live := false
## The coat's live field, in its target mesh's local space.
var _amount := 0.0
var _time := 0.0
var _center := Vector3.ZERO
var _normal := Vector3.BACK
var _radius := DEFAULT_RADIUS_M
## The target mesh's global transform: the space the field above is written in.
var _target := Transform3D.IDENTITY
## World metres per target-mesh unit.
var _target_scale := 1.0


## Drops the pony cached by the previous garment pass.
func begin_frame() -> void:
	_pony_id = 0
	_live = false


## Forgets the cached pony and the sampled wobble. The adapter calls it whenever it restores.
func reset() -> void:
	begin_frame()
	_amount = 0.0
	_time = 0.0
	_center = Vector3.ZERO
	_normal = Vector3.BACK
	_radius = DEFAULT_RADIUS_M
	_target = Transform3D.IDENTITY
	_target_scale = 1.0


## True while `pony`'s coat is wobbling, so `apply()` has something to write.
func sample(pony: Node3D) -> bool:
	if not is_instance_valid(pony):
		_pony_id = 0
		_live = false
		return false
	var id := pony.get_instance_id()
	if id == _pony_id:
		return _live
	_pony_id = id
	_live = _read(pony)
	return _live


## Converts the coat's field into `node`'s own model space, where the shader displaces vertices. The
## centre, the normal and the up axis are mapped through the target mesh's live transform; the
## amplitude and the radius go through the target/garment scale ratio, so a trimmed piece keeps the
## coat's world amplitude and spread.
func apply(node: MeshInstance3D) -> void:
	if not _live or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var inverse := node.global_transform.affine_inverse()
	var basis := _target.basis
	var ratio := _target_scale / _mean_scale(node.global_transform.basis)
	node.set_instance_shader_parameter("garment_jiggle_amount", _amount * ratio)
	node.set_instance_shader_parameter("garment_jiggle_time", _time)
	node.set_instance_shader_parameter("garment_jiggle_center", inverse * (_target * _center))
	node.set_instance_shader_parameter("garment_jiggle_normal",
		_axis(inverse.basis * (basis * _normal), Vector3.BACK))
	node.set_instance_shader_parameter("garment_jiggle_radius", _radius * ratio)
	node.set_instance_shader_parameter("garment_jiggle_up",
		_axis(inverse.basis * (basis * Vector3.UP), Vector3.UP))


## Returns the six uniforms to their defaults. The caller does this while the compatibility
## material is still the override, because the pack's own shader does not know the names.
static func clear(node: MeshInstance3D) -> void:
	if not is_instance_valid(node):
		return
	node.set_instance_shader_parameter("garment_jiggle_amount", 0.0)
	node.set_instance_shader_parameter("garment_jiggle_time", 0.0)
	node.set_instance_shader_parameter("garment_jiggle_center", Vector3.ZERO)
	node.set_instance_shader_parameter("garment_jiggle_normal", Vector3.BACK)
	node.set_instance_shader_parameter("garment_jiggle_radius", DEFAULT_RADIUS_M)
	node.set_instance_shader_parameter("garment_jiggle_up", Vector3.UP)


## The pair the cloth follows: a visible mesh with live values, otherwise the game body, otherwise
## the first pair with live values. Everything `FlankTouch._end_jiggle()` leaves behind (a null
## amount) is not a wobble.
func _read(pony: Node3D) -> bool:
	var flank := pony.get_node_or_null("FlankTouch")
	if flank == null:
		return false
	var rows: Variant = flank.get("_jiggle_targets")
	if not rows is Array or (rows as Array).is_empty():
		return false
	var targets := rows as Array
	var body: Variant = flank.get("_body")
	var first := -1
	var on_body := -1
	for i in targets.size():
		var row: Variant = targets[i]
		var mesh := _live_mesh(row)
		if mesh == null:
			continue
		if first < 0:
			first = i
		if on_body < 0 and is_instance_valid(body) and mesh == body:
			on_body = i
		if mesh.is_visible_in_tree():
			return _store(row)
	if on_body >= 0:
		return _store(targets[on_body])
	if first >= 0:
		return _store(targets[first])
	return false


## The mesh of a `[ShaderMaterial, MeshInstance3D]` pair that carries a live field, or null when the
## row is malformed, out of the tree, or its material holds no wobble.
static func _live_mesh(row: Variant) -> MeshInstance3D:
	if not row is Array or (row as Array).size() < 2:
		return null
	var pair := row as Array
	var material_value: Variant = pair[0]
	var mesh_value: Variant = pair[1]
	if not material_value is ShaderMaterial or not mesh_value is MeshInstance3D:
		return null
	var mesh := mesh_value as MeshInstance3D
	if not is_instance_valid(mesh) or not mesh.is_inside_tree():
		return null
	if not _live_values(material_value as ShaderMaterial):
		return null
	return mesh


## True while the material holds the amount, age, centre and normal the shader needs.
static func _live_values(material: ShaderMaterial) -> bool:
	var amount := _number(material.get_shader_parameter("jiggle_amount"))
	if is_nan(amount) or amount <= 0.0:
		return false
	if is_nan(_number(material.get_shader_parameter("jiggle_time"))):
		return false
	var center: Variant = material.get_shader_parameter("jiggle_center")
	var normal: Variant = material.get_shader_parameter("jiggle_normal")
	if not center is Vector3 or not normal is Vector3:
		return false
	if not (center as Vector3).is_finite() or not (normal as Vector3).is_finite():
		return false
	return (normal as Vector3).length_squared() > 0.5


## Copies the chosen pair's material values into the cache. The radius is the act's own when the
## reactions widened it, the stock spread otherwise; a material that lost its field between the
## checks is not a wobble.
func _store(row: Variant) -> bool:
	var pair := row as Array
	var material_value: Variant = pair[0]
	var mesh_value: Variant = pair[1]
	if not material_value is ShaderMaterial or not mesh_value is MeshInstance3D:
		return false
	var material := material_value as ShaderMaterial
	var mesh := mesh_value as MeshInstance3D
	var amount := _number(material.get_shader_parameter("jiggle_amount"))
	var time := _number(material.get_shader_parameter("jiggle_time"))
	var center: Variant = material.get_shader_parameter("jiggle_center")
	var normal: Variant = material.get_shader_parameter("jiggle_normal")
	if is_nan(amount) or amount <= 0.0 or is_nan(time) \
			or not center is Vector3 or not normal is Vector3:
		return false
	var radius := _number(material.get_shader_parameter("jiggle_radius"))
	_amount = amount
	_time = maxf(time, 0.0)
	_center = center as Vector3
	_normal = (normal as Vector3).normalized()
	_radius = radius if not is_nan(radius) and radius > 0.0 else DEFAULT_RADIUS_M
	_target = mesh.global_transform
	_target_scale = _mean_scale(_target.basis)
	return true


## A numeric game field as a float, or a quiet NaN when it is missing or renamed.
static func _number(value: Variant) -> float:
	if value is float:
		return value as float
	if value is int:
		return float(value)
	return NAN


## A mapped direction, or `fallback` when the mapping collapsed.
static func _axis(value: Vector3, fallback: Vector3) -> Vector3:
	if not value.is_finite() or value.length_squared() < 0.5:
		return fallback
	return value.normalized()


## World metres per model unit: the mean of the basis' three global axis lengths.
static func _mean_scale(basis: Basis) -> float:
	var mean := (basis.x.length() + basis.y.length() + basis.z.length()) / 3.0
	return mean if mean > MIN_SCALE else 1.0
