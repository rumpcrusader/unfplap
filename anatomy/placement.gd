extends RefCounted
## One mare's anatomy placement: the saved transform, the calibrated lift and the pose trims.
## It owns placement state only; the controller supplies the mesh, the bone bind and the depth.
## See `docs/anatomy.md` (`## Placement`).

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const IDENTITY := preload("res://mods/unfplap/anatomy/identity.gd")
const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")

const WINKING_REAR_Y := BODY_PROFILE.WINKING_REAR_Y
const WINKING_REAR_Z := BODY_PROFILE.WINKING_REAR_Z
const LIFT := 0.03

var pony: Node3D
var mesh: MeshInstance3D
var bone_inverse := Transform3D.IDENTITY
## The presented body's typed rig: the scale and rear anchor a princess (or source) body measures
## from. The ordinary rig maps exactly to the pre-form array's empty profile.
var rig: BODY_PROFILE.RigProfile = null

var _pos: Vector3
var _pitch: float
var _scale: float
var _place_revision := -1
## The placement trims, read on setup/live and never on the per-frame trim.
var _vulva_shift_mm := 0.0
var _depth_shift_mm := 0.0
var _vulva_pitch_deg := 0.0


func setup(pony_node: Node3D) -> void:
	pony = pony_node
	read_settings()


## Read the vulva trims once. A live edit applies on the next settings refresh, not mid-frame.
func read_settings() -> void:
	var size := SETTINGS.pony_size_name()
	_vulva_shift_mm = SETTINGS.vulva_shift_mm_for(size)
	_depth_shift_mm = SETTINGS.vulva_depth_shift_mm_for(size)
	_vulva_pitch_deg = SETTINGS.vulva_pitch_deg_for(size)


func set_mesh(mesh_node: MeshInstance3D, bind: Transform3D,
		rig_profile: BODY_PROFILE.RigProfile) -> void:
	mesh = mesh_node
	bone_inverse = bind
	rig = rig_profile


func clear_mesh() -> void:
	mesh = null
	bone_inverse = Transform3D.IDENTITY
	rig = null


## Read the resolved row. `fit_id` is the presented form's fit; empty falls back to the legacy
## body-fit mirror.
func load(fit_id: String = "") -> void:
	read_settings()
	var fit := fit_id if not fit_id.is_empty() else _body_fit_id()
	var saved := SETTINGS.anatomy_placement(_pony_id(), fit)
	_apply_values(Vector3(saved.num("offset_x"), saved.num("offset_y"),
		saved.num("offset_z")), saved.num("pitch_deg"), saved.num("scale"))
	_place_revision = SETTINGS.placement_revision


func apply(missionary: bool, depth: float, bed_frame: Variant) -> void:
	if not is_instance_valid(mesh):
		return
	var local := bone_inverse * base_place()
	if missionary:
		local = _missionary_trim(local, depth, bed_frame)
	mesh.transform = local


## The untrimmed anatomy placement in skeleton rest space. The coat line samples this placement;
## the missionary trim is applied after it on the mesh transform.
func base_place() -> Transform3D:
	var basis := Basis.from_euler(Vector3(deg_to_rad(_pitch), 0.0, 0.0)) \
		.scaled(Vector3.ONE * _scale)
	# Placement never follows the dock. `Dock style` is a visibility/colour switch.
	var place := _pos + Vector3(0.0, LIFT, minf(LIFT, 0.0) * 0.2)
	if rig != null:
		var size := rig.scale
		place = Vector3(place.x * size, rig.rear_y + (place.y - WINKING_REAR_Y) * size,
			rig.rear_z + (place.z - WINKING_REAR_Z) * size)
		basis = basis.scaled(Vector3.ONE * size)
	return Transform3D(basis, place)


## The depth trim follows the thrust every frame; the rest of the placement polls.
func tick(missionary: bool, depth: float, bed_frame: Variant) -> void:
	if not missionary:
		return
	if absf(_depth_shift_mm) < 0.0001:
		return
	apply(missionary, depth, bed_frame)


## Move only the anatomy mesh for the lying pose: a world-vertical shift plus a pitch about the
## bed's lateral axis, both around the mesh origin.
func _missionary_trim(local: Transform3D, depth: float, bed_frame: Variant) -> Transform3D:
	var shift := _vulva_shift_mm / 1000.0
	shift += _depth_shift_mm / 1000.0 * clampf((depth - 0.2) / 0.8, 0.0, 1.0)
	var pitch := deg_to_rad(_vulva_pitch_deg)
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


func revision() -> int:
	return _place_revision


func _apply_values(pos: Vector3, pitch: float, scale: float) -> void:
	_pos = pos
	_pitch = pitch
	_scale = maxf(0.05, scale)


func _pony_id() -> String:
	return PONY_ID.of(pony)


func _body_fit_id() -> String:
	return IDENTITY.body_fit_id(pony)
