extends Node
## Runtime-owned base-game act sounds: breath, thrust plap and the climax squeak. The optional
## pack layers stay in act_audio.gd and are gated by their own feature flags.

const BREATH_BASE_INTERVAL_S := 0.9
const BREATH_MIN_INTERVAL_S := 0.2
const BREATH_CLIMAX_INTERVAL_S := 0.85
const BREATH_RATE_CAP := 10.0
const BREATH_FADE_S := 2.5
const AFTERGLOW_BREATH_FADE_S := 5.0

var runtime: Node
var _breath: AudioStreamPlayer3D
var _breath_streams: Array[AudioStream] = []
var _breath_clock := 0.0
var _breath_gain := 0.0
var _kiss_sound: AudioStreamPlayer3D
var _mouth_kiss_sound: AudioStreamPlayer3D
var _plap_streams: Array[AudioStream] = []
var _climax_sound: AudioStreamPlayer3D
var _kiss_stream: AudioStream
var _climax_streams: Array[AudioStream] = []


func _init(runtime_node: Node = null) -> void:
	runtime = runtime_node


func start() -> void:
	stop()
	_breath_streams.clear()
	for i: int in range(1, 15):
		var path := "res://world/audio/pony/breath_%02d.wav" % i
		if ResourceLoader.exists(path):
			var stream: Resource = load(path)
			if stream is AudioStream:
				_breath_streams.append(stream)
	_breath = AudioStreamPlayer3D.new()
	_breath.name = "UnfplapBreath"
	_breath.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_breath.unit_size = 1.0
	_breath.max_distance = 8.0
	add_child(_breath)
	_breath_clock = 0.0
	_breath_gain = 0.0

	# The boop kiss uses the `kiss_soft_*` pool; use the same streams for the missionary rump plap.
	_kiss_stream = load("res://world/audio/pony/kiss.wav") if ResourceLoader.exists("res://world/audio/pony/kiss.wav") else null
	_plap_streams.clear()
	for i: int in range(1, 41):
		var path := "res://world/audio/pony/kiss_soft_%02d.wav" % i
		if ResourceLoader.exists(path):
			var stream: Resource = load(path)
			if stream is AudioStream:
				_plap_streams.append(stream)
	if _plap_streams.is_empty() and _kiss_stream != null:
		_plap_streams.append(_kiss_stream)
	_kiss_sound = AudioStreamPlayer3D.new()
	_kiss_sound.name = "UnfplapKiss"
	_kiss_sound.bus = _breath.bus
	_kiss_sound.unit_size = 1.0
	_kiss_sound.max_distance = 6.0
	add_child(_kiss_sound)

	_mouth_kiss_sound = AudioStreamPlayer3D.new()
	_mouth_kiss_sound.name = "UnfplapMouthKiss"
	_mouth_kiss_sound.bus = _breath.bus
	_mouth_kiss_sound.unit_size = 1.0
	_mouth_kiss_sound.max_distance = 4.0
	add_child(_mouth_kiss_sound)

	_climax_streams.clear()
	for path: String in ["res://world/audio/pony/squee_1.ogg", "res://world/audio/pony/squee_2.ogg"]:
		if ResourceLoader.exists(path):
			var stream: Resource = load(path)
			if stream is AudioStream:
				_climax_streams.append(stream)
	_climax_sound = AudioStreamPlayer3D.new()
	_climax_sound.name = "UnfplapClimax"
	_climax_sound.bus = _breath.bus
	_climax_sound.unit_size = 1.0
	_climax_sound.max_distance = 10.0
	add_child(_climax_sound)


func stop() -> void:
	for player: AudioStreamPlayer3D in [_breath, _kiss_sound, _mouth_kiss_sound, _climax_sound]:
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	_breath = null
	_kiss_sound = null
	_mouth_kiss_sound = null
	_climax_sound = null


func stop_breath() -> void:
	if is_instance_valid(_breath):
		_breath.stop()


## Play the low plap used when pack foley is off. The caller owns the foley-on check.
func play_kiss(at: Vector3) -> void:
	var stream: AudioStream = _plap_streams.pick_random() if not _plap_streams.is_empty() else _kiss_stream
	if stream == null or not is_instance_valid(_kiss_sound):
		return
	_kiss_sound.stream = stream
	_kiss_sound.global_position = at
	_kiss_sound.unit_size = 1.0
	_kiss_sound.max_distance = 6.0
	_kiss_sound.volume_db = -22.0
	_kiss_sound.pitch_scale = randf_range(0.95, 1.05)
	_kiss_sound.play()


func play_mouth_kiss(at: Vector3) -> void:
	if not is_instance_valid(_mouth_kiss_sound):
		return
	var stream: AudioStream = _plap_streams.pick_random() if not _plap_streams.is_empty() else _kiss_stream
	if stream == null:
		return
	_mouth_kiss_sound.stream = stream
	_mouth_kiss_sound.global_position = at
	_mouth_kiss_sound.volume_db = -22.0
	_mouth_kiss_sound.pitch_scale = randf_range(0.97, 1.03)
	_mouth_kiss_sound.play()


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
