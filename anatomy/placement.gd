extends RefCounted
## The per-mare anatomy placement: the saved offset/pitch/scale, the calibrated lift, the
## missionary trims and the debug nudge/save/reset path. It owns only placement state; the
## controller supplies the mesh, its bone bind and the act depth/frame.
##
## See `docs/anatomy.md` (`## Placement`).

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const IDENTITY := preload("res://mods/unfplap/anatomy/identity.gd")

const WINKING_REAR_Y := 0.541
const WINKING_REAR_Z := 0.2961
const LIFT := 0.03

var pony: Node3D
var mesh: MeshInstance3D
var bone_inverse := Transform3D.IDENTITY
var body: Array = []

var _pos := Vector3.ZERO
var _pitch := 0.0
var _scale := 1.0
var _place_dirty := false
var _place_revision := -1


func setup(pony_node: Node3D) -> void:
	pony = pony_node


func set_mesh(mesh_node: MeshInstance3D, bind: Transform3D, body_profile: Array) -> void:
	mesh = mesh_node
	bone_inverse = bind
	body = body_profile


func clear_mesh() -> void:
	mesh = null
	bone_inverse = Transform3D.IDENTITY
	body = []


func load() -> void:
	var saved := SETTINGS.anatomy_placement(_pony_id())
	_apply_values(saved)
	_place_revision = SETTINGS.placement_revision
	_place_dirty = false


func apply(missionary: bool, depth: float, bed_frame: Variant) -> void:
	if not is_instance_valid(mesh):
		return
	var local := bone_inverse * base_place()
	if missionary:
		local = _missionary_trim(local, depth, bed_frame)
	mesh.transform = local


## The untrimmed anatomy placement in skeleton rest space. The coat follow samples and rotates
## this placement; the missionary trim is applied after it on the mesh transform.
func base_place() -> Transform3D:
	var basis := Basis.from_euler(Vector3(deg_to_rad(_pitch), 0.0, 0.0)) \
		.scaled(Vector3.ONE * _scale)
	# Placement never follows the dock. `show_dock` is a visibility switch.
	var place := _pos + Vector3(0.0, LIFT, minf(LIFT, 0.0) * 0.2)
	if not body.is_empty():
		var size: float = body[2]
		place = Vector3(place.x * size, body[0] + (place.y - WINKING_REAR_Y) * size,
			body[1] + (place.z - WINKING_REAR_Z) * size)
		basis = basis.scaled(Vector3.ONE * size)
	# Push the whole mesh out along its own normal. A pose that tucks the anatomy into the coat
	# then shows the vulva instead of clipping it.
	var out: float = SETTINGS.vulva_out_mm.get_num() / 1000.0
	if absf(out) > 0.00001:
		place += basis.z.normalized() * out
	return Transform3D(basis, place)


## The untrimmed placement in the anatomy mesh's parent (bone) space, for sampling the body
## coat's skin weights.
func base_transform() -> Transform3D:
	return bone_inverse * base_place()


## The depth trim follows the thrust every frame; the rest of the placement polls.
func tick(missionary: bool, depth: float, bed_frame: Variant) -> void:
	if not missionary:
		return
	if absf(SETTINGS.vulva_depth_shift_mm_for(SETTINGS.pony_size_name())) < 0.0001:
		return
	apply(missionary, depth, bed_frame)


## Move only the anatomy mesh for the lying pose: a world-vertical shift plus a pitch about the
## bed's lateral axis, both around the mesh origin.
func _missionary_trim(local: Transform3D, depth: float, bed_frame: Variant) -> Transform3D:
	var size := SETTINGS.pony_size_name()
	var shift: float = SETTINGS.vulva_shift_mm_for(size) / 1000.0
	shift += SETTINGS.vulva_depth_shift_mm_for(size) / 1000.0 \
		* clampf((depth - 0.2) / 0.8, 0.0, 1.0)
	var pitch: float = deg_to_rad(SETTINGS.vulva_pitch_deg_for(size))
	if absf(shift) < 0.00001 and absf(pitch) < 0.00001:
		return local
	var parent := mesh.get_parent() as Node3D
	if not is_instance_valid(parent) or not mesh.is_inside_tree():
		return Transform3D(Basis(Vector3.RIGHT, pitch) * local.basis,
			local.origin + Vector3.UP * shift)
	var world := parent.global_transform * local
	var axis := Vector3.RIGHT
	if bed_frame is Transform3D:
		var lateral: Vector3 = (bed_frame as Transform3D).basis.x
		lateral.y = 0.0
		if lateral.length_squared() > 0.0001:
			axis = lateral.normalized()
	var pivot := world.origin
	world.basis = Basis(axis, pitch) * world.basis
	world.origin = pivot + Vector3.UP * shift
	return parent.global_transform.affine_inverse() * world


func dirty() -> bool:
	return _place_dirty


func revision() -> int:
	return _place_revision


func values() -> Dictionary:
	return {
		"offset_x": _pos.x, "offset_y": _pos.y, "offset_z": _pos.z,
		"pitch_deg": _pitch, "scale": _scale,
	}


func nudge(axis: String, amount: float) -> void:
	match axis:
		"y":
			_pos.y += amount
		"z":
			_pos.z += amount
		"x":
			_pos.x += amount
		"pitch":
			_pitch += amount
		"scale":
			_scale = maxf(0.05, _scale + amount)
	_place_dirty = true


func place_text() -> String:
	var id := _pony_id()
	var source := "override" if SETTINGS.anatomy_placement_has_override(id) else "default"
	if _place_dirty:
		source += "/unsaved"
	return "position=(%.3f,%.3f,%.3f) pitch=%.1f scale=%.3f source=%s" % [
		_pos.x, _pos.y, _pos.z, _pitch, _scale, source]


func save() -> void:
	var id := _pony_id()
	if id.is_empty():
		return
	SETTINGS.save_anatomy_placement(id, values())
	_place_dirty = false
	_place_revision = SETTINGS.placement_revision


func reset() -> void:
	_apply_values(SETTINGS.anatomy_placement_default(_pony_id(), false))
	_place_dirty = true
	_place_revision = SETTINGS.placement_revision


func _apply_values(placement: Dictionary) -> void:
	_pos = Vector3(float(placement.get("offset_x", 0.0)), float(placement.get("offset_y", 0.0)),
		float(placement.get("offset_z", 0.0)))
	_pitch = float(placement.get("pitch_deg", 0.0))
	_scale = maxf(0.05, float(placement.get("scale", 1.0)))


func _pony_id() -> String:
	return IDENTITY.id_for(str(pony.get_meta("relationship_id", "")),
		pony.get("identity")) if is_instance_valid(pony) else ""
