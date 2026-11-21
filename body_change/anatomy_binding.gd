extends "res://mods/unfplap/shared/body_binding.gd"
## Forwards the presented body's form to the anatomy API, so the controller and the tail seat
## stay in step with it.
## Scope: world. Never preloads `main.gd` or `runtime.gd`.
## See `docs/body_change.md` and `docs/anatomy.md` (`## Attachment and identity`).

const API := preload("res://mods/unfplap/anatomy/api.gd")

var anatomy: API = null


func setup(anatomy_api: Node) -> void:
	anatomy = anatomy_api as API


func binding_id() -> String:
	return "anatomy"


func bind_body(body: Node3D, form: BODY_FORM.BodyForm) -> void:
	if is_instance_valid(anatomy):
		anatomy.present(body, form)


func refresh_body(body: Node3D, form: BODY_FORM.BodyForm) -> void:
	if is_instance_valid(anatomy):
		anatomy.body_changed(body, form)


func unbind_body(body: Node3D) -> void:
	if is_instance_valid(anatomy):
		anatomy.withdraw(body)
