extends Node
## integration: ported from PonyPussyParadise anon_part.gd. Shows the part on the human player's
## Hips during encounters. The mesh and textures are local-only (see assets/anatomy/README.md).

const PLAYER_FORM := preload("res://world/life/player_form.gd")
const OUTLINE_EXCLUSION := preload("res://world/post_outline_exclusion.gd")
const TUNABLES := preload("res://mods/unfplap/tunables.gd")
const HIPS_REST := Vector3(0.0, 0.978635, 0.013361)
const PLACE_PATH := "user://mods/data/unfplap/anon_place.json"
const SKIN := Color(0.76, 0.58, 0.52)
const SKIN_SHADE := Color(0.62, 0.45, 0.41)
const TIP := Color(0.82, 0.60, 0.58)
const TIP_SHADE := Color(0.68, 0.46, 0.45)

const PIVOT := Vector3(0.0, 0.8226, 0.122)
const TIP_POINT := Vector3(0.0, 0.974, 0.76)
const PART_LENGTH := 0.655
const WIDTHS := [0.156, 0.133, 0.127, 0.14, 0.15, 0.151, 0.157, 0.159, 0.149, 0.13, 0.104, 0.091, 0.056]
const ENTRY_LEAD_M := 0.03
const BEND_MAX := 0.6
const BEND_STIFFNESS := 170.0
const BEND_DAMPING := 13.0
const BEND_INERTIA := 0.55
const BEND_BOB := 0.5
const BEND_SAG := 0.1
const SQUASH_STIFFNESS := 210.0
const SQUASH_DAMPING := 15.0
const SQUASH_INERTIA := 0.006
const SQUASH_MAX := 0.1
const ACCELERATION_MAX := 60.0
const BEND_NEAR := 0.45
const BEND_FAR := 0.75
const AIM_DEPTH := 0.3
const FULL_DEPTH := 1.0

const MESH_PATH := "res://mods/unfplap/assets/anatomy/anon_part.scn"
const ALBEDO_PATH := "res://mods/unfplap/assets/anatomy/anon_part_albedo.png"
const AO_PATH := "res://mods/unfplap/assets/anatomy/anon_part_ao.png"
const NRM_PATH := "res://mods/unfplap/assets/anatomy/anon_part_nrm.png"

var main: Node
var placing := false

var _mesh: MeshInstance3D
var _skeleton: Skeleton3D
var _bone_inverse := Transform3D.IDENTITY
var _pos := Vector3(0.0, 0.74, 0.085)
var _pitch := 0.0
var _scale := 0.2
var _setting_scale := 1.0
var _setting_pitch := 0.0
var _setting_yaw := 0.0
var _setting_roll := 0.0
var _ready_amount := 0.0
var _tween: Tween
var _in_encounter := false
var _legs_swapped := false
var _trousers_was_visible := true
var _legs_was_visible := false
var _bend := Vector3.ZERO
var _bend_speed := Vector3.ZERO
var _squash := 0.0
var _squash_speed := 0.0
var _last_root := Vector3.INF
var _last_velocity := Vector3.ZERO
var _bed_holder: Node3D
var _home: Node


static func assets_exist() -> bool:
	return ResourceLoader.exists(MESH_PATH)


func available() -> bool:
	return assets_exist()


func _ensure() -> bool:
	var form: Variant = PLAYER_FORM.active(get_tree())
	if PLAYER_FORM.is_young(form) or PLAYER_FORM.is_pony(form):
		return false
	if is_instance_valid(_mesh):
		return true
	if not assets_exist():
		return false
	# integration: the VR rig holds the same Anon body deeper down.
	var anon: Variant = (main.get("player") as Node).find_child("AnonBody", true, false)
	var body: Node3D = anon if anon is Node3D else main.call("player_body")
	if not is_instance_valid(body):
		return false
	var skeletons: Array = body.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return false
	_skeleton = skeletons[0]
	var bone := _skeleton.find_bone("Hips")
	if bone < 0:
		return false
	var scene: PackedScene = load(MESH_PATH)
	if scene == null:
		return false
	var instance: Node = scene.instantiate()
	var meshes: Array = instance.find_children("*", "MeshInstance3D", true, false)
	if instance is MeshInstance3D:
		meshes = [instance]
	if meshes.is_empty():
		instance.queue_free()
		return false
	_mesh = meshes[0]
	_mesh.owner = null
	if _mesh.get_parent() != null:
		_mesh.get_parent().remove_child(_mesh)
	if instance != _mesh:
		instance.queue_free()
	_mesh.name = "UnfplapAnonPart"
	var anchor := BoneAttachment3D.new()
	anchor.name = "UnfplapAnonAnchor"
	anchor.bone_name = "Hips"
	_skeleton.add_child(anchor)
	anchor.add_child(_mesh)
	_bone_inverse = _skeleton.get_bone_global_rest(bone).affine_inverse()
	_read_settings()
	_load_place()
	_apply_place()
	_apply_material()
	_apply_ready()
	_mesh.visible = false
	return true


func _apply_material() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://mods/unfplap/anon_part.gdshader")
	mat.set_shader_parameter("color", SKIN)
	mat.set_shader_parameter("shadow_color", SKIN_SHADE)
	mat.set_shader_parameter("tip_color", TIP)
	mat.set_shader_parameter("tip_shadow", TIP_SHADE)
	mat.set_shader_parameter("shaft_root", PIVOT)
	mat.set_shader_parameter("shaft_axis", (TIP_POINT - PIVOT).normalized())
	mat.set_shader_parameter("shaft_length", PART_LENGTH)
	mat.set_shader_parameter("base_texture", load(ALBEDO_PATH))
	mat.set_shader_parameter("ao_texture", load(AO_PATH))
	mat.set_shader_parameter("normal_texture", load(NRM_PATH))
	_mesh.set_surface_override_material(0, mat)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	OUTLINE_EXCLUSION.apply_to(_mesh)


func _apply_ready() -> void:
	var shape := _mesh.find_blend_shape_by_name("ready")
	if shape >= 0:
		_mesh.set_blend_shape_value(shape, _ready_amount)


func _read_settings() -> void:
	_setting_scale = TUNABLES.get_float("anatomy.player_scale")
	_setting_pitch = TUNABLES.get_float("anatomy.player_pitch_deg")
	_setting_yaw = TUNABLES.get_float("anatomy.player_yaw_deg")
	_setting_roll = TUNABLES.get_float("anatomy.player_roll_deg")


## integration: the user-facing scale and rotation sit on top of the saved placement.
func _rotation_basis() -> Basis:
	return Basis.from_euler(Vector3(
		deg_to_rad(_pitch + _setting_pitch),
		deg_to_rad(_setting_yaw),
		deg_to_rad(_setting_roll)))


func _placed() -> Transform3D:
	var basis := _rotation_basis().scaled(Vector3.ONE * _scale * _setting_scale)
	return _bone_inverse * Transform3D(basis, _pos)


func _apply_place() -> void:
	_mesh.transform = _placed()


## integration: live user-facing size/rotation update.
func apply_live() -> void:
	_read_settings()
	if is_instance_valid(_mesh):
		_apply_place()


## integration: standing: the part stays fixed to his hips. Bed: it rides her hips instead.
func track(target: Vector3, rear: Vector3, up: Vector3, bed: bool, depth: float, delta: float,
		mare_anchor: Node3D) -> void:
	if not is_instance_valid(_mesh) or not _mesh.visible or placing:
		return
	if bed:
		_track_bed(target, rear, up, depth, mare_anchor)
		return
	_end_bed()
	if delta <= 0.0:
		return
	var root := root_now()
	var velocity := Vector3.ZERO if _last_root == Vector3.INF else (root - _last_root) / delta
	var acceleration := ((velocity - _last_velocity) / delta).limit_length(ACCELERATION_MAX)
	_last_root = root
	_last_velocity = velocity
	var to_mesh := _mesh.global_basis.inverse().orthonormalized()
	var axis := (TIP_POINT - PIVOT).normalized()
	var reach := PART_LENGTH * _world_scale()
	var aim := (to_mesh * (target - rear * reach * AIM_DEPTH - root)).normalized()
	var near := 1.0 - smoothstep(BEND_NEAR, BEND_FAR, root.distance_to(target))
	var wanted := axis.cross(aim).normalized() * minf(axis.angle_to(aim) * 2.0, BEND_MAX) * near
	wanted += Vector3.RIGHT * BEND_SAG * (1.0 - near)
	var along := (to_mesh * acceleration).dot(axis)
	var pull := axis.cross(to_mesh * -acceleration) * BEND_INERTIA + Vector3.RIGHT * along * BEND_BOB
	_bend_speed += (pull + (wanted - _bend) * BEND_STIFFNESS - _bend_speed * BEND_DAMPING) * delta
	_bend = (_bend + _bend_speed * delta).limit_length(BEND_MAX)
	_squash_speed += (along * SQUASH_INERTIA * SQUASH_STIFFNESS - _squash * SQUASH_STIFFNESS
		- _squash_speed * SQUASH_DAMPING) * delta
	_squash = clampf(_squash + _squash_speed * delta, -SQUASH_MAX, SQUASH_MAX)
	_set_bend(_bend)
	var material := _mesh.get_surface_override_material(0) as ShaderMaterial
	if material != null:
		var at := root.distance_to(target) / _world_scale()
		material.set_shader_parameter("squish_at", at)
		material.set_shader_parameter("squish", near
			* clampf((PART_LENGTH - at) / (PART_LENGTH * 0.12), 0.0, 1.0))
		material.set_shader_parameter("compress", _squash)


func _set_bend(turn: Vector3) -> void:
	var material := _mesh.get_surface_override_material(0) as ShaderMaterial
	if material != null:
		material.set_shader_parameter("bend_turn", turn)


func _track_bed(target: Vector3, rear: Vector3, up: Vector3, depth: float,
		mare_anchor: Node3D) -> void:
	if not is_instance_valid(_bed_holder):
		_bed_holder = Node3D.new()
		_bed_holder.name = "UnfplapAnonBedHolder"
		mare_anchor.add_child(_bed_holder)
		_home = _mesh.get_parent()
		_mesh.reparent(_bed_holder, false)
		_set_bend(Vector3.ZERO)
		var straight := (_rotation_basis() * _straighten()).scaled(
			Vector3.ONE * _scale * _setting_scale)
		_mesh.transform = Transform3D(straight, -(straight * PIVOT))
	var reach := PART_LENGTH * _scale * _setting_scale \
		* (1.0 - clampf(depth, 0.0, 1.0) * FULL_DEPTH)
	_bed_holder.global_transform = Transform3D(Basis.looking_at(rear, up), target + rear * reach)


func _end_bed() -> void:
	if not is_instance_valid(_bed_holder):
		return
	if is_instance_valid(_mesh) and is_instance_valid(_home):
		_mesh.reparent(_home, false)
		_apply_place()
	_bed_holder.queue_free()
	_bed_holder = null


## integration: how far the tip has passed her opening, 0 to 1 of its length.
func entry(opening: Vector3, rear: Vector3) -> float:
	if not is_instance_valid(_mesh) or not _mesh.visible:
		return -1.0
	var length := PART_LENGTH * _mesh.global_transform.basis.get_scale().x
	return clampf((length - (_mesh.global_transform * PIVOT).distance_to(opening)
		+ ENTRY_LEAD_M) / length, 0.0, 1.0)


## integration: world radius of the shaft where it passes through `opening`.
func girth_at(opening: Vector3) -> float:
	if not is_instance_valid(_mesh) or not _mesh.visible:
		return -1.0
	var along := root_now().distance_to(opening) / (PART_LENGTH * _world_scale())
	if along >= 1.0:
		return 0.0
	var at := clampf(along, 0.0, 1.0) * (WIDTHS.size() - 1)
	var below := floori(at)
	return lerpf(WIDTHS[below], WIDTHS[mini(below + 1, WIDTHS.size() - 1)], at - below) \
		* _world_scale()


func _straighten() -> Basis:
	return Basis(Quaternion((TIP_POINT - PIVOT).normalized(), Vector3.BACK))


func showing() -> bool:
	return is_instance_valid(_mesh) and _mesh.visible and not placing


func tip_world() -> Vector3:
	return _mesh.global_transform * TIP_POINT


func depth_for(metres: float) -> float:
	return metres / (PART_LENGTH * _world_scale())


func root_now() -> Vector3:
	return _mesh.global_transform * PIVOT


func root_for(target: Vector3, rear: Vector3, depth: float) -> Vector3:
	return target + rear * PART_LENGTH * _world_scale() \
		* (1.0 - clampf(depth, 0.0, 1.0) * FULL_DEPTH)


func spine_length() -> float:
	if not is_instance_valid(_skeleton):
		return 0.65
	var hips := _skeleton.get_bone_global_rest(_skeleton.find_bone("Hips")).origin
	var head := _skeleton.get_bone_global_rest(_skeleton.find_bone("Head")).origin
	return hips.distance_to(head) * _skeleton.global_basis.get_scale().x


func axis() -> Vector3:
	return _rotation_basis() * (TIP_POINT - PIVOT).normalized()


func hip_for(root: Vector3, hips: Basis) -> Vector3:
	var local_root := _pos + _rotation_basis() * (PIVOT * _scale * _setting_scale)
	return root - hips * ((local_root - HIPS_REST) * _skeleton.global_basis.get_scale().x)


func _world_scale() -> float:
	return _mesh.global_transform.basis.get_scale().x


func _set_ready(value: float) -> void:
	_ready_amount = value
	if is_instance_valid(_mesh):
		_apply_ready()


func _animate(target: float, seconds: float, hide_after := false) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_set_ready, _ready_amount, target, seconds)
	if hide_after:
		_tween.tween_callback(_hide)


## integration: current garments create Trousers and BodyLegs at runtime. Save their visibility
## and restore it instead of assuming either node always exists.
func _swap_legs(bare: bool) -> void:
	if bare == _legs_swapped:
		return
	var trousers := _skeleton.get_node_or_null("Trousers") as Node3D
	var legs := _skeleton.get_node_or_null("BodyLegs") as Node3D
	if bare:
		if trousers != null:
			_trousers_was_visible = trousers.visible
		if legs != null:
			_legs_was_visible = legs.visible
		if trousers != null:
			trousers.visible = false
		if legs != null:
			legs.visible = true
		_legs_swapped = true
	elif _legs_swapped:
		if trousers != null:
			trousers.visible = _trousers_was_visible
		if legs != null:
			legs.visible = _legs_was_visible
		_legs_swapped = false


func _hide() -> void:
	if is_instance_valid(_mesh):
		_mesh.visible = false
	_swap_legs(false)


func encounter(on: bool) -> void:
	_in_encounter = on
	if on:
		if not _ensure():
			return
		_mesh.visible = true
		_swap_legs(true)
		_animate(1.0, 1.4)
	elif is_instance_valid(_mesh):
		_end_bed()
		_bend = Vector3.ZERO
		_bend_speed = Vector3.ZERO
		_squash = 0.0
		_squash_speed = 0.0
		_last_root = Vector3.INF
		_set_bend(Vector3.ZERO)
		_apply_place()
		_animate(0.0, 1.2, not placing)


func _load_place() -> void:
	if not FileAccess.file_exists(PLACE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLACE_PATH))
	if not data is Dictionary:
		return
	var pos: Variant = data.get("position")
	if pos is Array and (pos as Array).size() == 3:
		_pos = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	_pitch = float(data.get("pitch", _pitch))
	_scale = float(data.get("scale", _scale))
