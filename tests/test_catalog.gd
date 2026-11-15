extends SceneTree
## Catalog identity/schema tests. Run:
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_catalog.gd

const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

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
	check(CATALOG.all() == [CATALOG.MISSIONARY, CATALOG.STANDING], "pose ids")
	check(CATALOG.every() == [CATALOG.MISSIONARY, CATALOG.STANDING, CATALOG.STANDING_TEST],
		"every pose includes the internal test pose")
	check(not CATALOG.POSE_KEYS.has(CATALOG.STANDING_TEST),
		"the internal test pose has no settings schema")
	check(CATALOG.defaults(CATALOG.STANDING_TEST).is_empty(),
		"the internal test pose has no defaults")
	var ids := {}
	for id: String in CATALOG.all():
		check(not ids.has(id), "unique pose id " + id)
		ids[id] = true
		var defaults := CATALOG.defaults(id)
		check(not defaults.is_empty(), "defaults exist for " + id)
		var keys: Array = defaults.keys()
		keys.sort()
		var expected: Array = CATALOG.POSE_KEYS[id].duplicate()
		expected.sort()
		check(keys == expected, "the shipped defaults match the pose schema for " + id)
	check(not CATALOG.defaults(CATALOG.MISSIONARY).has("rump_drop_deg"),
		"the retired correction-stack defaults are gone")
	var gaps: Variant = CATALOG.defaults(CATALOG.STANDING).get("gaps", {})
	check(gaps is Dictionary and (gaps as Dictionary).size() == CATALOG.GAP_KEYS.size(),
		"standing size gaps")
	for key: String in CATALOG.GAP_KEYS:
		check(gaps is Dictionary and (gaps as Dictionary).has(key), "standing gap " + key)
	check(CATALOG.defaults("no_such_pose").is_empty(), "an unknown pose has no defaults")
	print("CATALOG_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("CATALOG_PASS")
	quit(0 if failures == 0 else 1)
