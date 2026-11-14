extends RefCounted
## The act key: the key that starts and ends an act. The player captures a physical key in the
## General tab; one mod-owned `InputMap` action is installed from that keycode, so the game's
## typing guard stashes it while a text field has focus.
##
## `6` is the default because the base game's bundled Dance Mod owns `Y`; `6` is unused by the
## game, every bundled pack and the source mods. `O` and `Y` are not a fixed list: the capture can
## bind any key, including the old choices.

const ACTION := &"unfplap_act"
const DEFAULT_CODE := KEY_6
## Same upper bound the game's own key loader accepts.
const MAX_CODE := 0x2000000


## The stored keycode, or the default when a hand-edited file holds an invalid value.
static func code(value: int) -> int:
	if value <= 0 or value >= MAX_CODE:
		return DEFAULT_CODE
	if OS.get_keycode_string(value).is_empty():
		return DEFAULT_CODE
	return value


## The key cap label for a keycode.
static func label(value: int) -> String:
	var text := OS.get_keycode_string(code(value))
	return text if not text.is_empty() else "?"
