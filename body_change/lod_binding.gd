extends "res://mods/unfplap/shared/body_binding.gd"
## The LOD body binding: drops a presented body's near/far caches and re-arms its near mesh when
## the body form is applied or revised, so the visible body is the form the descriptor names.
## The world read is `WORLD.refresh_body_lod()`; this file never preloads the game.
##
## See `docs/body_change.md` (`## Bindings`).

const WORLD := preload("res://mods/unfplap/world/service.gd")


func binding_id() -> String:
	return "lod"


func bind_body(body: Node3D, _form: BODY_FORM.BodyForm) -> void:
	WORLD.refresh_body_lod(body)


func refresh_body(body: Node3D, _form: BODY_FORM.BodyForm) -> void:
	WORLD.refresh_body_lod(body)
