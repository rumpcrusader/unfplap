extends "res://mods/unfplap/shared/body_binding.gd"
## The runtime body binding: one world binding owns the per-pony runtime's body-bound systems.
## Scope: world; `body_change.wire()` builds one instance with the rest of the chain.
## The runtime decides whether it is idle, live or suspended and never creates a second one.
## An unbind never runs the act exit.
## See `docs/runtime.md` (`### Suspend, adopt and resume`) and `docs/body_change.md`.

const PONIES := preload("res://mods/unfplap/ponies/service.gd")


func binding_id() -> String:
	return "runtime"


func bind_body(body: Node3D, form: BODY_FORM.BodyForm) -> void:
	_dispatch("bind_body_services", body, form)


func refresh_body(body: Node3D, form: BODY_FORM.BodyForm) -> void:
	_dispatch("refresh_body_services", body, form)


## A body leaving the tree takes its runtime with it; the runtime's own `_exit_tree()` restores
## what it holds. This binding must never run the act exit.
func unbind_body(_body: Node3D) -> void:
	pass


func _dispatch(method: StringName, body: Node3D, form: BODY_FORM.BodyForm) -> void:
	var runtime := _runtime_for(body)
	if runtime == null:
		return
	var session: Variant = runtime.get("act")
	if session != null and session.has_method(method):
		session.call(method, body, form)


func _runtime_for(body: Node3D) -> Node:
	if not is_instance_valid(body):
		return null
	var runtime: Node = PONIES.runtime_for(body)
	if is_instance_valid(runtime) and not runtime.is_queued_for_deletion():
		return runtime
	return null
