extends "res://mods/unfplap/tests/support/suite.gd"
## The anatomy roster: the identity gate in `present`, the stable id, the presented form, the one
## controller per body, the revised form and the withdrawal of both the controller and the tail.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_attach.gd

const API := preload("res://mods/unfplap/anatomy/api.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const ROWS := preload("res://mods/unfplap/settings/rows.gd")


class FakeIdentity extends "res://mods/unfplap/tests/support/fakes/fake_identity.gd":
	pass


class FakeEligibility extends "res://mods/unfplap/eligibility/service.gd":
	var allow := true
	var calls := 0

	func eligible(_pony: Node, _target: Target = Target.ACT) -> bool:
		calls += 1
		return allow


class FakePony extends Node3D:
	var identity: Resource


func _pony(id: String) -> FakePony:
	var pony := FakePony.new()
	var identity := FakeIdentity.new()
	identity.id = id
	pony.identity = identity
	pony.set_meta("relationship_id", id)
	root.add_child(pony)
	return pony


func run() -> void:
	var pony := _pony("twilight_sparkle")
	check(PONY_ID.of(pony) == "twilight_sparkle", "the relationship id is the stable id")

	var eligibility := FakeEligibility.new()
	var api: API = API.new()
	root.add_child(api)
	api.bind_eligibility(eligibility)
	api.present(pony)
	var controller := api.parts.controller(pony)
	check(is_instance_valid(controller), "present creates one controller")
	check(eligibility.calls == 1, "present asks the identity gate once")
	var stored: BODY_FORM.BodyForm = api.parts.form_for(pony)
	check(stored != null and stored.is_own() and stored.pony_id == "twilight_sparkle",
		"a null form presents the body's own default")

	# The same body with a revised form updates the existing controller instead of adding one.
	var revised := BODY_FORM.default_form(pony)
	revised.revision = 2
	api.present(pony, revised)
	check(api.parts.controller(pony) == controller, "a revised form keeps the same controller")
	check(api.parts.form_for(pony) == revised, "the revised form is stored")

	# An ineligible body keeps its stored form and loses both the controller and the tail row.
	eligibility.allow = false
	api.present(pony, revised)
	check(api.parts.controller(pony) == null, "an ineligible body has no controller")
	check(api.parts.form_for(pony) == revised, "the ineligible body still remembers its form")
	var rows: Dictionary = api.parts.tail_seat.get("_rows")
	check(not rows.has(pony), "an ineligible body seats no tail")
	eligibility.allow = true
	api.present(pony, revised)
	check(is_instance_valid(api.parts.controller(pony)), "an eligible body presents again")
	check(eligibility.calls == 4, "each present asks the gate once")

	# The deprecated tail key changes nothing for anatomy: the tail follows the anatomy capability.
	SETTINGS.save_participation("twilight_sparkle", ROWS.Rows.of({"tail": false}))
	api.present(pony)
	check(is_instance_valid(api.parts.controller(pony)),
		"a deprecated tail opt-out leaves the anatomy controller")
	SETTINGS.reset_participation("twilight_sparkle")

	# The withdraw releases the controller, the tail row and the form; a frame later the deferred
	# tail retry does not resurrect the tail.
	api.withdraw(pony)
	await process_frame
	check(api.parts.controller(pony) == null, "withdraw releases the controller")
	check(api.parts.form_for(pony) == null, "withdraw forgets the form")
	check(api.parts.controllers.is_empty(), "no controller returns after the deferred retry")
	check(not (api.parts.tail_seat.get("_rows") as Dictionary).has(pony),
		"no tail row returns after the deferred retry")
	api.withdraw(pony)
	api.present(null)
	check(api.parts.controller(null) == null, "a null body presents nothing")

	# Absent identity fails closed: the form is stored, nothing is presented.
	var unbound: API = API.new()
	root.add_child(unbound)
	var body := _pony("rainbow_dash")
	unbound.present(body)
	check(unbound.parts.controller(body) == null, "an unbound anatomy creates no controller")
	check(unbound.parts.form_for(body) != null, "an unbound anatomy still stores the form")
	unbound.shutdown()
	root.remove_child(unbound)
	unbound.free()

	api.shutdown()
	root.remove_child(api)
	api.free()
	for node: Node in [pony, body]:
		root.remove_child(node)
		node.free()
	finish()
