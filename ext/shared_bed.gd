extends "res://world/relationships/shared_bed.gd"
## The stock bed rejects any pony with body_scale > 1.05, which blocks the larger size presets
## (JRHNBR x1.35, Same Height x1.7, Hoers x2.3) from ever starting a cuddle. Keep every other
## eligibility rule intact and only raise that ceiling so the cuddle can start at the common
## preset sizes. Pose/act code then works from the actual body transform.

const MAX_CUDDLE_BODY_SCALE := 1.5


func eligible(actor: Node3D) -> bool:
	if actor == null or not actor is CharacterBody3D or not actor.has_method("request_posture"):
		return false
	var to_bed := actor.global_position - _frame.origin
	if Vector2(to_bed.x, to_bed.z).length() > 8.0 or absf(to_bed.y) > 0.5:
		return false
	if actor.get("sleeping") != false or actor.get("_held") == true or actor.get("motion_paused") == true:
		return false
	for busy: String in ["seating", "fishing_companion", "balloon_passenger", "cuddle_active"]:
		if actor.has_meta(busy):
			return false
	if actor.get_meta("affection_active", false):
		return false
	if actor.has_method("action_interruption_reason") and not str(actor.action_interruption_reason()).is_empty():
		return false
	if actor.get("flight") != null and actor.flight.active():
		return false
	if float(actor.get("body_scale")) > MAX_CUDDLE_BODY_SCALE:
		return false
	if Time.get_ticks_msec() < int(_cooldowns.get(actor.get_instance_id(), 0)):
		return false
	var nav := actor.get_node_or_null("Navigator")
	if nav == null:
		return false
	if "reserved_by" in nav and not str(nav.reserved_by).is_empty():
		return false
	var owner := str(nav.command_owner)
	var routine := owner.is_empty() or owner == "rest_after_command" or owner.begins_with("life:") \
		or owner.begins_with("bond:") or owner.begins_with("day:")
	var following := _is_player(nav.get("_follow_target")) or not _spoken_follow(actor, nav).is_empty()
	if not following and (not routine or nav.get("_has_target") == true):
		return false
	return _willing(actor)
