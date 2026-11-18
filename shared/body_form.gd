extends RefCounted
## The visible body's typed descriptor: the stable pony identity, the form id and name, the anatomy
## and tail placement fit, the rig, the source body's mesh-hide marker and tail root, the live body
## scale, and the form revision. A source's form overrides the pony's default own form.
##
## Shared read model: it reads a pony's identity and metadata, never a service, runtime, scene or
## file.

const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")


## One presented body's form. `form_id` is empty for the pony's own body.
class BodyForm extends RefCounted:
	var pony_id: String = ""
	var form_id: String = ""
	var form_name: String = ""
	var fit_id: String = ""
	var rig: BODY_PROFILE.RigProfile = null
	var owned_mesh_meta: String = ""
	var tail_root: Node3D = null
	var body_scale: float = 1.0
	var revision: int = 0

	func _init() -> void:
		rig = BODY_PROFILE.ordinary_rig()

	## True for the identity's own body; a borrowed or custom form carries an id.
	func is_own() -> bool:
		return form_id.is_empty()


## Build the identity's own form for a pony: stable id, own name and fit, the identity's rig, no
## source marker or tail root, and the body's live scale. A provider overrides it with its form.
static func default_form(pony: Node3D) -> BodyForm:
	var form := BodyForm.new()
	if not is_instance_valid(pony):
		return form
	var identity: Variant = pony.get("identity")
	form.pony_id = PONY_ID.from(str(pony.get_meta("relationship_id", "")), identity)
	form.form_name = form.pony_id
	if identity != null:
		var display: Variant = identity.get("display_name")
		if display != null and not str(display).strip_edges().is_empty():
			form.form_name = str(display).strip_edges()
	form.fit_id = BODY_PROFILE.body_fit_id(pony)
	form.rig = BODY_PROFILE.rig_for_identity(identity)
	var live_scale: Variant = pony.get("body_scale")
	form.body_scale = maxf(float(live_scale), 0.1) if live_scale != null else 1.0
	return form
