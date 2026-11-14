extends "res://mods/unfplap/hands/path_base.gd"
## Standing oral caress path: one authored head-side node per hand. Anon faces her, so his left
## hand holds her right side; the head area is authored from the mare's point of view and the
## lookup is flipped here. There is no lean chain and no flank fallback.

const PATH := preload("res://mods/unfplap/hands/paths/anchors.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

const ORAL_PALM_ROLL_DEG := 24.0

var _paths: Dictionary = {}
var _failed: Dictionary = {}
var _last_world: Dictionary = {}
var _path_pony_id := 0


func candidates(hand_side: String, _context: Dictionary) -> Array:
	if not is_instance_valid(pony):
		return []
	# Anon faces her, like in missionary, so his left hand holds her right side and his right
	# hand holds her left. The head area is mare-PoV, so read the opposite side.
	var anchor_side := "right" if hand_side == "left" else "left"
	var path: Variant = _path_for(anchor_side)
	if path == null:
		return []
	var world: Array = path.call("skinned")
	if world.size() != 1:
		return []
	var anchor: Dictionary = world[0]
	_last_world[hand_side] = world
	var normal: Vector3 = anchor.get("normal", Vector3.UP)
	if normal.length_squared() < 0.5:
		normal = Vector3.UP
	normal = normal.normalized()
	var forward: Vector3 = (-pony.global_basis.z).normalized()
	var along := forward - normal * forward.dot(normal)
	if along.length_squared() < 0.0001:
		along = normal.cross(Vector3.UP)
	if along.length_squared() < 0.0001:
		along = Vector3.FORWARD
	along = along.normalized()
	var across := normal.cross(along)
	if across.length_squared() < 0.0001:
		across = normal.cross(Vector3.RIGHT)
	across = across.normalized()
	return [{
		"point": anchor.get("position", Vector3.ZERO),
		"normal": normal,
		"oval_x": along,
		"oval_y": across,
		"finger": along,
		"mode": str(path.get("single_mode")),
		"roll": oral_palm_roll_deg(hand_side) * float(anchor.get("roll", 1.0)),
		"region": str(anchor.get("region", "head")),
		"u": 0.0,
	}]


func debug_world(hand_side: String) -> Array:
	var world: Variant = _last_world.get(hand_side)
	return world if world is Array else []


func reset() -> void:
	_paths.clear()
	_failed.clear()
	_last_world.clear()
	_path_pony_id = 0


func _path_for(anchor_side: String) -> Variant:
	var pony_id: int = int(pony.get_instance_id()) if is_instance_valid(pony) else 0
	if pony_id != _path_pony_id:
		_paths.clear()
		_failed.clear()
		_last_world.clear()
		_path_pony_id = pony_id
	if bool(_failed.get(anchor_side, false)):
		return null
	var path: Variant = _paths.get(anchor_side)
	if path != null and bool(path.get("valid")):
		return path
	var started := Time.get_ticks_usec()
	path = PATH.new()
	if not bool(path.call("build_single_area", pony, anchor_side, "head_side")):
		_failed[anchor_side] = true
		_log("caress oral head_side missing side=%s" % anchor_side)
		for note: Variant in (path.get("debug_notes") as Array):
			_log("caress " + str(note))
		return null
	_paths[anchor_side] = path
	if bool(SETTINGS.caress_debug.get_bool()):
		_log("caress path side=%s path=oral anchors=1 build_ms=%.1f" % [anchor_side,
			float(Time.get_ticks_usec() - started) / 1000.0])
		var world: Array = path.call("skinned")
		for anchor: Dictionary in world:
			_log("caress anchor %s pos=%s normal=%s" % [anchor["id"],
				str(anchor["position"]), str(anchor["normal"])])
	return path


static func oral_palm_roll_deg(side: String) -> float:
	return ORAL_PALM_ROLL_DEG if side == "right" else -ORAL_PALM_ROLL_DEG


func _log(text: String) -> void:
	if facts != null:
		facts.write_log(text)
