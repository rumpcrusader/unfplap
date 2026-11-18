extends "res://mods/unfplap/shared/body_binding.gd"
## The garment body binding: re-scans the worn pantyhose/panties nodes when a presented body
## changes form, so the cloth follows the new body instead of waiting for the adapter's fixed
## discovery fallback. The adapter is world-side and exposes a full `scan()`; it has no per-pony
## rebind, and a body change is rare enough for the one pass.
##
## Scope: world. `main.gd` registers one instance with `main.body_change` after the Pantyhose
## adapter exists. The target is a narrow host handle, so this file never preloads the adapter.
##
## See `docs/body_change.md` (`## Bindings`) and `docs/integrations.md`.

## The Pantyhose & Panties world adapter, for its public `scan()`.
var pantyhose: Node = null


func setup(adapter: Node) -> void:
	pantyhose = adapter


func binding_id() -> String:
	return "garments"


func bind_body(_body: Node3D, _form: BODY_FORM.BodyForm) -> void:
	_scan()


func refresh_body(_body: Node3D, _form: BODY_FORM.BodyForm) -> void:
	_scan()


func _scan() -> void:
	if is_instance_valid(pantyhose) and pantyhose.has_method("scan"):
		pantyhose.call("scan")
