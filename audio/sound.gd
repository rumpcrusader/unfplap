extends Node
## Base-game act sounds: breath and the climax squeak, built once for the world audio service.
## The service resets the clocks per act and silences them at the act's end.

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")

const BREATH_BASE_INTERVAL_S := 0.9
const BREATH_MIN_INTERVAL_S := 0.2
const BREATH_CLIMAX_INTERVAL_S := 0.85
const BREATH_RATE_CAP := 10.0
const BREATH_FADE_S := 2.5
const AFTERGLOW_BREATH_FADE_S := 5.0

var _breath: AudioStreamPlayer3D
var _breath_streams: Array[AudioStream] = []
var _breath_clock := 0.0
var _breath_gain := 0.0
var _climax_sound: AudioStreamPlayer3D
var _climax_streams: Array[AudioStream] = []


## Load the base-game streams and create the players. Idempotent, so the world service builds it
## once; the per-act cost is the clock reset, not a load.
func build() -> void:
	if is_instance_valid(_breath) and is_instance_valid(_climax_sound):
		return
	if _breath_streams.is_empty():
		for i: int in range(1, 15):
			var path := "res://world/audio/pony/breath_%02d.wav" % i
			if ResourceLoader.exists(path):
				var stream: Resource = load(path)
				if stream is AudioStream:
					_breath_streams.append(stream)
	if _climax_streams.is_empty():
		for path: String in ["res://world/audio/pony/squee_1.ogg",
				"res://world/audio/pony/squee_2.ogg"]:
			if ResourceLoader.exists(path):
				var stream: Resource = load(path)
				if stream is AudioStream:
					_climax_streams.append(stream)
	_breath = AudioStreamPlayer3D.new()
	_breath.name = "UnfplapBreath"
	_breath.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_breath.unit_size = 1.0
	_breath.max_distance = 8.0
	add_child(_breath)
	_climax_sound = AudioStreamPlayer3D.new()
	_climax_sound.name = "UnfplapClimax"
	_climax_sound.bus = _breath.bus
	_climax_sound.unit_size = 1.0
	_climax_sound.max_distance = 10.0
	add_child(_climax_sound)
	reset_act()


## A new act: the breath starts quiet and both clocks restart.
func reset_act() -> void:
	_breath_clock = 0.0
	_breath_gain = 0.0
	silence()


## Stop both players without freeing them.
func silence() -> void:
	if is_instance_valid(_breath):
		_breath.stop()
	if is_instance_valid(_climax_sound):
		_climax_sound.stop()


## Free both players and the loaded streams. Only the service's shutdown calls this.
func stop() -> void:
	silence()
	for player: AudioStreamPlayer3D in [_breath, _climax_sound]:
		if is_instance_valid(player):
			player.queue_free()
	_breath = null
	_climax_sound = null
	_breath_streams.clear()
	_climax_streams.clear()


## The breath phase for one act state; an empty phase means no breath work.
static func phase_for_state(act_state: int) -> String:
	match act_state:
		ACT_STATE.State.ACTIVE:
			return "active"
		ACT_STATE.State.CLIMAX:
			return "climax"
		ACT_STATE.State.AFTERGLOW:
			return "afterglow"
	return ""


func stop_breath() -> void:
	if is_instance_valid(_breath):
		_breath.stop()


func play_climax(at: Vector3) -> void:
	if not _climax_streams.is_empty() and is_instance_valid(_climax_sound):
		_climax_sound.stream = _climax_streams[randi() % _climax_streams.size()]
		_climax_sound.global_position = at
		_climax_sound.pitch_scale = randf_range(0.95, 1.05)
		_climax_sound.play()


## Gain follows the plap rate, jumps loud at climax, and fades out over 5 s in afterglow.
func breath_tick(delta: float, phase: String, rate_raw: float, at: Vector3) -> void:
	if phase.is_empty():
		return
	if _breath_streams.is_empty() or not is_instance_valid(_breath):
		return
	var rate := clampf(rate_raw / BREATH_RATE_CAP, 0.0, 1.0)
	var target := 0.0
	var fade := BREATH_FADE_S
	if phase == "active":
		target = rate
	elif phase == "climax":
		target = 1.0
		fade = 0.25
	else:
		target = 0.0
		fade = AFTERGLOW_BREATH_FADE_S
	_breath_gain = move_toward(_breath_gain, target, delta / fade)
	# Climax volume matches the kiss/plap level, not a shout.
	var max_db := -22.0 if phase == "climax" else -18.0
	var db := lerpf(-42.0, max_db, _breath_gain)
	if _breath.playing:
		_breath.volume_db = db
	_breath_clock -= delta
	if _breath_clock > 0.0:
		return
	if _breath_gain < 0.02:
		_breath_clock = 0.4
		return
	var interval := lerpf(BREATH_BASE_INTERVAL_S, BREATH_MIN_INTERVAL_S, rate)
	if phase == "climax":
		interval = BREATH_CLIMAX_INTERVAL_S
	elif phase == "afterglow":
		interval = 1.4
	_breath_clock = interval
	_breath.stream = _breath_streams[randi() % _breath_streams.size()]
	_breath.global_position = at
	_breath.volume_db = db
	_breath.pitch_scale = 1.0 + rate * 0.2
	_breath.play()
