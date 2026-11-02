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
	check(int(base.get("climax_at", 0)) == 100, "default climax_at is 100")
	check(int(base.get("aftercare_min", 0)) == 10, "default aftercare_min is 10")
	check(int(base.get("min_utterances", -1)) == 2, "default min_utterances")
	check(int(base.get("max_utterances", -1)) == 3, "default max_utterances")
	check(not base.has("chattiness"), "chattiness removed")
	var poses: Dictionary = base.get("poses", {})
	check(poses.has(CATALOG.MISSIONARY) and poses.has(CATALOG.HORSE), "pose defaults present")
	var preferences: Dictionary = base.get("preferences", {})
	check(preferences.has("pump"), "pump preferences present")
	check(str((preferences["pump"] as Dictionary).get("depth", "")) == "steady", "neutral depth default")
	check(bool(((preferences["pump"] as Dictionary)["speed"] as Dictionary).get("enabled", false)), "neutral speed enabled")
	check(near(float(((preferences["pump"] as Dictionary)["speed"] as Dictionary).get("min", 0.0)), 0.001), "neutral min speed")
	var prompts: Dictionary = base.get("act_prompts", {})
	check(not str(prompts.get("utterance", "")).is_empty(), "utterance prompt present")

	var characters := {
		"fluttershy": {
			"climax_at": 80,
			"min_utterances": 1,
			"max_utterances": 3,
			"poses": {CATALOG.MISSIONARY: {"hind_spread": 0.5}},
			"preferences": {"pump": {"depth": "deep"}},
		},
	}
	var profile := SETTINGS.profile_for(base, characters, "fluttershy")
	check(int(profile.get("climax_at", 0)) == 80, "character override wins")
	check(int(profile.get("min_utterances", 0)) == 1 and int(profile.get("max_utterances", 0)) == 3, "character utterance range")
	check(float((profile["poses"] as Dictionary)[CATALOG.MISSIONARY]["hind_spread"]) == 0.5, "character pose override wins")
	check(float((profile["poses"] as Dictionary)[CATALOG.MISSIONARY]["rump_drop_deg"]) == 35.0, "character pose inherits other defaults")
	check(float((profile["poses"] as Dictionary)[CATALOG.MISSIONARY]["camera_height"]) == 0.45, "missionary camera default")
	check(float((profile["poses"] as Dictionary)[CATALOG.HORSE]["hind_spread"]) == 0.32, "unrelated pose inherits defaults")
	var pump: Dictionary = (profile["preferences"] as Dictionary)["pump"]
	check(str(pump.get("depth", "")) == "deep", "character depth override")
	check(near(float((pump["speed"] as Dictionary).get("min", 0.0)), 0.001), "character speed inherits default")

	var other := SETTINGS.profile_for(base, characters, "rainbow_dash")
	check(int(other.get("climax_at", 0)) == 100, "other character keeps default")
	check(int(other.get("min_utterances", 0)) == 2, "other character keeps utterance default")
	check(float((other["poses"] as Dictionary)[CATALOG.MISSIONARY]["hind_spread"]) == 0.42, "other character keeps pose default")

	var with_unknown := SETTINGS.profile_for(base, {"x": {"poses": {"unknown": {"a": 1}}}}, "x")
	check((with_unknown["poses"] as Dictionary).has(CATALOG.MISSIONARY), "unknown pose does not remove known poses")
	check(not (with_unknown["poses"] as Dictionary).has("unknown"), "unknown pose is ignored")

	var built_in := SETTINGS.profile_for(base, SETTINGS.CHARACTER_TEMPLATES, "fluttershy")
	var fluttershy_pump: Dictionary = (built_in["preferences"] as Dictionary)["pump"]
	check((fluttershy_pump.get("phases", []) as Array).size() == 1, "Fluttershy phase present")
	var built_pump: Dictionary = (built_in["preferences"] as Dictionary)["pump"]
	check(str(built_pump.get("depth", "")) == "deep", "Fluttershy depth profile")
	check(str((built_pump["shape"] as Dictionary).get("likes", "")) == "ease_out", "Fluttershy shape")
	var rarity := SETTINGS.profile_for(base, SETTINGS.CHARACTER_TEMPLATES, "rarity")
	check(int(rarity.get("min_utterances", 0)) == 2, "Rarity line range")
	var rarity_horse: Dictionary = (rarity["poses"] as Dictionary).get("horse", {})
	check(near(float(rarity_horse.get("hind_spread", 0.0)), 0.32), "Rarity horse hind spread")
	var twilight := SETTINGS.profile_for(base, SETTINGS.CHARACTER_TEMPLATES, "twilight_sparkle")
	check(str(((twilight["preferences"] as Dictionary)["pump"] as Dictionary).get("depth", "")) == "steady", "Twilight neutral")

	var defaults := SETTINGS._defaults()
	check(bool((defaults.get("features", {}) as Dictionary).get("camera_inertia", false)),
		"camera inertia feature on")
	check(bool((defaults.get("features", {}) as Dictionary).get("settings_tab", false)),
		"settings tab feature on")
	check(bool((defaults.get("features", {}) as Dictionary).get("cuddle_override", false)),
		"cuddle override feature on")
	check(not bool((defaults.get("features", {}) as Dictionary).get("lean_return", true)),
		"lean return feature off by default")
	check(int((defaults.get("default", {}) as Dictionary).get("max_utterances", 99)) == 3,
		"act utterances capped at three")
	check(not bool((defaults.get("features", {}) as Dictionary).get("act_text_only_ponese", true)),
		"text-only Ponese off")
	check(not SETTINGS.feature("unknown_feature"), "unknown feature off")
	var pump_defaults: Dictionary = defaults.get("pump", {})
	check(str(pump_defaults.get("orientation", "")) == "up", "default pump orientation")
	check(not bool(pump_defaults.get("bobs", true)), "default pump bobs disabled")
	check(near(float(pump_defaults.get("pixels_per_full", 0.0)), 600.0), "default pump pixels")
	var controls := SETTINGS.pump_controls()
	check(bool(controls.get("up", false)), "runtime pump controls up")
	check(near(float(controls.get("pixels_per_full", 0.0)), 600.0), "runtime pump controls pixels")
	check(not bool(controls.get("bobs", true)), "runtime pump bobs disabled")

	var live := SETTINGS.template_for("fluttershy")
	check(int(live.get("min_utterances", 0)) == 1, "live Fluttershy min lines")
	var live_pump: Dictionary = (live["preferences"] as Dictionary)["pump"]
	check(str(live_pump.get("depth", "")) == "deep", "live Fluttershy depth")
	check(not SETTINGS.act_prompt("fluttershy", "utterance").is_empty(), "live utterance prompt")
	check(SETTINGS.utterance_range("fluttershy") == Vector2i(1, 3), "live utterance range")
	check(not SETTINGS.template_for("rarity").is_empty(), "live Rarity template")
	print("SETTINGS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("SETTINGS_PASS")
	quit(0 if failures == 0 else 1)
