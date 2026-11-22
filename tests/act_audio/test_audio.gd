extends "res://mods/unfplap/tests/support/suite.gd"
## The world audio facade and its per-act handle: the process-lifetime cue pool, the base-game
## breath and squee, the Ponese mute, her own generated vocal and the act identity it binds.
## The pure cue table is covered by `test_act_audio.gd`.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/act_audio/test_audio.gd

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const AUDIO := preload("res://mods/unfplap/audio/api.gd")
const CATALOGUE := preload("res://mods/unfplap/audio/cues.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const SOUND := preload("res://mods/unfplap/audio/sound.gd")
const VOICE := preload("res://mods/unfplap/shared/voice_status.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")



class FakePony extends Node3D:
	var head: Variant = null
	var boop_node: Variant = null


class FakeHead extends Node3D:
	var voice: Variant = null


class FakeBoop extends Node:
	var kisses := 0
	var volumes: Array[float] = []
	var softs: Array[bool] = []

	func nose_world() -> Vector3:
		return Vector3(0.5, 1.4, 0.25)

	func play_kiss(volume_db := -22.0, soft := false) -> void:
		kisses += 1
		volumes.append(volume_db)
		softs.append(soft)


class FakeTts extends Node:
	var voice_mode := "auto"

	func has_server() -> bool:
		return true


class FakeVocal extends Node:
	var _players: Dictionary = {}
	var plays := 0

	func play(_id: String, _kind: String, _pony: Variant, _db: float) -> bool:
		plays += 1
		return true


class FakeDirector extends Node:
	var state := "idle"
	var characters: Dictionary = {}
	var tts: Node = null
	var vocal: Node = null


func run() -> void:
	var before := SETTINGS.mute_ponese_audio.get_bool()
	SETTINGS.mute_ponese_audio.set_bool(false)
	var service: Node = AUDIO.new()
	root.add_child(service)
	var audio: AUDIO.ActAudio = AUDIO.ActAudio.new(service)
	var pool: Node = service.get("_pool")
	var sound: Node = service.get("_sound")
	check(is_instance_valid(pool), "the world audio service builds its cue pool")
	check(is_instance_valid(sound), "the world audio service builds its sound child")
	check(sound.get_parent() == service, "the sound child rides the audio service")
	check((pool.get("_pools") as Dictionary).has("plap_firm"),
		"the foley layer is ready before the first act")
	var breath := sound.find_child("UnfplapBreath", true, false)
	check(breath != null, "the breath player is built once")
	check(sound.find_child("UnfplapClimax", true, false) != null,
		"the squee player is built once")

	check(SOUND.phase_for_state(ACT_STATE.State.ACTIVE) == "active", "the active act breathes")
	check(SOUND.phase_for_state(ACT_STATE.State.CLIMAX) == "climax",
		"the climax peaks the breath")
	check(SOUND.phase_for_state(ACT_STATE.State.AFTERGLOW) == "afterglow",
		"the afterglow fades the breath")
	check(SOUND.phase_for_state(ACT_STATE.State.POSING_IN).is_empty(),
		"the posing-in beat is silent")
	check(SOUND.phase_for_state(ACT_STATE.State.RESTORE).is_empty(),
		"the restore beat is silent")

	# The bound bed owns the fabric layer and its point: couch, sofa and cloth are soft.
	var pony := FakePony.new()
	var head := FakeHead.new()
	var voice := AudioStreamPlayer3D.new()
	voice.volume_db = -6.0
	head.voice = voice
	head.add_child(voice)
	pony.head = head
	pony.add_child(head)
	var boop := FakeBoop.new()
	pony.boop_node = boop
	pony.add_child(boop)
	root.add_child(pony)
	var couch := Node3D.new()
	couch.name = "Couch"
	root.add_child(couch)
	audio.begin_act(pony, "rarity", couch)
	check(audio.get("_bed_soft"), "a couch is a soft bed")
	check(audio.get("_impact_profile") == "missionary", "a bound bed selects the bed layer")
	check(audio._bed_point(Vector3.ONE).is_equal_approx(couch.global_position
		+ Vector3.UP * 0.35), "the bed point rides the bound bed")
	check(audio._snout().is_equal_approx(Vector3(0.5, 1.4, 0.25)),
		"the snout reads her own kiss point")
	var plain_boop := Node.new()
	pony.boop_node = plain_boop
	pony.add_child(plain_boop)
	check(audio._snout().is_equal_approx(pony.global_position + Vector3.UP * 1.0),
		"a boop without a nose point falls back to her head position")
	pony.boop_node = boop

	# The bound bed decides the fabric: a bed-less (standing) act plays none.
	var ready: Dictionary = pool.get("_ready_at")
	ready["fabric"] = 0.0
	audio.impact("rough", 0.9, Vector3.ZERO, 0.0, true)
	check(float(ready.get("fabric", 0.0)) > 0.0, "the bound soft bed plays the fabric layer")
	audio.rebind_body(pony, "rarity", null)
	check(audio.get("_impact_profile") == "", "a bed-less act has no bed profile")
	ready["fabric"] = 0.0
	audio.impact("rough", 0.9, Vector3.ZERO, 0.0, true)
	check(float(ready.get("fabric", 0.0)) == 0.0, "a standing act plays no bed fabric")
	audio.rebind_body(pony, "rarity", couch)

	# The body slap needs his skin to reach her coat; the slide is never gated.
	ready["plap_rough"] = 0.0
	audio.impact("rough", 0.7, Vector3.ZERO, 0.03, true)
	check(float(ready.get("plap_rough", 0.0)) == 0.0, "a stroke short of contact has no plap")
	ready["slide_in"] = 0.0
	audio.impact("rough", 0.7, Vector3.ZERO, 0.03, true)
	check(float(ready.get("slide_in", 0.0)) > 0.0,
		"a stroke short of contact keeps the slide")
	ready["plap_rough"] = 0.0
	audio.impact("rough", 0.7, Vector3.ZERO, 0.0, true)
	check(float(ready.get("plap_rough", 0.0)) > 0.0, "true contact plays the plap")
	ready["plap_rough"] = 0.0
	audio.impact("", 0.7, Vector3.ZERO, 0.0, true)
	check(float(ready.get("plap_rough", 0.0)) == 0.0, "a slow bottom emits no plap")
	ready["plap_rough"] = 0.0
	ready["slide_in"] = 0.0
	audio.impact("rough", 0.7, Vector3.ZERO, 0.0, false)
	check(float(ready.get("plap_rough", 0.0)) == 0.0, "an oral impact skips the plap")
	check(float(ready.get("slide_in", 0.0)) > 0.0, "an oral impact keeps the slide")

	check(audio.crossing_out(0.5, 0.1), "an outward crossing is a withdraw")
	check(not audio.crossing_out(0.1, 0.5), "an inward move is not a withdraw")
	ready["slide_out"] = 0.0
	audio.slide_out(0.5, 0.1, 0.6, Vector3.ZERO)
	check(float(ready.get("slide_out", 0.0)) > 0.0, "the outward slide fires")
	ready["mouth_kiss"] = 0.0
	audio.mouth_kiss()
	check(float(ready.get("mouth_kiss", 0.0)) > 0.0, "the mouth kiss plays at her snout")
	pony.boop_node = plain_boop
	audio.oral_kiss()
	check(boop.kisses == 0, "a boop without a kiss op makes the soft kiss a no-op")
	pony.boop_node = boop
	audio.oral_kiss()
	check(boop.kisses == 1, "the soft kiss plays one base-game kiss")
	check(boop.volumes.size() == 1
		and is_equal_approx(boop.volumes[0], CATALOGUE.ORAL_KISS_DB),
		"the soft kiss uses the stock soft volume")
	check(boop.softs.size() == 1 and bool(boop.softs[0]), "the soft kiss is the soft variant")

	audio.tick(0.1, ACT_STATE.State.ACTIVE, 2.0)
	audio.tick(0.1, ACT_STATE.State.POSING_IN, 0.0)
	audio.climax()
	audio.silence_breath()

	# Her own generated vocal: the director's idle vocal plays once per cooldown, and a stale
	# cache slot in the game's player map is dropped before the play so a body swap recovers.
	var director := FakeDirector.new()
	var tts := FakeTts.new()
	director.tts = tts
	director.characters = {"rarity": {"profile": {
		"voice_status": "Ponese; no approved voice bank", "tts_speaker_id": -1}}}
	var vocal := FakeVocal.new()
	vocal._players = {"rarity": null, "applejack": "kept"}
	director.vocal = vocal
	director.add_child(vocal)
	director.add_to_group("conversation_director")
	root.add_child(director)
	audio.rebind_body(pony, "rarity", null)
	audio.vocal()
	check(vocal.plays == 1, "a stroke plays her own vocal")
	audio.vocal()
	check(vocal.plays == 1, "the vocal cooldown holds the next stroke silent")
	audio.tick(CATALOGUE.VOCAL_COOLDOWN_S, ACT_STATE.State.ACTIVE, 0.0)
	audio.vocal()
	check(vocal.plays == 2, "the cooldown releases the next vocal")
	check(not (vocal._players as Dictionary).has("rarity"),
		"the stale vocal cache slot for this act is dropped")
	check((vocal._players as Dictionary).has("applejack"),
		"another pony's vocal cache slot is untouched")
	director.state = "speaking"
	audio.tick(CATALOGUE.VOCAL_COOLDOWN_S, ACT_STATE.State.ACTIVE, 0.0)
	audio.vocal()
	check(vocal.plays == 2, "a busy director keeps the stroke silent")
	var plain_vocal := Node.new()
	director.vocal = plain_vocal
	director.state = "idle"
	audio.tick(CATALOGUE.VOCAL_COOLDOWN_S, ACT_STATE.State.ACTIVE, 0.0)
	audio.vocal()
	check(vocal.plays == 2, "a vocal node without a play op keeps the stroke silent")
	plain_vocal.free()
	director.vocal = vocal

	# The Ponese mute is audio's own: a settings edit reaches the open act without an act call.
	voice.volume_db = -6.0
	SETTINGS.mute_ponese_audio.set_bool(true)
	SETTINGS.apply_live()
	check(is_equal_approx(voice.volume_db, -80.0),
		"muting Ponese silences the live voice player")
	check(VOICE.status_line(WORLD.director().voice_facts("rarity")).begins_with("voice "),
		"the debug line names the live voice routing")
	SETTINGS.mute_ponese_audio.set_bool(false)
	SETTINGS.apply_live()
	check(is_equal_approx(voice.volume_db, -6.0),
		"unmuting Ponese restores the voice player")

	# A generated character voice is not a Ponese voice and is left alone.
	director.characters = {"rarity": {"profile": {
		"voice_status": "character voice", "tts_speaker_id": 5}}}
	SETTINGS.mute_ponese_audio.set_bool(true)
	SETTINGS.apply_live()
	check(is_equal_approx(voice.volume_db, -6.0), "a generated-voice pony is not muted")
	SETTINGS.mute_ponese_audio.set_bool(false)
	SETTINGS.apply_live()

	# The game's TTS switch arrives through the accessor: the shipped autoload answering true
	# leaves the generated voice alone, and an absent autoload reads as TTS off.
	var game_settings: Node = root.get_node_or_null("Settings")
	check(GAME.tts_enabled(game_settings), "the shipped switch leaves the generated voice alone")
	if game_settings != null:
		root.remove_child(game_settings)
	check(not GAME.tts_enabled(null), "an absent settings autoload reads as TTS off")
	SETTINGS.mute_ponese_audio.set_bool(true)
	SETTINGS.apply_live()
	check(is_equal_approx(voice.volume_db, -80.0),
		"a missing TTS switch reads as TTS off, so the mute reaches the generated voice")
	SETTINGS.mute_ponese_audio.set_bool(false)
	SETTINGS.apply_live()
	check(is_equal_approx(voice.volume_db, -6.0), "the mute off gives the volume back")
	if game_settings != null:
		root.add_child(game_settings)

	# The act's end silences it and the next act reuses the same pool and players.
	var first_plap: AudioStreamPlayer3D = (pool.get("_pools") as Dictionary)["plap_firm"][0]
	audio.end_act()
	check(not (pool.get("_pools") as Dictionary).is_empty(),
		"the cue pool survives the act")
	audio.begin_act(pony, "rarity", couch)
	check((pool.get("_pools") as Dictionary)["plap_firm"][0] == first_plap,
		"a new act reuses the process pool")
	check(sound.find_child("UnfplapBreath", true, false) == breath,
		"a new act reuses the breath child")
	audio.end_act()

	SETTINGS.mute_ponese_audio.set_bool(before)
	SETTINGS.apply_live()
	service.shutdown()
	root.remove_child(director)
	director.free()
	root.remove_child(couch)
	couch.free()
	root.remove_child(pony)
	pony.free()
	root.remove_child(service)
	service.free()

	if failures == 0:
		print("AUDIO_PASS")
	finish()
