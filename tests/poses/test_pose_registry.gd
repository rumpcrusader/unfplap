extends SceneTree
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
	_check_edges()
	_check_catalog()
	_check_table()
	print("POSE_REGISTRY_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("POSE_REGISTRY_PASS")
	quit(0 if failures == 0 else 1)


func _check_shipped() -> void:
	var registry: RefCounted = REGISTRY.new()
	var ids: Array = registry.ids()
	check(ids == [CATALOG.MISSIONARY, CATALOG.STANDING, CATALOG.STANDING_TEST,
		CATALOG.STANDING_ORAL, CATALOG.BED_FACESIT],
		"the registry has the two public poses and the three internal poses")
	check(registry.all().size() == 5, "the registry builds all five typed specs")
	var found: Array = registry.validate()
	check(found.is_empty(), "the shipped table and edges validate: %s" % str(found))
	var standing: Variant = registry.spec(CATALOG.STANDING)
	check(standing != null and standing.family == "standing", "the standing spec is typed")
	check(standing != null and standing.id == CATALOG.STANDING, "the standing spec keeps its id")
	var missionary: Variant = registry.spec(CATALOG.MISSIONARY)
	check(missionary != null and missionary.asset == "poses/missionary_pose.json",
		"missionary carries its authored asset")
	var test: Variant = registry.spec(CATALOG.STANDING_TEST)
	check(test != null and test.id == CATALOG.STANDING_TEST, "the test spec keeps its id")
	if test != null:
		check(not test.public_pose, "the test pose is internal")
		check(not test.offerable, "the test pose is not offerable")
		check(test.base == CATALOG.STANDING, "the test pose inherits standing")
		check(test.driver.is_empty(), "the test pose has no driver of its own")
		check(test.asset.is_empty(), "the test pose inherits its asset")
	var oral: Variant = registry.spec(CATALOG.STANDING_ORAL)
	check(oral != null and oral.id == CATALOG.STANDING_ORAL, "the oral spec keeps its id")
	if oral != null:
		check(not oral.public_pose, "the oral pose is internal")
		check(not oral.offerable, "the oral pose is not offerable")
		check(oral.base == CATALOG.STANDING, "the oral pose inherits standing")
		check(oral.driver.is_empty(), "the oral pose has no driver of its own")
		check(oral.asset.is_empty(), "the oral pose inherits its asset")
		check(oral.delta == "poses/standing_oral_recipe.gd",
			"the oral pose carries the procedural delta")
		check(oral.settings_group == "standing", "the oral pose uses the standing settings group")
		check(str(oral.contact.get("kind", "")) == "mouth", "the oral pose contacts the mouth")
		check(str(oral.hands.get("path", "")) == "oral", "the oral pose uses the oral hand path")
		check(str(oral.controls.get("set", "")) == "standing_oral",
			"the oral pose uses its own control set")
		check(not bool(oral.afterglow.get("close_window", true)),
			"the oral afterglow opens no close window")
	var facesit: Variant = registry.spec(CATALOG.BED_FACESIT)
	check(facesit != null and facesit.id == CATALOG.BED_FACESIT, "the face-sit spec keeps its id")
	if facesit != null:
		check(not facesit.public_pose, "the face-sit pose is internal")
		check(not facesit.offerable, "the face-sit pose is not offerable")
		check(facesit.base.is_empty(), "the face-sit owns its geometry")
		check(facesit.asset == "poses/bed_facesit_pose.json",
			"the face-sit carries its authored asset")
		check(facesit.driver == "poses/missionary_recipe.gd",
			"the face-sit reuses the missionary recipe")
		check(facesit.settings_group == "missionary",
			"the face-sit uses the missionary settings group")
		check(str(facesit.contact.get("kind", "")) == "face", "the face-sit contacts the face")
		check(str(facesit.hands.get("path", "")) == "missionary",
			"the face-sit reuses the missionary hand path")
		check(str(facesit.controls.get("set", "")) == "facesit",
			"the face-sit uses its own control set")
		check(facesit.forms == ["human"] and facesit.views == ["desktop"],
			"the face-sit is authored for human desktop")
		check(str(facesit.scene.get("frame", "")) == "bed" \
				and bool(facesit.scene.get("requires_bed", false)),
			"the face-sit requires a bed")
		check(not bool(facesit.afterglow.get("close_window", true)),
			"the face-sit afterglow opens no close window")
		check(str(facesit.presentation.get("hud_label", "")) == "Face-sit",
			"the face-sit HUD label")
	check(registry.spec("not_a_pose") == null, "an unknown id has no spec")
	check(is_same(registry.spec(CATALOG.MISSIONARY), registry.spec(CATALOG.MISSIONARY)),
		"the registry caches one spec per id")
	# Every shipped row declares the closed start contract; missionary and standing are the two
	# public starts, and the internal rows keep the placement of the pose they are reached from.
	for id: String in CATALOG.every():
		var row: Variant = registry.spec(id)
		check(row != null and row.start_mode == "key", "%s starts on the act key" % id)
		check(row != null and row.start_setup in SPECS.START_SETUPS,
			"%s declares a known start setup" % id)
	check(missionary != null and missionary.start_setup == "bed_stand_up",
		"missionary stands the bed act up")
	check(standing != null and standing.start_setup == "standing_place",
		"standing places the standing act")
	check(facesit != null and facesit.start_setup == "bed_stand_up",
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
	var blocks: Array = DEFAULTS.block("default.poses").keys()
	blocks.sort()
	check(blocks == public_ids, "every default.poses block is a public spec")
	var keys: Array = CATALOG.POSE_KEYS.keys()
	keys.sort()
	check(keys == public_ids, "POSE_KEYS stays the public schema")
	check(CATALOG.defaults(CATALOG.STANDING_TEST).is_empty(),
		"the internal test pose has no default.poses block")
	check(CATALOG.defaults(CATALOG.STANDING_ORAL).is_empty(),
		"the internal oral pose has no default.poses block")
	check(CATALOG.defaults(CATALOG.BED_FACESIT).is_empty(),
		"the internal face-sit pose has no default.poses block")
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
