extends "res://mods/unfplap/integrations/provider.gd"
## Kissing 1.2.9 reaction bridge. Kissing keeps building her feelings; this provider holds back the
## game's own burst excitement during the act and gives the build-up a cause, so her horn aura/hum
## (unicorn and alicorn), wing shiver (pegasus and alicorn) and earth-pony tail/ear fidgets play.
##
## Kissing's weight shift and hoof taps are not bound: they move the skeleton root or lift a planted
## hoof. Its own kiss driver, guard, rear, reach and memory recorder are out of scope.

const ACTION := preload("res://mods/unfplap/integrations/action.gd")
const FEATURE := "kissing_reactions"
const REQUIRED := ["feelings", "excitement", "beat"]

var _start_until := ACTION.set_value("excitement", "_until", 0.0)
var _bind_root := ACTION.bind_value("fidgets", "_root", -1, true)
var _bind_tap := ACTION.bind_value("fidgets", "_tap_next", 1.0e9, true)
var _tick_until := ACTION.set_value("excitement", "_until", 0.5)
var _afterglow_until := ACTION.set_value("excitement", "_until", 0.0)


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
	out.append(_start_until)
	out.append(_bind_root)
	out.append(_bind_tap)


func tick_actions(context: RefCounted, _delta: float, out: Array) -> void:
	if bool(context.get("afterglow")):
		return
	if str(context.get("affection_kind")) == "kiss":
		return
	out.append(_tick_until)


func afterglow_actions(_context: RefCounted, out: Array) -> void:
	out.append(_afterglow_until)
