extends RefCounted
## Classifies one AI profile's voice routing. Pure: the caller supplies the director's TTS node
## and the game's TTS-enabled setting. `effective_ponese` mirrors the game's own routing, so a
## profile with a character voice still counts as Ponese when the global mode/server says so.

const CHATTER := preload("res://world/ai/chatter_voice.gd")


static func classify(profile: Dictionary, tts: Node, tts_enabled := true) -> Dictionary:
	var global_mode := str(tts.get("voice_mode")) if is_instance_valid(tts) else "ponese"
	var profile_mode := str(profile.get("voice_mode", ""))
	var mode := profile_mode if not profile_mode.is_empty() else global_mode
	var status := str(profile.get("voice_status", ""))
	var speaker := int(profile.get("tts_speaker_id", -1))
	var openai := str(profile.get("openai_voice", ""))
	var has_character_voice := (speaker >= 0 or not openai.is_empty()) \
		and not status.begins_with("Ponese") \
		and not status.begins_with("temporary shared")
	var server := is_instance_valid(tts) and tts.has_method("has_server") and bool(tts.call("has_server"))
	var effective := not tts_enabled or not server or CHATTER.is_ponese_mode(global_mode)
	if not effective:
		effective = CHATTER.use_chatter(profile, global_mode)
	return {
		"mode": mode,
		"global_mode": global_mode,
		"status": status,
		"speaker": speaker,
		"openai_voice": openai,
		"generated": has_character_voice,
		"effective_ponese": effective,
	}


static func describe(info: Dictionary) -> String:
	return "mode=%s status=%s speaker=%d openai=%s generated=%s effective=%s" % [
		str(info.get("mode", "?")),
		str(info.get("status", "")),
		int(info.get("speaker", -1)),
		"yes" if not str(info.get("openai_voice", "")).is_empty() else "no",
		"yes" if bool(info.get("generated", false)) else "no",
		"ponese" if bool(info.get("effective_ponese", false)) else "tts",
	]
