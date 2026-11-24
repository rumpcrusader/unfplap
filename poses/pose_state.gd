extends RefCounted
## Pure pose state and edge math: transitions, request codes and one running edge.

const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")

## The runtime's act state value for an active act. The module never preloads `runtime.gd`.
const ACT_ACTIVE := 2

## The live states that may take the act exit.
const LIVE_STATES := [VIEW.ENTERING, VIEW.STEADY, VIEW.TRANSITIONING]


## One pose state transition. A foreign event, or one that does not apply here, keeps the state.
## This table owns only the state; the service reports a refusal.
static func next(state: int, event: String) -> int:
	match event:
		"begin":
			if state == VIEW.IDLE:
				return VIEW.ENTERING
		"entered":
			if state == VIEW.ENTERING:
				return VIEW.STEADY
		"request":
			if state == VIEW.STEADY:
				return VIEW.TRANSITIONING
		"complete":
			if state == VIEW.TRANSITIONING:
				return VIEW.STEADY
		"exit":
			if state in LIVE_STATES:
				return VIEW.EXITING
		"released":
			if state == VIEW.EXITING:
				return VIEW.IDLE
	return state


## Why a pose request was accepted or refused, in the order the session reports it. `checks` keys
## are optional and pass by default; the service decides which apply.
static func request_code(pose_state: int, act_state: int, from_id: String, to_id: String,
		edge_exists: bool, checks: Dictionary = {}) -> String:
	if from_id == to_id:
		return "same"
	if act_state != ACT_ACTIVE:
		return "bad_phase"
	if pose_state == VIEW.TRANSITIONING:
		return "busy"
	if pose_state != VIEW.STEADY:
		return "not_steady"
	if not edge_exists:
		return "no_edge"
	var required := _flags_code(checks)
	if required != "ok":
		return required
	if not _flag(checks, "asset_ok"):
		return "missing_asset"
	if _flag(checks, "locked", false):
		return "locked"
	return "ok"


## The form/view/refused flags in their fixed order, without an edge block.
static func _flags_code(checks: Dictionary) -> String:
	if not _flag(checks, "form_ok"):
		return "unsupported_form"
	if not _flag(checks, "view_ok"):
		return "unsupported_view"
	if not _flag(checks, "features_ok") or not _flag(checks, "consent_ok"):
		return "refused"
	return "ok"


## A missing check flag passes; `locked` is the one check whose absent value is false.
static func _flag(checks: Dictionary, key: String, fallback := true) -> bool:
	var value: Variant = checks.get(key, fallback)
	return bool(value)


## Start an edge from a validated dictionary. Returns a Run, or the outer `start_edge()` wrapper's
## Variant. Kept as a convenience so the service never depends on inner-class static access.
static func start_edge(edge: Dictionary, from_id: String, to_id: String) -> Variant:
	return Run.start(edge, from_id, to_id)


## One running edge: the clock, one precomputed record per channel, the eased weights and the
## events since the last tick. `start` allocates; `tick` reuses everything.
class Run extends RefCounted:
	const KIND_HOLD := 0
	const KIND_BLEND := 1
	const KIND_SWITCH := 2
	const KIND_LOCK := 3

	## The validated edge dictionary, held by reference and never duplicated.
	var edge: Dictionary = {}
	var id := ""
	var from_id := ""
	var to_id := ""
	var t := 0.0
	var duration := 0.0
	var done := false
	## The base channel's weight, 0..1. Hold, lock and an absent base are 1.0.
	var weight := 1.0

	## Reused per tick; the caller reads them after `tick` and before the next `tick`.
	var _events: Array = []
	var _switches: Array = []
	## The edge's authored events, by reference.
	var _edge_events: Array = []
	var _next_event := 0
	## One precomputed record per channel, in authored order.
	var _channels: Dictionary = {}
	var _order: Array[String] = []
	var _has_base := false

	## Build the run and its channel records, or return null for a bad field, kind, constraint,
	## duration or cycle. Constraints are start floors, not time shifts.
	static func start(edge_data: Dictionary, from_pose: String, to_pose: String) -> Run:
		if edge_data.is_empty():
			return null
		var edge_id := str(edge_data.get("id", ""))
		var edge_from := str(edge_data.get("from", ""))
		var edge_to := str(edge_data.get("to", ""))
		if edge_id.is_empty() or edge_from.is_empty() or edge_to.is_empty():
			return null
		if edge_from != from_pose or edge_to != to_pose:
			return null
		var channels_value: Variant = edge_data.get("channels")
		if not channels_value is Dictionary:
			return null
		var channels := channels_value as Dictionary
		var has_edge_duration := edge_data.has("duration")
		var edge_duration := 0.0
		if has_edge_duration:
			var duration_value: Variant = edge_data.get("duration")
			if not (duration_value is float or duration_value is int):
				return null
			edge_duration = maxf(float(duration_value), 0.0)
		var edge_easing := _ease_code(str(edge_data.get("easing", "smoothstep")))
		var run := Run.new()
		run.edge = edge_data
		run.id = edge_id
		run.from_id = edge_from
		run.to_id = edge_to
		for name_value: Variant in channels:
			var name := str(name_value)
			var channel_value: Variant = channels[name_value]
			if not channel_value is Dictionary:
				return null
			var channel := channel_value as Dictionary
			var kind := KIND_HOLD
			match str(channel.get("kind", "")):
				"hold":
					kind = KIND_HOLD
				"blend", "delta":
					kind = KIND_BLEND
				"switch":
					kind = KIND_SWITCH
				"lock":
					kind = KIND_LOCK
				_:
					return null
			var record := {
				"kind": kind,
				"start": 0.0,
				"duration": 0.0,
				"at": 0.0,
				"easing": edge_easing,
				"fired": false,
			}
			var start_value: Variant = channel.get("start", 0.0)
			if not (start_value is float or start_value is int):
				return null
			record["start"] = maxf(float(start_value), 0.0)
			if channel.has("easing"):
				record["easing"] = _ease_code(str(channel.get("easing")))
			match kind:
				KIND_SWITCH:
					if not channel.has("at"):
						return null
					var at_value: Variant = channel.get("at")
					if not (at_value is float or at_value is int):
						return null
					var at := maxf(float(at_value), 0.0)
					record["at"] = at
					record["start"] = at
				KIND_BLEND:
					if channel.has("duration"):
						var channel_duration: Variant = channel.get("duration")
						if not (channel_duration is float or channel_duration is int):
							return null
						record["duration"] = maxf(float(channel_duration), 0.0)
					elif has_edge_duration:
						record["duration"] = edge_duration
					else:
						return null
				_:
					pass
			run._channels[name] = record
			run._order.append(name)
		run._has_base = run._channels.has("base")
		# Constraints are start floors. Resolve in edge order with a small loop; a graph that keeps
		# changing after one pass per constraint is a cycle.
		var constraints_value: Variant = edge_data.get("constraints", [])
		if not constraints_value is Array:
			return null
		var constraints: Array = []
		for constraint_value: Variant in constraints_value as Array:
			var parsed := _parse_constraint(str(constraint_value))
			if parsed.is_empty():
				return null
			var target_name := str(parsed[0])
			var other_name := str(parsed[1])
			if not run._channels.has(target_name) or not run._channels.has(other_name):
				return null
			constraints.append(parsed)
		var resolved := constraints.is_empty()
		for _round in constraints.size() + 1:
			var changed := false
			for item: Array in constraints:
				var target_record: Dictionary = run._channels[str(item[0])]
				var other_record: Dictionary = run._channels[str(item[1])]
				var floor := float(other_record["start"]) + float(item[2])
				if float(target_record["start"]) < floor:
					target_record["start"] = floor
					changed = true
			if not changed:
				resolved = true
				break
		if not resolved:
			return null
		# A constrained switch fires at its floored start.
		for name: String in run._order:
			var record: Dictionary = run._channels[name]
			if int(record["kind"]) == KIND_SWITCH:
				record["at"] = maxf(float(record["at"]), float(record["start"]))
		# A configured edge duration is the floor; anything longer (channel or switch) wins.
		# With none, each channel supplies its own timing.
		var longest := edge_duration
		var timed := has_edge_duration
		for name: String in run._order:
			var record: Dictionary = run._channels[name]
			match int(record["kind"]):
				KIND_BLEND:
					longest = maxf(longest, float(record["start"]) + float(record["duration"]))
					timed = true
				KIND_SWITCH:
					longest = maxf(longest, float(record["at"]))
					timed = true
				_:
					longest = maxf(longest, float(record["start"]))
		if not timed:
			return null
		run.duration = longest
		var events_value: Variant = edge_data.get("events", [])
		if events_value is Array:
			run._edge_events = events_value as Array
		run._sync_weight()
		return run

	## Advance the clock and fire the switches and events reached this tick. `tick(0.0)` fires the
	## `at: 0` points; after completion only the arrays clear.
	func tick(delta: float) -> void:
		_events.clear()
		_switches.clear()
		if done:
			return
		t = minf(t + maxf(delta, 0.0), duration)
		for name: String in _order:
			var record: Dictionary = _channels[name]
			if int(record["kind"]) != KIND_SWITCH:
				continue
			if bool(record["fired"]) or t < float(record["at"]):
				continue
			record["fired"] = true
			_switches.append(name)
		while _next_event < _edge_events.size():
			var event_value: Variant = _edge_events[_next_event]
			if not event_value is Dictionary:
				_next_event += 1
				continue
			var event := event_value as Dictionary
			var at_value: Variant = event.get("at", 0.0)
			var at := float(at_value) if at_value is float or at_value is int else 0.0
			if at > t:
				break
			_events.append(event)
			_next_event += 1
		_sync_weight()
		done = t >= duration and _all_settled()

	## The eased weight of one channel; 0 for an unknown channel. Hold and lock read 1 at once; a
	## switch turns 1 when it fires; blend/delta ease across their window.
	func channel_weight(channel: String) -> float:
		if not _channels.has(channel):
			return 0.0
		var record: Dictionary = _channels[channel]
		match int(record["kind"]):
			KIND_BLEND:
				var length := float(record["duration"])
				if length <= 0.0:
					return 1.0 if t >= float(record["start"]) else 0.0
				var progress := clampf((t - float(record["start"])) / length, 0.0, 1.0)
				return _ease(int(record["easing"]), progress)
			KIND_SWITCH:
				return 1.0 if bool(record["fired"]) else 0.0
			_:
				return 1.0

	## The edge events that fired since the last tick, by reference and in authored order.
	func events() -> Array:
		return _events

	## The channel names whose switch fired since the last tick, by reference.
	func switches() -> Array:
		return _switches

	## True once every channel has settled and the clock reached the duration.
	func complete() -> bool:
		return done

	## True when every blend/delta has finished and every switch has fired.
	func _all_settled() -> bool:
		for name: String in _order:
			var record: Dictionary = _channels[name]
			match int(record["kind"]):
				KIND_BLEND:
					if t < float(record["start"]) + float(record["duration"]):
						return false
				KIND_SWITCH:
					if not bool(record["fired"]):
						return false
				_:
					pass
		return true

	## The base channel carries the view weight; with no base the weight stays at one.
	func _sync_weight() -> void:
		weight = channel_weight("base") if _has_base else 1.0

	## Parse `"channel after other@seconds"` into `[channel, other, seconds]`, or an empty array.
	static func _parse_constraint(text: String) -> Array:
		var pieces := text.split(" after ", false)
		if pieces.size() != 2:
			return []
		var target := pieces[0].strip_edges()
		var rest := pieces[1].strip_edges()
		var at := rest.rfind("@")
		if at <= 0:
			return []
		var other := rest.substr(0, at).strip_edges()
		var seconds_text := rest.substr(at + 1).strip_edges()
		if target.is_empty() or other.is_empty() or not seconds_text.is_valid_float():
			return []
		return [target, other, maxf(seconds_text.to_float(), 0.0)]

	## Map the authored easing name to its code. Unknown names use the default smoothstep.
	static func _ease_code(name: String) -> int:
		return 1 if name == "linear" else 0

	## Linear or smoothstep, pure over 0..1.
	static func _ease(mode: int, x: float) -> float:
		if mode == 1:
			return x
		return x * x * (3.0 - 2.0 * x)
