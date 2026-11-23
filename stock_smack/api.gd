extends "res://mods/unfplap/shared/service.gd"
## Service: stock_smack
## Scope: world
## Contract: docs/stock_smack.md
## The outside-act flank smack: the native player's pack layer while she is not in an act.

const CUES := preload("res://mods/unfplap/shared/smack_cues.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")


class _Applied extends RefCounted:
	var player: AudioStreamPlayer3D
	var stream: AudioStream
	var volume_db := 0.0
	var pitch_scale := 1.0


var _enabled := false
var _ponies: Array = []
var _applied: Array = []
var _randomizer: AudioStreamRandomizer
var _act_pony: Node


func _ready() -> void:
	_enabled = SETTINGS.pack_smack_sound.get_bool()
	CHANGE.on_changed(Callable(self, "apply_settings"))


## A pony is ready in the world. Remember her even while the setting is off, so a later enable
## reaches every pony already loaded.
func pony_ready(pony: Node) -> void:
	if not is_instance_valid(pony) or _ponies.has(pony):
		return
	_ponies.append(pony)
	_install(pony)


## The setting changed. Enabling installs the pack layer on every pony seen so far; disabling
## puts every saved stock player back. An act pony is skipped until `act_end()`.
func apply_settings() -> void:
	var want := SETTINGS.pack_smack_sound.get_bool()
	if want == _enabled:
		return
	_enabled = want
	if _enabled:
		_prune()
		for pony: Variant in _ponies:
			_install(pony)
		LOG.debug("pack smack on ponies=%d", [_ponies.size()])
		return
	_restore_all()
	LOG.debug("pack smack off")


## The act owns this pony's player: give the stock stream back before the act hands install
## their per-impact variant, and leave the entry out until `act_end()`.
func act_start(pony: Node) -> void:
	_act_pony = pony
	_restore_pony(pony)


func act_end(pony: Node) -> void:
	if _act_pony == pony:
		_act_pony = null
	_install(pony)


func on_world_closed() -> void:
	_restore_all()
	_ponies.clear()
	_act_pony = null


func shutdown() -> void:
	CHANGE.off_changed(Callable(self, "apply_settings"))
	on_world_closed()


func _install(pony: Variant) -> void:
	if not _enabled or not is_instance_valid(pony) or pony == _act_pony:
		return
	var player := _player_for(pony)
	if player == null or _applied_for(player) != null:
		return
	var stream := _smack_stream()
	if stream == null:
		return
	var saved := _Applied.new()
	saved.player = player
	saved.stream = player.stream
	saved.volume_db = player.volume_db
	saved.pitch_scale = player.pitch_scale
	_applied.append(saved)
	player.stream = stream
	player.volume_db = CUES.STOCK_VOLUME_DB
	player.pitch_scale = 1.0


func _restore_pony(pony: Variant) -> void:
	if not is_instance_valid(pony):
		return
	var player := _player_for(pony)
	if player == null:
		return
	var index := _applied_index(player)
	if index < 0:
		return
	var saved: _Applied = _applied[index]
	_applied.remove_at(index)
	if not is_instance_valid(player):
		return
	player.stream = saved.stream
	player.volume_db = saved.volume_db
	player.pitch_scale = saved.pitch_scale


func _restore_all() -> void:
	for saved_v: Variant in _applied:
		var saved: _Applied = saved_v
		if not is_instance_valid(saved.player):
			continue
		saved.player.stream = saved.stream
		saved.player.volume_db = saved.volume_db
		saved.player.pitch_scale = saved.pitch_scale
	_applied.clear()


func _player_for(pony: Variant) -> AudioStreamPlayer3D:
	if not is_instance_valid(pony):
		return null
	var flank: Variant = pony.get_node_or_null("FlankTouch")
	if not is_instance_valid(flank):
		return null
	var player: Variant = flank.get("sound")
	if not player is AudioStreamPlayer3D:
		player = flank.get_node_or_null("sound")
	return player as AudioStreamPlayer3D if player is AudioStreamPlayer3D else null


func _applied_for(player: AudioStreamPlayer3D) -> _Applied:
	var index := _applied_index(player)
	return _applied[index] if index >= 0 else null


func _applied_index(player: AudioStreamPlayer3D) -> int:
	for index: int in _applied.size():
		var saved: _Applied = _applied[index]
		if saved.player == player:
			return index
	return -1


func _prune() -> void:
	for index: int in range(_ponies.size() - 1, -1, -1):
		if not is_instance_valid(_ponies[index]):
			_ponies.remove_at(index)
	for index: int in range(_applied.size() - 1, -1, -1):
		var saved: _Applied = _applied[index]
		if not is_instance_valid(saved.player):
			_applied.remove_at(index)


## The two pack variants behind one stream, so the native player picks a new one on every
## `play()`. The randomizer's no-repeat mode keeps the previous slap out of the next one.
func _smack_stream() -> AudioStreamRandomizer:
	if is_instance_valid(_randomizer):
		return _randomizer
	var randomizer := AudioStreamRandomizer.new()
	randomizer.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	randomizer.random_pitch = CUES.PITCH_MAX
	for path: String in CUES.PATHS:
		var stream: Resource = load(path)
		if stream is AudioStream:
			randomizer.add_stream(-1, stream)
	if randomizer.streams_count <= 0:
		LOG.debug("no pack smack stream")
		return null
	_randomizer = randomizer
	return _randomizer


