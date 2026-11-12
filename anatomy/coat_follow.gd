extends RefCounted
## Per-pony coat follow: the anatomy follows the body coat's leg skinning so the seam stays on the
## rump when the hind legs move. The act's hole point and normal use the same matrices, so the
## visible vulva and anus, the shaft and the fluid stay together.
##
## The weights are sampled once from the body mesh's own skin, stored in the anatomy mesh's
## custom0 RGBA8 channel, and blended in `anatomy.gdshader` by four pelvis-relative bone
## matrices. See `docs/anatomy.md` (`## Coat follow`).

const SETTINGS := preload("res://mods/unfplap/settings.gd")
const GEOMETRY := preload("res://mods/unfplap/anatomy/geometry.gd")

const BODY_NAME := "MareBody"
const HIPS_BONE := "pony_hips"
## The shader's four matrices, in the custom0 weight order.
const UNIFORMS := ["coat_follow_l", "coat_follow_r", "coat_follow_femur_l",
	"coat_follow_femur_r"]
## The two local openings. The act's hole point and normal use the same sampled weights as the
## shader, so the shaft and the fluid keep tracking the visible opening.
const WINKING_OPENING := Vector3(0.0, -0.012, 0.02)
const ANAL_OPENING := Vector3(0.0, 0.071, 0.019)

var pony: Node3D
var placement: RefCounted
var mesh: MeshInstance3D
var skeleton: Skeleton3D
var material: ShaderMaterial

var last_error := ""

## Body mesh/skin id -> rest vertices, leg-weight names, hips bind and the vertex grid. The body
## resources are shared by every standard mare, so the 7,625-vertex grid is built once.
static var _body_cache: Dictionary = {}

var _body_hips_bind := Transform3D.IDENTITY
var _body_vertices := PackedVector3Array()
var _body_bones := PackedInt32Array()
var _body_weights := PackedFloat32Array()
var _body_names := PackedStringArray()
var _weights := PackedByteArray()
var _grid: Dictionary = {}
var _grid_cell := GEOMETRY.COAT_FOLLOW_CELL_M

var _hips_index := -1
var _hips_rest := Transform3D.IDENTITY
var _leg_indices: Array[int] = [-1, -1, -1, -1]
var _leg_rests: Array[Transform3D] = []
var _built_place := Transform3D.IDENTITY
var _built_mesh_id := 0
var _built := false
## A body without a usable coat is a stable condition; do not scan for it every frame.
var _retry_at_msec := 0
## The last four matrices, also used by the act's hole point and normal.
var _matrices: Array[Transform3D] = []
var _vulva_weights := PackedFloat32Array()
var _anal_weights := PackedFloat32Array()


func setup(pony_node: Node3D, placement_node: RefCounted) -> void:
	pony = pony_node
	placement = placement_node


func set_mesh(mesh_node: MeshInstance3D, skeleton_node: Skeleton3D) -> void:
	mesh = mesh_node
	skeleton = skeleton_node
	_built = false
	_built_mesh_id = 0
	_retry_at_msec = 0


## The material is recreated whenever the anatomy appearance changes; the follow keeps its
## uniforms on the new one. Matrices stay identity until the next tick.
func set_material(material_node: ShaderMaterial) -> void:
	material = material_node
	if not is_instance_valid(material):
		return
	for uniform: String in UNIFORMS:
		material.set_shader_parameter(uniform, Transform3D.IDENTITY)
	material.set_shader_parameter("coat_follow_strength", 0.0)
	_matrices = []


## One debug line for the attach log: how many anatomy vertices got a leg weight.
func summary() -> String:
	if not _built:
		return "not built: %s" % last_error
	var count := _weights.size() / 4
	var weighted := 0
	var sum := 0.0
	for i in count:
		var w := (float(_weights[i * 4]) + float(_weights[i * 4 + 1])
			+ float(_weights[i * 4 + 2]) + float(_weights[i * 4 + 3])) / 255.0
		if w > 0.001:
			weighted += 1
		sum += w
	return "verts=%d weighted=%d mean=%.2f" % [count, weighted,
		sum / maxf(1.0, float(count))]


func clear() -> void:
	if is_instance_valid(material):
		material.set_shader_parameter("coat_follow_strength", 0.0)
	pony = null
	placement = null
	mesh = null
	skeleton = null
	material = null
	_built = false
	_built_mesh_id = 0
	_retry_at_msec = 0
	_weights = PackedByteArray()
	_vulva_weights = PackedFloat32Array()
	_anal_weights = PackedFloat32Array()
	_matrices = []
	_grid = {}
	last_error = ""


## Called every frame by the controller. Builds the weighted mesh lazily and refreshes the four
## matrices from the live skeleton. Outside a body or with the setting at zero the anatomy stays
## rigid.
func tick() -> void:
	var strength := SETTINGS.coat_follow.get_num()
	if strength <= 0.0:
		if is_instance_valid(material):
			material.set_shader_parameter("coat_follow_strength", 0.0)
		return
	if not is_instance_valid(mesh) or not is_instance_valid(skeleton) \
			or not is_instance_valid(placement) or not is_instance_valid(material):
		return
	var base: Variant = placement.base_place()
	if not base is Transform3D:
		return
	if not _built or _built_mesh_id == 0 or not is_instance_valid(mesh.mesh) \
			or mesh.mesh.get_instance_id() != _built_mesh_id \
			or not (base as Transform3D).is_equal_approx(_built_place):
		var now := Time.get_ticks_msec()
		if now < _retry_at_msec:
			material.set_shader_parameter("coat_follow_strength", 0.0)
			return
		if not rebuild():
			_retry_at_msec = now + 2000
			material.set_shader_parameter("coat_follow_strength", 0.0)
			return
	var poses: Array[Transform3D] = []
	for i in _leg_indices.size():
		var bone := _leg_indices[i]
		poses.append(skeleton.get_bone_global_pose(bone) if bone >= 0
			else Transform3D.IDENTITY)
	var matrices := GEOMETRY.coat_follow_matrices(skeleton.get_bone_global_pose(_hips_index),
		_hips_rest, poses, _leg_rests, _built_place)
	_matrices = matrices
	for i in mini(matrices.size(), UNIFORMS.size()):
		material.set_shader_parameter(UNIFORMS[i], matrices[i])
	material.set_shader_parameter("coat_follow_strength", strength)


## Re-find the body mesh, resample the anatomy vertices and replace the mesh with a weighted
## copy. Called on attach, a mesh swap or a placement change; not per frame.
func rebuild() -> bool:
	_built = false
	_built_mesh_id = 0
	_matrices = []
	last_error = ""
	if not is_instance_valid(mesh) or not is_instance_valid(skeleton) \
			or not is_instance_valid(placement):
		last_error = "no anatomy mesh"
		return false
	var source := mesh.mesh as ArrayMesh
	if source == null or source.get_surface_count() != 1:
		last_error = "anatomy mesh is not one surface"
		return false
	if not _read_body():
		return false
	var base_value: Variant = placement.base_place()
	var local_value: Variant = placement.base_transform()
	if not base_value is Transform3D or not local_value is Transform3D:
		last_error = "no anatomy placement"
		return false
	var base := base_value as Transform3D
	var local := local_value as Transform3D
	var hips_index := skeleton.find_bone(HIPS_BONE)
	if hips_index < 0:
		last_error = "no pony_hips bone"
		return false
	var arrays: Array = source.surface_get_arrays(0)
	if arrays.size() != Mesh.ARRAY_MAX or arrays[Mesh.ARRAY_VERTEX] == null:
		last_error = "anatomy mesh has no vertices"
		return false
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var to_body := _body_hips_bind.affine_inverse() * local
	var weights := GEOMETRY.sample_coat_weights(vertices, to_body, _body_vertices,
		_body_bones, _body_weights, _body_names, _grid, _grid_cell)
	if weights.is_empty():
		last_error = "no body coat weights at the anatomy"
		return false
	var weighted := GEOMETRY.mesh_with_coat_weights(source, weights)
	if weighted == null:
		last_error = "anatomy mesh cannot take coat weights"
		return false
	_hips_index = hips_index
	_hips_rest = skeleton.get_bone_global_rest(_hips_index)
	_leg_indices.clear()
	_leg_rests.clear()
	for bone_name: String in GEOMETRY.COAT_FOLLOW_BONES:
		var bone := skeleton.find_bone(bone_name)
		_leg_indices.append(bone)
		_leg_rests.append(skeleton.get_bone_global_rest(bone) if bone >= 0
			else Transform3D.IDENTITY)
	mesh.mesh = weighted
	_weights = weights
	_vulva_weights = _opening_weights_at(vertices, WINKING_OPENING)
	_anal_weights = _opening_weights_at(vertices, ANAL_OPENING)
	_built_mesh_id = weighted.get_instance_id()
	_built_place = base
	_built = true
	_retry_at_msec = 0
	return true


## The four leg weights at one of the two openings, blended by the act's hole mix. The act's
## `hole_point()` and `hole_rear()` use this so the shaft, fluid and idle drips track the visible
## opening instead of the rigid mesh transform.
func opening_weights(mix: float) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	if _vulva_weights.size() < 4:
		return out
	var t := clampf(mix, 0.0, 1.0)
	for i in 4:
		out[i] = lerpf(_vulva_weights[i],
			_anal_weights[i] if _anal_weights.size() >= 4 else 0.0, t)
	return out


func deform_point(local: Vector3, weights: PackedFloat32Array) -> Vector3:
	return GEOMETRY.weighted_point(local, weights, _matrices,
		SETTINGS.coat_follow.get_num())


func deform_direction(local: Vector3, weights: PackedFloat32Array) -> Vector3:
	return GEOMETRY.weighted_direction(local, weights, _matrices,
		SETTINGS.coat_follow.get_num())


## Decode the four custom0 bytes at the nearest anatomy vertex to a local opening.
func _opening_weights_at(vertices: PackedVector3Array, point: Vector3) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var index := GEOMETRY.nearest_vertex_index(vertices, point)
	if index < 0 or _weights.size() < (index + 1) * 4:
		return out
	for i in 4:
		out[i] = float(_weights[index * 4 + i]) / 255.0
	return out


## The body coat's rest vertices and skin bind indices. The body mesh and skin resources are
## shared by every standard mare; the grid is built once and reused by every pony's follow.
func _read_body() -> bool:
	if not is_instance_valid(pony):
		last_error = "no pony"
		return false
	var model: Variant = pony.get("_model")
	if not model is Node:
		last_error = "no pony model"
		return false
	var body := (model as Node).find_child(BODY_NAME, true, false) as MeshInstance3D
	if not is_instance_valid(body) or body.mesh == null or body.skin == null:
		last_error = "no skinned body coat"
		return false
	if body.mesh.get_surface_count() < 1:
		last_error = "body coat has no surface"
		return false
	var key := "%d:%d" % [body.mesh.get_instance_id(), body.skin.get_instance_id()]
	var cached: Variant = _body_cache.get(key)
	if not cached is Dictionary:
		cached = _build_body(body)
		if (cached as Dictionary).is_empty():
			return false
		_body_cache[key] = cached
	var row := cached as Dictionary
	_body_vertices = row.get("vertices", PackedVector3Array())
	_body_bones = row.get("bones", PackedInt32Array())
	_body_weights = row.get("weights", PackedFloat32Array())
	_body_names = row.get("names", PackedStringArray())
	_body_hips_bind = row.get("hips_bind", Transform3D.IDENTITY)
	_grid = row.get("grid", {})
	if _body_vertices.is_empty() or _body_bones.is_empty() or _body_weights.is_empty():
		last_error = "body coat has no skin data"
		return false
	return true


## Build the immutable body-side data once per body mesh and skin.
func _build_body(body: MeshInstance3D) -> Dictionary:
	var arrays: Array = body.mesh.surface_get_arrays(0)
	if arrays.size() != Mesh.ARRAY_MAX or arrays[Mesh.ARRAY_VERTEX] == null \
			or arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
		last_error = "body coat is not skinned"
		return {}
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if vertices.is_empty() or bones.is_empty() or weights.is_empty():
		last_error = "body coat has no skin data"
		return {}
	var skin: Skin = body.skin
	var names := PackedStringArray()
	for i in skin.get_bind_count():
		names.append(String(skin.get_bind_name(i)))
	var hips_bind := -1
	for i in names.size():
		if names[i] == HIPS_BONE:
			hips_bind = i
			break
	if hips_bind < 0:
		last_error = "body coat has no pony_hips bind"
		return {}
	return {
		"vertices": vertices,
		"bones": bones,
		"weights": weights,
		"names": names,
		"hips_bind": skin.get_bind_pose(hips_bind),
		"grid": GEOMETRY.body_weight_grid(vertices, _grid_cell),
	}
