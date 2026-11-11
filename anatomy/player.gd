extends Node
## integration: ported from PonyPussyParadise anon_part.gd; the player part. Shows the part on the human player's
## Hips during encounters. The mesh and textures come from the external resource pack
## (see assets/README.md).

const PLAYER_FORM := preload("res://world/life/player_form.gd")
const OUTLINE_EXCLUSION := preload("res://world/post_outline_exclusion.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const HIPS_REST := Vector3(0.0, 0.978635, 0.013361)
const SKIN := Color(0.34, 0.66, 0.34)
const SKIN_SHADE := Color(0.27, 0.54, 0.28)
const TIP := Color(0.62, 0.74, 0.42)
const TIP_SHADE := Color(0.46, 0.57, 0.3)

const PIVOT := Vector3(0.0, 0.8226, 0.122)
const TIP_POINT := Vector3(0.0, 0.974, 0.76)
## The visible glans tip sits slightly above the centre-line tip point; aim the debug point there.
const TIP_LIFT_M := 0.02
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
## The applied penetration's low-pass, so the act-start contact pull-in and live size edits glide.
const PENETRATION_SMOOTH_S := 0.06
## The glans band: the head multiplier is fully applied from HEAD_FULL to the tip.
const HEAD_START := 0.72
const HEAD_FULL := 0.86
## A two-lobe heartbeat. The amplitude is a fraction of the shaft radius.
const THROB_HZ := 1.1
const THROB_DEPTH_RATE := 0.15
const THROB_REST := 0.012
const THROB_DEPTH := 0.018
## How far the tip rises on a beat while the shaft is out of her, as a fraction of its visible
## length. Full thrust fades the rise to nothing.
const THROB_LIFT := 0.02

const MESH_PATH := "res://mods/unfplap/assets/anatomy/anon_part.scn"
const ALBEDO_PATH := "res://mods/unfplap/assets/anatomy/anon_part_albedo.png"
const AO_PATH := "res://mods/unfplap/assets/anatomy/anon_part_ao.png"
const NRM_PATH := "res://mods/unfplap/assets/anatomy/anon_part_nrm.png"

## The Anon body this part binds to. The facade resolves it; the part never reads the main node.
var player_body: Node3D
var placing := false

var _mesh: MeshInstance3D
var _skeleton: Skeleton3D
var _bone_inverse := Transform3D.IDENTITY
var _pos := Vector3.ZERO
var _pitch := 0.0
var _scale := 1.0
## Missionary-only base slide along the shaft, set by `anatomy_act` from
## `presentation.missionary.part_inset_m`. Negative pulls the whole part back into the pelvis.
var bed_inset_m := 0.0
var _setting_scale := 1.0
var _girth_base := 1.0
var _girth_mid := 1.0
var _girth_head := 1.0
var _part_length_scale := 1.0
var _throb_gain := 1.0
var _throb_clock := 0.0
var _throb_depth := 0.0
var _throb_amount := 0.0
## The beat's upward rise, in local units before the ready blend; only while the shaft is out.
var _throb_lift := 0.0
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
## The applied penetration in metres and whether it has been seeded from the act's stance yet.
var _p_smooth := 0.0
var _p_started := false
## The total Hips-bone offset the standing controller applied last frame, and the offset this
## frame asks for. The pelvis carries the part, so the two always move as one body.
var hip_offset_applied := Vector3.ZERO
var _hip_offset_wanted := Vector3.ZERO
## Downward aim tilt for the anal hole, degrees; set by the act each frame.
var aim_pitch_deg := 0.0
## Her opening's outward normal and the point itself, set by the act each frame.
var aim_normal := Vector3.ZERO
var aim_opening := Vector3.ZERO


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
	var body: Node3D = player_body if is_instance_valid(player_body) else null
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
	mat.shader = load("res://mods/unfplap/anatomy/player.gdshader")
	mat.set_shader_parameter("color", SKIN)
	mat.set_shader_parameter("shadow_color", SKIN_SHADE)
	mat.set_shader_parameter("tip_color", TIP)
	mat.set_shader_parameter("tip_shadow", TIP_SHADE)
	mat.set_shader_parameter("shaft_root", PIVOT)
	mat.set_shader_parameter("shaft_axis", (TIP_POINT - PIVOT).normalized())
	mat.set_shader_parameter("shaft_length", _part_length())
	mat.set_shader_parameter("length_scale", _part_length_scale)
	mat.set_shader_parameter("head_start", HEAD_START)
	mat.set_shader_parameter("head_full", HEAD_FULL)
	mat.set_shader_parameter("girth_base", _girth_base)
	mat.set_shader_parameter("girth_mid", _girth_mid)
	mat.set_shader_parameter("girth_head", _girth_head)
	mat.set_shader_parameter("throb", _throb_amount)
	mat.set_shader_parameter("throb_lift", _throb_lift * _ready_amount)
	mat.set_shader_parameter("throb_up", _throb_up())
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
	_setting_scale = SETTINGS.player_scale.get_num()
	_girth_base = maxf(SETTINGS.part_base_scale.get_num(), 0.01)
	_girth_mid = maxf(SETTINGS.part_mid_scale.get_num(), 0.01)
	_girth_head = maxf(SETTINGS.part_head_scale.get_num(), 0.01)
	_part_length_scale = maxf(SETTINGS.part_length_scale.get_num(), 0.01)
	_throb_gain = maxf(SETTINGS.part_throb.get_num(), 0.0)


## integration: the user-facing scale sits on top of the saved placement.
func _rotation_basis() -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(_pitch), 0.0, 0.0))


func _placed() -> Transform3D:
	var basis := _rotation_basis().scaled(Vector3.ONE * _scale * _setting_scale)
	# `Cock forward` slides the base out along the shaft, so it can sit on the front of the hips
	# instead of inside the pelvis. The missionary inset moves the whole part back into the pelvis.
	var front := SETTINGS.part_front_m.get_num() + bed_inset_m
	var axis := (TIP_POINT - PIVOT).normalized()
	return _bone_inverse * Transform3D(basis, _pos + (_rotation_basis() * axis) * front)


func _apply_place() -> void:
	_mesh.transform = _placed()


## The shader multiplies each cross-section; keep the reported girth in step with it so the holes
## stretch to the visible size.
func _apply_girth() -> void:
	var material := _mesh.get_surface_override_material(0) as ShaderMaterial
	if material != null:
		material.set_shader_parameter("shaft_length", _part_length())
		material.set_shader_parameter("length_scale", _part_length_scale)
		material.set_shader_parameter("girth_base", _girth_base)
		material.set_shader_parameter("girth_mid", _girth_mid)
		material.set_shader_parameter("girth_head", _girth_head)
	_apply_throb()


## The heartbeat uniforms, together: the girth pulse, the upward rise and the axis it lifts along.
## The rise is scaled by the ready blend so it folds away with the mesh.
func _apply_throb() -> void:
	if not is_instance_valid(_mesh):
		return
	var material := _mesh.get_surface_override_material(0) as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("throb", _throb_amount)
	material.set_shader_parameter("throb_lift", _throb_lift * _ready_amount)
	material.set_shader_parameter("throb_up", _throb_up())


## World up expressed in the mesh's own frame. The bed placement turns the shaft flat onto the
## mattress, so a fixed local axis would lift it sideways there.
func _throb_up() -> Vector3:
	if not is_instance_valid(_mesh):
		return Vector3.UP
	var up := _mesh.global_basis.inverse() * Vector3.UP
	return up.normalized() if up.length_squared() > 0.000001 else Vector3.UP


## The shaped shaft length, in the mesh's local units. Every placement and report uses it so the
## visible part, the hole grip and the fluid point can never drift apart.
func _part_length() -> float:
	return PART_LENGTH * _part_length_scale


## The visible tip on the local shaft axis. The shader stretches positive axial geometry by the
## same factor.
func _visible_tip_local() -> Vector3:
	var axis := (TIP_POINT - PIVOT).normalized()
	return PIVOT + axis * ((TIP_POINT - PIVOT).length() * _part_length_scale)


## The head multiplier's share at normalized length `u`, matching the shader.
func _head_scale_at(u: float) -> float:
	return lerpf(1.0, _girth_head, smoothstep(HEAD_START, HEAD_FULL, u))


## The placed shaft's visible length in metres, from the pelvis pivot to the tip on its axis. The
## act's depth scale and every placement are built on it, so a size or length change is physical.
func shaft_length_m() -> float:
	if not is_instance_valid(_mesh):
		return 0.0
	return _part_length() * _world_scale()


## The applied penetration, eased: in the standing pose the first frame pulls his pelvis in from
## wherever the stance left it, so it blends through `POSING_IN` instead of snapping; the other
## placements start where the depth already is. A live size change stays smooth in every path.
func _smooth_penetration(penetration_m: float, delta: float, target: Vector3,
		seed: bool) -> float:
	if not _p_started:
		_p_started = true
		_p_smooth = (shaft_length_m() - root_now().distance_to(target)) if seed else penetration_m
	if delta <= 0.0:
		return _p_smooth
	_p_smooth = lerpf(_p_smooth, penetration_m, 1.0 - exp(-delta / PENETRATION_SMOOTH_S))
	return _p_smooth


## integration: live user-facing size/rotation update.
func apply_live() -> void:
	_read_settings()
	_load_place()
	if is_instance_valid(_mesh):
		_apply_place()
		_apply_girth()


## integration: standing: the part stays fixed to his hips. Bed: it rides her hips instead.
## `penetration_m` is how far the tip has passed her lips, measured in metres; negative is the
## `Back-out gap` standoff, so the placement never needs a separate depth fraction.
func track(target: Vector3, rear: Vector3, up: Vector3, bed: bool, penetration_m: float,
		delta: float, mare_anchor: Node3D, attached := true) -> void:
	if not is_instance_valid(_mesh) or not _mesh.visible or placing:
		return
	_throb_tick(delta, penetration_m / maxf(shaft_length_m(), 0.001))
	var shown := _smooth_penetration(penetration_m, delta, target, attached and not bed)
	if bed:
		_track_bed(target, rear, up, shown, mare_anchor)
		return
	_end_bed()
	_aim_part(target, shown, attached)
	if delta <= 0.0:
		return
	var root := root_now()
	var velocity := Vector3.ZERO if _last_root == Vector3.INF else (root - _last_root) / delta
	var acceleration := ((velocity - _last_velocity) / delta).limit_length(ACCELERATION_MAX)
	_last_root = root
	_last_velocity = velocity
	var to_mesh := _mesh.global_basis.inverse().orthonormalized()
	var axis := (TIP_POINT - PIVOT).normalized()
	var reach := _part_length() * _world_scale()
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
			* clampf((_part_length() - at) / (_part_length() * 0.12), 0.0, 1.0))
		material.set_shader_parameter("compress", _squash)


## A slight heartbeat that rises with depth. The waveform has two lobes so it reads as a pulse
## rather than a clean sine. `part_throb` is an intensity counter; zero stops it. While the shaft
## is out of her the beat also lifts it, fading to nothing as the thrust reaches full depth.
func _throb_tick(delta: float, depth: float) -> void:
	if delta <= 0.0:
		return
	_throb_depth = lerpf(_throb_depth, clampf(depth, 0.0, 1.0), 1.0 - exp(-delta / 0.15))
	_throb_clock = fposmod(_throb_clock
		+ delta * THROB_HZ * lerpf(1.0, 1.0 + THROB_DEPTH_RATE, _throb_depth), 1.0)
	var t := _throb_clock
	var first := exp(-pow((t - 0.10) / 0.075, 2.0))
	var second := 0.55 * exp(-pow((t - 0.30) / 0.09, 2.0))
	var beat := clampf(first + second, 0.0, 1.0)
	_throb_amount = _ready_amount * _throb_gain \
		* (THROB_REST + THROB_DEPTH * _throb_depth) * beat
	_throb_lift = _throb_gain * THROB_LIFT * _part_length() * beat \
		* (1.0 - smoothstep(0.0, 1.0, _throb_depth))
	_apply_throb()


## Aim the visible part at the entrance. In the standing act the part stays a rigid child of the
## hips and the controller moves the pelvis instead (`hip_offset_wanted`), so his crotch and the
## part travel together; the other poses keep the aim-and-slide placement.
func _aim_part(target: Vector3, penetration_m: float, attached: bool) -> void:
	if not is_instance_valid(_mesh) or not target.is_finite():
		return
	_apply_place()
	if attached:
		_aim_attached(target, penetration_m)
		return
	_hip_offset_wanted = Vector3.ZERO
	var pivot := _mesh.global_transform * PIVOT
	var tip := _mesh.global_transform * _visible_tip_local()
	var to_tip := tip - pivot
	var to_open := target - pivot
	if to_tip.length_squared() < 0.000001 or to_open.length_squared() < 0.000001:
		return
	var turned := Basis(Quaternion(to_tip.normalized(), to_open.normalized())) * _mesh.global_transform.basis
	var direction := to_open.normalized()
	# Put the tip exactly `penetration_m` past her lips; a negative value is the back-out standoff,
	# so the whole part pulls back instead of eating into the depth range.
	var desired := to_open.length() + penetration_m
	var slide := desired - to_tip.length()
	_mesh.global_transform = Transform3D(turned, pivot - turned * PIVOT + direction * slide)


## Standing: rotate the part about its base in the hips' frame and ask the controller to move the
## pelvis by the distance the entrance needs, so the base never leaves his crotch.
func _aim_attached(target: Vector3, penetration_m: float) -> void:
	var parent := _mesh.get_parent() as Node3D
	if not is_instance_valid(parent):
		return
	var local := _mesh.transform
	var posed := parent.global_transform * local
	var pivot_natural := posed * PIVOT - hip_offset_applied
	var tip_natural := posed * _visible_tip_local() - hip_offset_applied
	var to_tip := tip_natural - pivot_natural
	var to_open := target - pivot_natural
	if to_tip.length_squared() < 0.000001 or to_open.length_squared() < 0.000001:
		return
	# The shaft must run along her opening's normal, not any line that happens to reach the hole:
	# that is what keeps it out of her rump when she sways. `aim_normal` points at Anon, so into
	# her is its negation.
	var on_normal: bool = aim_normal.length_squared() > 0.0001
	var shaft_dir: Vector3 = (-aim_normal.normalized()) if on_normal else to_open.normalized()
	var turn := Basis(Quaternion(to_tip.normalized(), shaft_dir))
	if not is_zero_approx(aim_pitch_deg):
		var right := Vector3.UP.cross(shaft_dir)
		if right.length_squared() > 0.000001:
			turn = Basis(right.normalized(), deg_to_rad(aim_pitch_deg)) * turn
	var pivot := posed * PIVOT
	var turned := Transform3D(turn * posed.basis, pivot + turn * (posed.origin - pivot))
	_mesh.transform = parent.global_transform.affine_inverse() * turned
	# Place his pelvis so the tip is exactly `penetration_m` past her lips along her opening's
	# normal, or the back-out standoff behind them when it is negative. `penetration_reach()` in
	# the runtime already stops his body on `Pelvis gap`, so there is no second clamp here.
	var aim_dir := (turn * to_tip.normalized()).normalized()
	if on_normal and aim_opening != Vector3.ZERO:
		# `aim_dir` points into her, so step *back* from the opening by the remaining shaft.
		var pivot_target: Vector3 = aim_opening - aim_dir * (to_tip.length() - penetration_m)
		_hip_offset_wanted = pivot_target - pivot_natural
	else:
		_hip_offset_wanted = to_open - aim_dir * (to_tip.length() - penetration_m)


## The Hips-bone offset, in world space, that puts the part at the entrance for this depth.
func hip_offset_wanted() -> Vector3:
	return _hip_offset_wanted


func _set_bend(turn: Vector3) -> void:
	var material := _mesh.get_surface_override_material(0) as ShaderMaterial
	if material != null:
		material.set_shader_parameter("bend_turn", turn)


## Missionary on the bed body: the part rides her hips, so the holder sits `shaft - penetration`
## behind her lips and the tip lands exactly that deep. A negative penetration is the standoff.
func _track_bed(target: Vector3, rear: Vector3, up: Vector3, penetration_m: float,
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
	var reach := shaft_length_m() - penetration_m
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
	var length := _part_length() * _mesh.global_transform.basis.get_scale().x
	return clampf((length - (_mesh.global_transform * PIVOT).distance_to(opening)
		+ ENTRY_LEAD_M) / length, 0.0, 1.0)


## integration: world radius of the shaft where it passes through `opening`.
func girth_at(opening: Vector3) -> float:
	if not is_instance_valid(_mesh) or not _mesh.visible:
		return -1.0
	var along := root_now().distance_to(opening) / (_part_length() * _world_scale())
	if along >= 1.0:
		return 0.0
	var at := clampf(along, 0.0, 1.0) * (WIDTHS.size() - 1)
	var below := floori(at)
	var profile := lerpf(_girth_base, _girth_mid, smoothstep(0.0, 0.35, clampf(along, 0.0, 1.0)))
	profile *= _head_scale_at(clampf(along, 0.0, 1.0)) * (1.0 + _throb_amount)
	return lerpf(WIDTHS[below], WIDTHS[mini(below + 1, WIDTHS.size() - 1)], at - below) \
		* _world_scale() * profile


func _straighten() -> Basis:
	return Basis(Quaternion((TIP_POINT - PIVOT).normalized(), Vector3.BACK))


func showing() -> bool:
	return is_instance_valid(_mesh) and _mesh.visible and not placing


func tip_world() -> Vector3:
	return _mesh.global_transform * (_visible_tip_local() + Vector3(0.0, TIP_LIFT_M, 0.0))


## The modelled tip on the shaft axis, without the debug aim lift `tip_world()` carries. The act
## measures the tip against her lips with this, so a tuning offset cannot make a touch look far.
func tip_center() -> Vector3:
	if not is_instance_valid(_mesh):
		return Vector3.INF
	return _mesh.global_transform * _visible_tip_local()


## Radius profile along the shaft, world metres, sampled evenly from base to tip. The anatomy
## shader projects any vulva vertex inside this swept circle onto its surface.
func shaft_radii(count := 8) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(count)
	var scale := _world_scale()
	for i: int in count:
		var u: float = float(i) / float(maxi(count - 1, 1))
		var at: float = u * (WIDTHS.size() - 1)
		var below := floori(at)
		var width := lerpf(WIDTHS[below], WIDTHS[mini(below + 1, WIDTHS.size() - 1)], at - below)
		var profile := lerpf(_girth_base, _girth_mid, smoothstep(0.0, 0.35, u))
		profile *= _head_scale_at(u) * (1.0 + _throb_amount)
		out[i] = width * scale * profile
	return out


func depth_for(metres: float) -> float:
	return metres / (_part_length() * _world_scale())


func root_now() -> Vector3:
	if not is_instance_valid(_mesh):
		return Vector3.INF
	return _mesh.global_transform * PIVOT


## Build the hidden part mesh so a gate can measure its natural root before an encounter.
func prepare() -> bool:
	return _ensure()


## Where his pelvis pivot sits for a given penetration: `shaft - penetration` behind her lips, so
## the bed body follows the same physical model as the placed part.
func root_for(target: Vector3, rear: Vector3, penetration_m: float) -> Vector3:
	return target + rear * (shaft_length_m() - penetration_m)


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


## Debug: the visible part's world scale. A stretch shows up here before it is visible in the scene.
func debug_scale() -> Vector3:
	return _mesh.global_transform.basis.get_scale() if is_instance_valid(_mesh) else Vector3.ZERO


func _set_ready(value: float) -> void:
	_ready_amount = value
	if is_instance_valid(_mesh):
		_apply_ready()
		_apply_throb()


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


## Complete per-act reset. The part is a child of the player's Hips, so a stale local transform,
## aim or pelvis offset from one act is visible in the next one; every transient is cleared here.
func reset_state() -> void:
	hip_offset_applied = Vector3.ZERO
	_hip_offset_wanted = Vector3.ZERO
	bed_inset_m = 0.0
	aim_normal = Vector3.ZERO
	aim_opening = Vector3.ZERO
	aim_pitch_deg = 0.0
	_bend = Vector3.ZERO
	_bend_speed = Vector3.ZERO
	_squash = 0.0
	_squash_speed = 0.0
	_last_root = Vector3.INF
	_last_velocity = Vector3.ZERO
	_throb_amount = 0.0
	_throb_depth = 0.0
	_throb_lift = 0.0
	_p_smooth = 0.0
	_p_started = false
	if not is_instance_valid(_mesh):
		return
	_end_bed()
	_set_bend(Vector3.ZERO)
	_apply_place()
	_apply_girth()
	var material := _mesh.get_surface_override_material(0) as ShaderMaterial
	if material != null:
		material.set_shader_parameter("squish", 0.0)
		material.set_shader_parameter("squish_at", 0.0)
		material.set_shader_parameter("compress", 0.0)
		material.set_shader_parameter("throb", 0.0)
		material.set_shader_parameter("throb_lift", 0.0)


func encounter(on: bool) -> void:
	_in_encounter = on
	if on:
		if not _ensure():
			return
		reset_state()
		_mesh.visible = true
		_swap_legs(true)
		_animate(1.0, 1.4)
	elif is_instance_valid(_mesh):
		reset_state()
		_animate(0.0, 1.2, not placing)


func _load_place() -> void:
	var placement := SETTINGS.anon_placement()
	_pos = Vector3(
		float(placement.get("offset_x", 0.0)),
		float(placement.get("offset_y", 0.0)),
		float(placement.get("offset_z", 0.0)))
	_pitch = float(placement.get("pitch_deg", 0.0))
	_scale = maxf(0.05, float(placement.get("scale", 1.0)))
