extends "res://mods/unfplap/shared/service.gd"
## Service: audio
## Scope: world
## Contract: docs/audio.md
## The act's sound: the world playback pool, the base-game breath and her voice policy.

const CATALOGUE := preload("res://mods/unfplap/audio/cues.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const POOL := preload("res://mods/unfplap/audio/pool.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const SOUND := preload("res://mods/unfplap/audio/sound.gd")
const VOICE := preload("res://mods/unfplap/shared/voice_status.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const SELF := preload("res://mods/unfplap/audio/api.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## The process-lifetime cue players and the base-game sound child.
var _pool: POOL = null
var _sound: SOUND = null
## The live Ponese mute the open handles receive on every change.
var _muted := false
## The handles a running act opened; `end_act()` and the world close remove them.
var _handles: Array[ActAudio] = []


func _ready() -> void:
	_pool = POOL.new()
	_pool.name = "UnfplapCuePool"
	add_child(_pool)
	_pool.open()
	_sound = SOUND.new()
	_sound.name = "UnfplapActSound"
	add_child(_sound)
	_sound.build()
	_muted = SETTINGS.mute_ponese_audio.get_bool()
	CHANGE.on_changed(Callable(self, "_on_settings_changed"))


func on_world_closed() -> void:
	_handles.clear()
	if is_instance_valid(_pool):
		_pool.silence()
	if is_instance_valid(_sound):
		_sound.silence()


func shutdown() -> void:
	CHANGE.off_changed(Callable(self, "_on_settings_changed"))
	for handle: ActAudio in _handles.duplicate():
		handle.end_act()
	_handles.clear()
	if is_instance_valid(_pool):
		_pool.stop()
	if is_instance_valid(_sound):
		_sound.stop()


## The settings edit reaches every open act without an act call: a changed mute restores the
## saved voice volume and applies the new policy.
func _on_settings_changed() -> void:
	var want := SETTINGS.mute_ponese_audio.get_bool()
	if want == _muted:
		return
	_muted = want
	for handle: ActAudio in _handles.duplicate():
		handle._on_voice_setting()


func _director() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("conversation_director")


## The per-act handle the act modules call: her cues, her breath and the Ponese mute. It no-ops
## without the world service, which is a suite's construction.
class ActAudio extends RefCounted:
	var _world: SELF = null
	var _pony: Node3D = null
	var _id := ""
	var _bed: Node3D = null
	var _bed_soft := false
	## The bound bed selects the bed layer; the stroke event will carry the pose profile later.
	var _impact_profile := ""
	## The generated-vocal cooldown runs on rendered time: a paused tree freezes it with the act.
	var _vocal_cooldown := 0.0
	var _voice_player: AudioStreamPlayer3D = null
	var _voice_volume_saved := 0.0
	var _open := false

	func _init(world: SELF = null) -> void:
		_world = world

	## Open the act's sound on this body and bed. The pool and the breath players already exist.
	func begin_act(body: Node, id: String, bed: Node3D) -> void:
		if _world == null or not is_instance_valid(_world._pool) \
				or not is_instance_valid(_world._sound):
			return
		_bind(body, id, bed)
		_open = true
		if not _world._handles.has(self):
			_world._handles.append(self)
		_world._pool.open()
		_world._sound.reset_act()
		_apply_voice()

	## End the act's sound and give her voice back. The pool and the sound child stay for the next act.
	func end_act() -> void:
		_restore_voice()
		_open = false
		_vocal_cooldown = 0.0
		_bind(null, "", null)
		if _world == null:
			return
		_world._handles.erase(self)
		_world._pool.silence()
		_world._sound.silence()

	## The presented body changed: the snout, the bed point and the vocal id follow it, and the
	## Ponese mute applies to the new body's own voice player.
	func rebind_body(body: Node, id: String, bed: Node3D) -> void:
		if _world == null:
			return
		_bind(body, id, bed)
		_apply_voice()

	## One rendered frame: the vocal cooldown and the breath loop follow the act state and rate.
	func tick(delta: float, state: int, rate: float) -> void:
		if not _open or _world == null:
			return
		_vocal_cooldown = maxf(0.0, _vocal_cooldown - delta)
		_world._sound.breath_tick(delta, SOUND.phase_for_state(state), rate, _snout())

	func impact(tier: String, strength: float, rump: Vector3, gap: float,
			body_slap: bool) -> void:
		if not _open or _world == null:
			return
		var level := clampf(strength, 0.0, 1.0)
		var limit := CATALOGUE.CONTACT_GAP_M
		if body_slap and not tier.is_empty() and gap <= limit:
			var contact := 1.0 if limit <= 0.0 and gap <= 0.0 \
				else 1.0 - clampf(gap / maxf(limit, 0.001), 0.0, 1.0)
			_world._pool.play(CATALOGUE.cue_for_plap(tier), rump, 1.0,
				CATALOGUE.plap_volume_db(level) + CATALOGUE.plap_contact_db(contact),
				CATALOGUE.pitch_for(level))
		if CATALOGUE.uses_bed(_impact_profile):
			_play_bed(level, _bed_point(rump))
		_world._pool.play("slide_in", rump, level, -12.0)

	## True only on the frames that will fire the outward slide.
	func crossing_out(before: float, now: float) -> bool:
		return before > CATALOGUE.WITHDRAW_DEPTH and now <= CATALOGUE.WITHDRAW_DEPTH

	## The outward slide. The caller already asked `crossing_out()` and owns the rump read.
	func slide_out(before: float, now: float, strength: float, rump: Vector3) -> void:
		if not _open or _world == null or not crossing_out(before, now):
			return
		var level := clampf(strength, 0.0, 1.0)
		_world._pool.play("slide_out", rump, level, -4.0)
		if CATALOGUE.uses_bed(_impact_profile):
			_play_bed(level, _bed_point(rump))

	## Her own generated vocal on a stroke, at most once per cooldown. A busy director stays silent.
	func vocal() -> void:
		if not _open or _world == null or _vocal_cooldown > 0.0:
			return
		var director := _world._director()
		if director == null or WORLD.director().speaking() or not is_instance_valid(_pony):
			return
		var vocal_node: Variant = director.get("vocal")
		if not vocal_node is Node:
			return
		_prune_freed_vocal(vocal_node)
		if WORLD.director().play_vocal(vocal_node, _id, "m", _pony, CATALOGUE.VOCAL_DB):
			_vocal_cooldown = CATALOGUE.VOCAL_COOLDOWN_S

	## The base game's soft kiss at her snout, for the oral turn's idle timer.
	func oral_kiss() -> void:
		if not _open or not is_instance_valid(_pony):
			return
		WORLD.director().play_kiss(WORLD.pony(_pony).boop(), CATALOGUE.ORAL_KISS_DB, true)

	func mouth_kiss() -> void:
		if not _open or _world == null:
			return
		_world._pool.play("mouth_kiss", _snout(), 0.55)

	## The base-game squee at her snout.
	func climax() -> void:
		if not _open or _world == null:
			return
		_world._sound.play_climax(_snout())

	func silence_breath() -> void:
		if _world != null:
			_world._sound.stop_breath()

	func _on_voice_setting() -> void:
		if _open:
			_apply_voice()

	func _bind(body: Node, id: String, bed: Node3D) -> void:
		_pony = body as Node3D
		_id = id
		_bed = bed if is_instance_valid(bed) else null
		_bed_soft = is_instance_valid(_bed) and CATALOGUE.soft_surface(str(_bed.name).to_lower())
		_impact_profile = "missionary" if is_instance_valid(_bed) else ""

	func _snout() -> Vector3:
		if not is_instance_valid(_pony):
			return Vector3.ZERO
		var view := WORLD.pony(_pony)
		var boop := view.boop()
		if boop != null:
			var point := view.nose_world()
			if point.is_finite():
				return point
		return _pony.global_position + Vector3.UP * 1.0

	func _bed_point(rump: Vector3) -> Vector3:
		if is_instance_valid(_bed):
			return _bed.global_position + Vector3.UP * 0.35
		return rump

	func _play_bed(level: float, at: Vector3) -> void:
		if _bed_soft:
			_world._pool.play("fabric", at, level)

	## `mute_ponese_audio`: keep the generated line and text HUD, but silence the Ponese audio for
	## this act. A generated-voice pony is left alone.
	func _apply_voice() -> void:
		_restore_voice()
		if not _open or _world == null or not is_instance_valid(_pony) or not _world._muted:
			return
		var info: Dictionary = VOICE.classify(WORLD.director().voice_facts(_id, SETTINGS.tts_enabled()))
		if not bool(info.get("effective_ponese", false)):
			return
		_voice_player = _find_voice_player(_pony)
		if not is_instance_valid(_voice_player):
			LOG.debug("voice text-only: no voice player pony=%s", [_id])
			return
		_voice_volume_saved = _voice_player.volume_db
		_voice_player.volume_db = -80.0
		LOG.debug("voice text-only pony=%s %s", [_id, VOICE.describe(info)])

	func _restore_voice() -> void:
		if is_instance_valid(_voice_player):
			_voice_player.volume_db = _voice_volume_saved
		_voice_player = null
		_voice_volume_saved = 0.0

	func _find_voice_player(pony_node: Node3D) -> AudioStreamPlayer3D:
		if not is_instance_valid(pony_node):
			return null
		var head: Variant = pony_node.get("head")
		var voice: Variant = head.get("voice") if head != null else null
		if voice is AudioStreamPlayer3D:
			return voice
		var found: Variant = pony_node.find_child("Voice", true, false)
		return found as AudioStreamPlayer3D if found is AudioStreamPlayer3D else null

	## A body swap leaves a freed player in the game's vocal cache; drop only this id so the typed
	## read at `play()` cannot error. Guarded for a changed cache.
	func _prune_freed_vocal(vocal: Node) -> void:
		if not is_instance_valid(vocal):
			return
		var players: Variant = vocal.get("_players")
		if not players is Dictionary:
			return
		if not (players as Dictionary).has(_id):
			return
		# An untyped read of a freed object normalizes to null; the game's typed read is what errors.
		var cached: Variant = (players as Dictionary).get(_id)
		if cached == null or not is_instance_valid(cached):
			(players as Dictionary).erase(_id)
