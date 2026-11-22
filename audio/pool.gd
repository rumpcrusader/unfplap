extends Node
## The process-lifetime cue player pools: one `AudioStreamPlayer3D` set per pack cue, built once
## and reused by every act. The world audio service owns this child; an act handle only plays it.

const CATALOGUE := preload("res://mods/unfplap/audio/cues.gd")

var _pools: Dictionary = {}
var _next: Dictionary = {}
var _last: Dictionary = {}
var _ready_at: Dictionary = {}
var _rng := RandomNumberGenerator.new()


## Build the foley group's players. Idempotent, so the world service opens it once per process.
func open() -> void:
	if not _pools.is_empty():
		return
	_rng.randomize()
	_build_group("foley")


## Stop every player but keep it for the next act.
func silence() -> void:
	for cue: String in _pools.keys():
		for player: AudioStreamPlayer3D in _pools[cue]:
			if is_instance_valid(player):
				player.stop()


## Free every player. Only the service's shutdown calls this.
func stop() -> void:
	silence()
	for players: Array in _pools.values():
		for player: AudioStreamPlayer3D in players:
			if is_instance_valid(player):
				player.queue_free()
	_pools.clear()
	_next.clear()
	_last.clear()
	_ready_at.clear()


## Play one cue at a world position. Returns false when the cue is disabled, cooling down or
## has no usable stream.
func play(cue: String, at: Vector3, strength := 1.0,
		extra_db := 0.0, pitch := 1.0) -> bool:
	if not _pools.has(cue) or not at.is_finite():
		return false
	var spec: Variant = CATALOGUE.CUES.get(cue, {})
	if not spec is Dictionary:
		return false
	var config: Dictionary = spec
	var streams: Variant = config.get("streams", [])
	if not streams is Array or (streams as Array).is_empty():
		return false
	var now := Time.get_ticks_msec() * 0.001
	if now < float(_ready_at.get(cue, 0.0)):
		return false
	_ready_at[cue] = now + float(config.get("cooldown", 0.0))
	var variants: Array = streams
	var index := next_index(variants.size(), int(_last.get(cue, -1)),
		_rng.randi_range(0, variants.size() - 1))
	_last[cue] = index
	var player := _take_player(cue)
	if player == null:
		return false
	var level := clampf(strength, 0.0, 1.0)
	player.stream = variants[index] as AudioStream
	player.global_position = at
	player.volume_db = float(config.get("volume_db", -20.0)) + extra_db \
		+ lerpf(-CATALOGUE.STRENGTH_GAIN_DB, 0.0, level)
	player.pitch_scale = clampf(pitch * _rng.randf_range(
		float(config.get("pitch_min", 0.94)), float(config.get("pitch_max", 1.06))),
		0.5, 2.0)
	player.play()
	return true


func _build_group(group: String) -> void:
	for cue: String in CATALOGUE.CUES:
		var spec: Variant = CATALOGUE.CUES[cue]
		if not spec is Dictionary or str((spec as Dictionary).get("group", "")) != group:
			continue
		if _pools.has(cue):
			continue
		_build_cue(cue, spec as Dictionary)


func _build_cue(cue: String, spec: Dictionary) -> void:
	var players: Array[AudioStreamPlayer3D] = []
	var count := maxi(1, int(spec.get("voices", 2)))
	for i: int in count:
		var player := AudioStreamPlayer3D.new()
		player.name = "Act%s%d" % [cue.capitalize(), i + 1]
		player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		player.unit_size = 1.0
		player.max_distance = float(spec.get("distance", 6.0))
		player.max_polyphony = 1
		add_child(player)
		players.append(player)
	_pools[cue] = players
	_next[cue] = 0
	_last[cue] = -1
	_ready_at[cue] = 0.0


func _take_player(cue: String) -> AudioStreamPlayer3D:
	var players: Array = _pools.get(cue, [])
	if players.is_empty():
		return null
	var start := int(_next.get(cue, 0))
	for i: int in players.size():
		var index := (start + i) % players.size()
		var candidate: AudioStreamPlayer3D = players[index]
		if is_instance_valid(candidate) and not candidate.playing:
			_next[cue] = (index + 1) % players.size()
			return candidate
	var index := start % players.size()
	var player: AudioStreamPlayer3D = players[index]
	_next[cue] = (index + 1) % players.size()
	if is_instance_valid(player):
		player.stop()
		return player
	return null


## Deterministic variant picker: never repeat the previous index for a cue with >1 variant.
static func next_index(count: int, last: int, roll: int) -> int:
	if count <= 1:
		return 0
	var index := clampi(roll, 0, count - 1)
	if index == last:
		index = (index + 1) % count
	return index
