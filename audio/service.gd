extends Node
## The act audio facade: the pack foley layer, the base-game breath and squee climax, the Ponese
## mute policy and her own generated vocal. The runtime creates one node and keeps it for the
## process; `bind()` names the act's pony, id and bed and `begin()` opens the layer for an act,
## `end()` closes it.
##
## `foley` covers thrust plaps, slides, bed/fabric and mouth kisses. The base-game breath, Ponese
## voice and `squee_*` climax are separate and always on. See `docs/audio.md`.

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const CATALOGUE := preload("res://mods/unfplap/audio/cues.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const SOUND := preload("res://mods/unfplap/audio/sound.gd")
const VOICE := preload("res://mods/unfplap/audio/voice_status.gd")

## The withdraw sound fires when the depth crosses back out. The impact itself fires from the
## tracker's `impact` event, the moment the inward stroke bottoms out, so the plap lands with
## the motion instead of when the stroke closes.
const WITHDRAW_DEPTH := 0.22
## Full-strength cue level is lowered by this much at strength 0.
const STRENGTH_GAIN_DB := 10.0
## The base game's own soft kiss level at her snout.
const ORAL_KISS_DB := -22.0
## One generated vocal per this many seconds of act, however fast the stroke.
const VOCAL_COOLDOWN_S := 3.0
## Her body's own vocal level under the spoken line.
const VOCAL_DB := -34.0

## The active impact profile, from the pose view's `impact` (`missionary` or `standing`).
## `pose_changed()` sets it; the impact and withdraw calls read it instead of the pose id.
var _impact_profile := ""
var _pools: Dictionary = {}
var _next: Dictionary = {}
var _last: Dictionary = {}
var _ready_at: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## The base-game breath and squee players, one child node for the act.
var _sound: Node
## The act's pony, its stable id and its bed. `bind()` sets them; they resolve the snout, the bed
## point, the soft-bed flag, the oral kiss and the director's vocal cache key, so the call sites
## carry only the stroke facts.
var _pony: Node3D
var _id := ""
var _bed: Node3D
var _bed_soft := false
## The generated-vocal cooldown runs on processed time: a paused tree freezes it with the act.
var _vocal_cooldown := 0.0
## Ponese mute policy state. Kept on the persistent facade, so a settings edit at IDLE can still
## give the voice player its volume back.
var _voice_player: AudioStreamPlayer3D
var _voice_volume_saved := 0.0
var _text_only_voice := false

## Host boundary. A missing callback is a no-op.
var log := Callable()


## Name the act's pony, its stable id and the bed it plays on. Couch, sofa and cloth are the soft
## surfaces that get the fabric layer; every other bed is wood and plays none.
func bind(pony_in: Node3D, id: String, bed_in: Node3D) -> void:
	_pony = pony_in
	_id = id
	_bed = bed_in
	_bed_soft = is_instance_valid(bed_in) and soft_surface(str(bed_in.name).to_lower())


static func soft_surface(name_lower: String) -> bool:
	return "couch" in name_lower or "sofa" in name_lower or "cloth" in name_lower


## Open the act's layer. The impact profile and the vocal cooldown are cleared here and the first
## pose fan-out of the act fills the profile.
func begin() -> void:
	_rng.randomize()
	_impact_profile = ""
	_vocal_cooldown = 0.0
	_build_group("foley")
	if not is_instance_valid(_sound):
		_sound = SOUND.new()
		_sound.name = "UnfplapActSound"
		add_child(_sound)
	_sound.call("start")


## One pose-change hook: the impact profile follows the live view, so an internal pose (`standing_test`)
## or a later oral edge never inherits the act's start pose. A missing profile falls back to the bed
## profile; standing and standing_test carry `impact = "standing"`.
func pose_changed(view: Variant) -> void:
	var audio: Variant = view.audio if view != null else null
	_impact_profile = str((audio as Dictionary).get("impact", "")) if audio is Dictionary else ""
	if _impact_profile.is_empty():
		_impact_profile = "missionary"


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


## The base-game squee climax at her snout.
func climax() -> void:
	if is_instance_valid(_sound):
		_sound.call("play_climax", snout())


## Breath follows the plap rate and the act phase. `phase` is empty outside the act.
func tick(delta: float, phase: String, rate: float) -> void:
	if is_instance_valid(_sound):
		_sound.call("breath_tick", delta, phase, rate, snout())


## The breath phase for one act state. Posing in and restore are silent; the base-game breath is
## loud in `ACTIVE`, jumps at `CLIMAX` and fades through `AFTERGLOW`.
static func phase_for_state(act_state: int) -> String:
	match act_state:
		ACT_STATE.State.ACTIVE:
			return "active"
		ACT_STATE.State.CLIMAX:
			return "climax"
		ACT_STATE.State.AFTERGLOW:
			return "afterglow"
	return ""


## Her snout, the base game's own kiss point. A lost body has no point: the cues are dropped
## rather than played at a guessed position.
func snout() -> Vector3:
	if not is_instance_valid(_pony):
		return Vector3.ZERO
	var boop: Variant = _pony.get("boop_node")
	if is_instance_valid(boop) and boop.has_method("nose_world"):
		return boop.call("nose_world")
	return _pony.global_position + Vector3.UP * 1.0


## The bed's surface point for the fabric layer. Without a bed the caller's rump point keeps the
## cue where the stroke is.
func bed_point(rump: Vector3) -> Vector3:
	if is_instance_valid(_bed):
		return _bed.global_position + Vector3.UP * 0.35
	return rump


func bed_soft() -> bool:
	return _bed_soft


## `mute_ponese_audio`: keep the generated line and text HUD, but silence the Ponese audio for
## this act. A generated-voice pony is left alone.
func apply_voice_policy(mute: bool, pony_in: Node3D, id: String) -> void:
	var info := VOICE.classify(_voice_profile(id), _tts_node(), _tts_enabled())
	_text_only_voice = mute and bool(info.get("effective_ponese", false))
	if not _text_only_voice:
		return
	_voice_player = _find_voice_player(pony_in)
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


## The debug read: the routing the director's profile and the game's TTS switch give her.
func voice_status_line(id: String) -> String:
	return "voice " + VOICE.describe(VOICE.classify(_voice_profile(id), _tts_node(), _tts_enabled()))


func _voice_profile(id: String) -> Dictionary:
	var director := _director()
	if director == null:
		return {}
	var characters: Variant = director.get("characters")
	if characters is Dictionary and (characters as Dictionary).has(id):
		var entry: Variant = (characters as Dictionary)[id]
		if entry is Dictionary:
			var profile: Variant = (entry as Dictionary).get("profile", {})
			if profile is Dictionary:
				return profile
	return {}


func _tts_node() -> Node:
	var director := _director()
	if director == null:
		return null
	var tts: Variant = director.get("tts")
	return tts as Node if is_instance_valid(tts) else null


func _tts_enabled() -> bool:
	var settings := get_node_or_null("/root/Settings")
	if settings != null and settings.has_method("tts_enabled"):
		return bool(settings.call("tts_enabled"))
	return true


func _director() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("conversation_director")


func _find_voice_player(pony_node: Node3D) -> AudioStreamPlayer3D:
	if not is_instance_valid(pony_node):
		return null
	var head: Variant = pony_node.get("head")
	var voice: Variant = head.get("voice") if head != null else null
	if voice is AudioStreamPlayer3D:
		return voice
	var found: Variant = pony_node.find_child("Voice", true, false)
	return found as AudioStreamPlayer3D if found is AudioStreamPlayer3D else null


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


## The body slap: `tier` is `firm` or `rough`, already chosen from the impact speed. There is no
## pose branch: standing and missionary play the same bags.
func play_plap(tier: String, strength: float, at: Vector3, extra_db := 0.0) -> bool:
	if tier.is_empty():
		return false
	return play(cue_for_plap(tier), at, 1.0, extra_db, pitch_for(strength))


## The act's impact fan-out: the plap, the bed layer and the slide at one bottom. The facade
## resolves the bed point and the soft-bed flag from its bound bed, so the call site passes only
## the stroke facts and the rump point the reactions computed.
func impact(tier: String, strength: float, rump: Vector3,
		gap: float, eps: float, plap := true) -> void:
	play_impact(tier, strength, rump, bed_point(rump), _bed_soft, gap, eps, plap)


## Called from the tracker's impact event: the deepest point of the stroke, so it also catches
## shallow strokes that never crossed a fixed depth. `tier` is empty below the firm impact speed,
## and `gap` is how far his skin still is from her coat in metres; `eps` is the contact epsilon.
## A stroke outside it gets no plap, while the bed fabric and the slide still play. `plap` is
## false for the oral segment, which keeps the slide and the bed but has no body slap.
func play_impact(tier: String, strength: float, rump: Vector3,
		bed_at: Vector3, soft_bed: bool, gap: float, eps: float, plap := true) -> void:
	var level := clampf(strength, 0.0, 1.0)
	var limit := maxf(eps, 0.0)
	if plap and not tier.is_empty() and gap <= limit:
		# A zero epsilon means true contact: a stroke that actually reaches zero is a full plap,
		# not the quiet edge of a division by a guard value.
		var contact := 1.0 if limit <= 0.0 and gap <= 0.0 \
			else 1.0 - clampf(gap / maxf(limit, 0.001), 0.0, 1.0)
		play_plap(tier, level, rump, plap_volume_db(level) + plap_contact_db(contact))
	if uses_bed(_impact_profile):
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


## The kiss cue at her snout, for the kiss that lands without the mouth contact.
func play_mouth_kiss() -> bool:
	return play("mouth_kiss", snout(), 0.55)


## True only on the frames that will fire the withdraw layer. The caller uses this before asking
## for the rump point, which walks the skeleton and should not run on every mouse move.
func crossed(before: float, after: float) -> bool:
	return before > WITHDRAW_DEPTH and after <= WITHDRAW_DEPTH


## Withdraw only. The impact layer is fired from `impact()` on the tracker's impact event.
func withdraw(before: float, after: float, strength: float, rump: Vector3) -> void:
	if not crossed(before, after):
		return
	var level := clampf(strength, 0.0, 1.0)
	play_slide("out", level, rump, -4.0)
	if uses_bed(_impact_profile):
		play_bed(level, bed_point(rump), _bed_soft)


## Her own generated vocal on a stroke, at most once per `VOCAL_COOLDOWN_S`. The director must be
## idle, or the stroke stays silent and the next one tries again.
func play_vocal() -> void:
	if _vocal_cooldown > 0.0:
		return
	var director := _director()
	if director == null or str(director.get("state")) != "idle" or not is_instance_valid(_pony):
		return
	var vocal: Variant = director.get("vocal")
	if not vocal is Node:
		return
	var vocal_node: Node = vocal
	if not vocal_node.has_method("play"):
		return
	prune_freed_vocal(vocal_node)
	if bool(vocal_node.call("play", _id, "m", _pony, VOCAL_DB)):
		_vocal_cooldown = VOCAL_COOLDOWN_S


func tick_vocal(delta: float) -> void:
	_vocal_cooldown = maxf(0.0, _vocal_cooldown - delta)


## The base game's vocal cache maps a pony id to an AudioStreamPlayer3D parented to her body.
## A body swap frees that body and leaves a freed instance in the cache; the game's typed read at
## `vocal_noises.gd:play()` then fails before its own validity guard. Clear only this act's stable
## id so the game can create the player on the presented body. Guarded for a changed cache.
func prune_freed_vocal(vocal: Node) -> void:
	if not is_instance_valid(vocal):
		return
	var players: Variant = vocal.get("_players")
	if not players is Dictionary:
		return
	if not (players as Dictionary).has(_id):
		return
	# An untyped read of a freed object normalizes to null; the game's typed read is what errors.
	# The cache never stores a legitimate null, so an existing null slot is stale and safe to drop.
	var cached: Variant = (players as Dictionary).get(_id)
	if cached == null or not is_instance_valid(cached):
		(players as Dictionary).erase(_id)


## The base game's soft kiss at her snout: the same cue a stock kiss plays. The oral turn owns its
## idle timer and the mouth shape.
func oral_kiss() -> void:
	if not is_instance_valid(_pony):
		return
	var boop: Variant = _pony.get("boop_node")
	if boop != null and boop.has_method("play_kiss"):
		boop.call("play_kiss", ORAL_KISS_DB, true)


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


static func cue_for_plap(tier: String) -> String:
	if tier.is_empty():
		return ""
	return "plap_" + tier


## Bed and fabric only belong to the bed profile. The standing pose and the internal standing_test
## carry `impact = "standing"` and play no bed/fabric.
static func uses_bed(profile: String) -> bool:
	return profile == "missionary"


static func tier_for(strength: float) -> String:
	return PREFERENCES.intensity_for(strength)


## Plap level follows the physical strength; the gate above already decided speed and contact.
static func plap_volume_db(strength: float) -> float:
	return lerpf(-10.0, 0.0, clampf(strength, 0.0, 1.0))


## A body slap that only just reaches her coat sits this many dB under a bottomed-out one.
## `contact` is 0 at the contact epsilon edge and 1 at the deepest point.
static func plap_contact_db(contact: float) -> float:
	return lerpf(-8.0, 0.0, clampf(contact, 0.0, 1.0))


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
