extends "res://mods/unfplap/tests/support/suite.gd"
## The outside-act stock smack sound: install, restore, live switch and the act handoff.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/act_audio/test_smack_sound.gd

const STOCK := preload("res://mods/unfplap/audio/stock_smack.gd")
const CUES := preload("res://mods/unfplap/audio/smack_cues.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")



func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	var before := SETTINGS.pack_smack_sound.get_bool()
	SETTINGS.pack_smack_sound.set_bool(true)

	var service: Node = STOCK.new()
	root.add_child(service)

	var pony := _pony()
	root.add_child(pony)
	var player := _player(pony)
	var stock_stream := player.stream
	service.call("pony_ready", pony)
	var randomizer := player.stream as AudioStreamRandomizer
	check(randomizer != null, "a ready pony gets the pack stream")
	if randomizer != null:
		check(randomizer.streams_count == CUES.PATHS.size(),
			"every pack smack variant is in the pool")
		check(randomizer.playback_mode == AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS,
			"the pool avoids repeating the previous slap")
		check(near(randomizer.random_pitch, CUES.PITCH_MAX),
			"the pool varies pitch by the act range")
	check(near(player.volume_db, CUES.STOCK_VOLUME_DB), "the native player uses the outside-act level")
	check(CUES.STOCK_VOLUME_DB > CUES.VOLUME_DB, "the outside-act level is louder than the act's")
	check(near(player.pitch_scale, 1.0), "the native pitch is neutral before the pool varies it")

	SETTINGS.pack_smack_sound.set_bool(false)
	service.call("apply_settings")
	check(player.stream == stock_stream, "turning the switch off restores the stock stream")
	check(near(player.volume_db, -10.0) and near(player.pitch_scale, 1.2),
		"turning the switch off restores the stock level and pitch")

	SETTINGS.pack_smack_sound.set_bool(true)
	service.call("apply_settings")
	check(player.stream is AudioStreamRandomizer, "turning the switch on installs the pack stream")

	service.call("act_start", pony)
	check(player.stream == stock_stream, "an act pony gives its player back to the stock act path")
	service.call("act_end", pony)
	check(player.stream is AudioStreamRandomizer, "the pack stream returns after the act")

	var other := _pony()
	root.add_child(other)
	var other_player := _player(other)
	var other_stock := other_player.stream
	service.call("pony_ready", other)
	check(other_player.stream is AudioStreamRandomizer, "a new pony joins while the switch is on")

	SETTINGS.pack_smack_sound.set_bool(false)
	service.call("apply_settings")
	check(other_player.stream == other_stock, "a later off also restores the newer pony")
	var late := _pony()
	root.add_child(late)
	var late_player := _player(late)
	var late_stock := late_player.stream
	service.call("pony_ready", late)
	check(late_player.stream == late_stock, "a pony seen while off keeps the stock stream")
	SETTINGS.pack_smack_sound.set_bool(true)
	service.call("apply_settings")
	check(late_player.stream is AudioStreamRandomizer,
		"turning the switch on reaches a pony seen while off")

	var bare := Node3D.new()
	root.add_child(bare)
	service.call("pony_ready", bare)
	check(bare.is_inside_tree(), "a pony without FlankTouch is ignored")

	service.call("on_world_closed")
	check(player.stream == stock_stream and other_player.stream == other_stock
		and late_player.stream == late_stock, "a world close puts every stock player back")

	service.call("shutdown")
	root.remove_child(service)
	service.free()
	root.remove_child(pony)
	pony.free()
	root.remove_child(other)
	other.free()
	root.remove_child(late)
	late.free()
	root.remove_child(bare)
	bare.free()
	SETTINGS.pack_smack_sound.set_bool(before)

	finish()


func _pony() -> Node3D:
	var pony := Node3D.new()
	var flank := Node3D.new()
	flank.name = "FlankTouch"
	pony.add_child(flank)
	var player := AudioStreamPlayer3D.new()
	player.name = "sound"
	player.stream = AudioStreamWAV.new()
	player.volume_db = -10.0
	player.pitch_scale = 1.2
	flank.add_child(player)
	return pony


func _player(pony: Node3D) -> AudioStreamPlayer3D:
	return pony.get_node("FlankTouch/sound") as AudioStreamPlayer3D
