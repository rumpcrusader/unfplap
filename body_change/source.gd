extends "res://mods/unfplap/shared/service.gd"
## The documented provider base: a world node that observes its own pack and supplies body forms.
## Providers extend it by path; the service owns the transition and calls these hooks.

const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const POLICY := preload("res://mods/unfplap/shared/body_change_policy.gd")


## The stable provider id, for the service log and the source registry.
func source_id() -> String:
	return ""


## True while the provider's own pack or feature is available.
func is_active() -> bool:
	return false


## Re-read the provider's own pack availability and registration. Optional.
func refresh() -> void:
	pass


## True when this source handles the pony's presented body.
func handles_pony(_pony: Node3D) -> bool:
	return false


## True between a request and the change's settle or failure.
func change_in_progress() -> bool:
	return false


## The change this source is running, or null.
func active_change() -> BODY_CHANGE:
	return null


## Ask for a borrowed or custom form id. False when the request was refused.
func request_form(_body: Node3D, _form_id: String, _origin: BODY_CHANGE.Origin) -> bool:
	return false


## Ask for the identity's own form. False when the request was refused.
func request_own_form(_body: Node3D, _origin: BODY_CHANGE.Origin) -> bool:
	return false


## The next body's form, built before the act's systems attach to it.
## A late variant settles by preparing again with a bumped revision.
func prepare_body(_body: Node3D, _change: BODY_CHANGE) -> BODY_FORM.BodyForm:
	return null


## True when this provider owns the new body and the act may adopt it.
func claims_body(_body: Node3D) -> bool:
	return false


## The requested form id; empty for her own form.
func target_form_id() -> String:
	return ""


## The form id the body presents now; empty for her own form.
func presented_form_id(_body: Node3D) -> String:
	return ""


## True when the player's line asks for the identity's own form. Optional.
func asks_form_change(_text: String) -> bool:
	return false


## The form id the player's line names, or "" for none. Optional.
func named_form(_text: String) -> String:
	return ""


## A short status for a form that cannot be worn, or "" for ordinary talk. Optional.
func named_form_note(_text: String) -> String:
	return ""


## The provider's optional offer/reveal policy, or null.
func policy() -> POLICY:
	return null


## Character ids this provider installs even while they are away. Optional.
func installed_character_ids() -> Array[String]:
	var ids: Array[String] = []
	return ids


## True when this provider wants to place the pony's tail itself. Optional.
func has_tail_placement(_pony: Node3D) -> bool:
	return false


## Apply the provider's tail placement. Optional.
func apply_tail_placement(_pony: Node3D) -> void:
	pass


## One line per live source-owned tail, or "" for none. Optional.
func tail_placement_report() -> String:
	return ""
