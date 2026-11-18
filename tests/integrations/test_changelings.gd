extends SceneTree
## The changelings adapter: installed listing, provider profile, and the body-fit/tail metadata.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/integrations/test_changelings.gd

const CHANGELINGS := preload("res://mods/unfplap/integrations/changelings.gd")
const SHAPE_CHANGE := preload("res://mods/unfplap/integrations/shape_change.gd")
const API := preload("res://mods/unfplap/api.gd")
const REGISTRY := preload("res://mods/unfplap/registry/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const PROFILES := preload("res://mods/unfplap/shared/character_preferences.gd")
const IDENTITY := preload("res://mods/unfplap/anatomy/identity.gd")

var failures := 0
var checks := 0


class FakeEligibility extends RefCounted:
	func eligible_id(_id: String) -> bool:
		return false


class FakeMain extends Node:
	var api: Node
	var live_ids: Array[String] = []
	var game: Variant = null
	var eligibility: Variant = null
	var late_prepares: Array[Node] = []

	func live_character_ids() -> Array[String]:
		return live_ids.duplicate()

	func prepare_pony_late(pony: Node) -> void:
		late_prepares.append(pony)


class FakePopulation extends Node:
	var available: Dictionary = {}


class FakeGame extends Node:
	var population: Variant = null


class FakeIdentity extends Resource:
	var id := ""
	var character_id := ""


class FakePony extends Node3D:
	var identity: Variant = null
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
	var main := FakeMain.new()
	main.name = "FakeMain"
	main.eligibility = FakeEligibility.new()
	root.add_child(main)
	var api := API.new()
	api.name = "UnfplapAPI"
	root.add_child(api)
	api.call("_bind", main)
	main.api = api
	var gate := Gate.new()
	var pack := FakeSourceMod.new()
	pack.name = "FakeChangelingsMod"
	root.add_child(pack)
	var adapter := CHANGELINGS.new()
	adapter.name = "UnfplapChangelings"
	adapter.set("mod_active", Callable(gate, "active"))
	adapter.call("setup", main)
	root.add_child(adapter)

	# With the pack installed she is a registered provider mare and an installed list entry.
	gate.on = true
	adapter.call("refresh")
	check(REGISTRY.has("chrysalis"), "the adapter registers Queen Chrysalis")
	var installed: Array = adapter.call("installed_character_ids")
	check(installed.size() == 1 and str(installed[0]) == "chrysalis",
		"the installed list names her while the pack is on")
	check(SETTINGS.character_name("chrysalis") == "Queen Chrysalis", "the provider name")
	var preferences := SETTINGS.preferences("chrysalis")
	check(str(preferences.get("intensity", "")) == "firm", "approved intensity")
	check(str(preferences.get("pattern", "")) == "teasing", "approved pattern")
	check((preferences.get("touch", []) as Array) == ["caress", "kiss"], "approved touch")
	check((preferences.get("dislikes", []) as Array) == ["smack"], "approved dislikes")
	check((preferences.get("talk", []) as Array) == ["praise", "playful"], "approved talk")
	check(str(preferences.get("warmth", "")) == "slow", "approved warmth")
	check(str(preferences.get("tolerance", "")) == "normal", "approved tolerance")
	check(str(preferences.get("notes", "")).begins_with("You "), "second-person notes")
	var placed := SETTINGS.anatomy_placement_default("chrysalis")
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
	adapter.call("prepare_pony", own)
	check(str(own.get_meta("body_fit_id", "")) == "chrysalis", "her own body uses her fit")
	check(str(own.get_meta("anatomy_owned_meta", "")) == "chrysalis_own",
		"her body names the marker its hide pass keeps")
	check(own.has_meta("tail_pose_root") and own.get_meta("tail_pose_root") == chain,
		"her spring tail root is exposed")
	var wrapper := chain.get_parent() as Node3D
	check(is_instance_valid(wrapper) and str(wrapper.name) == "UnfplapTailPlacement",
		"the adapter puts a placement wrapper above the chain")
	check(wrapper.get_parent() == holder, "the wrapper sits under the hair attachment")
	adapter.call("prepare_pony", own)
	check(chain.get_parent() == wrapper, "a repeated prepare reuses the wrapper")
	check(holder.get_node_or_null("UnfplapTailPlacement/UnfplapTailPlacement") == null,
		"the wrapper is never nested")
	check(bool(adapter.call("has_tail_placement", own)),
		"her own body reports a source-owned tail placement")
	check(IDENTITY.body_fit_id(own) == "chrysalis", "the body-fit fallback reads the metadata")
	check(near(float(SETTINGS.anatomy_placement("chrysalis", "chrysalis")
		.get("offset_y", 0.0)), 0.49), "her fit resolves the provider placement")

	# The tail keys apply from the pack's modelled root, like the seat from its reference dock.
	check(near(wrapper.position.y, 0.04), "her baked tail default is applied")
	var reseat_before := SETTINGS.reseat_tails.get_bool()
	SETTINGS.reseat_tails.set_bool(true)
	var tail_values := SETTINGS.anatomy_placement("chrysalis", "chrysalis")
	tail_values["tail_y"] = 0.05
	tail_values["tail_z"] = 0.02
	tail_values["tail_tilt_deg"] = 10.0
	SETTINGS.save_anatomy_placement("chrysalis", tail_values, "chrysalis")
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
		SETTINGS.anatomy_placement_default("chrysalis", false, "chrysalis"), "chrysalis")
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
	adapter.call("prepare_pony", late_body)
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
	check(main.late_prepares.has(late_body),
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

	# A disguise copies the pony's fit and drops the custom tail root.
	var disguise := FakePony.new()
	disguise.identity = _identity("chrysalis", "")
	disguise.set_meta("geometry_variant", "changeling=fluttershy")
	root.add_child(disguise)
	disguise.set_meta("tail_pose_root", chain)
	adapter.call("prepare_pony", disguise)
	check(str(disguise.get_meta("body_fit_id", "")) == "fluttershy",
		"a disguise uses the copied pony's fit")
	check(not disguise.has_meta("anatomy_owned_meta"), "a disguise has no body marker")
	check(not disguise.has_meta("tail_pose_root"), "a disguise has no custom tail root")
	check(not bool(adapter.call("has_tail_placement", disguise)),
		"a disguise has no source-owned tail placement")
	check(SETTINGS.anatomy_placement("chrysalis", "fluttershy")
		== SETTINGS.anatomy_placement("fluttershy"), "a disguise does not borrow her placement")

	# An unrelated pony is never touched.
	var other := FakePony.new()
	other.identity = _identity("fluttershy")
	root.add_child(other)
	adapter.call("prepare_pony", other)
	check(not other.has_meta("body_fit_id"), "an unrelated pony keeps the generic fit rule")

	# The generic source contract: the adapter is the only object that reads the pack's fields.
	var manager := SHAPE_CHANGE.new()
	manager.call("register", adapter)
	check(bool(manager.call("active")), "the manager sees the active source")
	check(manager.call("source_for", own) == adapter, "her body resolves to the source")
	check(manager.call("source_for", other) == null, "an unrelated pony has no source")
	check((manager.call("installed_character_ids") as Array) == ["chrysalis"],
		"the manager lists the installed mare")
	check(bool(adapter.call("handles_pony", own)), "the source handles her own body")
	check(bool(adapter.call("handles_pony", disguise)), "the source handles a disguise")
	check(not bool(adapter.call("handles_pony", other)), "the source leaves other mares alone")
	var manager_tail := SETTINGS.anatomy_placement("chrysalis", "chrysalis")
	manager_tail["tail_y"] = 0.03
	SETTINGS.save_anatomy_placement("chrysalis", manager_tail, "chrysalis")
	check(bool(manager.call("has_tail_placement", own)),
		"the manager forwards the tail-placement check")
	check(not bool(manager.call("has_tail_placement", other)),
		"a body without a source has no tail placement")
	manager.call("apply_tail_placement", own)
	check(near(wrapper.position.y, 0.03), "the manager forwards the placement apply")
	check(str(manager.call("tail_placement_report")).contains(
		"chrysalis custom tail offset=(0.000,0.030,0.000)"),
		"the manager forwards the tail report")
	SETTINGS.save_anatomy_placement("chrysalis",
		SETTINGS.anatomy_placement_default("chrysalis", false, "chrysalis"), "chrysalis")
	manager.call("apply_tail_placement", own)

	# A true-form change: the old body is captured, the new own body is claimed, and completion
	# clears the change while leaving the handles for the act's log.
	pack.actor = own
	pack.disguised_as = "fluttershy"
	check(bool(adapter.call("request_true_form")), "the source starts a true-form change")
	check(bool(adapter.call("is_changing")) and adapter.call("old_actor") == own,
		"the old body is held for the act")
	check(str(adapter.call("target")).is_empty(), "a true-form change has no shape target")
	check(pack.revealed == 1, "the source calls the pack's reveal")
	var true_new := _own_body()
	root.add_child(true_new)
	check(bool(adapter.call("claims_body", true_new)), "the new own body is claimed")
	pack.actor = true_new
	pack.busy = false
	adapter.call("poll")
	check(adapter.call("new_actor") == true_new, "the new body is readable")
	check(not bool(adapter.call("is_changing")), "poll ends the change when the pack is free")

	# A named shape: the copied body's variant is its claim, not any changeling body.
	pack.actor = own
	pack.disguised_as = ""
	check(bool(adapter.call("request_shape", "rarity")), "the source starts a named change")
	check(str(adapter.call("target")) == "rarity", "the requested shape is held")
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
	check(not bool(adapter.call("is_changing")), "the named change completes")

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
	root.remove_child(note_game)
	note_game.free()

	# A live off-roster adult mare is a candidate through the entry's list.
	main.live_ids = ["sunny_star"]
	check(str(adapter.call("named_form", "Sunny Star")) == "sunny_star",
		"a live off-roster adult mare resolves")
	main.live_ids = []

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
	check(str(adapter.call("named_form", "Fluttershy")).is_empty(),
		"a shape the pack cannot copy is excluded")
	check(str(adapter.call("named_form_note", "Fluttershy")) == CHANGELINGS.NOTE_CANNOT,
		"an uncopyable shape gets the status")
	population.available["fluttershy"] = "res://mods/unfplap/tools/pose_lab.tscn"
	pack.actor = true_new
	check(str(adapter.call("named_form", "Fluttershy")) == "fluttershy",
		"a copyable shape resolves")
	main.game = null
	root.remove_child(game)
	game.free()

	# The player flag travels on the change just started.
	pack.actor = own
	pack.disguised_as = "fluttershy"
	check(not bool(adapter.call("requested_by_player")), "a request starts as hers")
	check(bool(adapter.call("request_true_form")), "the true-form request starts")
	adapter.call("set_player_request", true)
	check(bool(adapter.call("requested_by_player")), "the player flag marks the change")
	pack.busy = false
	adapter.call("poll")
	check(not bool(adapter.call("is_changing")), "the marked change completes")

	# Her own AI starts a change: a busy edge with the act body as actor is observed without a
	# request call. The new disguise is claimed by identity before its shape is known.
	pack.actor = own
	pack.disguised_as = "fluttershy"
	pack.busy = false
	adapter.call("handles_pony", own)
	adapter.call("poll")
	pack.busy = true
	adapter.call("poll")
	check(bool(adapter.call("is_changing")), "an AI-started change is observed")
	check(adapter.call("old_actor") == own, "the AI change holds the old body")
	check(not bool(adapter.call("requested_by_player")), "the AI change is not the player's")
	var ai_shape := FakePony.new()
	ai_shape.identity = _identity("chrysalis", "")
	ai_shape.set_meta("geometry_variant", "changeling=rarity")
	root.add_child(ai_shape)
	check(bool(adapter.call("claims_body", ai_shape)),
		"the AI body is claimed by identity before the shape is known")
	pack.actor = ai_shape
	adapter.call("poll")
	check(str(adapter.call("target")) == "rarity", "the AI target fills from the new body")
	pack.busy = false
	adapter.call("poll")
	check(not bool(adapter.call("is_changing")), "the AI change completes")

	# A busy on a body that is not the act pony never reaches the act.
	adapter.call("handles_pony", own)
	pack.actor = other
	pack.busy = false
	adapter.call("poll")
	pack.busy = true
	adapter.call("poll")
	check(not bool(adapter.call("is_changing")),
		"a busy on another body is not the act's change")
	pack.busy = false
	adapter.call("poll")

	# An AI reveal keeps the empty target: the new body is her own form, not a disguise.
	adapter.call("handles_pony", ai_shape)
	pack.actor = ai_shape
	pack.busy = false
	adapter.call("poll")
	pack.busy = true
	adapter.call("poll")
	check(bool(adapter.call("is_changing")), "an AI reveal is observed")
	var ai_own := _own_body()
	root.add_child(ai_own)
	pack.actor = ai_own
	adapter.call("poll")
	check(str(adapter.call("target")).is_empty(), "an AI reveal keeps no shape target")
	check(bool(adapter.call("claims_body", ai_own)), "the AI true-form body is claimed")
	pack.busy = false
	adapter.call("poll")
	check(not bool(adapter.call("is_changing")), "the AI reveal completes")

	# The idle helper only asks the pack to bring her out; it is not a shape change.
	pack.actor = null
	pack.busy = false
	check(bool(adapter.call("request_appear")), "the idle action asks her out")
	check(pack.brought == 1 and not bool(adapter.call("is_changing")),
		"bringing her out is not a change")

	# The pack off unregisters the provider and empties the installed list.
	gate.on = false
	adapter.call("refresh")
	check(not REGISTRY.has("chrysalis"), "the layer is gone when the pack is off")
	check((adapter.call("installed_character_ids") as Array).is_empty(),
		"no ghost entry without the pack")
	check(SETTINGS.character_name("chrysalis") != "Queen Chrysalis",
		"the provider name is gone with the layer")

	# On again: idempotent registration and listing.
	gate.on = true
	adapter.call("refresh")
	adapter.call("refresh")
	check(REGISTRY.has("chrysalis"), "the layer returns with the pack")
	var again: Array = adapter.call("installed_character_ids")
	check(again.size() == 1 and str(again[0]) == "chrysalis",
		"the installed entry returns once")

	adapter.call("shutdown")
	root.remove_child(adapter)
	adapter.free()
	for node: Node in [own, disguise, other, true_new, shape_new, wrong_shape, ai_shape, ai_own, pack]:
		root.remove_child(node)
		node.free()
	api.call("_shutdown")
	root.remove_child(api)
	api.free()
	root.remove_child(main)
	main.free()
	REGISTRY.reset()
	print("CHANGELINGS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
