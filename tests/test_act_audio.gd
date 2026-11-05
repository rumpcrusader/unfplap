extends SceneTree
## Pure/unit checks for the optional OpenNSFW act audio layer.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_act_audio.gd

const ACT := preload("res://mods/unfplap/act_audio.gd")
const CATALOGUE := preload("res://mods/unfplap/audio/act/catalogue.gd")
const SMACK := preload("res://mods/unfplap/audio/act/smack/catalogue.gd")
const PREFERENCES := preload("res://mods/unfplap/preferences.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const CAESS := preload("res://mods/unfplap/standing_caress.gd")
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
	check(ACT.cue_for_plap(CATALOG.MISSIONARY, "soft") == "",
		"soft has no plap cue")
	check(ACT.cue_for_plap(CATALOG.MISSIONARY, "rough") == "plap_rough",
		"missionary rough cue")
	check(ACT.cue_for_plap(CATALOG.STANDING, "firm") == "plap_standing",
		"standing uses its own plap pool")
	check(ACT.uses_bed(CATALOG.MISSIONARY), "missionary uses bed cues")
	check(not ACT.uses_bed(CATALOG.STANDING), "standing skips bed cues")
	check(ACT.pitch_for(0.0) < ACT.pitch_for(1.0), "pitch rises with strength")
	check(ACT.pitch_for(0.0) >= 0.9 and ACT.pitch_for(1.0) <= 1.1, "pitch stays bounded")
	check(ACT.gain_db(0.0) < ACT.gain_db(0.5) and ACT.gain_db(0.5) < ACT.gain_db(1.0),
		"gain rises with strength")
	check(near(ACT.gain_db(0.0), -10.0), "soft gain floor")
	check(near(ACT.gain_db(1.0), 0.0), "full-strength gain")
	check(ACT.plap_volume_db(0.2) == -80.0, "soft emits no plap")
	check(ACT.plap_volume_db(0.33) < ACT.plap_volume_db(0.5), "firm plap fades in")
	check(ACT.plap_volume_db(0.5) < ACT.plap_volume_db(PREFERENCES.FIRM_MAX - 0.01),
		"firm plap keeps rising")
	check(ACT.plap_volume_db(PREFERENCES.FIRM_MAX) == 0.0,
		"rough starts at full plap volume")
	check(ACT.plap_volume_db(PREFERENCES.FIRM_MAX - 0.01) < 0.0,
		"the top of firm is still below full plap volume")
	check(ACT.plap_volume_db(1.0) == 0.0, "rough stays at full plap volume")

	check(ACT.next_index(1, 0, 0) == 0, "single variant index")
	for last: int in range(4):
		for roll: int in range(4):
			var picked := ACT.next_index(4, last, roll)
			check(picked >= 0 and picked < 4, "variant index in range")
			check(picked != last or last < 0, "variant never repeats the previous index")
	check(ACT.next_index(4, 2, 2) == 3, "repeat rolls forward")

	var expected := {
		"plap_firm": 7, "plap_rough": 7, "plap_standing": 8,
		"slide_in": 6, "slide_out": 6,
		"fabric": 8, "mouth_kiss": 8, "climax_wet": 4,
		"climax_voice": 3,
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
	act.setup(false, false, false)
	check(not act.foley_enabled() and not act.vocals_enabled(), "both flags off")
	check((act.get("_pools") as Dictionary).is_empty(), "off/off allocates no players")

	act.setup(true, false, false)
	var pools: Dictionary = act.get("_pools")
	check(act.foley_enabled() and not act.vocals_enabled(), "foley only")
	check(pools.has("plap_firm"), "foley pool built")
	check(not pools.has("climax_voice"), "vocal pool not built")

	act.set_enabled(false, true, false)
	pools = act.get("_pools")
	check(not act.foley_enabled() and act.vocals_enabled(), "vocals only")
	check(not pools.has("plap_firm"), "foley pool cleared")
	check(pools.has("climax_voice"), "climax voice pool built after switch")
	check(not pools.has("climax_wet"), "wet climax stays off with vocals only")
	act.set_enabled(false, false, true)
	pools = act.get("_pools")
	check(act.climax_enabled() and pools.has("climax_wet"), "wet climax builds only from its own flag")
	act.set_enabled(false, true, true)

	act.set_enabled(false, false, false)
	check((act.get("_pools") as Dictionary).is_empty(), "both off clears every pool")

	var parent := Node3D.new()
	root.add_child(parent)
	parent.add_child(act)
	act.setup(true, false, false)
	act.play_impact(CATALOG.MISSIONARY, 0.2, Vector3.ZERO, Vector3.ZERO, false)
	var ready_at: Dictionary = act.get("_ready_at")
	check(float(ready_at.get("plap_firm", 0.0)) == 0.0, "soft impact emits no plap")
	check(float(ready_at.get("slide_in", 0.0)) > 0.0, "soft impact keeps the slide")
	check(float(ready_at.get("fabric", 0.0)) == 0.0, "a wood bed has no bed cue")
	check(not act.play_plap(CATALOG.MISSIONARY, "soft", 0.2, Vector3.ZERO),
		"soft plap call is refused")
	act.set_enabled(true, false, false)
	ready_at = act.get("_ready_at")
	ready_at["plap_rough"] = 0.0
	ready_at["slide_in"] = 0.0
	act.play_impact(CATALOG.MISSIONARY, 0.7, Vector3.ZERO, Vector3.ZERO, false)
	check(float(ready_at.get("plap_rough", 0.0)) > 0.0, "rough impact plays the plap")
	check(float(ready_at.get("slide_in", 0.0)) > 0.0, "rough impact keeps the slide")
	check(act.play_bed(0.7, Vector3.ZERO, true), "soft-bed fabric plays")
	check(not act.play_bed(0.7, Vector3.ZERO, false), "a wood bed has no creak")
	check(act.play_plap(CATALOG.MISSIONARY, "firm", 0.7, Vector3.ZERO),
		"foley plap starts a player")
	check(not act.play_plap(CATALOG.MISSIONARY, "firm", 0.7, Vector3.ZERO),
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
	act.set_enabled(false, true, false)
	act.play_climax_voice(Vector3.ZERO)
	check(act.vocals_enabled(), "climax voice accepted after a live toggle")
	check(not act.play_plap(CATALOG.STANDING, "rough", 0.9, Vector3.ZERO),
		"foley plap is off after a live toggle")
	act.stop()
	parent.remove_child(act)
	act.free()
	parent.free()

	# Runtime integration: both flags off leaves the pack node out entirely; either flag on
	# creates it. _start_audio() also builds the existing fallback players.
	var runtime: Node = RUNTIME.new()
	runtime.pony = Node3D.new()
	runtime.bed = Node3D.new()
	runtime._features = {"act_foley": false, "act_vocals": false, "act_climax": false}
	root.add_child(runtime)
	runtime._start_audio()
	check(not runtime.has_node("UnfplapActAudio"), "off/off starts no pack audio node")
	runtime._stop_audio()
	runtime._features = {"act_foley": true, "act_vocals": false, "act_climax": false}
	runtime._start_audio()
	check(runtime.has_node("UnfplapActAudio"), "foley on starts the pack audio node")
	runtime._stop_audio()
	runtime._features = {"act_foley": false, "act_vocals": true, "act_climax": false}
	runtime._start_audio()
	check(runtime.has_node("UnfplapActAudio"), "vocals on starts the pack audio node")
	runtime._stop_audio()
	runtime._features = {"act_foley": false, "act_vocals": false, "act_climax": true}
	runtime._start_audio()
	check(runtime.has_node("UnfplapActAudio"), "climax on starts the pack audio node")
	runtime._stop_audio()
	root.remove_child(runtime)
	runtime.free()

	# The native FlankTouch player is the smack voice: act_foley on swaps in a pack variant at
	# impact time, off restores the stock stream, level and pitch.
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
	var smack_runtime: Node = RUNTIME.new()
	smack_runtime.pony = smack_pony
	smack_runtime._features = {"act_foley": false}
	root.add_child(smack_runtime)
	var caress: RefCounted = CAESS.new(smack_runtime)
	caress.set("pony", smack_pony)
	caress.call("_install_smack_sound")
	check(smack_player.stream == stock_stream, "act_foley off keeps the stock smack")
	smack_runtime._features = {"act_foley": true}
	caress.call("_install_smack_sound")
	check(smack_player.stream != stock_stream and smack_player.stream is AudioStream,
		"act_foley installs a pack smack")
	check(near(smack_player.volume_db, CAESS.SMACK_VOLUME_DB), "pack smack uses its own level")
	check(smack_player.pitch_scale >= CAESS.SMACK_PITCH_MIN
		and smack_player.pitch_scale <= CAESS.SMACK_PITCH_MAX, "pack smack varies its pitch")
	caress.call("_restore_smack_sound")
	check(smack_player.stream == stock_stream, "smack restore puts the stock stream back")
	check(near(smack_player.volume_db, -10.0) and near(smack_player.pitch_scale, 1.2),
		"smack restore puts the stock level and pitch back")
	caress.call("_install_smack_sound")
	smack_runtime._features = {"act_foley": false}
	caress.call("_sync")
	check(smack_player.stream == stock_stream, "live foley off restores the stock smack")
	caress = null
	root.remove_child(smack_runtime)
	smack_runtime.free()
	root.remove_child(smack_pony)
	smack_pony.free()

	print("_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
