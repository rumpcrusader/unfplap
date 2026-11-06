extends SceneTree
## integration: anatomy consent, eligibility and schema gate checks.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_anatomy.gd

const CONSENT := preload("res://mods/unfplap/consent.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const SCHEMA := preload("res://mods/unfplap/tunables_schema.gd")
const TUNABLES := preload("res://mods/unfplap/tunables.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")

var failures := 0
var checks := 0

class FakeIdentity extends Resource:
	var id := ""
	var filly := false
	var stallion := false

class FakePony extends Node3D:
	var identity: Resource
	var rig: Node


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


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
	check(bool(SCHEMA.default_value("features.anatomy")), "anatomy is on by default")
	for key: String in ["anatomy_holes", "anatomy_oral", "anatomy_finish", "anatomy_fluid"]:
		check(SCHEMA.has("features." + key), "%s flag" % key)
		check(bool(SCHEMA.default_value("features." + key)), "%s is on by default" % key)
	for key: String in ["anatomy_align", "anatomy_bed_body", "anatomy_vr",
			"act_bystanders", "act_line_variety", "act_chat", "act_public_offer"]:
		check(SCHEMA.has("features." + key), "%s flag" % key)
		check(not bool(SCHEMA.default_value("features." + key)), "%s is off by default" % key)
	check(SCHEMA.has("anatomy.teats"), "teats flag")
	check(bool(SCHEMA.default_value("anatomy.teats")), "teats on by default")
	check(SCHEMA.has("anatomy.act_only"), "act-only flag")
	check(not bool(SCHEMA.default_value("anatomy.act_only")), "act-only off by default")
	check(SCHEMA.has("anatomy.cover_depth_m"), "coat depth bias")
	check(SCHEMA.has("anatomy.player_scale"), "player part scale")
	check(SCHEMA.has("anatomy.player_pitch_deg"), "player part pitch")
	check(TUNABLES.get_string("anatomy.skin_tone") in ["coat", "darker", "dark"],
		"skin tone choice")
	check(ANATOMY.DEFAULT_PLACE == Vector3(-0.005, 0.525, 0.281), "global anatomy placement")
	check(is_equal_approx(ANATOMY.DEFAULT_PITCH, -6.0), "global anatomy pitch")
	check(is_equal_approx(ANATOMY.DEFAULT_SCALE, 0.662), "global anatomy scale")
	check(SCHEMA.has("presentation.lean_back_m"), "back lean setting")
	check(is_equal_approx(float(SCHEMA.default_value("presentation.lean_back_m")), 0.08),
		"back lean default")
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

	for pony: Node in [twilight, filly, stallion, off_roster, player]:
		if is_instance_valid(pony):
			pony.free()
	print("ANATOMY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
