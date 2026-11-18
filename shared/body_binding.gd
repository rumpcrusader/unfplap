extends RefCounted
## The typed base for one system attached to the presented body. A body-bound service extends this
## file by path and forwards to its own facade; the body-change service calls the methods and names
## the binding by `binding_id()` in its debug line. No `class_name`.
##
## No runtime behavior: the base answers with empty defaults.

const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")


## The short binding name for the service log; empty on the base.
func binding_id() -> String:
	return ""


## The presented body is adopted: attach to it and read its form.
func bind_body(_body: Node3D, _form: BODY_FORM.BodyForm) -> void:
	pass


## The same presented body carries a revised form: re-read the descriptor.
func refresh_body(_body: Node3D, _form: BODY_FORM.BodyForm) -> void:
	pass


## The presented body is leaving: release or hide this system's attachment.
func unbind_body(_body: Node3D) -> void:
	pass
