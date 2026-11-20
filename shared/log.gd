extends RefCounted
## The mod's only log sink, and its act and idle perf entry. Static, so printing a line costs a
## preload and never a host reference. The entry binds the two debug switch reads, because a shared
## module cannot import a service, and the change notification re-reads them on every edit.

const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const PERF_IDLE := preload("res://mods/unfplap/shared/perf_idle.gd")
const PERF_VIEW := preload("res://mods/unfplap/shared/perf_view.gd")

## The game setting DEBUG LOGS: every line is silent with it off.
static var debug_logs := false
## The game setting PRINT PERF LOGS: needs `debug_logs` too.
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
## The line sink. Empty in game, where every line prints; a suite binds one to read its text.
static var sink := Callable()
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
	debug_logs = debug_read.is_valid() and bool(debug_read.call())
	debug_perf = perf_read.is_valid() and bool(perf_read.call())
	if not (debug_logs and debug_perf):
		clear_panel()


## Each line repeats the mod's id, so interleaved game output cannot claim a block's continuation
## line.
static func debug(text: String) -> void:
	if not debug_logs:
		return
	if sink.is_valid():
		sink.call(text)
		return
	if text.contains("\n"):
		print(("[unfplap] " + text).replace("\n", "\n[unfplap] "))
	else:
		print("[unfplap] " + text)


## One entry per diagnostic action: identification first, then tab-indented rows.
static func block(title: String, rows: Array) -> void:
	var text := title
	for row: Variant in rows:
		var line := str(row)
		if line.is_empty():
			continue
		text += "\n\t" + line
	debug(text)


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
	if not debug_logs or not debug_perf:
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
	return debug_logs and debug_perf


## The idle probe runs only with both switches on and no act live.
static func _probe_on() -> bool:
	if not debug_logs or not debug_perf:
		return false
	return not (act_running.is_valid() and bool(act_running.call()))


## Header counts for one idle block. Read once per window, never per note.
static func _probe_counts() -> Dictionary:
	return {
		"runtimes": int(runtime_count.call()) if runtime_count.is_valid() else 0,
		"mares": int(mare_count.call()) if mare_count.is_valid() else 0,
	}
