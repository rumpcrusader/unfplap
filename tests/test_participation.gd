extends "res://mods/unfplap/tests/support/suite.gd"
## Pure per-mare participation layer: defaults, the partial merge and the capability check.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_participation.gd

const PARTICIPATION := preload("res://mods/unfplap/shared/participation.gd")



func run() -> void:
	check(PARTICIPATION.KEYS.size() == 2, "two capability keys")
	check(PARTICIPATION.KEYS.has("acts"), "acts is a key")
	check(PARTICIPATION.KEYS.has("anatomy"), "anatomy is a key")
	check(PARTICIPATION.DEPRECATED_KEYS == ["tail"], "tail is the one deprecated key")
	check(PARTICIPATION.all_keys().size() == 3, "the full key table adds the deprecated key")
	check(not PARTICIPATION.LABELS.has("tail"), "the Characters form has no tail row")

	var defaults := PARTICIPATION.defaults()
	check(bool(defaults.get("acts", false)), "acts defaults to allowed")
	check(bool(defaults.get("anatomy", false)), "anatomy defaults to allowed")
	check(bool(defaults.get("tail", false)), "tail defaults to allowed")

	var resolved := PARTICIPATION.resolve({"acts": false, "tail": false})
	check(not bool(resolved.get("acts", true)), "a partial acts opt-out applies")
	check(bool(resolved.get("anatomy", false)), "a missing anatomy key keeps the default")
	check(not bool(resolved.get("tail", true)), "a deprecated tail value is kept")

	check(PARTICIPATION.resolve(null).is_empty() == false, "a null layer resolves to defaults")
	check(PARTICIPATION.resolve("nope").is_empty() == false, "a non-dictionary layer resolves to defaults")

	var cleaned := PARTICIPATION.clean({"acts": false, "tail": false, "unknown": true,
		"anatomy": "yes"})
	check(cleaned.has("acts"), "a known key is kept")
	check(not bool(cleaned.get("tail", true)), "a deprecated key is still accepted")
	check(not cleaned.has("unknown"), "an unknown key is dropped")
	check(not cleaned.has("anatomy"), "a non-boolean value is dropped")

	check(PARTICIPATION.allows({"acts": false}, "acts") == false, "a false capability is not allowed")
	check(PARTICIPATION.allows({"acts": true}, "acts") == true, "a true capability is allowed")
	check(PARTICIPATION.allows({}, "acts") == true, "a missing capability is allowed")

	finish()
