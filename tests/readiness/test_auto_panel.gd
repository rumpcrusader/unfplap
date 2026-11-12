extends SceneTree
## Hold-X auto settings layer: tap toggles, hold opens, the grace period, and key repeats.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/readiness/test_auto_panel.gd

const PANEL := preload("res://mods/unfplap/auto_panel.gd")
const DT := 1.0 / 60.0
var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _keys(count := PANEL.KEY_COUNT) -> Array:
	var out: Array = []
	for i: int in count:
		out.append(false)
	return out


## One frame with X held and no layer key; returns the actions.
func _hold(panel: RefCounted, seconds: float, allow := true) -> Array:
	var actions: Array = []
	var steps := int(round(seconds / DT))
	for i: int in steps:
		actions.append_array(panel.tick(DT, true, _keys(), allow))
	return actions


func run() -> void:
	# A short press is still the auto toggle.
	var tap: RefCounted = PANEL.new()
	_hold(tap, 0.1)
	var actions: Array = tap.tick(DT, false, _keys(), true)
	check(actions.has("toggle"), "a short tap toggles auto")
	check(not bool(tap.get("open")), "a short tap does not open the layer")

	# A hold opens the layer and never toggles, even on release.
	var held: RefCounted = PANEL.new()
	_hold(held, PANEL.HOLD_S + 0.1)
	check(bool(held.get("open")), "a hold opens the settings layer")
	actions = held.tick(DT, false, _keys(), true)
	check(not actions.has("toggle"), "a held press never toggles")

	# Releasing keeps it open for the grace, and a re-press inside it does not flicker.
	var grace: RefCounted = PANEL.new()
	_hold(grace, PANEL.HOLD_S + 0.1)
	grace.tick(DT, false, _keys(), true)
	check(bool(grace.get("open")), "release keeps the layer open for the grace")
	grace.tick(PANEL.GRACE_S * 0.5, true, _keys(), true)
	check(bool(grace.get("open")), "a re-press inside the grace keeps it open")
	check(not grace.tick(PANEL.GRACE_S, false, _keys(), true).has("toggle"),
		"a re-pressed layer press still cannot toggle")
	check(not bool(grace.get("open")), "the layer closes after the grace")
	check(bool(PANEL.new().get("open")) == false, "a new panel starts closed")

	# A layer key steps on press, then repeats after the delay at the repeat rate.
	var keys := _keys()
	keys[0] = true
	var test: RefCounted = PANEL.new()
	_hold(test, PANEL.HOLD_S + 0.05)
	actions = test.tick(DT, true, keys, true)
	check(actions.has("min_up"), "the min key steps on press")
	actions = []
	for i: int in int(PANEL.REPEAT_DELAY_S / DT) - 1:
		actions.append_array(test.tick(DT, true, keys, true))
	check(actions.is_empty(), "no repeat before the delay")
	actions = []
	for i: int in int(0.2 / DT):
		actions.append_array(test.tick(DT, true, keys, true))
	check(actions.size() >= 2, "a held key keeps repeating")
	keys[0] = false
	actions = test.tick(DT, true, keys, true)
	check(actions.is_empty(), "releasing the key stops the repeats")

	# Auto off: the tap toggles, but a hold has nothing to open.
	var off: RefCounted = PANEL.new()
	_hold(off, 0.1, false)
	check(off.tick(DT, false, _keys(), false).has("toggle"), "a tap toggles with auto off")
	_hold(off, PANEL.HOLD_S + 0.2, false)
	check(not bool(off.get("open")), "a hold cannot open the layer while auto is off")

	# Stopping auto closes an open layer and clears its key state.
	var closing: RefCounted = PANEL.new()
	_hold(closing, PANEL.HOLD_S + 0.05)
	closing.call("close")
	check(not bool(closing.get("open")), "stopping auto closes the layer")

	print("AUTO_PANEL_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("AUTO_PANEL_PASS")
	quit(0 if failures == 0 else 1)
