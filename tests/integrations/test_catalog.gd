extends SceneTree
## The supported-mod catalog: metadata, feature declarations and binding specs.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/integrations/test_catalog.gd

const CATALOG := preload("res://mods/unfplap/shared/integrations.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var providers: Array[Dictionary] = CATALOG.all()
	check(not providers.is_empty(), "the catalog lists at least one supported mod")
	var ids: Array = []
	var features: Array = []
	var complete := true
	for provider: Dictionary in providers:
		var id := str(provider.get("mod_id", ""))
		check(not id.is_empty(), "every provider has a mod id")
		check(not ids.has(id), "provider ids are unique: %s" % id)
		ids.append(id)
		for key: String in ["mod_name", "author", "verified_version"]:
			if str(provider.get(key, "")).is_empty():
				complete = false
		if str(provider.get("mod_name", "")).is_empty() \
				or str(provider.get("author", "")).is_empty() \
				or str(provider.get("verified_version", "")).is_empty():
			check(false, "provider %s has name, author and verified version" % id)
		var rows: Variant = provider.get("features", [])
		check(rows is Array and not (rows as Array).is_empty(),
			"provider %s declares a feature flag" % id)
		if rows is Array:
			for raw: Variant in rows as Array:
				var name := str(raw)
				check(not features.has(name), "feature names are unique: %s" % name)
				features.append(name)
				var setting := SETTINGS.by_name(name)
				check(setting != null, "feature %s has a settings declaration" % name)
				if setting != null:
					check(setting.tab == SETTINGS.INTEGRATIONS,
						"feature %s lives in the Integrations tab" % name)
		var bindings: Variant = provider.get("bindings", {})
		check(bindings is Dictionary and not (bindings as Dictionary).is_empty(),
			"provider %s declares bindings" % id)
		if bindings is Dictionary:
			for binding: String in bindings as Dictionary:
				var steps: Variant = (bindings as Dictionary)[binding]
				check(steps is Array and not (steps as Array).is_empty(),
					"binding %s has at least one step" % binding)
				if steps is Array:
					for raw_step: Variant in steps as Array:
						check(raw_step is Dictionary,
							"binding %s steps are dictionaries" % binding)
						if raw_step is Dictionary:
							var step := raw_step as Dictionary
							check(step.has("property") != step.has("child"),
								"binding %s step is one property or one child" % binding)
	check(complete, "every provider has complete display metadata")
	var declared: Array = []
	for setting: SETTINGS.Setting in SETTINGS.tab_settings(SETTINGS.INTEGRATIONS):
		if not features.has(setting.name):
			declared.append(setting.name)
	check(declared.is_empty(),
		"every Integrations declaration belongs to a provider: %s" % str(declared))
	check(ids.has("kissing"), "Kissing is a supported integration")
	var kissing: Dictionary = CATALOG.provider("kissing")
	check(str(kissing.get("mod_name", "")) == "Kissing", "Kissing display name")
	check(str(kissing.get("author", "")) == "modChad", "Kissing author")
	check(str(kissing.get("verified_version", "")) == "1.2.9", "Kissing verified version")
	check((kissing.get("features", []) as Array).has("kissing_reactions"),
		"Kissing owns the reactions feature")
	print("INTEGRATIONS_CATALOG_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
