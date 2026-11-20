extends "res://mods/unfplap/tests/support/suite.gd"
## Pure voice-routing classification checks.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_voice.gd

const VOICE := preload("res://mods/unfplap/audio/voice_status.gd")



func run() -> void:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar voice_mode := \"auto\"\nvar server := true\nfunc has_server() -> bool:\n\treturn server\n"
	script.reload()
	var tts: Node = script.new()
	root.add_child(tts)

	var generated: Dictionary = VOICE.classify({
		"id": "fluttershy",
		"voice_status": "character voice",
		"tts_speaker_id": 5,
	}, tts, true)
	check(bool(generated.get("generated", false)), "character voice is generated")
	check(not bool(generated.get("effective_ponese", true)), "character voice routes to TTS")

	var ponese: Dictionary = VOICE.classify({
		"id": "wallflower_blush",
		"voice_status": "Ponese; no approved voice bank",
		"tts_speaker_id": -1,
	}, tts, true)
	check(not bool(ponese.get("generated", true)), "Ponese profile is not generated")
	check(bool(ponese.get("effective_ponese", false)), "Ponese profile is effective Ponese")

	var shared: Dictionary = VOICE.classify({
		"id": "cheerilee",
		"voice_status": "temporary shared Cheerilee voice",
		"tts_speaker_id": 6,
	}, tts, true)
	check(not bool(shared.get("generated", true)), "temporary shared voice is not generated")
	check(bool(shared.get("effective_ponese", false)), "temporary shared voice falls back to Ponese")

	tts.set("voice_mode", "ponese")
	var forced: Dictionary = VOICE.classify({
		"id": "fluttershy",
		"voice_status": "character voice",
		"tts_speaker_id": 5,
	}, tts, true)
	check(bool(forced.get("effective_ponese", false)), "global Ponese mode forces Ponese")

	tts.set("voice_mode", "auto")
	var disabled: Dictionary = VOICE.classify({
		"id": "fluttershy",
		"voice_status": "character voice",
		"tts_speaker_id": 5,
	}, tts, false)
	check(bool(disabled.get("effective_ponese", false)), "disabled TTS forces Ponese")
	check(not VOICE.describe(generated).is_empty(), "voice description exists")

	# A TTS node without the server probe, and a missing TTS node, both read as no server.
	var silent_script := GDScript.new()
	silent_script.source_code = "extends Node\nvar voice_mode := \"auto\"\n"
	silent_script.reload()
	var no_server: Node = silent_script.new()
	root.add_child(no_server)
	var no_probe: Dictionary = VOICE.classify({
		"id": "fluttershy",
		"voice_status": "character voice",
		"tts_speaker_id": 5,
	}, no_server, true)
	check(bool(no_probe.get("effective_ponese", false)),
		"a TTS node without has_server reads as no server")
	var absent: Dictionary = VOICE.classify({
		"id": "fluttershy",
		"voice_status": "character voice",
		"tts_speaker_id": 5,
	}, null, true)
	check(bool(absent.get("effective_ponese", false)),
		"a missing TTS node reads as no server")
	check(str(absent.get("global_mode", "")) == "ponese",
		"a missing TTS node reads the Ponese mode")
	no_server.free()

	tts.free()
	if failures == 0:
		print("VOICE_PASS")
	finish()
