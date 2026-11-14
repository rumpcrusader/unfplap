extends RefCounted
## The act key: the key that starts and ends an act. One mod-owned `InputMap` action is installed
## from the `act_key` setting, so the game's typing guard stashes it while a text field has focus.
##
## `O` is the default because the base game's bundled Dance Mod owns `Y`; `Y` stays available for
## players who switch that mod off. The key cap, the native prompt and the runtime all read this
## module or the setting, never a hardcoded key.

const ACTION := &"unfplap_act"
const DEFAULT := "o"
const CHOICES: Array[String] = ["o", "y"]
const LABELS: Array[String] = ["O", "Y"]
const KEYS := {"o": KEY_O, "y": KEY_Y}


## The stored choice, or the default when a hand-edited file names another key.
static func choice(value: String) -> String:
	return value if CHOICES.has(value) else DEFAULT


## The physical key for a choice.
static func key(value: String) -> int:
	return int(KEYS.get(choice(value), KEY_O))


## The key cap label for a choice.
static func label(value: String) -> String:
	var index := CHOICES.find(choice(value))
	return LABELS[index] if index >= 0 else LABELS[0]
