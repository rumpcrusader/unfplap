extends "res://mods/unfplap/shared/body_binding.gd"
## The stock smack body binding: hands a presented body to the outside-act smack layer again
## when its form changes, so a body the entry has not seen yet joins the pack stream.
## `pony_ready()` is idempotent, so a revision is a quiet no-op.
## See `docs/body_change.md` (`## Bindings`) and `docs/audio.md`.

## The outside-act stock smack layer, for its public `pony_ready(pony)`.
var adapter: Node = null


func setup(smack: Node) -> void:
	adapter = smack


func binding_id() -> String:
	return "stock_smack"


func bind_body(body: Node3D, _form: BODY_FORM.BodyForm) -> void:
	_ready_pony(body)


func refresh_body(body: Node3D, _form: BODY_FORM.BodyForm) -> void:
	_ready_pony(body)


func _ready_pony(body: Node3D) -> void:
	if is_instance_valid(adapter) and adapter.has_method("pony_ready"):
		adapter.call("pony_ready", body)
