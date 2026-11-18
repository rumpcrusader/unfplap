extends "res://mods/unfplap/shared/body_binding.gd"
## The LOD body binding: drops a presented body's near/far caches and re-arms its near mesh when
## the body form is applied or revised, so the visible body is the form the descriptor names.
## The world system is `main.gd`; the target is a narrow host handle, so this file never preloads
## `main.gd` or `runtime.gd`.
##
## Scope: world. `main.gd` registers one instance with `main.body_change` after the service exists.
##
## See `docs/body_change.md` (`## Lifecycle`).

## The entry node, for its public `refresh_body_lod(pony)`.
var host: Node = null


func setup(host_node: Node) -> void:
	host = host_node


func binding_id() -> String:
	return "lod"


func bind_body(body: Node3D, _form: BODY_FORM.BodyForm) -> void:
	_refresh(body)


func refresh_body(body: Node3D, _form: BODY_FORM.BodyForm) -> void:
	_refresh(body)


func _refresh(body: Node3D) -> void:
	if is_instance_valid(host) and host.has_method("refresh_body_lod"):
		host.call("refresh_body_lod", body)
