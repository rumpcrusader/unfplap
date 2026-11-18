extends SceneTree
## Catalog identity/schema tests. Run:
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_catalog.gd

const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const POSE_SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")

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
	check(CATALOG.every() == [CATALOG.MISSIONARY, CATALOG.STANDING, CATALOG.STANDING_TEST,
		CATALOG.STANDING_ORAL, CATALOG.BED_FACESIT],
		"every pose includes the three internal poses")
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
	var gaps: Variant = CATALOG.defaults(CATALOG.STANDING).get("gaps", {})
	check(gaps is Dictionary and (gaps as Dictionary).size() == CATALOG.GAP_KEYS.size(),
		"standing size gaps")
	for key: String in CATALOG.GAP_KEYS:
		check(gaps is Dictionary and (gaps as Dictionary).has(key), "standing gap " + key)
	check(CATALOG.defaults("no_such_pose").is_empty(), "an unknown pose has no defaults")
	for id: String in CATALOG.all():
		check(POSE_SPECS.is_public(id) and POSE_SPECS.is_offerable(id),
			"the public poses are offerable: " + id)
	for id: String in [CATALOG.STANDING_TEST, CATALOG.STANDING_ORAL, CATALOG.BED_FACESIT]:
		check(not POSE_SPECS.is_public(id) and not POSE_SPECS.is_offerable(id),
			"the internal pose stays internal: " + id)
		check(CATALOG.defaults(id).is_empty() and not CATALOG.POSE_KEYS.has(id),
			"the internal pose has no settings template: " + id)
	var missionary_scene := POSE_SPECS.scene(CATALOG.MISSIONARY)
	check(bool(missionary_scene.get("requires_bed", false))
		and not bool(missionary_scene.get("stool", false)),
		"the bed scene block requires a bed and no stool")
	check((missionary_scene.get("sources", []) as Array).has("cradle"),
		"the bed scene authors the cradle source")
	var standing_scene := POSE_SPECS.scene(CATALOG.STANDING)
	check(not bool(standing_scene.get("requires_bed", true))
		and bool(standing_scene.get("stool", false))
		and bool(standing_scene.get("standing_free", false)),
		"the standing scene block is free-standing with a stool")
	check(POSE_SPECS.supports(CATALOG.MISSIONARY, "human", "desktop"),
		"missionary supports human desktop")
	check(not POSE_SPECS.supports(CATALOG.MISSIONARY, "pony", "desktop"),
		"missionary rejects AnonPony")
	check(not POSE_SPECS.supports(CATALOG.MISSIONARY, "human", "vr"),
		"missionary rejects the headset view")
	var facesit_scene := POSE_SPECS.scene(CATALOG.BED_FACESIT)
	check(bool(facesit_scene.get("requires_bed", false))
		and bool(facesit_scene.get("managed_bed", false))
		and not bool(facesit_scene.get("stool", false))
		and not bool(facesit_scene.get("standing_free", false)),
		"the face-sit is a managed bed scene with no stool")
	check(POSE_SPECS.supports(CATALOG.BED_FACESIT, "human", "desktop"),
		"the face-sit supports human desktop")
	check(not POSE_SPECS.supports(CATALOG.BED_FACESIT, "pony", "desktop")
		and not POSE_SPECS.supports(CATALOG.BED_FACESIT, "human", "vr"),
		"the face-sit rejects AnonPony and the headset view")
	for form: String in ["human", "pony"]:
		for view: String in ["desktop", "vr"]:
			check(POSE_SPECS.supports(CATALOG.STANDING, form, view),
				"standing supports %s %s" % [form, view])
	check(not POSE_SPECS.supports("no_such_pose", "human", "desktop"),
		"an unknown pose supports nothing")
	var missing_scene := POSE_SPECS.scene("no_such_pose")
	check(str(missing_scene.get("frame", "?")) == ""
		and not bool(missing_scene.get("requires_bed", true)),
		"an unknown pose reads the fail-closed scene")
	print("CATALOG_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("CATALOG_PASS")
	quit(0 if failures == 0 else 1)
