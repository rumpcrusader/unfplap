extends Node
## Re-seats every adult mare's hair tail at the game's exact reference dock and moves the
## OpenPonyDock with it. One controller under main; it never touches the body, skeleton, mane or
## act systems.
##
## The reference is the body-space anchor of the game's reference dock, read from
## `dock_tail_mounts.json`. A per-mare exception under `anatomy.tail_seat.<id>` offsets only Y/Z.
## The controller caches every original before it writes, so turning the setting off restores the
## game's tail and dock exactly.

const SETTINGS := preload("res://mods/unfplap/settings.gd")
const PLACEMENT := preload("res://mods/unfplap/tail_seat_placement.gd")
const DOCK_TAIL_MOUNT := preload("res://world/characters/hybrid_mare/dock_tail_mount.gd")
const HYBRID_DOCK := preload("res://world/characters/hybrid_mare/hybrid_dock.gd")
const DOCK_SEAT := preload("res://mods/unfplap/dock_seat.gd")
const DOCK_ATTACH := preload("res://mods/unfplap/dock_attach.gd")
const HYBRID_FAR_MESH := preload("res://world/characters/hybrid_mare/hybrid_far_mesh.gd")

const DOCK_NAME := "OpenPonyDock"
const REFERENCE_PATH := "res://world/characters/hybrid_mare/dock_tail_mounts.json"
const DOCK_VISIBILITY_PATH := "res://world/characters/hybrid_mare/dock_visibility_fits.json"
## Mirrors `hybrid_dock.VISIBILITY_FALLBACK`: the median of the hand fits.
const DOCK_VISIBILITY_FALLBACK := Vector3(0.0, 0.0, 0.04)
## The reference's cap sits just below and in front of the body's own tail root. This fallback is
## the current game relation; the JSON reference wins whenever it is available.
const FALLBACK_TAIL_OFFSET := Vector3(0.0, -0.0044, -0.0235)
const MOVE_STEP := 0.005

var main: Node

## pony -> cached original values, target and live state. See `_prepare()`.
var _rows: Dictionary = {}
## Last applied values of Anatomy › Re-seat tails and docks and the two debug offsets.
var _enabled := true
var _tail_lift := 0.0
var _dock_lift := 0.0
static var _reference := Vector3.INF
static var _reference_loaded := false
static var _visibility: Dictionary = {}


func _ready() -> void:
	_enabled = SETTINGS.reseat_tails.get_bool()
	_tail_lift = SETTINGS.tail_offset_mm.get_num() / 1000.0
	_dock_lift = SETTINGS.dock_offset_mm.get_num() / 1000.0


## The game's exact reference anchor, in body mesh space. Falls back to the body tail root.
static func reference(pony: Node = null) -> Vector3:
	if not _reference_loaded:
		_reference_loaded = true
		if FileAccess.file_exists(REFERENCE_PATH):
			var parsed: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(REFERENCE_PATH))
			if parsed is Dictionary:
				var value: Variant = (parsed as Dictionary).get("reference")
				if value is Array and (value as Array).size() == 3:
					var point := Vector3(float(value[0]), float(value[1]), float(value[2]))
					if point.is_finite():
						_reference = point
	if _reference.is_finite():
		return _reference
	if is_instance_valid(pony):
		var skeleton: Variant = pony.get("skeleton")
		if skeleton is Skeleton3D:
			var bone := (skeleton as Skeleton3D).find_bone("pony_tail_01")
			if bone >= 0:
				return (skeleton as Skeleton3D).get_bone_global_rest(bone).origin \
					+ FALLBACK_TAIL_OFFSET
	return Vector3.INF


## Vertical centre of the pinned hair tail cap in body bind space. The dock's outer opening is
## seated on this line, which is what makes the visible band sit under the tail base instead of on
## its upper side. Returns NAN when the cap cannot be measured.
static func _tail_cap_centre(pony: Node) -> float:
	if not is_instance_valid(pony):
		return NAN
	var identity: Variant = pony.get("identity")
	var hair_node: Variant = pony.get("hair")
	if identity == null or not is_instance_valid(hair_node):
		return NAN
	var body: MeshInstance3D = pony.get("_model").find_child("MareBody", true, false) \
		as MeshInstance3D
	var tail: MeshInstance3D = (hair_node as Node).find_child(
		str(identity.get("hair_prefix")) + "DevkitTail", true, false) as MeshInstance3D
	if not is_instance_valid(body) or not is_instance_valid(tail):
		return NAN
	var link: Variant = pony.get("hair_link")
	var transform: Transform3D = _bind_for(body, "pony_hips").affine_inverse() \
		* link.get("pelvis_offset") * _bind_for(tail, "mPelvis")
	var low := INF
	var high := -INF
	var count := 0
	for surface in tail.mesh.get_surface_count():
		var vertices: PackedVector3Array = tail.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for i: int in tail.mesh.get_meta("pinned_" + str(surface), PackedInt32Array()):
			var y: float = (transform * vertices[i]).y
			low = minf(low, y)
			high = maxf(high, y)
			count += 1
	return (low + high) * 0.5 if count > 0 else NAN


## A skinned mesh's skeleton path, including a hidden rig mesh that lends its skeleton while
## parked (`hybrid_mare.set_rig_parking`). Mirrors `dock_tail_mount.bind_for`.
static func _bind_for(mesh: MeshInstance3D, bone_name: String) -> Transform3D:
	var sk: Skeleton3D = mesh.get_node(mesh.get_meta(&"parked_skeleton", mesh.skeleton)) \
		as Skeleton3D
	for i in mesh.skin.get_bind_count():
		var bone := sk.find_bone(mesh.skin.get_bind_name(i))
		if bone < 0:
			bone = mesh.skin.get_bind_bone(i)
		if sk.get_bone_name(bone) == bone_name:
			return mesh.skin.get_bind_pose(i)
	return Transform3D.IDENTITY


## The per-mare visibility offset `hybrid_dock.effective_fit()` adds to the reference fit, so the
## seat can remove it. Zero when the user has a custom dock fit or the mare is Rainbow Dash.
static func _visibility_offset(pony: Node, fit: Dictionary) -> Vector3:
	if not is_instance_valid(pony):
		return Vector3.ZERO
	if _visibility.is_empty():
		if not FileAccess.file_exists(DOCK_VISIBILITY_PATH):
			return Vector3.ZERO
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(DOCK_VISIBILITY_PATH))
		if not parsed is Dictionary:
			return Vector3.ZERO
		_visibility = parsed
	var reference_fit: Variant = _visibility.get("reference_fit")
	if not reference_fit is Dictionary or not HYBRID_DOCK.same_fit(fit, reference_fit):
		return Vector3.ZERO
	var identity: Variant = pony.get("identity")
	if identity == null or str(identity.get("id")) == "rainbow_dash":
		return Vector3.ZERO
	var offsets: Variant = _visibility.get("offsets")
	if offsets is Dictionary and (offsets as Dictionary).has(str(identity.get("id"))):
		var raw: Variant = (offsets as Dictionary)[str(identity.get("id"))]
		if raw is Array and (raw as Array).size() == 3:
			return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	if bool(identity.get("filly")):
		return Vector3.ZERO
	return DOCK_VISIBILITY_FALLBACK


## Called by main when a pony is ready. Idempotent.
func attach(pony: Node) -> void:
	if not is_instance_valid(pony) or _rows.has(pony) or not _eligible(pony):
		return
	var row := _prepare(pony)
	if row.is_empty():
		return
	_rows[pony] = row
	pony.tree_exiting.connect(func() -> void: _rows.erase(pony))
	_apply(row)
	_log("tail seat %s anchor=(%.3f,%.3f,%.3f) delta=(%.3f,%.3f,%.3f)" % [
		str(row["id"]), (row["anchor"] as Vector3).x, (row["anchor"] as Vector3).y,
		(row["anchor"] as Vector3).z, (row["applied"] as Vector3).x,
		(row["applied"] as Vector3).y, (row["applied"] as Vector3).z])


## Re-apply or restore every live pony. Called on every settings edit; only the toggle and a
## changed saved exception cause a write.
func refresh_all() -> void:
	var enabled := SETTINGS.reseat_tails.get_bool()
	var tail_lift := SETTINGS.tail_offset_mm.get_num() / 1000.0
	var dock_lift := SETTINGS.dock_offset_mm.get_num() / 1000.0
	var toggle_changed := enabled != _enabled
	var offsets_changed := not is_equal_approx(tail_lift, _tail_lift) \
		or not is_equal_approx(dock_lift, _dock_lift)
	_enabled = enabled
	_tail_lift = tail_lift
	_dock_lift = dock_lift
	for pony: Variant in _rows.keys():
		if not is_instance_valid(pony):
			_rows.erase(pony)
			continue
		var row: Dictionary = _rows[pony]
		var changed := toggle_changed or offsets_changed
		if not bool(row["dirty"]):
			var saved: Vector2 = SETTINGS.tail_seat_offset(str(row["id"]))
			if not PLACEMENT.same(saved, row["offset"] as Vector2):
				row["offset"] = saved
				changed = true
		if changed:
			_apply(row)


## Move, save or reset the pointed mare's exception. Returns the status line.
func place(pony: Node, op: String, value := MOVE_STEP) -> String:
	if not is_instance_valid(pony) or not _rows.has(pony):
		return "No tail-seat pony targeted."
	if not SETTINGS.reseat_tails.get_bool():
		return "Re-seat tails and docks is off."
	var row: Dictionary = _rows[pony]
	var offset: Vector2 = row["offset"]
	match op:
		"up":
			offset.x += value
		"down":
			offset.x -= value
		"forward":
			offset.y -= value
		"back":
			offset.y += value
		"save":
			SETTINGS.save_tail_seat_offset(str(row["id"]), offset)
			row["dirty"] = false
			_apply(row)
			return "%s saved" % _text(row)
		"reset":
			offset = Vector2.ZERO
		"text":
			return _text(row)
		_:
			return _text(row)
	row["offset"] = offset
	row["dirty"] = true
	_apply(row)
	return _text(row)


## Log every live mare's original seat, target and source; return a short summary.
func report_all() -> String:
	var lines := PackedStringArray()
	var count := 0
	var exceptions := 0
	var tail_lift := SETTINGS.tail_offset_mm.get_num() / 1000.0
	var dock_lift := SETTINGS.dock_offset_mm.get_num() / 1000.0
	for pony: Variant in _rows.keys():
		if not is_instance_valid(pony):
			_rows.erase(pony)
			continue
		var row: Dictionary = _rows[pony]
		var target := PLACEMENT.target(reference(pony), row["offset"] as Vector2, tail_lift)
		var source := _source(row)
		lines.append("%s anchor=(%.3f,%.3f,%.3f) target=(%.3f,%.3f,%.3f) %s applied=(%.3f,%.3f,%.3f) source=%s" % [
			str(row["id"]), (row["anchor"] as Vector3).x, (row["anchor"] as Vector3).y,
			(row["anchor"] as Vector3).z, target.x, target.y, target.z,
			PLACEMENT.text(row["offset"] as Vector2), (row["applied"] as Vector3).x,
			(row["applied"] as Vector3).y, (row["applied"] as Vector3).z, source])
		count += 1
		if source == "override" or source == "unsaved":
			exceptions += 1
	if not lines.is_empty():
		_log("tail seats tail_offset=%+.0fmm dock_offset=%+.0fmm\n\t" % [
			tail_lift * 1000.0, dock_lift * 1000.0] + "\n\t".join(lines))
	return "tail seats: %d live, %d exceptions (see log)" % [count, exceptions]


func _exit_tree() -> void:
	for pony: Variant in _rows.keys():
		if is_instance_valid(pony):
			_restore(_rows[pony] as Dictionary)
	_rows.clear()


func _eligible(pony: Node) -> bool:
	var identity: Variant = pony.get("identity")
	if identity == null or bool(identity.get("filly")) or bool(identity.get("stallion")):
		return false
	if pony.name == "PlayerPony" or is_instance_valid(pony.get("rig")):
		return false
	var hair: Variant = pony.get("hair_skeleton")
	var skeleton: Variant = pony.get("skeleton")
	if not hair is Skeleton3D or not skeleton is Skeleton3D:
		return false
	var link: Variant = pony.get("hair_link")
	if not is_instance_valid(link) or not link.get("pelvis_offset") is Transform3D:
		return false
	var dock: Variant = pony.find_child(DOCK_NAME, true, false)
	return dock is MeshInstance3D and (dock as MeshInstance3D).mesh != null


## Cache every value the controller needs before its first write. Empty when the pony cannot be
## measured; the controller then leaves her alone.
func _prepare(pony: Node) -> Dictionary:
	var link: Node = pony.get("hair_link") as Node
	var skeleton: Skeleton3D = pony.get("skeleton") as Skeleton3D
	var dock: MeshInstance3D = pony.find_child(DOCK_NAME, true, false) as MeshInstance3D
	var hips := skeleton.find_bone("pony_hips")
	var measured: Dictionary = DOCK_TAIL_MOUNT.measure(pony)
	var raw: Variant = measured.get("anchor")
	if hips < 0 or not raw is Array or (raw as Array).size() != 3:
		_log("tail seat: no anchor for %s" % pony.name)
		return {}
	var anchor := Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	if not anchor.is_finite():
		_log("tail seat: non-finite anchor for %s" % pony.name)
		return {}
	var fit: Dictionary = HYBRID_DOCK.effective_fit(pony, HYBRID_DOCK.read_fit())
	# `effective_fit()` also applies the per-mare visibility offset (up to +60 mm back) that was
	# fitted for the mare's *own* tail. The seat already moves her tail to the reference anchor,
	# so that offset puts the cuff above and behind the tail base: the sliver that read as "dock
	# above tail". Keep the tail-mount part (the seat delta cancels it) and drop the visibility
	# part.
	var visible := _visibility_offset(pony, HYBRID_DOCK.read_fit())
	if visible != Vector3.ZERO:
		var position: Variant = fit.get("position")
		if position is Array and (position as Array).size() == 3:
			fit["position"] = [
				float(position[0]) - visible.x,
				float(position[1]) - visible.y,
				float(position[2]) - visible.z,
			]
	if fit.is_empty():
		_log("tail seat: no dock fit for %s" % pony.name)
		return {}
	var identity: Variant = pony.get("identity")
	var hair: Skeleton3D = pony.get("hair_skeleton") as Skeleton3D
	var original_skin: Skin = dock.skin
	return {
		"pony": pony,
		"id": str(identity.get("id")),
		"body": "stallion" if bool(identity.get("stallion")) else "mare",
		"link": link,
		"dock": dock,
		"body_sk": skeleton,
		"hair_sk": hair,
		"original_pelvis": link.get("pelvis_offset") as Transform3D,
		"original_dock": dock.mesh,
		"original_skin": original_skin,
		"original_material": dock.get_surface_override_material(0),
		"hips_rest": skeleton.get_bone_global_rest(hips),
		"anchor": anchor,
		"cap_centre": _tail_cap_centre(pony),
		"fit": fit.duplicate(true),
		"offset": SETTINGS.tail_seat_offset(str(identity.get("id"))),
		"attached": null,
		"applied": Vector3.ZERO,
		"dirty": false,
	}


func _apply(row: Dictionary) -> void:
	var pony: Node = row.get("pony") as Node
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		return
	if not SETTINGS.reseat_tails.get_bool():
		_restore(row)
		return
	var reference_anchor := reference(pony)
	if not reference_anchor.is_finite():
		return
	var tail_lift := SETTINGS.tail_offset_mm.get_num() / 1000.0
	var delta := PLACEMENT.delta(row["anchor"] as Vector3, reference_anchor,
		row["offset"] as Vector2, tail_lift)
	var link: Node = row["link"]
	if not is_instance_valid(link) or not link.is_inside_tree():
		return
	var next: Transform3D = row["original_pelvis"]
	next.origin += (row["hips_rest"] as Transform3D).basis.inverse() * delta
	link.set("pelvis_offset", next)
	if link.has_method("_body_updated"):
		link.call("_body_updated")
	_move_dock(row, delta)
	row["applied"] = delta
	_invalidate_far(pony)


func _restore(row: Dictionary) -> void:
	var pony: Node = row.get("pony") as Node
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		return
	var link: Node = row["link"]
	if is_instance_valid(link) and link.is_inside_tree():
		link.set("pelvis_offset", row["original_pelvis"])
		if link.has_method("_body_updated"):
			link.call("_body_updated")
	_detach_follower(row)
	var dock: MeshInstance3D = row["dock"]
	if is_instance_valid(dock):
		dock.mesh = row["original_dock"]
		dock.skin = row["original_skin"]
		dock.set_surface_override_material(0, row["original_material"])
	row["applied"] = Vector3.ZERO
	_invalidate_far(pony)


## Place the dock in its fitted/snapped cuff position, then let the tail-only follower carry it
## with the hair tail root. The fit is captured before the first write, so repeated nudges rebuild
## from the game's original fit instead of accumulating.
func _move_dock(row: Dictionary, delta: Vector3) -> void:
	var dock: MeshInstance3D = row["dock"]
	if not is_instance_valid(dock):
		return
	var fit: Dictionary = (row["fit"] as Dictionary).duplicate(true)
	var position: Variant = fit.get("position")
	if not position is Array or (position as Array).size() != 3:
		return
	fit["position"] = [
		float(position[0]) + delta.x,
		float(position[1]) + delta.y,
		float(position[2]) + delta.z,
	]
	var fitted: ArrayMesh = HYBRID_DOCK.fitted_mesh(fit, false)
	var mesh: ArrayMesh = HYBRID_DOCK.reach_rump(fitted, row["pony"] as Node, false)
	if mesh == null:
		return
	mesh = DOCK_SEAT.snap_base(mesh, str(row["body"]))
	if mesh != null:
		dock.mesh = mesh
		_install_follower(row, mesh, delta)


func _install_follower(row: Dictionary, mesh: ArrayMesh, delta: Vector3) -> void:
	_detach_follower(row)
	var dock: MeshInstance3D = row["dock"]
	var hair: Skeleton3D = row["hair_sk"]
	var body: Skeleton3D = row["body_sk"]
	if not is_instance_valid(dock) or not is_instance_valid(hair) or not is_instance_valid(body):
		return
	dock.skin = null
	dock.set_surface_override_material(0, _dock_material(row))
	var follower: SkeletonModifier3D = DOCK_ATTACH.new()
	follower.name = "UnfplapDockAttach"
	follower.set("pony", row["pony"])
	follower.set("dock", dock)
	follower.set("body", body)
	follower.set("hair", hair)
	follower.set("rest_mesh", mesh)
	# Seat the dock's outer opening on the tail cap's centre line. `mesh` is already moved by the
	# seat delta, so subtract that delta before comparing it with the cap measured in the mare's
	# own pre-seat frame. The Anatomy Dock offset trims it from there.
	var top := mesh.get_aabb().end.y - delta.y
	var drop := float(row.get("cap_centre", NAN)) - top
	if not is_finite(drop):
		drop = 0.0
	follower.set("dock_lift", drop + SETTINGS.dock_offset_mm.get_num() / 1000.0)
	hair.add_child(follower)
	row["attached"] = follower


## The dock's chosen colour. Genitals uses a copy of the live anatomy material, recoloured so the
## cuff matches her genital skin tone; otherwise the game's original coat material is kept.
func _dock_material(row: Dictionary) -> Material:
	if SETTINGS.dock_color.get_choice() == "genitals":
		var pony: Node = row.get("pony") as Node
		if is_instance_valid(pony):
			var skeleton: Variant = pony.get("skeleton")
			if skeleton is Skeleton3D:
				var anatomy := (skeleton as Skeleton3D).find_child(
					"UnfplapAnatomy", true, false) as MeshInstance3D
				if is_instance_valid(anatomy) and not anatomy.is_queued_for_deletion():
					var base := anatomy.get_active_material(0)
					if base is ShaderMaterial:
						# The anatomy material is shared with the vulva; a copy keeps the dock's
						# recolour and the shader reset away from it. The main material never sets
						# `coat_color` (only the teats copy does), so a direct reuse is black:
						# the dock's missing COLOR leaves `to_coat` at 1.
						var dock := (base as ShaderMaterial).duplicate() as ShaderMaterial
						var skin: Variant = base.get_shader_parameter("skin_color")
						var shadow: Variant = base.get_shader_parameter("skin_shadow")
						if skin is Color:
							dock.set_shader_parameter("coat_color", skin)
						if shadow is Color:
							dock.set_shader_parameter("coat_shadow", shadow)
						dock.set_shader_parameter("fold_coloring", 0.0)
						dock.set_shader_parameter("contour_amount", 0.0)
						return dock
	var original: Variant = row.get("original_material")
	return original as Material if original is Material else null


## Re-apply the chosen dock material after the anatomy attaches, changes or detaches.
func refresh_dock_color(pony: Node) -> void:
	if not is_instance_valid(pony) or not _rows.has(pony):
		return
	var row: Dictionary = _rows[pony]
	var dock: MeshInstance3D = row["dock"]
	if is_instance_valid(dock):
		dock.set_surface_override_material(0, _dock_material(row))


func _detach_follower(row: Dictionary) -> void:
	var follower: Variant = row.get("attached")
	row["attached"] = null
	if not is_instance_valid(follower):
		return
	var parent: Node = (follower as Node).get_parent()
	if is_instance_valid(parent):
		parent.remove_child(follower)
	(follower as Node).queue_free()


func _invalidate_far(pony: Node) -> void:
	if not is_instance_valid(pony):
		return
	var key := HYBRID_FAR_MESH._id(pony)
	HYBRID_FAR_MESH.cache.erase(key)
	HYBRID_FAR_MESH.shadow_cache.erase(key)
	HYBRID_FAR_MESH.eyes_cache.erase(key)
	if bool(pony.get("_far_mesh_shown")) and pony.is_inside_tree() \
			and pony.has_method("set_near_mesh"):
		pony.call("set_near_mesh", true)


func _source(row: Dictionary) -> String:
	if not SETTINGS.reseat_tails.get_bool():
		return "off"
	if bool(row["dirty"]):
		return "unsaved"
	if SETTINGS.tail_seat_has_override(str(row["id"])):
		return "override"
	return "auto"


func _text(row: Dictionary) -> String:
	return "%s source=%s" % [PLACEMENT.text(row["offset"] as Vector2), _source(row)]


func _log(text: String) -> void:
	if is_instance_valid(main) and main.has_method("_debug"):
		main.call("_debug", text)
