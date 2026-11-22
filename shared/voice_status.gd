extends RefCounted
## Classifies one AI profile's voice routing and names the line the debug panel shows. It reads no
## game node: the world Director view reads the live facts and hands them in.

## One classification's inputs: the profile the director holds and the game's own answers for it.
class Facts extends RefCounted:
	var profile: Dictionary = {}
	var global_mode := "ponese"
	var server := false
	var tts_enabled := true
	var ponese := true
	var chatter := false


## Classifies one AI profile's voice routing. `effective_ponese` mirrors the game's own routing, so
## a character voice still counts as Ponese when the global mode or server says so.
static func classify(facts: Facts) -> Dictionary:
	var profile := facts.profile
	var global_mode := facts.global_mode
	var profile_mode := str(profile.get("voice_mode", ""))
	var mode := profile_mode if not profile_mode.is_empty() else global_mode
	var status := str(profile.get("voice_status", ""))
	var speaker := int(profile.get("tts_speaker_id", -1))
	var openai := str(profile.get("openai_voice", ""))
	var has_character_voice := (speaker >= 0 or not openai.is_empty()) \
		and not status.begins_with("Ponese") \
		and not status.begins_with("temporary shared")
	var effective := not facts.tts_enabled or not facts.server or facts.ponese
	if not effective:
		effective = facts.chatter
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


## The debug panel's one voice line for the facts it was handed.
static func status_line(facts: Facts) -> String:
	return "voice " + describe(classify(facts))
