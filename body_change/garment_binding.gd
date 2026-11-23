extends "res://mods/unfplap/shared/body_binding.gd"
## The garment body binding: one worn-garment scan when a presented body changes form.
## The adapter exposes only a world-side `scan()`, so one pass is all a change can do.
## See `docs/body_change.md` (`## Bindings`).

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
		pantyhose.scan()
