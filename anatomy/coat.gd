extends RefCounted
## The rig coat's runtime deform: the duplicate-and-patch, the vulva/anal spread, the vulva cut,
## the two no-jiggle zones and the debug overlay. It owns the coat material copies and restores
## the game shaders exactly.
##
## See `docs/anatomy.md` (`## Body coat deform`).

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const GEOMETRY := preload("res://mods/unfplap/anatomy/geometry.gd")
const BODY_COAT_PATCH := preload("res://mods/unfplap/anatomy/body_coat_patch.gd")
const STILL_ZONE_DEBUG := preload("res://mods/unfplap/anatomy/still_zone_debug.gd")

const WINKING_OPENING := Vector3(0.0, -0.012, 0.02)
const LIP_OUTER_FACTOR := 3.0
const BODY_ANAL_REACH := 0.09
const VULVA_RELIEF_M := 0.002
const JIGGLE_STILL_MIN_M := 0.05

var pony: Node3D
var mesh: MeshInstance3D
var skeleton: Skeleton3D
var shapes: RefCounted

var _body_mesh: MeshInstance3D
var _body_material: ShaderMaterial
var _body_outline: ShaderMaterial
var _body_original_shader: Shader
var _body_outline_original_shader: Shader
var _body_patched := false
var _hips_bind := Transform3D.IDENTITY
var _hips_bind_ready := false
var _zone_debug: Node3D
var _zone_vulva_centre := Vector3.ZERO
var _zone_anal_centre := Vector3.ZERO
var _zone_axes := Basis.IDENTITY
var _zone_vulva_radius := 0.0
var _zone_anal_radius := 0.0
var _zone_oval := 0.7
var _zone_fade := 0.25


func setup(pony_node: Node3D, shapes_node: RefCounted) -> void:
	pony = pony_node
	shapes = shapes_node


func set_mesh(mesh_node: MeshInstance3D, skeleton_node: Skeleton3D) -> void:
	mesh = mesh_node
	skeleton = skeleton_node
	_hips_bind_ready = false


func clear_mesh() -> void:
	var body := _body_mesh
	var material := _body_material
	restore()
	# A despawned pony can already be a surface-less mesh; releasing surface 0 then errors in the
	# rendering server.
	if is_instance_valid(body) and is_instance_valid(material) \
			and body.mesh != null and body.mesh.get_surface_count() > 0:
		body.set_surface_override_material(0, null)
	mesh = null
	skeleton = null
	_hips_bind_ready = false
	_hips_bind = Transform3D.IDENTITY


func is_patched() -> bool:
	return _body_patched


func body_mesh() -> MeshInstance3D:
	return _body_mesh if _body_patched and is_instance_valid(_body_mesh) else null


func body_material() -> ShaderMaterial:
	return _body_material if _body_patched and is_instance_valid(_body_material) else null


func body_outline_material() -> ShaderMaterial:
	return _body_outline if _body_patched and is_instance_valid(_body_outline) else null


## Apply or remove the patch and write the current uniforms. Idempotent and safe to call live.
func apply() -> void:
	if not SETTINGS.body_coat_deform.get_bool():
		restore()
		return
	if not is_instance_valid(pony):
		restore()
		return
	var model: Variant = pony.get("_model")
	if not model is Node:
		restore()
		return
	var body := (model as Node).find_child("MareBody", true, false) as MeshInstance3D
	if not is_instance_valid(body) or body.mesh == null:
		restore()
		return
	if body.mesh.get_surface_count() == 0:
		restore()
		return
	if not _hips_bind_ready:
		_hips_bind_pose()
	if _body_mesh != body or not is_instance_valid(_body_material) \
			or body.get_active_material(0) != _body_material:
		restore()
		# The body material is shared between ponies of one identity. FlankTouch owns the
		# per-pony copies and keeps the outline in the pony's outline list.
		var flank := pony.get_node_or_null("FlankTouch")
		if flank != null and flank.has_method("_own_body_materials"):
			flank.call("_own_body_materials")
		var source := body.get_active_material(0) as ShaderMaterial
		if source == null:
			return
		if not source.has_meta("jiggle_own"):
			source = source.duplicate() as ShaderMaterial
			var own_hull := source.next_pass as ShaderMaterial
			if own_hull != null:
				source.next_pass = own_hull.duplicate()
			source.set_meta("jiggle_own", true)
			body.set_surface_override_material(0, source)
		_body_mesh = body
		_body_material = source
		_body_original_shader = source.shader
		var hull := source.next_pass as ShaderMaterial
		_body_outline = hull
		_body_outline_original_shader = hull.shader if hull != null else null
	if not _body_patched:
		var patched := BODY_COAT_PATCH.patched(_body_original_shader)
		if patched == null:
			return
		_body_material.shader = patched
		if _body_outline != null and _body_outline_original_shader != null:
			var hull_patched := BODY_COAT_PATCH.patched(_body_outline_original_shader)
			if hull_patched != null:
				_body_outline.shader = hull_patched
		_body_patched = true
	_ensure_zone_debug()
	_apply_uniforms()


## Put the game shaders back. The per-pony material copies stay; only the shader resource and
## the mod uniforms are undone.
func restore() -> void:
	if _body_patched:
		if is_instance_valid(_body_material) and is_instance_valid(_body_original_shader):
			_body_material.shader = _body_original_shader
		if is_instance_valid(_body_outline) and is_instance_valid(_body_outline_original_shader):
			_body_outline.shader = _body_outline_original_shader
	_body_patched = false
	if is_instance_valid(_zone_debug):
		_zone_debug.visible = false
	_body_material = null
	_body_outline = null
	_body_mesh = null
	_body_original_shader = null
	_body_outline_original_shader = null


## Debug-only rings for the two still zones.
func tick_debug() -> void:
	if not is_instance_valid(_zone_debug):
		_zone_debug = null
		return
	var show := SETTINGS.draw_still_zones.get_bool() and _body_patched \
		and SETTINGS.body_coat_deform.get_bool() and _hips_bind_ready \
		and is_instance_valid(skeleton) and is_instance_valid(mesh)
	if not show:
		_zone_debug.visible = false
		return
	var hip := skeleton.find_bone("pony_hips")
	if hip < 0:
		_zone_debug.visible = false
		return
	# The zone centres are body-local; the hips skinning transform puts the rings on the posed
	# rump. The rump coat is dominated by this bone, so this is the useful debug frame.
	var body_to_world := skeleton.global_transform \
		* skeleton.get_bone_global_pose(hip) * _hips_bind
	_zone_debug.call("update", body_to_world, _zone_vulva_centre, _zone_axes,
		_zone_vulva_radius, _zone_anal_centre, _zone_anal_radius, _zone_oval,
		_zone_fade, true)


func _hips_bind_pose() -> Transform3D:
	if _hips_bind_ready:
		return _hips_bind
	var model: Variant = pony.get("_model") if is_instance_valid(pony) else null
	if not model is Node:
		return _hips_bind
	var body := (model as Node).find_child("MareBody", true, false) as MeshInstance3D
	if not is_instance_valid(body) or body.skin == null:
		return _hips_bind
	for i in body.skin.get_bind_count():
		if String(body.skin.get_bind_name(i)) == "pony_hips":
			_hips_bind = body.skin.get_bind_pose(i)
			_hips_bind_ready = true
			break
	return _hips_bind


func _apply_uniforms() -> void:
	if not _body_patched or not is_instance_valid(_body_material) \
			or not is_instance_valid(mesh) or not _hips_bind_ready or shapes == null:
		return
	var scale := maxf(mesh.transform.basis.get_scale().x, 0.0001)
	var centre := GEOMETRY.body_local_point(_hips_bind, mesh.transform, WINKING_OPENING)
	var right_axis := GEOMETRY.body_local_direction(_hips_bind, mesh.transform, Vector3.RIGHT)
	var out_axis := GEOMETRY.body_local_direction(_hips_bind, mesh.transform, Vector3.BACK)
	var up_axis := GEOMETRY.body_local_direction(_hips_bind, mesh.transform, Vector3.UP)
	var spread := maxf(shapes.hole_target() / maxf(shapes.lip_radius(), 0.004), 1.0)
	spread = 1.0 + (spread - 1.0) * SETTINGS.coat_spread.get_num()
	var reach := maxf(shapes.lip_radius() * LIP_OUTER_FACTOR * scale * 1.1, 0.02)
	var depth := (spread - 1.0) * VULVA_RELIEF_M
	# Cut the coat behind the vulva opening so the silhouette cannot show through the closed lips.
	# The anatomy mesh is pushed into the coat; the cut is the same body-local frame as the spread
	# and follows the placement/scale. The gate closes when the anatomy is hidden (act-only mode).
	var hole: float = maxf(SETTINGS.coat_hole.get_num(), 0.0)
	var hole_radius: float = shapes.lip_radius() * scale * hole
	var hole_depth: float = maxf(SETTINGS.coat_hole_depth_mm.get_num(), 0.0) / 1000.0
	var hole_open: float = 1.0 if is_instance_valid(mesh) and mesh.is_visible_in_tree() else 0.0
	var still_centre := centre + up_axis * (SETTINGS.still_height_mm.get_num() / 1000.0)
	var still_radius := maxf(shapes.lip_radius() * LIP_OUTER_FACTOR * scale * 1.3,
			JIGGLE_STILL_MIN_M) * SETTINGS.jiggle_still.get_num()
	var anal_centre := GEOMETRY.body_local_point(_hips_bind, mesh.transform, shapes.anal_mouth())
	var anal_extreme := maxf(0.0, (shapes.anal_local() - GEOMETRY.ANAL_OVER_R)
		/ (GEOMETRY.ANAL_EXTREME_R - GEOMETRY.ANAL_OVER_R))
	var anal_still_centre := anal_centre
	var anal_still_radius := GEOMETRY.anal_still_radius_for(GEOMETRY.ANAL_LIP,
		GEOMETRY.ANAL_OUTER_FACTOR, scale, SETTINGS.anal_still.get_num()) * (1.0 + anal_extreme)
	_zone_vulva_centre = still_centre
	_zone_anal_centre = anal_still_centre
	_zone_vulva_radius = still_radius
	_zone_anal_radius = anal_still_radius
	_zone_axes = Basis(right_axis, up_axis, out_axis)
	_zone_oval = SETTINGS.still_oval.get_num()
	_zone_fade = SETTINGS.still_fade.get_num()
	# Follow the extrapolated V2 extreme so the visible body mound wraps the same ring.
	var anal_scale := SETTINGS.anal_scale.get_num() * (1.0 + anal_extreme)
	for material in [_body_material, _body_outline]:
		if not is_instance_valid(material):
			continue
		var mat := material as ShaderMaterial
		mat.set_shader_parameter("body_coat_anal_centre", anal_centre)
		mat.set_shader_parameter("body_coat_anal_scale", anal_scale)
		mat.set_shader_parameter("body_coat_anal_reach", BODY_ANAL_REACH)
		mat.set_shader_parameter("body_coat_anal_out", out_axis)
		mat.set_shader_parameter("body_coat_anal_depth",
			SETTINGS.anal_body_depth_mm.get_num() / 1000.0 * (1.0 + anal_extreme))
		# Keep the body under the V2 lip: the indent must not reach past the outer lip.
		# Slightly wider than the shaft; the extra 3 mm side lip flange covers the wall.
		mat.set_shader_parameter("body_coat_anal_hole_reach",
			(maxf(shapes.anal_local(), GEOMETRY.ANAL_OPEN_R) + 0.0015) * scale)
		mat.set_shader_parameter("body_coat_vulva_centre", centre)
		mat.set_shader_parameter("body_coat_vulva_out", out_axis)
		mat.set_shader_parameter("body_coat_vulva_scale", spread)
		mat.set_shader_parameter("body_coat_vulva_reach", reach)
		mat.set_shader_parameter("body_coat_vulva_depth", depth)
		mat.set_shader_parameter("body_coat_vulva_hole", hole_radius)
		mat.set_shader_parameter("body_coat_vulva_hole_depth", hole_depth)
		mat.set_shader_parameter("body_coat_vulva_hole_open", hole_open)
		mat.set_shader_parameter("body_coat_still_centre", still_centre)
		mat.set_shader_parameter("body_coat_still_radius", still_radius)
		mat.set_shader_parameter("body_coat_anal_still_centre", anal_still_centre)
		mat.set_shader_parameter("body_coat_anal_still_radius", anal_still_radius)
		mat.set_shader_parameter("body_coat_still_right", right_axis)
		mat.set_shader_parameter("body_coat_still_up", up_axis)
		mat.set_shader_parameter("body_coat_still_oval", SETTINGS.still_oval.get_num())
		mat.set_shader_parameter("body_coat_still_fade", SETTINGS.still_fade.get_num())


func _ensure_zone_debug() -> void:
	if is_instance_valid(_zone_debug) or not is_instance_valid(pony):
		return
	_zone_debug = STILL_ZONE_DEBUG.new()
	pony.add_child(_zone_debug)
	_zone_debug.call("setup")
