extends SceneTree
## The typed body-change data and base contracts: BodyForm and its default form, the RigProfile
## mapping, BodyChange, and the BodyBinding/BodyChangePolicy virtual bases. Run:
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/body_change/test_service.gd

const BODY_BINDING := preload("res://mods/unfplap/shared/body_binding.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")
const POLICY := preload("res://mods/unfplap/shared/body_change_policy.gd")

var failures := 0
var checks := 0


class FakePony extends Node3D:
	var identity: Variant = null
	var body_scale := 1.0


class FakeSource extends Node:
	pass


class RecordingBinding extends "res://mods/unfplap/shared/body_binding.gd":
	var calls: Array[String] = []
	var last_body: Node3D = null
	var last_form: BODY_FORM.BodyForm = null

	func bind_body(body: Node3D, form: BODY_FORM.BodyForm) -> void:
		calls.append("bind")
		last_body = body
		last_form = form

	func refresh_body(body: Node3D, form: BODY_FORM.BodyForm) -> void:
		calls.append("refresh")
		last_body = body
		last_form = form

	func unbind_body(body: Node3D) -> void:
		calls.append("unbind")
		last_body = body


class RecordingPolicy extends "res://mods/unfplap/shared/body_change_policy.gd":
	var events: Array[int] = []

	func on_act_event(event: POLICY.ActEvent, _context: POLICY.BodyChangeActContext) -> void:
		events.append(int(event))

	func should_offer(_context: POLICY.BodyChangeActContext) -> bool:
		return true

	func offer_prompt() -> String:
		return "Show me the real you."

	func on_offer_accepted(_context: POLICY.BodyChangeActContext) -> POLICY.BodyChangeEffects:
		var effects := POLICY.BodyChangeEffects.new()
		effects.heat = 30.0
		return effects

	func on_reveal(_context: POLICY.BodyChangeActContext) -> POLICY.BodyChangeEffects:
		return POLICY.BodyChangeEffects.new()


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	_check_rig_profiles()
	_check_default_form()
	_check_body_change()
	_check_binding()
	_check_policy()
	print("BODY_CHANGE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_rig_profiles() -> void:
	var row: Array = BODY_PROFILE.WINKING_BODIES["celestia"]
	var copy := BODY_PROFILE.rig_for_identity({"id": "custom_princess", "character_id": "celestia"})
	check(copy.id == "celestia", "the typed rig uses the character_id key")
	check(is_equal_approx(copy.rear_y, float(row[0])), "the typed rig carries the table rear y")
	check(is_equal_approx(copy.rear_z, float(row[1])), "the typed rig carries the table rear z")
	check(is_equal_approx(copy.scale, float(row[2])), "the typed rig carries the table scale")
	var ordinary := BODY_PROFILE.rig_for_identity({"id": "fluttershy"})
	check(ordinary.is_ordinary(), "an off-table identity is the ordinary rig")
	check(is_equal_approx(ordinary.rear_y, BODY_PROFILE.WINKING_REAR_Y),
		"the ordinary rig uses the shared rear y")
	check(is_equal_approx(ordinary.rear_z, BODY_PROFILE.WINKING_REAR_Z),
		"the ordinary rig uses the shared rear z")
	check(is_equal_approx(ordinary.scale, 1.0), "the ordinary rig is at scale one")
	check(BODY_PROFILE.body_profile({"id": "luna"}).size() == 3,
		"the array accessor still maps a princess")
	check(BODY_PROFILE.body_profile({"id": "fluttershy"}).is_empty(),
		"the array accessor still maps an ordinary body")

	var pony := FakePony.new()
	pony.identity = {"id": "custom_princess", "character_id": "celestia"}
	check(BODY_PROFILE.rig_for_pony(pony).id == "celestia",
		"the typed pony rig follows the body-fit key")
	pony.set_meta("body_fit_id", "borrowed_unknown")
	check(BODY_PROFILE.rig_for_pony(pony).is_ordinary(),
		"an unknown body-fit key is the ordinary rig")
	pony.free()


func _check_default_form() -> void:
	var pony := FakePony.new()
	pony.identity = {"id": "fluttershy", "display_name": "Fluttershy"}
	pony.body_scale = 0.92
	var form := BODY_FORM.default_form(pony)
	check(form.pony_id == "fluttershy", "the default form keeps the stable identity id")
	check(form.form_id.is_empty() and form.is_own(), "the default form is her own form")
	check(form.form_name == "Fluttershy", "the default form uses her display name")
	check(form.fit_id == "fluttershy", "the default form uses the body-fit fallback")
	check(form.rig.is_ordinary(), "an ordinary identity gets the ordinary rig")
	check(form.owned_mesh_meta.is_empty(), "the default form has no source marker")
	check(form.tail_root == null, "the default form has no source tail root")
	check(is_equal_approx(form.body_scale, 0.92), "the default form reads the live body scale")
	check(form.revision == 0, "the default form starts at revision zero")

	pony.set_meta("relationship_id", "rarity")
	var named := BODY_FORM.default_form(pony)
	check(named.pony_id == "rarity", "relationship metadata wins the stable id")
	check(named.fit_id == "fluttershy", "the fit still follows the identity body")

	pony.identity = {"id": "custom_princess", "character_id": "celestia",
		"display_name": "Princess Copy"}
	pony.remove_meta("relationship_id")
	var princess := BODY_FORM.default_form(pony)
	check(princess.rig.id == "celestia", "the default rig follows the identity character")
	check(princess.fit_id == "celestia", "the fit follows character_id when no metadata is set")
	pony.set_meta("body_fit_id", "borrowed_unknown")
	var borrowed_fit := BODY_FORM.default_form(pony)
	check(borrowed_fit.fit_id == "borrowed_unknown", "body-fit metadata wins the fit")
	check(borrowed_fit.rig.id == "celestia",
		"the default rig stays the identity's, not the borrowed fit's")

	var borrowed_form := BODY_FORM.default_form(pony)
	borrowed_form.form_id = "borrowed_unknown"
	check(not borrowed_form.is_own(), "a form with an id is not her own form")

	var empty := BODY_FORM.default_form(null)
	check(empty.pony_id.is_empty(), "no pony has no stable id")
	check(empty.rig.is_ordinary(), "no pony still has a typed ordinary rig")
	pony.free()


func _check_body_change() -> void:
	var change := BODY_CHANGE.new()
	check(change.state == BODY_CHANGE.State.REQUESTED, "a change starts requested")
	check(change.origin == BODY_CHANGE.Origin.PROVIDER, "a change defaults to the provider origin")
	check(change.form == null and change.target_form_id.is_empty(),
		"a fresh change has no form or target")

	var source := FakeSource.new()
	var old_body := FakePony.new()
	old_body.name = "OldBody"
	var new_body := FakePony.new()
	new_body.name = "NewBody"
	var form := BODY_FORM.default_form(new_body)
	form.form_id = "borrowed_form"
	change.source = source
	change.origin = BODY_CHANGE.Origin.AI
	change.previous_body = old_body
	change.next_body = new_body
	change.target_form_id = "borrowed_form"
	change.form = form
	change.state = BODY_CHANGE.State.ADOPTED
	change.started_s = 12.5
	check(change.source == source, "the change keeps its source")
	check(change.origin == BODY_CHANGE.Origin.AI, "the change keeps the AI origin")
	check(change.previous_body == old_body and change.next_body == new_body,
		"the change keeps both presented bodies")
	check(change.target_form_id == "borrowed_form", "the change keeps its target form id")
	check(change.form == form and not change.form.is_own(),
		"the change keeps the prepared form")
	check(change.state == BODY_CHANGE.State.ADOPTED, "the change can be adopted")
	check(is_equal_approx(change.started_s, 12.5), "the change keeps its start time")
	source.free()
	old_body.free()
	new_body.free()


func _check_binding() -> void:
	var body := FakePony.new()
	body.identity = {"id": "fluttershy", "display_name": "Fluttershy"}
	var form := BODY_FORM.default_form(body)
	var binding := RecordingBinding.new()
	binding.bind_body(body, form)
	binding.refresh_body(body, form)
	binding.unbind_body(body)
	check(binding.calls == ["bind", "refresh", "unbind"],
		"a binding receives bind, refresh, then unbind")
	check(binding.last_body == body, "the binding receives the presented body")
	check(binding.last_form == form, "the binding receives the form")
	# The base's virtual defaults stay callable and inert for a service that overrides nothing.
	var base := BODY_BINDING.new()
	base.bind_body(body, form)
	base.refresh_body(body, form)
	base.unbind_body(body)
	body.free()


func _check_policy() -> void:
	var body := FakePony.new()
	body.identity = {"id": "fluttershy", "display_name": "Fluttershy"}
	var form := BODY_FORM.default_form(body)
	var change := BODY_CHANGE.new()
	change.form = form
	change.state = BODY_CHANGE.State.SETTLED

	var context := POLICY.BodyChangeActContext.new()
	context.pony_id = form.pony_id
	context.form = form
	context.change = change
	context.origin = BODY_CHANGE.Origin.PLAYER
	context.state = BODY_CHANGE.State.SETTLED
	context.offer_pending = true
	context.reveal_used = false
	context.by_player = true

	var base := POLICY.new()
	check(not base.should_offer(context), "the base policy offers no form")
	check(base.offer_prompt().is_empty(), "the base policy has no offer prompt")
	check(base.on_offer_accepted(context).is_empty(), "the base offer has no effects")
	check(base.on_reveal(context).is_empty(), "the base reveal has no effects")
	check(base.on_offer_accepted(context).comfort == 0, "a fresh effect marks no comfort")

	var policy := RecordingPolicy.new()
	policy.on_act_event(POLICY.ActEvent.CLIMAX_END, context)
	check(policy.events == [int(POLICY.ActEvent.CLIMAX_END)],
		"the policy receives the act milestone")
	check(policy.should_offer(context), "the fake policy offers its form")
	check(policy.offer_prompt() == "Show me the real you.", "the policy supplies its prompt")
	var effects := policy.on_offer_accepted(context)
	check(is_equal_approx(effects.heat, 30.0), "the policy supplies the generic heat effect")
	check(not effects.is_empty(), "a non-zero effect is not empty")
	check(context.origin == BODY_CHANGE.Origin.PLAYER and context.by_player,
		"the act context distinguishes the player's origin")

	var empty := POLICY.BodyChangeEffects.new()
	check(empty.is_empty(), "a fresh effects value is empty")
	empty.comfort = 1
	check(not empty.is_empty(), "a comfort mark makes the effects non-empty")
	body.free()
