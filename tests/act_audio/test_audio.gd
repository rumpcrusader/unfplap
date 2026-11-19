extends SceneTree
## The act audio facade: the pack foley layer plus the base-game breath/climax, the Ponese mute
## policy, her own generated vocal and the act identity it binds. The pure pack catalogue is
## covered by `test_act_audio.gd`.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/act_audio/test_audio.gd

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const AUDIO := preload("res://mods/unfplap/audio/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

var failures := 0
var checks := 0


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


class FakeView extends RefCounted:
	var audio: Dictionary = {}


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


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var audio: Node = AUDIO.new()
	root.add_child(audio)

	audio.begin()
	var view := FakeView.new()
	view.audio = {"impact": CATALOG.MISSIONARY}
	audio.pose_changed(view)
	check(audio.get("_impact_profile") == "missionary",
		"the pose hook caches the bed impact profile")
	var pools: Dictionary = audio.get("_pools")
	check(pools.has("plap_firm"), "the foley layer opens with the act")
	var sound: Variant = audio.get("_sound")
	check(is_instance_valid(sound), "the base-game sound node is created")
	check(sound.get_parent() == audio, "the sound node rides the audio facade")
	check(audio.find_child("UnfplapBreath", true, false) != null,
		"the breath player is started")
	check(audio.find_child("UnfplapClimax", true, false) != null,
		"the squee player is started")

	check(AUDIO.phase_for_state(ACT_STATE.State.ACTIVE) == "active",
		"the active act breathes")
	check(AUDIO.phase_for_state(ACT_STATE.State.CLIMAX) == "climax",
		"the climax peaks the breath")
	check(AUDIO.phase_for_state(ACT_STATE.State.AFTERGLOW) == "afterglow",
		"the afterglow fades the breath")
	check(AUDIO.phase_for_state(ACT_STATE.State.POSING_IN).is_empty(),
		"the posing-in beat is silent")
	check(AUDIO.phase_for_state(ACT_STATE.State.RESTORE).is_empty(),
		"the restore beat is silent")

	audio.tick(0.1, "active", 2.0)
	audio.tick(0.1, "", 0.0)
	audio.climax()

	# The bound bed owns the fabric layer and its point: couch, sofa and cloth are soft.
	var pony := FakePony.new()
	var head := FakeHead.new()
	var voice := AudioStreamPlayer3D.new()
	voice.volume_db = -6.0
	head.voice = voice
	head.add_child(voice)
	pony.head = head
	var boop := FakeBoop.new()
	pony.boop_node = boop
	pony.add_child(boop)
	root.add_child(pony)
	var couch := Node3D.new()
	couch.name = "Couch"
	root.add_child(couch)
	audio.bind(pony, "rarity", couch)
	check(audio.bed_soft(), "a couch is a soft bed")
	check(audio.bed_point(Vector3.ONE).is_equal_approx(couch.global_position
		+ Vector3.UP * 0.35), "the bed point rides the bound bed")
	check(audio.snout().is_equal_approx(Vector3(0.5, 1.4, 0.25)),
		"the snout reads her own kiss point")

	# The cached impact profile gates the soft-bed fabric: standing and standing_test play none.
	var ready: Dictionary = audio.get("_ready_at")
	view.audio = {"impact": CATALOG.STANDING}
	audio.pose_changed(view)
	ready["fabric"] = 0.0
	audio.impact("rough", 0.9, Vector3.ZERO, 0.0, 0.02)
	check(float(ready.get("fabric", 0.0)) == 0.0, "the standing profile plays no bed fabric")
	view.audio = {"impact": CATALOG.MISSIONARY}
	audio.pose_changed(view)
	ready["fabric"] = 0.0
	audio.impact("rough", 0.9, Vector3.ZERO, 0.0, 0.02)
	check(float(ready.get("fabric", 0.0)) > 0.0, "the missionary profile plays soft-bed fabric")
	audio.bind(pony, "rarity", null)
	ready["fabric"] = 0.0
	audio.impact("rough", 0.9, Vector3.ZERO, 0.0, 0.02)
	check(float(ready.get("fabric", 0.0)) == 0.0, "a wood bed has no fabric")

	check(audio.crossed(0.5, 0.1), "an outward crossing is a withdraw")
	ready["slide_out"] = 0.0
	audio.withdraw(0.5, 0.1, 0.6, Vector3.ZERO)
	check(float(ready.get("slide_out", 0.0)) > 0.0, "the withdraw slide fires once")
	check(audio.play_mouth_kiss(), "the mouth kiss plays at her snout")
	audio.oral_kiss()
	check(boop.kisses == 1, "the soft kiss plays one base-game kiss")
	check(boop.volumes.size() == 1 and is_equal_approx(boop.volumes[0], AUDIO.ORAL_KISS_DB),
		"the soft kiss uses the stock soft volume")
	check(boop.softs.size() == 1 and bool(boop.softs[0]), "the soft kiss is the soft variant")

	audio.end()
	check((audio.get("_pools") as Dictionary).is_empty(), "stopping the act clears every pool")
	check(not is_instance_valid(audio.get("_sound")), "stopping the act frees the sound node")

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
	audio.bind(pony, "rarity", null)
	audio.begin()
	audio.play_vocal()
	check(vocal.plays == 1, "a stroke plays her own vocal")
	audio.play_vocal()
	check(vocal.plays == 1, "the vocal cooldown holds the next stroke silent")
	audio.tick_vocal(AUDIO.VOCAL_COOLDOWN_S)
	audio.play_vocal()
	check(vocal.plays == 2, "the cooldown releases the next vocal")
	check(not (vocal._players as Dictionary).has("rarity"),
		"the stale vocal cache slot for this act is dropped")
	check((vocal._players as Dictionary).has("applejack"),
		"another pony's vocal cache slot is untouched")
	director.state = "speaking"
	audio.tick_vocal(AUDIO.VOCAL_COOLDOWN_S)
	audio.play_vocal()
	check(vocal.plays == 2, "a busy director keeps the stroke silent")
	director.state = "idle"

	# The Ponese mute keeps the generated line but silences the voice player for the act.
	audio.apply_voice_policy(true, pony, "rarity")
	check(audio.voice_text_only(), "a Ponese act with the mute owns the text-only state")
	check(is_equal_approx(voice.volume_db, -80.0), "the Ponese voice player is silenced")
	check(audio.voice_status_line("rarity").begins_with("voice "),
		"the debug read describes the routing")
	audio.restore_voice_policy()
	check(is_equal_approx(voice.volume_db, -6.0), "the saved voice volume comes back")
	check(not audio.voice_text_only(), "the restore drops the text-only state")
	audio.apply_voice_policy(false, pony, "rarity")
	check(not audio.voice_text_only(), "the mute off leaves the voice alone")
	check(is_equal_approx(voice.volume_db, -6.0), "the unmuted voice keeps its volume")

	# A generated character voice is not a Ponese voice and is left alone.
	director.characters = {"rarity": {"profile": {
		"voice_status": "character voice", "tts_speaker_id": 5}}}
	audio.apply_voice_policy(true, pony, "rarity")
	check(not audio.voice_text_only(), "a generated-voice pony is not muted")
	check(is_equal_approx(voice.volume_db, -6.0), "a generated voice keeps its volume")

	audio.begin()
	pools = audio.get("_pools")
	check(pools.has("plap_firm"), "a new act rebuilds the foley layer")
	audio.end()

	root.remove_child(director)
	director.free()
	root.remove_child(couch)
	couch.free()
	root.remove_child(pony)
	pony.free()
	root.remove_child(audio)
	audio.free()

	_check_live_mute()

	print("AUDIO_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("AUDIO_PASS")
	quit(0 if failures == 0 else 1)


## A live Ponese mute edit has to reach the voice policy during an act. `apply_live_settings()`
## reads the pre-edit mute before it snapshots the new features; a snapshot-first order makes the
## comparison always equal and the edit never lands.
func _check_live_mute() -> void:
	var pony := FakePony.new()
	var head := FakeHead.new()
	var voice := AudioStreamPlayer3D.new()
	voice.volume_db = -8.0
	head.voice = voice
	head.add_child(voice)
	pony.head = head
	pony.add_child(head)
	root.add_child(pony)
	var runtime: Node = RUNTIME.new()
	root.add_child(runtime)
	runtime.pony = pony
	runtime._id = "rarity"
	runtime._act.pony_id = "rarity"
	runtime._set_state(2) # ACTIVE
	runtime._act.pose_id = CATALOG.STANDING
	var before := SETTINGS.mute_ponese_audio.get_bool()
	SETTINGS.mute_ponese_audio.set_bool(false)
	runtime.call("apply_live_settings")
	var voice_audio: Node = runtime._audio.service()
	check(is_instance_valid(voice_audio) and not bool(voice_audio.call("voice_text_only")),
		"the act opens with the Ponese voice live")
	SETTINGS.mute_ponese_audio.set_bool(true)
	runtime.call("apply_live_settings")
	check(is_instance_valid(voice_audio) and bool(voice_audio.call("voice_text_only")),
		"muting Ponese mid-act reaches the voice policy")
	check(is_equal_approx(voice.volume_db, -80.0), "the live mute silences the voice player")
	SETTINGS.mute_ponese_audio.set_bool(false)
	runtime.call("apply_live_settings")
	check(is_instance_valid(voice_audio) and not bool(voice_audio.call("voice_text_only")),
		"unmuting Ponese mid-act restores the voice")
	check(is_equal_approx(voice.volume_db, -8.0), "the live unmute gives the volume back")
	SETTINGS.mute_ponese_audio.set_bool(before)
	root.remove_child(runtime)
	runtime.free()
	root.remove_child(pony)
	pony.free()
