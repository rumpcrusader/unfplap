extends SceneTree
## The anatomy attachment identity: the per-mare consent, the eligibility capability, the body
## profile and off-roster list, the provider assertion, the participation veto, the runtime gates
## and the body-owned marker.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_attach.gd

const ANATOMY := preload("res://mods/unfplap/anatomy/controller.gd")
const ANATOMY_BINDING := preload("res://mods/unfplap/anatomy/body_binding.gd")
const ANATOMY_SERVICE := preload("res://mods/unfplap/anatomy/service.gd")
const ATTACH := preload("res://mods/unfplap/anatomy/attach.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const CONSENT := preload("res://mods/unfplap/shared/consent.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const FACTS := preload("res://mods/unfplap/anatomy/facts.gd")
const MARE_REGISTRY := preload("res://mods/unfplap/registry/service.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

var failures := 0
var checks := 0

class FakeIdentity extends Resource:
	var id := ""
	var character_id := ""
	var filly := false
	var stallion := false

class FakePony extends Node3D:
	var identity: Resource
	var rig: Node
	var skeleton: Skeleton3D
	var hair_skeleton: Skeleton3D
	var hair_link: Node
	var head_width := 1.0
	var head_width_factor := 1.0
	var _far_mesh_shown := false


class FakeMain extends Node:
	var eligibility: Variant


class FakeRuntime extends Node:
	var context: RefCounted

	func anatomy_facts() -> RefCounted:
		return context


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _pony(id: String, filly := false, stallion := false) -> FakePony:
	var pony := FakePony.new()
	var identity := FakeIdentity.new()
	identity.id = id
	identity.filly = filly
	identity.stallion = stallion
	pony.identity = identity
	pony.set_meta("relationship_id", id)
	return pony


func run() -> void:
	# Consent defaults are deterministic and per-id, and an override wins.
	var a := CONSENT.defaults("twilight_sparkle")
	check(a.has("public") and a.has("anal") and a.has("oral"), "consent has all three keys")
	var over := CONSENT.resolve("twilight_sparkle", {"anal": true, "oral": false})
	check(bool(over.get("anal", false)), "consent anal override wins")
	check(not bool(over.get("oral", true)), "consent oral override wins")
	check(bool(CONSENT.resolve("twilight_sparkle", {}).get("public", false))
		== bool(a.get("public", false)), "empty override keeps defaults")
	check(not bool(a.get("public", true)), "no mare is public by default")

	# Eligibility is capability-scoped: the eligibility service answers the anatomy target, and
	# the base-game roster is not an attachment whitelist.
	var host := FakeMain.new()
	root.add_child(host)
	host.eligibility = ELIGIBILITY.new()
	host.eligibility.setup(host)
	var twilight := _pony("twilight_sparkle")
	check(bool(host.eligibility.eligible(twilight, ELIGIBILITY.Target.ANATOMY)),
		"base adult is eligible")
	var off_roster := _pony("not_a_base_mare")
	check(bool(host.eligibility.eligible(off_roster, ELIGIBILITY.Target.ANATOMY)),
		"off-roster adult is eligible")
	var filly := _pony("not_a_base_mare", true)
	check(not bool(host.eligibility.eligible(filly, ELIGIBILITY.Target.ANATOMY)),
		"identity filly is excluded")
	var stallion := _pony("not_a_base_mare", false, true)
	check(not bool(host.eligibility.eligible(stallion, ELIGIBILITY.Target.ANATOMY)),
		"stallion is excluded")
	var no_id := _pony("")
	check(not bool(host.eligibility.eligible(no_id, ELIGIBILITY.Target.ANATOMY)),
		"empty id is excluded")
	var no_identity := FakePony.new()
	check(not bool(host.eligibility.eligible(no_identity, ELIGIBILITY.Target.ANATOMY)),
		"no identity is excluded")
	var player := _pony("twilight_sparkle")
	player.name = "PlayerPony"
	check(not bool(host.eligibility.eligible(player, ELIGIBILITY.Target.ANATOMY)),
		"player pony is excluded")

	# A provider's `eligible` assertion overrides the identity's age flag; the participation block
	# is the anatomy target's veto, and the character target keeps her editable.
	var registered: Dictionary = MARE_REGISTRY.register(1, {
		"id": "provider_filly", "source": "test",
		"eligible": true, "profile": {"participation": {"anatomy": false}},
	})
	check(bool(registered.get("ok", false)), "the provider registers")
	var provider_filly := _pony("provider_filly", true)
	check(bool(host.eligibility.eligible(provider_filly, ELIGIBILITY.Target.CHARACTER)),
		"a provider's eligible assertion attaches a filly")
	check(not bool(host.eligibility.eligible(provider_filly, ELIGIBILITY.Target.ANATOMY)),
		"a participation opt-out blocks the anatomy target")
	MARE_REGISTRY.unregister(1, "provider_filly")

	# The act calls its consent callback with the key alone, so the facade binds the pony before
	# handing it down; the two-argument lookup stays the world-level API.
	var consent_service: Node = ANATOMY_SERVICE.new()
	root.add_child(consent_service)
	consent_service.call("setup", host)
	var consent_pony := _pony("fluttershy")
	root.add_child(consent_pony)
	var consent_controller: Node = consent_service.call("controller_for", consent_pony, null)
	var consent_call: Callable = consent_controller.get("consent")
	check(consent_call.get_argument_count() == 1,
		"the act's consent callback takes the key alone")
	check(bool(consent_call.call("anal")) == bool(SETTINGS.consent("fluttershy").get("anal", false)),
		"the act's consent callback answers for its own pony")
	check(not bool(consent_call.call("nope")), "an unknown consent key is refused")
	consent_service.call("detach_controller", consent_pony)
	root.remove_child(consent_pony)
	consent_pony.free()
	root.remove_child(consent_service)
	consent_service.free()

	# A modded copy of a princess uses the canon body profile; an ordinary modded mare does not.
	var princess_copy := FakeIdentity.new()
	princess_copy.id = "custom_celestia"
	princess_copy.character_id = "celestia"
	check(ANATOMY.body_profile(princess_copy).size() == 3,
		"a modded Celestia copy uses the princess body profile")
	var ordinary_identity := FakeIdentity.new()
	ordinary_identity.id = "not_a_base_mare"
	check(ANATOMY.body_profile(ordinary_identity).is_empty(),
		"an ordinary modded mare uses the normal body profile")
	check(ANATOMY.body_profile(null).is_empty(), "no identity has no body profile")

	# The anatomy body binding stores the presented form, creates one controller and updates its
	# facts when the runtime attaches later; a revised form refreshes the same controller.
	var body_main := FakeMain.new()
	root.add_child(body_main)
	body_main.eligibility = host.eligibility
	var body_service: Node = ANATOMY_SERVICE.new()
	root.add_child(body_service)
	body_service.call("setup", body_main)
	var body_pony := _pony("fluttershy")
	root.add_child(body_pony)
	var own_form := BODY_FORM.default_form(body_pony)
	var binding: RefCounted = ANATOMY_BINDING.new()
	binding.call("setup", body_service)
	check(str(binding.call("binding_id")) == "anatomy", "the anatomy binding names itself")
	binding.call("bind_body", body_pony, own_form)
	var body_controller: Node = body_service.call("controller", body_pony)
	check(is_instance_valid(body_controller) and body_controller.call("form") == own_form,
		"the anatomy binding creates one controller with the presented form")
	check(body_service.call("form_for", body_pony) == own_form,
		"the anatomy facade keeps the form the binding stored")
	var facts_a: RefCounted = FACTS.new()
	var runtime_a := FakeRuntime.new()
	runtime_a.context = facts_a
	root.add_child(runtime_a)
	check(body_service.call("bind", body_pony, runtime_a) == body_controller,
		"a later runtime bind reuses the controller the binding created")
	var attach_a: Object = body_controller.get("attach") as Object
	check(body_controller.get("facts") == facts_a \
		and attach_a != null and attach_a.get("facts") == facts_a,
		"the reused controller receives the runtime facts, not its default context")
	var facts_b: RefCounted = FACTS.new()
	var runtime_b := FakeRuntime.new()
	runtime_b.context = facts_b
	root.add_child(runtime_b)
	body_service.call("bind", body_pony, runtime_b)
	var attach_b: Object = body_controller.get("attach") as Object
	check(body_controller.get("facts") == facts_b \
		and attach_b != null and attach_b.get("facts") == facts_b,
		"a second bind updates the same controller's facts")
	var late_form := BODY_FORM.default_form(body_pony)
	late_form.form_id = "borrowed_form"
	late_form.fit_id = "fluttershy"
	binding.call("refresh_body", body_pony, late_form)
	check(body_controller.call("form") == late_form,
		"a revised form refreshes the same controller without a second one")
	check(ANATOMY._same_rig_and_fit(own_form, late_form),
		"a form revision with the same rig and fit is a no-op refresh")
	var changed_fit := BODY_FORM.default_form(body_pony)
	changed_fit.fit_id = "borrowed_fit"
	check(not ANATOMY._same_rig_and_fit(own_form, changed_fit),
		"a changed fit re-applies the anatomy form")
	binding.call("unbind_body", body_pony)
	check(body_service.call("controller", body_pony) == null,
		"the anatomy binding releases the controller")
	check(body_service.call("form_for", body_pony) == null,
		"the anatomy binding drops the form on unbind")
	body_pony.free()
	runtime_a.free()
	runtime_b.free()
	body_service.call("shutdown")
	root.remove_child(body_service)
	body_service.free()
	root.remove_child(body_main)
	body_main.free()

	# The Characters selector lists only live off-roster mares.
	var live_ids: Array[String] = ANATOMY.off_roster_ids(
		["not_a_base_mare", "twilight_sparkle"], SETTINGS.CHARACTER_ORDER)
	check(live_ids.size() == 1 and live_ids[0] == "not_a_base_mare",
		"the Characters selector lists live off-roster mares")

	# A profile keeps its custom prompts and poses when consent is merged.
	var base: Dictionary = SETTINGS._filled_default()
	var characters := {"twilight_sparkle": {
		"consent": {"anal": true},
		"event_prompts": {"climax": "custom"},
		"poses": {"missionary": {"rump_drop_deg": 12.0}},
	}}
	var profile: Dictionary = SETTINGS.profile_for(base, characters, "twilight_sparkle")
	check(profile.has("consent"), "profile carries consent")
	check(str((profile.get("event_prompts", {}) as Dictionary).get("climax", "")) == "custom",
		"consent merge preserves event prompts")
	check(absf(float(((profile.get("poses", {}) as Dictionary).get("missionary", {}) as Dictionary)
		.get("rump_drop_deg", 0.0)) - 12.0) < 0.001, "consent merge preserves pose overrides")

	# No act controller means all anatomy action gates are closed.
	var runtime: Node = RUNTIME.new()
	check(not bool(runtime.call("anatomy_hole_ready")), "hole gate closed without an act")
	check(not bool(runtime.call("anatomy_oral_ready")), "oral gate closed without an act")
	check(not bool(runtime.call("anatomy_actions_ready")), "all anatomy gates closed without an act")
	# The refresh binds the reactions facade to her node, which is what the standing offer's rump
	# anchor reads. Without it the act-key hint never appears.
	var rump_pony := Node3D.new()
	get_root().add_child(rump_pony)
	runtime.pony = rump_pony
	check(not runtime.call("rump_anchor").is_finite(),
		"no refresh leaves the rump anchor unbound")
	runtime.call("_anatomy_refresh")
	check(runtime.call("rump_anchor").is_finite(),
		"the anatomy refresh binds the reactions scene for the rump anchor")
	get_root().remove_child(rump_pony)
	rump_pony.free()
	runtime.free()

	# A body that hides every mesh under its model without its own marker names that marker on
	# `anatomy_owned_meta`; the anatomy and its parts ride the same skeleton and must carry it.
	var owner_attach: RefCounted = ATTACH.new()
	var owner_pony := Node3D.new()
	var owner_skeleton := Skeleton3D.new()
	var owner_mesh := MeshInstance3D.new()
	owner_mesh.name = "UnfplapAnatomy"
	var owner_part := MeshInstance3D.new()
	owner_part.name = "UnfplapAnatomySkinStrip"
	var owner_body := MeshInstance3D.new()
	owner_body.name = "MareBody"
	owner_skeleton.add_child(owner_mesh)
	owner_skeleton.add_child(owner_part)
	owner_skeleton.add_child(owner_body)
	owner_pony.add_child(owner_skeleton)
	get_root().add_child(owner_pony)
	owner_attach.setup(owner_pony, owner_pony, FACTS.new())
	owner_attach.attached = true
	owner_attach.skeleton = owner_skeleton
	owner_pony.set_meta("anatomy_owned_meta", "chrysalis_own")
	owner_attach.mark_owned()
	check(owner_mesh.has_meta("chrysalis_own"), "the anatomy mesh carries the body marker")
	check(owner_part.has_meta("chrysalis_own"), "an anatomy part carries the body marker")
	check(not owner_body.has_meta("chrysalis_own"), "the body's own mesh is left alone")
	get_root().remove_child(owner_pony)
	owner_pony.free()

	for pony: Node in [twilight, filly, stallion, off_roster, no_id, no_identity, player]:
		if is_instance_valid(pony):
			pony.free()
	print("ANATOMY_ATTACH_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
