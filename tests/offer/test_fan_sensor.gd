extends "res://mods/unfplap/tests/support/suite.gd"
## The offer fan sensor: the standing fan boundary, the candidate distance order, the lying
## candidate, the bed-side partner, the scene fingerprint transitions, the far-mare silence and
## the act-inert state.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/offer/test_fan_sensor.gd

const SENSOR := preload("res://mods/unfplap/offer/fan_sensor.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")



class FakeHoof extends RefCounted:
	var active_state := false

	func active() -> bool:
		return active_state


class FakeMare extends Node3D:
	var requested := "stand"
	var settled := true
	var sleeping := false
	var held := false
	var speed := 0.0
	var hoof_hold: Variant = null

	func posture_status() -> Dictionary:
		return {"requested": requested, "settled": settled}

	func is_held() -> bool:
		return held

	func grounded() -> bool:
		return true

	func action_interruption_reason() -> String:
		return ""


class FakeGame extends Node:
	var mares: Array = []
	var headset_view := false


class FakePlayer extends Node3D:
	var seat: Variant = null


class FakeCouch extends Node:
	var partner_pony: Node = null

	func partner(_seat: Node) -> Node:
		return partner_pony


func run() -> void:
	_check_fan_boundary()
	_check_order_and_focus()
	_check_lying()
	_check_beside()
	_check_fingerprint_and_far_mare()
	_check_rotation()
	_check_poll_cadence()
	_check_reset_and_act()
	if failures == 0:
		print("FAN_SENSOR_PASS")
	finish()


## The fan is the rump's reach and half-plane; a held mare is still a candidate until the poll.
func _check_fan_boundary() -> void:
	var made := _fixture()
	var sensor := SENSOR.new()
	var mare: FakeMare = made["mare"]
	var eye := Vector3(0.0, 1.6, 2.10)
	check(sensor.update(0.2, eye, Vector3(0.0, 0.0, -1.0), false),
		"the first read reports a transition")
	check(sensor.candidates().size() == 1 and sensor.candidates()[0] == mare,
		"a point at the fan's reach is inside")
	check(not sensor.update(0.2, eye, Vector3(0.0, 0.0, -1.0), false),
		"a stationary fan reports nothing")
	eye = Vector3(0.0, 1.6, 2.20)
	sensor.update(0.2, eye, Vector3(0.0, 0.0, -1.0), false)
	check(sensor.candidates().is_empty(), "a point past the reach is outside")
	mare.basis = Basis(Vector3.UP, PI)
	eye = Vector3(0.0, 1.6, 0.5)
	sensor.update(0.2, eye, Vector3(0.0, 0.0, -1.0), false)
	check(sensor.candidates().is_empty(), "a point in front of her is outside the fan")
	_free(made, sensor)


## The candidates arrive nearest first, and the focus follows the offer.
func _check_order_and_focus() -> void:
	var made := _fixture()
	var sensor := SENSOR.new()
	var far: FakeMare = made["mare"]
	var near := _mare(Vector3(0.0, 0.0, 1.2), "near")
	(made["game"] as FakeGame).mares.append(near)
	var eye := Vector3(0.0, 1.6, 2.10)
	sensor.update(0.2, eye, Vector3(0.0, 0.0, -1.0), false)
	check(sensor.candidates().size() == 2, "both fan points are candidates")
	check(sensor.candidates()[0] == near, "the nearer candidate is first")
	sensor.focus(near)
	check(sensor.update(0.2, eye, Vector3(0.0, 0.0, -1.0), false) == false,
		"a focus baseline alone reports nothing")
	far.requested = "lie_down"
	check(sensor.update(0.2, eye, Vector3(0.0, 0.0, -1.0), false),
		"a candidate leaving the fan reports a transition")
	_free(made, sensor)


## AnonPony's lying candidate is the best-facing mare in front, within the lying reach.
func _check_lying() -> void:
	var made := _fixture()
	var sensor := SENSOR.new()
	var mare: FakeMare = made["mare"]
	mare.requested = "lie_down"
	var eye := Vector3(0.0, 1.6, 2.0)
	var forward := Vector3(0.0, 0.0, -1.0)
	sensor.update(0.2, eye, forward, true)
	check(sensor.lying() == mare, "a lying mare in front is the lying candidate")
	sensor.reset()
	sensor.update(0.2, eye, forward, false)
	check(sensor.lying() == null, "human Anon has no lying candidate")
	mare.requested = "stand"
	sensor.reset()
	sensor.update(0.2, eye, forward, false)
	check(sensor.candidates().size() == 1, "a standing mare is a fan candidate")
	_free(made, sensor)


## A human Anon's bed-side partner is a candidate of its own: she arriving, settling and leaving
## each report a transition, and AnonPony has none.
func _check_beside() -> void:
	var made := _fixture()
	var sensor := SENSOR.new()
	var mare: FakeMare = made["mare"]
	mare.requested = "lie_down"
	var player := FakePlayer.new()
	player.name = "FakePlayer"
	root.add_child(player)
	var seat := Node3D.new()
	seat.name = "PlayerBedSeat"
	root.add_child(seat)
	var couch := FakeCouch.new()
	couch.name = "FakeBedRest"
	root.add_child(couch)
	seat.set_meta("couch", couch)
	player.seat = seat
	WORLD.bind_player(player)
	var eye := Vector3(0.0, 1.6, 2.0)
	var forward := Vector3(0.0, 0.0, -1.0)
	sensor.update(0.2, eye, forward, false)
	check(sensor.beside() == null, "an empty seat has no bed-side partner")
	couch.partner_pony = mare
	check(sensor.update(0.2, eye, forward, false), "a partner arriving reports a transition")
	check(sensor.beside() == mare, "the seat's other occupant is the bed-side partner")
	mare.settled = false
	check(sensor.update(0.2, eye, forward, false), "the partner settling reports a transition")
	mare.settled = true
	check(sensor.update(0.2, eye, forward, false), "the partner moving again reports a transition")
	couch.partner_pony = null
	check(sensor.update(0.2, eye, forward, false), "the partner leaving reports a transition")
	check(sensor.beside() == null, "an empty seat clears the bed-side partner")
	couch.partner_pony = mare
	sensor.reset()
	sensor.update(0.2, eye, forward, true)
	check(sensor.beside() == null, "AnonPony has no bed-side partner")
	_drop(player)
	_drop(seat)
	_drop(couch)
	_free(made, sensor)


func _drop(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


## The scene fingerprint polls the candidates only: a state change inside the fan reports a
## transition, a change of a mare outside it does not.
func _check_fingerprint_and_far_mare() -> void:
	var made := _fixture()
	var sensor := SENSOR.new()
	var mare: FakeMare = made["mare"]
	var far := _mare(Vector3(0.0, 0.0, -8.0), "far")
	(made["game"] as FakeGame).mares.append(far)
	var eye := Vector3(0.0, 1.6, 2.10)
	var forward := Vector3(0.0, 0.0, -1.0)
	sensor.update(0.2, eye, forward, false)
	check(not sensor.update(0.016, eye, forward, false), "a no-op frame is silent")
	check(not sensor.update(0.2, eye, forward, false), "a quiet poll is silent")
	mare.held = true
	check(sensor.update(0.2, eye, forward, false), "a held candidate reports a transition")
	var hoof := FakeHoof.new()
	mare.hoof_hold = hoof
	sensor.update(0.2, eye, forward, false)
	hoof.active_state = true
	check(sensor.update(0.2, eye, forward, false),
		"an active hoof hold reports a transition")
	far.held = true
	check(not sensor.update(0.2, eye, forward, false), "a far mare's change is silent")
	_free(made, sensor)


## A transition baselines every candidate; between polls the budget rotates, so the farthest
## candidate's change is still caught within a few turns.
func _check_rotation() -> void:
	var made := _fixture()
	var sensor := SENSOR.new()
	var far: FakeMare = made["mare"]
	var near := _mare(Vector3(0.0, 0.0, 1.2), "near")
	var mid := _mare(Vector3(0.0, 0.0, 0.6), "mid")
	var game: FakeGame = made["game"]
	game.mares = [far, near, mid]
	var eye := Vector3(0.0, 1.6, 2.10)
	var forward := Vector3(0.0, 0.0, -1.0)
	sensor.update(0.2, eye, forward, false)
	check(sensor.candidates().size() == 3, "the three fan points are candidates")
	far.held = true
	var detected := false
	for _turn in 3:
		if sensor.update(0.2, eye, forward, false):
			detected = true
			break
	check(detected, "the rotating budget reaches the farthest candidate")
	_free(made, sensor)


## The fan is read at the poll cadence, not every frame; the press forces a read.
func _check_poll_cadence() -> void:
	var made := _fixture()
	var sensor := SENSOR.new()
	var mare: FakeMare = made["mare"]
	var eye := Vector3(0.0, 1.6, 2.10)
	var forward := Vector3(0.0, 0.0, -1.0)
	sensor.update(0.2, eye, forward, false)
	mare.requested = "lie_down"
	check(not sensor.update(0.05, eye, forward, false),
		"a frame between polls does not read the fan")
	check(sensor.candidates().size() == 1, "the stale candidate survives until the poll")
	check(sensor.update(0.06, eye, forward, false), "the poll reads the fan and drops the mare")
	check(sensor.candidates().is_empty(), "the poll clears the lodged candidate")
	mare.requested = "stand"
	check(sensor.update(0.0, eye, forward, false, true), "a forced read skips the cadence")
	check(sensor.candidates().size() == 1, "the forced read finds the standing mare")
	_free(made, sensor)


## A reset reports the next read, and a live act clears the fan without a transition.
func _check_reset_and_act() -> void:
	var made := _fixture()
	var sensor := SENSOR.new()
	var eye := Vector3(0.0, 1.6, 2.10)
	var forward := Vector3(0.0, 0.0, -1.0)
	sensor.update(0.2, eye, forward, false)
	sensor.reset()
	check(sensor.update(0.2, eye, forward, false), "a reset reports the next read")
	var holder := Node.new()
	PONIES.set_active(holder)
	check(not sensor.update(0.2, eye, forward, false), "a live act reports nothing")
	check(sensor.candidates().is_empty(), "a live act clears the fan")
	PONIES.clear_active(holder)
	check(sensor.update(0.2, eye, forward, false), "the idle fan returns after the act")
	holder.free()
	_free(made, sensor)


func _fixture() -> Dictionary:
	var game := FakeGame.new()
	game.name = "FakeGame"
	root.add_child(game)
	var mare := _mare(Vector3.ZERO, "near")
	game.mares = [mare]
	PONIES.offer = null
	PONIES.stock_smack = null
	PONIES.eligibility = null
	WORLD.bind_world(game)
	return {"game": game, "mare": mare}


func _mare(at: Vector3, mare_name: String) -> FakeMare:
	var mare := FakeMare.new()
	mare.name = mare_name
	root.add_child(mare)
	mare.global_position = at
	return mare


func _free(made: Dictionary, sensor: Variant) -> void:
	sensor.reset()
	WORLD.unbind()
	for mare: Node in (made["game"] as FakeGame).mares:
		if is_instance_valid(mare) and mare.get_parent() != null:
			mare.get_parent().remove_child(mare)
			mare.free()
	var game: Node = made["game"]
	if is_instance_valid(game) and game.get_parent() != null:
		game.get_parent().remove_child(game)
		game.free()
