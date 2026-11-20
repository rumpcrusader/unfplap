extends RefCounted
## Service: log
## Contract: this header, frozen; edit only with the user's approval
## Scope: process
## Import: shared/log.gd
## The mod's only log sink: one line prefix, one debug gate, warnings and errors always on.

const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const PERF_IDLE := preload("res://mods/unfplap/shared/perf_idle.gd")
const PERF_VIEW := preload("res://mods/unfplap/shared/perf_view.gd")
## Every physical line carries it, so interleaved game output cannot continue a mod line.
const PREFIX := "[unfplap] "

## The game setting ENABLE DEBUG: every debug line is silent while it is off.
static var enabled := false
## The game setting PRINT PERF LOGS: the perf gate needs `enabled` too.
static var debug_perf := false
## The switch reads are injected by the entry; a shared file cannot import a service.
static var debug_read := Callable()
static var perf_read := Callable()
## The change notification's listener. A static module has no instance, so the callable is a
## closure over this file's own `apply_settings()`.
static var _listener := func() -> void: apply_settings()
## True while an act owns the frame. The idle window stays off inside an act; the entry installs
## `ponies`' read, because a shared module never sees the runtime.
static var act_running := Callable()
## The idle block's header counts, `{runtimes, mares}`, read once per window from two entry-injected
## reads, so the header never reaches into a service's privates.
static var runtime_count := Callable()
static var mare_count := Callable()
## The idle (outside-act) debug perf probe; see `docs/perf.md`.
static var _probe := _new_probe()
## The entry node: it parents the panel and nothing else.
static var _host: Node = null
## The in-game perf panel, created on the first printed window.
static var _panel: CanvasLayer = null


static func _new_probe() -> PERF_IDLE:
	var probe := PERF_IDLE.new()
	probe.enabled = func() -> bool: return _probe_on()
	probe.counts = func() -> Dictionary: return _probe_counts()
	probe.log = func(text: String) -> void: debug(text)
	probe.show = func(entries: Array, info: Dictionary) -> void: perf_block(entries, info)
	return probe


## Bind the entry node, which parents the lazy panel, and join the settings change notification.
static func attach(entry: Node) -> void:
	_host = entry
	CHANGE.on_changed(_listener)
	apply_settings()


## The entry left the tree: the panel goes with it and the window starts empty.
static func detach() -> void:
	CHANGE.off_changed(_listener)
	_host = null
	_panel = null
	_probe.reset()


## Re-read the two debug switches. A panel that lost either switch closes.
static func apply_settings() -> void:
	enabled = debug_read.is_valid() and bool(debug_read.call())
	debug_perf = perf_read.is_valid() and bool(perf_read.call())
	if not (enabled and debug_perf):
		clear_panel()


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


## Record one idle chunk. Cheap no-op with the probe off.
static func note(key: String, usec: int, owner := "") -> void:
	_probe.note(key, usec, owner)


## Close an idle chunk the caller stamped; the close itself stays outside the next chunk.
static func close(key: String, started: int) -> void:
	_probe.note(key, Time.get_ticks_usec() - started)


## The cheap idle gate, for a caller that times several chunks in one frame.
static func idle_on() -> bool:
	return _probe.on()


## One frame of the probe; the returned gate is the idle window's on state.
static func tick(delta: float) -> bool:
	_probe.tick(delta)
	return _probe_on()


## Clear the window: world start, world close and teardown.
static func reset() -> void:
	_probe.reset()


## One window from either probe, drawn in the corner panel. The text block stays the record.
static func perf_block(entries: Array, info: Dictionary) -> void:
	if not enabled or not debug_perf:
		return
	if not is_instance_valid(_panel) and is_instance_valid(_host):
		_panel = PERF_VIEW.new()
		_panel.name = "UnfplapPerfView"
		_host.add_child(_panel)
	if is_instance_valid(_panel):
		_panel.call("show_window", entries, info)


## Hide the panel and drop its last window: either switch off, a world close.
static func clear_panel() -> void:
	if is_instance_valid(_panel):
		_panel.call("clear")


## Both debug switches on: an act's perf probe and the idle window read this once at a boundary.
static func perf_on() -> bool:
	return enabled and debug_perf


## The idle probe runs only with both switches on and no act live.
static func _probe_on() -> bool:
	if not enabled or not debug_perf:
		return false
	return not (act_running.is_valid() and bool(act_running.call()))


## Header counts for one idle block. Read once per window, never per note.
static func _probe_counts() -> Dictionary:
	return {
		"runtimes": int(runtime_count.call()) if runtime_count.is_valid() else 0,
		"mares": int(mare_count.call()) if mare_count.is_valid() else 0,
	}
