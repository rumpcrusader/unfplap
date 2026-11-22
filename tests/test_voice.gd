extends "res://mods/unfplap/tests/support/suite.gd"
## The pure voice-routing classification and the live debug line the world Director view fills.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_voice.gd

const VOICE := preload("res://mods/unfplap/shared/voice_status.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")



class FakeTts extends Node:
	var voice_mode := "auto"

	func has_server() -> bool:
		return true


class FakeSettings extends Node:
	func tts_enabled() -> bool:
		return true


class FakeDirector extends Node:
	var characters: Dictionary = {}
	var tts: Node = null


func _facts(profile: Dictionary, mode: String, server: bool, ponese: bool,
		chatter: bool, enabled := true) -> VOICE.Facts:
	var out := VOICE.Facts.new()
	out.profile = profile
	out.global_mode = mode
	out.server = server
	out.ponese = ponese
	out.chatter = chatter
	out.tts_enabled = enabled
	return out


func run() -> void:
	var generated_profile := {
		"id": "fluttershy",
		"voice_status": "character voice",
		"tts_speaker_id": 5,
	}
	var generated: Dictionary = VOICE.classify(
		_facts(generated_profile, "auto", true, false, false))
	check(bool(generated.get("generated", false)), "character voice is generated")
	check(not bool(generated.get("effective_ponese", true)), "character voice routes to TTS")

	var ponese: Dictionary = VOICE.classify(_facts({
		"id": "wallflower_blush",
		"voice_status": "Ponese; no approved voice bank",
		"tts_speaker_id": -1,
	}, "auto", true, true, true))
	check(not bool(ponese.get("generated", true)), "Ponese profile is not generated")
	check(bool(ponese.get("effective_ponese", false)), "Ponese profile is effective Ponese")

	var shared: Dictionary = VOICE.classify(_facts({
		"id": "cheerilee",
		"voice_status": "temporary shared Cheerilee voice",
		"tts_speaker_id": 6,
	}, "auto", true, false, true))
	check(not bool(shared.get("generated", true)), "temporary shared voice is not generated")
	check(bool(shared.get("effective_ponese", false)), "temporary shared voice falls back to Ponese")

	var forced: Dictionary = VOICE.classify(
		_facts(generated_profile, "ponese", true, true, false))
	check(bool(forced.get("effective_ponese", false)), "global Ponese mode forces Ponese")

	var disabled: Dictionary = VOICE.classify(
		_facts(generated_profile, "auto", true, false, false, false))
	check(bool(disabled.get("effective_ponese", false)), "disabled TTS forces Ponese")
	check(not VOICE.describe(generated).is_empty(), "voice description exists")

	# A missing server answer reads as no server, and no TTS node reads the Ponese mode.
	var no_server: Dictionary = VOICE.classify(
		_facts(generated_profile, "auto", false, false, false))
	check(bool(no_server.get("effective_ponese", false)),
		"a TTS node without has_server reads as no server")
	var absent: Dictionary = VOICE.classify(_facts(generated_profile, "ponese", false, true, false))
	check(bool(absent.get("effective_ponese", false)), "a missing TTS node reads as no server")
	check(str(absent.get("global_mode", "")) == "ponese",
		"a missing TTS node reads the Ponese mode")

	# The Director view reads the live profile, mode, server and switch into the facts.
	var tts := FakeTts.new()
	root.add_child(tts)
	var existing: Node = root.get_node_or_null("Settings")
	if existing != null:
		existing.name = "SettingsTestHidden"
	var settings := FakeSettings.new()
	settings.name = "Settings"
	root.add_child(settings)
	var director := FakeDirector.new()
	director.tts = tts
	director.characters = {"fluttershy": {"profile": generated_profile}}
	director.add_to_group("conversation_director")
	root.add_child(director)
	var live: VOICE.Facts = WORLD.director().voice_facts("fluttershy")
	check(live.profile == generated_profile, "the live facts carry the director's profile")
	check(live.global_mode == "auto" and live.server and live.tts_enabled,
		"the live facts carry the TTS mode, its server and the game's switch")
	check(not live.ponese and not live.chatter,
		"the game's own routing keeps a character voice on TTS")
	var routed: Dictionary = VOICE.classify(live)
	check(bool(routed.get("generated", false)) and not bool(routed.get("effective_ponese", true)),
		"the live facts classify as the director routes her")
	check(VOICE.status_line(live).begins_with("voice "),
		"the live debug line names the routing")
	check(str(VOICE.classify(WORLD.director().voice_facts("unknown")).get("status", "?")) == "",
		"an unknown id reads an empty profile")

	director.tts = null
	var silent: VOICE.Facts = WORLD.director().voice_facts("fluttershy")
	check(not silent.server and silent.global_mode == "ponese",
		"a director without a TTS node reads no server and the Ponese mode")
	check(bool(VOICE.classify(silent).get("effective_ponese", false)),
		"a director without a TTS node routes to Ponese")

	director.remove_from_group("conversation_director")
	root.remove_child(director)
	director.free()
	root.remove_child(settings)
	settings.free()
	if existing != null:
		existing.name = "Settings"
	tts.free()
	WORLD.unbind()
	if failures == 0:
		print("VOICE_PASS")
	finish()
