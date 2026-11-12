extends SceneTree
## Pure per-mare participation layer: defaults, the partial merge and the capability check.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_participation.gd

const PARTICIPATION := preload("res://mods/unfplap/participation.gd")

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
	check(PARTICIPATION.KEYS.size() == 3, "three capability keys")
	check(PARTICIPATION.KEYS.has("acts"), "acts is a key")
	check(PARTICIPATION.KEYS.has("anatomy"), "anatomy is a key")
	check(PARTICIPATION.KEYS.has("tail"), "tail is a key")

	var defaults := PARTICIPATION.defaults()
	check(bool(defaults.get("acts", false)), "acts defaults to allowed")
	check(bool(defaults.get("anatomy", false)), "anatomy defaults to allowed")
	check(bool(defaults.get("tail", false)), "tail defaults to allowed")

	var resolved := PARTICIPATION.resolve({"acts": false, "tail": true})
	check(not bool(resolved.get("acts", true)), "a partial acts opt-out applies")
	check(bool(resolved.get("anatomy", false)), "a missing anatomy key keeps the default")
	check(bool(resolved.get("tail", false)), "a tail value is kept")

	check(PARTICIPATION.resolve(null).is_empty() == false, "a null layer resolves to defaults")
	check(PARTICIPATION.resolve("nope").is_empty() == false, "a non-dictionary layer resolves to defaults")

	var cleaned := PARTICIPATION.clean({"acts": false, "unknown": true, "anatomy": "yes"})
	check(cleaned.has("acts"), "a known key is kept")
	check(not cleaned.has("unknown"), "an unknown key is dropped")
	check(not cleaned.has("anatomy"), "a non-boolean value is dropped")

	check(PARTICIPATION.allows({"acts": false}, "acts") == false, "a false capability is not allowed")
	check(PARTICIPATION.allows({"acts": true}, "acts") == true, "a true capability is allowed")
	check(PARTICIPATION.allows({}, "acts") == true, "a missing capability is allowed")

	print("PARTICIPATION_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
