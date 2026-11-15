extends SceneTree
## The act audio facade: the pack foley layer plus the base-game breath/climax and the Ponese mute
## policy. The pure pack catalogue is covered by `test_act_audio.gd`.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/act_audio/test_audio.gd

const AUDIO := preload("res://mods/unfplap/audio/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

var failures := 0
var checks := 0


class FakePony extends Node3D:
	var head: Variant = null


class FakeHead extends Node3D:
	var voice: Variant = null


class FakeView extends RefCounted:
	var audio: Dictionary = {}


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
	check(not pools.has("climax_wet"), "there is no wet climax layer")
	var sound: Variant = audio.get("_sound")
	check(is_instance_valid(sound), "the base-game sound node is created")
	check(sound.get_parent() == audio, "the sound node rides the audio facade")
	check(audio.find_child("UnfplapBreath", true, false) != null,
		"the breath player is started")
	check(audio.find_child("UnfplapClimax", true, false) != null,
		"the squee player is started")

	audio.tick(0.1, "active", 2.0, Vector3.ZERO)
	audio.tick(0.1, "", 0.0, Vector3.ZERO)
	audio.climax(Vector3.ZERO)
	audio.call("stop_breath")

	# The body slap gates on contact and takes its tier from the impact speed.
	var ready: Dictionary = audio.get("_ready_at")
	audio.play_impact("", 0.9, Vector3.ZERO, Vector3.ZERO, false, 0.0, 0.02)
	check(float(ready.get("plap_firm", 0.0)) == 0.0, "a slow bottom stays silent")
	ready["plap_rough"] = 0.0
	audio.play_impact("rough", 0.9, Vector3.ZERO, Vector3.ZERO, false, 0.03, 0.02)
	check(float(ready.get("plap_rough", 0.0)) == 0.0,
		"a stroke 3 cm short is silent at a 2 cm contact gap")
	audio.play_impact("rough", 0.9, Vector3.ZERO, Vector3.ZERO, false, 0.0, 0.02)
	check(float(ready.get("plap_rough", 0.0)) > 0.0, "a bottomed-out rough stroke plaps")
	ready["plap_rough"] = 0.0
	audio.play_impact("rough", 0.9, Vector3.ZERO, Vector3.ZERO, false, 0.0, 0.0)
	check(float(ready.get("plap_rough", 0.0)) > 0.0,
		"true contact at a zero epsilon plays the plap")
	# The cached impact profile gates the soft-bed fabric: standing and standing_test play none.
	view.audio = {"impact": CATALOG.STANDING}
	audio.pose_changed(view)
	ready["fabric"] = 0.0
	audio.play_impact("rough", 0.9, Vector3.ZERO, Vector3.ZERO, true, 0.0, 0.02)
	check(float(ready.get("fabric", 0.0)) == 0.0, "the standing profile plays no bed fabric")
	view.audio = {"impact": CATALOG.MISSIONARY}
	audio.pose_changed(view)
	ready["fabric"] = 0.0
	audio.play_impact("rough", 0.9, Vector3.ZERO, Vector3.ZERO, true, 0.0, 0.02)
	check(float(ready.get("fabric", 0.0)) > 0.0, "the missionary profile plays soft-bed fabric")

	audio.end()
	check((audio.get("_pools") as Dictionary).is_empty(), "stopping the act clears every pool")
	check(not is_instance_valid(audio.get("_sound")), "stopping the act frees the sound node")

	# The Ponese mute keeps the generated line but silences the voice player for the act.
	var pony := FakePony.new()
	var head := FakeHead.new()
	var voice := AudioStreamPlayer3D.new()
	voice.volume_db = -6.0
	head.voice = voice
	head.add_child(voice)
	pony.head = head
	pony.add_child(head)
	root.add_child(pony)
	audio.call("apply_voice_policy", pony, "rarity", true, {"effective_ponese": true})
	check(audio.call("voice_text_only"), "a Ponese act with the mute owns the text-only state")
	check(is_equal_approx(voice.volume_db, -80.0), "the Ponese voice player is silenced")
	audio.call("restore_voice_policy")
	check(is_equal_approx(voice.volume_db, -6.0), "the saved voice volume comes back")
	check(not audio.call("voice_text_only"), "the restore drops the text-only state")
	audio.call("apply_voice_policy", pony, "rarity", false, {"effective_ponese": true})
	check(not audio.call("voice_text_only"), "the mute off leaves the voice alone")
	check(is_equal_approx(voice.volume_db, -6.0), "the unmuted voice keeps its volume")
	audio.call("apply_voice_policy", pony, "rarity", true, {"effective_ponese": false})
	check(not audio.call("voice_text_only"), "a generated-voice pony is not muted")

	audio.begin()
	pools = audio.get("_pools")
	check(pools.has("plap_firm"), "a new act rebuilds the foley layer")
	check(not pools.has("climax_wet"), "a new act still has no wet layer")
	audio.end()

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
	var runtime: Node = RUNTIME.new()
	root.add_child(runtime)
	runtime.state = 2 # ACTIVE
	runtime.pose_id = CATALOG.STANDING
	var before := SETTINGS.mute_ponese_audio.get_bool()
	SETTINGS.mute_ponese_audio.set_bool(false)
	runtime.call("apply_live_settings")
	var voice_audio: Node = runtime.call("_audio_service")
	check(is_instance_valid(voice_audio) and not bool(voice_audio.call("voice_text_only")),
		"the act opens with the Ponese voice live")
	SETTINGS.mute_ponese_audio.set_bool(true)
	runtime.call("apply_live_settings")
	check(is_instance_valid(voice_audio) and bool(voice_audio.call("voice_text_only")),
		"muting Ponese mid-act reaches the voice policy")
	SETTINGS.mute_ponese_audio.set_bool(false)
	runtime.call("apply_live_settings")
	check(is_instance_valid(voice_audio) and not bool(voice_audio.call("voice_text_only")),
		"unmuting Ponese mid-act restores the voice")
	SETTINGS.mute_ponese_audio.set_bool(before)
	root.remove_child(runtime)
	runtime.free()
