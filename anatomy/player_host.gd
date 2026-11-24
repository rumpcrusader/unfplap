extends RefCounted
## Owns the one `anatomy/player.gd` node and its warm/body resolution.
## The public surface is `api.AnonBody`; nothing outside anatomy reaches this module.

const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const PLAYER := preload("res://mods/unfplap/anatomy/player.gd")
const RIG := preload("res://mods/unfplap/anatomy/rig.gd")

var api: Node
var rig: RIG
var player: Node = null
var _part: PLAYER
## The part whose hidden mesh is already built, and whether a deferred warm is queued.
var _warm_part: PLAYER = null
var _warm_queued := false


func setup(api_node: Node, rig_node: RIG) -> void:
	api = api_node
	rig = rig_node


## The player rig arrived. A new body drops the old warm result.
func on_player(body: Node) -> void:
	if player != body:
		_warm_part = null
		_warm_queued = false
	player = body
	refresh()


## A world enter or close: the player part dies with its world.
func on_world_closed() -> void:
	if is_instance_valid(_part):
		_part.encounter(false)
		_part.queue_free()
	_part = null
	_warm_part = null
	_warm_queued = false
	player = null


func refresh() -> void:
	var enabled := SETTINGS.anatomy_on() and is_instance_valid(player)
	if not enabled:
		if is_instance_valid(_part):
			_part.encounter(false)
			_part.queue_free()
			_part = null
		_warm_part = null
		_warm_queued = false
		return
	if not is_instance_valid(_part):
		_part = PLAYER.new()
		_part.name = "UnfplapAnonPart"
		api.add_child(_part)
	_part.player_body = _player_body()
	_part.apply_live()
	_queue_warm()


func _queue_warm() -> void:
	if _warm_queued or not is_instance_valid(_part):
		return
	if is_instance_valid(_warm_part) and _warm_part == _part:
		return
	_warm_queued = true
	_warm_now.call_deferred()


func _warm_now() -> void:
	_warm_queued = false
	if not SETTINGS.anatomy_on() or not is_instance_valid(_part):
		return
	if _part.prepare():
		_warm_part = _part


## The Anon body the player part binds to. The rig resolves the game body.
func _player_body() -> Node3D:
	if not is_instance_valid(player):
		return null
	var anon := rig.anon_body()
	if anon != null:
		return anon
	return player as Node3D if player is Node3D else null


func part() -> PLAYER:
	return _part if is_instance_valid(_part) else null


func apply_live() -> void:
	if is_instance_valid(_part):
		_part.apply_live()


func encounter(on: bool) -> void:
	if is_instance_valid(_part):
		_part.encounter(on)


func prepare() -> bool:
	if not is_instance_valid(_part):
		return false
	return _part.prepare()


func showing() -> bool:
	return is_instance_valid(_part) and _part.showing()


func shaft_length_m() -> float:
	if not is_instance_valid(_part):
		return 0.0
	return _part.shaft_length_m()


func root_now() -> Vector3:
	if not is_instance_valid(_part):
		return Vector3.INF
	var value := _part.root_now()
	return value if value.is_finite() else Vector3.INF


func root_natural() -> Vector3:
	if not is_instance_valid(_part):
		return Vector3.INF
	var value := _part.root_natural()
	return value if value.is_finite() else Vector3.INF


func hip_offset() -> Vector3:
	if not is_instance_valid(_part) or not _part.showing():
		return Vector3.ZERO
	var value := _part.hip_offset_wanted()
	return value if value.is_finite() else Vector3.ZERO


func note_hip_offset(offset: Vector3) -> void:
	if is_instance_valid(_part) and _part.showing():
		_part.hip_offset_applied = offset


## Apply the wanted pelvis offset to the supplied standing hip and record the applied value.
func drive_hip(hip: Node3D) -> void:
	if not is_instance_valid(_part) or not _part.showing() or not is_instance_valid(hip):
		return
	var wanted := _part.hip_offset_wanted()
	if not wanted.is_finite():
		return
	hip.set("offset_world", wanted)
	_part.hip_offset_applied = wanted


func reset_pelvis() -> void:
	if is_instance_valid(_part):
		_part.reset_pelvis()


func debug_scale() -> Vector3:
	if not is_instance_valid(_part) or not _part.showing():
		return Vector3.INF
	return _part.debug_scale()
