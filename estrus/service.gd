extends "res://mods/unfplap/shared/service.gd"
## Service: estrus
## Contract: docs/estrus.md
## Scope: world
## Import: estrus/service.gd only
## The optional cycle service: one phase per mare, her wink timer and the idle rest.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")

## The live service's static handle. Eligibility calls this without preloading `ponies`; a null
## handle means the cycle feature is off for that read and the phase falls back to normal.
static var bound: Node = null

const PHASE_POLL_S := 0.5

## One tracked mare's schedule.
class Session extends RefCounted:
	var phase := ""
	var phase_left := 0.0
	var wink_left := 0.0


## The anatomy API the idle verbs reach; main binds it once both services exist.
var anatomy: ANATOMY = null
var _enabled := true
var _wink_min := 0.0
var _wink_max := 0.0
var _rest_open := 0.0
var _sessions: Dictionary[Node, Session] = {}


func _ready() -> void:
	bound = self
	_snapshot()
	CHANGE.on_changed(Callable(self, "_on_settings_changed"))
	process_priority = 90


## The anatomy API, bound by the entry after both world services exist.
func bind(anatomy_api: ANATOMY) -> void:
	anatomy = anatomy_api


func on_world(_host: Node) -> void:
	_snapshot()


func on_world_closed() -> void:
	_sessions.clear()


func shutdown() -> void:
	CHANGE.off_changed(Callable(self, "_on_settings_changed"))
	_sessions.clear()
	if bound == self:
		bound = null
	anatomy = null


func _exit_tree() -> void:
	if bound == self:
		bound = null


## One pony's phase from the bound service, or normal when no service exists.
static func phase_for(pony: Node) -> String:
	if bound == null:
		return CYCLE.NORMAL
	return str(bound.phase(pony))


## One pony's effective phase: debug override, feature switch and the relationship bond day.
func phase(pony: Node) -> String:
	if not is_instance_valid(pony):
		return CYCLE.NORMAL
	var id := PONY_ID.of(pony)
	var override := CYCLE.override_for(id)
	if not override.is_empty():
		return override
	if not _enabled or id.is_empty() or not pony.has_meta("relationship_runtime"):
		return CYCLE.NORMAL
	var day := GAME.bond_day(GAME.bonds_of(pony))
	if is_nan(day):
		return CYCLE.NORMAL
	return CYCLE.phase(day, id)


## The debug override. A session override is honoured even with the feature off.
func debug_set_phase(pony: Node, phase_name: String) -> String:
	if not is_instance_valid(pony):
		return ""
	CYCLE.set_override(PONY_ID.of(pony), phase_name)
	var session := _session(pony)
	session.phase = ""
	_refresh(pony, session, true)
	var label := "automatic" if phase_name.is_empty() else phase_name
	LOG.debug("estrus override %s=%s", [str(pony.name), label])
	return phase(pony)


## Start scheduling one pony. Called by the roster on every prepare.
func track(pony: Node) -> void:
	if not is_instance_valid(pony) or _sessions.has(pony):
		return
	var session := Session.new()
	_sessions[pony] = session
	pony.tree_exiting.connect(func() -> void: untrack(pony))
	_refresh(pony, session, true)


func untrack(pony: Node) -> void:
	_sessions.erase(pony)


func _process(delta: float) -> void:
	PERF.begin("estrus_tick")
	for pony: Node in _sessions.keys():
		if not is_instance_valid(pony):
			_sessions.erase(pony)
			continue
		var session: Session = _sessions[pony]
		_refresh(pony, session, false)
		if session.phase == CYCLE.HEAT:
			session.wink_left -= delta
			if session.wink_left <= 0.0:
				session.wink_left = _interval()
				if anatomy != null:
					anatomy.wink(pony, CYCLE.wink_burst_count(randf()))
	PERF.end("estrus_tick")


## Refresh one pony's phase and, on a change, its rest and wink clock. `force` re-applies the
## rest even when the phase did not move (a settings edit or a debug override).
func _refresh(pony: Node, session: Session, force: bool) -> void:
	session.phase_left -= get_process_delta_time()
	if not force and session.phase_left > 0.0:
		return
	session.phase_left = PHASE_POLL_S
	var current := phase(pony)
	if current == session.phase and not force:
		return
	session.phase = current
	var rest := _rest_open if current == CYCLE.HEAT else 0.0
	if anatomy != null:
		anatomy.rest(pony, rest)
	session.wink_left = _interval() if current == CYCLE.HEAT else 0.0


func _snapshot() -> void:
	_enabled = SETTINGS.estrus_cycle.get_bool()
	_wink_min = maxf(SETTINGS.wink_min_s.get_num(), 0.05)
	_wink_max = maxf(SETTINGS.wink_max_s.get_num(), 0.05)
	_rest_open = clampf(SETTINGS.heat_rest_open.get_num(), 0.0, 1.0)


func _on_settings_changed() -> void:
	_snapshot()
	for pony: Node in _sessions.keys():
		if is_instance_valid(pony):
			_refresh(pony, _sessions[pony], true)


func _session(pony: Node) -> Session:
	var session: Session = _sessions.get(pony)
	if session == null:
		session = Session.new()
		_sessions[pony] = session
		pony.tree_exiting.connect(func() -> void: untrack(pony))
	return session


func _interval() -> float:
	return CYCLE.wink_interval(_wink_min, _wink_max)
