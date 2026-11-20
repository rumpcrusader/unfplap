extends SceneTree
## The changelings adapter: installed listing, provider profile, and the body-fit/tail metadata.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/integrations/test_changelings.gd

const HYBRID_NEAR_MESH := preload("res://world/characters/hybrid_mare/hybrid_near_mesh.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_CHANGE_SERVICE := preload("res://mods/unfplap/body_change/service.gd")
const BODY_CHANGE_SOURCE := preload("res://mods/unfplap/body_change/source.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const CHANGELINGS := preload("res://mods/unfplap/integrations/changelings.gd")
const CHANGELINGS_POLICY := preload("res://mods/unfplap/integrations/changelings_policy.gd")
const POLICY := preload("res://mods/unfplap/shared/body_change_policy.gd")
const API := preload("res://mods/unfplap/api.gd")
const REGISTRY := preload("res://mods/unfplap/registry/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const ROWS := preload("res://mods/unfplap/settings/rows.gd")
const PROFILES := preload("res://mods/unfplap/shared/character_preferences.gd")
const IDENTITY := preload("res://mods/unfplap/anatomy/identity.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")

var failures := 0
var checks := 0


class FakeEligibility extends RefCounted:
	func eligible_id(_id: String) -> bool:
		return false


class FixtureHost extends Node:
	var api: Node
	var body_change: Node
	var game: Variant = null
	var eligibility: Variant = null


## Records the settings pass the settled shape runs instead of reaching the entry.
class ChangeSpy extends RefCounted:
	var calls := 0

	func _on_changed() -> void:
		calls += 1


## The registry's prepare hook, forwarded to the real service and recorded: the adapter's late
## prepare and installed list both reach `ponies`.
class RecordingBodyChange extends Node:
	var service: Node = null
	var prepared: Array[Node] = []

	func notify_body_ready(pony: Node) -> void:
		prepared.append(pony)
		service.call("notify_body_ready", pony)

	func installed_character_ids() -> Array[String]:
		return service.call("installed_character_ids")


class FakePopulation extends Node:
	var available: Dictionary = {}


class FakeGame extends Node:
	var population: Variant = null


class FakeIdentity extends Resource:
	var id := ""
	var character_id := ""
	var filly := false
	var stallion := false


class FakePony extends Node3D:
	var identity: Variant = null
	var shading_version := 3
	var head_width := 1.0
	var head_width_factor := 1.0
	var reference_face_enabled := false
	var own_meshes: Array = []
	var skeleton: Variant = null


class Gate extends RefCounted:
	var on := false

	func active() -> bool:
		return on


class FakeSourceMod extends Node:
	var actor: Variant = null
	var disguised_as := ""
	var busy := false
	var revealed := 0
	var disguised_to := ""
	var brought := 0

	func _ready() -> void:
		add_to_group(CHANGELINGS.GROUP)

	func reveal() -> void:
		revealed += 1
		busy = true

	func disguise(shape_id: String) -> void:
		disguised_to = shape_id
		busy = true

	func bring_out() -> void:
		brought += 1


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func _identity(id: String, character_id := "") -> FakeIdentity:
	var identity := FakeIdentity.new()
	identity.id = id
	identity.character_id = character_id
	return identity


func _own_body() -> FakePony:
	var pony := FakePony.new()
	pony.identity = _identity("chrysalis", "celestia")
	var rig := Node3D.new()
	rig.name = "Skeleton3D"
	pony.add_child(rig)
	pony.skeleton = rig
	var hair := Node3D.new()
	hair.name = "ChrysalisHair"
	pony.add_child(hair)
	var attach := Node3D.new()
	attach.name = "Hair_tail"
	rig.add_child(attach)
	var chain := Node3D.new()
	chain.name = "Chain"
	attach.add_child(chain)
	pony.own_meshes = [MeshInstance3D.new()]
	return pony


func run() -> void:
	REGISTRY.reset()
	var main := FixtureHost.new()
	main.name = "FixtureHost"
	main.eligibility = FakeEligibility.new()
	root.add_child(main)
	# The provider's world reads are the live scene: a bare world node is enough here.
	var world := FakeGame.new()
	root.add_child(world)
	WORLD.bind_world(world)
	var body_change := BODY_CHANGE_SERVICE.new()
	body_change.name = "UnfplapBodyChange"
	body_change.call("setup")
	root.add_child(body_change)
	main.body_change = body_change
	PONIES.shutdown()
	var recorder := RecordingBodyChange.new()
	recorder.name = "RecordingBodyChange"
	recorder.service = body_change
	root.add_child(recorder)
	PONIES.body_change = recorder
	PONIES.eligibility = ELIGIBILITY.new()
	var api := API.new()
	api.name = "UnfplapAPI"
	root.add_child(api)
	PONIES.api = api
	var gate := Gate.new()
	var pack := FakeSourceMod.new()
	pack.name = "FakeChangelingsMod"
	root.add_child(pack)
	var adapter := CHANGELINGS.new()
	adapter.name = "UnfplapChangelings"
	adapter.set("mod_active", Callable(gate, "active"))
	adapter.call("setup")
	root.add_child(adapter)
	check(bool(body_change.call("register_source", adapter)),
		"the adapter registers as a typed body-change source")
	var bare := Node.new()
	check(not bool(body_change.call("register_source", bare)),
		"a bare node is not a body-change source")
	bare.free()

	# With the pack installed she is a registered provider mare and an installed list entry.
	gate.on = true
	adapter.call("refresh")
	check(REGISTRY.has("chrysalis"), "the adapter registers Queen Chrysalis")
	check(adapter.is_processing(), "an active pack arms the adapter's own observation")
	var installed: Array = adapter.call("installed_character_ids")
	check(installed.size() == 1 and str(installed[0]) == "chrysalis",
		"the installed list names her while the pack is on")
	check(SETTINGS.character_name("chrysalis") == "Queen Chrysalis", "the provider name")
	var preferences := SETTINGS.preferences("chrysalis").raw()
	check(str(preferences.get("intensity", "")) == "firm", "approved intensity")
	check(str(preferences.get("pattern", "")) == "teasing", "approved pattern")
	check((preferences.get("touch", []) as Array) == ["caress", "kiss"], "approved touch")
	check((preferences.get("dislikes", []) as Array) == ["smack"], "approved dislikes")
	check((preferences.get("talk", []) as Array) == ["praise", "playful"], "approved talk")
	check(str(preferences.get("warmth", "")) == "slow", "approved warmth")
	check(str(preferences.get("tolerance", "")) == "normal", "approved tolerance")
	check(str(preferences.get("notes", "")).begins_with("You "), "second-person notes")
	var placed := SETTINGS.anatomy_placement_default("chrysalis").raw()
	check(near(float(placed.get("offset_y", 0.0)), 0.49), "provider placement Y")
	check(near(float(placed.get("offset_z", 0.0)), 0.271), "provider placement Z")
	check(near(float(placed.get("pitch_deg", 0.0)), 8.0), "provider placement pitch")
	check(near(float(placed.get("scale", 0.0)), 0.422), "provider placement scale")
	check(near(float(placed.get("tail_y", 0.0)), 0.04), "provider tail Y")
	check(near(float(placed.get("tail_z", 0.0)), 0.0), "provider tail Z")
	check(near(float(placed.get("tail_tilt_deg", 0.0)), 0.0), "provider tail tilt")

	# No base-catalog change, and no ghost entry once the pack is off.
	check(PROFILES.ORDER.size() == 103, "the base roster stays 103")
	check(not "chrysalis" in PROFILES.ORDER, "she is not a base-roster pony")
	check(not "chrysalis" in SETTINGS.CHARACTER_ORDER, "she is not in the base order")

	# Her own body uses her fit and exposes the visible spring-tail root. The adapter owns the
	# placement wrapper above the chain, so the anatomy editor can move it without a seat row.
	var own := _own_body()
	root.add_child(own)
	var holder: Node3D = own.get_node_or_null("Skeleton3D/Hair_tail") as Node3D
	var chain: Node3D = holder.get_node_or_null("Chain") as Node3D
	body_change.call("notify_body_ready", own)
	check(str(own.get_meta("body_fit_id", "")) == "chrysalis", "her own body uses her fit")
	check(str(own.get_meta("anatomy_owned_meta", "")) == "chrysalis_own",
		"her body names the marker its hide pass keeps")
	check(own.has_meta("tail_pose_root") and own.get_meta("tail_pose_root") == chain,
		"her spring tail root is exposed")
	var wrapper := chain.get_parent() as Node3D
	check(is_instance_valid(wrapper) and str(wrapper.name) == "UnfplapTailPlacement",
		"the adapter puts a placement wrapper above the chain")
	check(wrapper.get_parent() == holder, "the wrapper sits under the hair attachment")
	body_change.call("notify_body_ready", own)
	check(chain.get_parent() == wrapper, "a repeated prepare reuses the wrapper")
	check(holder.get_node_or_null("UnfplapTailPlacement/UnfplapTailPlacement") == null,
		"the wrapper is never nested")
	check(bool(adapter.call("has_tail_placement", own)),
		"her own body reports a source-owned tail placement")
	check(IDENTITY.body_fit_id(own) == "chrysalis", "the body-fit fallback reads the metadata")
	check(near(float(SETTINGS.anatomy_placement("chrysalis", "chrysalis").raw()
		.get("offset_y", 0.0)), 0.49), "her fit resolves the provider placement")
	var own_form: BODY_FORM.BodyForm = body_change.call("form_for", own)
	check(own_form.pony_id == "chrysalis" and own_form.is_own(),
		"her own form keeps the stable identity and the empty form id")
	check(own_form.form_name == "Queen Chrysalis", "her own form carries her name")
	check(own_form.fit_id == "chrysalis", "her own form uses her placement row")
	check(own_form.rig.id == "celestia", "her own form uses the princess rig")
	check(own_form.owned_mesh_meta == "chrysalis_own", "her own form keeps the source marker")
	check(own_form.tail_root == chain, "her own form returns the spring-tail root")
	check(adapter.call("source_id") == "changelings", "the source names its provider id")
	check(bool(adapter.call("is_active")), "the source reports the pack active")
	check(not bool(adapter.call("change_in_progress")), "no change is in progress yet")
	check(adapter.call("presented_form_id", own).is_empty(),
		"her own body presents no borrowed form id")

	# The tail keys apply from the pack's modelled root, like the seat from its reference dock.
	check(near(wrapper.position.y, 0.04), "her baked tail default is applied")
	var reseat_before := SETTINGS.reseat_tails.get_bool()
	SETTINGS.reseat_tails.set_bool(true)
	var tail_values := SETTINGS.anatomy_placement("chrysalis", "chrysalis").raw()
	tail_values["tail_y"] = 0.05
	tail_values["tail_z"] = 0.02
	tail_values["tail_tilt_deg"] = 10.0
	SETTINGS.save_anatomy_placement("chrysalis", ROWS.Rows.of(tail_values), "chrysalis")
	adapter.call("apply_tail_placement", own)
	check(near(wrapper.position.y, 0.05) and near(wrapper.position.z, 0.02),
		"the saved tail keys move the wrapper")
	check(not wrapper.basis.is_equal_approx(Basis.IDENTITY),
		"the saved tail tilt turns the wrapper")
	var tail_report := str(adapter.call("tail_placement_report"))
	check(tail_report.contains("chrysalis custom tail offset=(0.000,0.050,0.020)"),
		"the report names the applied offset")

	# Re-seat off returns the wrapper to the pack's modelled tail; on applies the saved keys.
	SETTINGS.reseat_tails.set_bool(false)
	adapter.call("apply_tail_placement", own)
	check(wrapper.transform.is_equal_approx(Transform3D.IDENTITY),
		"re-seat off returns the wrapper to identity")
	SETTINGS.reseat_tails.set_bool(true)
	adapter.call("apply_tail_placement", own)
	check(near(wrapper.position.y, 0.05), "re-seat on applies the saved keys")
	SETTINGS.save_anatomy_placement("chrysalis",
		SETTINGS.anatomy_placement_default("chrysalis", "chrysalis"), "chrysalis")
	adapter.call("apply_tail_placement", own)
	check(near(wrapper.position.y, 0.04), "reset returns her tail to the baked default")
	SETTINGS.reseat_tails.set_bool(reseat_before)

	# Her hair can arrive after the first prepare, even before the body has an identity. The
	# adapter-owned late check wraps the chain without the anatomy seat or `tail_ready()`.
	var late_body := FakePony.new()
	var late_mesh := MeshInstance3D.new()
	late_body.add_child(late_mesh)
	late_body.own_meshes = [late_mesh]
	root.add_child(late_body)
	body_change.call("notify_body_ready", late_body)
	check(str(late_body.get_meta("body_fit_id", "")) == "chrysalis",
		"an early own body still gets her fit")
	check(not late_body.has_meta("tail_pose_root"), "an early body has no tail root yet")
	var late_rig := Node3D.new()
	late_rig.name = "Skeleton3D"
	late_body.add_child(late_rig)
	late_body.skeleton = late_rig
	var late_hair := Node3D.new()
	late_hair.name = "ChrysalisHair"
	late_body.add_child(late_hair)
	var late_attach := Node3D.new()
	late_attach.name = "Hair_tail"
	var late_chain := Node3D.new()
	late_chain.name = "Chain"
	late_rig.add_child(late_attach)
	late_attach.add_child(late_chain)
	adapter.call("_late_tail_one", late_body)
	var late_wrapper := late_chain.get_parent() as Node3D
	check(is_instance_valid(late_wrapper) and str(late_wrapper.name) == "UnfplapTailPlacement",
		"the late check wraps a chain that arrives after an identity-less prepare")
	check(late_body.has_meta("tail_pose_root")
		and late_body.get_meta("tail_pose_root") == late_chain,
		"the late retry finds the tail root")
	check(bool(adapter.call("has_tail_placement", late_body)),
		"the late body reports a source-owned tail placement")
	check(recorder.prepared.has(late_body),
		"the late retry asks main to prepare the body again")
	late_body.free()

	# A body that does not expose its rig through `skeleton` still resolves the attachment by
	# search; runtime-built children have no scene owner.
	var fallback := FakePony.new()
	var fallback_root := Node3D.new()
	fallback_root.name = "Body"
	fallback.add_child(fallback_root)
	var fallback_attach := Node3D.new()
	fallback_attach.name = "Hair_tail"
	fallback_root.add_child(fallback_attach)
	var fallback_chain := Node3D.new()
	fallback_chain.name = "Chain"
	fallback_attach.add_child(fallback_chain)
	check(adapter.call("_tail_root", fallback) == fallback_chain,
		"the tail root falls back to a recursive attachment search")
	fallback.free()

	# A disguise copies the pony's fit and keeps only the source marker, with no custom tail root.
	var disguise := FakePony.new()
	disguise.identity = _identity("chrysalis", "")
	disguise.set_meta("geometry_variant", "changeling=fluttershy")
	root.add_child(disguise)
	disguise.set_meta("tail_pose_root", chain)
	body_change.call("notify_body_ready", disguise)
	check(str(disguise.get_meta("body_fit_id", "")) == "fluttershy",
		"a disguise uses the copied pony's fit")
	check(str(disguise.get_meta("anatomy_owned_meta", "")) == "chrysalis_own",
		"a disguise keeps the source marker")
	check(not disguise.has_meta("tail_pose_root"), "a disguise has no custom tail root")
	check(not bool(adapter.call("has_tail_placement", disguise)),
		"a disguise has no source-owned tail placement")
	check(adapter.call("presented_form_id", disguise) == "fluttershy",
		"a disguise presents the copied form id")
	check(SETTINGS.anatomy_placement("chrysalis", "fluttershy").raw()
		== SETTINGS.anatomy_placement("fluttershy").raw(), "a disguise does not borrow her placement")
	var disguise_form: BODY_FORM.BodyForm = body_change.call("form_for", disguise)
	check(disguise_form.pony_id == "chrysalis" and disguise_form.form_id == "fluttershy",
		"a borrowed regular form keeps the stable identity and the shape id")
	check(disguise_form.fit_id == "fluttershy", "a borrowed regular form uses the shape's fit")
	check(disguise_form.rig.is_ordinary(), "a borrowed regular form uses the ordinary rig")
	check(disguise_form.owned_mesh_meta == "chrysalis_own",
		"a borrowed regular form keeps the source marker")
	check(disguise_form.tail_root == null, "a borrowed regular form has no own tail root")

	# A borrowed princess shape takes the shared profile table's rig.
	var princess := FakePony.new()
	princess.identity = _identity("chrysalis", "")
	princess.set_meta("geometry_variant", "changeling=celestia")
	root.add_child(princess)
	body_change.call("notify_body_ready", princess)
	var princess_form: BODY_FORM.BodyForm = body_change.call("form_for", princess)
	check(princess_form.form_id == "celestia" and princess_form.fit_id == "celestia",
		"a borrowed princess form uses the shape's fit")
	check(princess_form.rig.id == "celestia", "a borrowed princess form uses the princess rig")
	check(princess_form.owned_mesh_meta == "chrysalis_own",
		"a borrowed princess form keeps the source marker")
	check(princess_form.tail_root == null, "a borrowed princess form has no own tail root")
	check(near(princess_form.body_scale, 1.0), "a borrowed form carries the live body scale")

	# An unrelated pony is never touched.
	var other := FakePony.new()
	other.identity = _identity("fluttershy")
	root.add_child(other)
	body_change.call("notify_body_ready", other)
	check(not other.has_meta("body_fit_id"), "an unrelated pony keeps the generic fit rule")

	# The typed body-change source registry: the adapter is the only object that reads the pack's
	# fields, and the base service owns the lookup and the optional provider forwards.
	check(bool(body_change.call("active")), "the service sees the active source")
	check(body_change.call("source_for", own) == adapter, "her body resolves to the source")
	check(body_change.call("source_for", other) == null, "an unrelated pony has no source")
	check((body_change.call("installed_character_ids") as Array) == ["chrysalis"],
		"the service lists the installed mare")
	check(bool(adapter.call("handles_pony", own)), "the source handles her own body")
	check(bool(adapter.call("handles_pony", disguise)), "the source handles a disguise")
	check(not bool(adapter.call("handles_pony", other)), "the source leaves other mares alone")
	var service_tail := SETTINGS.anatomy_placement("chrysalis", "chrysalis").raw()
	service_tail["tail_y"] = 0.03
	SETTINGS.save_anatomy_placement("chrysalis", ROWS.Rows.of(service_tail), "chrysalis")
	check(bool(body_change.call("has_tail_placement", own)),
		"the service forwards the tail-placement check")
	check(not bool(body_change.call("has_tail_placement", other)),
		"a body without a source has no tail placement")
	body_change.call("apply_tail_placement", own)
	check(near(wrapper.position.y, 0.03), "the service forwards the placement apply")
	check(str(body_change.call("tail_placement_report")).contains(
		"chrysalis custom tail offset=(0.000,0.030,0.000)"),
		"the service forwards the tail report")
	SETTINGS.save_anatomy_placement("chrysalis",
		SETTINGS.anatomy_placement_default("chrysalis", "chrysalis"), "chrysalis")
	body_change.call("apply_tail_placement", own)

	# A true-form change: the old body is captured, the new own body is claimed, and completion
	# leaves the typed change readable for the act's watcher.
	pack.actor = own
	pack.disguised_as = "fluttershy"
	check(bool(body_change.call("request_own_form", own, BODY_CHANGE.Origin.PROVIDER)),
		"the typed service starts a true-form change")
	check(bool(adapter.call("change_in_progress"))
		and adapter.call("active_change").previous_body == own,
		"the old body is held for the act")
	check(adapter.call("active_change").origin == BODY_CHANGE.Origin.PROVIDER,
		"the true-form change keeps its provider origin")
	check(adapter.call("target_form_id").is_empty(), "a true-form change has no shape target")
	check(pack.revealed == 1, "the source calls the pack's reveal")
	var begun: BODY_CHANGE = body_change.call("active_change_for", own)
	check(begun == adapter.call("active_change") and begun.source == adapter,
		"the provider announcement publishes the typed change")
	check(begun.state == BODY_CHANGE.State.REQUESTED and begun.target_form_id.is_empty(),
		"the new change starts requested with an empty target")
	var true_new := _own_body()
	root.add_child(true_new)
	check(bool(adapter.call("claims_body", true_new)), "the new own body is claimed")
	pack.actor = true_new
	pack.busy = false
	adapter.call("poll")
	check(adapter.call("active_change").next_body == true_new, "the new body is recorded")
	check(not bool(adapter.call("change_in_progress")),
		"poll ends the change when the pack is free")
	check(adapter.call("active_change").state == BODY_CHANGE.State.SETTLED,
		"the completed change keeps its settled read")
	check(body_change.call("active_change_for", true_new) == null,
		"the service clears a settled change from the active map")
	var true_form: BODY_FORM.BodyForm = body_change.call("form_for", true_new)
	check(true_form.is_own() and true_form.fit_id == "chrysalis",
		"the new own body presents her own form")

	# A named shape: the copied body's variant is its claim, not any changeling body.
	pack.actor = own
	pack.disguised_as = ""
	check(bool(body_change.call("request_form", true_new, "rarity", BODY_CHANGE.Origin.PROVIDER)),
		"the typed service starts a named change")
	check(adapter.call("active_change").previous_body == true_new, "the current body is held")
	check(adapter.call("active_change").target_form_id == "rarity", "the requested shape is held")
	check(adapter.call("target_form_id") == "rarity", "the typed target reads the same shape")
	check(pack.disguised_to == "rarity", "the source calls the pack's disguise")
	var shape_new := FakePony.new()
	shape_new.identity = _identity("chrysalis", "")
	shape_new.set_meta("geometry_variant", "changeling=rarity")
	root.add_child(shape_new)
	var wrong_shape := FakePony.new()
	wrong_shape.identity = _identity("chrysalis", "")
	wrong_shape.set_meta("geometry_variant", "changeling=fluttershy")
	root.add_child(wrong_shape)
	check(bool(adapter.call("claims_body", shape_new)), "the requested shape's body is claimed")
	check(not bool(adapter.call("claims_body", wrong_shape)),
		"another shape's body is not claimed")
	pack.actor = shape_new
	pack.busy = false
	adapter.call("poll")
	check(not bool(adapter.call("change_in_progress")), "the named change completes")

	# A named change's new body can spawn before the pack writes its variant. Its first prepare
	# must fit the requested shape, not her own, and it must not take the own tail wrapper.
	pack.actor = own
	pack.disguised_as = ""
	check(bool(body_change.call("request_form", own, "rarity", BODY_CHANGE.Origin.PROVIDER)),
		"a second named change starts")
	var early := FakePony.new()
	early.identity = _identity("chrysalis", "")
	var early_rig := Node3D.new()
	early_rig.name = "Skeleton3D"
	early.add_child(early_rig)
	early.skeleton = early_rig
	var early_hair := Node3D.new()
	early_hair.name = "ChrysalisHair"
	early.add_child(early_hair)
	var early_attach := Node3D.new()
	early_attach.name = "Hair_tail"
	early_rig.add_child(early_attach)
	var early_chain := Node3D.new()
	early_chain.name = "Chain"
	early_attach.add_child(early_chain)
	early.own_meshes = [MeshInstance3D.new()]
	root.add_child(early)
	pack.actor = early
	body_change.call("notify_body_ready", early)
	check(str(early.get_meta("body_fit_id", "")) == "rarity",
		"the new body is fitted as the target before its variant")
	check(not early.has_meta("tail_pose_root"), "the target fit exposes no own tail root")
	check(str(early.get_meta("anatomy_owned_meta", "")) == "chrysalis_own",
		"the target fit keeps the source marker")
	check(early_chain.get_parent() == early_attach,
		"the target fit adds no own tail wrapper")
	var early_form: BODY_FORM.BodyForm = body_change.call("form_for", early)
	check(early_form.form_id == "rarity" and early_form.fit_id == "rarity",
		"the new body's form is the requested shape")
	check(early_form.owned_mesh_meta == "chrysalis_own" and early_form.tail_root == null,
		"the new body's borrowed form keeps the marker and drops the own tail")
	var own_fit := str(own.get_meta("body_fit_id", ""))
	body_change.call("notify_body_ready", own)
	check(str(own.get_meta("body_fit_id", "")) == own_fit,
		"the old body is not refitted during the change")
	var old_form: BODY_FORM.BodyForm = body_change.call("form_for", own)
	check(old_form.is_own() and old_form.fit_id == "chrysalis",
		"the old body keeps its own form, not the new body's fit")
	var untouched := FakePony.new()
	untouched.identity = _identity("fluttershy")
	root.add_child(untouched)
	body_change.call("notify_body_ready", untouched)
	check(not untouched.has_meta("body_fit_id"),
		"an unrelated pony is not fitted during the change")

	# The variant appears: one late fit for the shape, with the anatomy and LOD refresh.
	early.set_meta("geometry_variant", "changeling=rarity")
	var late_before := recorder.prepared.size()
	var spy := ChangeSpy.new()
	CHANGE.on_changed(Callable(spy, "_on_changed"))
	var lod_key: String = HYBRID_NEAR_MESH.key(early)
	HYBRID_NEAR_MESH.cache[lod_key] = true
	adapter.call("poll")
	check(adapter.call("active_change").target_form_id == "rarity",
		"the delayed named change keeps its target")
	check(str(early.get_meta("body_fit_id", "")) == "rarity",
		"the settled shape refits the new body as the target")
	# The settle notifies the service once and the registry's late prepare notifies it again: the
	# adapter and the registry now read the one body-change handle the entry bound.
	# The settle notifies the service for the change and again for the late variant, then the
	# registry's one late prepare notifies it a third time: every path reads the one service.
	check(recorder.prepared.size() == late_before + 3 and recorder.prepared.back() == early,
		"the settled shape's one late prepare reaches the service")
	check(spy.calls == 1, "the settled shape runs one settings pass")
	CHANGE.off_changed(Callable(spy, "_on_changed"))
	check(not HYBRID_NEAR_MESH.cache.has(lod_key), "the settled shape rebuilds the body's LOD")
	adapter.call("poll")
	check(recorder.prepared.size() == late_before + 3,
		"the settled shape is not refitted again")
	pack.busy = false
	adapter.call("poll")
	check(not bool(adapter.call("change_in_progress")), "the delayed named change completes")

	# A body prepared before the pack exposes the requested shape first reads as her own form;
	# once the target becomes known the descriptor changes and the revision bumps for that body.
	pack.actor = own
	pack.disguised_as = ""
	pack.busy = false
	check(bool(body_change.call("request_form", own, "rarity", BODY_CHANGE.Origin.PROVIDER)),
		"a late-variant change starts")
	var late_variant := _own_body()
	root.add_child(late_variant)
	body_change.call("notify_body_ready", late_variant)
	var before_variant: BODY_FORM.BodyForm = body_change.call("form_for", late_variant)
	check(before_variant.is_own() and before_variant.revision == 0,
		"the body reads as her own form before the target is known")
	pack.actor = late_variant
	body_change.call("notify_body_ready", late_variant)
	var after_variant: BODY_FORM.BodyForm = body_change.call("form_for", late_variant)
	check(after_variant.form_id == "rarity" and after_variant.fit_id == "rarity",
		"the late target refits the body as the borrowed shape")
	check(after_variant.revision == before_variant.revision + 1,
		"the late variant bumps only that body's form revision")
	pack.busy = false
	adapter.call("poll")
	check(not bool(adapter.call("change_in_progress")), "the late-variant change completes")

	# The player's own words: the reveal ask, then an adult mare's name.
	pack.actor = true_new
	pack.disguised_as = ""
	check(bool(adapter.call("asks_form_change", "Please, show me the real you.")),
		"the ask phrase asks for a reveal")
	check(bool(adapter.call("asks_form_change", "show me the real her")),
		"the hint's own phrase asks for a reveal")
	check(bool(adapter.call("asks_form_change", "drop the disguise")),
		"the disguise phrase asks for a reveal")
	check(not bool(adapter.call("asks_form_change", "you are beautiful")),
		"ordinary talk is not a reveal ask")
	var typed_source: BODY_CHANGE_SOURCE = adapter
	check(typed_source.asks_form_change("show me the real her"),
		"the typed source exposes the reveal ask")
	check(typed_source.named_form("Rarity") == "rarity",
		"the typed source exposes the named form")
	check(str(adapter.call("named_form", "Rarity")) == "rarity",
		"a whole adult mare name resolves")
	check(str(adapter.call("named_form", "wear Rarity")) == "rarity",
		"an imperative wear request resolves")
	check(str(adapter.call("named_form", "become Rarity")) == "rarity",
		"an imperative become request resolves")
	check(str(adapter.call("named_form", "turn into Rarity")) == "rarity",
		"an imperative turn-into request resolves")
	check(str(adapter.call("named_form", "name yourself Rarity")) == "rarity",
		"an imperative name request resolves")
	check(str(adapter.call("named_form", "name Rarity")) == "rarity",
		"a leading name request resolves")
	check(str(adapter.call("named_form", "you are a rarity")).is_empty(),
		"a name mentioned without an imperative is not a choice")
	check(str(adapter.call("named_form", "I want Rarity")).is_empty(),
		"wanting a name is not an imperative request")
	check(str(adapter.call("named_form", "I don't want Rarity")).is_empty(),
		"a negated name is not a choice")
	check(str(adapter.call("named_form", "I don't want to wear Rarity")).is_empty(),
		"a negation wins over the request phrase")
	check(str(adapter.call("named_form", "your name is Rarity")).is_empty(),
		"a descriptive name is not a choice")
	check(str(adapter.call("named_form", "Twilight Sparkle")) == "twilight_sparkle",
		"a whole multi-word display name resolves")
	check(str(adapter.call("named_form", "wear Twilight Sparkle")) == "twilight_sparkle",
		"a multi-word name resolves with an imperative")
	check(str(adapter.call("named_form", "I don't want Twilight Sparkle")).is_empty(),
		"a negated multi-word name is not a choice")
	check(str(adapter.call("named_form", "your name is Twilight Sparkle")).is_empty(),
		"a descriptive multi-word name is not a choice")
	check(str(adapter.call("named_form", "Apple")).is_empty(),
		"an ambiguous name resolves to nothing")
	check(str(adapter.call("named_form", "wear Applesauce")).is_empty(),
		"a name word inside another word does not match")
	check(str(adapter.call("named_form", "Rarity or Fluttershy")).is_empty(),
		"two whole names resolve to nothing")
	check(str(adapter.call("named_form", "Chrysalis")).is_empty(),
		"she cannot be named as her own shape")
	var note_game := FakeGame.new()
	var note_population := FakePopulation.new()
	note_population.available = {
		"twist": "res://mods/unfplap/tools/pose_lab.tscn",
		"big_mcintosh": "res://mods/unfplap/tools/pose_lab.tscn",
		"sweetie_belle": "res://mods/unfplap/tools/pose_lab.tscn",
	}
	note_game.population = note_population
	note_game.add_child(note_population)
	root.add_child(note_game)
	main.game = note_game
	WORLD.bind_world(main.game)
	check(str(adapter.call("named_form_note", "Chrysalis")) == CHANGELINGS.NOTE_HERSELF,
		"naming herself gets the status")
	check(str(adapter.call("named_form_note", "Twist")) == CHANGELINGS.NOTE_CANNOT,
		"a schoolfilly is refused")
	check(str(adapter.call("named_form_note", "Big McIntosh")) == CHANGELINGS.NOTE_CANNOT,
		"a stallion is refused")
	check(str(adapter.call("named_form_note", "Sweetie Belle")) == CHANGELINGS.NOTE_CANNOT,
		"a filly from the base roster is refused")
	check(str(adapter.call("named_form_note", "you are beautiful")).is_empty(),
		"ordinary talk gets no status")
	main.game = null
	WORLD.bind_world(main.game)
	root.remove_child(note_game)
	note_game.free()

	# A live off-roster adult mare is a candidate through the registry's own list.
	var live_mare := FakePony.new()
	live_mare.name = "SunnyStar"
	live_mare.identity = _identity("sunny_star")
	root.add_child(live_mare)
	var live_runtime := Node.new()
	live_runtime.name = "LiveRuntime"
	PONIES.factory = func(_pony_node: Node) -> Node: return live_runtime
	PONIES.attach(live_mare)
	check(str(adapter.call("named_form", "Sunny Star")) == "sunny_star",
		"a live off-roster adult mare resolves")
	PONIES.shutdown()
	# The teardown drops the registry's handles; the rest of the suite still reads the API.
	PONIES.api = api
	live_runtime.free()
	root.remove_child(live_mare)
	live_mare.free()

	# The provider policy owns the offer timing, prompt and reveal effects.
	var policy: POLICY = adapter.call("policy")
	check(policy is CHANGELINGS_POLICY, "the adapter returns the typed changelings policy")
	var offer_context := POLICY.BodyChangeActContext.new()
	offer_context.form = own_form
	offer_context.act_active = true
	offer_context.pony_climaxes = 1
	check(policy.should_offer(offer_context),
		"the policy offers after the first climax in her own form")
	offer_context.pony_climaxes = 0
	check(not policy.should_offer(offer_context), "no offer before the first climax")
	offer_context.pony_climaxes = 1
	offer_context.act_active = false
	check(not policy.should_offer(offer_context), "no offer outside the active stage")
	offer_context.act_active = true
	offer_context.form = disguise_form
	check(not policy.should_offer(offer_context), "no offer while she wears a borrowed form")
	offer_context.form = own_form
	offer_context.offer_pending = true
	check(not policy.should_offer(offer_context), "no second offer while one is pending")
	offer_context.offer_pending = false
	offer_context.reveal_used = true
	check(not policy.should_offer(offer_context), "no offer after the reveal was used")
	offer_context.reveal_used = false
	offer_context.max_climaxes = 1
	offer_context.origin = BODY_CHANGE.Origin.PLAYER
	offer_context.by_player = true
	check(policy.should_offer(offer_context),
		"the player's origin and climax cap do not change the offer")
	check(not policy.offer_prompt().is_empty(), "the policy supplies the one offer prompt")
	var accepted := policy.on_offer_accepted(offer_context)
	check(accepted.is_empty(), "a named shape is neutral")
	var reveal := policy.on_reveal(offer_context)
	check(near(reveal.heat, 30.0), "the reveal adds the readiness heat")
	check(near(reveal.peak, 150.0), "the reveal records the peak")
	check(reveal.memory_kind == "form_reveal" and not reveal.cue.is_empty(),
		"the reveal names its memory and cue")

	# The shape she already wears is not a change, and the pack's population decides copyable.
	pack.actor = shape_new
	check(str(adapter.call("current_shape")) == "rarity", "the worn shape is readable")
	check(str(adapter.call("named_form", "Rarity")).is_empty(),
		"the worn shape is excluded")
	check(str(adapter.call("named_form_note", "Rarity")) == CHANGELINGS.NOTE_WEARING,
		"naming the worn shape gets the status")
	check(str(adapter.call("named_form_note", "I don't want Rarity")).is_empty(),
		"a negated worn name gets no status")
	var game := FakeGame.new()
	var population := FakePopulation.new()
	population.available = {"rarity": "res://mods/unfplap/tools/pose_lab.tscn"}
	game.population = population
	root.add_child(game)
	main.game = game
	WORLD.bind_world(main.game)
	check(str(adapter.call("named_form", "Fluttershy")).is_empty(),
		"a shape the pack cannot copy is excluded")
	check(str(adapter.call("named_form_note", "Fluttershy")) == CHANGELINGS.NOTE_CANNOT,
		"an uncopyable shape gets the status")
	population.available["fluttershy"] = "res://mods/unfplap/tools/pose_lab.tscn"
	pack.actor = true_new
	check(str(adapter.call("named_form", "Fluttershy")) == "fluttershy",
		"a copyable shape resolves")
	main.game = null
	WORLD.bind_world(main.game)
	root.remove_child(game)
	game.free()

	# The player origin travels on the change just started.
	pack.actor = own
	pack.disguised_as = "fluttershy"
	check(bool(body_change.call("request_own_form", own, BODY_CHANGE.Origin.PLAYER)),
		"the player-requested true-form change starts")
	check(adapter.call("active_change").origin == BODY_CHANGE.Origin.PLAYER,
		"the player origin marks the change")
	pack.busy = false
	adapter.call("poll")
	check(not bool(adapter.call("change_in_progress")), "the marked change completes")
	check(body_change.call("active_change_for", own) == null,
		"the service clears the player's completed change")

	# Her own AI starts a change: a busy edge with the act body as actor is observed without a
	# request call. The new disguise is claimed by identity before its shape is known.
	pack.actor = own
	pack.disguised_as = "fluttershy"
	pack.busy = false
	adapter.call("handles_pony", own)
	adapter.call("poll")
	pack.busy = true
	adapter.call("poll")
	check(bool(adapter.call("change_in_progress")), "an AI-started change is observed")
	check(adapter.call("active_change").previous_body == own, "the AI change holds the old body")
	check(adapter.call("active_change").origin == BODY_CHANGE.Origin.AI,
		"the AI change is not the player's")
	var ai_shape := FakePony.new()
	ai_shape.identity = _identity("chrysalis", "")
	ai_shape.set_meta("geometry_variant", "changeling=rarity")
	root.add_child(ai_shape)
	check(bool(adapter.call("claims_body", ai_shape)),
		"the AI body is claimed by identity before the shape is known")
	pack.actor = ai_shape
	adapter.call("poll")
	check(adapter.call("active_change").target_form_id == "rarity",
		"the AI target fills from the new body")
	pack.busy = false
	adapter.call("poll")
	check(not bool(adapter.call("change_in_progress")), "the AI change completes")

	# A busy on a body that is not the act pony never reaches the act.
	adapter.call("handles_pony", own)
	pack.actor = other
	pack.busy = false
	adapter.call("poll")
	pack.busy = true
	adapter.call("poll")
	check(not bool(adapter.call("change_in_progress")),
		"a busy on another body is not the act's change")
	pack.busy = false
	adapter.call("poll")

	# The adapter observes the pack on its own 0.1 s cadence; no runtime or base service pumps it.
	adapter.call("handles_pony", own)
	pack.actor = own
	pack.busy = false
	adapter.call("poll")
	adapter.set("_observe_clock", 0.0)
	pack.busy = true
	adapter.call("_process", CHANGELINGS.OBSERVE_S * 0.6)
	check(not bool(adapter.call("change_in_progress")),
		"the adapter observes the pack only at its cadence")
	adapter.call("_process", CHANGELINGS.OBSERVE_S * 0.6)
	check(bool(adapter.call("change_in_progress")), "the adapter observes the pack on the cadence tick")
	pack.busy = false
	adapter.call("_process", CHANGELINGS.OBSERVE_S * 2.0)
	check(not bool(adapter.call("change_in_progress")),
		"the adapter's own observation completes the change")

	# An AI reveal keeps the empty target: the new body is her own form, not a disguise.
	adapter.call("handles_pony", ai_shape)
	pack.actor = ai_shape
	pack.busy = false
	adapter.call("poll")
	pack.busy = true
	adapter.call("poll")
	check(bool(adapter.call("change_in_progress")), "an AI reveal is observed")
	var ai_own := _own_body()
	root.add_child(ai_own)
	pack.actor = ai_own
	adapter.call("poll")
	check(adapter.call("active_change").target_form_id.is_empty(),
		"an AI reveal keeps no shape target")
	check(bool(adapter.call("claims_body", ai_own)), "the AI true-form body is claimed")
	pack.busy = false
	adapter.call("poll")
	check(not bool(adapter.call("change_in_progress")), "the AI reveal completes")

	# The idle helper only asks the pack to bring her out; it is not a shape change.
	pack.actor = null
	pack.busy = false
	check(bool(adapter.call("request_appear")), "the idle action asks her out")
	check(pack.brought == 1 and not bool(adapter.call("change_in_progress")),
		"bringing her out is not a change")

	# The pack off unregisters the provider and empties the installed list.
	gate.on = false
	body_change.call("on_world", null)
	check(not REGISTRY.has("chrysalis"), "the layer is gone when the pack is off")
	check(not adapter.is_processing(), "a missing pack stops the adapter's observation")
	check((adapter.call("installed_character_ids") as Array).is_empty(),
		"no ghost entry without the pack")
	check(not bool(body_change.call("active")), "the service sees no active source")
	check((body_change.call("installed_character_ids") as Array).is_empty(),
		"the service lists no installed mare without the pack")
	check(SETTINGS.character_name("chrysalis") != "Queen Chrysalis",
		"the provider name is gone with the layer")

	# On again: idempotent registration and listing.
	gate.on = true
	body_change.call("on_world", null)
	body_change.call("on_world", null)
	check(REGISTRY.has("chrysalis"), "the layer returns with the pack")
	check(adapter.is_processing(), "the adapter observes again once the pack returns")
	var again: Array = adapter.call("installed_character_ids")
	check(again.size() == 1 and str(again[0]) == "chrysalis",
		"the installed entry returns once")

	adapter.call("shutdown")
	root.remove_child(adapter)
	adapter.free()
	for node: Node in [own, disguise, princess, other, true_new, shape_new, wrong_shape, ai_shape,
			ai_own, early, late_variant, untouched, pack]:
		root.remove_child(node)
		node.free()
	root.remove_child(body_change)
	body_change.free()
	api.call("_shutdown")
	root.remove_child(api)
	api.free()
	PONIES.shutdown()
	root.remove_child(recorder)
	recorder.free()
	root.remove_child(main)
	main.free()
	REGISTRY.reset()
	print("CHANGELINGS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
