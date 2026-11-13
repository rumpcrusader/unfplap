extends SceneTree
## Pure/unit checks for the act audio facade and its pack cue table.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/act_audio/test_act_audio.gd

const ACT := preload("res://mods/unfplap/audio/service.gd")
const CATALOGUE := preload("res://mods/unfplap/audio/cues.gd")
const SMACK := preload("res://mods/unfplap/audio/smack_cues.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const HANDS := preload("res://mods/unfplap/hands/service.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const SMACK_CTL := preload("res://mods/unfplap/hands/smack.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	for value: float in [0.0, 0.1, 0.33, 0.5, 0.66, 0.9, 1.0]:
		check(ACT.tier_for(value) == PREFERENCES.intensity_for(value),
			"tier matches preferences at %.2f" % value)
	check(ACT.cue_for_plap("") == "", "no impact tier has no plap cue")
	check(ACT.cue_for_plap("firm") == "plap_firm", "firm cue")
	check(ACT.cue_for_plap("rough") == "plap_rough", "rough cue")
	check(ACT.uses_bed(CATALOG.MISSIONARY), "missionary uses bed cues")
	check(not ACT.uses_bed(CATALOG.STANDING), "standing skips bed cues")
	check(ACT.pitch_for(0.0) < ACT.pitch_for(1.0), "pitch rises with strength")
	check(ACT.pitch_for(0.0) >= 0.9 and ACT.pitch_for(1.0) <= 1.1, "pitch stays bounded")
	check(ACT.gain_db(0.0) < ACT.gain_db(0.5) and ACT.gain_db(0.5) < ACT.gain_db(1.0),
		"gain rises with strength")
	check(near(ACT.gain_db(0.0), -10.0), "soft gain floor")
	check(near(ACT.gain_db(1.0), 0.0), "full-strength gain")
	check(near(ACT.plap_volume_db(0.0), -10.0), "soft plap floor")
	check(ACT.plap_volume_db(0.2) < ACT.plap_volume_db(0.5), "plap volume rises with strength")
	check(near(ACT.plap_volume_db(1.0), 0.0), "full-strength plap volume")
	check(near(ACT.plap_contact_db(0.0), -8.0), "the contact edge is the quiet end")
	check(near(ACT.plap_contact_db(1.0), 0.0), "full body contact is the loud end")
	check(ACT.plap_contact_db(0.5) > -8.0 and ACT.plap_contact_db(0.5) < 0.0,
		"a partial body contact fades in")

	check(ACT.next_index(1, 0, 0) == 0, "single variant index")
	for last: int in range(4):
		for roll: int in range(4):
			var picked := ACT.next_index(4, last, roll)
			check(picked >= 0 and picked < 4, "variant index in range")
			check(picked != last or last < 0, "variant never repeats the previous index")
	check(ACT.next_index(4, 2, 2) == 3, "repeat rolls forward")

	var expected := {
		"plap_firm": 7, "plap_rough": 7,
		"slide_in": 6, "slide_out": 6,
		"fabric": 8, "mouth_kiss": 8, "climax_wet": 4,
	}
	check(CATALOGUE.CUES.size() == expected.size(), "cue count")
	for cue: String in expected:
		var spec: Variant = CATALOGUE.CUES.get(cue, {})
		check(spec is Dictionary, "cue exists: " + cue)
		if not spec is Dictionary:
			continue
		var streams: Array = (spec as Dictionary).get("streams", [])
		check(streams.size() == int(expected[cue]), "variant count: " + cue)
		for stream: Variant in streams:
			check(stream is AudioStream, "stream type: " + cue)
			if stream is AudioStream:
				check((stream as AudioStream).get_length() > 0.02, "stream length: " + cue)

	var act: Node = ACT.new()
	act.set_enabled(false)
	check(not act.climax_enabled(), "the optional layer is off")
	var pools: Dictionary = act.get("_pools")
	check(pools.has("plap_firm"), "foley pool is always built")
	check(not pools.has("climax_wet"), "wet pool not built")

	act.set_enabled(true)
	pools = act.get("_pools")
	check(act.climax_enabled(), "the wet layer is on")
	check(pools.has("plap_firm"), "foley pool stays built")
	check(pools.has("climax_wet"), "wet pool built after the switch")
	act.set_enabled(false)
	check(not (act.get("_pools") as Dictionary).has("climax_wet"),
		"a live settings edit clears the wet layer")

	act.set_enabled(false)
	check(not (act.get("_pools") as Dictionary).is_empty(),
		"foley stays after the optional layer clears")

	var parent := Node3D.new()
	root.add_child(parent)
	parent.add_child(act)
	act.set_enabled(false)
	# A slow bottom that touches still stays silent: the tier is the impact speed.
	act.play_impact(CATALOG.MISSIONARY, "", 0.9, Vector3.ZERO, Vector3.ZERO, false, 0.0, 0.02)
	var ready_at: Dictionary = act.get("_ready_at")
	check(float(ready_at.get("plap_firm", 0.0)) == 0.0, "a slow bottom emits no plap")
	check(float(ready_at.get("plap_rough", 0.0)) == 0.0, "a slow bottom emits no rough plap")
	check(float(ready_at.get("slide_in", 0.0)) > 0.0, "a slow impact keeps the slide")
	check(float(ready_at.get("fabric", 0.0)) == 0.0, "a wood bed has no bed cue")
	check(not act.play_plap("", 0.2, Vector3.ZERO), "a plap call without a tier is refused")
	act.set_enabled(false)
	ready_at = act.get("_ready_at")
	ready_at["plap_rough"] = 0.0
	ready_at["slide_in"] = 0.0
	act.play_impact(CATALOG.MISSIONARY, "rough", 0.7, Vector3.ZERO, Vector3.ZERO, false, 0.0, 0.02)
	check(float(ready_at.get("plap_rough", 0.0)) > 0.0, "a bottomed-out rough impact plays the plap")
	check(float(ready_at.get("slide_in", 0.0)) > 0.0, "a rough impact keeps the slide")
	check(act.play_bed(0.7, Vector3.ZERO, true), "soft-bed fabric plays")
	check(not act.play_bed(0.7, Vector3.ZERO, false), "a wood bed has no creak")
	# The body slap needs his skin to reach her coat: 3 cm short of a 2 cm Contact gap is silent,
	# while a stroke at the epsilon edge still plays. The slide and the bed are never gated.
	ready_at["plap_rough"] = 0.0
	ready_at["slide_in"] = 0.0
	act.play_impact(CATALOG.MISSIONARY, "rough", 0.7, Vector3.ZERO, Vector3.ZERO, false, 0.03, 0.02)
	check(float(ready_at.get("plap_rough", 0.0)) == 0.0,
		"a stroke past the contact gap has no plap")
	check(float(ready_at.get("slide_in", 0.0)) > 0.0,
		"a stroke past the contact gap keeps the slide")
	ready_at["plap_rough"] = 0.0
	act.play_impact(CATALOG.MISSIONARY, "rough", 0.7, Vector3.ZERO, Vector3.ZERO, false, 0.02, 0.02)
	check(float(ready_at.get("plap_rough", 0.0)) > 0.0,
		"a stroke at the contact edge plays the plap")
	check(act.play_plap("firm", 0.7, Vector3.ZERO), "foley plap starts a player")
	check(not act.play_plap("firm", 0.7, Vector3.ZERO),
		"cooldown blocks an immediate second plap")
	check(act.play_mouth_kiss(Vector3.ZERO), "mouth kiss plays")
	check(not CATALOGUE.CUES.has("smack"), "flank smack stays out of the optional cue table")
	check(SMACK.PATHS.size() >= 2, "flank smack has multiple pack variants")
	for path: String in SMACK.PATHS:
		check(ResourceLoader.exists(path), "smack stream exists: " + path)
		var smack_stream: Resource = load(path)
		check(smack_stream is AudioStream, "smack stream type: " + path)
		if smack_stream is AudioStream:
			var seconds := (smack_stream as AudioStream).get_length()
			check(seconds > 0.05 and seconds < 1.0, "smack stream length: " + path)
	act.set_enabled(true)
	act.play_climax_wet(Vector3.ZERO)
	check(act.climax_enabled(), "the wet layer is accepted after a live toggle")
	ready_at = act.get("_ready_at")
	ready_at["plap_rough"] = 0.0
	check(act.play_plap("rough", 0.9, Vector3.ZERO),
		"foley plap stays on after a live toggle")
	act.stop()
	parent.remove_child(act)
	act.free()
	parent.free()

	# Runtime integration: the pack node is created for every act; the wet layer is optional.
	var runtime: Node = RUNTIME.new()
	runtime.pony = Node3D.new()
	runtime.bed = Node3D.new()
	runtime._features = {"act_climax": false}
	root.add_child(runtime)
	runtime._start_audio()
	check(runtime.has_node("UnfplapActAudio"), "foley starts the pack audio node")
	runtime._stop_audio()
	runtime._features = {"act_climax": true}
	runtime._start_audio()
	check(runtime.has_node("UnfplapActAudio"), "climax on keeps the pack audio node")
	runtime._stop_audio()
	root.remove_child(runtime)
	runtime.free()

	# The native FlankTouch player is the smack voice: the act swaps in a pack variant at
	# impact time and restores the stock stream, level and pitch at act end.
	var smack_pony := Node3D.new()
	root.add_child(smack_pony)
	var flank := Node3D.new()
	flank.name = "FlankTouch"
	smack_pony.add_child(flank)
	var smack_player := AudioStreamPlayer3D.new()
	smack_player.name = "sound"
	var stock_stream := AudioStreamWAV.new()
	smack_player.stream = stock_stream
	smack_player.volume_db = -10.0
	smack_player.pitch_scale = 1.2
	flank.add_child(smack_player)
	var smack_facts: RefCounted = ACT_FACTS.new()
	smack_facts.pony = smack_pony
	var hands: RefCounted = HANDS.new(smack_facts)
	hands.set("pony", smack_pony)
	hands.set("_flank", flank)
	var smack: RefCounted = hands.call("_smack_controller")
	smack.call("_install_sound")
	check(smack_player.stream != stock_stream and smack_player.stream is AudioStream,
		"the act installs a pack smack")
	check(near(smack_player.volume_db, SMACK_CTL.SMACK_VOLUME_DB), "pack smack uses its own level")
	check(smack_player.pitch_scale >= SMACK_CTL.SMACK_PITCH_MIN
		and smack_player.pitch_scale <= SMACK_CTL.SMACK_PITCH_MAX, "pack smack varies its pitch")
	smack.call("_restore_sound")
	check(smack_player.stream == stock_stream, "smack restore puts the stock stream back")
	check(near(smack_player.volume_db, -10.0) and near(smack_player.pitch_scale, 1.2),
		"smack restore puts the stock level and pitch back")
	hands = null
	root.remove_child(smack_pony)
	smack_pony.free()

	print("ACT_AUDIO_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
