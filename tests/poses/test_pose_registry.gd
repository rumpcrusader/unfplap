extends SceneTree
## The pose registry: the two shipped specs, the unchanged public catalog and the table rules.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_pose_registry.gd

const REGISTRY := preload("res://mods/unfplap/poses/registry.gd")
const SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const DEFAULTS := preload("res://mods/unfplap/shared/defaults_data.gd")

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
	_check_shipped()
	_check_catalog()
	_check_table()
	print("POSE_REGISTRY_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("POSE_REGISTRY_PASS")
	quit(0 if failures == 0 else 1)


func _check_shipped() -> void:
	var registry: RefCounted = REGISTRY.new()
	var ids: Array = registry.ids()
	check(ids == [CATALOG.MISSIONARY, CATALOG.STANDING],
		"the registry has the two public poses")
	check(registry.all().size() == 2, "the registry builds both typed specs")
	var found: Array = registry.validate()
	check(found.is_empty(), "the shipped table validates: %s" % str(found))
	var standing: Variant = registry.spec(CATALOG.STANDING)
	check(standing != null and standing.family == "standing", "the standing spec is typed")
	check(standing != null and standing.id == CATALOG.STANDING, "the standing spec keeps its id")
	check(registry.spec("standing_oral") == null, "no internal pose ships yet")
	check(registry.spec("not_a_pose") == null, "an unknown id has no spec")
	check(registry.edges().is_empty(), "the edge table is empty")
	check(registry.edge(CATALOG.MISSIONARY) == null, "an edge stub has no edge")
	check(is_same(registry.spec(CATALOG.MISSIONARY), registry.spec(CATALOG.MISSIONARY)),
		"the registry caches one spec per id")


func _check_catalog() -> void:
	check(CATALOG.all() == [CATALOG.MISSIONARY, CATALOG.STANDING],
		"CATALOG.all() is unchanged")
	check(CATALOG.every() == CATALOG.all(), "CATALOG.every() aliases the public list")
	var public_ids: Array = CATALOG.all().duplicate()
	public_ids.sort()
	var blocks: Array = DEFAULTS.block("default.poses").keys()
	blocks.sort()
	check(blocks == public_ids, "every default.poses block is a public spec")
	var keys: Array = CATALOG.POSE_KEYS.keys()
	keys.sort()
	check(keys == public_ids, "POSE_KEYS stays the public schema")
	for id: String in CATALOG.all():
		check(not CATALOG.defaults(id).is_empty(), "%s has shipped defaults" % id)


func _check_table() -> void:
	var internal := SPECS.spec(CATALOG.STANDING).duplicate(true)
	internal["id"] = "standing_oral"
	internal["display_name"] = "Standing oral"
	internal["public"] = false
	internal["offerable"] = false
	var table := {"standing_oral": internal}
	check(REGISTRY.check_table(["standing_oral"], table, [], ["standing_oral"]).is_empty(),
		"an internal pose validates outside the public catalog")
	check(not REGISTRY.check_table(["standing_oral"], table, ["standing_oral"],
		["standing_oral"]).is_empty(), "an internal pose in CATALOG.all() is rejected")
	check(not REGISTRY.check_table(["standing_oral"], table, [], []).is_empty(),
		"a spec missing from CATALOG.every() is rejected")
	check(not REGISTRY.check_table(["standing_oral", "standing_oral"], table, [],
		["standing_oral"]).is_empty(), "a duplicate id is rejected")
	check(not REGISTRY.check_table([], {}, ["missionary"], ["missionary"]).is_empty(),
		"a catalog id without a spec row is rejected")
	var hidden := SPECS.spec(CATALOG.MISSIONARY).duplicate(true)
	hidden["public"] = false
	hidden["offerable"] = false
	check(not REGISTRY.check_table(["missionary"], {"missionary": hidden}, ["missionary"],
		["missionary"]).is_empty(), "a catalog id with an internal spec is rejected")
	var public_row := SPECS.spec(CATALOG.STANDING).duplicate(true)
	check(not REGISTRY.check_table(["standing"], {"standing": public_row}, [],
		["standing"]).is_empty(), "a public pose outside CATALOG.all() is rejected")
	check(REGISTRY.check_table(["standing"], {"standing": public_row}, ["standing"],
		["standing"]).is_empty(), "a public pose inside CATALOG.all() passes")
	var bad := SPECS.spec(CATALOG.STANDING).duplicate(true)
	bad["frame"] = "seat"
	check(not REGISTRY.check_table(["standing"], {"standing": bad}, ["standing"],
		["standing"]).is_empty(), "the table check runs the spec validator")