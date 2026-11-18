extends SceneTree
## The typed pose spec: the shipped rows, the shared validator and the base/driver rule.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_pose_spec.gd

const SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const POSE_SPEC := preload("res://mods/unfplap/poses/pose_spec.gd")

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
	_check_base_driver()
	_check_errors()
	print("POSE_SPEC_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("POSE_SPEC_PASS")
	quit(0 if failures == 0 else 1)


func _copy(id := SPECS.MISSIONARY) -> Dictionary:
	return SPECS.spec(id).duplicate(true)


## One spec row with its top-level keys replaced, checked as `id`.
func _mutated(changes: Dictionary, id := SPECS.STANDING) -> Array[String]:
	var data := _copy(id)
	for key: String in changes.keys():
		data[key] = changes[key]
	return POSE_SPEC.errors(id, data)


## One spec row with one profile key removed.
func _without(profile: String, key: String, id := SPECS.STANDING) -> Array[String]:
	var data := _copy(id)
	(data[profile] as Dictionary).erase(key)
	return POSE_SPEC.errors(id, data)


func _check_shipped() -> void:
	for id: String in SPECS.ids():
		var row: Dictionary = SPECS.spec(id)
		check(not row.is_empty(), "%s has a raw row" % id)
		var found := POSE_SPEC.errors(id, row)
		check(found.is_empty(), "%s validates: %s" % [id, str(found)])
		var table_found := POSE_SPEC.errors(id, row, SPECS.SPECS)
		check(table_found.is_empty(), "%s validates against the table: %s" % [id, str(table_found)])
		var spec: Variant = POSE_SPEC.from_dict(id, row)
		check(spec != null, "%s builds a typed spec" % id)
		if spec == null:
			continue
		check(spec.id == id, "%s keeps its id" % id)
		check(not spec.display_name.is_empty(), "%s has a display name" % id)


## The driver/base rule: a driver may be empty only when an inherited base owns it, and a base must
## be the same family and acyclic.
func _check_base_driver() -> void:
	var no_driver := _copy(SPECS.STANDING)
	no_driver["driver"] = ""
	check(not POSE_SPEC.errors(SPECS.STANDING, no_driver).is_empty(),
		"an empty driver without a base is rejected")
	check(not POSE_SPEC.errors(SPECS.STANDING, no_driver, SPECS.SPECS).is_empty(),
		"the table still rejects an empty driver without a base")
	var inherited := _copy(SPECS.STANDING_TEST)
	check(POSE_SPEC.errors(SPECS.STANDING_TEST, inherited).is_empty(),
		"an inherited base validates without the table")
	check(POSE_SPEC.errors(SPECS.STANDING_TEST, inherited, SPECS.SPECS).is_empty(),
		"an inherited base validates with the table")
	check(POSE_SPEC.from_dict(SPECS.STANDING_TEST, inherited) != null,
		"an inherited base builds a typed spec")
	var with_driver := _copy(SPECS.STANDING_TEST)
	with_driver["driver"] = "poses/standing_recipe.gd"
	check(POSE_SPEC.errors(SPECS.STANDING_TEST, with_driver, SPECS.SPECS).is_empty(),
		"a base plus a driver is valid")
	var with_delta := _copy(SPECS.STANDING_ORAL)
	check(POSE_SPEC.errors(SPECS.STANDING_ORAL, with_delta, SPECS.SPECS).is_empty(),
		"a base plus a procedural delta is valid")
	check(POSE_SPEC.from_dict(SPECS.STANDING_ORAL, with_delta, SPECS.SPECS) != null,
		"a base plus a delta builds a typed spec")
	var self_base := _copy(SPECS.STANDING_TEST)
	self_base["base"] = SPECS.STANDING_TEST
	check(not POSE_SPEC.errors(SPECS.STANDING_TEST, self_base, SPECS.SPECS).is_empty(),
		"a base equal to the id is rejected")
	var missing := _copy(SPECS.STANDING_TEST)
	missing["base"] = "missing_base"
	check(not POSE_SPEC.errors(SPECS.STANDING_TEST, missing, SPECS.SPECS).is_empty(),
		"a missing base is rejected with the table")
	check(POSE_SPEC.errors(SPECS.STANDING_TEST, missing).is_empty(),
		"a missing base needs the table to be seen")
	var cross := _copy(SPECS.STANDING_TEST)
	cross["base"] = SPECS.MISSIONARY
	check(not POSE_SPEC.errors(SPECS.STANDING_TEST, cross, SPECS.SPECS).is_empty(),
		"a cross-family base is rejected")
	var a := _copy(SPECS.STANDING)
	a["id"] = "a"
	a["base"] = "b"
	a["driver"] = ""
	var b := _copy(SPECS.STANDING)
	b["id"] = "b"
	b["base"] = "a"
	b["driver"] = ""
	check(not POSE_SPEC.errors("a", a, {"a": a, "b": b}).is_empty(),
		"a base cycle is rejected")
	var chain_a := _copy(SPECS.STANDING)
	chain_a["id"] = "a"
	chain_a["base"] = "b"
	chain_a["driver"] = ""
	var chain_b := _copy(SPECS.STANDING)
	chain_b["id"] = "b"
	chain_b["base"] = ""
	chain_b["driver"] = "poses/standing_recipe.gd"
	check(POSE_SPEC.errors("a", chain_a, {"a": chain_a, "b": chain_b}).is_empty(),
		"a base chain that ends at a driver is valid")


func _check_errors() -> void:
	check(not _mutated({"family": "seat"}).is_empty(), "an unknown family is rejected")
	check(not _mutated({"frame": "seat"}).is_empty(), "an unknown frame is rejected")
	check(not _mutated({"settings_group": "missionary_alt"}).is_empty(),
		"an unknown settings group is rejected")
	check(not _mutated({"public": false, "offerable": true}).is_empty(),
		"offerable without public is rejected")
	check(not _mutated({"public": "yes"}).is_empty(), "a non-boolean public is rejected")
	check(not _mutated({"offerable": "yes"}).is_empty(), "a non-boolean offerable is rejected")
	check(not _mutated({"forms": ["unicorn"]}).is_empty(), "an unknown form is rejected")
	check(not _mutated({"forms": ["human", 3]}).is_empty(), "a non-string form is rejected")
	check(not _mutated({"views": []}).is_empty(), "an empty view list is rejected")
	check(not _mutated({"views": ["desktop", "desktop"]}).is_empty(),
		"a repeated view is rejected")
	check(not _mutated({"display_name": ""}).is_empty(), "an empty display name is rejected")
	check(not _mutated({"driver": ""}).is_empty(),
		"an empty driver without a base is rejected")
	check(not _mutated({"game_posture": ""}).is_empty(),
		"an empty game posture is rejected")
	check(not _mutated({"drive_policy": ""}).is_empty(), "an empty drive policy is rejected")
	check(not _mutated({"asset": "missions/pose.json"}).is_empty(),
		"an asset outside poses/ is rejected")
	check(not _mutated({"asset": "poses/pose.txt"}).is_empty(),
		"a non-JSON asset is rejected")
	check(_mutated({"asset": ""}).is_empty(), "an empty asset is valid")
	check(not _mutated({"start": {}}).is_empty(), "a missing start block is rejected")
	check(not _mutated({"start": {"mode": "key"}}).is_empty(),
		"a start block without a setup is rejected")
	check(not _mutated({"start": {"mode": "wait", "setup": "standing_place"}}).is_empty(),
		"an unknown start mode is rejected")
	check(not _mutated({"start": {"mode": "key", "setup": "bench_place"}}).is_empty(),
		"an unknown start setup is rejected")
	check(_mutated({"start": {"mode": "auto", "setup": "bed_keep_lying", "why": "test"}}).is_empty(),
		"an extra start key is additive")
	check(not _without("camera", "profile").is_empty(), "a missing profile key is rejected")
	check(not _without("afterglow", "close_window").is_empty(),
		"a missing close window flag is rejected")
	var bad_scene := _copy(SPECS.STANDING)
	(bad_scene["scene"] as Dictionary)["requires_bed"] = "yes"
	check(not POSE_SPEC.errors(SPECS.STANDING, bad_scene).is_empty(),
		"a non-boolean scene flag is rejected")
	bad_scene = _copy(SPECS.STANDING)
	(bad_scene["scene"] as Dictionary)["frame"] = "seat"
	check(not POSE_SPEC.errors(SPECS.STANDING, bad_scene).is_empty(),
		"an unknown scene frame is rejected")
	bad_scene = _copy(SPECS.STANDING)
	(bad_scene["scene"] as Dictionary)["sources"] = [3]
	check(not POSE_SPEC.errors(SPECS.STANDING, bad_scene).is_empty(),
		"a non-string scene source is rejected")
	check(not POSE_SPEC.errors("Standing", SPECS.spec(SPECS.STANDING)).is_empty(),
		"a non-snake id is rejected")
	var wrong_id := _copy(SPECS.STANDING)
	wrong_id["id"] = "missionary"
	check(not POSE_SPEC.errors(SPECS.STANDING, wrong_id).is_empty(),
		"a mismatched id field is rejected")
	check(POSE_SPEC.from_dict("Standing", SPECS.spec(SPECS.STANDING)) == null,
		"from_dict refuses an invalid id")
	var internal := _copy(SPECS.STANDING)
	internal["id"] = "standing_oral"
	internal["display_name"] = "Standing oral"
	internal["public"] = false
	internal["offerable"] = false
	check(POSE_SPEC.errors("standing_oral", internal).is_empty(),
		"an internal spec shape is valid")
	check(POSE_SPEC.from_dict("standing_oral", internal) != null,
		"an internal spec builds")
