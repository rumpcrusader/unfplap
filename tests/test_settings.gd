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


func run() -> void:
	var base: Dictionary = SETTINGS._filled_default()
	check(int(base.get("climax_at", 0)) == 100, "default climax_at is 100")
	check(int(base.get("aftercare_min", 0)) == 10, "default aftercare_min is 10")
	var poses: Dictionary = base.get("poses", {})
	check(poses.has(CATALOG.MISSIONARY) and poses.has(CATALOG.HORSE), "pose defaults present")

	var characters := {
		"fluttershy": {
			"climax_at": 80,
			"poses": {CATALOG.MISSIONARY: {"hind_spread": 0.5}},
		},
	}
	var profile := SETTINGS.profile_for(base, characters, "fluttershy")
	check(int(profile.get("climax_at", 0)) == 80, "character override wins")
	check(float((profile["poses"] as Dictionary)[CATALOG.MISSIONARY]["hind_spread"]) == 0.5, "character pose override wins")
	check(float((profile["poses"] as Dictionary)[CATALOG.MISSIONARY]["rump_drop_deg"]) == 35.0, "character pose inherits other defaults")
	check(float((profile["poses"] as Dictionary)[CATALOG.HORSE]["hind_spread"]) == 0.16, "unrelated pose inherits defaults")

	var other := SETTINGS.profile_for(base, characters, "rainbow_dash")
	check(int(other.get("climax_at", 0)) == 100, "other character keeps default")
	check(float((other["poses"] as Dictionary)[CATALOG.MISSIONARY]["hind_spread"]) == 0.42, "other character keeps pose default")

	var with_unknown := SETTINGS.profile_for(base, {"x": {"poses": {"unknown": {"a": 1}}}}, "x")
	check((with_unknown["poses"] as Dictionary).has(CATALOG.MISSIONARY), "unknown pose does not remove known poses")
	check(not (with_unknown["poses"] as Dictionary).has("unknown"), "unknown pose is ignored")

	check(SETTINGS.chattiness("nobody") >= 0.0 and SETTINGS.chattiness("nobody") <= 1.0, "chattiness clamped")
	print("SETTINGS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("SETTINGS_PASS")
	quit(0 if failures == 0 else 1)
