extends SceneTree
## Settings merge/default tests without touching user://.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_settings.gd

const SETTINGS := preload("res://mods/unfplap/settings.gd")
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


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	var base: Dictionary = SETTINGS._filled_default()
	check(SETTINGS.CHARACTER_ORDER.size() == 16, "sixteen editable ponies")
	check(SETTINGS.CHARACTER_ORDER.size() == SETTINGS.CHARACTER_NAMES.size(), "every pony has a display name")
	check(SETTINGS.character_name("pinkie_pie") == "Pinkie Pie", "display name lookup")
	var catalog_ok := true
	var taste_ok := true
	for id: String in SETTINGS.CHARACTER_ORDER:
		if not SETTINGS.CHARACTER_TEMPLATES.has(id):
			catalog_ok = false
		var built_taste: Dictionary = SETTINGS.profile_for(base, SETTINGS.CHARACTER_TEMPLATES, id).get("taste", {})
		if built_taste.has("pose"):
			taste_ok = false
		var recovery := int((built_taste as Dictionary).get("recovery", -1))
		if recovery < 0 or recovery > 80:
			taste_ok = false
	check(catalog_ok, "every pony has a taste template")
	check(taste_ok, "generated tastes are valid and pose-free")
	var maud := SETTINGS.profile_for(base, SETTINGS.CHARACTER_TEMPLATES, "maud_pie")
	check(int((maud["taste"] as Dictionary).get("recovery", -1)) == 10, "Maud is slow to recover")
	check(((maud["taste"] as Dictionary).get("talk", []) as Array).is_empty(), "Maud is quiet")

	check(int(base.get("aftercare_min", 0)) == 10, "default aftercare_min is 10")
	check(not base.has("climax_at"), "climax_at removed")
	check(not base.has("min_utterances"), "min_utterances removed")
	check(not base.has("max_utterances"), "max_utterances removed")
	var poses: Dictionary = base.get("poses", {})
	check(poses.has(CATALOG.MISSIONARY) and poses.has(CATALOG.HORSE), "pose defaults present")
	var taste: Dictionary = base.get("taste", {})
	check(str(taste.get("intensity", "")) == "firm", "neutral intensity default")
	check(str(taste.get("pattern", "")) == "steady", "neutral pattern default")
	check(int(taste.get("recovery", 0)) == 20, "neutral recovery default")
	check((taste.get("touch", []) as Array).is_empty(), "neutral touch default")
	var prompts: Dictionary = base.get("act_prompts", {})
	check(not str(prompts.get("utterance", "")).is_empty(), "utterance prompt present")
	check(not str(prompts.get("cue", "")).is_empty(), "cue prompt present")
	check(not str(prompts.get("talk_cue", "")).is_empty(), "talk cue prompt present")

	var characters := {
		"fluttershy": {
			"poses": {CATALOG.MISSIONARY: {"hind_spread": 0.5}},
			"taste": {"intensity": "rough", "touch": ["smack"], "recovery": 30},
		},
	}
	var profile := SETTINGS.profile_for(base, characters, "fluttershy")
	check(float((profile["poses"] as Dictionary)[CATALOG.MISSIONARY]["hind_spread"]) == 0.5, "character pose override wins")
	check(float((profile["poses"] as Dictionary)[CATALOG.MISSIONARY]["rump_drop_deg"]) == 35.0, "character pose inherits other defaults")
	check(float((profile["poses"] as Dictionary)[CATALOG.MISSIONARY]["camera_height"]) == 0.45, "missionary camera default")
	check(float((profile["poses"] as Dictionary)[CATALOG.HORSE]["hind_spread"]) == 0.32, "unrelated pose inherits defaults")
	var profile_taste: Dictionary = profile["taste"]
	check(str(profile_taste.get("intensity", "")) == "rough", "character taste override")
	check((profile_taste.get("touch", []) as Array).has("smack"), "character touch override")
	check(str(profile_taste.get("pattern", "")) == "steady", "character pattern inherits default")
	check(int(profile_taste.get("recovery", 0)) == 30, "character recovery override")

	var other := SETTINGS.profile_for(base, characters, "rainbow_dash")
	check(float((other["poses"] as Dictionary)[CATALOG.MISSIONARY]["hind_spread"]) == 0.42, "other character keeps pose default")
	check(str((other["taste"] as Dictionary).get("intensity", "")) == "firm", "other character keeps taste default")

	var with_unknown := SETTINGS.profile_for(base, {"x": {"poses": {"unknown": {"a": 1}}}}, "x")
	check((with_unknown["poses"] as Dictionary).has(CATALOG.MISSIONARY), "unknown pose does not remove known poses")
	check(not (with_unknown["poses"] as Dictionary).has("unknown"), "unknown pose is ignored")

	var old_prompts := base.duplicate(true)
	old_prompts["act_prompts"] = {"utterance": "old {preferences}", "speed_perfect": "old"}
	var cleaned := SETTINGS.profile_for(old_prompts, {}, "x")
	var cleaned_prompts: Dictionary = cleaned.get("act_prompts", {})
	check(not str(cleaned_prompts.get("utterance", "")).contains("{preferences}"),
		"old preferences prompt replaced")
	check(not cleaned_prompts.has("speed_perfect"), "old prompt key dropped")
	check(cleaned_prompts.has("cue") and cleaned_prompts.has("talk_cue"), "new prompt keys present")

	var built_in := SETTINGS.profile_for(base, SETTINGS.CHARACTER_TEMPLATES, "fluttershy")
	var fluttershy_taste: Dictionary = built_in["taste"]
	check(str(fluttershy_taste.get("intensity", "")) == "firm", "Fluttershy intensity")
	check(str(fluttershy_taste.get("pattern", "")) == "steady", "Fluttershy pattern")
	check(int(fluttershy_taste.get("recovery", 0)) == 12, "Fluttershy recovery")
	check((fluttershy_taste.get("talk", []) as Array).has("reassurance"), "Fluttershy talk")
	var rarity := SETTINGS.profile_for(base, SETTINGS.CHARACTER_TEMPLATES, "rarity")
	var rarity_taste: Dictionary = rarity["taste"]
	check(str(rarity_taste.get("intensity", "")) == "soft", "Rarity intensity")
	check((rarity_taste.get("talk", []) as Array).has("praise"), "Rarity talk")
	var twilight := SETTINGS.profile_for(base, SETTINGS.CHARACTER_TEMPLATES, "twilight_sparkle")
	check(int((twilight["taste"] as Dictionary).get("recovery", 0)) == 20, "Twilight recovery")

	var defaults := SETTINGS._defaults()
	var feature_block: Dictionary = defaults.get("features", {})
	check(bool(feature_block.get("hud_readouts", false)), "HUD readouts feature on")
	check(bool(feature_block.get("settings_tab", false)), "settings tab feature on")
	check(bool(feature_block.get("thrust_camera_rock", false)), "thrust camera rock feature on")
	check(not bool(feature_block.get("idle_camera_sway", true)), "idle camera sway off by default")
	check(bool(feature_block.get("captions_on_top", false)), "captions on top feature on")
	check(bool(feature_block.get("pose2_body_sway", false)), "pose 2 body sway feature on")
	check(bool(feature_block.get("pose1_body_motion", false)), "pose 1 body motion feature on")
	check(bool(feature_block.get("thrust_ear_twitch", false)), "thrust ear twitch feature on")
	check(bool(feature_block.get("allow_act_during_cuddle", false)), "cuddle override feature on")
	check(not bool(feature_block.get("mute_ponese_audio", true)), "mute Ponese audio off")
	check(not feature_block.has("mood_cues"), "old mood cues flag removed")
	check(not feature_block.has("readiness_hud"), "old readiness HUD flag removed")
	check(not feature_block.has("afterglow_close"), "afterglow close flag removed")
	check(not feature_block.has("camera_inertia"), "camera inertia flag removed")
	check(not feature_block.has("rump_blush"), "rump blush flag removed")
	check(not SETTINGS.feature("unknown_feature"), "unknown feature off")
	for key: String in SETTINGS.FEATURE_DEFAULTS:
		var info: Dictionary = SETTINGS.FEATURE_INFO.get(key, {})
		check(not str(info.get("label", "")).is_empty(), "feature label for " + key)
		check(not str(info.get("help", "")).is_empty(), "feature help for " + key)
	check(SETTINGS.FEATURE_INFO.size() == SETTINGS.FEATURE_DEFAULTS.size(),
		"feature info matches the flag set")
	var pruned := SETTINGS.prune_features({
		"hud_readouts": false,
		"afterglow_close": true,
		"free_camera": true,
		"lean_return": true,
	})
	check(not bool(pruned.get("hud_readouts", true)), "prune keeps current values")
	check(not pruned.has("afterglow_close"), "prune drops removed flags")
	check(not pruned.has("free_camera"), "prune drops stale free camera")
	check(not pruned.has("lean_return"), "prune drops stale lean return")
	check(pruned.size() == SETTINGS.FEATURE_DEFAULTS.size(), "prune fills the current flag set")
	var thrust_defaults: Dictionary = defaults.get("thrust", {})
	check(str(thrust_defaults.get("orientation", "")) == "up", "default thrust orientation")
	check(not bool(thrust_defaults.get("camera_bob", true)), "default camera bob disabled")
	check(not bool(thrust_defaults.get("camera_motion", true)), "default camera motion disabled")
	check(near(float(thrust_defaults.get("pixels_per_full", 0.0)), 480.0), "default thrust pixels")
	var legacy_thrust := {"thrust": {"bobs": true}}
	SETTINGS._migrate_thrust_block(legacy_thrust)
	var migrated: Dictionary = legacy_thrust["thrust"]
	check(bool(migrated.get("camera_bob", false)), "legacy bob migrates to camera bob")
	check(bool(migrated.get("camera_motion", false)), "legacy bob migrates to camera motion")
	check(not migrated.has("bobs"), "legacy bob key is removed")
	var default_written := {"thrust": {"bobs": true, "camera_bob": false, "camera_motion": false}}
	SETTINGS._migrate_thrust_block(default_written)
	var recovered: Dictionary = default_written["thrust"]
	check(bool(recovered.get("camera_bob", false)), "legacy bob overrides default camera bob")
	check(bool(recovered.get("camera_motion", false)), "legacy bob overrides default camera motion")
	var controls := SETTINGS.thrust_controls()
	check(bool(controls.get("up", false)), "runtime thrust controls up")
	var runtime_pixels := float(controls.get("pixels_per_full", 0.0))
	check(runtime_pixels >= 240.0 and runtime_pixels <= 1200.0,
		"runtime thrust controls pixels in range")
	check(controls.has("camera_bob"), "runtime camera bob read")
	check(controls.has("camera_motion"), "runtime camera motion read")
	check(not controls.has("bobs"), "old combined bob toggle removed")
	var rock_defaults: Dictionary = SETTINGS.CAMERA_ROCK_DEFAULTS
	check(near(float(rock_defaults.get("impulse", 0.0)), 0.50), "camera rock default impulse")
	check(near(float(rock_defaults.get("limit", 0.0)), 0.055), "camera rock default limit")
	check(near(float(rock_defaults.get("pitch_ratio", 0.0)), 1.0), "camera rock default pitch share")
	check(near(float(rock_defaults.get("roll_ratio", 1.0)), 0.0), "camera rock default roll off")
	var rock_controls := SETTINGS.camera_rock_controls()
	var rock_impulse := float(rock_controls.get("impulse", -1.0))
	var rock_roll := float(rock_controls.get("roll_ratio", -1.0))
	check(rock_impulse >= 0.0 and rock_impulse <= 2.0, "runtime camera rock impulse in range")
	check(rock_roll >= 0.0 and rock_roll <= 2.0, "runtime camera rock roll share in range")
	var event_prompts: Dictionary = SETTINGS.DEFAULT_TEMPLATE.get("event_prompts", {})
	check(event_prompts.has("stay_close"), "stay close event prompt exists")

	var live := SETTINGS.template_for("fluttershy")
	check(not live.is_empty(), "live template")
	check(str((live.get("taste", {}) as Dictionary).get("intensity", "")) == "firm", "live Fluttershy taste")
	check(not SETTINGS.act_prompt("fluttershy", "utterance").is_empty(), "live utterance prompt")
	check(not SETTINGS.act_prompt("fluttershy", "cue").is_empty(), "live cue prompt")
	check(not SETTINGS.taste("rarity").is_empty(), "live Rarity taste")

	print("SETTINGS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("SETTINGS_PASS")
	quit(0 if failures == 0 else 1)
