extends Node
## Optional OpenNSFW act audio. The runtime creates this node only when `act_foley` or
## `act_vocals` is on, so both flags off never loads a pack stream or allocates a player.
##
## `foley` covers thrust plaps, slides, bed/fabric, mouth kisses, flank smacks and the wet
## climax layer. `vocals` covers pack human moans and Anon breath. The mod's pony breath,
## Ponese voice and `squee_*` climax stay in runtime.gd and are not gated by these flags.

const CATALOGUE := preload("res://mods/unfplap/audio/act/catalogue.gd")
const PREFERENCES := preload("res://mods/unfplap/preferences.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")

## Depth crossings that fire the presentation sounds. A thrust closes on the mouse reversal,
## which is too late for the impact; these are read while the depth is moving.
const IMPACT_DEPTH := 0.78
const WITHDRAW_DEPTH := 0.22
## Full-strength cue level is lowered by this much at strength 0.
const STRENGTH_GAIN_DB := 10.0

var _foley := false
var _vocals := false
var _pools: Dictionary = {}
var _next: Dictionary = {}
var _last: Dictionary = {}
var _ready_at: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _moan_clock := 0.0
var _breath_clock := 0.0


func setup(foley: bool, vocals: bool) -> void:
	_rng.randomize()
	set_enabled(foley, vocals)


func foley_enabled() -> bool:
	return _foley


func vocals_enabled() -> bool:
	return _vocals


## Rebuild only the group that changed. Called at act start and from apply_live_settings().
func set_enabled(foley: bool, vocals: bool) -> void:
	if foley == _foley and vocals == _vocals and not _pools.is_empty():
		return
	if _foley and not foley:
		_clear_group("foley")
	if _vocals and not vocals:
		_clear_group("vocals")
	_foley = foley
	_vocals = vocals
	if _foley:
		_build_group("foley")
	if _vocals:
		_build_group("vocals")
	if not _foley and not _vocals:
		_moan_clock = 0.0
		_breath_clock = 0.0


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


func play_plap(pose: String, intensity: String, strength: float, at: Vector3) -> bool:
	var cue := cue_for_plap(pose, intensity)
	return play(cue, at, strength, 0.0, pitch_for(strength))


func play_bed(direction: String, strength: float, at: Vector3, soft := false) -> bool:
	if soft:
		return play("fabric", at, strength)
	var cue := "bed_wood_in" if direction == "in" else "bed_wood_out"
	return play(cue, at, strength)


func play_slide(direction: String, strength: float, at: Vector3, extra_db := -6.0) -> bool:
	var cue := "slide_in" if direction == "in" else "slide_out"
	return play(cue, at, strength, extra_db)


func play_mouth_kiss(at: Vector3) -> bool:
	return play("mouth_kiss", at, 0.55)


func play_smack(at: Vector3) -> bool:
	return play("smack", at, 1.0)


func play_climax_wet(at: Vector3) -> void:
	play("climax_wet", at, 1.0)


func play_climax_voice(at: Vector3) -> void:
	if _vocals:
		play("climax_voice", at, 1.0)


## Called for every real thrust. Moans are not per-stroke; the clock keeps them sparse.
func maybe_moan(strength: float, rate: float, at: Vector3) -> void:
	if not _vocals or _moan_clock > 0.0:
		return
	var cue := "moan_intense" if strength >= 0.55 else "moan_soft"
	if play(cue, at, strength):
		_moan_clock = clampf(2.4 - rate * 0.25, 0.9, 2.4) * _rng.randf_range(0.85, 1.2)


## Called once per physics tick from _breath_tick(). Only Anon's breath is pack-driven.
func tick_vocals(delta: float, rate: float, active: bool, at: Vector3) -> void:
	if not _vocals:
		return
	_moan_clock = maxf(0.0, _moan_clock - delta)
	_breath_clock = maxf(0.0, _breath_clock - delta)
	if not active or _breath_clock > 0.0:
		return
	if play("anon_breath", at, 0.55):
		_breath_clock = clampf(2.8 - rate * 0.2, 1.4, 2.8) * _rng.randf_range(0.9, 1.1)


## True only on the frames that will fire a presentation sound. The caller uses this before
## asking for the rump point, which walks the skeleton and should not run on every mouse move.
func crossed(before: float, after: float) -> bool:
	return (before < IMPACT_DEPTH and after >= IMPACT_DEPTH) \
		or (before > WITHDRAW_DEPTH and after <= WITHDRAW_DEPTH)


## Presentation-only depth triggers. Scoring still uses the closed stroke in _on_stroke().
func depth_crossed(before: float, after: float, strength: float, pose: String,
		rump: Vector3, bed_at: Vector3, soft_bed: bool) -> void:
	if not _foley:
		return
	var level := clampf(strength, 0.0, 1.0)
	if before < IMPACT_DEPTH and after >= IMPACT_DEPTH:
		play_plap(pose, PREFERENCES.intensity_for(level), level, rump)
		play_bed("in", level, bed_at, soft_bed)
		play_slide("in", level, rump, -12.0)
	if before > WITHDRAW_DEPTH and after <= WITHDRAW_DEPTH:
		play_slide("out", level, rump, -4.0)
		play_bed("out", level, bed_at, soft_bed)


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
	_moan_clock = 0.0
	_breath_clock = 0.0


static func cue_for_plap(pose: String, intensity: String) -> String:
	if pose == CATALOG.HORSE:
		return "plap_horse"
	return "plap_" + intensity


static func tier_for(strength: float) -> String:
	return PREFERENCES.intensity_for(strength)


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
