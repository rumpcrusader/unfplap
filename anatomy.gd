extends Node
## The anatomy system's world facade. One service under `main` owns the per-pony controllers and,
## later, the player part and tail seating. Other systems call this facade, never a controller's
## internals.
##
## The per-pony controller is `anatomy/controller.gd`; it owns the per-act handle
## `anatomy/act.gd`.
##
## See `docs/anatomy.md`.

const CONTROLLER := preload("res://mods/unfplap/anatomy/controller.gd")
const PLAYER := preload("res://mods/unfplap/anatomy/player.gd")
const TAIL_SEAT := preload("res://mods/unfplap/anatomy/tail/seat.gd")
const TAIL_VISIBILITY := preload("res://mods/unfplap/anatomy/tail/visibility.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const PLACEMENT := preload("res://mods/unfplap/anatomy_placement.gd")

var main: Node
var player: Node
var tail_seat: Node
var tail_visibility: Node

## pony -> controller
var _controllers: Dictionary = {}
var _player_part: Node


func setup(main_node: Node) -> void:
	main = main_node
	tail_visibility = TAIL_VISIBILITY.new()
	tail_visibility.name = "UnfplapTailVisibility"
	add_child(tail_visibility)
	tail_seat = TAIL_SEAT.new()
	tail_seat.name = "UnfplapTailSeat"
	tail_seat.set("main", main)
	add_child(tail_seat)


## The live controller for a pony, created on first use. Runtime passes itself so the controller
## can read the act state, cycle and perf sink.
func controller_for(pony: Node, runtime: Node) -> Node:
	if not is_instance_valid(pony):
		return null
	var existing: Variant = _controllers.get(pony)
	if is_instance_valid(existing):
		return existing
	var controller: Node = CONTROLLER.new()
	controller.name = "UnfplapAnatomyController"
	add_child(controller)
	controller.call("setup", pony, runtime)
	_controllers[pony] = controller
	pony.tree_exiting.connect(func() -> void: detach_controller(pony))
	return controller


func bind(pony: Node, runtime: Node) -> Node:
	return controller_for(pony, runtime)


func controller(pony: Node) -> Node:
	var value: Variant = _controllers.get(pony)
	return value if is_instance_valid(value) else null


func online(pony: Node) -> bool:
	return is_instance_valid(controller(pony))


## Re-read settings and identity for every live controller.
func refresh_all() -> void:
	for pony: Variant in _controllers.keys():
		if not is_instance_valid(pony):
			_controllers.erase(pony)
			continue
		var controller: Variant = _controllers[pony]
		if is_instance_valid(controller) and controller.has_method("refresh"):
			controller.call("refresh")


func apply_live() -> void:
	for pony: Variant in _controllers.keys():
		if not is_instance_valid(pony):
			_controllers.erase(pony)
			continue
		var controller: Variant = _controllers[pony]
		if is_instance_valid(controller) and controller.has_method("apply_live"):
			controller.call("apply_live")


func tail_ready(pony: Node) -> void:
	if not is_instance_valid(tail_seat) or not is_instance_valid(pony):
		return
	tail_seat.call("attach", pony)
	# A mod may finish its hair or dock a frame after the pony is ready; attach is idempotent.
	tail_seat.call_deferred("attach", pony)


func refresh_tails() -> void:
	if is_instance_valid(tail_seat):
		tail_seat.call("refresh_all")


func refresh_dock_color(pony: Node) -> void:
	if is_instance_valid(tail_seat):
		tail_seat.call("refresh_dock_color", pony)


func can_seat(pony: Node) -> bool:
	return is_instance_valid(tail_seat) and bool(tail_seat.call("can_seat", pony))


func tail_report() -> String:
	if not is_instance_valid(tail_seat):
		return ""
	return str(tail_seat.call("report_all"))


# --------------------------------------------------------------------------- placement editor

func placement_target() -> Node:
	if not is_instance_valid(main):
		return null
	var view: Camera3D = main.call("camera")
	var target: Node = main.call("debug_target", view) if is_instance_valid(view) else null
	if not is_instance_valid(target):
		target = main.call("nearest_pony", view)
	return target


func placement_id() -> String:
	if SETTINGS.edit_target.get_choice() == "default":
		return "default"
	var target := placement_target()
	if not is_instance_valid(target):
		return ""
	return CONTROLLER.pony_id(target)


func placement_values(id: String) -> Dictionary:
	if id == "default":
		return SETTINGS.anatomy_placement_draft_values()
	return SETTINGS.anatomy_placement(id)


func placement_refresh() -> void:
	if is_instance_valid(main):
		main.call("refresh_anatomy")
	refresh_tails()


func placement_debug(op: String, value := 0.0) -> String:
	var id := placement_id()
	if id.is_empty():
		return "No placement pony targeted."
	if id != "default" and (op.begins_with("tail_") or op.begins_with("dock_")):
		if not can_seat(placement_target()):
			return "%s: tail seat unavailable (no hair tail or dock)." % id
	var values := placement_values(id)
	match op:
		"save":
			if id == "default":
				SETTINGS.save_anatomy_placement_default(values)
				if is_instance_valid(main):
					main.call("apply_settings_changed")
			else:
				SETTINGS.save_anatomy_placement(id, values)
				placement_refresh()
			return "%s saved %s" % [id, PLACEMENT.text(values)]
		"reset":
			if id == "default":
				SETTINGS.reset_anatomy_placement_default()
			else:
				SETTINGS.save_anatomy_placement(id,
					SETTINGS.anatomy_placement_default(id, false))
			placement_refresh()
			return "%s %s" % [id, PLACEMENT.text(placement_values(id))]
		"text":
			return "%s %s" % [id, PLACEMENT.text(values)]
		_:
			if not _nudge_placement(values, op, value):
				return "Unknown placement action."
			if id == "default":
				SETTINGS.set_anatomy_placement_draft(values)
			else:
				SETTINGS.save_anatomy_placement(id, values)
			placement_refresh()
			return "%s %s" % [id, PLACEMENT.text(values)]


func placement_show() -> String:
	var text := placement_debug("text")
	var report := tail_report()
	return text if report.is_empty() else "%s | %s" % [text, report]


static func _nudge_placement(placement: Dictionary, op: String, value: float) -> bool:
	match op:
		"x":
			placement["offset_x"] = float(placement.get("offset_x", 0.0)) + value
		"y":
			placement["offset_y"] = float(placement.get("offset_y", 0.0)) + value
		"z":
			placement["offset_z"] = float(placement.get("offset_z", 0.0)) + value
		"pitch":
			placement["pitch_deg"] = float(placement.get("pitch_deg", 0.0)) + value
		"scale":
			placement["scale"] = maxf(0.05, float(placement.get("scale", 1.0)) + value)
		"tail_up":
			placement["tail_y"] = float(placement.get("tail_y", 0.0)) + value
		"tail_down":
			placement["tail_y"] = float(placement.get("tail_y", 0.0)) - value
		"tail_forward":
			placement["tail_z"] = float(placement.get("tail_z", 0.0)) - value
		"tail_back":
			placement["tail_z"] = float(placement.get("tail_z", 0.0)) + value
		"dock_up":
			placement["dock_y"] = float(placement.get("dock_y", 0.0)) + value
		"dock_down":
			placement["dock_y"] = float(placement.get("dock_y", 0.0)) - value
		"dock_scale_up":
			placement["dock_scale"] = minf(float(placement.get("dock_scale", 1.0)) + value, 4.0)
		"dock_scale_down":
			placement["dock_scale"] = maxf(float(placement.get("dock_scale", 1.0)) - value, 0.05)
		"tail_tilt_left":
			placement["tail_tilt_deg"] = float(placement.get("tail_tilt_deg", 0.0)) + value
		"tail_tilt_right":
			placement["tail_tilt_deg"] = float(placement.get("tail_tilt_deg", 0.0)) - value
		_:
			return false
	return true


func detach_controller(pony: Node) -> void:
	var controller: Variant = _controllers.get(pony)
	_controllers.erase(pony)
	if not is_instance_valid(controller):
		return
	controller.call("detach")
	controller.queue_free()


func shutdown() -> void:
	for pony: Variant in _controllers.keys():
		if is_instance_valid(pony):
			var controller: Variant = _controllers[pony]
			if is_instance_valid(controller):
				controller.call("detach")
				controller.queue_free()
	_controllers.clear()
	clear_player()
	tail_seat = null
	tail_visibility = null
	main = null


# --------------------------------------------------------------------------- player part

func player_ready(body: Node) -> void:
	player = body
	refresh_player()


func clear_player() -> void:
	if is_instance_valid(_player_part):
		_player_part.call("encounter", false)
		_player_part.queue_free()
	_player_part = null
	player = null


func refresh_player() -> void:
	var enabled := SETTINGS.anatomy_on() and is_instance_valid(player) and PLAYER.assets_exist()
	if not enabled:
		if is_instance_valid(_player_part):
			_player_part.call("encounter", false)
			_player_part.queue_free()
			_player_part = null
		return
	if not is_instance_valid(_player_part):
		_player_part = PLAYER.new()
		_player_part.name = "UnfplapAnonPart"
		_player_part.set("main", main)
		add_child(_player_part)
	if _player_part.has_method("apply_live"):
		_player_part.call("apply_live")


## The anatomy-internal player part handle. Pose systems use the methods below instead.
func part() -> Node:
	return _player_part if is_instance_valid(_player_part) else null


func player_available() -> bool:
	return is_instance_valid(_player_part)


func player_encounter(on: bool) -> void:
	if is_instance_valid(_player_part):
		_player_part.call("encounter", on)


func player_track(target: Vector3, rear: Vector3, up: Vector3, bed: bool,
		penetration_m: float, delta: float, mare_anchor: Node3D, attached := true) -> void:
	if is_instance_valid(_player_part):
		_player_part.call("track", target, rear, up, bed, penetration_m, delta,
			mare_anchor, attached)


func player_showing() -> bool:
	return is_instance_valid(_player_part) and bool(_player_part.call("showing"))


func player_shaft_length_m() -> float:
	if not is_instance_valid(_player_part):
		return 0.0
	return float(_player_part.call("shaft_length_m"))


func player_girth_at(point: Vector3) -> float:
	if not is_instance_valid(_player_part):
		return -1.0
	return float(_player_part.call("girth_at", point))


func player_tip_world() -> Vector3:
	if not is_instance_valid(_player_part):
		return Vector3.ZERO
	var value: Variant = _player_part.call("tip_world")
	return value if value is Vector3 else Vector3.ZERO


func player_tip_center() -> Vector3:
	if not is_instance_valid(_player_part):
		return Vector3.ZERO
	var value: Variant = _player_part.call("tip_center")
	return value if value is Vector3 else Vector3.ZERO


func player_root_now() -> Vector3:
	if not is_instance_valid(_player_part):
		return Vector3.ZERO
	var value: Variant = _player_part.call("root_now")
	return value if value is Vector3 else Vector3.ZERO


func player_shaft_radii(count := 8) -> PackedFloat32Array:
	if not is_instance_valid(_player_part):
		return PackedFloat32Array()
	var value: Variant = _player_part.call("shaft_radii", count)
	return value if value is PackedFloat32Array else PackedFloat32Array()


func player_hip_offset() -> Vector3:
	if not is_instance_valid(_player_part) or not bool(_player_part.call("showing")):
		return Vector3.ZERO
	var value: Variant = _player_part.call("hip_offset_wanted")
	return value if value is Vector3 and (value as Vector3).is_finite() else Vector3.ZERO


func player_note_hip_offset(offset: Vector3) -> void:
	if is_instance_valid(_player_part) and bool(_player_part.call("showing")):
		_player_part.set("hip_offset_applied", offset)


func player_debug_scale() -> Variant:
	if not is_instance_valid(_player_part) or not bool(_player_part.call("showing")):
		return null
	return _player_part.call("debug_scale")


func player_set_aim(normal: Vector3, opening: Vector3, pitch := 0.0) -> void:
	if not is_instance_valid(_player_part):
		return
	_player_part.set("aim_normal", normal)
	_player_part.set("aim_opening", opening)
	_player_part.set("aim_pitch_deg", pitch)


func player_set_bed_inset(metres: float) -> void:
	if is_instance_valid(_player_part):
		_player_part.set("bed_inset_m", metres)


func player_apply_live() -> void:
	if is_instance_valid(_player_part) and _player_part.has_method("apply_live"):
		_player_part.call("apply_live")


# --------------------------------------------------------------------------- static identity

static func assets_exist() -> bool:
	return CONTROLLER.assets_exist()


static func selected_mare_bits_path() -> String:
	return CONTROLLER.selected_mare_bits_path()


static func eligible(pony_node: Node3D) -> bool:
	return CONTROLLER.eligible(pony_node)


static func pony_id(pony_node: Node) -> String:
	return CONTROLLER.pony_id(pony_node)


static func body_profile(identity: Variant) -> Array:
	return CONTROLLER.body_profile(identity)


static func off_roster_ids(ponies: Array, base_ids: Array) -> Array[String]:
	return CONTROLLER.off_roster_ids(ponies, base_ids)
