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
	check(near(float(base.get("cue_gap", 0.0)), 12.0), "default cue_gap is 12")
	check(near(SETTINGS.cue_gap_value(99.0), 30.0), "cue_gap clamps high")
	check(near(SETTINGS.cue_gap_value(1.0), 8.0), "cue_gap clamps low")
	var cue_override := SETTINGS.profile_for(base, {"fluttershy": {"cue_gap": 15.0}}, "fluttershy")
	check(near(float(cue_override.get("cue_gap", 0.0)), 15.0), "character cue_gap override wins")
	var poses: Dictionary = base.get("poses", {})
	check(poses.has(CATALOG.MISSIONARY) and poses.has(CATALOG.STANDING), "pose defaults present")
	var taste: Dictionary = base.get("taste", {})
	check(str(taste.get("intensity", "")) == "firm", "neutral intensity default")
	check(str(taste.get("pattern", "")) == "steady", "neutral pattern default")
	check(int(taste.get("recovery", 0)) == 20, "neutral recovery default")
	check((taste.get("touch", []) as Array).is_empty(), "neutral touch default")
	var prompts: Dictionary = base.get("act_prompts", {})
	check(not str(prompts.get("utterance", "")).is_empty(), "utterance prompt present")
	check(not str(prompts.get("cue", "")).is_empty(), "cue prompt present")
	check(str(prompts.get("cue", "")).contains("{relationship}"), "cue prompt has relationship note")
	check(str(prompts.get("cue", "")).contains("{tone}"), "cue prompt has tone")
	check(str(prompts.get("cue", "")).contains("{memory}"), "cue prompt has memory hint")
	check(not (prompts as Dictionary).has("talk_cue"), "talk cue prompt removed")

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
	check(float((profile["poses"] as Dictionary)[CATALOG.MISSIONARY]["neck_lift_deg"]) == 15.0, "missionary neck lift default")
	check(float((profile["poses"] as Dictionary)[CATALOG.STANDING]["hind_spread"]) == 0.32, "unrelated pose inherits defaults")
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
	check(bool(feature_block.get("idle_camera_sway", false)), "idle camera sway on by default")
	check(bool(feature_block.get("captions_on_top", false)), "captions on top feature on")
	check(bool(feature_block.get("standing_body_sway", false)), "standing body sway feature on")
	check(bool(feature_block.get("missionary_body_motion", false)), "missionary body motion feature on")
	check(bool(feature_block.get("thrust_ear_twitch", false)), "thrust ear twitch feature on")
	check(bool(feature_block.get("thrust_tail_dock_jiggle", false)),
		"tail/dock jiggle on by default")
	check(bool(feature_block.get("standing_plant_feet", false)),
		"standing feet plant on by default")
	check(bool(feature_block.get("dock_tail_follow", false)),
		"dock follows the tail on by default")
	check(bool(feature_block.get("allow_act_during_cuddle", false)), "cuddle override feature on")
	check(not bool(feature_block.get("press_y_starts_sex", true)), "press-Y sex is off by default")
	check(bool(feature_block.get("mute_ponese_audio", false)), "mute Ponese audio on by default")
	check(bool(feature_block.get("act_foley", false)), "act foley on by default")
	check(not bool(feature_block.get("act_vocals", true)), "act vocals off by default")
	check(not bool(feature_block.get("act_climax", true)), "wet climax off by default")
	check(not bool(feature_block.get("bed_creaks", true)), "bed creaks off by default")
	check(not bool(feature_block.get("act_ear_pin", true)), "pinned act ears off by default")
	check(not SETTINGS.feature("unknown_feature"), "unknown feature off")
	for key: String in SETTINGS.FEATURE_DEFAULTS:
		var info: Dictionary = SETTINGS.FEATURE_INFO.get(key, {})
		check(not str(info.get("label", "")).is_empty(), "feature label for " + key)
		check(not str(info.get("help", "")).is_empty(), "feature help for " + key)
	check(SETTINGS.FEATURE_INFO.size() == SETTINGS.FEATURE_DEFAULTS.size(),
		"feature info matches the flag set")
	check(not bool(defaults.get("debug_logs", true)), "debug logs off by default")
	var thrust_defaults: Dictionary = defaults.get("thrust", {})
	check(str(thrust_defaults.get("orientation", "")) == "up", "default thrust orientation")
	check(near(float(thrust_defaults.get("pixels_per_full", 0.0)), 1000.0), "default thrust pixels")
	check(near(float(thrust_defaults.get("travel", 0.0)), 2.0), "default hip travel")
	var controls := SETTINGS.thrust_controls()
	check(bool(controls.get("up", false)), "runtime thrust controls up")
	var runtime_pixels := float(controls.get("pixels_per_full", 0.0))
	check(runtime_pixels >= 240.0 and runtime_pixels <= 1200.0,
		"runtime thrust controls pixels in range")
	var runtime_travel := float(controls.get("travel", -1.0))
	check(runtime_travel >= 0.0 and runtime_travel <= 3.0,
		"runtime hip travel in range")
	var jiggle_defaults: Dictionary = defaults.get("jiggle", {})
	check(near(float(jiggle_defaults.get("radius", -1.0)), 0.26),
		"default jiggle radius")
	check(near(float(jiggle_defaults.get("intensity", -1.0)), 0.25),
		"default jiggle intensity")
	check(near(float(jiggle_defaults.get("smack_intensity", -1.0)), 0.55),
		"default smack jiggle intensity")
	var jiggle_controls := SETTINGS.jiggle_controls()
	check(float(jiggle_controls.get("radius", -1.0)) >= 0.02,
		"runtime jiggle radius in range")
	check(float(jiggle_controls.get("intensity", -1.0)) >= 0.0,
		"runtime jiggle intensity in range")
	check(float(jiggle_controls.get("smack_intensity", -1.0)) >= 0.0,
		"runtime smack jiggle intensity in range")
	var camera_defaults: Dictionary = defaults.get("camera_thrust", {})
	check(near(float(camera_defaults.get("surge", -1.0)), 1.0), "default camera surge full")
	check(near(float(camera_defaults.get("bob", -1.0)), 0.35), "default camera bob amount")
	var camera_controls := SETTINGS.camera_thrust_controls()
	var camera_surge := float(camera_controls.get("surge", -1.0))
	var camera_bob := float(camera_controls.get("bob", -1.0))
	check(camera_surge >= 0.0 and camera_surge <= 1.0, "runtime camera surge in range")
	check(camera_bob >= 0.0 and camera_bob <= 1.0, "runtime camera bob in range")
	var presentation_defaults: Dictionary = defaults.get("presentation", {})
	var missionary_defaults: Dictionary = presentation_defaults.get("missionary", {})
	var standing_defaults: Dictionary = presentation_defaults.get("standing", {})
	check(near(float(missionary_defaults.get("forward", 0.0)), 0.30),
		"default missionary forward")
	check(near(float(missionary_defaults.get("height", 0.0)), 0.25),
		"default missionary height")
	check(near(float(missionary_defaults.get("side", -1.0)), 0.0),
		"default missionary side")
	check(near(float(missionary_defaults.get("pullback", 0.0)), 0.22),
		"default missionary pullback")
	check(near(float(missionary_defaults.get("side_lean", 0.0)), 0.10),
		"default missionary side-lean forward")
	check(near(float(missionary_defaults.get("pitch_deg", 0.0)), -15.0),
		"default missionary pitch")
	check(near(float(missionary_defaults.get("neck1_deg", -1.0)), 0.0),
		"default missionary neck1")
	check(near(float(missionary_defaults.get("neck2_deg", -1.0)), 0.0),
		"default missionary neck2")
	check(near(float(missionary_defaults.get("neck_roll_deg", -1.0)), 0.0),
		"default missionary neck roll")
	check(near(float(missionary_defaults.get("head_pitch_deg", -1.0)), 0.0),
		"default missionary head pitch")
	check(near(float(missionary_defaults.get("head_roll_deg", -1.0)), 13.0),
		"default missionary head roll")
	check(near(float(standing_defaults.get("glance_back_speed", 0.0)), 2.0),
		"default glance-back speed")
	check(near(float(standing_defaults.get("torso_angle_deg", -1.0)), 6.0),
		"default Anon torso lean")
	var kiss_defaults: Dictionary = standing_defaults.get("kiss", {})
	check(near(float(kiss_defaults.get("mouth_drop", -1.0)), 0.0),
		"default kiss mouth drop")
	check(near(float(kiss_defaults.get("mouth_forward", -1.0)), 0.0),
		"default kiss mouth forward")
	check(near(float(kiss_defaults.get("camera_yaw_deg", 0.0)), 7.0),
		"default kiss camera yaw")
	check(near(float(kiss_defaults.get("lean_side", 0.0)), 0.46),
		"default kiss side lean")
	check(near(float(kiss_defaults.get("lean_forward", 0.0)), 0.03),
		"default kiss forward lean")
	check(near(float(kiss_defaults.get("lean_drop", 0.0)), 0.09),
		"default kiss lean drop")
	check(str(kiss_defaults.get("forelegs", "")) == "planted",
		"default kiss forelegs planted")
	check(near(float(standing_defaults.get("idle_sway_side", -1.0)), 0.0),
		"default idle side sway")
	var caress_defaults: Dictionary = standing_defaults.get("caress", {})
	check(near(float(caress_defaults.get("palm_distance", 0.0)), 0.02),
		"default caress palm distance")
	check(near(float(caress_defaults.get("oval_across_m", 0.0)), 0.053625),
		"default caress oval across")
	check(near(float(caress_defaults.get("oval_up_m", 0.0)), 0.028875),
		"default caress oval up")
	var scale_defaults: Dictionary = caress_defaults.get("palm_scale", {})
	check(near(float(scale_defaults.get("canon", 0.0)), 0.75),
		"default Canon palm scale")
	check(near(float(scale_defaults.get("mounting", 0.0)), 0.9),
		"default mounting palm scale")
	check((caress_defaults.get("ignore", []) as Array).has("tail"),
		"default caress ignores tail")
	check((caress_defaults.get("ignore", []) as Array).has("wing"),
		"default caress ignores wing")
	var smack_defaults: Dictionary = standing_defaults.get("smack", {})
	check(near(float(smack_defaults.get("raise_m", -1.0)), 0.30),
		"default smack raise")
	check(near(float(smack_defaults.get("hind_m", -1.0)), 0.10),
		"default smack hind offset")
	check(near(float(smack_defaults.get("height_m", 1.0)), -0.03),
		"default smack height offset")
	check(near(float(smack_defaults.get("arc_m", -1.0)), 0.06),
		"default smack arc")
	check(near(float(smack_defaults.get("pitch_deg", -1.0)), 12.0),
		"default smack pitch")
	check(near(float(smack_defaults.get("raise_speed", -1.0)), 2.0),
		"default smack raise speed")
	check(near(float(smack_defaults.get("return_speed", -1.0)), 6.0),
		"default smack return speed")

	var old_presentation := {
		"presentation": {
			"pose1_forward": 0.31,
			"pose1_height": -0.2,
			"pose1_pitch_deg": 3.0,
			"glance_back_speed": 1.5,
			"torso_angle_deg": 7.0,
			"pose1_camera": 0.09,
		},
	}
	var migrated: Dictionary = SETTINGS._normalize_presentation(old_presentation)
	var migrated_block: Dictionary = migrated.get("presentation", {})
	var migrated_mission: Dictionary = migrated_block.get("missionary", {})
	var migrated_standing: Dictionary = migrated_block.get("standing", {})
	check(near(float(migrated_mission.get("forward", 0.0)), 0.31),
		"migrates old missionary forward")
	check(near(float(migrated_mission.get("pitch_deg", 0.0)), 3.0),
		"migrates old missionary pitch")
	check(near(float(migrated_standing.get("glance_back_speed", 0.0)), 1.5),
		"migrates old glance speed")
	check(near(float(migrated_standing.get("torso_angle_deg", 0.0)), 7.0),
		"migrates old torso lean")
	check(not migrated_block.has("pose1_forward"), "drops old flat presentation keys")
	check(not migrated_block.has("pose1_camera"), "drops obsolete camera key")

	var legacy_features := {
		"features": {
			"pose2_body_sway": false,
			"pose1_body_motion": false,
		},
	}
	var renamed_features: Dictionary = SETTINGS._normalize_feature_names(legacy_features)
	var renamed_feature_block: Dictionary = renamed_features.get("features", {})
	check(renamed_feature_block.has("standing_body_sway")
		and not renamed_feature_block.has("pose2_body_sway"),
		"migrates the legacy standing feature key")
	check(renamed_feature_block.has("missionary_body_motion")
		and not renamed_feature_block.has("pose1_body_motion"),
		"migrates the legacy missionary feature key")
	check(not bool(renamed_feature_block.get("standing_body_sway", true)),
		"keeps the legacy standing feature value")
	var current_features := {
		"features": {
			"standing_body_sway": true,
			"pose2_body_sway": false,
		},
	}
	var current_renamed: Dictionary = SETTINGS._normalize_feature_names(current_features)
	var current_block: Dictionary = current_renamed.get("features", {})
	check(bool(current_block.get("standing_body_sway", false)),
		"current feature value wins over legacy")

	var legacy_pose := {
		"presentation": {
			"missionary": {"forward": 0.31},
			"horse": {"glance_back_speed": 1.5},
		},
		"default": {"poses": {"horse": {"hind_spread": 0.77}}},
		"characters": {
			"fluttershy": {"poses": {"horse": {"bow": 1.9}}},
		},
	}
	var renamed: Dictionary = SETTINGS._normalize_pose_names(legacy_pose)
	var renamed_presentation: Dictionary = renamed.get("presentation", {})
	var renamed_default: Dictionary = renamed.get("default", {})
	var renamed_fluttershy: Dictionary = (renamed.get("characters", {}) as Dictionary).get(
		"fluttershy", {})
	check(renamed_presentation.has("standing") and not renamed_presentation.has("horse"),
		"migrates the legacy presentation pose id")
	check(near(float((renamed_presentation.get("standing", {}) as Dictionary).get(
		"glance_back_speed", 0.0)), 1.5), "keeps legacy presentation values")
	var renamed_default_poses: Dictionary = renamed_default.get("poses", {})
	var renamed_default_standing: Dictionary = renamed_default_poses.get("standing", {})
	check(near(float(renamed_default_standing.get("hind_spread", 0.0)), 0.77),
		"migrates the default pose block")
	var renamed_fluttershy_poses: Dictionary = renamed_fluttershy.get("poses", {})
	var renamed_fluttershy_standing: Dictionary = renamed_fluttershy_poses.get("standing", {})
	check(near(float(renamed_fluttershy_standing.get("bow", 0.0)), 1.9),
		"migrates a character pose block")
	var both_pose := {
		"presentation": {
			"standing": {"glance_back_speed": 2.5},
			"horse": {"glance_back_speed": 1.5},
		},
	}
	var both_renamed: Dictionary = SETTINGS._normalize_pose_names(both_pose)
	var both_standing: Dictionary = (both_renamed.get("presentation", {}) as Dictionary).get(
		"standing", {})
	check(near(float(both_standing.get("glance_back_speed", 0.0)), 2.5),
		"current pose values win over legacy values")

	var standing := SETTINGS.presentation_controls("standing")
	var glance_speed := float(standing.get("glance_back_speed", 0.0))
	check(glance_speed >= 0.25 and glance_speed <= 3.0,
		"runtime glance-back speed in range")
	check(float(standing.get("idle_sway_side", -1.0)) >= 0.0,
		"runtime idle side sway is non-negative")
	var caress_controls: Dictionary = standing.get("caress", {})
	check(float(caress_controls.get("oval_across_m", -1.0)) >= 0.0,
		"runtime caress oval across is non-negative")
	check(float(caress_controls.get("oval_up_m", -1.0)) >= 0.0,
		"runtime caress oval up is non-negative")
	var smack_controls: Dictionary = standing.get("smack", {})
	check(float(smack_controls.get("raise_m", -1.0)) >= 0.0,
		"runtime smack raise is non-negative")
	check(float(smack_controls.get("hind_m", -1.0)) >= 0.0,
		"runtime smack hind offset is non-negative")
	check(smack_controls.has("height_m"), "runtime smack height is present")
	check(float(smack_controls.get("arc_m", -1.0)) >= 0.0,
		"runtime smack arc is non-negative")
	check(smack_controls.has("pitch_deg"), "runtime smack pitch is present")
	check(float(smack_controls.get("raise_speed", 0.0)) >= 0.05,
		"runtime smack raise speed is positive")
	check(float(smack_controls.get("return_speed", 0.0)) >= 0.05,
		"runtime smack return speed is positive")
	var event_prompts: Dictionary = SETTINGS.DEFAULT_TEMPLATE.get("event_prompts", {})
	check(event_prompts.has("climax") and event_prompts.has("end_early"),
		"remaining event prompts exist")
	check(not event_prompts.has("inside") and not event_prompts.has("stay_close"),
		"afterglow scripted prompts removed")

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
