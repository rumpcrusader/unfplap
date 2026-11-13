extends Node
## Re-seats every adult mare's hair tail at the game's exact reference dock and moves the
## OpenPonyDock with it. One controller under the anatomy facade; it never touches the body,
## skeleton, mane or act systems. Mares from other mods use the game's tail seat and the global
## placement until a per-mare override is saved.
##
## The reference is the body-space anchor of the game's reference dock, read from
## `dock_tail_mounts.json`. The per-mare row under `anatomy.placement.<id>` moves the tail, trims
## and scales the dock and tilts the tail about the body's rear axis. The controller caches every
## original before it writes, so turning the setting off restores the game's tail and dock exactly.
##
## Nothing is measured or written while the setting is off: the row then holds only the mare's id,
## so a disabled seat costs one dictionary entry per pony. A placement edit writes the tail at
## once and the skinned dock follows it; the dock mesh is rebuilt once per settled edit, not once
## per settings tick.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const DOCK_TAIL_MOUNT := preload("res://world/characters/hybrid_mare/dock_tail_mount.gd")
const HYBRID_DOCK := preload("res://world/characters/hybrid_mare/hybrid_dock.gd")
const DOCK_SEAT := preload("res://mods/unfplap/anatomy/tail/dock_seat.gd")
const DOCK_ATTACH := preload("res://mods/unfplap/anatomy/tail/dock_attach.gd")
const HYBRID_FAR_MESH := preload("res://world/characters/hybrid_mare/hybrid_far_mesh.gd")
const ANATOMY_PLACEMENT := preload("res://mods/unfplap/shared/anatomy_placement.gd")

const DOCK_NAME := "OpenPonyDock"
const REFERENCE_PATH := "res://world/characters/hybrid_mare/dock_tail_mounts.json"
## The reference's cap sits just below and in front of the body's own tail root. This fallback is
## the current game relation; the JSON reference wins whenever it is available.
const FALLBACK_TAIL_OFFSET := Vector3(0.0, -0.0044, -0.0235)
## A placement edit writes the tail at once and the skinned dock follows it; the dock mesh is
## rebuilt once this long after the last edit, because only the base-ring snap needs it.
const DOCK_SETTLE_S := 0.12
## The per-mare placement keys and their defaults, compared in `refresh_all()`.
const PLACEMENT_KEYS := [["tail_y", 0.0], ["tail_z", 0.0], ["dock_y", 0.0],
	["dock_scale", 1.0], ["tail_tilt_deg", 0.0]]

var perf_on := Callable()
var log := Callable()
## The anatomy facade's capability answer for this pony (identity + tail participation).
var eligible := Callable()

## pony -> cached original values, target and live state. See `_prepare()`.
var _rows: Dictionary = {}
## Last applied values of Anatomy › Re-seat tails and docks and the two debug offsets.
var _enabled := true
static var _reference := Vector3.INF
static var _reference_loaded := false
var _perf_window := 0.0
## Rows whose dock mesh is stale after a placement edit; rebuilt when the settle timer fires.
var _dirty: Array[Dictionary] = []
var _settle: Timer


func _ready() -> void:
	_enabled = SETTINGS.reseat_tails.get_bool()
	_settle = Timer.new()
	_settle.name = "UnfplapTailSeatSettle"
	_settle.one_shot = true
	_settle.wait_time = DOCK_SETTLE_S
	_settle.timeout.connect(_flush_dirty)
	add_child(_settle)
	set_process(_perf_on())


func _process(delta: float) -> void:
	if not _perf_on():
		_perf_window = 0.0
		return
	_perf_window += delta
	if _perf_window < 1.0:
		return
	_perf_window = 0.0
	_log_perf()


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


## Called by main when a pony is ready. Idempotent.
func attach(pony: Node) -> void:
	if not is_instance_valid(pony) or _rows.has(pony) or not _eligible(pony):
		return
	if not SETTINGS.reseat_tails.get_bool():
		# Off writes nothing: remember her so turning the setting on can seat her without a
		# respawn, but never measure her tail or rebuild her dock for a disabled feature.
		_rows[pony] = {"pony": pony, "id": _id_for(pony), "seated": false}
		pony.tree_exiting.connect(func() -> void: _forget(pony))
		return
	var started := Time.get_ticks_usec()
	var row := _prepare(pony)
	if row.is_empty():
		return
	var prepared := Time.get_ticks_usec()
	_rows[pony] = row
	pony.tree_exiting.connect(func() -> void: _forget(pony))
	_apply(row)
	var done := Time.get_ticks_usec()
	if _perf_on():
		var dock: Variant = row.get("dock")
		var verts := 0
		if is_instance_valid(dock) and (dock as MeshInstance3D).mesh != null:
			var arrays: Array = (dock as MeshInstance3D).mesh.surface_get_arrays(0)
			if arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				verts = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		_log("tail perf attach %s prepare=%dus apply=%dus verts=%d" % [
			str(row["id"]), prepared - started, done - prepared, verts])
	_log("tail seat %s anchor=(%.3f,%.3f,%.3f) delta=(%.3f,%.3f,%.3f)" % [
		str(row["id"]), (row["anchor"] as Vector3).x, (row["anchor"] as Vector3).y,
		(row["anchor"] as Vector3).z, (row["applied"] as Vector3).x,
		(row["applied"] as Vector3).y, (row["applied"] as Vector3).z])


## Re-apply or restore every live pony. Called on every settings edit; only the toggle, a
## changed saved exception or a changed placement causes a write.
func refresh_all() -> void:
	var enabled := SETTINGS.reseat_tails.get_bool()
	var toggle_changed := enabled != _enabled
	_enabled = enabled
	set_process(_perf_on())
	var started := Time.get_ticks_usec()
	var checked := 0
	var rebuilt := 0
	for pony: Variant in _rows.keys():
		if not is_instance_valid(pony):
			_forget(pony)
			continue
		var row: Dictionary = _rows[pony]
		if not enabled:
			# Only the toggle itself restores; a settings tick with the seat already off writes
			# nothing, and the row keeps her id for the next toggle.
			if toggle_changed and _seated(row):
				_restore(row)
			continue
		if not _eligible(pony):
			if _seated(row):
				_restore(row)
			_forget(pony)
			continue
		if not _seated(row):
			# She arrived while the seat was off; measure her now that it is on.
			var prepared := _prepare(pony)
			if prepared.is_empty():
				continue
			_rows[pony] = prepared
			_apply(prepared)
			checked += 1
			rebuilt += 1
			continue
		checked += 1
		if toggle_changed:
			_apply(row)
			rebuilt += 1
			continue
		var placement := SETTINGS.anatomy_placement(str(row["id"]))
		var changed := false
		var tail_moved := false
		var dock_stale := false
		for pair: Array in PLACEMENT_KEYS:
			var key := str(pair[0])
			var value := float(placement.get(key, pair[1]))
			if is_equal_approx(value, float(row.get(key, pair[1]))):
				continue
			row[key] = value
			changed = true
			match key:
				"dock_y":
					# A post-skin lift on the dock instance transform: no mesh rebuild.
					pass
				"dock_scale":
					dock_stale = true
				_:
					# The tail moved, and the base-ring snap follows it.
					tail_moved = true
					dock_stale = true
		if not changed:
			continue
		if tail_moved:
			_apply_tail(row)
		if dock_stale:
			_mark_dirty(row)
		else:
			_apply_lift(row)
		rebuilt += 1
	if _perf_on() and rebuilt > 0:
		_log("tail perf refresh checked=%d rebuilt=%d usec=%d" % [
			checked, rebuilt, Time.get_ticks_usec() - started])

## Log every live mare's seat and the resolved placement; return a short summary.
func report_all() -> String:
	var lines := PackedStringArray()
	var count := 0
	var exceptions := 0
	for pony: Variant in _rows.keys():
		if not is_instance_valid(pony):
			_forget(pony)
			continue
		var row: Dictionary = _rows[pony]
		if not _seated(row):
			continue
		var placement := SETTINGS.anatomy_placement(str(row["id"]))
		var reference_anchor := reference(pony)
		var target := reference_anchor + Vector3(0.0, float(placement.get("tail_y", 0.0)),
			float(placement.get("tail_z", 0.0)))
		var source := _source(row)
		lines.append("%s anchor=(%.3f,%.3f,%.3f) target=(%.3f,%.3f,%.3f) %s applied=(%.3f,%.3f,%.3f) source=%s" % [
			str(row["id"]), (row["anchor"] as Vector3).x, (row["anchor"] as Vector3).y,
			(row["anchor"] as Vector3).z, target.x, target.y, target.z,
			ANATOMY_PLACEMENT.text(placement), (row["applied"] as Vector3).x,
			(row["applied"] as Vector3).y, (row["applied"] as Vector3).z, source])
		count += 1
		if source == "override":
			exceptions += 1
	if not lines.is_empty():
		var base := SETTINGS.anatomy_placement_draft_values()
		_log("tail seats default %s\n\t%s" % [ANATOMY_PLACEMENT.text(base),
			"\n\t".join(lines)])
	return "tail seats: %d live, %d exceptions (see log)" % [count, exceptions]

func _exit_tree() -> void:
	for pony: Variant in _rows.keys():
		if is_instance_valid(pony):
			_restore(_rows[pony] as Dictionary)
	_rows.clear()
	_dirty.clear()


## True for a row `_prepare()` measured. A row created while the setting is off holds only her id
## and is prepared when the setting is turned back on.
func _seated(row: Dictionary) -> bool:
	return bool(row.get("seated", false))


## Drop a pony from the row set and from the pending settle pass.
func _forget(pony: Variant) -> void:
	_rows.erase(pony)
	for index in range(_dirty.size() - 1, -1, -1):
		if _dirty[index].get("pony") == pony:
			_dirty.remove_at(index)


func _eligible(pony: Node) -> bool:
	if eligible.is_null() or not bool(eligible.call(pony)):
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


## The mod's stable id for a pony: relationship metadata first, then the identity.
func _id_for(pony: Node) -> String:
	var meta_id := str(pony.get_meta("relationship_id", ""))
	if not meta_id.is_empty():
		return meta_id
	var identity: Variant = pony.get("identity")
	return str(identity.get("id")) if identity != null else ""


## True when the tail/dock placement can ever move this pony, even while the seat is toggled off.
func can_seat(pony: Node) -> bool:
	return is_instance_valid(pony) and _eligible(pony)


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
	# `effective_fit()` adds the game's seat shift for a seated tail; the seat delta below cancels
	# it, so the dock keeps the player's fit.
	var fit: Dictionary = HYBRID_DOCK.effective_fit(pony, HYBRID_DOCK.read_fit())
	if fit.is_empty():
		_log("tail seat: no dock fit for %s" % pony.name)
		return {}
	var identity: Variant = pony.get("identity")
	var id := str(pony.get_meta("relationship_id", ""))
	if id.is_empty():
		id = str(identity.get("id"))
	var placement := SETTINGS.anatomy_placement(id)
	var hair: Skeleton3D = pony.get("hair_skeleton") as Skeleton3D
	var original_skin: Skin = dock.skin
	# A far pony's dock may be parked by the game's rig parking: the path is empty and the real
	# one is in `parked_skeleton`. Cache the resolved path so `_restore()` always puts it back.
	var original_skeleton: NodePath = dock.skeleton
	if original_skeleton.is_empty() and dock.has_meta(&"parked_skeleton"):
		original_skeleton = dock.get_meta(&"parked_skeleton")
	return {
		"pony": pony,
		"id": id,
		"body": "stallion" if bool(identity.get("stallion")) else "mare",
		"link": link,
		"dock": dock,
		"body_sk": skeleton,
		"hair_sk": hair,
		"original_pelvis": link.get("pelvis_offset") as Transform3D,
		"original_dock": dock.mesh,
		"original_skin": original_skin,
		"original_material": dock.get_surface_override_material(0),
		"original_parent": dock.get_parent(),
		"original_transform": dock.transform,
		"original_skeleton": original_skeleton,
		"hips_rest": skeleton.get_bone_global_rest(hips),
		"anchor": anchor,
		"cap_centre": _tail_cap_centre(pony),
		"fit": fit.duplicate(true),
		"tail_y": float(placement.get("tail_y", 0.0)),
		"tail_z": float(placement.get("tail_z", 0.0)),
		"dock_y": float(placement.get("dock_y", 0.0)),
		"dock_scale": float(placement.get("dock_scale", 1.0)),
		"tail_tilt_deg": float(placement.get("tail_tilt_deg", 0.0)),
		"seated": true,
		"attached": false,
		"drop": 0.0,
		"builds": 0,
		"applied": Vector3.ZERO,
	}


## Seat her and build the dock: the attach path and a settled placement edit.
func _apply(row: Dictionary) -> void:
	if not _apply_tail(row):
		return
	_apply_dock(row)


## Write the seat to the hair link. The dock is skinned to the tail, so it follows this write
## without a rebuild; only the base-ring snap needs `_apply_dock()`.
func _apply_tail(row: Dictionary) -> bool:
	var pony: Node = row.get("pony") as Node
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		return false
	if not SETTINGS.reseat_tails.get_bool():
		_restore(row)
		return false
	var reference_anchor := reference(pony)
	if not reference_anchor.is_finite():
		return false
	var target := reference_anchor + Vector3(0.0, float(row.get("tail_y", 0.0)),
		float(row.get("tail_z", 0.0)))
	var delta := target - (row["anchor"] as Vector3)
	var link: Node = row["link"]
	if not is_instance_valid(link) or not link.is_inside_tree():
		return false
	var next: Transform3D = row["original_pelvis"]
	next.origin += (row["hips_rest"] as Transform3D).basis.inverse() * delta
	var tilt := deg_to_rad(float(row.get("tail_tilt_deg", 0.0)))
	if absf(tilt) > 0.000001:
		next.basis = Basis(Vector3.BACK, tilt) * next.basis
	link.set("pelvis_offset", next)
	if link.has_method("_body_updated"):
		link.call("_body_updated")
	row["applied"] = delta
	_invalidate_far(pony)
	return true


## Rebuild the dock mesh for the current fit and seat delta. Expensive: attach, toggle and one
## pass per settled placement edit only.
func _apply_dock(row: Dictionary) -> void:
	var pony: Node = row.get("pony") as Node
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		return
	if not SETTINGS.reseat_tails.get_bool():
		_restore(row)
		return
	_move_dock(row, row.get("applied", Vector3.ZERO) as Vector3)


## The dock offset is a post-skin lift on the instance transform, so a `dock_y` edit needs no
## mesh rebuild.
func _apply_lift(row: Dictionary) -> void:
	if not bool(row.get("attached", false)):
		return
	var dock: MeshInstance3D = row.get("dock") as MeshInstance3D
	var hair: Skeleton3D = row.get("hair_sk") as Skeleton3D
	var body: Skeleton3D = row.get("body_sk") as Skeleton3D
	if not is_instance_valid(dock) or not is_instance_valid(hair) or not is_instance_valid(body):
		return
	dock.transform = DOCK_ATTACH.lift_transform(body, hair,
		float(row.get("drop", 0.0)) + float(row.get("dock_y", 0.0)))


## Queue her dock for the settle pass. A slider drag rewrites the tail every tick; the dock mesh
## is rebuilt once after the last edit.
func _mark_dirty(row: Dictionary) -> void:
	if not _dirty.has(row):
		_dirty.append(row)
	if is_instance_valid(_settle):
		_settle.start()


func _flush_dirty() -> void:
	var rows: Array[Dictionary] = _dirty
	_dirty = []
	for row: Dictionary in rows:
		var pony: Variant = row.get("pony")
		if not is_instance_valid(pony) or not _rows.has(pony) or not is_same(_rows[pony], row):
			continue
		if not _seated(row) or not SETTINGS.reseat_tails.get_bool():
			continue
		_apply_dock(row)


func _restore(row: Dictionary) -> void:
	if not _seated(row):
		return
	var pony: Node = row.get("pony") as Node
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		return
	var link: Node = row["link"]
	if is_instance_valid(link) and link.is_inside_tree():
		link.set("pelvis_offset", row["original_pelvis"])
		if link.has_method("_body_updated"):
			link.call("_body_updated")
	_clear_skin(row)
	var dock: MeshInstance3D = row["dock"]
	if is_instance_valid(dock):
		# Same relative-path hazard as `_install_skin`: detach first, then move the node.
		dock.skeleton = NodePath()
		dock.skin = null
		var original_parent: Variant = row.get("original_parent")
		if is_instance_valid(original_parent) and dock.get_parent() != original_parent:
			var current: Node = dock.get_parent()
			if is_instance_valid(current):
				current.remove_child(dock)
			(original_parent as Node).add_child(dock)
		var original_skeleton: NodePath = row.get("original_skeleton", NodePath())
		var original_transform: Transform3D = row.get("original_transform",
			Transform3D.IDENTITY)
		# The dock is watched by the game's rig parking; a stale parked path would make the next
		# unpark restore our hair binding instead of the body one.
		dock.remove_meta(&"parked_skeleton")
		dock.mesh = row["original_dock"]
		dock.skin = row["original_skin"]
		dock.skeleton = original_skeleton
		dock.transform = original_transform
		# Back under `_model`; carry the far-mesh hide again if the pony is far right now, so the
		# game's own far-end restore takes it down with the other rig meshes.
		if bool(pony.get("_far_mesh_shown")) and dock.visible:
			dock.set_meta(&"far_hidden", true)
			dock.visible = false
		dock.set_surface_override_material(0, row["original_material"])
	row["applied"] = Vector3.ZERO
	row["drop"] = 0.0
	_invalidate_far(pony)


## Place the dock in its fitted/snapped cuff position, then install the hair-bound two-bone skin
## that carries it with the hair tail root. The fit is captured before the first write, so repeated
## nudges rebuild from the game's original fit instead of accumulating.
func _move_dock(row: Dictionary, delta: Vector3) -> void:
	var dock: MeshInstance3D = row["dock"]
	if not is_instance_valid(dock):
		return
	var fit: Dictionary = (row["fit"] as Dictionary).duplicate(true)
	var dock_scale := maxf(0.05, float(row.get("dock_scale", 1.0)))
	if not is_equal_approx(dock_scale, 1.0):
		fit["scale"] = float(fit.get("scale", 1.0)) * dock_scale
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
		_install_skin(row, mesh, delta)


func _install_skin(row: Dictionary, mesh: ArrayMesh, delta: Vector3) -> void:
	var dock: MeshInstance3D = row["dock"]
	var hair: Skeleton3D = row["hair_sk"]
	var body: Skeleton3D = row["body_sk"]
	if not is_instance_valid(dock) or not is_instance_valid(hair) or not is_instance_valid(body):
		return
	# Seat the dock's outer opening on the tail cap's centre line. `mesh` is already moved by the
	# seat delta, so subtract that delta before comparing it with the cap measured in the mare's
	# own pre-seat frame. The Anatomy Dock offset trims it from there.
	var top := mesh.get_aabb().end.y - delta.y
	var drop := float(row.get("cap_centre", NAN)) - top
	if not is_finite(drop):
		drop = 0.0
	# The lift is cached so a later `dock_y` edit can rewrite the instance transform alone.
	row["drop"] = drop
	var parts := DOCK_ATTACH.build(mesh, body, hair, drop + float(row.get("dock_y", 0.0)))
	if parts.is_empty():
		return
	_clear_skin(row)
	# Drop the old binding before the node moves: `skeleton` is a relative path, and an old skin
	# must not resolve against the new parent while the node is re-entering the tree.
	dock.skeleton = NodePath()
	dock.skin = null
	# The dock is skinned to the hair skeleton, so it must live under it: the game bakes every
	# visible `_model` mesh with a skin into the far mesh, and a hair-bound skin there would be
	# remapped onto body bones. Under `hair`, `_show_far_mesh()` hides the cuff with the hair.
	var parent: Node = dock.get_parent()
	if parent != hair:
		if is_instance_valid(parent):
			parent.remove_child(dock)
		hair.add_child(dock)
	var placement: Transform3D = parts.get("transform")
	var skinned: ArrayMesh = parts.get("mesh")
	var skin: Skin = parts.get("skin")
	dock.remove_meta(&"parked_skeleton")
	dock.transform = placement
	dock.mesh = skinned
	# Set the skin while the skeleton path is empty, then resolve it once: setting the path with
	# no skin would make Godot register a temporary rest skin for the whole hair rig.
	dock.skin = skin
	dock.skeleton = dock.get_path_to(hair)
	# The dock left `_model`, so the far-mesh pass cannot restore a `far_hidden` mark it set
	# before the move. Only a visible dock gets that mark; return it to the anatomy's switch.
	if dock.has_meta(&"far_hidden"):
		dock.remove_meta(&"far_hidden")
		dock.visible = SETTINGS.show_dock.get_bool()
	dock.set_surface_override_material(0, _dock_material(row))
	row["attached"] = true
	row["builds"] = int(row.get("builds", 0)) + 1


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
						# The dock rides the hair skeleton, not the body's leg skinning.
						dock.set_shader_parameter("coat_follow_strength", 0.0)
						return dock
	var original: Variant = row.get("original_material")
	return original as Material if original is Material else null


## Re-apply the chosen dock material after the anatomy attaches, changes or detaches.
func refresh_dock_color(pony: Node) -> void:
	if not is_instance_valid(pony) or not _rows.has(pony):
		return
	var row: Dictionary = _rows[pony]
	if not _seated(row):
		return
	var dock: MeshInstance3D = row["dock"]
	if not is_instance_valid(dock) or dock.is_queued_for_deletion():
		return
	var mesh: Mesh = dock.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return
	dock.set_surface_override_material(0, _dock_material(row))


## The dock is a real skinned mesh now, so there is no follower node to free. `_restore()` puts
## the game's body-skinned dock back; a rebuild simply overwrites the installed mesh and skin.
func _clear_skin(row: Dictionary) -> void:
	row["attached"] = false


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


func _perf_on() -> bool:
	return perf_on.is_valid() and bool(perf_on.call())


func _log_perf() -> void:
	var seats := 0
	var skinned := 0
	var builds := 0
	for pony: Variant in _rows.keys():
		if not is_instance_valid(pony):
			continue
		var row: Dictionary = _rows[pony]
		if not _seated(row):
			continue
		seats += 1
		if bool(row.get("attached", false)):
			skinned += 1
		builds += int(row.get("builds", 0))
		row["builds"] = 0
	_log("tail perf seats=%d skinned=%d builds=%d/s" % [seats, skinned, builds])


func _source(row: Dictionary) -> String:
	if not SETTINGS.reseat_tails.get_bool():
		return "off"
	if SETTINGS.anatomy_placement_has_override(str(row["id"])):
		return "override"
	return "auto"


func _log(text: String) -> void:
	if log.is_valid():
		log.call(text)
