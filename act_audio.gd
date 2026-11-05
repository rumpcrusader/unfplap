extends Node
## Optional OpenNSFW act audio. The runtime creates this node only when `act_foley` or
## `act_vocals` is on, so both flags off never loads a pack stream or allocates a player.
##
## `foley` covers thrust plaps, slides, bed/fabric and mouth kisses. `vocals`
## covers only the pack climax moan. `climax` is the separate wet finish layer. The mod's pony
## breath, Ponese voice and `squee_*` climax stay in runtime.gd and are not gated by these flags.

const CATALOGUE := preload("res://mods/unfplap/audio/act/catalogue.gd")
const PREFERENCES := preload("res://mods/unfplap/preferences.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")

## The withdraw sound fires when the depth crosses back out. The impact itself fires from the
## closed-stroke event, which is the deepest point and works for shallow thrusts too.
const WITHDRAW_DEPTH := 0.22
## Full-strength cue level is lowered by this much at strength 0.
const STRENGTH_GAIN_DB := 10.0

var _foley := false
var _vocals := false
var _climax := false
var _pools: Dictionary = {}
var _next: Dictionary = {}
var _last: Dictionary = {}
var _ready_at: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func setup(foley: bool, vocals: bool, climax: bool) -> void:
	_rng.randomize()
	set_enabled(foley, vocals, climax)


func foley_enabled() -> bool:
	return _foley


func vocals_enabled() -> bool:
	return _vocals


func climax_enabled() -> bool:
	return _climax


## Rebuild only the layer that changed. Called at start and from apply_live_settings().
func set_enabled(foley: bool, vocals: bool, climax: bool) -> void:
	if foley == _foley and vocals == _vocals and climax == _climax and not _pools.is_empty():
		return
	if _foley and not foley:
		_clear_group("foley")
	if _vocals and not vocals:
		_clear_group("vocals")
	if _climax and not climax:
		_clear_group("climax")
	_foley = foley
	_vocals = vocals
	_climax = climax
	if _foley:
		_build_group("foley")
	if _vocals:
		_build_group("vocals")
	if _climax:
		_build_group("climax")


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


func _clear_group(group: String) -> void:
	for cue: String in _pools.keys():
		var spec: Variant = CATALOGUE.CUES.get(cue, {})
		if not spec is Dictionary or str((spec as Dictionary).get("group", "")) != group:
			continue
		for player: AudioStreamPlayer3D in _pools[cue]:
			if is_instance_valid(player):
				player.stop()
				player.queue_free()
		_pools.erase(cue)
		_next.erase(cue)
		_last.erase(cue)
		_ready_at.erase(cue)


## Play one cue at a world position. Returns false when the cue is disabled, cooling down, or
## has no usable stream so the caller can fall back to the current game-sample path.
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
		+ lerpf(-STRENGTH_GAIN_DB, 0.0, level)
	player.pitch_scale = clampf(pitch * _rng.randf_range(
		float(config.get("pitch_min", 0.94)), float(config.get("pitch_max", 1.06))),
		0.5, 2.0)
	player.play()
	return true


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


func play_plap(pose: String, intensity: String, strength: float, at: Vector3,
		extra_db := 0.0) -> bool:
	if intensity == "soft":
		return false
	var cue := cue_for_plap(pose, intensity)
	var pitch := pitch_for(strength)
	if pose == CATALOG.STANDING:
		pitch *= 0.96
	return play(cue, at, 1.0, extra_db, pitch)


## Called from the closed-stroke event. This is the deepest point of a real thrust, so it also
## catches shallow strokes that never crossed a fixed depth.
func play_impact(pose: String, strength: float, rump: Vector3,
		bed_at: Vector3, soft_bed: bool) -> void:
	if not _foley:
		return
	var level := clampf(strength, 0.0, 1.0)
	var intensity := PREFERENCES.intensity_for(level)
	if intensity != "soft":
		play_plap(pose, intensity, level, rump, plap_volume_db(level))
	if uses_bed(pose):
		play_bed(level, bed_at, soft_bed)
	play_slide("in", level, rump, -12.0)


## Soft beds get the fabric layer; wooden creaks are gone.
func play_bed(strength: float, at: Vector3, soft := false) -> bool:
	if soft:
		return play("fabric", at, strength)
	return false


func play_slide(direction: String, strength: float, at: Vector3, extra_db := -6.0) -> bool:
	var cue := "slide_in" if direction == "in" else "slide_out"
	return play(cue, at, strength, extra_db)


func play_mouth_kiss(at: Vector3) -> bool:
	return play("mouth_kiss", at, 0.55)


func play_climax_wet(at: Vector3) -> void:
	if _climax:
		play("climax_wet", at, 1.0)


func play_climax_voice(at: Vector3) -> void:
	if _vocals:
		play("climax_voice", at, 1.0)


## True only on the frames that will fire the withdraw layer. The caller uses this before asking
## for the rump point, which walks the skeleton and should not run on every mouse move.
func crossed(before: float, after: float) -> bool:
	return before > WITHDRAW_DEPTH and after <= WITHDRAW_DEPTH


## Withdraw only. The impact layer is fired from play_impact() on the closed-stroke event.
func withdraw_crossed(before: float, after: float, strength: float, pose: String,
		rump: Vector3, bed_at: Vector3, soft_bed: bool) -> void:
	if not _foley or not (before > WITHDRAW_DEPTH and after <= WITHDRAW_DEPTH):
		return
	var level := clampf(strength, 0.0, 1.0)
	play_slide("out", level, rump, -4.0)
	if uses_bed(pose):
		play_bed(level, bed_at, soft_bed)


func stop() -> void:
	for cue: String in _pools.keys():
		for player: AudioStreamPlayer3D in _pools[cue]:
			if is_instance_valid(player):
				player.stop()
				player.queue_free()
	_pools.clear()
	_next.clear()
	_last.clear()
	_ready_at.clear()


static func cue_for_plap(pose: String, intensity: String) -> String:
	if intensity == "soft":
		return ""
	if pose == CATALOG.STANDING:
		return "plap_standing"
	return "plap_" + intensity


## Bed and fabric only belong to the missionary shot. The standing pose has no bed under her.
static func uses_bed(pose: String) -> bool:
	return pose != CATALOG.STANDING


static func tier_for(strength: float) -> String:
	return PREFERENCES.intensity_for(strength)


## Plaps start only in the firm range. Firm fades in from -18 dB to full; rough is full.
static func plap_volume_db(strength: float) -> float:
	var level := clampf(strength, 0.0, 1.0)
	if level < PREFERENCES.SOFT_MAX:
		return -80.0
	if level < PREFERENCES.FIRM_MAX:
		return lerpf(-18.0, 0.0, (level - PREFERENCES.SOFT_MAX)
			/ (PREFERENCES.FIRM_MAX - PREFERENCES.SOFT_MAX))
	return 0.0


static func pitch_for(strength: float) -> float:
	return clampf(1.0 + (clampf(strength, 0.0, 1.0) - 0.5) * 0.10, 0.9, 1.1)


static func gain_db(strength: float) -> float:
	return lerpf(-STRENGTH_GAIN_DB, 0.0, clampf(strength, 0.0, 1.0))


## Deterministic variant picker: never repeat the previous index for a cue with >1 variant.
static func next_index(count: int, last: int, roll: int) -> int:
	if count <= 1:
		return 0
	var index := clampi(roll, 0, count - 1)
	if index == last:
		index = (index + 1) % count
	return index
