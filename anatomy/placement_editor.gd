extends RefCounted
## The Anatomy Placement editor: the placement actions and the text report.
## The caller names the pony; the editor no longer selects one or reads the debug facade.
## See `docs/anatomy.md` (`## Placement`).

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const PLACEMENT := preload("res://mods/unfplap/shared/anatomy_placement.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const IDENTITY := preload("res://mods/unfplap/anatomy/identity.gd")
const PARTS := preload("res://mods/unfplap/anatomy/parts.gd")
const RIG := preload("res://mods/unfplap/anatomy/rig.gd")

var parts: PARTS
var rig: RIG


func setup(parts_node: PARTS, rig_node: RIG) -> void:
	parts = parts_node
	rig = rig_node


func placement_id(pony: Node) -> String:
	if SETTINGS.edit_target.get_choice() == "default":
		return "default"
	if not is_instance_valid(pony):
		return ""
	return PONY_ID.of(pony)


func placement_values(id: String, fit_id: String = "") -> Dictionary:
	if id == "default":
		return SETTINGS.anatomy_placement_default("").raw()
	return SETTINGS.anatomy_placement(id, fit_id).raw()


func placement_refresh() -> void:
	if parts != null:
		parts.apply_live()
		parts.refresh_tails()


## `tail_owned` is the body-change service's answer: a source-owned tail can be moved even when
## the regular seat has no row.
func placement_debug(pony: Node, op: String, value := 0.0, tail_owned := false) -> String:
	var id := placement_id(pony)
	if id.is_empty():
		return "No placement pony targeted."
	var fit_id := ""
	if id != "default" and is_instance_valid(pony):
		fit_id = IDENTITY.body_fit_id(pony)
	if id != "default" and op.begins_with("dock_"):
		if not parts.can_dock(pony):
			return "%s: no dock on this tail." % id
	if id != "default" and op.begins_with("tail_"):
		if not tail_owned and not parts.can_seat(pony):
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
			return "%s %s" % [id, PLACEMENT.text(values)]


func placement_show(pony: Node) -> String:
	var parts_out := PackedStringArray([placement_debug(pony, "text")])
	var report := parts.tail_report() if parts != null else ""
	if not report.is_empty():
		parts_out.append(report)
	return " | ".join(parts_out)


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
