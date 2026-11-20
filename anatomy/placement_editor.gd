extends RefCounted
## The Anatomy Placement editor: the placement actions and the text report.
## It resolves the pointed mare with the debug facade's aim rule, so wheel and editor agree.
## See `docs/anatomy.md` (`## Placement`).

const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const DEBUG_ACTIONS := preload("res://mods/unfplap/debug/service.gd")
const PLACEMENT := preload("res://mods/unfplap/shared/anatomy_placement.gd")
const CONTROLLER := preload("res://mods/unfplap/anatomy/controller.gd")
const SERVICE := preload("res://mods/unfplap/anatomy/service.gd")

var service: SERVICE


func setup(service_node: SERVICE) -> void:
	service = service_node


func placement_target() -> Node:
	var view: Camera3D = WORLD.camera()
	var target: Node = DEBUG_ACTIONS.aimed_pony(view)
	if not is_instance_valid(target):
		target = DEBUG_ACTIONS.nearest_pony(view)
	return target


func placement_id() -> String:
	if SETTINGS.edit_target.get_choice() == "default":
		return "default"
	var target := placement_target()
	if not is_instance_valid(target):
		return ""
	return CONTROLLER.pony_id(target)


func placement_values(id: String, fit_id: String = "") -> Dictionary:
	if id == "default":
		return SETTINGS.anatomy_placement_default("").raw()
	return SETTINGS.anatomy_placement(id, fit_id).raw()


func placement_refresh() -> void:
	if is_instance_valid(service):
		service.apply_settings()


func placement_debug(op: String, value := 0.0) -> String:
	var id := placement_id()
	if id.is_empty():
		return "No placement pony targeted."
	var target := placement_target()
	var fit_id := ""
	if id != "default" and is_instance_valid(target):
		fit_id = CONTROLLER.body_fit_id(target)
	if id != "default" and op.begins_with("dock_"):
		if not service.can_dock(target):
			return "%s: no dock on this tail." % id
	if id != "default" and op.begins_with("tail_"):
		if not service.can_place_tail(target):
			return "%s: tail seat unavailable (no hair tail or dock)." % id
	var rows := (SETTINGS.anatomy_placement_default("") if id == "default"
		else SETTINGS.anatomy_placement(id, fit_id))
	var values := rows.raw()
	match op:
		"reset":
			if id == "default":
				SETTINGS.reset_anatomy_placement_default()
				SETTINGS.apply_live()
			else:
				SETTINGS.save_anatomy_placement(id,
					SETTINGS.anatomy_placement_default(id, fit_id), fit_id)
				placement_refresh()
				_apply_custom_tail(target)
			return "%s %s" % [id, PLACEMENT.text(placement_values(id, fit_id))]
		"text":
			return "%s %s" % [id, PLACEMENT.text(values)]
		_:
			if not _nudge_placement(values, op, value):
				return "Unknown placement action."
			if id == "default":
				SETTINGS.save_anatomy_placement_default(rows)
				SETTINGS.apply_live()
			else:
				SETTINGS.save_anatomy_placement(id, rows, fit_id)
				placement_refresh()
				_apply_custom_tail(target)
			return "%s %s" % [id, PLACEMENT.text(values)]


func placement_show() -> String:
	var parts := PackedStringArray([placement_debug("text")])
	var report := service.tail_report() if is_instance_valid(service) else ""
	if not report.is_empty():
		parts.append(report)
	var change := PONIES.body_change
	if is_instance_valid(change):
		var custom := str(change.tail_placement_report())
		if not custom.is_empty():
			parts.append(custom)
	return " | ".join(parts)


func _apply_custom_tail(target: Node) -> void:
	var change := PONIES.body_change
	if is_instance_valid(target) and is_instance_valid(change):
		change.apply_tail_placement(target)


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
