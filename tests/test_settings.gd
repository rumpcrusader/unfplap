extends SceneTree
## Settings merge/default tests without touching user://.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_settings.gd

const SETTINGS := preload("res://mods/unfplap/settings.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const SCHEMA := preload("res://mods/unfplap/tunables_schema.gd")
const TUNABLES := preload("res://mods/unfplap/tunables.gd")
const TUNABLES_UI := preload("res://mods/unfplap/tunables_ui.gd")

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
	check(SETTINGS.CHARACTER_ORDER.size() == 102, "every spawnable adult mare is editable")
	check(SETTINGS.CHARACTER_ORDER.size() == SETTINGS.CHARACTER_NAMES.size(), "every pony has a display name")
	check(SETTINGS.CHARACTER_ORDER.size() == SETTINGS.CHARACTER_TEMPLATES.size(),
		"every editable pony has a preference template")
	check(SETTINGS.character_name("pinkie_pie") == "Pinkie Pie", "display name lookup")
	var catalog_ok := true
	var preferences_ok := true
	for id: String in SETTINGS.CHARACTER_ORDER:
		if not SETTINGS.CHARACTER_TEMPLATES.has(id):
			catalog_ok = false
		var built_preferences: Dictionary = SETTINGS.profile_for(base, SETTINGS.CHARACTER_TEMPLATES, id).get("preferences", {})
		if built_preferences.has("pose"):
			preferences_ok = false
	check(catalog_ok, "every pony has a preference template")
	check(preferences_ok, "generated preferences are valid and pose-free")
	var maud := SETTINGS.profile_for(base, SETTINGS.CHARACTER_TEMPLATES, "maud_pie")
	check(((maud["preferences"] as Dictionary).get("talk", []) as Array).is_empty(), "Maud is quiet")

	check(int(base.get("aftercare_min", 0)) == 10, "default aftercare_min is 10")
	check(near(float(base.get("cue_gap", 0.0)), 12.0), "default cue_gap is 12")
	check(near(SETTINGS.cue_gap_value(99.0), 30.0), "cue_gap clamps high")
	check(near(SETTINGS.cue_gap_value(1.0), 8.0), "cue_gap clamps low")
	var cue_override := SETTINGS.profile_for(base, {"fluttershy": {"cue_gap": 15.0}}, "fluttershy")
	check(near(float(cue_override.get("cue_gap", 0.0)), 15.0), "character cue_gap override wins")
	var poses: Dictionary = base.get("poses", {})
	check(poses.has(CATALOG.MISSIONARY) and poses.has(CATALOG.STANDING), "pose defaults present")
	var preference: Dictionary = base.get("preferences", {})
	check(str(preference.get("intensity", "")) == "firm", "neutral intensity default")
	check(str(preference.get("pattern", "")) == "steady", "neutral pattern default")
	check(str(preference.get("tolerance", "")) == "normal", "normal tolerance default")
	check((preference.get("touch", []) as Array).is_empty(), "neutral touch default")
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
			"preferences": {"intensity": "rough", "touch": ["smack"]},
		},
	}
	var profile := SETTINGS.profile_for(base, characters, "fluttershy")
	check(float((profile["poses"] as Dictionary)[CATALOG.MISSIONARY]["hind_spread"]) == 0.5, "character pose override wins")
	check(float((profile["poses"] as Dictionary)[CATALOG.MISSIONARY]["rump_drop_deg"]) == 35.0, "character pose inherits other defaults")
	check(float((profile["poses"] as Dictionary)[CATALOG.MISSIONARY]["camera_height"]) == 0.45, "missionary camera default")
	check(float((profile["poses"] as Dictionary)[CATALOG.MISSIONARY]["neck_lift_deg"]) == 15.0, "missionary neck lift default")
	check(float((profile["poses"] as Dictionary)[CATALOG.STANDING]["hind_spread"]) == 0.32, "unrelated pose inherits defaults")
	var profile_preferences: Dictionary = profile["preferences"]
	check(str(profile_preferences.get("intensity", "")) == "rough", "character preference override")
	check((profile_preferences.get("touch", []) as Array).has("smack"), "character touch override")
	check(str(profile_preferences.get("pattern", "")) == "steady", "character pattern inherits default")

	var other := SETTINGS.profile_for(base, characters, "rainbow_dash")
	check(float((other["poses"] as Dictionary)[CATALOG.MISSIONARY]["hind_spread"]) == 0.42, "other character keeps pose default")
	check(str((other["preferences"] as Dictionary).get("intensity", "")) == "firm", "other character keeps preference default")

	var with_unknown := SETTINGS.profile_for(base, {"x": {"poses": {"unknown": {"a": 1}}}}, "x")
	check((with_unknown["poses"] as Dictionary).has(CATALOG.MISSIONARY), "unknown pose does not remove known poses")
	check(not (with_unknown["poses"] as Dictionary).has("unknown"), "unknown pose is ignored")

	var built_in := SETTINGS.profile_for(base, SETTINGS.CHARACTER_TEMPLATES, "fluttershy")
	var fluttershy_preferences: Dictionary = built_in["preferences"]
	check(str(fluttershy_preferences.get("intensity", "")) == "firm", "Fluttershy intensity")
	check(str(fluttershy_preferences.get("pattern", "")) == "steady", "Fluttershy pattern")
	check(str(fluttershy_preferences.get("tolerance", "")) == "forgiving", "Fluttershy is forgiving")
	check((fluttershy_preferences.get("talk", []) as Array).has("reassurance"), "Fluttershy talk")
	var rarity := SETTINGS.profile_for(base, SETTINGS.CHARACTER_TEMPLATES, "rarity")
	var rarity_preferences: Dictionary = rarity["preferences"]
	check(str(rarity_preferences.get("intensity", "")) == "soft", "Rarity intensity")
	check(str(rarity_preferences.get("tolerance", "")) == "strict", "Rarity is strict")
	check((rarity_preferences.get("talk", []) as Array).has("praise"), "Rarity talk")
	var twilight := SETTINGS.profile_for(base, SETTINGS.CHARACTER_TEMPLATES, "twilight_sparkle")

	var defaults := SETTINGS._defaults()
	var feature_block: Dictionary = defaults.get("features", {})
	check(bool(feature_block.get("hud_readouts", false)), "HUD readouts feature on")
	check(bool(feature_block.get("act_lines", false)), "act lines feature on")
	check(bool(feature_block.get("act_history", false)), "long-term act history on by default")
	check(not bool(feature_block.get("idle_camera_sway", true)), "idle camera sway off by default")
	check(bool(feature_block.get("captions_on_top", false)), "captions on top feature on")
	check(bool(feature_block.get("standing_body_sway", false)), "standing body sway feature on")
	check(bool(feature_block.get("missionary_body_motion", false)), "missionary body motion feature on")
	check(bool(feature_block.get("thrust_ear_twitch", false)), "thrust ear twitch feature on")
	check(bool(feature_block.get("standing_plant_feet", false)),
		"standing feet plant on by default")
	check(not bool(feature_block.get("standing_play_bow", true)),
		"play-bow standing stance off by default")
	check(bool(feature_block.get("allow_act_during_cuddle", false)), "cuddle override feature on")
	check(bool(feature_block.get("mute_ponese_audio", false)), "mute Ponese audio on by default")
	check(bool(feature_block.get("act_foley", false)), "act foley on by default")
	check(not bool(feature_block.get("act_vocals", true)), "act vocals off by default")
	check(not bool(feature_block.get("act_climax", true)), "wet climax off by default")
	check(not bool(feature_block.get("act_ear_pin", true)), "pinned act ears off by default")
	check(near(TUNABLES.get_float("thrust.max_pony_climaxes"), 3.0),
		"climax limit defaults to three")
	check(near(TUNABLES.get_float("cues.override_seconds"), 10.0),
		"cue override defaults to ten seconds")
	check(not TUNABLES.get_bool("debug_perf"), "perf logging off by default")
	check(not TUNABLES.get_bool("features.unknown_feature"), "unknown feature off")
	for key: String in SETTINGS.feature_keys():
		var info: Dictionary = SETTINGS.feature_info(key)
		check(not str(info.get("label", "")).is_empty(), "feature label for " + key)
		check(not str(info.get("help", "")).is_empty(), "feature help for " + key)
	check(SETTINGS.feature_keys().size() == SETTINGS.feature_defaults().size(),
		"feature info matches the flag set")
	var relationship_defaults: Dictionary = defaults.get("relationship", {})
	check(str(relationship_defaults.get("promiscuity", "")) == "any",
		"default Promiscuity is Any Adult")
	check(str(relationship_defaults.get("sex_start", "")) == "try_luck",
		"default Starting Sex is Try Your Luck")
	var promiscuity := SCHEMA.entry("relationship.promiscuity")
	check((promiscuity.get("options", []) as Array).has("any"),
		"Promiscuity exposes Any Adult")
	check((promiscuity.get("labels", []) as Array).has("Any Adult"),
		"Any Adult label is present")
	var sex_start := SCHEMA.entry("relationship.sex_start")
	check((sex_start.get("options", []) as Array).has("try_luck"),
		"Starting Sex exposes Try Your Luck")
	check((sex_start.get("labels", []) as Array).has("Try Your Luck"),
		"Try Your Luck label is present")
	check((sex_start.get("labels", []) as Array).has("When Available"),
		"When Available label is present")
	check(not bool(defaults.get("debug_logs", true)), "debug logs off by default")
	var thrust_defaults: Dictionary = defaults.get("thrust", {})
	check(str(thrust_defaults.get("orientation", "")) == "up", "default thrust orientation")
	check(near(float(thrust_defaults.get("pixels_per_full", 0.0)), 1000.0), "default thrust pixels")
	check(near(float(thrust_defaults.get("travel", 0.0)), 1.0), "default hip travel")
	var controls := TUNABLES.block("thrust.")
	check(str(controls.get("orientation", "")) == "up", "runtime thrust controls up")
	check(float(controls.get("pixels_per_full", 0.0)) >= 240.0,
		"runtime thrust controls expose the sensitivity")
	check(float(controls.get("travel", -1.0)) >= 0.0, "runtime hip travel is exposed")
	var jiggle_defaults: Dictionary = defaults.get("jiggle", {})
	check(near(float(jiggle_defaults.get("radius", -1.0)), 0.26),
		"default jiggle radius")
	check(near(float(jiggle_defaults.get("intensity", -1.0)), 0.15),
		"default jiggle intensity")
	check(near(float(jiggle_defaults.get("smack_intensity", -1.0)), 0.45),
		"default smack jiggle intensity")
	var jiggle_controls := TUNABLES.block("jiggle.")
	check(near(float(jiggle_controls.get("radius", -1.0)), TUNABLES.get_float("jiggle.radius")),
		"runtime jiggle radius is the stored value")
	check(near(float(jiggle_controls.get("intensity", -1.0)), TUNABLES.get_float("jiggle.intensity")),
		"runtime jiggle intensity is the stored value")
	check(near(float(jiggle_controls.get("smack_intensity", -1.0)),
		TUNABLES.get_float("jiggle.smack_intensity")),
		"runtime smack jiggle intensity is the stored value")
	var camera_defaults: Dictionary = defaults.get("camera_thrust", {})
	check(near(float(camera_defaults.get("surge", -1.0)), 1.0), "default camera surge full")
	check(near(float(camera_defaults.get("bob", -1.0)), 0.35), "default camera bob amount")
	var camera_controls := TUNABLES.block("camera_thrust.")
	check(near(float(camera_controls.get("surge", -1.0)), 1.0), "runtime camera surge is exposed")
	check(near(float(camera_controls.get("bob", -1.0)), 0.35), "runtime camera bob is exposed")
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
	check(near(float(standing_defaults.get("torso_angle_deg", -1.0)), -12.0),
		"default Anon torso lean")
	var kiss_defaults: Dictionary = standing_defaults.get("kiss", {})
	check(near(float(kiss_defaults.get("mouth_drop", -1.0)), 0.0),
		"default kiss mouth drop")
	check(near(float(kiss_defaults.get("mouth_forward", -1.0)), 0.0),
		"default kiss mouth forward")
	check(near(float(kiss_defaults.get("camera_yaw_deg", 0.0)), 12.0),
		"default kiss camera yaw")
	check(near(float(kiss_defaults.get("lean_side", 0.0)), 0.46),
		"default kiss side lean")
	check(near(float(kiss_defaults.get("lean_forward", 0.0)), 0.25),
		"default kiss forward lean")
	check(near(float(kiss_defaults.get("lean_drop", 0.0)), 0.04),
		"default kiss lean drop")
	var caress_defaults: Dictionary = standing_defaults.get("caress", {})
	check(near(float(caress_defaults.get("palm_distance", 0.0)), 0.02),
		"default caress palm distance")
	check(near(float(caress_defaults.get("oval_across_m", 0.0)), 0.01),
		"default caress oval across")
	check(near(float(caress_defaults.get("oval_up_m", 0.0)), 0.02),
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
	check(near(float(smack_defaults.get("hind_m", -1.0)), 0.09),
		"default smack hind offset")
	check(near(float(smack_defaults.get("height_m", 1.0)), 0.05),
		"default smack height offset")
	check(near(float(smack_defaults.get("arc_m", -1.0)), 0.1),
		"default smack arc")
	check(near(float(smack_defaults.get("pitch_deg", -1.0)), 0.0),
		"default smack pitch")
	check(near(float(smack_defaults.get("raise_speed", -1.0)), 1.5),
		"default smack raise speed")
	check(near(float(smack_defaults.get("return_speed", -1.0)), 3.0),
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

	var legacy_profile := {
		"default": {"taste": {"intensity": "rough"}},
		"characters": {"fluttershy": {"taste": {"intensity": "soft"}}},
	}
	var renamed_profile: Dictionary = SETTINGS._normalize_character_preferences(legacy_profile)
	var renamed_profile_default: Dictionary = renamed_profile.get("default", {})
	var renamed_character: Dictionary = (renamed_profile.get("characters", {}) as Dictionary).get("fluttershy", {})
	check(str((renamed_profile_default.get("preferences", {}) as Dictionary).get("intensity", "")) == "rough",
		"migrates the default taste block to preferences")
	check(str((renamed_character.get("preferences", {}) as Dictionary).get("intensity", "")) == "soft",
		"migrates a character taste block to preferences")
	check(not renamed_profile_default.has("taste") and not renamed_character.has("taste"),
		"removes the old taste key")

	var legacy_tolerance := {
		"tolerance": {"timid_warning": 5.0, "neutral_stop": 9.0},
	}
	var renamed_tolerance: Dictionary = SETTINGS._normalize_tolerance(legacy_tolerance)
	var tolerance_block: Dictionary = renamed_tolerance.get("tolerance", {})
	check(near(float(tolerance_block.get("forgiving_warning", 0.0)), 5.0),
		"migrates the forgiving warning path")
	check(near(float(tolerance_block.get("normal_stop", 0.0)), 9.0),
		"migrates the normal stop path")
	check(not tolerance_block.has("timid_warning") and not tolerance_block.has("neutral_stop"),
		"removes the old tolerance paths")

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

	# A per-act presentation snapshot must carry the whole nested schema shape. Values come from
	# the saved file, so only the defaults are asserted by value.
	var standing := TUNABLES.block("presentation.standing.")
	var standing_schema := SCHEMA.default_block("presentation.standing.")
	check(standing.has("glance_back_speed"), "runtime presentation snapshot has the glance speed")
	var caress_controls: Dictionary = standing.get("caress", {})
	var caress_saved: Dictionary = standing_schema.get("caress", {})
	check(caress_controls.has("palm_distance"), "runtime presentation snapshot has the caress")
	check(near(float(caress_saved.get("palm_distance", -1.0)), 0.02),
		"default caress palm distance")
	check((caress_saved.get("ignore", []) as Array).has("tail"),
		"default caress ignore list keeps tail")
	var smack_controls: Dictionary = standing.get("smack", {})
	var smack_saved: Dictionary = standing_schema.get("smack", {})
	check(smack_controls.has("raise_m"), "runtime presentation snapshot has the smack")
	check(near(float(smack_saved.get("raise_m", -1.0)), 0.30), "default smack raise")
	check(near(float(smack_saved.get("height_m", 1.0)), 0.05), "default smack height")
	check(near(float(smack_saved.get("return_speed", 0.0)), 3.0), "default smack return speed")
	var event_prompts: Dictionary = SETTINGS.DEFAULT_TEMPLATE.get("event_prompts", {})
	check(event_prompts.has("climax") and event_prompts.has("end_early"),
		"remaining event prompts exist")
	check(not event_prompts.has("inside") and not event_prompts.has("stay_close"),
		"afterglow scripted prompts removed")

	var live := SETTINGS.template_for("fluttershy")
	check(not live.is_empty(), "live template")
	check(str((live.get("preferences", {}) as Dictionary).get("intensity", "")) == "firm", "live Fluttershy preference")
	check(not SETTINGS.act_prompt("fluttershy", "utterance").is_empty(), "live utterance prompt")
	check(not SETTINGS.act_prompt("fluttershy", "cue").is_empty(), "live cue prompt")
	check(not SETTINGS.preferences("rarity").is_empty(), "live Rarity preference")

	_check_schema(defaults)

	print("SETTINGS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("SETTINGS_PASS")
	quit(0 if failures == 0 else 1)


## The tunable schema is the single source of truth for defaults, labels, groups and storage
## paths. These checks keep it honest as entries are added.
func _check_schema(defaults: Dictionary) -> void:
	var paths: Array = SCHEMA.all().keys()
	check(paths.size() > 50, "schema has every tunable")
	var kinds := ["bool", "num", "choice", "list"]
	var complete := true
	var groups_ok := true
	for path: String in paths:
		var item := SCHEMA.entry(path)
		if not kinds.has(str(item.get("kind", ""))) or not item.has("default"):
			complete = false
		if str(item.get("label", "")).is_empty() or str(item.get("help", "")).is_empty():
			complete = false
		if str(item.get("group", "")).is_empty():
			groups_ok = false
		if str(item.get("tab", "")) not in [SCHEMA.GENERAL_TAB, SCHEMA.ANATOMY_TAB, SCHEMA.DEBUG_TAB]:
			complete = false
	check(complete, "every schema entry has a kind, default, label, help and tab")
	check(groups_ok, "every schema entry names its panel section")
	check(SCHEMA.groups(SCHEMA.DEBUG_TAB).size() > 5, "debug tab is split into sections")
	check(SCHEMA.groups(SCHEMA.GENERAL_TAB).size() >= 2, "general tab is split into sections")
	check(SCHEMA.groups(SCHEMA.ANATOMY_TAB).size() >= 3, "anatomy tab is split into sections")

	# The schema path is the settings.json path, so the defaults must land in the same blocks.
	check(near(float(SCHEMA.default_value("thrust.travel")), 1.0), "schema thrust travel default")
	check(bool(SCHEMA.default_value("features.act_foley")), "schema act foley default")
	var kiss_defaults := SCHEMA.default_block("presentation.standing.kiss.")
	check(near(float(kiss_defaults.get("lean_side", 0.0)), 0.46),
		"schema block keeps the nested kiss shape")
	var saved_features: Dictionary = defaults.get("features", {})
	check(saved_features.size() == SCHEMA.default_block("features.").size(),
		"saved feature block comes from the schema")

	# Debug numbers are stored and returned verbatim; only user-facing contract bounds clamp.
	var radius := SCHEMA.entry("jiggle.radius")
	check(near(float(TUNABLES._coerce(radius, -5.0)), -5.0), "debug numbers are never clamped")
	var sensitivity := SCHEMA.entry("thrust.pixels_per_full")
	check(near(float(TUNABLES._coerce(sensitivity, 5000.0)), 1200.0),
		"player sensitivity keeps its contract bound")
	var orientation := SCHEMA.entry("thrust.orientation")
	check(str(TUNABLES._coerce(orientation, "sideways")) == "up",
		"unknown choices fall back to the default")
	var ignore := SCHEMA.entry("presentation.standing.caress.ignore")
	check((TUNABLES._coerce(ignore, ["tail", "nonsense"]) as Array) == ["tail"],
		"list values keep only known options")

	# Unknown paths must read as off, never on.
	check(not TUNABLES.get_bool("nope"), "unknown tunable reads off")
	check(near(TUNABLES.get_float("nope"), 0.0), "unknown number reads zero")
	_check_api_names()
	_check_write_round_trip()
	var feature_block := TUNABLES.block("features.")
	check(feature_block.size() == SETTINGS.feature_keys().size(),
		"tunable block exposes every feature")
	check(feature_block.has("act_foley"), "tunable block keys drop the prefix")

	_check_panels()


## A script constant resolves a built-in before a same-named static function, so an API name that
## exists on Script/GDScript would silently call the built-in instead of ours.
func _check_api_names() -> void:
	var names := ["get_bool", "get_float", "get_int", "get_string", "get_list", "get_value",
		"set_value", "reset_value", "block", "reload_settings", "hotkey_action", "run_action",
		"data", "reload_file", "write_setting", "preferences", "pose", "template_for", "features",
		"feature", "build", "build_actions", "all", "has", "entry",
		"default_value", "default_block", "groups", "flag", "num", "user_num", "choice", "list",
		"write_path"]
	var clashes: Array = []
	for name: String in names:
		if ClassDB.class_has_method("GDScript", name):
			clashes.append(name)
	check(clashes.is_empty(), "no settings API name shadows a Script built-in: %s" % str(clashes))


## A write must never leave the resolved table half-filled: setting one path before any read has
## to keep every other tunable readable. The original value is restored at the end.
func _check_write_round_trip() -> void:
	var original := TUNABLES.get_float("jiggle.intensity")
	TUNABLES.reload_settings()
	TUNABLES.set_value("jiggle.intensity", 0.42)
	check(near(TUNABLES.get_float("jiggle.intensity"), 0.42), "set_value round-trips")
	check(TUNABLES.get_bool("features.act_foley") == bool(SCHEMA.default_value("features.act_foley")),
		"a cold write keeps other tunables readable")
	check(TUNABLES.get_float("jiggle.radius") == float(SCHEMA.default_value("jiggle.radius")) \
			or TUNABLES.get_float("jiggle.radius") > 0.0,
		"a cold write keeps a number readable")
	# The panel writes through tunables_ui._store, so cover that path too, not just set_value.
	TUNABLES_UI._store("jiggle.intensity", 0.33, null, Callable())
	check(near(TUNABLES.get_float("jiggle.intensity"), 0.33), "the panel write path persists")
	TUNABLES.set_value("jiggle.intensity", original)
	check(near(TUNABLES.get_float("jiggle.intensity"), original), "set_value restores the original")


## Every schema entry must render exactly one row in its tab, and every section must have a
## heading. This is the guard that keeps "add a schema line" sufficient for the panel.
func _check_panels() -> void:
	for tab: String in [SCHEMA.GENERAL_TAB, SCHEMA.ANATOMY_TAB, SCHEMA.DEBUG_TAB]:
		var list := VBoxContainer.new()
		TUNABLES_UI.build(list, tab, 16, null, Callable())
		var labels: Array = []
		_collect_labels(list, labels)
		var missing: Array = []
		for path: String in SCHEMA.all():
			var item := SCHEMA.entry(path)
			if str(item.get("tab", SCHEMA.DEBUG_TAB)) != tab:
				continue
			if not labels.has(str(item.get("label", ""))):
				missing.append(path)
		check(missing.is_empty(), "%s tab draws every entry (%s)" % [tab, str(missing)])
		for group: String in SCHEMA.groups(tab):
			var heading := group.split("›", true, 1)[0].strip_edges()
			check(labels.has(heading), "%s tab heading for %s" % [tab, group])
		list.free()
	var actions := VBoxContainer.new()
	TUNABLES_UI.build_actions(actions, 16, null)
	var buttons := 0
	for name: String in TUNABLES.ACTIONS:
		if bool(TUNABLES.ACTIONS[name].get("panel", true)):
			buttons += 1
	check(actions.get_child_count() == 1, "actions section is one inserted block")
	var action_box := actions.get_child(0) as VBoxContainer
	check(action_box != null and action_box.get_child_count() == buttons + 3,
		"actions section draws one button per panel action plus its heading and status")
	check(TUNABLES.hotkey_action(KEY_F10) == "skeleton_overlay",
		"the skeleton overlay is the only hotkey action")
	check(TUNABLES.hotkey_action(KEY_APOSTROPHE).is_empty(),
		"no offer hotkey is bound")
	actions.free()


func _collect_labels(node: Node, out: Array) -> void:
	var text := ""
	if node is Label:
		text = (node as Label).text
	elif node is Button:
		text = (node as Button).text.strip_edges()
	if not text.is_empty() and not out.has(text):
		out.append(text)
	for child: Node in node.get_children():
		_collect_labels(child, out)
