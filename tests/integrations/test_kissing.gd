extends SceneTree
## The pure Kissing 1.2.9 policy: availability, the three reaction families and the reduced earth
## fidgets.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/integrations/test_kissing.gd

const KISSING := preload("res://mods/unfplap/integrations/kissing.gd")
const CONTEXT := preload("res://mods/unfplap/integrations/context.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _context(feature := true) -> RefCounted:
	var context := CONTEXT.new()
	context.features = {"kissing_reactions": feature}
	context.bindings = {
		"feelings": true,
		"excitement": true,
		"beat": true,
		"skeleton": true,
		"fidgets": false,
	}
	return context


func _find(actions: Array, binding: String, property: String) -> Variant:
	for raw: Variant in actions:
		if str(raw.get("binding")) == binding and str(raw.get("property")) == property:
			return raw
	return null


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
	check(root != null and int(root.get("value")) == -1, "fidgets keep no skeleton-root weight shift")
	check(tap != null and near(float(tap.get("value")), 1.0e9), "fidgets keep no hoof taps")
	check(_find(start, "beat", "paused") == null,
		"the provider leaves the Beat ownership to the act hold")
	for raw: Variant in start:
		check(str(raw.get("binding")) != "skeleton", "the skeleton root is never driven")
		check(str(raw.get("binding")) != "hoof_hold", "the hoof hold is never driven")

	var tick: Array = []
	policy.tick_actions(context, 0.1, tick)
	var cause: Variant = _find(tick, "excitement", "_until")
	check(cause != null and near(float(cause.get("value")), 0.5),
		"the act gives the build-up a cause")
	context.affection_kind = "kiss"
	tick.clear()
	policy.tick_actions(context, 0.1, tick)
	check(tick.is_empty(), "an Affection kiss keeps its own cause")
	context.affection_kind = ""
	context.afterglow = true
	tick.clear()
	policy.tick_actions(context, 0.1, tick)
	check(tick.is_empty(), "afterglow stops the acted cause")

	var after: Array = []
	policy.afterglow_actions(context, after)
	var fade: Variant = _find(after, "excitement", "_until")
	check(fade != null and near(float(fade.get("value")), 0.0),
		"afterglow lets Kissing's own hold and fade run")
	print("INTEGRATIONS_KISSING_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func near(a: float, b: float, eps := 0.00001) -> bool:
	return absf(a - b) <= eps
