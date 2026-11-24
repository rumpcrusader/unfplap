extends "res://mods/unfplap/tests/support/suite.gd"
## The pose registry: the three shipped specs, the authored edge table, the unchanged public
## catalog and the table rules.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_pose_registry.gd

const REGISTRY := preload("res://mods/unfplap/poses/registry.gd")
const SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const DEFAULTS := preload("res://mods/unfplap/shared/defaults_data.gd")

const FORWARD := "standing__standing_test"
const REVERSE := "standing_test__standing"
const ORAL_FORWARD := "standing__standing_oral"
const ORAL_REVERSE := "standing_oral__standing"
const FACESIT_FORWARD := "missionary__bed_facesit"
const FACESIT_REVERSE := "bed_facesit__missionary"



func run() -> void:
	_check_shipped()
	_check_edges()
	_check_catalog()
	_check_defaults()
	_check_table()
	if failures == 0:
		print("POSE_REGISTRY_PASS")
	finish()


func _check_shipped() -> void:
	var registry: RefCounted = REGISTRY.new()
	var ids: Array = registry.ids()
	check(ids == [CATALOG.MISSIONARY, CATALOG.STANDING, CATALOG.STANDING_TEST,
		CATALOG.STANDING_ORAL, CATALOG.BED_FACESIT],
		"the registry has the two public poses and the three internal poses")
	check(registry.all().size() == 5, "the registry builds all five typed specs")
	var found: Array = registry.validate()
	check(found.is_empty(), "the shipped table and edges validate: %s" % str(found))
	check(registry.spec("not_a_pose") == null, "an unknown id has no spec")
	check(is_same(registry.spec(CATALOG.MISSIONARY), registry.spec(CATALOG.MISSIONARY)),
		"the registry caches one spec per id")
	# Every shipped row declares the closed start contract; missionary and standing are the two
	# public starts, and the internal rows keep the placement of the pose they are reached from.
	for id: String in CATALOG.every():
		var row: Variant = registry.spec(id)
		check(row != null and row.start_setup in SPECS.START_SETUPS,
			"%s declares a known start setup" % id)
	var missionary: Variant = registry.spec(CATALOG.MISSIONARY)
	var facesit: Variant = registry.spec(CATALOG.BED_FACESIT)
	check(facesit != null and missionary != null
		and facesit.start_setup == missionary.start_setup,
		"the bed face-sit keeps the bed placement")


func _check_edges() -> void:
	var registry: RefCounted = REGISTRY.new()
	var edges: Array = registry.edges()
	check(edges.size() == 6, "the registry loads the two debug edges, the oral pair and the face-sit pair")
	var ids: Array = []
	for edge: Variant in edges:
		ids.append(str(edge.id))
	check(ids == [FACESIT_REVERSE, FACESIT_FORWARD, ORAL_FORWARD, FORWARD, ORAL_REVERSE, REVERSE],
		"the edges load in sorted id order")
	for edge_id: String in [FORWARD, REVERSE, ORAL_FORWARD, ORAL_REVERSE,
			FACESIT_FORWARD, FACESIT_REVERSE]:
		var edge: Variant = registry.edge(edge_id)
		check(edge != null, "%s is cached" % edge_id)
		check(is_same(edge, registry.edge(edge_id)), "%s lookup is the same instance" % edge_id)
	check(registry.edge(CATALOG.STANDING) == null, "a pose id is not an edge id")
	check(registry.edge("no_such_edge") == null, "an unknown edge is null")


func _check_catalog() -> void:
	check(CATALOG.all() == [CATALOG.MISSIONARY, CATALOG.STANDING],
		"CATALOG.all() is unchanged")
	check(CATALOG.every() == [CATALOG.MISSIONARY, CATALOG.STANDING, CATALOG.STANDING_TEST,
		CATALOG.STANDING_ORAL, CATALOG.BED_FACESIT],
		"CATALOG.every() carries the three internal poses")
	var public_ids: Array = CATALOG.all().duplicate()
	public_ids.sort()
	var blocks: Array = DEFAULTS.characters_block("default.poses").keys()
	blocks.sort()
	check(blocks == public_ids, "every default.poses block is a public spec")
	var keys: Array = CATALOG.POSE_KEYS.keys()
	keys.sort()
	check(keys == public_ids, "POSE_KEYS stays the public schema")


## The catalog schema: each public row's shipped defaults carry exactly its `POSE_KEYS`, the
## standing gaps cover every `GAP_KEYS` entry, only public rows are offerable and an unknown id
## fails closed.
func _check_defaults() -> void:
	for id: String in CATALOG.all():
		var defaults: Dictionary = CATALOG.defaults(id)
		check(not defaults.is_empty(), "the shipped defaults exist for " + id)
		var keys: Array = defaults.keys()
		keys.sort()
		var expected: Array = CATALOG.POSE_KEYS[id].duplicate()
		expected.sort()
		check(keys == expected, "the shipped defaults match the pose schema for " + id)
	var gaps: Variant = CATALOG.defaults(CATALOG.STANDING).get("gaps", {})
	check(gaps is Dictionary and (gaps as Dictionary).size() == CATALOG.GAP_KEYS.size(),
		"the standing size gaps cover GAP_KEYS")
	var missing: Array = []
	for key: String in CATALOG.GAP_KEYS:
		if not (gaps is Dictionary and (gaps as Dictionary).has(key)):
			missing.append(key)
	check(missing.is_empty(), "the standing size gaps carry every key: %s" % str(missing))
	check(CATALOG.defaults("no_such_pose").is_empty(), "an unknown pose reads no defaults")
	for id: String in CATALOG.all():
		check(SPECS.is_public(id) and SPECS.is_offerable(id),
			"a public pose is offerable: " + id)
	for id: String in [CATALOG.STANDING_TEST, CATALOG.STANDING_ORAL, CATALOG.BED_FACESIT]:
		check(not SPECS.is_public(id) and not SPECS.is_offerable(id),
			"an internal pose is not offerable: " + id)
		check(CATALOG.defaults(id).is_empty() and not CATALOG.POSE_KEYS.has(id),
			"an internal pose has no settings template: " + id)


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
	var inherited := SPECS.spec(CATALOG.STANDING_TEST).duplicate(true)
	var inherited_table := {
		"standing": SPECS.spec(CATALOG.STANDING),
		"standing_test": inherited,
		"missionary": SPECS.spec(CATALOG.MISSIONARY),
	}
	check(REGISTRY.check_table(["standing_test"], inherited_table, [],
		["standing_test"]).is_empty(), "the base table rule accepts an inherited driver")
	inherited["base"] = "missionary"
	check(not REGISTRY.check_table(["standing_test"], inherited_table, [],
		["standing_test"]).is_empty(), "the table rule rejects a cross-family base")
