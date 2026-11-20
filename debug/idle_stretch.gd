extends RefCounted
## Debug-only deep-stretch preview through the installed Idle Life mod; it calls the entry's play
## and end callbacks and lets the pose own everything else. See `docs/debug.md`.

## The Idle Life entry script this bridge was written against (1.4.2) and the idle id.
const ENTRY_PATH := "res://mods/idle_life/main.gd"
const IDLE := "stretch_deep"


## Play the deep stretch on `pony`, forced to the end. Returns the action's toast/log line.
static func stretch(entry: Node, pony: Node3D) -> String:
	if not is_instance_valid(pony):
		return "No pony to stretch."
	if not is_instance_valid(entry) or not entry.has_method("play"):
		return "Idle Life isn't running."
	var rows: Variant = entry.get("_rows")
	if rows is Dictionary and (rows as Dictionary).has(pony) and entry.has_method("_finish"):
		entry.call("_finish", pony)
	if bool(entry.call("play", pony, IDLE, 0.0, true)):
		return "Deep stretch for %s." % str(pony.name)
	return "%s can't play the deep stretch." % str(pony.name)
