extends SceneTree
## The changelings adapter: installed listing, provider profile, and the body-fit/tail metadata.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/integrations/test_changelings.gd

const CHANGELINGS := preload("res://mods/unfplap/integrations/changelings.gd")
const API := preload("res://mods/unfplap/api.gd")
const REGISTRY := preload("res://mods/unfplap/registry/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const PROFILES := preload("res://mods/unfplap/shared/character_preferences.gd")
const IDENTITY := preload("res://mods/unfplap/anatomy/identity.gd")

var failures := 0
var checks := 0


class FakeMain extends Node:
	var api: Node


class FakeIdentity extends Resource:
	var id := ""
	var character_id := ""


class FakePony extends Node3D:
	var identity: Variant = null
	var own_meshes: Array = []


class Gate extends RefCounted:
	var on := false

	func active() -> bool:
		return on


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
	var hair := Node3D.new()
	hair.name = "ChrysalisHair"
	pony.add_child(hair)
	var attach := Node3D.new()
	attach.name = "Hair_tail"
	hair.add_child(attach)
	var chain := Node3D.new()
	chain.name = "Chain"
	attach.add_child(chain)
	pony.own_meshes = [MeshInstance3D.new()]
	return pony


func run() -> void:
	REGISTRY.reset()
	var main := FakeMain.new()
	main.name = "FakeMain"
	root.add_child(main)
	var api := API.new()
	api.name = "UnfplapAPI"
	root.add_child(api)
	api.call("_bind", main)
	main.api = api
	var gate := Gate.new()
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
	check(near(float(placed.get("offset_y", 0.0)), 0.51), "provider placement Y")
	check(near(float(placed.get("offset_z", 0.0)), 0.271), "provider placement Z")
	check(near(float(placed.get("scale", 0.0)), 0.462), "provider placement scale")

	# No base-catalog change, and no ghost entry once the pack is off.
	check(PROFILES.ORDER.size() == 103, "the base roster stays 103")
	check(not "chrysalis" in PROFILES.ORDER, "she is not a base-roster pony")
	check(not "chrysalis" in SETTINGS.CHARACTER_ORDER, "she is not in the base order")

	# Her own body uses her fit and names the visible spring-tail root.
	var own := _own_body()
	root.add_child(own)
	adapter.call("prepare_pony", own)
	check(str(own.get_meta("body_fit_id", "")) == "chrysalis", "her own body uses her fit")
	var chain: Node = own.get_node_or_null("ChrysalisHair/Hair_tail/Chain")
	check(own.get_meta("tail_pose_root", null) == chain, "her spring tail root is exposed")
	check(IDENTITY.body_fit_id(own) == "chrysalis", "the body-fit fallback reads the metadata")
	check(near(float(SETTINGS.anatomy_placement("chrysalis", "chrysalis")
		.get("offset_y", 0.0)), 0.51), "her fit resolves the provider placement")

	# A disguise copies the pony's fit and drops the custom tail root.
	var disguise := FakePony.new()
	disguise.identity = _identity("chrysalis", "")
	disguise.set_meta("geometry_variant", "changeling=fluttershy")
	root.add_child(disguise)
	disguise.set_meta("tail_pose_root", chain)
	adapter.call("prepare_pony", disguise)
	check(str(disguise.get_meta("body_fit_id", "")) == "fluttershy",
		"a disguise uses the copied pony's fit")
	check(not disguise.has_meta("tail_pose_root"), "a disguise has no custom tail root")
	check(SETTINGS.anatomy_placement("chrysalis", "fluttershy")
		== SETTINGS.anatomy_placement("fluttershy"), "a disguise does not borrow her placement")

	# An unrelated pony is never touched.
	var other := FakePony.new()
	other.identity = _identity("fluttershy")
	root.add_child(other)
	adapter.call("prepare_pony", other)
	check(not other.has_meta("body_fit_id"), "an unrelated pony keeps the generic fit rule")

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
	for node: Node in [own, disguise, other]:
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
