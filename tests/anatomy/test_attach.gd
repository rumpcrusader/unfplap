extends "res://mods/unfplap/tests/support/suite.gd"
## The anatomy roster: the stable id, the presented form, the one controller per body, the
## revised form and the withdrawal. Eligibility stays in the roster and is tested there.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_attach.gd

const API := preload("res://mods/unfplap/anatomy/api.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")


class FakeIdentity extends "res://mods/unfplap/tests/support/fakes/fake_identity.gd":
	pass

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

	var api: API = API.new()
	root.add_child(api)
	api.present(pony)
	var controller := api.parts.controller(pony)
	check(is_instance_valid(controller), "present creates one controller")
	var stored: BODY_FORM.BodyForm = api.parts.form_for(pony)
	check(stored != null and stored.is_own() and stored.pony_id == "twilight_sparkle",
		"a null form presents the body's own default")

	# The same body with a revised form updates the existing controller instead of adding one.
	var revised := BODY_FORM.default_form(pony)
	revised.revision = 2
	api.body_changed(pony, revised)
	check(api.parts.controller(pony) == controller, "a revised form keeps the same controller")
	check(api.parts.form_for(pony) == revised, "the revised form is stored")

	api.reseat_tail(pony)
	api.withdraw_tail(pony)
	check(api.parts.controller(pony) == controller, "withdrawing the tail keeps the controller")

	api.withdraw(pony)
	check(api.parts.controller(pony) == null, "withdraw releases the controller")
	api.withdraw(pony)
	api.present(null)
	check(api.parts.controller(null) == null, "a null body presents nothing")

	api.shutdown()
	root.remove_child(api)
	api.free()
	root.remove_child(pony)
	pony.free()
	finish()
