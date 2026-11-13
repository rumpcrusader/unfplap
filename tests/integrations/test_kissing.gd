extends SceneTree
## The pure Kissing 1.2.9 policy: availability, the readiness-driven level, the bond cap, the
## activity fade, the climax boost and the optional full fidgets.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/integrations/test_kissing.gd

const KISSING := preload("res://mods/unfplap/integrations/kissing.gd")
const CONTEXT := preload("res://mods/unfplap/integrations/context.gd")
const ACTION := preload("res://mods/unfplap/integrations/action.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _context(feature := true, full := false) -> RefCounted:
	var context := CONTEXT.new()
	context.state = 2
	context.features = {"kissing_reactions": feature, "kissing_full_fidgets": full}
	context.bindings = {
		"feelings": true,
		"excitement": true,
		"beat": true,
		"skeleton": true,
		"fidgets": true,
	}
	context.satisfaction = 0.0
	context.mood = "warming"
	context.seconds_since_stroke = 0.0
	context.reaction_cap = 1.0
	return context


func _find(actions: Array, binding: String, property: String) -> Variant:
	for raw: Variant in actions:
		if str(raw.get("binding")) == binding and str(raw.get("property")) == property:
			return raw
	return null


func _tick(policy: Variant, context: RefCounted, delta: float, count := 1) -> Array:
	var actions: Array = []
	for i in count:
		actions.clear()
		policy.tick_actions(context, delta, actions)
	return actions


func run() -> void:
	var policy := KISSING.new()
	var context := _context()
	check(policy.available(context), "Kissing runs when its required bindings exist")
	check(policy.holds_excitement(), "Kissing requests the shared excitement Beat hold")
	check(not policy.available(_context(false)), "the feature flag gates the provider")
	for missing: String in ["feelings", "excitement", "beat"]:
		var broken := _context()
		broken.bindings[missing] = false
		check(not policy.available(broken), "missing required binding blocks the provider: %s" % missing)
	var optional := _context()
	optional.bindings["fidgets"] = false
	check(policy.available(optional), "the fidget node is optional")

	var start: Array = []
	policy.start_actions(context, start)
	var until: Variant = _find(start, "excitement", "_until")
	var root: Variant = _find(start, "fidgets", "_root")
	var tap: Variant = _find(start, "fidgets", "_tap_next")
	check(until != null and near(float(until.get("value")), 0.0), "start clears the excitement cause")
	check(_find(start, "feelings", "level") == null, "start does not drive the level before close")
	check(root != null and int(root.get("value")) == -1, "fidgets keep no skeleton-root weight shift")
	check(tap != null and near(float(tap.get("value")), 1.0e9), "fidgets keep no hoof taps")
	check(_find(start, "beat", "paused") == null,
		"the provider leaves the Beat ownership to the act hold")
	for raw: Variant in start:
		check(str(raw.get("binding")) != "skeleton", "the skeleton root is never driven")
		check(str(raw.get("binding")) != "hoof_hold", "the hoof hold is never driven")

	# Warming: no reaction yet.
	context.satisfaction = 20.0
	context.mood = "warming"
	context.reaction_cap = 0.85
	var warming := _tick(policy, context, 0.1)
	until = _find(warming, "excitement", "_until")
	var level: Variant = _find(warming, "feelings", "level")
	check(until != null and near(float(until.get("value")), 0.0),
		"warming clears the acted cause")
	check(level != null and near(float(level.get("value")), 0.0),
		"warming drives no reaction level")

	# Close: the level ramps with readiness under the bond cap.
	context.satisfaction = 82.5
	context.mood = "close"
	_tick(policy, context, 0.1, 10)
	level = _find(_tick(policy, context, 0.1), "feelings", "level")
	check(level != null and float(level.get("value")) > 0.0,
		"a close mare builds a reaction")
	check(float(level.get("value")) <= 0.85 + 0.00001,
		"the close ramp stays under the bond cap")
	until = _find(_tick(policy, context, 0.1), "excitement", "_until")
	check(until != null and near(float(until.get("value")), 0.5),
		"the close build keeps Kissing's cause alive")

	context.satisfaction = 100.0
	_tick(policy, context, 0.1, 20)
	level = _find(_tick(policy, context, 0.1), "feelings", "level")
	check(near(float(level.get("value")), 0.85, 0.01),
		"full readiness reaches her bond cap, not 1.0")

	# A pause releases the build at the fade rate.
	context.seconds_since_stroke = 2.0
	_tick(policy, context, 1.0, 4)
	var actions := _tick(policy, context, 0.1)
	level = _find(actions, "feelings", "level")
	until = _find(actions, "excitement", "_until")
	check(level != null and near(float(level.get("value")), 0.0, 0.01),
		"a stopped player fades the reaction down")
	check(until != null and near(float(until.get("value")), 0.0),
		"a stopped player releases the acted cause")

	# Climax: full for her bond, even when the stroke is stale.
	context.state = 3
	context.satisfaction = 100.0
	context.mood = "climax"
	context.seconds_since_stroke = 5.0
	_tick(policy, context, 0.1, 10)
	actions = _tick(policy, context, 0.1)
	level = _find(actions, "feelings", "level")
	until = _find(actions, "excitement", "_until")
	check(level != null and near(float(level.get("value")), 0.85, 0.01),
		"the climax reaches her bond cap")
	check(until != null and near(float(until.get("value")), 0.5),
		"the climax keeps Kissing's cause alive")

	# An Affection kiss owns the build-up; afterglow hands the fade back to Kissing.
	context.affection_kind = "kiss"
	check(_tick(policy, context, 0.1).is_empty(), "an Affection kiss keeps its own cause")
	context.affection_kind = ""
	context.afterglow = true
	check(_tick(policy, context, 0.1).is_empty(), "afterglow stops the acted cause")
	var after: Array = []
	policy.afterglow_actions(context, after)
	var fade: Variant = _find(after, "excitement", "_until")
	check(fade != null and near(float(fade.get("value")), 0.0),
		"afterglow lets Kissing's own hold and fade run")

	# The debug feature restores the root sway and hoof taps only inside the climax.
	var full := _context(true, true)
	full.state = 3
	full.satisfaction = 100.0
	full.mood = "climax"
	full.reaction_cap = 0.85
	policy.start_actions(full, [])
	var climax: Array = []
	policy.tick_actions(full, 0.1, climax)
	check(_find(climax, "fidgets", "_root").get("kind") == ACTION.RESTORE,
		"the debug feature restores the root sway at climax")
	check(_find(climax, "fidgets", "_tap_next").get("kind") == ACTION.RESTORE,
		"the debug feature restores the hoof taps at climax")
	full.state = 2
	full.mood = "close"
	var leaving: Array = []
	policy.tick_actions(full, 0.1, leaving)
	var re_root: Variant = _find(leaving, "fidgets", "_root")
	var re_tap: Variant = _find(leaving, "fidgets", "_tap_next")
	check(re_root != null and int(re_root.get("value")) == -1,
		"leaving the climax suppresses the root sway again")
	check(re_tap != null and near(float(re_tap.get("value")), 1.0e9),
		"leaving the climax suppresses the hoof taps again")
	var settled: Array = []
	policy.tick_actions(full, 0.1, settled)
	check(_find(settled, "fidgets", "_root") == null,
		"the suppress action is not repeated every tick")
	full.state = 3
	policy.tick_actions(full, 0.1, settled)
	after.clear()
	policy.afterglow_actions(full, after)
	check(_find(after, "fidgets", "_root").get("value") == -1,
		"afterglow suppresses a climax's full fidgets")

	print("INTEGRATIONS_KISSING_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func near(a: float, b: float, eps := 0.00001) -> bool:
	return absf(a - b) <= eps
