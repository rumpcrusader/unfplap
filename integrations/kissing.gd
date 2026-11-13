extends "res://mods/unfplap/integrations/provider.gd"
## Kissing 1.2.9 reaction bridge. Kissing's own build-up is held back while the act drives its
## `Feelings.level` directly: nothing before she is close, a bond-capped ramp while she is close and
## being stroked, and her full cap through the climax. A pause releases the build, and the afterglow
## hands the fade back to Kissing. Her horn aura/hum (unicorn and alicorn), wing shiver (pegasus and
## alicorn) and earth-pony tail/ear fidgets all read that level.
##
## Kissing's weight shift and hoof taps are suppressed by default: they move the skeleton root or
## lift a planted hoof. The debug feature `kissing_full_fidgets` restores them for the climax only.
## Its own kiss driver, guard, rear, reach and memory recorder are out of scope.

const ACTION := preload("res://mods/unfplap/integrations/action.gd")
const FEATURE := "kissing_reactions"
const FULL_FIDGETS := "kissing_full_fidgets"
const REQUIRED := ["feelings", "excitement", "beat"]

## The act's "she is close" cue, matching lines/utterance_scheduler.gd `CLOSE_AT`.
const CLOSE_AT := 65.0
const READINESS_MAX := 100.0
## A real stroke inside this window keeps the build going; it matches the act's stroke memory.
const ACTIVE_GRACE_S := 1.2
## Level per second. The rise follows the readiness ramp; the fall matches Kissing's own fade.
const RISE_RATE := 0.45
const FALL_RATE := 0.25
## The climax pins her to the cap quickly instead of waiting for the close ramp.
const CLIMAX_RATE := 1.5

const STATE_CLIMAX := 3

var _start_until := ACTION.set_value("excitement", "_until", 0.0)
var _bind_root := ACTION.bind_value("fidgets", "_root", -1, true)
var _bind_tap := ACTION.bind_value("fidgets", "_tap_next", 1.0e9, true)
var _restore_root := ACTION.restore_value("fidgets", "_root")
var _restore_tap := ACTION.restore_value("fidgets", "_tap_next")
var _tick_until := ACTION.set_value("excitement", "_until", 0.5)
var _tick_level := ACTION.set_value("feelings", "level", 0.0)
var _afterglow_until := ACTION.set_value("excitement", "_until", 0.0)

## The level the act is currently asking for, eased toward the target so steps in readiness do not
## snap the horn or wings.
var _level := 0.0
## Whether the debug flag currently has the full fidget set restored in the climax.
var _full_fidgets := false


func holds_excitement() -> bool:
	return true


func available(context: RefCounted) -> bool:
	var features: Variant = context.get("features")
	if not (features is Dictionary) \
			or not bool((features as Dictionary).get(FEATURE, false)):
		return false
	var bindings: Variant = context.get("bindings")
	if not (bindings is Dictionary):
		return false
	var present := bindings as Dictionary
	for name: String in REQUIRED:
		if not bool(present.get(name, false)):
			return false
	return true


func start_actions(_context: RefCounted, out: Array) -> void:
	_level = 0.0
	_full_fidgets = false
	out.append(_start_until)
	out.append(_bind_root)
	out.append(_bind_tap)


func tick_actions(context: RefCounted, delta: float, out: Array) -> void:
	if bool(context.get("afterglow")):
		return
	# An Affection kiss owns the build-up: let Kissing rise at its own kiss/deep rates.
	if str(context.get("affection_kind")) == "kiss":
		return
	var cap := clampf(float(context.get("reaction_cap")), 0.0, 1.0)
	var target := _target(context, cap)
	var rate := RISE_RATE if target > _level else FALL_RATE
	if int(context.get("state")) == STATE_CLIMAX:
		rate = CLIMAX_RATE
	_level = move_toward(_level, target, rate * maxf(0.0, delta))
	_tick_level.value = _level
	out.append(_tick_level)
	# The cause keeps Kissing's hold topped up while the act is building, so afterglow starts its
	# own hold/fade from the level the act left. At rest it releases the cause entirely.
	_tick_until.value = 0.5 if _level > 0.001 else 0.0
	out.append(_tick_until)
	_sync_full_fidgets(context, out)


## The level the act asks for, capped by her bond. Before close, or once the player has stopped
## stroking, the target is zero and the level falls back at FALL_RATE.
func _target(context: RefCounted, cap: float) -> float:
	if cap <= 0.0:
		return 0.0
	if int(context.get("state")) == STATE_CLIMAX:
		return cap
	if str(context.get("mood")) != "close":
		return 0.0
	if float(context.get("seconds_since_stroke")) > ACTIVE_GRACE_S:
		return 0.0
	var progress := clampf(
		(float(context.get("satisfaction")) - CLOSE_AT) / (READINESS_MAX - CLOSE_AT),
		0.0, 1.0)
	var eased := progress * progress * (3.0 - 2.0 * progress)
	return cap * eased


## Restore the weight-shift root and hoof-tap clock only while the debug flag is on and she is
## climaxing. Every other time the bridge keeps them suppressed.
func _sync_full_fidgets(context: RefCounted, out: Array) -> void:
	var features: Variant = context.get("features")
	var full: bool = int(context.get("state")) == STATE_CLIMAX \
		and features is Dictionary and bool((features as Dictionary).get(FULL_FIDGETS, false))
	if full:
		# Re-emit while the binding is optional: if the fidget node appears mid-climax, the next
		# tick restores it. A restore with no saved value is a no-op in the facade.
		out.append(_restore_root)
		out.append(_restore_tap)
		_full_fidgets = true
	elif _full_fidgets:
		out.append(_bind_root)
		out.append(_bind_tap)
		_full_fidgets = false


func afterglow_actions(_context: RefCounted, out: Array) -> void:
	out.append(_afterglow_until)
	if _full_fidgets:
		out.append(_bind_root)
		out.append(_bind_tap)
		_full_fidgets = false
