extends "res://mods/unfplap/tests/support/suite.gd"
## Pure cue math, the pack cue table and the hand-smack install path.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/act_audio/test_act_audio.gd

const CATALOGUE := preload("res://mods/unfplap/audio/cues.gd")
const POOL := preload("res://mods/unfplap/audio/pool.gd")
const SMACK := preload("res://mods/unfplap/shared/smack_cues.gd")
const PREFERENCES := preload("res://mods/unfplap/shared/preferences.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
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
		check(CATALOGUE.tier_for(value) == PREFERENCES.intensity_for(value),
			"tier matches preferences at %.2f" % value)
	check(CATALOGUE.cue_for_plap("") == "", "no impact tier has no plap cue")
	check(CATALOGUE.cue_for_plap("firm") == "plap_firm", "firm cue")
	check(CATALOGUE.cue_for_plap("rough") == "plap_rough", "rough cue")
	check(CATALOGUE.uses_bed(CATALOG.MISSIONARY), "missionary uses bed cues")
	check(not CATALOGUE.uses_bed(CATALOG.STANDING), "standing skips bed cues")
	check(not CATALOGUE.uses_bed(""), "an empty profile skips bed cues")
	check(CATALOGUE.soft_surface("couch"), "a couch is a soft surface")
	check(CATALOGUE.soft_surface("wooden_sofa"), "a sofa is a soft surface")
	check(not CATALOGUE.soft_surface("bed"), "a plain bed is wood")
	check(CATALOGUE.pitch_for(0.0) < CATALOGUE.pitch_for(1.0), "pitch rises with strength")
	check(CATALOGUE.pitch_for(0.0) >= 0.9 and CATALOGUE.pitch_for(1.0) <= 1.1,
		"pitch stays bounded")
	check(near(CATALOGUE.plap_volume_db(0.0), -10.0), "soft plap floor")
	check(CATALOGUE.plap_volume_db(0.2) < CATALOGUE.plap_volume_db(0.5),
		"plap volume rises with strength")
	check(near(CATALOGUE.plap_volume_db(1.0), 0.0), "full-strength plap volume")
	check(near(CATALOGUE.plap_contact_db(0.0), -8.0), "the contact edge is the quiet end")
	check(near(CATALOGUE.plap_contact_db(1.0), 0.0), "full body contact is the loud end")
	check(CATALOGUE.plap_contact_db(0.5) > -8.0 and CATALOGUE.plap_contact_db(0.5) < 0.0,
		"a partial body contact fades in")

	check(POOL.next_index(1, 0, 0) == 0, "single variant index")
	for last: int in range(4):
		for roll: int in range(4):
			var picked: int = POOL.next_index(4, last, roll)
			check(picked >= 0 and picked < 4, "variant index in range")
			check(picked != last or last < 0, "variant never repeats the previous index")
	check(POOL.next_index(4, 2, 2) == 3, "repeat rolls forward")

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
	check(SMACK.PATHS.size() >= 2, "flank smack has multiple pack variants")
	for path: String in SMACK.PATHS:
		check(ResourceLoader.exists(path), "smack stream exists: " + path)
		var smack_stream: Resource = load(path)
		check(smack_stream is AudioStream, "smack stream type: " + path)
		if smack_stream is AudioStream:
			var seconds := (smack_stream as AudioStream).get_length()
			check(seconds > 0.05 and seconds < 1.0, "smack stream length: " + path)

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
