extends RefCounted
## Classifies one AI profile's voice routing and names the line the debug panel shows. The match
## is pure when the caller passes its inputs, and reads the live director when it asks by id.

const CHATTER := preload("res://world/ai/chatter_voice.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")


## Classifies one AI profile's voice routing. `effective_ponese` mirrors the game's own routing, so
## a character voice still counts as Ponese when the global mode or server says so.
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
	var server := GAME.tts_has_server(tts)
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


## The live routing for one stable id: the director's own profile and TTS node plus the game's
## switch. An absent director or settings autoload reads as Ponese.
static func routing(id: String) -> Dictionary:
	var director := _director()
	return classify(_profile(director, id), GAME.tts_of(director), _tts_enabled())


## The debug panel's one voice line for `id`.
static func status_line(id: String) -> String:
	return "voice " + describe(routing(id))


static func _director() -> Node:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	return (loop as SceneTree).get_first_node_in_group("conversation_director")


static func _profile(director: Node, id: String) -> Dictionary:
	if not is_instance_valid(director):
		return {}
	var characters: Variant = director.get("characters")
	if characters is Dictionary and (characters as Dictionary).has(id):
		var entry: Variant = (characters as Dictionary)[id]
		if entry is Dictionary:
			var profile: Variant = (entry as Dictionary).get("profile", {})
			if profile is Dictionary:
				return profile
	return {}


static func _tts_enabled() -> bool:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return false
	return GAME.tts_enabled((loop as SceneTree).root.get_node_or_null("Settings"))
