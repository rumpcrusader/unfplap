extends RefCounted
## The mod's one log sink and perf entry: the two debug switches, the `[unfplap] ` prefix, the idle
## perf probe and the corner panel. Static like `settings/service.gd`, so printing a line costs a
## preload and never a host reference.
##
##   const LOG := preload("res://mods/unfplap/shared/log.gd")
##   LOG.debug("offer pony=%s pose=%s" % [str(pony.name), pose])
##
## The entry reads the switches from `settings` once and again on a settings edit; nothing else
## reads `settings` for them. See `docs/log.md`.

const PERF_IDLE := preload("res://mods/unfplap/shared/perf_idle.gd")
const PERF_VIEW := preload("res://mods/unfplap/shared/perf_view.gd")

## The game setting DEBUG LOGS: every line is silent with it off.
static var debug_logs := false
## The game setting PRINT PERF LOGS: needs `debug_logs` too.
static var debug_perf := false
## True while an act owns the frame. The idle window stays off inside an act; the entry installs
## `ponies`' read, because a shared module never sees the runtime.
static var act_running := Callable()
## The idle block's header counts, `{runtimes, mares}`, read once per window. The entry installs
## `ponies`' read: the live runtimes are its registry and the mares come from the world facade.
static var counts := Callable()
## The idle (outside-act) debug perf probe; see `docs/perf.md`.
static var _probe := _new_probe()
## The line sink: empty in game, where every line goes to the console. A suite binds one to read
## the text it asserts.
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


## Bind the entry node, which parents the lazy panel.
static func attach(entry: Node) -> void:
	_host = entry


## The entry left the tree: the panel goes with it and the window starts empty.
static func detach() -> void:
	_host = null
	_panel = null
	_probe.reset()


## Every line carries the mod's id, so a block's continuation lines stay attributable after the
## game's own output interleaves with them.
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


## Close one idle chunk whose stamp the caller took. The note itself stays outside the next chunk.
static func close(key: String, started: int) -> void:
	_probe.note(key, Time.get_ticks_usec() - started)


## The cheap idle gate, for a caller that times several chunks in one frame.
static func idle_on() -> bool:
	return _probe.on()


## One frame of the probe. Returns the idle gate so the entry reads it once at the top of
## `_process`; the entry closes its own `entry_process` chunk after the body.
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


## Enabled only while both debug switches are on and no act is running.
static func _probe_on() -> bool:
	if not debug_logs or not debug_perf:
		return false
	return not (act_running.is_valid() and bool(act_running.call()))


## Header counts for one idle block. Read once per window, never per note.
static func _probe_counts() -> Dictionary:
	return counts.call() if counts.is_valid() else {}
