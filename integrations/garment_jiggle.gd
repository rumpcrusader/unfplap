extends RefCounted

const DEFAULT_RADIUS_M := 0.12
const MARK_LIFT_M := 0.015
const MIN_SCALE := 0.000001

var _pony_id := 0
var _live := false
var _amount := 0.0
var _time := 0.0
var _center := Vector3.ZERO
var _normal := Vector3.BACK
var _radius := DEFAULT_RADIUS_M


func begin_frame() -> void:
	_pony_id = 0
	_live = false


func reset() -> void:
	begin_frame()
	_amount = 0.0
	_time = 0.0
	_center = Vector3.ZERO
	_normal = Vector3.BACK
	_radius = DEFAULT_RADIUS_M


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


func apply(node: MeshInstance3D) -> void:
	if not _live or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var inverse := node.global_transform.affine_inverse()
	var center_local := inverse * _center
	var normal_local := (inverse.basis * _normal).normalized()
	if not normal_local.is_finite() or normal_local.length_squared() < 0.5:
		normal_local = Vector3.BACK
	var scale := _local_scale(node)
	node.set_instance_shader_parameter("garment_jiggle_amount", _amount / scale)
	node.set_instance_shader_parameter("garment_jiggle_time", _time)
	node.set_instance_shader_parameter("garment_jiggle_center", center_local)
	node.set_instance_shader_parameter("garment_jiggle_normal", normal_local)
	node.set_instance_shader_parameter("garment_jiggle_radius", _radius / scale)


static func clear(node: MeshInstance3D) -> void:
	if not is_instance_valid(node):
		return
	node.set_instance_shader_parameter("garment_jiggle_amount", 0.0)
	node.set_instance_shader_parameter("garment_jiggle_time", 0.0)
	node.set_instance_shader_parameter("garment_jiggle_center", Vector3.ZERO)
	node.set_instance_shader_parameter("garment_jiggle_normal", Vector3.BACK)
	node.set_instance_shader_parameter("garment_jiggle_radius", DEFAULT_RADIUS_M)


func _read(pony: Node3D) -> bool:
	var flank := pony.get_node_or_null("FlankTouch")
	if flank == null:
		return false
	var index_value: Variant = flank.get("_jiggle_index")
	if not index_value is int:
		return false
	var index := int(index_value)
	var marks: Variant = flank.get("marks")
	if not marks is Array:
		return false
	var rows := marks as Array
	if index < 0 or index >= rows.size():
		return false
	var mark_value: Variant = rows[index]
	if not mark_value is Decal:
		return false
	var mark := mark_value as Decal
	if not mark.is_inside_tree():
		return false
	var amount := _number(flank.get("_jiggle_amount"))
	if is_nan(amount) or amount <= 0.0:
		return false
	var age := _number(flank.get("_jiggle_age"))
	if is_nan(age):
		return false
	var at := mark.global_position
	var outward := mark.global_basis.y.normalized()
	if not at.is_finite() or not outward.is_finite() or outward.length_squared() < 0.5:
		return false
	_amount = amount
	_time = maxf(age, 0.0)
	_center = at - outward * MARK_LIFT_M
	_normal = outward
	_radius = _live_radius(flank)
	return true


static func _live_radius(flank: Node) -> float:
	var targets: Variant = flank.get("_jiggle_targets")
	if not targets is Array:
		return DEFAULT_RADIUS_M
	for row: Variant in targets as Array:
		if not row is Array or (row as Array).is_empty():
			continue
		var material_value: Variant = (row as Array)[0]
		if not material_value is ShaderMaterial:
			continue
		var value: Variant = (material_value as ShaderMaterial).get_shader_parameter("jiggle_radius")
		if value is float and (value as float) > 0.0:
			return value as float
	return DEFAULT_RADIUS_M


static func _number(value: Variant) -> float:
	if value is float:
		return value as float
	if value is int:
		return float(value)
	return NAN


static func _local_scale(node: Node3D) -> float:
	var basis := node.global_transform.basis
	var mean := (basis.x.length() + basis.y.length() + basis.z.length()) / 3.0
	return mean if mean > MIN_SCALE else 1.0
