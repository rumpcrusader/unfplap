extends Node
## Pantyhose & Panties world adapter: keeps worn panties and pantyhose clear of the optional
## anatomy, lets the cloth follow the rump wobble and starts each act undressed.
## Scope: world. It never preloads the entry or `runtime.gd` and never edits the pack.

const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const CUT_SHADER := preload("res://mods/unfplap/integrations/shaders/pantyhose_cut.gdshader")
const SHEER_SHADER := preload("res://mods/unfplap/integrations/shaders/pantyhose_sheer.gdshader")
## The per-node cloth jiggle; see `docs/integrations.md` (`## Pantyhose & Panties`).
const GARMENT_JIGGLE := preload("res://mods/unfplap/integrations/garment_jiggle.gd")

const MOD_ID := "pantyhose"
## The garment nodes are children of the body's parent, next to `MareBody`.
const PREFIXES := ["Wear_panties-", "Wear_pantyhose-"]
## The same two families as item kinds, so `wanted()` names the pieces to take off.
const KIND_PREFIXES := ["panties-", "pantyhose-"]
## How often the adapter re-discovers the worn nodes. The hull transform and instance uniforms
## update every frame; this only catches a new/removed garment.
const DISCOVER_S := 0.5
## A precision edit waits for the drag to settle before the one-time rebuild.
const REBUILD_DELAY_S := 0.3
## Runs after the coat's own `FlankTouch` pass, so the cloth reads this frame's wobble. A game
## change that delays `FlankTouch` must delay this too.
const PROCESS_PRIORITY := 100
## The debug heatmap sits this far in front of the field surface (anatomy-local metres).
const OVERLAY_Z_LIFT := 0.0015
const OVERLAY_ALPHA := 0.78
const PERF := preload("res://mods/unfplap/shared/perf.gd")


## One garment node's saved overrides, so a feature-off, a mod-off or a world close restores
## exactly what was there before this adapter wrote it.
class Applied:
	var mesh_id := 0
	var count := 0
	var originals: Array = []
	## True while the six cloth-jiggle uniforms are this adapter's, so every restore clears them.
	var jiggling := false


## Test seam for the pack-active check. Production sets it in `setup()`.
var mod_active := Callable()

var _game: Node
var _discover_clock := 0.0
var _undress: bool
var _bulge: bool
## The per-node cloth follower every worn node reads; it caches one pony's coat sample per pass.
var _jiggle := GARMENT_JIGGLE.new()
var _jiggle_enabled: bool
var _hull_width: int
var _hull_height: int
var _hull_smoothing: int
var _hull_margin_mm: float
var _hull_min_margin_mm: float
var _show_hull: bool
var _rebuild_at := -1.0
var _mismatch_logged := false

## garment node -> the pony it belongs to
var _tracked: Dictionary = {}
## garment node -> Applied
var _applied: Dictionary = {}
## original material instance id + variant -> compatibility material
var _materials: Dictionary = {}
## The debug heatmap. It is top-level and copies the anatomy transform, so a hidden anatomy
## still shows it.
var _overlay: MeshInstance3D
var _overlay_texture: Variant = null
var _overlay_parent: Node3D = null
var _overlay_reason := ""


func setup() -> void:
	process_priority = PROCESS_PRIORITY
	if mod_active.is_null():
		mod_active = Callable(self, "_mod_active")
	set_process(false)
	apply_live_settings()
	_connect_anatomy()
	CHANGE.on_changed(Callable(self, "apply_live_settings"))


## Called by the entry when the world is ready.
func on_world(host: Node) -> void:
	_game = host
	_discover_clock = 0.0
	_rebuild_at = -1.0
	_mismatch_logged = false
	_overlay_reason = ""
	set_process(true)
	_connect_anatomy()
	apply_live_settings()


## The host's world close. Restore every override before the game and its ponies go away.
func on_world_closed() -> void:
	_restore_all()
	_hide_overlay()
	_free_overlay()
	_materials.clear()
	_game = null
	_discover_clock = 0.0
	_rebuild_at = -1.0
	set_process(false)


## The entry node's teardown. Idempotent.
func shutdown() -> void:
	CHANGE.off_changed(Callable(self, "apply_live_settings"))
	on_world_closed()
	_disconnect_anatomy()


func _exit_tree() -> void:
	on_world_closed()


## Cache every setting this adapter reads. The settings change notification calls this on every
## edit; there is no per-frame settings read.
func apply_live_settings() -> void:
	_undress = SETTINGS.pantyhose_undress.get_bool()
	_bulge = SETTINGS.pantyhose_bulge.get_bool()
	_jiggle_enabled = SETTINGS.pantyhose_jiggle.get_bool()
	_hull_margin_mm = SETTINGS.pantyhose_hull_margin_mm.get_num()
	_hull_min_margin_mm = SETTINGS.pantyhose_hull_min_margin_mm.get_num()
	_show_hull = SETTINGS.pantyhose_hull_show.get_bool()
	var width := int(SETTINGS.pantyhose_hull_width.get_num())
	var height := int(SETTINGS.pantyhose_hull_height.get_num())
	var smoothing := int(SETTINGS.pantyhose_hull_smoothing.get_num())
	if width != _hull_width or height != _hull_height or smoothing != _hull_smoothing:
		_hull_width = width
		_hull_height = height
		_hull_smoothing = smoothing
		_queue_rebuild()
	if (not _bulge and not _jiggle_enabled) or not _mod_active_now():
		_restore_all()
	if not _show_hull:
		_hide_overlay()
	_overlay_reason = ""
	if is_instance_valid(_game):
		scan()


## The hull transform and every per-instance uniform update every frame. The worn nodes are
## re-discovered on a fixed fallback, not by a user setting.
func _process(delta: float) -> void:
	if not is_instance_valid(_game):
		return
	if _rebuild_at >= 0.0:
		_rebuild_at -= delta
		if _rebuild_at < 0.0:
			rebuild_hull()
	_update_overlay_transform()
	_update_garments()
	_discover_clock -= delta
	if _discover_clock <= 0.0:
		_discover_clock = DISCOVER_S
		_discover()
	var anatomy := _anatomy()
	var mares: Variant = _game.get("mares")
	if _show_hull and anatomy != null and mares is Array:
		_scan_overlay(mares, anatomy)
	else:
		_hide_overlay()


## One full pass, for the Rebuild action and the tests: re-discover the worn nodes and update
## the hull.
func scan() -> void:
	if not is_instance_valid(_game) or not _mod_active_now():
		_restore_all()
		_hide_overlay()
		return
	_discover()
	_update_garments()
	var anatomy := _anatomy()
	var mares: Variant = _game.get("mares")
	if _show_hull and anatomy != null and mares is Array:
		_scan_overlay(mares, anatomy)
	else:
		_hide_overlay()


## Rebuild the shared depth field after a precision edit or the debug Rebuild button. The
## build is one-time; `scan()` applies the new texture on the same call.
func rebuild_hull() -> String:
	if not is_instance_valid(_game) or not _mod_active_now():
		return "Pantyhose integration is inactive."
	var anatomy := _anatomy()
	if anatomy == null or not anatomy.has_method("garment_hull_rebuild"):
		return "No anatomy service."
	PERF.begin("garment_hull")
	anatomy.call("garment_hull_rebuild")
	scan()
	PERF.end("garment_hull")
	LOG.debug("[pantyhose] garment hull rebuilt")
	return "Garment hull rebuilt."


## True while the debug heatmap is shown. Headless runs never create it.
func overlay_active() -> bool:
	return is_instance_valid(_overlay) and _overlay.visible


# --------------------------------------------------------------------------- garment surfaces

## Worn nodes are tracked whenever the lift or the jiggle can use them, so a hidden anatomy, or one
## the player never shows, still gets the cloth wobble.
func _discover() -> void:
	if not is_instance_valid(_game) or not _mod_active_now():
		_restore_all()
		return
	var anatomy := _anatomy()
	var mares: Variant = _game.get("mares")
	var seen: Dictionary = {}
	if (anatomy != null or _jiggle_enabled) and mares is Array:
		for pony: Variant in mares:
			if not is_instance_valid(pony) or not (pony is Node3D):
				continue
			_discover_pony(pony as Node3D, seen)
	_drop_missing(seen)


func _discover_pony(pony: Node3D, seen: Dictionary) -> void:
	for prefix: String in PREFIXES:
		for node: Node in pony.find_children(prefix + "*", "", true, false):
			if not node is MeshInstance3D or node.is_queued_for_deletion():
				continue
			var mesh_node := node as MeshInstance3D
			seen[mesh_node] = true
			_tracked[mesh_node] = pony


## The every-frame pass: the hull transform and every instance uniform follow the anatomy, and a
## worn piece carries its pony's live flank wobble while the cloth-jiggle flag is on.
func _update_garments() -> void:
	if not is_instance_valid(_game) or not _mod_active_now():
		_restore_all()
		return
	if not _bulge and not _jiggle_enabled:
		_restore_all()
		return
	var anatomy := _anatomy()
	_jiggle.begin_frame()
	var nodes: Array = _tracked.keys()
	for node: Variant in nodes:
		if not is_instance_valid(node) or not node is MeshInstance3D:
			_tracked.erase(node)
			continue
		var mesh_node := node as MeshInstance3D
		var pony: Variant = _tracked.get(mesh_node)
		if not is_instance_valid(pony) or not (pony is Node3D):
			_tracked.erase(mesh_node)
			_restore_if_applied(mesh_node)
			continue
		var visible := _bulge and anatomy != null and anatomy.has_method("garment_visible") \
			and bool(anatomy.call("garment_visible", pony))
		var hull: Variant = null
		var xform := Transform3D.IDENTITY
		if visible:
			if anatomy.has_method("garment_hull"):
				hull = anatomy.call("garment_hull", pony)
			if hull != null and anatomy.has_method("garment_transform"):
				var value: Variant = anatomy.call("garment_transform", pony)
				if value is Transform3D:
					xform = value as Transform3D
		_apply_node(mesh_node, pony as Node3D, hull, xform)


## Gives the surfaces the compatibility override plus the lift values and, with the flag on, the
## pony's wobble. Restores the node when neither is needed.
func _apply_node(node: MeshInstance3D, pony: Node3D, hull: Variant, xform: Transform3D) -> void:
	if hull == null and not _jiggle_enabled:
		_restore_if_applied(node)
		return
	var mesh := node.mesh
	if mesh == null:
		_restore_if_applied(node)
		return
	var count := mesh.get_surface_count()
	var mesh_id := mesh.get_rid().get_id()
	var applied_value: Variant = _applied.get(node)
	if applied_value is Applied \
			and (applied_value.mesh_id != mesh_id or applied_value.count != count):
		_restore_node(node, applied_value)
		applied_value = null
	if not applied_value is Applied:
		var fresh := Applied.new()
		fresh.mesh_id = mesh_id
		fresh.count = count
		fresh.originals.resize(count)
		for i in count:
			fresh.originals[i] = node.get_surface_override_material(i)
		_applied[node] = fresh
		applied_value = fresh
	var applied := applied_value as Applied
	var texture: Variant = null
	var domain_vec := Vector4.ZERO
	var z_range := Vector2.ZERO
	if hull != null:
		var domain: Rect2 = hull.domain
		texture = hull.texture
		domain_vec = Vector4(domain.position.x, domain.position.y, domain.size.x, domain.size.y)
		z_range = Vector2(float(hull.z_min), float(hull.z_max))
	var any := false
	for i in count:
		var original := mesh.surface_get_material(i)
		var compat := _compat_material(original)
		if compat == null:
			var saved: Variant = applied.originals[i] if i < applied.originals.size() else null
			var fallback: Material = saved if saved is Material else null
			if node.get_surface_override_material(i) != fallback:
				node.set_surface_override_material(i, fallback)
			continue
		if hull != null:
			compat.set_shader_parameter("hull_texture", texture)
			compat.set_shader_parameter("hull_domain", domain_vec)
			compat.set_shader_parameter("hull_z_range", z_range)
		if node.get_surface_override_material(i) != compat:
			node.set_surface_override_material(i, compat)
		any = true
	if not any:
		_restore_node(node, applied)
		return
	if hull != null:
		var basis := xform.basis
		var inverse := Basis.IDENTITY
		if absf(basis.determinant()) > 0.0000001:
			inverse = basis.inverse()
		node.set_instance_shader_parameter("hull_on", 1.0)
		node.set_instance_shader_parameter("hull_origin", xform.origin)
		node.set_instance_shader_parameter("hull_basis_x", basis.x)
		node.set_instance_shader_parameter("hull_basis_y", basis.y)
		node.set_instance_shader_parameter("hull_basis_z", basis.z)
		node.set_instance_shader_parameter("hull_basis_inv_x", inverse.x)
		node.set_instance_shader_parameter("hull_basis_inv_y", inverse.y)
		node.set_instance_shader_parameter("hull_basis_inv_z", inverse.z)
		node.set_instance_shader_parameter("hull_margin", _margin_local(xform, _hull_margin_mm))
		node.set_instance_shader_parameter("hull_min_margin",
			_margin_local(xform, _hull_min_margin_mm))
	else:
		node.set_instance_shader_parameter("hull_on", 0.0)
	if _jiggle_enabled and _jiggle.sample(pony):
		_jiggle.apply(node)
		applied.jiggling = true
	elif applied.jiggling:
		GARMENT_JIGGLE.clear(node)
		applied.jiggling = false


## Millimetres as anatomy-local units. The shader scales the push back, so the slider reads
## world millimetres.
static func _margin_local(xform: Transform3D, millimetres: float) -> float:
	var scale := (xform.basis * Vector3(0.0, 0.0, 1.0)).length()
	return (millimetres / 1000.0) / maxf(scale, 0.0001)


func _restore_if_applied(node: MeshInstance3D) -> void:
	var applied: Variant = _applied.get(node)
	if applied is Applied:
		_restore_node(node, applied)


func _restore_node(node: Node, applied: Applied) -> void:
	_applied.erase(node)
	if not is_instance_valid(node) or not node is MeshInstance3D:
		return
	var mesh_node := node as MeshInstance3D
	# Clear the uniforms before the pack material returns; it lacks these names.
	mesh_node.set_instance_shader_parameter("hull_on", 0.0)
	if applied.jiggling:
		GARMENT_JIGGLE.clear(mesh_node)
		applied.jiggling = false
	var mesh := mesh_node.mesh
	if mesh == null:
		return
	var count := mini(applied.count, mesh.get_surface_count())
	for i in count:
		var saved: Variant = applied.originals[i] if i < applied.originals.size() else null
		mesh_node.set_surface_override_material(i, saved if saved is Material else null)


func _drop_missing(seen: Dictionary) -> void:
	var missing: Array = []
	for node: Variant in _tracked:
		if not is_instance_valid(node) or not seen.has(node):
			missing.append(node)
	for node: Variant in missing:
		_tracked.erase(node)
		var applied: Variant = _applied.get(node)
		if applied is Applied:
			_restore_node(node, applied)
		else:
			_applied.erase(node)


## Restore every override and forget the sampled wobble; the pack-off, feature-off and world-close
## path.
func _restore_all() -> void:
	_jiggle.reset()
	_tracked.clear()
	var nodes: Array = _applied.keys()
	for node: Variant in nodes:
		var applied: Variant = _applied.get(node)
		if is_instance_valid(node) and node is Node and applied is Applied:
			_restore_node(node, applied)
	_applied.clear()


# --------------------------------------------------------------------------- compatibility material

func _compat_material(original: Material) -> ShaderMaterial:
	if not original is ShaderMaterial:
		return null
	var source := original as ShaderMaterial
	var shader := source.shader
	if shader == null:
		return null
	var variant := _variant_of(shader)
	if variant.is_empty():
		if not _mismatch_logged:
			_mismatch_logged = true
			LOG.debug("[pantyhose] garment material is not the verified pantyhose shader; cloth left alone")
		return null
	var key := "%d|%s" % [source.get_instance_id(), variant]
	var cached: Variant = _materials.get(key)
	if cached is ShaderMaterial:
		return cached as ShaderMaterial
	var compat := ShaderMaterial.new()
	compat.shader = SHEER_SHADER if variant == "sheer" else CUT_SHADER
	compat.render_priority = source.render_priority
	var rows: Array = shader.get_shader_uniform_list()
	for row: Dictionary in rows:
		var name := str(row.get("name", ""))
		if name.is_empty() or name.begins_with("hull_"):
			continue
		var value: Variant = source.get_shader_parameter(name)
		if value != null:
			compat.set_shader_parameter(name, value)
	_materials[key] = compat
	return compat


## Which copied shader the original material needs. The 0.1.1 paths are the contract; the
## `edge_alpha` fallback keeps a renamed copy working.
static func _variant_of(shader: Shader) -> String:
	var path := shader.resource_path
	if path.ends_with("hosiery_sheer.gdshader") or path.ends_with("pantyhose_sheer.gdshader"):
		return "sheer"
	if path.ends_with("hosiery_cut.gdshader") or path.ends_with("pantyhose_cut.gdshader"):
		return "cut"
	var rows: Array = shader.get_shader_uniform_list()
	for row: Dictionary in rows:
		if str(row.get("name", "")) == "edge_alpha":
			return "sheer"
	return ""


# --------------------------------------------------------------------------- act undress

func _connect_anatomy() -> void:
	var anatomy := _anatomy()
	if anatomy == null or not anatomy.has_signal("act_started"):
		return
	if not anatomy.is_connected("act_started", _on_act_started):
		anatomy.connect("act_started", _on_act_started)


func _disconnect_anatomy() -> void:
	var anatomy := _anatomy()
	if anatomy == null or not anatomy.has_signal("act_started"):
		return
	if anatomy.is_connected("act_started", _on_act_started):
		anatomy.disconnect("act_started", _on_act_started)


## The act start: one `take_off` per worn kind, so dialogue records the undress; a missing
## director or executor falls back to the wardrobe calls.
func _on_act_started(pony: Node3D) -> void:
	if not _undress or not _mod_active_now():
		return
	if not is_instance_valid(_game) or not is_instance_valid(pony):
		return
	var tree := get_tree()
	if tree == null:
		return
	var wardrobe: Node = tree.get_first_node_in_group("pony_wardrobe")
	if wardrobe == null or not wardrobe.has_method("set_worn") or not wardrobe.has_method("dress") \
			or not wardrobe.has_method("wanted"):
		LOG.debug("[pantyhose] undress skipped: no pony wardrobe")
		return
	var identity: Variant = pony.get("identity")
	var id := str(identity.get("id")) if identity != null else ""
	if id.is_empty():
		LOG.debug("[pantyhose] undress skipped: no pony id")
		return
	var season: String = str(wardrobe.call("_season")) if wardrobe.has_method("_season") else "spring"
	var kinds := _worn_hosiery(wardrobe.call("wanted", id, season))
	if kinds.is_empty():
		return
	if _take_off_action(tree, id, kinds, wardrobe, season):
		LOG.debug("[pantyhose] undress %s (%s) through take_off", [id, ", ".join(kinds)])
		return
	for kind: String in kinds:
		wardrobe.call("set_worn", id, kind, false)
	wardrobe.call("dress", pony, id, season)
	LOG.debug("[pantyhose] undress %s (%s)", [id, ", ".join(kinds)])


## The worn kinds among `wanted()`'s `{kind: colour}` that are this pack's lower garments.
static func _worn_hosiery(worn: Variant) -> Array[String]:
	var kinds: Array[String] = []
	if not worn is Dictionary:
		return kinds
	for key: Variant in (worn as Dictionary).keys():
		var kind := str(key)
		for prefix: String in KIND_PREFIXES:
			if kind.begins_with(prefix):
				kinds.append(kind)
				break
	return kinds


## The `take_off` action her own reply would use, so its outcome reaches her prompt. False when
## it cannot run or the pieces survive, and the caller then takes the direct path.
func _take_off_action(tree: SceneTree, id: String, kinds: Array[String], wardrobe: Node,
		season: String) -> bool:
	var director: Node = tree.get_first_node_in_group("conversation_director")
	if director == null:
		return false
	var coordinator: Variant = director.get("actions")
	if not coordinator is Node or not is_instance_valid(coordinator) \
			or not (coordinator as Node).has_method("commit"):
		return false
	var executors: Variant = coordinator.get("executors")
	if not executors is Dictionary or not (executors as Dictionary).has(id):
		return false
	var turn_value: Variant = director.get("_turn_id")
	var turn: int = int(turn_value) if turn_value is int else 0
	var actions: Array = []
	for kind: String in kinds:
		actions.append({"id": "undress_" + kind, "type": "take_off", "kind": kind})
	var error := str(coordinator.call("commit", id, actions, {}, turn))
	if not error.is_empty():
		LOG.debug("[pantyhose] take_off refused: %s", [error])
		return false
	return _worn_hosiery(wardrobe.call("wanted", id, season)).is_empty()


# --------------------------------------------------------------------------- debug heatmap

func _scan_overlay(mares: Array, anatomy: Node) -> void:
	if DisplayServer.get_name() == "headless":
		_hide_overlay()
		return
	if not anatomy.has_method("garment_hull") or not anatomy.has_method("garment_parent"):
		_hide_overlay()
		_note_overlay_reason("no anatomy reads")
		return
	for pony: Variant in mares:
		if not is_instance_valid(pony) or not (pony is Node3D):
			continue
		# The anatomy may be hidden (far mesh or act mode); the field still exists, and the
		# heatmap is the debug way to inspect it. Only a detached controller has no parent/hull.
		var parent_value: Variant = anatomy.call("garment_parent", pony)
		if not parent_value is Node3D:
			continue
		var value: Variant = anatomy.call("garment_hull", pony)
		if value == null:
			continue
		_show_overlay(pony as Node3D, value, parent_value as Node3D)
		return
	_hide_overlay()
	_note_overlay_reason("no anatomy controller or hull")


func _show_overlay(pony: Node3D, hull: Variant, parent: Node3D) -> void:
	var overlay := _ensure_overlay()
	if overlay == null:
		return
	_overlay_parent = parent
	if overlay.get_parent() != self:
		if overlay.get_parent() != null:
			overlay.get_parent().remove_child(overlay)
		add_child(overlay)
	# The field lives in anatomy-mesh space; copy the transform rather than parenting, so a
	# hidden mesh leaves the heatmap visible.
	overlay.top_level = true
	overlay.global_transform = parent.global_transform
	if _overlay_texture != hull.texture:
		overlay.mesh = _hull_mesh(hull)
		_overlay_texture = hull.texture
	overlay.visible = overlay.mesh != null
	if overlay.visible:
		_note_overlay_reason("shown pony=%s res=%dx%d" % [pony.name, hull.resolution_x,
			hull.resolution_y])
	else:
		_note_overlay_reason("empty hull mesh")


func _ensure_overlay() -> MeshInstance3D:
	if is_instance_valid(_overlay):
		return _overlay
	_overlay = MeshInstance3D.new()
	_overlay.name = "UnfplapPantyhoseHull"
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(1.0, 1.0, 1.0, OVERLAY_ALPHA)
	material.render_priority = 10
	_overlay.material_override = material
	return _overlay


func _update_overlay_transform() -> void:
	if not is_instance_valid(_overlay) or not _overlay.visible:
		return
	if not is_instance_valid(_overlay_parent):
		_hide_overlay()
		return
	_overlay.global_transform = _overlay_parent.global_transform


func _hide_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.visible = false
	_overlay_texture = null
	_overlay_parent = null
	if _overlay_reason.begins_with("shown"):
		LOG.debug("[pantyhose] hull overlay hidden")
	_overlay_reason = ""


func _free_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_overlay_texture = null
	_overlay_parent = null
	_overlay_reason = ""


## Log the overlay state once per change. Debug logs only; the state changes rarely.
func _note_overlay_reason(reason: String) -> void:
	if _overlay_reason == reason:
		return
	_overlay_reason = reason
	LOG.debug("[pantyhose] hull overlay: %s", [reason])


## A continuous corner-grid surface coloured from blue (low) to red (high). The mesh is in the
## anatomy's local space; the overlay copies the anatomy mesh's global transform every frame.
func _hull_mesh(hull: Variant) -> ArrayMesh:
	var field: PackedFloat32Array = hull.field
	var domain: Rect2 = hull.domain
	var res_x: int = hull.resolution_x
	var res_y: int = hull.resolution_y
	if res_x <= 0 or res_y <= 0 or field.size() != res_x * res_y \
			or domain.size.x <= 0.0 or domain.size.y <= 0.0:
		return null
	var z_min: float = hull.z_min
	var z_max: float = hull.z_max
	var span := z_max - z_min
	var cell := Vector2(domain.size.x / float(res_x), domain.size.y / float(res_y))
	var stride := res_x + 1
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	# A shared corner grid: each corner takes the maximum of the up-to-four cells touching it, so
	# adjacent quads meet exactly instead of floating at different heights.
	var corners := PackedFloat32Array()
	corners.resize(stride * (res_y + 1))
	corners.fill(-1.0)
	for j in res_y + 1:
		for i in stride:
			var value := -1.0
			for dj in range(-1, 1):
				for di in range(-1, 1):
					var ci := i + di
					var cj := j + dj
					if ci < 0 or cj < 0 or ci >= res_x or cj >= res_y:
						continue
					var cell_value := field[cj * res_x + ci]
					if cell_value >= 0.0:
						value = maxf(value, cell_value)
			corners[j * stride + i] = value
	for j in res_y + 1:
		for i in stride:
			var value := maxf(corners[j * stride + i], 0.0)
			var x := domain.position.x + float(i) * cell.x
			var y := domain.position.y + float(j) * cell.y
			var z := z_min + value * span + OVERLAY_Z_LIFT
			vertices.append(Vector3(x, y, z))
			colors.append(Color(value, 0.25, 1.0 - value, OVERLAY_ALPHA))
	for j in res_y:
		for i in res_x:
			var a := j * stride + i
			var b := a + 1
			var c := a + stride + 1
			var d := a + stride
			if corners[a] < 0.0 or corners[b] < 0.0 \
					or corners[c] < 0.0 or corners[d] < 0.0:
				continue
			indices.append(a)
			indices.append(b)
			indices.append(c)
			indices.append(a)
			indices.append(c)
			indices.append(d)
	if indices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --------------------------------------------------------------------------- host

func _anatomy() -> Node:
	var value: Node = PONIES.anatomy
	if value is Node:
		return value as Node
	return null


func _mod_active() -> bool:
	if not is_inside_tree():
		return false
	var mods := get_node_or_null("/root/Mods")
	if mods == null or not mods.has_method("is_active"):
		return false
	return bool(mods.call("is_active", MOD_ID))


func _mod_active_now() -> bool:
	return not mod_active.is_null() and bool(mod_active.call())


func _queue_rebuild() -> void:
	if is_instance_valid(_game):
		_rebuild_at = REBUILD_DELAY_S


