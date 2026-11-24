extends RefCounted
## The rig and merged-near coat's runtime deform: the duplicate-and-patch, the vulva/anal spread,
## the vulva cut, the vulva no-jiggle zone and the debug overlay. It owns the coat material copies
## and restores the game shaders exactly.

const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const GEOMETRY := preload("res://mods/unfplap/anatomy/geometry.gd")
const BODY_COAT_PATCH := preload("res://mods/unfplap/anatomy/body_coat_patch.gd")
const BODY_COAT := preload("res://mods/unfplap/shared/body_coat.gd")
const STILL_ZONE_DEBUG := preload("res://mods/unfplap/anatomy/still_zone_debug.gd")
const RIG := preload("res://mods/unfplap/anatomy/rig.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const BODY_ANAL_REACH := 0.09
const VULVA_RELIEF_M := 0.002
const JIGGLE_STILL_MIN_M := 0.05
const PALETTE_ENTRIES := 32

var pony: Node3D
var rig: RIG
var mesh: MeshInstance3D
var skeleton: Skeleton3D
var shapes: RefCounted
var _patch_log := ""

var _body_mesh: MeshInstance3D
var _body_surface := 0
var _body_material: ShaderMaterial
var _body_outline: ShaderMaterial
var _body_original_shader: Shader
var _body_outline_original_shader: Shader
var _body_patched := false
## The two debug toggles, read on the visibility poll so the per-frame ring check is a field read.
var _body_coat_deform := false
var _draw_still_zones := false
var _zone_debug: STILL_ZONE_DEBUG
var _zone_vulva_centre := Vector3.ZERO
var _zone_axes := Basis.IDENTITY
var _zone_vulva_radius := 0.0
var _zone_oval: float
var _zone_fade: float
var _near_state: Dictionary = {}
var _near_entries: Dictionary = {}
var _materials: Array = []
var _targets: Array = []


func setup(pony_node: Node3D, shapes_node: RefCounted, rig_node: RIG) -> void:
	pony = pony_node
	shapes = shapes_node
	rig = rig_node


func set_mesh(mesh_node: MeshInstance3D, skeleton_node: Skeleton3D) -> void:
	mesh = mesh_node
	skeleton = skeleton_node


func clear_mesh() -> void:
	var body := _body_mesh
	var material := _body_material
	var surface := _body_surface
	restore()
	# A despawned pony can already be a surface-less mesh; releasing the surface then errors in
	# the rendering server.
	if is_instance_valid(body) and is_instance_valid(material) \
			and body.mesh != null and body.mesh.get_surface_count() > surface:
		body.set_surface_override_material(surface, null)
	mesh = null
	skeleton = null


func body_mesh() -> MeshInstance3D:
	return _body_mesh if _body_patched and is_instance_valid(_body_mesh) else null


func body_material() -> ShaderMaterial:
	return _body_material if _body_patched and is_instance_valid(_body_material) else null


func body_outline_material() -> ShaderMaterial:
	return _body_outline if _body_patched and is_instance_valid(_body_outline) else null


func targets() -> Array:
	return _targets


## Apply or remove the patch and write the current uniforms. Idempotent and safe to call live.
func apply() -> void:
	_body_coat_deform = SETTINGS.body_coat_deform.get_bool()
	_draw_still_zones = SETTINGS.draw_still_zones.get_bool()
	if not _body_coat_deform:
		restore()
		return
	if not is_instance_valid(pony):
		restore()
		return
	var found := BODY_COAT.resolve(pony)
	if found.is_empty():
		_log_once("body coat skipped: no drawn coat")
		restore()
		return
	var body := found.get("mesh") as MeshInstance3D
	var surface := int(found.get("surface", -1))
	if not is_instance_valid(body) or body.mesh == null or surface < 0 \
			or surface >= body.mesh.get_surface_count():
		_log_once("body coat skipped: invalid body surface")
		restore()
		return
	if _body_mesh != body or _body_surface != surface or not is_instance_valid(_body_material) \
			or body.get_active_material(surface) != _body_material:
		restore()
		# The body material is shared across an identity, so the per-pony copy lives on FlankTouch
		# along with the outline.
		rig.own_body_materials(pony)
		var source := body.get_active_material(surface) as ShaderMaterial
		if source == null:
			var active := body.get_active_material(surface)
			_log_once("body coat skipped: body=%s surface=%d material=%s" % [
				str(body.name), surface, active.get_class() if active != null else "none"])
			return
		if not source.has_meta("jiggle_own"):
			source = source.duplicate() as ShaderMaterial
			var own_hull := source.next_pass as ShaderMaterial
			if own_hull != null:
				source.next_pass = own_hull.duplicate()
			source.set_meta("jiggle_own", true)
			body.set_surface_override_material(surface, source)
		_body_mesh = body
		_body_surface = surface
		_body_material = source
		_body_original_shader = source.shader
		var hull := source.next_pass as ShaderMaterial
		_body_outline = hull
		_body_outline_original_shader = hull.shader if hull != null else null
	if not _body_patched:
		var shader_path := _body_original_shader.resource_path \
			if is_instance_valid(_body_original_shader) and not _body_original_shader.resource_path.is_empty() \
			else "inline"
		var patched := BODY_COAT_PATCH.patched(_body_original_shader)
		if patched == null:
			_log_once("body coat skipped: body=%s surface=%d shader=%s" % [
				str(_body_mesh.name) if is_instance_valid(_body_mesh) else "?",
				_body_surface, shader_path])
			return
		_body_material.shader = patched
		if _body_outline != null and _body_outline_original_shader != null:
			var hull_patched := BODY_COAT_PATCH.patched(_body_outline_original_shader)
			if hull_patched != null:
				_body_outline.shader = hull_patched
		_body_patched = true
		_log_patch("body coat patched body=%s surface=%d shader=%s" % [
			str(_body_mesh.name) if is_instance_valid(_body_mesh) else "?",
			_body_surface, shader_path])
	_refresh_near()
	_rebuild_materials()
	_ensure_zone_debug()
	_apply_uniforms()


## Put the game shaders back; the per-pony material copies stay.
func restore() -> void:
	if _body_patched:
		if is_instance_valid(_body_material) and is_instance_valid(_body_original_shader):
			_body_material.shader = _body_original_shader
		if is_instance_valid(_body_outline) and is_instance_valid(_body_outline_original_shader):
			_body_outline.shader = _body_outline_original_shader
	_body_patched = false
	_restore_near()
	_materials.clear()
	_targets.clear()
	if is_instance_valid(_zone_debug):
		_zone_debug.visible = false
	_body_material = null
	_body_outline = null
	_body_mesh = null
	_body_surface = 0
	_body_original_shader = null
	_body_outline_original_shader = null


## Advance the body-to-anatomy matrices used by the cut and the still zone. The static uniforms
## are rewritten on the visibility poll; these two follow the pose and the act trims every frame.
func tick() -> void:
	if not _body_patched or not is_instance_valid(mesh) or _materials.is_empty():
		return
	var anatomy_inverse := mesh.global_transform.affine_inverse()
	for item: Array in _materials:
		var material := item[0] as ShaderMaterial
		var target := item[1] as MeshInstance3D
		if not is_instance_valid(material) or not is_instance_valid(target) \
				or not target.is_visible_in_tree():
			continue
		var body_to_anatomy := anatomy_inverse * target.global_transform
		material.set_shader_parameter("body_coat_anatomy_inverse", body_to_anatomy)
		material.set_shader_parameter("body_coat_anatomy_to_body",
			body_to_anatomy.affine_inverse())


## Debug-only rings for the still zone.
func tick_debug() -> void:
	if not is_instance_valid(_zone_debug):
		_zone_debug = null
		return
	var show := _draw_still_zones and _body_patched \
		and _body_coat_deform and is_instance_valid(mesh)
	if not show:
		_zone_debug.visible = false
		return
	# The zone is anatomy-local; the anatomy node carries the pose, the placement and the
	# missionary trims, so the rings land on the same opening the shader tests.
	_zone_debug.update(mesh.global_transform, _zone_vulva_centre, _zone_axes,
		_zone_vulva_radius, _zone_oval, _zone_fade, true)


func _refresh_near() -> void:
	if not is_instance_valid(pony) or not is_instance_valid(_body_mesh):
		_restore_near()
		return
	var near_v: Variant = pony.get("_near")
	if not near_v is Dictionary:
		_restore_near()
		return
	var near := near_v as Dictionary
	if near.is_empty():
		_restore_near()
		return
	if is_same(near, _near_state):
		return
	_near_state = near
	var found := {}
	var groups_v: Variant = near.get("groups")
	if groups_v is Array:
		for group_v: Variant in groups_v as Array:
			if not group_v is Dictionary:
				continue
			var group := group_v as Dictionary
			var near_mesh_v: Variant = group.get("mi")
			var plan_v: Variant = group.get("group")
			var built_v: Variant = group.get("built")
			if not near_mesh_v is MeshInstance3D or not plan_v is Dictionary \
					or not built_v is Dictionary:
				continue
			var near_mesh := near_mesh_v as MeshInstance3D
			var plan := plan_v as Dictionary
			var built := built_v as Dictionary
			var variants_v: Variant = plan.get("variants")
			if not variants_v is Dictionary:
				continue
			var variants := variants_v as Dictionary
			for variant_key: Variant in built.keys():
				var variant_name := str(variant_key)
				if not variants.has(variant_name):
					continue
				var variant_v: Variant = variants[variant_name]
				var build_v: Variant = built[variant_name]
				if not variant_v is Dictionary or not build_v is Dictionary:
					continue
				var outputs_v: Variant = (variant_v as Dictionary).get("outputs")
				var materials_v: Variant = (build_v as Dictionary).get("materials")
				if not outputs_v is Array or not materials_v is Array:
					continue
				var outputs := outputs_v as Array
				var materials := materials_v as Array
				for i in mini(outputs.size(), materials.size()):
					var output_v: Variant = outputs[i]
					var material_v: Variant = materials[i]
					if not output_v is Dictionary or not material_v is ShaderMaterial:
						continue
					var entries_v: Variant = (output_v as Dictionary).get("entries")
					if not entries_v is Array:
						continue
					var mask := _body_entry_mask(entries_v as Array)
					if not _mask_has_body(mask):
						continue
					var material := material_v as ShaderMaterial
					_add_near_material(found, material, near_mesh, mask)
					var hull_v: Variant = material.next_pass
					if hull_v is ShaderMaterial:
						_add_near_material(found, hull_v as ShaderMaterial, near_mesh, mask)
	var stale: Array = []
	for key: Variant in _near_entries.keys():
		if not found.has(key):
			stale.append(key)
	for key: Variant in stale:
		var entry := _near_entries[key] as Dictionary
		var old_material := entry.get("material") as ShaderMaterial
		var original := entry.get("original") as Shader
		if is_instance_valid(old_material) and is_instance_valid(original):
			old_material.shader = original
		_near_entries.erase(key)
	for key: Variant in found.keys():
		var target := found[key] as Dictionary
		var material := target.get("material") as ShaderMaterial
		var mask := target.get("mask") as PackedFloat32Array
		if not _near_entries.has(key):
			var original := material.shader
			var patched := BODY_COAT_PATCH.patched(original)
			if patched == null:
				continue
			material.shader = patched
			_near_entries[key] = {"material": material, "original": original,
				"mesh": target.get("mesh"), "mask": mask}
		material.set_shader_parameter("jiggle_entry", mask)
		material.set_shader_parameter("body_coat_entry", mask)


func _restore_near() -> void:
	for entry_v: Variant in _near_entries.values():
		var entry := entry_v as Dictionary
		var material := entry.get("material") as ShaderMaterial
		var original := entry.get("original") as Shader
		if is_instance_valid(material) and is_instance_valid(original):
			material.shader = original
	_near_entries.clear()
	_near_state = {}


func _body_entry_mask(entries: Array) -> PackedFloat32Array:
	var mask := PackedFloat32Array()
	mask.resize(PALETTE_ENTRIES)
	for i in mini(entries.size(), PALETTE_ENTRIES):
		var entry_v: Variant = entries[i]
		if not entry_v is Array:
			continue
		var entry := entry_v as Array
		if entry.is_empty():
			continue
		var path := str(entry[0])
		if not path.is_empty() and pony.get_node_or_null(path) == _body_mesh:
			mask[i] = 1.0
	return mask


static func _mask_has_body(mask: PackedFloat32Array) -> bool:
	for value: float in mask:
		if value > 0.5:
			return true
	return false


func _add_near_material(found: Dictionary, material: ShaderMaterial,
		near_mesh: MeshInstance3D, mask: PackedFloat32Array) -> void:
	var key := material.get_instance_id()
	var existing_v: Variant = found.get(key)
	if existing_v is Dictionary:
		var merged := (existing_v as Dictionary).get("mask") as PackedFloat32Array
		for i in mini(merged.size(), mask.size()):
			if mask[i] > 0.5:
				merged[i] = 1.0
		return
	found[key] = {"material": material, "mesh": near_mesh, "mask": mask}


func _rebuild_materials() -> void:
	_materials.clear()
	_targets.clear()
	if not _body_patched:
		return
	if is_instance_valid(_body_material) and is_instance_valid(_body_mesh):
		_materials.append([_body_material, _body_mesh])
		if is_instance_valid(_body_outline):
			_materials.append([_body_outline, _body_mesh])
	for entry_v: Variant in _near_entries.values():
		var entry := entry_v as Dictionary
		var material := entry.get("material") as ShaderMaterial
		var target := entry.get("mesh") as MeshInstance3D
		if is_instance_valid(material) and is_instance_valid(target):
			_materials.append([material, target])
	for item: Array in _materials:
		_targets.append([item[0], item[1]])


func _apply_uniforms() -> void:
	if not _body_patched or not is_instance_valid(mesh) or shapes == null:
		return
	var scale := maxf(mesh.transform.basis.get_scale().x, 0.0001)
	var lip: float = float(shapes.lip_radius())
	var lip_denom := maxf(lip, 0.004)
	var spread := maxf(float(shapes.hole_target()) / lip_denom, 1.0)
	spread = 1.0 + (spread - 1.0) * SETTINGS.coat_spread.get_num()
	var reach := maxf(lip * GEOMETRY.LIP_OUTER_FACTOR * 1.1, 0.02 / scale)
	var depth := (spread - 1.0) * VULVA_RELIEF_M / scale
	var hole: float = maxf(SETTINGS.coat_hole.get_num(), 0.0)
	var hole_height: float = maxf(SETTINGS.coat_hole_height.get_num(), 0.0)
	var hole_radius: float = lip * hole
	var hole_vertical: float = lip * hole_height
	var hole_depth: float = maxf(SETTINGS.coat_hole_depth_mm.get_num(), 0.0) / 1000.0 / scale
	var hole_front: float = 0.01 / scale
	var hole_open: float = 1.0 if is_instance_valid(mesh) and mesh.is_visible_in_tree() else 0.0
	var still_centre := GEOMETRY.WINKING_OPENING \
		+ Vector3.UP * (SETTINGS.still_height_mm.get_num() / 1000.0 / scale)
	var still_radius := maxf(lip * GEOMETRY.LIP_OUTER_FACTOR * 1.3,
		JIGGLE_STILL_MIN_M / scale) * SETTINGS.jiggle_still.get_num()
	var anal_centre: Vector3 = shapes.anal_mouth()
	var anal_local: float = float(shapes.anal_local())
	var anal_extreme := maxf(0.0, (anal_local - GEOMETRY.ANAL_OVER_R)
		/ (GEOMETRY.ANAL_EXTREME_R - GEOMETRY.ANAL_OVER_R))
	_zone_vulva_centre = still_centre
	_zone_vulva_radius = still_radius
	_zone_axes = Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	_zone_oval = SETTINGS.still_oval.get_num()
	_zone_fade = SETTINGS.still_fade.get_num()
	# Follow the extrapolated V2 extreme so the visible body mound wraps the same ring.
	var anal_scale := SETTINGS.anal_scale.get_num() * (1.0 + anal_extreme)
	for item: Array in _materials:
		var material := item[0] as ShaderMaterial
		if not is_instance_valid(material):
			continue
		material.set_shader_parameter("body_coat_anal_centre", anal_centre)
		material.set_shader_parameter("body_coat_anal_scale", anal_scale)
		material.set_shader_parameter("body_coat_anal_reach", BODY_ANAL_REACH / scale)
		material.set_shader_parameter("body_coat_anal_out", Vector3.BACK)
		material.set_shader_parameter("body_coat_anal_depth",
			SETTINGS.anal_body_depth_mm.get_num() / 1000.0 / scale * (1.0 + anal_extreme))
		# Keep the body under the V2 lip: the indent must not reach past the outer lip.
		# Slightly wider than the shaft; the extra 3 mm side lip flange covers the wall.
		material.set_shader_parameter("body_coat_anal_hole_reach",
			maxf(anal_local, GEOMETRY.ANAL_OPEN_R) + 0.0015 / scale)
		material.set_shader_parameter("body_coat_vulva_centre", GEOMETRY.WINKING_OPENING)
		material.set_shader_parameter("body_coat_vulva_out", Vector3.BACK)
		material.set_shader_parameter("body_coat_vulva_scale", spread)
		material.set_shader_parameter("body_coat_vulva_reach", reach)
		material.set_shader_parameter("body_coat_vulva_depth", depth)
		material.set_shader_parameter("body_coat_vulva_hole", hole_radius)
		material.set_shader_parameter("body_coat_vulva_hole_height", hole_vertical)
		material.set_shader_parameter("body_coat_vulva_hole_up", Vector3.UP)
		material.set_shader_parameter("body_coat_vulva_hole_depth", hole_depth)
		material.set_shader_parameter("body_coat_vulva_hole_front", hole_front)
		material.set_shader_parameter("body_coat_vulva_hole_open", hole_open)
		material.set_shader_parameter("body_coat_still_centre", still_centre)
		material.set_shader_parameter("body_coat_still_radius", still_radius)
		material.set_shader_parameter("body_coat_still_right", Vector3.RIGHT)
		material.set_shader_parameter("body_coat_still_up", Vector3.UP)
		material.set_shader_parameter("body_coat_still_oval", SETTINGS.still_oval.get_num())
		material.set_shader_parameter("body_coat_still_fade", SETTINGS.still_fade.get_num())
	tick()


func _ensure_zone_debug() -> void:
	if is_instance_valid(_zone_debug) or not is_instance_valid(pony):
		return
	_zone_debug = STILL_ZONE_DEBUG.new()
	pony.add_child(_zone_debug)
	_zone_debug.setup()


## One patch log line per body/material state, so a form change speaks and a steady frame does
## not. A skipped patch is a warning, not a debug line.
func _log_once(text: String) -> void:
	if _patch_log == text:
		return
	_patch_log = text
	LOG.warning(text)


## A successful patch is a debug line, not a warning.
func _log_patch(text: String) -> void:
	if _patch_log == text:
		return
	_patch_log = text
	LOG.debug(text)
