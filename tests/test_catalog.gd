extends SceneTree
## Catalog identity/default tests. Run:
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_catalog.gd

const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")

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
	check(CATALOG.all() == [CATALOG.MISSIONARY, CATALOG.HORSE], "pose ids")
	check(CATALOG.legacy_index(CATALOG.MISSIONARY) == 1, "missionary legacy index")
	check(CATALOG.legacy_index(CATALOG.HORSE) == 2, "horse legacy index")
	check(CATALOG.from_legacy(1) == CATALOG.MISSIONARY, "legacy 1 maps to missionary")
	check(CATALOG.from_legacy(2) == CATALOG.HORSE, "legacy 2 maps to horse")
	check(CATALOG.from_legacy(99) == "", "unknown legacy index")
	var ids := {}
	for id: String in CATALOG.all():
		check(not ids.has(id), "unique pose id " + id)
		ids[id] = true
		var defaults := CATALOG.defaults(id)
		check(not defaults.is_empty(), "defaults exist for " + id)
	check(float(CATALOG.defaults(CATALOG.MISSIONARY).get("rump_drop_deg", -1.0)) == 35.0, "missionary rump pitch default")
	check(float(CATALOG.defaults(CATALOG.HORSE).get("hind_spread", -1.0)) == 0.16, "horse hind spread default")
	var gaps: Variant = CATALOG.defaults(CATALOG.HORSE).get("gaps", {})
	check(gaps is Dictionary and int((gaps as Dictionary).size()) == 4, "horse size gaps")
	print("CATALOG_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("CATALOG_PASS")
	quit(0 if failures == 0 else 1)
