extends RefCounted
## Service: log
## Contract: this header, frozen; edit only with the user's approval
## Scope: process
## Import: shared/log.gd
## The mod's only log sink: one line prefix, one debug gate, warnings and errors always on.

const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
## Every physical line carries it, so interleaved game output cannot continue a mod line.
const PREFIX := "[unfplap] "

## The game setting ENABLE DEBUG: every debug line is silent while it is off.
static var enabled := false
## The switch read the entry injects; a shared file cannot import a service.
static var debug_read := Callable()
## The change notification's listener. A static module has no instance, so it is a bare closure.
static var _listener := func() -> void:
	enabled = debug_read.is_valid() and bool(debug_read.call())
## Joined at load: the one settings notification that keeps the gate in step.
static var _joined := _join()


## Join the settings change notification once per load; a repeated load still counts once.
static func _join() -> bool:
	CHANGE.on_changed(_listener)
	return true


## One debug line: formatted and prefixed only while the gate is on.
static func debug(message: String, args: Array = []) -> void:
	if not enabled:
		return
	print(_line(message if args.is_empty() else message % args))


## A warning always reaches the log: it names a condition the player may have to act on.
static func warning(message: String, args: Array = []) -> void:
	push_warning(_line(message if args.is_empty() else message % args))


## An error always reaches the log: the feature it names could not do its work.
static func error(message: String, args: Array = []) -> void:
	push_error(_line(message if args.is_empty() else message % args))


## One diagnostic block: the title, then each non-empty row on its own indented line.
static func block(title: String, rows: Array) -> void:
	var text := title
	for row: Variant in rows:
		var line := str(row)
		if line.is_empty():
			continue
		text += "\n\t" + line
	debug(text)


## The message with the mod's prefix on every physical line it spans.
static func _line(text: String) -> String:
	if not text.contains("\n"):
		return PREFIX + text
	return PREFIX + text.replace("\n", "\n" + PREFIX)
