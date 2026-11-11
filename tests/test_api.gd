extends SceneTree
## Cross-mod API: the public surface, the contract, provider registration and resolution.
##
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_api.gd

const API := preload("res://mods/unfplap/api.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const REGISTRY := preload("res://mods/unfplap/mare_registry.gd")
const PLACEMENT := preload("res://mods/unfplap/anatomy_placement.gd")

## The public v1 surface. An addition or rename must update this list and docs/api.md together.
const METHODS := ["contract", "describe_mare", "register_mare", "supports", "unregister_mare"]
const DESCRIPTOR_KEYS := [
	"schema", "id", "source", "name",
	"preferences", "consent", "placement", "poses", "act_prompts", "event_prompts",
	"cue_gap", "aftercare_min", "smack_zone_radius",
]
const DESCRIPTION_KEYS := [
	"schema", "id", "name", "known", "registered", "sources",
	"preferences", "consent", "placement", "poses", "act_prompts", "event_prompts",
	"cue_gap", "aftercare_min", "smack_zone_radius",
]

var failures := 0
var checks := 0
var api: Node
var owner: Node


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	REGISTRY.reset()
	api = API.new()
	api.name = "UnfplapAPI"
	root.add_child(api)
	owner = Node.new()
	owner.name = "TestProvider"
	root.add_child(owner)
	_check_surface()
	_check_contract()
	_check_docs()
	_check_base_description()
	_check_custom_mare()
	_check_base_provider()
	_check_validation()
	_check_deep_copies()
	await _check_owner_cleanup()
	SETTINGS.reset_preferences("fluttershy")
	api.call("_shutdown")
	root.remove_child(api)
	api.free()
	root.remove_child(owner)
	owner.free()
	REGISTRY.reset()
	print("API_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("API_PASS")
	quit(0 if failures == 0 else 1)


func _check_surface() -> void:
	check(api.is_in_group("unfplap_api"), "current API group")
	check(api.is_in_group("unfplap_api_v1"), "pinned major group")
	var script: Script = api.get_script()
	var methods: Array[String] = []
	for row: Dictionary in script.get_script_method_list():
		var name := str(row.get("name", ""))
		if not name.begins_with("_"):
			methods.append(name)
	methods.sort()
	check(methods == METHODS, "public method surface: %s" % str(methods))
	check(script.get_script_signal_list().is_empty(), "v1 declares no signals")
	var descriptor_keys: Array = REGISTRY.TOP_KEYS.duplicate()
	descriptor_keys.sort()
	var expected_keys: Array = DESCRIPTOR_KEYS.duplicate()
	expected_keys.sort()
	check(descriptor_keys == expected_keys, "descriptor key surface")


func _check_contract() -> void:
	var contract: Dictionary = api.contract()
	check(str(contract.get("provider", "")) == "unfplap", "provider id")
	check(int(contract.get("api_major", 0)) == 1, "api major")
	check(int(contract.get("api_minor", -1)) == 0, "api minor")
	check(int((contract.get("schemas", {}) as Dictionary).get("mare", 0)) == 1, "mare schema")
	var capabilities: Dictionary = contract.get("capabilities", {})
	check(int(capabilities.get("registry.mare", 0)) == 1, "registry capability")
	check(int(capabilities.get("mare.read", 0)) == 1, "read capability")
	check((contract.get("deprecations", []) as Array).is_empty(), "no v1 deprecations")
	check(api.supports("registry.mare"), "supports a known capability")
	check(not api.supports("registry.mare", 2), "capability version check")
	check(not api.supports("not.a.capability"), "unknown capability")


func _check_docs() -> void:
	var text := FileAccess.get_file_as_string("res://mods/unfplap/docs/api.md")
	check(not text.is_empty(), "docs/api.md exists")
	for name: String in METHODS:
		check(text.contains(name), "docs mention " + name)
	for name: String in ["registry.mare", "mare.read"]:
		check(text.contains(name), "docs mention capability " + name)
	for key: String in DESCRIPTOR_KEYS:
		check(text.contains(key), "docs mention descriptor " + key)
	for key: String in DESCRIPTION_KEYS:
		check(text.contains(key), "docs mention description " + key)
	check(text.contains("1.0"), "docs carry the current API version")


func _check_base_description() -> void:
	var data: Dictionary = api.describe_mare("fluttershy")
	var description_keys: Array = data.keys()
	description_keys.sort()
	var expected_keys: Array = DESCRIPTION_KEYS.duplicate()
	expected_keys.sort()
	check(description_keys == expected_keys, "description key surface")
	check(int(data.get("schema", 0)) == 1, "description schema")
	check(str(data.get("name", "")) == "Fluttershy", "built-in display name")
	check(bool(data.get("known", false)) and not bool(data.get("registered", true)),
		"a base mare is known and unregistered")
	check((data.get("sources", []) as Array).is_empty(), "no provider sources")
	check(str((data.get("preferences", {}) as Dictionary).get("intensity", "")) == "firm",
		"built-in preference resolves")
	check((data.get("consent", {}) as Dictionary).has("public"), "consent resolves")
	check((data.get("placement", {}) as Dictionary).size() == PLACEMENT.KEYS.size(),
		"placement has every key")
	check(near(float((data.get("placement", {}) as Dictionary).get("tail_tilt_deg", -1.0)), 0.0),
		"placement keeps tail_tilt_deg")
	check((data.get("poses", {}) as Dictionary).has("missionary"), "pose defaults resolve")
	check(not str((data.get("act_prompts", {}) as Dictionary).get("cue", "")).is_empty(),
		"act prompt defaults resolve")
	check(not str((data.get("event_prompts", {}) as Dictionary).get("climax", "")).is_empty(),
		"Fluttershy's event prompt resolves")
	check(near(float(data.get("cue_gap", 0.0)), 12.0), "cue gap resolves")
	check(int(data.get("aftercare_min", 0)) == 10, "aftercare minimum resolves")
	check(near(float(data.get("smack_zone_radius", 0.0)), 0.035), "smack radius resolves")


func _check_custom_mare() -> void:
	var descriptor := {
		"schema": 1,
		"id": "test_mare",
		"source": "test_pack",
		"name": "Test Mare",
		"preferences": {
			"intensity": "soft",
			"pattern": "quick",
			"touch": ["kiss"],
			"dislikes": ["smack"],
			"talk": ["praise"],
			"warmth": "slow",
			"tolerance": "strict",
			"notes": "A test provider mare.",
		},
		"consent": {"public": true, "anal": true, "oral": false},
		"placement": {"tail_tilt_deg": 4.0, "dock_scale": 0.9},
		"poses": {"missionary": {"nuzzle_scale": 0.5}},
		"act_prompts": {"cue": "Custom cue {seed}"},
		"event_prompts": {"climax": "Custom climax"},
		"cue_gap": 15.0,
		"aftercare_min": 12,
		"smack_zone_radius": 0.04,
	}
	var result: Dictionary = api.register_mare(owner, descriptor)
	check(bool(result.get("ok", false)), "custom mare registers")
	check(not bool(result.get("replaced", true)), "first registration is not a replacement")
	check((result.get("warnings", []) as Array).is_empty(), "clean descriptor has no warnings")
	check((result.get("errors", []) as Array).is_empty(), "clean descriptor has no errors")

	var data: Dictionary = api.describe_mare("test_mare")
	check(bool(data.get("known", false)) and bool(data.get("registered", false)),
		"a provider mare is known and registered")
	check(str(data.get("name", "")) == "Test Mare", "provider display name")
	check((data.get("sources", []) as Array) == ["test_pack"], "provider source")
	var preferences: Dictionary = data.get("preferences", {})
	check(str(preferences.get("intensity", "")) == "soft", "provider intensity")
	check(str(preferences.get("pattern", "")) == "quick", "provider pattern")
	check(str(preferences.get("tolerance", "")) == "strict", "provider tolerance")
	check((preferences.get("touch", []) as Array).has("kiss"), "provider touch")
	check(not (preferences.get("touch", []) as Array).has("smack"), "provider touch list is exact")
	var consent: Dictionary = data.get("consent", {})
	check(bool(consent.get("public", false)), "provider public consent")
	check(bool(consent.get("anal", false)), "provider anal consent")
	check(not bool(consent.get("oral", true)), "provider oral consent")
	var placement: Dictionary = data.get("placement", {})
	check(near(float(placement.get("tail_tilt_deg", 0.0)), 4.0), "provider tail tilt")
	check(near(float(placement.get("dock_scale", 1.0)), 0.9), "provider dock scale")
	check(near(float(((data.get("poses", {}) as Dictionary).get("missionary", {})
		as Dictionary).get("nuzzle_scale", 0.0)), 0.5), "provider pose value")
	check(str((data.get("act_prompts", {}) as Dictionary).get("cue", "")) == "Custom cue {seed}",
		"provider act prompt")
	check(str((data.get("event_prompts", {}) as Dictionary).get("climax", "")) == "Custom climax",
		"provider event prompt")
	check(near(float(data.get("cue_gap", 0.0)), 15.0), "provider cue gap")
	check(int(data.get("aftercare_min", 0)) == 12, "provider aftercare")
	check(near(float(data.get("smack_zone_radius", 0.0)), 0.04), "provider smack radius")

	# Re-registering the same owner replaces in place.
	descriptor["preferences"] = {"intensity": "rough"}
	var replaced: Dictionary = api.register_mare(owner, descriptor)
	check(bool(replaced.get("ok", false)) and bool(replaced.get("replaced", false)),
		"same owner re-registers")
	check(str((api.describe_mare("test_mare").get("preferences", {}) as Dictionary)
		.get("intensity", "")) == "rough", "replacement wins")
	check((api.describe_mare("test_mare").get("sources", []) as Array) == ["test_pack"],
		"replacement does not duplicate the source")

	# The player's saved difference still wins over the provider template.
	SETTINGS.save_preferences("test_mare", {"intensity": "firm"})
	var overridden: Dictionary = api.describe_mare("test_mare")
	check(str((overridden.get("preferences", {}) as Dictionary).get("intensity", "")) == "firm",
		"player preference wins over the provider")
	check(str(SETTINGS.default_preferences("test_mare").get("intensity", "")) == "rough",
		"the provider remains the reset default")
	SETTINGS.reset_preferences("test_mare")
	check(str((api.describe_mare("test_mare").get("preferences", {}) as Dictionary)
		.get("intensity", "")) == "rough", "reset returns to the provider template")

	var second: Node = Node.new()
	root.add_child(second)
	api.register_mare(second, {"id": "test_mare", "source": "second_pack",
		"preferences": {"intensity": "firm"}})
	var stacked: Dictionary = api.describe_mare("test_mare")
	check((stacked.get("sources", []) as Array) == ["test_pack", "second_pack"],
		"provider layers stack in registration order")
	check(str((stacked.get("preferences", {}) as Dictionary).get("intensity", "")) == "firm",
		"the later provider wins")
	api.unregister_mare(second, "test_mare")
	second.free()
	check((api.describe_mare("test_mare").get("sources", []) as Array) == ["test_pack"],
		"unregistering a layer reveals the one beneath")
	check(str((api.describe_mare("test_mare").get("preferences", {}) as Dictionary)
		.get("intensity", "")) == "rough", "the earlier provider returns")

	check(bool(api.unregister_mare(owner, "test_mare").get("removed", false)), "unregister removes")
	check(not bool(api.describe_mare("test_mare").get("registered", true)),
		"unregistered mare is gone")
	check(str((api.describe_mare("test_mare").get("preferences", {}) as Dictionary)
		.get("intensity", "")) == "firm", "unregistered mare falls back to the global default")


func _check_base_provider() -> void:
	# A player difference saved before the provider exists must not pin the provider's other
	# fields; only the edited key is stored.
	SETTINGS.save_preferences("fluttershy", {"intensity": "rough"})
	var result: Dictionary = api.register_mare(owner, {
		"id": "fluttershy",
		"source": "base_pack",
		"preferences": {"intensity": "soft", "notes": "Base pack note."},
		"placement": {"tail_tilt_deg": 3.0},
		"cue_gap": 14.0,
	})
	check(bool(result.get("ok", false)), "a base-roster provider registers")
	var data: Dictionary = api.describe_mare("fluttershy")
	check(str(data.get("name", "")) == "Fluttershy", "a provider cannot rename a base mare")
	check(bool(data.get("registered", false)), "base mare reports the provider")
	check(str((data.get("preferences", {}) as Dictionary).get("intensity", "")) == "rough",
		"an existing player edit still wins over a base provider")
	check(str((data.get("preferences", {}) as Dictionary).get("notes", "")) == "Base pack note.",
		"an unedited field takes the provider value")
	check(near(float((data.get("placement", {}) as Dictionary).get("tail_tilt_deg", 0.0)), 3.0),
		"provider overrides the shipped placement")
	check(near(float(data.get("cue_gap", 0.0)), 14.0), "provider overrides a timing value")

	SETTINGS.reset_preferences("fluttershy")
	check(str((api.describe_mare("fluttershy").get("preferences", {}) as Dictionary)
		.get("intensity", "")) == "soft", "reset returns to the base provider")

	check(bool(api.unregister_mare(owner, "fluttershy").get("removed", false)),
		"base provider unregisters")
	data = api.describe_mare("fluttershy")
	check(not bool(data.get("registered", true)), "base mare is unregistered")
	check(str((data.get("preferences", {}) as Dictionary).get("intensity", "")) == "firm",
		"base provider removal restores the built-in profile")
	check(near(float((data.get("placement", {}) as Dictionary).get("tail_tilt_deg", 0.0)), 0.0),
		"base provider removal restores the shipped placement")


func _check_validation() -> void:
	var bad: Dictionary = api.register_mare(owner, {"id": "bad", "source": "test",
		"preferences": {"intensity": "wrong"}})
	check(not bool(bad.get("ok", true)), "an invalid enum is rejected")
	check(not (bad.get("errors", []) as Array).is_empty(), "an invalid enum reports an error")

	bad = api.register_mare(owner, {"id": "default", "source": "test"})
	check(not bool(bad.get("ok", true)), "a reserved id is rejected")

	bad = api.register_mare(owner, {"id": "bad_owner", "source": "test", "placement": {"scale": 0.0}})
	check(not bool(bad.get("ok", true)), "a non-positive placement scale is rejected")

	bad = api.register_mare(owner, {"id": "missing_source"})
	check(not bool(bad.get("ok", true)), "a missing source is rejected")

	bad = api.register_mare(owner, {"schema": 2, "id": "future_mare", "source": "test"})
	check(not bool(bad.get("ok", true)), "a newer descriptor schema is rejected")

	bad = api.register_mare(owner, {"id": 5, "source": "test"})
	check(not bool(bad.get("ok", true)), "a non-string id is rejected")
	bad = api.register_mare(owner, {"id": "typed_source", "source": 5})
	check(not bool(bad.get("ok", true)), "a non-string source is rejected")

	bad = api.register_mare(null, {"id": "no_owner", "source": "test"})
	check(not bool(bad.get("ok", true)), "a null owner is rejected")

	var warned: Dictionary = api.register_mare(owner, {"id": "warned_mare", "source": "test",
		"unknown_key": true})
	check(bool(warned.get("ok", false)), "an unknown key is a warning, not an error")
	check(not (warned.get("warnings", []) as Array).is_empty(), "the unknown key is reported")
	api.unregister_mare(owner, "warned_mare")


func _check_deep_copies() -> void:
	var before: Dictionary = api.describe_mare("fluttershy")
	before["preferences"]["intensity"] = "rough"
	before["placement"]["tail_tilt_deg"] = 9.0
	var after: Dictionary = api.describe_mare("fluttershy")
	check(str((after.get("preferences", {}) as Dictionary).get("intensity", "")) == "firm",
		"a returned preference dictionary is a copy")
	check(near(float((after.get("placement", {}) as Dictionary).get("tail_tilt_deg", 0.0)), 0.0),
		"a returned placement dictionary is a copy")

	var unknown: Dictionary = api.describe_mare("not_a_mare")
	check(not bool(unknown.get("known", true)) and not bool(unknown.get("registered", true)),
		"an unknown id is not known")
	check((unknown.get("sources", []) as Array).is_empty(), "an unknown id has no sources")
	check((unknown.get("placement", {}) as Dictionary).size() == PLACEMENT.KEYS.size(),
		"an unknown id still gets a complete placement")


func _check_owner_cleanup() -> void:
	var temp: Node = Node.new()
	temp.name = "TempProvider"
	root.add_child(temp)
	var result: Dictionary = api.register_mare(temp, {"id": "temp_mare", "source": "temp"})
	check(bool(result.get("ok", false)), "temporary owner registers")
	check(bool(api.describe_mare("temp_mare").get("registered", false)),
		"temporary mare is registered")
	temp.free()
	await process_frame
	check(not bool(api.describe_mare("temp_mare").get("registered", true)),
		"freeing the owner unregisters her mare")
