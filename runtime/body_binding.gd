extends "res://mods/unfplap/shared/body_binding.gd"
## The runtime body binding: one world binding owns the per-pony runtime's body-bound systems.
## It looks the runtime up through the entry's public `runtime_for(pony)` and hands it the form;
## the runtime decides whether it is idle, live or suspended and never creates a second runtime.
##
## Scope: world. `main.gd` registers one instance with `main.body_change` after the service and the
## entry exist. The target is a narrow host handle, so this file never preloads `main.gd` or
## `runtime.gd`, and an unbind never runs the act exit.
##
## See `docs/runtime.md` (`## Body swap`) and `docs/body_change.md`.

## The entry node, for its public `runtime_for(pony)` and nothing else.
var host: Node = null


func setup(host_node: Node) -> void:
	host = host_node


func binding_id() -> String:
	return "runtime"


func bind_body(body: Node3D, form: BODY_FORM.BodyForm) -> void:
	_dispatch("bind_body_services", body, form)


func refresh_body(body: Node3D, form: BODY_FORM.BodyForm) -> void:
	_dispatch("refresh_body_services", body, form)


## A body leaving the tree takes its runtime with it; the runtime's own `_exit_tree()` restores
## what it holds. This binding must never run `_end_session()`.
func unbind_body(_body: Node3D) -> void:
	pass


func _dispatch(method: StringName, body: Node3D, form: BODY_FORM.BodyForm) -> void:
	var runtime := _runtime_for(body)
	if runtime != null and runtime.has_method(method):
		runtime.call(method, body, form)


func _runtime_for(body: Node3D) -> Node:
	if not is_instance_valid(body) or not is_instance_valid(host) \
			or not host.has_method("runtime_for"):
		return null
	var runtime: Variant = host.call("runtime_for", body)
	if runtime is Node and is_instance_valid(runtime) and not (runtime as Node).is_queued_for_deletion():
		return runtime as Node
	return null
