extends RefCounted
## Contract: docs/offer.md
## The idle fan sensor: the standing fan, the lying candidate and the pony beside a seated Anon,
## as the transitions the offer reconsiders on. It reads the scene at the poll cadence.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const RUMP_CONE := preload("res://mods/unfplap/shared/rump_cone.gd")
const PERF := preload("res://mods/unfplap/shared/perf.gd")

## The fan discovery and scene fingerprint cadence.
const SENSOR_POLL_S := 0.1
## How many fan candidates are fingerprinted per poll; the rest rotate through the next polls.
const FINGERPRINT_BUDGET := 2
## The eye-to-body margin over the standing reach before the rump math runs.
const NEAR_MARGIN_M := 0.5
const NEAR_SQ := (RUMP_CONE.REACH_M + NEAR_MARGIN_M) * (RUMP_CONE.REACH_M + NEAR_MARGIN_M)
## The AnonPony lying candidate: reach from the eye and the facing floor.
const LYING_REACH_M := 3.2
const LYING_REACH_SQ := LYING_REACH_M * LYING_REACH_M
const LYING_NEAR_SQ := (LYING_REACH_M + NEAR_MARGIN_M) * (LYING_REACH_M + NEAR_MARGIN_M)
const LYING_DOT := 0.78
## The standing pose's moving threshold, as the scene gate reads it.
const STILL_SPEED := 0.06


## One mare's last scene fingerprint.
class MareSense extends RefCounted:
	var pony: Node3D = null
	var fingerprint := 0


## Per-mare state, keyed by instance id.
var _senses: Dictionary = {}
## The standing fan candidates, nearest first; rebuilt in place each frame.
var _candidates: Array[Node3D] = []
var _distances := PackedFloat64Array()
var _previous: Array[Node3D] = []
## The best lying candidate for AnonPony's bed poses, or null.
var _lying: Node3D = null
var _previous_lying: Node3D = null
## The pony lying in the seat beside a seated human Anon, or null.
var _beside: Node3D = null
var _previous_beside: Node3D = null
## The pony the offer last offered, so its state is polled even outside the fan.
var _focus: Node3D = null
var _clock := 0.0
## The next candidate the rotating fingerprint budget reads.
var _cursor := 0
var _pony_form := false
## A world enter or a settings edit: the next update reports a transition.
var _pending := true


## One idle frame; only the poll cadence reads the fan. True when the offer must reconsider.
## The sensor stays inert while an act owns the frame.
func update(delta: float, eye: Vector3, forward: Vector3, pony_form: bool,
		force := false) -> bool:
	_clock += delta
	if PONIES.act_running() or not is_instance_valid(WORLD.game) or not eye.is_finite():
		return _clear()
	var mode_changed := pony_form != _pony_form
	if not (force or _pending or mode_changed or _clock >= SENSOR_POLL_S):
		return false
	_clock = 0.0
	PERF.begin("fan_discover")
	_discover(eye, forward, pony_form)
	PERF.end("fan_discover")
	var list_changed := not _same_candidates()
	var structural := _pending or list_changed
	var changed := structural or _lying != _previous_lying \
		or _beside != _previous_beside or mode_changed
	_pending = false
	_pony_form = pony_form
	var has_state := is_instance_valid(_focus) or is_instance_valid(_lying) \
		or is_instance_valid(_beside) or not _candidates.is_empty()
	if structural and has_state:
		# A transition re-evaluates the offer anyway: baseline every sense now, so a candidate
		# that entered the fan is compared from its current state on its first poll turn.
		PERF.begin("fan_hash")
		var baseline := _player_hash()
		for pony: Node3D in _candidates:
			_changed(pony, _scene_hash(pony, baseline), false)
		if is_instance_valid(_lying):
			_changed(_lying, _scene_hash(_lying, baseline), false)
		if is_instance_valid(_beside):
			_changed(_beside, _scene_hash(_beside, baseline), false)
		if is_instance_valid(_focus):
			_changed(_focus, _scene_hash(_focus, baseline), false)
		_cursor = 0
		PERF.end("fan_hash")
	elif has_state:
		PERF.begin("fan_hash")
		var player_value := _player_hash()
		var lead: Node3D = _focus if is_instance_valid(_focus) else _lead_candidate()
		if is_instance_valid(lead) \
				and _changed(lead, _scene_hash(lead, player_value), true):
			changed = true
		if is_instance_valid(_lying) and _lying != lead \
				and _changed(_lying, _scene_hash(_lying, player_value), true):
			changed = true
		if is_instance_valid(_beside) and _beside != lead and _beside != _lying \
				and _changed(_beside, _scene_hash(_beside, player_value), true):
			changed = true
		# The budget bounds one poll's cost in a crowd; a candidate's next turn is a few polls
		# away, and the offer target above is always read.
		var count := mini(FINGERPRINT_BUDGET, _candidates.size())
		for step in count:
			var index := (_cursor + step) % _candidates.size()
			var pony := _candidates[index]
			if pony == lead or pony == _focus:
				continue
			if _changed(pony, _scene_hash(pony, player_value), true):
				changed = true
		if count > 0:
			_cursor = (_cursor + count) % _candidates.size()
		PERF.end("fan_hash")
	return changed


## The full fan read: every mare in the game's array, with the distance reject first. It runs at
## the poll cadence, so a crowd costs the whole array ten times a second.
func _discover(eye: Vector3, forward: Vector3, pony_form: bool) -> void:
	_previous.clear()
	_previous.assign(_candidates)
	_previous_lying = _lying
	_previous_beside = _beside
	_candidates.clear()
	_distances.clear()
	_lying = null
	_beside = null
	var near_sq := LYING_NEAR_SQ if pony_form else NEAR_SQ
	var lying_dot := LYING_DOT
	var mares: Variant = WORLD.game.get("mares")
	if mares is Array:
		for node: Variant in mares as Array:
			if not node is Node3D or not is_instance_valid(node):
				continue
			var actor := node as Node3D
			if not actor.has_method("posture_status"):
				continue
			var dx := actor.global_position.x - eye.x
			var dz := actor.global_position.z - eye.z
			if dx * dx + dz * dz > near_sq:
				continue
			var status: Dictionary = actor.posture_status()
			var posture := str(status.get("requested", ""))
			if posture == "stand":
				var rump := RUMP_CONE.approx_point(actor)
				var rx := eye.x - rump.x
				var rz := eye.z - rump.z
				var distance := rx * rx + rz * rz
				if distance > RUMP_CONE.REACH_SQ:
					continue
				if not RUMP_CONE.contains(actor.global_basis.z, rump, eye):
					continue
				_insert(actor, distance)
			elif pony_form and posture == "lie_down":
				var at := actor.global_position + Vector3.UP * 0.5
				var to := at - eye
				var reach := to.length_squared()
				if reach > LYING_REACH_SQ or reach < 0.000001:
					continue
				var dot := forward.dot(to * (1.0 / sqrt(reach)))
				if dot > lying_dot:
					lying_dot = dot
					_lying = actor
	if not pony_form:
		_beside = _seat_partner()


## The pony in the seat beside a seated human Anon; null without an occupied seat.
static func _seat_partner() -> Node3D:
	var body: Node3D = WORLD.player
	if not is_instance_valid(body):
		return null
	var seat: Node = WORLD.anon().seat()
	if not is_instance_valid(seat) or not seat.has_meta("couch"):
		return null
	var couch: Variant = seat.get_meta("couch")
	if not is_instance_valid(couch):
		return null
	var partner: Node = WORLD.bed(couch).couch_partner(seat)
	return partner as Node3D if is_instance_valid(partner) else null


## The first fan point, the one that would win if the offer target is null.
func _lead_candidate() -> Node3D:
	return _candidates[0] if not _candidates.is_empty() else null



## The standing fan candidates, nearest first. Live until the next update.
func candidates() -> Array[Node3D]:
	return _candidates


## The best lying candidate for AnonPony's bed poses, or null.
func lying() -> Node3D:
	return _lying


## The pony lying beside a seated human Anon, or null.
func beside() -> Node3D:
	return _beside


## The pony whose scene state the next polls follow: the offer's current target, or null.
func focus(pony: Node) -> void:
	_focus = pony as Node3D
	if is_instance_valid(_focus):
		_changed(_focus, _scene_hash(_focus, _player_hash()), false)


## Advance the per-frame poll clock. The offer calls this once before `due()`.
func advance(delta: float) -> void:
	_clock += delta


## True when this frame should read the fan: a poll, a mode change or a pending reset.
func due(pony_form: bool) -> bool:
	return _pending or pony_form != _pony_form or _clock >= SENSOR_POLL_S


## A world enter, a world close or a settings edit: forget every sense and report a transition.
func reset() -> void:
	_senses.clear()
	_candidates.clear()
	_distances.clear()
	_previous.clear()
	_lying = null
	_previous_lying = null
	_beside = null
	_previous_beside = null
	_focus = null
	_clock = 0.0
	_cursor = 0
	_pony_form = false
	_pending = true


## No world and no fan: drop the candidates without asking the offer to reconsider.
func _clear() -> bool:
	_candidates.clear()
	_distances.clear()
	_previous.clear()
	_lying = null
	_previous_lying = null
	_beside = null
	_previous_beside = null
	_focus = null
	_cursor = 0
	_pending = false
	_pony_form = false
	return false


## Insert one candidate in distance order. The fan is small, so a shift beats a sort.
func _insert(pony: Node3D, distance: float) -> void:
	var at := _candidates.size()
	_candidates.append(pony)
	_distances.append(distance)
	while at > 0 and _distances[at - 1] > distance:
		_candidates[at] = _candidates[at - 1]
		_distances[at] = _distances[at - 1]
		at -= 1
	_candidates[at] = pony
	_distances[at] = distance


func _same_candidates() -> bool:
	if _candidates.size() != _previous.size():
		return false
	for index in _candidates.size():
		if _candidates[index] != _previous[index]:
			return false
	return true


## Store one pony's fingerprint and answer whether it changed. A first read is only a baseline.
func _changed(pony: Node3D, value: int, compare: bool) -> bool:
	var key := int(pony.get_instance_id())
	var sense: Variant = _senses.get(key)
	if not sense is MareSense:
		sense = MareSense.new()
		sense.pony = pony
		(sense as MareSense).fingerprint = value
		_senses[key] = sense
		return false
	var known := sense as MareSense
	var changed := compare and known.fingerprint != value
	known.pony = pony
	known.fingerprint = value
	return changed


## One mare's scene state as an integer mix: everything the offer's checks read that can change
## without moving her. The player's half is read once and passed in.
func _scene_hash(pony: Node3D, player_value: int) -> int:
	var value := _mix(int(pony.get_instance_id()), player_value)
	var status: Dictionary = pony.posture_status()
	value = _mix(value, hash(str(status.get("requested", ""))))
	value = _mix(value, 1 if status.get("settled") == true else 0)
	value = _mix(value, 1 if pony.get("sleeping") == true else 0)
	value = _mix(value, 1 if pony.get_meta("sex_active", false) == true else 0)
	value = _mix(value, 1 if pony.has_meta("sex_aftercare") else 0)
	value = _mix(value, 1 if pony.has_meta("seated") else 0)
	value = _mix(value, 1 if pony.get("motion_paused") == true else 0)
	value = _mix(value, 1 if pony.has_method("is_held") and pony.is_held() else 0)
	value = _mix(value, 1 if pony.has_method("grounded") and not pony.grounded() else 0)
	var speed: Variant = pony.get("actual_speed")
	value = _mix(value, 1 if speed != null and float(speed) > STILL_SPEED else 0)
	var interruption := ""
	if pony.has_method("action_interruption_reason"):
		interruption = str(pony.action_interruption_reason())
	value = _mix(value, 1 if not interruption.is_empty() else 0)
	var target: Variant = pony.get("conversation_target")
	value = _mix(value, int(target.get_instance_id()) \
		if target is Object and is_instance_valid(target) else 0)
	var hoof: Variant = pony.get("hoof_hold")
	value = _mix(value, 1 if hoof is Object and is_instance_valid(hoof) \
		and WORLD.affection().hoof_active(hoof as Object) else 0)
	var affection: Node = pony.get_node_or_null("Affection")
	value = _mix(value, hash(str(affection.get("kind"))) if affection != null else 0)
	value = _mix(value, 1 if _cuddle_active(pony) else 0)
	var nav: Node = pony.get_node_or_null("Navigator")
	if nav != null:
		value = _mix(value, hash(str(nav.get("reserved_by"))))
		value = _mix(value, hash(str(nav.get("command_owner"))))
		value = _mix(value, 1 if nav.get("_has_target") == true else 0)
	var runtime: Node = PONIES.runtime_for(pony)
	var act: Variant = runtime.get("act") if is_instance_valid(runtime) else null
	value = _mix(value, int(act.get("state")) if act != null else 0)
	return value


## The player's half of the fingerprint: everything the press guards read.
func _player_hash() -> int:
	var body: Node3D = WORLD.player
	if not is_instance_valid(body):
		return 0
	var value := 0
	value = _mix(value, 1 if body.get("controls_locked") == true else 0)
	value = _mix(value, 1 if body.get("flying") == true else 0)
	var wing: Variant = body.get("wing_flight")
	value = _mix(value, 1 if wing is Object and is_instance_valid(wing) \
		and wing.get("active") == true else 0)
	value = _mix(value, 1 if body.get_meta("knocked_down", false) == true else 0)
	var swimming: Variant = body.get("swimming")
	value = _mix(value, 1 if swimming is Object and is_instance_valid(swimming) \
		and swimming.get("active") == true else 0)
	var seat: Variant = body.get("seat")
	value = _mix(value, int(seat.get_instance_id()) \
		if seat is Object and is_instance_valid(seat) else 0)
	var rest: Variant = body.get("_couch_rest")
	if rest is Object and is_instance_valid(rest):
		var amount: Variant = rest.get("amount")
		value = _mix(value, 1 if amount != null and float(amount) < 0.99 else 0)
	if is_instance_valid(WORLD.game):
		var inventory: Variant = WORLD.game.get("inventory")
		if inventory is Object and is_instance_valid(inventory):
			var held: Variant = inventory.get("held")
			value = _mix(value, (held as Dictionary).size() if held is Dictionary else 0)
			value = _mix(value, hash(str(inventory.get("holding_case"))))
	value = _mix(value, 1 if WORLD.player_is_pony() else 0)
	value = _mix(value, 1 if WORLD.headset_view() else 0)
	value = _mix(value, int(Input.mouse_mode))
	return value


## The cuddle rule the scene gate reads: a marker, or an enabled or blending session.
func _cuddle_active(pony: Node3D) -> bool:
	if pony.has_meta("cuddle_active"):
		return true
	if not pony.has_meta("cuddle_session"):
		return false
	var session: Variant = pony.get_meta("cuddle_session")
	if session == null or not is_instance_valid(session):
		return false
	if session.get("enabled") == true:
		return true
	var blend: Variant = session.get("blend")
	return blend != null and float(blend) > 0.01


static func _mix(value: int, extra: int) -> int:
	return (value * 31 + extra) & 0x7FFFFFFF
