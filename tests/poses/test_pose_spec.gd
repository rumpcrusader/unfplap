extends SceneTree
## The typed pose spec: the field wrapper, the shared validator and the pure source.
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
	_check_errors()
	_check_sources()
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
		var spec: Variant = POSE_SPEC.from_dict(id, row)
		check(spec != null, "%s builds a typed spec" % id)
		if spec == null:
			continue
		check(spec.id == id, "%s keeps its id" % id)
		check(not spec.display_name.is_empty(), "%s has a display name" % id)
		check(spec.public_pose == bool(row.get("public", false)),
			"%s reads public into public_pose" % id)
		check(spec.offerable == bool(row.get("offerable", false)), "%s reads offerable" % id)
		check(spec.forms is Array[String], "%s types its forms" % id)
		check(spec.views is Array[String], "%s types its views" % id)
		check(spec.forms == row.get("forms"), "%s keeps its forms" % id)
		check(spec.views == row.get("views"), "%s keeps its views" % id)
		for profile: String in POSE_SPEC.REQUIRED_PROFILES.keys():
			check(is_same(spec.get(profile), row.get(profile)),
				"%s shares the %s profile dictionary" % [id, profile])
		check(is_same(spec.camera, row["camera"]), "%s does not copy its camera profile" % id)


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
	check(not _mutated({"driver": ""}).is_empty(), "an empty driver is rejected")
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


## The table and the wrapper are data: no settings read, no file, no scene.
func _check_sources() -> void:
	for path: String in ["shared/pose_specs.gd", "poses/pose_spec.gd"]:
		var text := FileAccess.get_file_as_string("res://mods/unfplap/" + path)
		check(not text.is_empty(), "%s is readable" % path)
		for token: String in ["SETTINGS.", "FileAccess.", "res://world/", "settings/service.gd",
				"poses/pose_view.gd"]:
			check(not text.contains(token), "%s stays pure: %s" % [path, token])