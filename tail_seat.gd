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
const HYBRID_FAR_MESH := preload("res://world/characters/hybrid_mare/hybrid_far_mesh.gd")

const DOCK_NAME := "OpenPonyDock"
const REFERENCE_PATH := "res://world/characters/hybrid_mare/dock_tail_mounts.json"
## The reference's cap sits just below and in front of the body's own tail root. This fallback is
## the current game relation; the JSON reference wins whenever it is available.
const FALLBACK_TAIL_OFFSET := Vector3(0.0, -0.0044, -0.0235)
const MOVE_STEP := 0.005
## Below this squared length the dock can stay on its cached original mesh.
const DOCK_EPSILON := 0.0000000001

var main: Node

## pony -> cached original values, target and live state. See `_prepare()`.
var _rows: Dictionary = {}
## Last applied value of Anatomy › Re-seat tails; `refresh_all` only re-applies when it changes.
var _enabled := true
static var _reference := Vector3.INF
static var _reference_loaded := false


func _ready() -> void:
	_enabled = SETTINGS.reseat_tails.get_bool()


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
	var toggle_changed := enabled != _enabled
	_enabled = enabled
	for pony: Variant in _rows.keys():
		if not is_instance_valid(pony):
			_rows.erase(pony)
			continue
		var row: Dictionary = _rows[pony]
		var changed := toggle_changed
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
		return "Re-seat tails is off."
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
	for pony: Variant in _rows.keys():
		if not is_instance_valid(pony):
			_rows.erase(pony)
			continue
		var row: Dictionary = _rows[pony]
		var target := PLACEMENT.target(reference(pony), row["offset"] as Vector2)
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
		_log("tail seats\n\t" + "\n\t".join(lines))
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
	if fit.is_empty():
		_log("tail seat: no dock fit for %s" % pony.name)
		return {}
	var identity: Variant = pony.get("identity")
	return {
		"pony": pony,
		"id": str(identity.get("id")),
		"link": link,
		"dock": dock,
		"original_pelvis": link.get("pelvis_offset") as Transform3D,
		"original_dock": dock.mesh,
		"hips_rest": skeleton.get_bone_global_rest(hips),
		"anchor": anchor,
		"fit": fit.duplicate(true),
		"offset": SETTINGS.tail_seat_offset(str(identity.get("id"))),
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
	var delta := PLACEMENT.delta(row["anchor"] as Vector3, reference_anchor,
		row["offset"] as Vector2)
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
	var dock: MeshInstance3D = row["dock"]
	if is_instance_valid(dock):
		dock.mesh = row["original_dock"]
	row["applied"] = Vector3.ZERO
	_invalidate_far(pony)


## Move the dock by the same body-space delta as the tail. The fit is captured before the first
## write, so repeated nudges rebuild from the game's original fit instead of accumulating.
func _move_dock(row: Dictionary, delta: Vector3) -> void:
	var dock: MeshInstance3D = row["dock"]
	if not is_instance_valid(dock):
		return
	if delta.length_squared() <= DOCK_EPSILON:
		dock.mesh = row["original_dock"]
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
	if mesh != null:
		dock.mesh = mesh


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
