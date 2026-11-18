extends SceneTree
## The typed body-change data, the base contracts and the body-change service: BodyForm and its
## default form, the RigProfile mapping, BodyChange, the BodyBinding/BodyChangePolicy virtual bases,
## the service's form store, legacy mirror, binding fan-out and source registry. Run:
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/body_change/test_service.gd

const BODY_BINDING := preload("res://mods/unfplap/shared/body_binding.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")
const GARMENT_BINDING := preload("res://mods/unfplap/body_change/garment_binding.gd")
const LOD_BINDING := preload("res://mods/unfplap/body_change/lod_binding.gd")
const POLICY := preload("res://mods/unfplap/shared/body_change_policy.gd")
const RUNTIME_BINDING := preload("res://mods/unfplap/runtime/body_binding.gd")
const SERVICE := preload("res://mods/unfplap/body_change/service.gd")
const SMACK_BINDING := preload("res://mods/unfplap/body_change/smack_binding.gd")

var failures := 0
var checks := 0


class FakePony extends Node3D:
	var identity: Variant = null
	var body_scale := 1.0
	var scale_calls: Array[float] = []

	func set_body_scale(value: float) -> void:
		scale_calls.append(value)
		body_scale = value


class FakeHost extends Node:
	var lines: Array[String] = []
	var runtimes: Dictionary = {}

	func debug(text: String) -> void:
		lines.append(text)

	func runtime_for(body: Node) -> Node:
		if not is_instance_valid(body):
			return null
		var runtime: Variant = runtimes.get(body)
		return runtime if runtime is Node else null


class FakeRuntime extends Node:
	var journal: Array[String] = []
	var last_body: Node3D = null
	var last_form: BODY_FORM.BodyForm = null

	func bind_body_services(body: Node3D, form: BODY_FORM.BodyForm) -> void:
		journal.append("bind")
		last_body = body
		last_form = form

	func refresh_body_services(body: Node3D, form: BODY_FORM.BodyForm) -> void:
		journal.append("refresh")
		last_body = body
		last_form = form


class FakeLodHost extends Node:
	var refreshes: Array[Node] = []

	func refresh_body_lod(body: Node) -> void:
		refreshes.append(body)


class FakeGarments extends Node:
	var scans := 0

	func scan() -> void:
		scans += 1


class FakeSmack extends Node:
	var handed_over: Array[Node] = []

	func pony_ready(body: Node) -> void:
		handed_over.append(body)


class FakeSource extends "res://mods/unfplap/body_change/source.gd":
	var id := "fake"
	var active := true
	var handled: Node3D = null
	var claimed: Node3D = null
	var change: BODY_CHANGE = null
	var form_to_return: BODY_FORM.BodyForm = null
	var policy_value: POLICY = null
	var prepared: Array[Node3D] = []
	var request_kind := ""
	var requested_form := ""
	var requested_origin: int = -1
	var request_result := true

	func source_id() -> String:
		return id

	func is_active() -> bool:
		return active

	func handles_pony(pony: Node3D) -> bool:
		return handled != null and pony == handled

	func change_in_progress() -> bool:
		return change != null

	func active_change() -> BODY_CHANGE:
		return change

	func request_form(_body: Node3D, form_id: String, origin: BODY_CHANGE.Origin) -> bool:
		request_kind = "form"
		requested_form = form_id
		requested_origin = int(origin)
		return request_result

	func request_own_form(_body: Node3D, origin: BODY_CHANGE.Origin) -> bool:
		request_kind = "own"
		requested_form = ""
		requested_origin = int(origin)
		return request_result

	func prepare_body(body: Node3D, _change: BODY_CHANGE) -> BODY_FORM.BodyForm:
		prepared.append(body)
		return form_to_return

	func claims_body(body: Node3D) -> bool:
		return claimed != null and body == claimed

	func policy() -> POLICY:
		return policy_value


class RecordingBinding extends "res://mods/unfplap/shared/body_binding.gd":
	var id := "recording"
	var calls: Array[String] = []
	var journal: Array[String] = []
	var last_body: Node3D = null
	var last_form: BODY_FORM.BodyForm = null

	func binding_id() -> String:
		return id

	func bind_body(body: Node3D, form: BODY_FORM.BodyForm) -> void:
		calls.append("bind")
		journal.append(id + ":bind")
		last_body = body
		last_form = form

	func refresh_body(body: Node3D, form: BODY_FORM.BodyForm) -> void:
		calls.append("refresh")
		journal.append(id + ":refresh")
		last_body = body
		last_form = form

	func unbind_body(body: Node3D) -> void:
		calls.append("unbind")
		journal.append(id + ":unbind")
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
	_check_world_bindings()
	_check_runtime_binding()
	_check_scale_clamp()
	_check_service()
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
	check(binding.binding_id() == "recording", "a binding names itself for the service log")
	binding.bind_body(body, form)
	binding.refresh_body(body, form)
	binding.unbind_body(body)
	check(binding.calls == ["bind", "refresh", "unbind"],
		"a binding receives bind, refresh, then unbind")
	check(binding.last_body == body, "the binding receives the presented body")
	check(binding.last_form == form, "the binding receives the form")
	# The base's virtual defaults stay callable and inert for a service that overrides nothing.
	var base := BODY_BINDING.new()
	check(base.binding_id().is_empty(), "the base binding has no log name")
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
	empty.heat = 1.0
	check(not empty.is_empty(), "a heat mark makes the effects non-empty")
	body.free()


func _check_world_bindings() -> void:
	var host := FakeHost.new()
	var service := SERVICE.new()
	service.setup(host)
	var lod_target := FakeLodHost.new()
	var lod: RefCounted = LOD_BINDING.new()
	lod.call("setup", lod_target)
	var garment_target := FakeGarments.new()
	var garments: RefCounted = GARMENT_BINDING.new()
	garments.call("setup", garment_target)
	var smack_target := FakeSmack.new()
	var smack: RefCounted = SMACK_BINDING.new()
	smack.call("setup", smack_target)
	check(str(lod.call("binding_id")) == "lod", "the LOD binding names itself")
	check(str(garments.call("binding_id")) == "garments", "the garment binding names itself")
	check(str(smack.call("binding_id")) == "stock_smack",
		"the stock smack binding names itself")
	check(service.register_binding(lod), "the LOD binding registers")
	check(service.register_binding(garments), "the garment binding registers")
	check(service.register_binding(smack), "the stock smack binding registers")

	var body := FakePony.new()
	body.name = "WorldBody"
	body.identity = {"id": "fluttershy", "display_name": "Fluttershy"}
	service.bind_body(body)
	check(lod_target.refreshes == [body], "the LOD binding refreshes the adopted body")
	check(garment_target.scans == 1, "the garment binding re-scans for the adopted body")
	check(smack_target.handed_over == [body], "the smack binding hands the adopted body over")
	var line := host.lines[host.lines.size() - 1] if not host.lines.is_empty() else ""
	check(line.contains("bindings=lod,garments,stock_smack"),
		"the service log names the world bindings in registration order")

	var revised := service.form_for(body)
	revised.revision = 1
	service.apply_form(body, revised)
	check(lod_target.refreshes.size() == 2, "a revised form refreshes the LOD once")
	check(garment_target.scans == 2, "a revised form re-scans the garments once")
	check(smack_target.handed_over.size() == 2, "a revised form re-readies the smack layer once")

	service.unbind_body(body)
	check(lod_target.refreshes.size() == 2 and garment_target.scans == 2
		and smack_target.handed_over.size() == 2,
		"an unbind does not refresh the world systems again")

	service.free()
	host.free()
	lod_target.free()
	garment_target.free()
	smack_target.free()
	body.free()


## The runtime binding dispatches through the entry's public runtime lookup and never owns the
## act: a body without a runtime is inert, and an unbind is not a teardown.
func _check_runtime_binding() -> void:
	var host := FakeHost.new()
	host.name = "RuntimeBindingHost"
	var binding: RefCounted = RUNTIME_BINDING.new()
	binding.call("setup", host)
	check(str(binding.call("binding_id")) == "runtime", "the runtime binding names itself")

	var body := FakePony.new()
	body.name = "RuntimeBody"
	body.identity = {"id": "fluttershy", "display_name": "Fluttershy"}
	var form := BODY_FORM.default_form(body)
	var runtime := FakeRuntime.new()
	runtime.name = "FakeRuntime"
	host.runtimes[body] = runtime
	binding.call("bind_body", body, form)
	check(runtime.journal == ["bind"], "a body with a runtime binds that runtime")
	check(runtime.last_body == body, "the runtime receives the presented body")
	check(runtime.last_form == form, "the runtime receives the form")
	binding.call("refresh_body", body, form)
	check(runtime.journal == ["bind", "refresh"],
		"a same-node revision refreshes the runtime")
	binding.call("unbind_body", body)
	check(runtime.journal == ["bind", "refresh"],
		"the runtime binding never runs an act teardown on unbind")

	var idle := FakePony.new()
	idle.name = "IdleBody"
	idle.identity = {"id": "rarity", "display_name": "Rarity"}
	binding.call("bind_body", idle, form)
	binding.call("refresh_body", idle, form)
	check(runtime.journal == ["bind", "refresh"],
		"a body without a runtime is left alone")

	host.runtimes[idle] = runtime
	runtime.name = "SecondRuntime"
	binding.call("bind_body", idle, form)
	check(runtime.journal == ["bind", "refresh", "bind"],
		"the binding follows the entry's runtime lookup")
	check(runtime.last_body == idle, "the second body's runtime is the target")

	host.free()
	runtime.free()
	body.free()
	idle.free()


func _check_scale_clamp() -> void:
	var host := FakeHost.new()
	var service := SERVICE.new()
	service.setup(host)
	var pony := FakePony.new()
	pony.name = "ScaleBody"
	pony.identity = {"id": "fluttershy", "display_name": "Fluttershy"}

	var huge := service.default_form(pony)
	huge.form_id = "huge"
	huge.body_scale = 99.0
	service.apply_form(pony, huge)
	check(is_equal_approx(huge.body_scale, SERVICE.BODY_SCALE_MAX),
		"an oversized provider scale is clamped to the game capsule's range")
	check(is_equal_approx(pony.body_scale, SERVICE.BODY_SCALE_MAX),
		"the descriptor and the body take the same clamped scale")
	check(is_equal_approx(pony.scale_calls.back(), SERVICE.BODY_SCALE_MAX),
		"the clamped scale goes through the game setter")

	var tiny := service.default_form(pony)
	tiny.form_id = "tiny"
	tiny.revision = 1
	tiny.body_scale = 0.01
	service.apply_form(pony, tiny)
	check(is_equal_approx(tiny.body_scale, SERVICE.BODY_SCALE_MIN),
		"an undersized provider scale is clamped to the game capsule's range")

	var broken := service.default_form(pony)
	broken.form_id = "broken"
	broken.revision = 2
	broken.body_scale = NAN
	service.apply_form(pony, broken)
	check(is_equal_approx(broken.body_scale, 1.0),
		"a non-finite provider scale falls back to the ordinary scale")
	check(is_equal_approx(pony.body_scale, 1.0),
		"the fallback scale reaches the body too")

	service.free()
	host.free()
	pony.free()


func _check_service() -> void:
	var host := FakeHost.new()
	var service := SERVICE.new()
	service.setup(host)

	var journal: Array[String] = []
	var one := RecordingBinding.new()
	one.id = "one"
	one.journal = journal
	var two := RecordingBinding.new()
	two.id = "two"
	two.journal = journal
	check(service.register_binding(one), "a body binding registers")
	check(service.register_binding(two), "a second body binding registers")
	check(service.register_binding(one), "registering the same binding twice is idempotent")
	check(not service.register_binding(RefCounted.new()),
		"a bare object is not a body binding")

	var pony := FakePony.new()
	pony.name = "PonyBody"
	pony.identity = {"id": "fluttershy", "display_name": "Fluttershy"}
	pony.body_scale = 0.92
	var own := service.form_for(pony)
	check(own.is_own() and own.fit_id == "fluttershy",
		"the service builds and stores the own form")
	check(service.form_for(pony) == own, "the form store returns the cached form")
	check(service.pony_id_for(pony) == "fluttershy", "the service exposes the stable pony id")
	check(service.form_for(null) == null, "a missing body has no form")
	check(service.pony_id_for(null).is_empty(), "a missing body has no stable id")

	# Built before the borrowed form mirrors its fit, as a provider's own form is.
	var own_again := service.default_form(pony)
	own_again.revision = 2

	var tail := Node3D.new()
	tail.name = "TailRoot"
	var borrowed := service.default_form(pony)
	borrowed.form_id = "borrowed_form"
	borrowed.form_name = "Borrowed Form"
	borrowed.fit_id = "borrowed_fit"
	borrowed.rig = BODY_PROFILE.rig_for_key("celestia")
	borrowed.owned_mesh_meta = "source_own"
	borrowed.tail_root = tail
	borrowed.body_scale = 1.2
	borrowed.revision = 0
	service.apply_form(pony, borrowed)
	check(journal == ["one:bind", "two:bind"], "bindings fan out in registration order")
	check(service.form_for(pony) == borrowed, "the applied form replaces the stored default")
	check(service.pony_id_for(pony) == "fluttershy", "a borrowed form keeps the stable identity")
	check(pony.get_meta("body_fit_id", "") == "borrowed_fit",
		"the mirror writes the body-fit key")
	check(pony.get_meta("anatomy_owned_meta", "") == "source_own",
		"the mirror writes the source marker")
	check(pony.get_meta("tail_pose_root", null) == tail, "the mirror writes the source tail root")
	check(is_equal_approx(pony.body_scale, 1.2), "the mirror writes the body scale")
	check(pony.scale_calls == [1.2],
		"the mirror resizes through the game's body-scale setter, not a bare field write")
	check(host.lines.size() == 1, "one form application logs one line")
	var line := host.lines[host.lines.size() - 1] if not host.lines.is_empty() else ""
	check(line.contains("body change") and line.contains("pony=fluttershy")
		and line.contains("form=borrowed_form") and line.contains("fit=borrowed_fit")
		and line.contains("rig=celestia") and line.contains("marker=source_own")
		and line.contains("bindings=one,two"),
		"the applied form logs the form, rig, marker and bindings")

	journal.clear()
	borrowed.revision = 1
	borrowed.fit_id = "late_fit"
	service.apply_form(pony, borrowed)
	check(journal == ["one:refresh", "two:refresh"],
		"a new revision refreshes in registration order")
	check(pony.get_meta("body_fit_id", "") == "late_fit",
		"the late revision updates the legacy fit")
	journal.clear()
	service.apply_form(pony, borrowed)
	check(journal.is_empty(), "an unchanged revision does not refresh the bindings")

	journal.clear()
	service.apply_form(pony, own_again)
	check(journal == ["one:refresh", "two:refresh"],
		"a return to the own form refreshes the bindings")
	check(not pony.has_meta("anatomy_owned_meta"), "the own form clears the source marker")
	check(not pony.has_meta("tail_pose_root"), "the own form clears the source tail root")
	check(pony.get_meta("body_fit_id", "") == "fluttershy",
		"the own form restores the identity fit")
	check(service.form_for(pony).is_own(), "the store keeps the returned own form")

	journal.clear()
	service.unbind_body(pony)
	check(journal == ["one:unbind", "two:unbind"], "unbind fans out in registration order")
	check(service.form_for(pony).is_own() and service.form_for(pony) != own_again,
		"unbinding drops the stored source form")
	journal.clear()
	service.unbind_body(pony)
	check(journal.is_empty(), "a second unbind is a no-op")

	var second := FakePony.new()
	second.name = "SecondBody"
	second.identity = {"id": "rarity", "display_name": "Rarity"}
	journal.clear()
	service.bind_body(second)
	check(journal == ["one:bind", "two:bind"], "a direct bind uses the registration order")
	check(second.get_meta("body_fit_id", "") == "rarity",
		"a direct bind mirrors the default form")
	journal.clear()
	service.bind_body(second)
	check(journal.is_empty(), "binding an already bound body is a no-op")
	journal.clear()
	service.refresh_body(second)
	check(journal == ["one:refresh", "two:refresh"],
		"a direct refresh re-reads the stored form")

	journal.clear()
	var source_own := service.default_form(second)
	source_own.owned_mesh_meta = "source_own"
	service.apply_form(second, source_own)
	check(journal == ["one:refresh", "two:refresh"],
		"a source own form replaces the default at the same revision")
	check(second.get_meta("anatomy_owned_meta", "") == "source_own",
		"the source own form mirrors its marker over the default")

	var source := FakeSource.new()
	source.name = "FakeSource"
	source.handled = second
	source.claimed = second
	var policy := RecordingPolicy.new()
	source.policy_value = policy
	var bare := Node.new()
	check(not service.register_source(bare), "a bare node is not a body-change source")
	bare.free()
	check(service.register_source(source), "a typed source registers")
	check(service.register_source(source), "registering the same source twice is idempotent")
	check(service.active_sources().size() == 1 and service.active_sources()[0] == source,
		"the active source list keeps the typed registration")
	check(service.source_for(second) == source, "the handling source is found for its body")
	check(service.source_for(pony) == null, "a body without a handling source has none")
	check(service.policy_for(second) == policy, "the service exposes the provider policy")
	check(service.policy_for(pony) == null, "a body without a source has no policy")

	source.active = false
	check(service.source_for(second) == null, "an inactive source does not handle a body")
	check(service.active_sources().is_empty(), "an inactive source is not active")
	check(service.policy_for(second) == null, "an inactive source exposes no policy")
	source.active = true

	check(service.request_form(second, "borrowed_form", BODY_CHANGE.Origin.PLAYER),
		"the service forwards a form request")
	check(source.request_kind == "form" and source.requested_form == "borrowed_form"
		and source.requested_origin == int(BODY_CHANGE.Origin.PLAYER),
		"the provider receives the form id and origin")
	check(service.request_own_form(second, BODY_CHANGE.Origin.AI),
		"the service forwards an own-form request")
	check(source.request_kind == "own" and source.requested_origin == int(BODY_CHANGE.Origin.AI),
		"the provider receives the own-form origin")
	source.request_result = false
	check(not service.request_form(second, "other", BODY_CHANGE.Origin.AI),
		"a refused provider request is reported")
	check(not service.request_form(pony, "other", BODY_CHANGE.Origin.AI),
		"a body without a source refuses the request")
	source.request_result = true

	var change := BODY_CHANGE.new()
	change.source = source
	change.origin = BODY_CHANGE.Origin.PROVIDER
	change.previous_body = second
	change.target_form_id = "borrowed_form"
	source.change = change
	service.notify_source_changed(source)
	check(service.active_change() == change, "a provider notification publishes the active change")
	check(service.active_change_for(second) == change,
		"the active change is readable for its old body")

	var idle_source := FakeSource.new()
	idle_source.name = "IdleSource"
	idle_source.handled = pony
	check(service.register_source(idle_source), "a second provider registers")
	var idle_change := BODY_CHANGE.new()
	idle_change.source = idle_source
	idle_change.origin = BODY_CHANGE.Origin.PROVIDER
	idle_change.previous_body = pony
	idle_change.state = BODY_CHANGE.State.REQUESTED
	idle_source.change = idle_change
	service.notify_source_changed(idle_source)
	check(service.active_change_for(pony) == idle_change,
		"the idle body's change is readable for that body")
	check(service.active_change_for(second) == change,
		"an idle body's change never overwrites an act's change")
	check(service.active_change() == change, "the compatibility read keeps the first live change")
	idle_change.state = BODY_CHANGE.State.SETTLED
	service.notify_source_changed(idle_source)
	check(service.active_change_for(pony) == null,
		"a settled change is cleared from the active map")
	check(service.active_change_for(second) == change,
		"another provider's settled change leaves the act's change")
	idle_source.change = null
	service.unregister_source(idle_source)
	idle_source.free()

	source.change = null
	service.notify_source_changed(source)
	check(service.active_change() == null, "a cleared provider change clears the active read")
	check(service.active_change_for(second) == null,
		"a cleared provider change clears its body entry")

	var late := service.default_form(second)
	late.form_id = "borrowed_form"
	late.form_name = "Borrowed Form"
	late.fit_id = "late_fit"
	late.rig = BODY_PROFILE.rig_for_key("celestia")
	late.owned_mesh_meta = "source_own"
	late.body_scale = 1.1
	late.revision = 3
	source.form_to_return = late
	source.change = change
	change.state = BODY_CHANGE.State.ADOPTED
	journal.clear()
	service.notify_body_ready(second)
	check(source.prepared.size() == 1 and source.prepared[0] == second,
		"the claiming provider prepares the new body once")
	check(journal == ["one:refresh", "two:refresh"],
		"a late provider form refreshes the bound body")
	check(second.get_meta("body_fit_id", "") == "late_fit",
		"the late provider form updates the legacy fit")
	check(change.form == late and change.next_body == second,
		"the active change keeps the prepared form and body")

	source.prepared.clear()
	service.notify_body_ready(pony)
	check(source.prepared.is_empty(), "a body the source does not claim is left alone")

	service.unregister_source(source)
	check(service.active_sources().is_empty(), "an unregistered source leaves the registry")
	check(service.active_change() == null,
		"unregistering the change's source clears the active read")

	var leaving := FakePony.new()
	leaving.name = "LeavingBody"
	leaving.identity = {"id": "rainbow_dash", "display_name": "Rainbow Dash"}
	root.add_child(leaving)
	service.bind_body(leaving)
	var leaving_source := FakeSource.new()
	leaving_source.handled = leaving
	leaving_source.claimed = leaving
	check(service.register_source(leaving_source), "the leaving body's source registers")
	var leaving_change := BODY_CHANGE.new()
	leaving_change.source = leaving_source
	leaving_change.previous_body = leaving
	leaving_change.state = BODY_CHANGE.State.REQUESTED
	leaving_source.change = leaving_change
	service.notify_source_changed(leaving_source)
	check(service.active_change_for(leaving) == leaving_change,
		"the leaving body's change is active before it leaves")
	journal.clear()
	root.remove_child(leaving)
	check(journal == ["one:unbind", "two:unbind"],
		"a body leaving the tree unbinds through the service")
	check(service.form_for(leaving).is_own(), "the leaving body drops its stored source form")
	check(service.active_change_for(leaving) == null,
		"a body leaving clears its active change")
	leaving_source.change = null
	service.unregister_source(leaving_source)
	leaving_source.free()
	leaving.free()

	service.free()
	host.free()
	source.free()
	second.free()
	pony.free()
	tail.free()
