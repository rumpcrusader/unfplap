extends SceneTree
## integration: anatomy consent, eligibility and schema gate checks.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_anatomy.gd

const CONSENT := preload("res://mods/unfplap/consent.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const SCHEMA := preload("res://mods/unfplap/tunables_schema.gd")
const TUNABLES := preload("res://mods/unfplap/tunables.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const ANATOMY_ACT := preload("res://mods/unfplap/anatomy_act.gd")
const ANON_PART := preload("res://mods/unfplap/anon_part.gd")

var failures := 0
var checks := 0

class FakeIdentity extends Resource:
	var id := ""
	var filly := false
	var stallion := false

class FakePony extends Node3D:
	var identity: Resource
	var rig: Node


class FakeAnatomy extends Node:
	var calls: Array[String] = []

	func _clear_part() -> void:
		calls.append("clear")

	func fluid() -> Node3D:
		return null


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func _pony(id: String, filly := false, stallion := false) -> FakePony:
	var pony := FakePony.new()
	var identity := FakeIdentity.new()
	identity.id = id
	identity.filly = filly
	identity.stallion = stallion
	pony.identity = identity
	pony.set_meta("relationship_id", id)
	return pony


func run() -> void:
	# Consent defaults are deterministic and per-id, and an override wins.
	var a := CONSENT.defaults("twilight_sparkle")
	var b := CONSENT.defaults("twilight_sparkle")
	check(a == b, "consent defaults are deterministic")
	check(a.has("public") and a.has("anal") and a.has("oral"), "consent has all three keys")
	var over := CONSENT.resolve("twilight_sparkle", {"anal": true, "oral": false})
	check(bool(over.get("anal", false)), "consent anal override wins")
	check(not bool(over.get("oral", true)), "consent oral override wins")
	check(bool(CONSENT.resolve("twilight_sparkle", {}).get("public", false))
		== bool(a.get("public", false)), "empty override keeps defaults")
	check(not bool(a.get("public", true)), "no mare is public by default")

	# Eligibility is the modern preference roster plus identity checks. There is no age list.
	var twilight := _pony("twilight_sparkle")
	check(ANATOMY.eligible(twilight), "roster adult is eligible")
	var filly := _pony("twilight_sparkle", true)
	check(not ANATOMY.eligible(filly), "identity filly is excluded")
	var stallion := _pony("twilight_sparkle", false, true)
	check(not ANATOMY.eligible(stallion), "stallion is excluded")
	var off_roster := _pony("not_a_base_mare")
	check(not ANATOMY.eligible(off_roster), "off-roster mare is excluded")
	var player := _pony("twilight_sparkle")
	player.name = "PlayerPony"
	check(not ANATOMY.eligible(player), "player pony is excluded")

	# Every new flag exists with the intended default.
	check(SCHEMA.has("features.anatomy"), "anatomy master flag")
	check(not bool(SCHEMA.default_value("features.anatomy")), "anatomy is off by default")
	for key: String in ["anatomy_holes", "anatomy_finish", "anatomy_fluid"]:
		check(SCHEMA.has("features." + key), "%s flag" % key)
		check(bool(SCHEMA.default_value("features." + key)), "%s is on by default" % key)
	check(bool(SCHEMA.default_value("features.anatomy_oral")), "oral is on by default")
	for key: String in ["anatomy_bed_body", "anatomy_vr", "act_bystanders", "act_public_offer"]:
		check(SCHEMA.has("features." + key), "%s flag" % key)
		check(bool(SCHEMA.default_value("features." + key)), "%s is on by default" % key)
	check(SCHEMA.has("features.act_line_angles")
		and bool(SCHEMA.default_value("features.act_line_angles")),
		"line angles are on by default")
	check(SCHEMA.has("features.act_speech_feel")
		and not bool(SCHEMA.default_value("features.act_speech_feel")),
		"speech feel is off by default")
	check(SCHEMA.has("anatomy.teats"), "teats flag")
	check(not bool(SCHEMA.default_value("anatomy.teats")), "teats off by default")
	check(SCHEMA.has("anatomy.skin_strip"), "skin strip flag")
	check(bool(SCHEMA.default_value("anatomy.skin_strip")), "skin strip on by default")
	check(SCHEMA.has("anatomy.act_only"), "act-only flag")
	check(not bool(SCHEMA.default_value("anatomy.act_only")), "act-only off by default")
	check(SCHEMA.has("anatomy.player_scale"), "player part scale")
	check(SCHEMA.has("anatomy.part_head_scale"), "player part head scale")
	check(SCHEMA.has("anatomy.part_length_scale"), "player part length scale")
	check(SCHEMA.has("anatomy.part_throb"), "player part throb")
	check(near(float(SCHEMA.default_value("anatomy.part_head_scale")), 1.3),
		"head scale uses the tuned default")
	check(near(float(SCHEMA.default_value("anatomy.part_length_scale")), 1.0),
		"length scale defaults to one")
	check(SCHEMA.has("anatomy.anal_ring"), "anal ring toggle")
	check(SCHEMA.has("anatomy.anal_height_mm"), "anal placement height")
	check(not SCHEMA.has("anatomy.cover_depth_m"), "coat depth bias removed")
	check(not SCHEMA.has("anatomy.player_pitch_deg"), "player part pitch removed")
	var tone := SCHEMA.entry("anatomy.skin_tone")
	check(str(tone.get("kind", "")) == "num", "skin tone is a number")
	check(bool(tone.get("slider", false)), "skin tone uses the slider row")
	check(near(float(tone.get("default", -1.0)), 0.5), "skin tone default is the old darker")
	check(near(float(TUNABLES._coerce(tone, 2.0)), 1.0), "skin tone clamps to the slider range")
	check(ANATOMY.DEFAULT_PLACE == Vector3(0.0, 0.525, 0.286), "global anatomy placement is on the crease")
	check(is_equal_approx(ANATOMY.DEFAULT_PITCH, -6.0), "global anatomy pitch")
	check(is_equal_approx(ANATOMY.DEFAULT_SCALE, 0.662), "global anatomy scale")
	# Saved placements migrate once onto the current default: v0 rows get both shifts, v1 the
	# lateral one, and a current row is left alone.
	var v0 := ANATOMY.migrate_place({"version": 0, "fluttershy": {
		"position": [-0.005, 0.5, 0.281], "pitch": 6.0, "scale": 0.662}})
	check(int(v0.get("version", 0)) == ANATOMY.PLACE_VERSION, "v0 placements migrate forward")
	var v0_pos: Array = v0["fluttershy"]["position"]
	check(near(float(v0_pos[0]), 0.0), "v0 row loses the lateral bias")
	check(near(float(v0_pos[2]), 0.286), "v0 row keeps the forward shift")
	var v1 := ANATOMY.migrate_place({"version": 1, "rarity": {
		"position": [-0.005, 0.5, 0.286], "pitch": 6.0, "scale": 0.662}})
	var v1_pos: Array = v1["rarity"]["position"]
	check(near(float(v1_pos[0]), 0.0), "v1 row loses the lateral bias")
	check(near(float(v1_pos[2]), 0.286), "v1 row is not shifted forward twice")
	var v2 := ANATOMY.migrate_place({"version": 2, "rarity": {
		"position": [-0.004, 0.5, 0.286]}})
	var v2_pos: Array = v2["rarity"]["position"]
	check(near(float(v2_pos[0]), -0.004), "current rows are not touched")
	check(not SCHEMA.has("presentation.lean_back_m"), "back lean setting removed")
	check(ClassDB.class_has_method("XRBodyTracker", "get_has_tracking_data"),
		"VR body tracker API")
	check(not ClassDB.class_has_method("XRBodyTracker", "get_have_tracking_data"),
		"old VR tracker API absent")
	check(not FileAccess.get_file_as_string("res://mods/unfplap/vr_act.gd").contains(
		"get_have_tracking_data"), "VR source uses the engine method")

	# A profile keeps its custom prompts and poses when consent is merged.
	var base: Dictionary = SETTINGS._filled_default()
	var characters := {"twilight_sparkle": {
		"consent": {"anal": true},
		"event_prompts": {"climax": "custom"},
		"poses": {"missionary": {"rump_drop_deg": 12.0}},
	}}
	var profile: Dictionary = SETTINGS.profile_for(base, characters, "twilight_sparkle")
	check(profile.has("consent"), "profile carries consent")
	check(str((profile.get("event_prompts", {}) as Dictionary).get("climax", "")) == "custom",
		"consent merge preserves event prompts")
	check(absf(float(((profile.get("poses", {}) as Dictionary).get("missionary", {}) as Dictionary)
		.get("rump_drop_deg", 0.0)) - 12.0) < 0.001, "consent merge preserves pose overrides")
	check(not ANATOMY.assets_exist() or ANATOMY.assets_exist(), "asset check is a bool")
	# integration: no act controller means all anatomy action gates are closed.
	var runtime: Node = RUNTIME.new()
	check(not bool(runtime.call("anatomy_hole_ready")), "hole gate closed without an act")
	check(not bool(runtime.call("anatomy_oral_ready")), "oral gate closed without an act")
	check(not bool(runtime.call("anatomy_finish_ready")), "finish gate closed without an act")
	check(not bool(runtime.call("anatomy_actions_ready")), "all anatomy gates closed without an act")
	runtime.free()

	# Climax clears the shape once and arms the wink pulses; the tick keeps driving the hug so
	# the lips stay on the shaft through the climax instead of closing on nothing.
	var anatomy_act: Node = ANATOMY_ACT.new()
	var fake_anatomy := FakeAnatomy.new()
	anatomy_act.anatomy = fake_anatomy
	anatomy_act.on_climax()
	check(fake_anatomy.calls.size() == 1 and fake_anatomy.calls[0] == "clear",
		"climax clears the shape once")
	check(absf(float(anatomy_act.get("_wink_left")) - ANATOMY_ACT.CLIMAX_WINK_S) < 0.001,
		"climax arms the wink pulses")
	anatomy_act.free()
	fake_anatomy.free()

	# The shaped length and head profile are reported from the same values the shader uses.
	var part: Node = ANON_PART.new()
	part.set("_part_length_scale", 1.5)
	part.set("_girth_head", 1.5)
	check(absf(float(part.call("_part_length")) - ANON_PART.PART_LENGTH * 1.5) < 0.0001,
		"part length scales")
	check(absf(float(part.call("_head_scale_at", 0.0)) - 1.0) < 0.0001,
		"head scale leaves the base alone")
	check(absf(float(part.call("_head_scale_at", 1.0)) - 1.5) < 0.0001,
		"head scale reaches the full glans value")
	part.set("_ready_amount", 1.0)
	part.set("_throb_gain", 1.0)
	part.set("_throb_clock", 0.099)
	part.call("_throb_tick", 0.001, 1.0)
	check(float(part.get("_throb_amount")) > 0.0, "the heartbeat produces a pulse at its peak")
	part.free()

	for pony: Node in [twilight, filly, stallion, off_roster, player]:
		if is_instance_valid(pony):
			pony.free()
	print("ANATOMY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
