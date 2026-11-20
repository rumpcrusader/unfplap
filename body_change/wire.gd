extends RefCounted
## The legacy metadata mirror for one presented body: body-fit key, mesh-hide marker, tail root
## and live body scale. The mirror is write-only; nothing reads a form back out of these keys.
## See `docs/body_change.md` (`## Internal API`).

const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")


## Mirror `form` onto `pony`.
static func apply(pony: Node3D, form: BODY_FORM.BodyForm) -> void:
	if not is_instance_valid(pony) or form == null:
		return
	pony.set_meta("body_fit_id", form.fit_id)
	if form.owned_mesh_meta.is_empty():
		if pony.has_meta("anatomy_owned_meta"):
			pony.remove_meta("anatomy_owned_meta")
	else:
		pony.set_meta("anatomy_owned_meta", form.owned_mesh_meta)
	if is_instance_valid(form.tail_root):
		pony.set_meta("tail_pose_root", form.tail_root)
	elif pony.has_meta("tail_pose_root"):
		pony.remove_meta("tail_pose_root")
	var live_scale: Variant = pony.get("body_scale")
	if pony.has_method("set_body_scale"):
		# The game body's capsule and pose calibration follow the same field; a bare `set()` would
		# leave the capsule at the old size.
		if live_scale == null or not is_equal_approx(float(live_scale), form.body_scale):
			pony.call("set_body_scale", form.body_scale)
	elif live_scale != null:
		pony.set("body_scale", form.body_scale)
