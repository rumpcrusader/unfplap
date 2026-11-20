extends "res://mods/unfplap/shared/body_binding.gd"
## Forwards the presented body's form to the anatomy facade, so the controller and the tail
## seat stay in step with it.
## Scope: world. Never preloads `main.gd` or `runtime.gd`.
## See `docs/anatomy.md` (`## Attachment and identity`).

const SERVICE := preload("res://mods/unfplap/anatomy/service.gd")

var service: SERVICE = null


func setup(anatomy_service: SERVICE) -> void:
	service = anatomy_service


func binding_id() -> String:
	return "anatomy"


func bind_body(body: Node3D, form: BODY_FORM.BodyForm) -> void:
	if is_instance_valid(service):
		service.bind_body(body, form)


func refresh_body(body: Node3D, form: BODY_FORM.BodyForm) -> void:
	if is_instance_valid(service):
		service.refresh_body(body, form)


func unbind_body(body: Node3D) -> void:
	if is_instance_valid(service):
		service.unbind_body(body)
