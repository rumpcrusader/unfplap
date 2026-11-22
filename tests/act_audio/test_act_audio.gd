extends "res://mods/unfplap/tests/support/suite.gd"
## Pure/unit checks for the act audio facade and its pack cue table.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/act_audio/test_act_audio.gd

const ACT := preload("res://mods/unfplap/audio/service.gd")
const CATALOGUE := preload("res://mods/unfplap/audio/cues.gd")
const SMACK := preload("res://mods/unfplap/shared/smack_cues.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const POSE_VIEW := preload("res://mods/unfplap/shared/pose_view.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const SMACK_ACTION := preload("res://mods/unfplap/hands/smack.gd")
const SMACK_PORT := preload("res://mods/unfplap/hands/port.gd")


class FakeSmackPort extends SMACK_PORT:
	var flank_node: Node = null

	func _init(flank: Node) -> void:
		flank_node = flank

	func flank() -> Node:
		return flank_node

func run() -> void:
	for value: float in [0.0, 0.1, 0.33, 0.5, 0.66, 0.9, 1.0]:
		check(ACT.tier_for(value) == PREFERENCES.intensity_for(value),
			"tier matches preferences at %.2f" % value)
	check(ACT.cue_for_plap("") == "", "no impact tier has no plap cue")
	check(ACT.cue_for_plap("firm") == "plap_firm", "firm cue")
	check(ACT.cue_for_plap("rough") == "plap_rough", "rough cue")
	check(ACT.uses_bed(CATALOG.MISSIONARY), "missionary uses bed cues")
	check(not ACT.uses_bed(CATALOG.STANDING), "standing skips bed cues")
	check(not ACT.uses_bed(""), "an empty profile skips bed cues")
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
		"fabric": 8, "mouth_kiss": 8,
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
	var pools: Dictionary = act.get("_pools")
	check(pools.is_empty(), "a fresh facade has no pool before the act")

	var parent := Node3D.new()
	root.add_child(parent)
	parent.add_child(act)
	act.begin()
	var view := POSE_VIEW.new()
	view.audio = {"impact": CATALOG.MISSIONARY}
	act.pose_changed(view)
	pools = act.get("_pools")
	check(pools.has("plap_firm"), "begin opens the foley layer")
	# A slow bottom that touches still stays silent: the tier is the impact speed.
	act.play_impact("", 0.9, Vector3.ZERO, Vector3.ZERO, false, 0.0, 0.02)
	var ready_at: Dictionary = act.get("_ready_at")
	check(float(ready_at.get("plap_firm", 0.0)) == 0.0, "a slow bottom emits no plap")
	check(float(ready_at.get("plap_rough", 0.0)) == 0.0, "a slow bottom emits no rough plap")
	check(float(ready_at.get("slide_in", 0.0)) > 0.0, "a slow impact keeps the slide")
	check(float(ready_at.get("fabric", 0.0)) == 0.0, "a wood bed has no bed cue")
	check(not act.play_plap("", 0.2, Vector3.ZERO), "a plap call without a tier is refused")
	ready_at = act.get("_ready_at")
	ready_at["plap_rough"] = 0.0
	ready_at["slide_in"] = 0.0
	act.play_impact("rough", 0.7, Vector3.ZERO, Vector3.ZERO, false, 0.0, 0.02)
	check(float(ready_at.get("plap_rough", 0.0)) > 0.0, "a bottomed-out rough impact plays the plap")
	check(float(ready_at.get("slide_in", 0.0)) > 0.0, "a rough impact keeps the slide")
	check(act.play_bed(0.7, Vector3.ZERO, true), "soft-bed fabric plays")
	check(not act.play_bed(0.7, Vector3.ZERO, false), "a wood bed has no creak")
	# The body slap needs his skin to reach her coat: 3 cm short of a 2 cm contact epsilon is silent,
	# while a stroke at the epsilon edge still plays. The slide and the bed are never gated.
	ready_at["plap_rough"] = 0.0
	ready_at["slide_in"] = 0.0
	act.play_impact("rough", 0.7, Vector3.ZERO, Vector3.ZERO, false, 0.03, 0.02)
	check(float(ready_at.get("plap_rough", 0.0)) == 0.0,
		"a stroke past the contact gap has no plap")
	check(float(ready_at.get("slide_in", 0.0)) > 0.0,
		"a stroke past the contact gap keeps the slide")
	ready_at["plap_rough"] = 0.0
	act.play_impact("rough", 0.7, Vector3.ZERO, Vector3.ZERO, false, 0.02, 0.02)
	check(float(ready_at.get("plap_rough", 0.0)) > 0.0,
		"a stroke at the contact edge plays the plap")
	ready_at["plap_rough"] = 0.0
	act.play_impact("rough", 0.7, Vector3.ZERO, Vector3.ZERO, false, 0.0, 0.0)
	check(float(ready_at.get("plap_rough", 0.0)) > 0.0,
		"true contact at a zero epsilon plays the plap")
	# The oral segment drops the body slap but keeps the slide.
	ready_at["plap_rough"] = 0.0
	ready_at["slide_in"] = 0.0
	act.play_impact("rough", 0.7, Vector3.ZERO, Vector3.ZERO, false,
		0.0, 0.02, false)
	check(float(ready_at.get("plap_rough", 0.0)) == 0.0, "an oral impact skips the plap")
	check(float(ready_at.get("slide_in", 0.0)) > 0.0, "an oral impact keeps the slide")
	check(act.play_plap("firm", 0.7, Vector3.ZERO), "foley plap starts a player")
	check(not act.play_plap("firm", 0.7, Vector3.ZERO),
		"cooldown blocks an immediate second plap")
	check(act.play_mouth_kiss(), "mouth kiss plays")
	check(SMACK.PATHS.size() >= 2, "flank smack has multiple pack variants")
	for path: String in SMACK.PATHS:
		check(ResourceLoader.exists(path), "smack stream exists: " + path)
		var smack_stream: Resource = load(path)
		check(smack_stream is AudioStream, "smack stream type: " + path)
		if smack_stream is AudioStream:
			var seconds := (smack_stream as AudioStream).get_length()
			check(seconds > 0.05 and seconds < 1.0, "smack stream length: " + path)
	ready_at = act.get("_ready_at")
	ready_at["plap_rough"] = 0.0
	check(act.play_plap("rough", 0.9, Vector3.ZERO), "a rough plap starts a player")
	act.stop()
	parent.remove_child(act)
	act.free()
	parent.free()

	# Runtime integration: the pack node is created for every act.
	var runtime: Node = RUNTIME.new()
	runtime.pony = Node3D.new()
	runtime.act.bed = Node3D.new()
	root.add_child(runtime)
	runtime._bundle.audio.start(runtime.pony, "", runtime.act.bed)
	check(runtime.has_node("UnfplapActAudio"), "the act starts the pack audio node")
	runtime._bundle.audio.stop()
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
	var port := FakeSmackPort.new(flank)
	var smack: RefCounted = SMACK_ACTION.new(port)
	smack.call("_install_sound")
	check(smack_player.stream != stock_stream and smack_player.stream is AudioStream,
		"the act installs a pack smack")
	check(near(smack_player.volume_db, SMACK.VOLUME_DB), "pack smack uses its own level")
	check(smack_player.pitch_scale >= SMACK.PITCH_MIN
		and smack_player.pitch_scale <= SMACK.PITCH_MAX, "pack smack varies its pitch")
	smack.call("_restore_sound")
	check(smack_player.stream == stock_stream, "smack restore puts the stock stream back")
	check(near(smack_player.volume_db, -10.0) and near(smack_player.pitch_scale, 1.2),
		"smack restore puts the stock level and pitch back")
	smack = null
	root.remove_child(smack_pony)
	smack_pony.free()

	finish()
