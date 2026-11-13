extends Node
## The act audio facade: the OpenNSFW foley/vocal/wet layers, the base-game breath and squee
## climax, and the Ponese mute policy. The runtime creates one node and keeps it for the process;
## `begin()` opens the layers for an act and `end()` closes them.
##
## `foley` covers thrust plaps, slides, bed/fabric and mouth kisses. `vocals` covers only the pack
## climax moan. `climax` is the separate wet finish layer. The base-game breath, Ponese voice and
## `squee_*` climax are not gated by these flags. See `docs/audio.md`.

const CATALOGUE := preload("res://mods/unfplap/audio/cues.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const SOUND := preload("res://mods/unfplap/audio/sound.gd")
const VOICE := preload("res://mods/unfplap/audio/voice_status.gd")

## The withdraw sound fires when the depth crosses back out. The impact itself fires from the
## tracker's `impact` event, the moment the inward stroke bottoms out, so the plap lands with
## the motion instead of when the stroke closes.
const WITHDRAW_DEPTH := 0.22
## Full-strength cue level is lowered by this much at strength 0.
const STRENGTH_GAIN_DB := 10.0

var _vocals := false
var _climax := false
var _pools: Dictionary = {}
var _next: Dictionary = {}
var _last: Dictionary = {}
var _ready_at: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## The base-game breath and squee players, one child node for the act.
var _sound: Node
## Ponese mute policy state. Kept on the persistent facade, so a settings edit at IDLE can still
## give the voice player its volume back.
var _voice_player: AudioStreamPlayer3D
var _voice_volume_saved := 0.0
var _text_only_voice := false

## Host boundary. A missing callback is a no-op.
var log := Callable()


## Open the act's layers. The foley group is always built; `vocals` and `climax` are optional.
func begin(features: Dictionary) -> void:
	_rng.randomize()
	set_enabled(bool(features.get("act_vocals", false)),
		bool(features.get("act_climax", false)))
	if not is_instance_valid(_sound):
		_sound = SOUND.new()
		_sound.name = "UnfplapActSound"
		add_child(_sound)
	_sound.call("start")


## Close the act's layers but keep the facade (and the voice policy state) alive for the process.
func end() -> void:
	stop()
	if is_instance_valid(_sound):
		_sound.call("stop")
		_sound.queue_free()
		_sound = null


func stop_breath() -> void:
	if is_instance_valid(_sound):
		_sound.call("stop_breath")


## The squee climax plus the pack wet and vocal layers.
func climax(snout: Vector3, dock: Vector3) -> void:
	if is_instance_valid(_sound):
		_sound.call("play_climax", snout)
	play_climax_wet(dock)
	play_climax_voice(snout)


## Breath follows the plap rate and the act phase. `phase` is empty outside the act.
## One breath frame: `phase` is `active`, `climax`, `afterglow` or empty for silence.
func tick(delta: float, phase: String, rate: float, snout: Vector3) -> void:
	if is_instance_valid(_sound):
		_sound.call("breath_tick", delta, phase, rate, snout)


## `mute_ponese_audio`: keep the generated line and text HUD, but silence the Ponese audio for
## this act. A generated-voice pony is left alone. `info` is `VOICE.classify()`.
func apply_voice_policy(pony_node: Variant, id: String, mute: bool, info: Dictionary) -> void:
	_text_only_voice = mute and bool(info.get("effective_ponese", false))
	if not _text_only_voice:
		return
	_voice_player = _find_voice_player(pony_node)
	if not is_instance_valid(_voice_player):
		write_log("voice text-only: no voice player pony=%s" % id)
		return
	_voice_volume_saved = _voice_player.volume_db
	_voice_player.volume_db = -80.0
	write_log("voice text-only pony=%s %s" % [id, VOICE.describe(info)])


func restore_voice_policy() -> void:
	if is_instance_valid(_voice_player):
		_voice_player.volume_db = _voice_volume_saved
	_voice_player = null
	_voice_volume_saved = 0.0
	_text_only_voice = false


func voice_text_only() -> bool:
	return _text_only_voice


func _find_voice_player(pony_node: Variant) -> AudioStreamPlayer3D:
	if not is_instance_valid(pony_node):
		return null
	var head: Variant = pony_node.get("head")
	var voice: Variant = head.get("voice") if head != null else null
	if voice is AudioStreamPlayer3D:
		return voice
	var found: Variant = pony_node.find_child("Voice", true, false)
	return found as AudioStreamPlayer3D if found is AudioStreamPlayer3D else null



func vocals_enabled() -> bool:
	return _vocals


func climax_enabled() -> bool:
	return _climax


## Rebuild only the optional layer that changed. The foley group is always built. Called at
## start and from apply_live_settings().
func set_enabled(vocals: bool, climax: bool) -> void:
	if vocals == _vocals and climax == _climax and not _pools.is_empty():
		return
	if _vocals and not vocals:
		_clear_group("vocals")
	if _climax and not climax:
		_clear_group("climax")
	_vocals = vocals
	_climax = climax
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


## Called from the tracker's impact event: the deepest point of the stroke, so it also catches
## shallow strokes that never crossed a fixed depth. `contact` is how much of his skin actually
## meets her coat there; below it only the slide and the bed play, because a stroke that stopped
## short has no body slap. The bed fabric and the slide are not gated.
func play_impact(pose: String, strength: float, rump: Vector3,
		bed_at: Vector3, soft_bed: bool, contact := 1.0) -> void:
	var level := clampf(strength, 0.0, 1.0)
	var touch := clampf(contact, 0.0, 1.0)
	var intensity := PREFERENCES.intensity_for(level)
	if intensity != "soft" and touch > 0.001:
		play_plap(pose, intensity, level, rump, plap_volume_db(level) + plap_contact_db(touch))
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


## Withdraw only. The impact layer is fired from play_impact() on the tracker's impact event.
func withdraw_crossed(before: float, after: float, strength: float, pose: String,
		rump: Vector3, bed_at: Vector3, soft_bed: bool) -> void:
	if not (before > WITHDRAW_DEPTH and after <= WITHDRAW_DEPTH):
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


## A body slap that only just reaches her coat sits this many dB under a bottomed-out one.
static func plap_contact_db(contact: float) -> float:
	return lerpf(-14.0, 0.0, clampf(contact, 0.0, 1.0))


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


func write_log(text: String) -> void:
	if log.is_valid():
		log.call(text)
