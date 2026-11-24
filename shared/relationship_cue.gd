extends RefCounted
## Pure relationship/tone formatting for the cue prompt. The runtime gathers the live facts;
## this module only turns them into private, non-numeric guidance and owns the peak-memory gate.

const DEFAULTS_DATA := preload("res://mods/unfplap/shared/defaults_data.gd")
const PROMPT_TEXT := preload("res://mods/unfplap/shared/prompt_text.gd")


static func note(facts: Dictionary) -> String:
	if facts.is_empty():
		return ""
	var friendship := str(facts.get("friendship", "")).strip_edges()
	var love := str(facts.get("love", "")).strip_edges()
	if friendship.is_empty() and love.is_empty():
		return ""
	var parts: PackedStringArray = []
	if not friendship.is_empty():
		parts.append("friendship " + friendship)
	if not love.is_empty():
		parts.append("love " + love)
	var stage := _stage_phrase(str(facts.get("stage", "")).strip_edges())
	if not stage.is_empty():
		parts.append(stage)
	if bool(facts.get("first_time", false)):
		parts.append("first time together")
	else:
		parts.append("you have been together before")
	var mood := str(facts.get("mood", "")).strip_edges()
	if not mood.is_empty():
		parts.append("mood " + mood)
	if bool(facts.get("careful", false)):
		parts.append("there is a little hurt")
	return "You and Anon: " + ", ".join(parts) + "."


## A human stage phrase. The raw bond id is never sent to the model.
static func _stage_phrase(stage: String) -> String:
	var rows: Dictionary = DEFAULTS_DATA.prompts_block("relationship.stages")
	return PROMPT_TEXT.render(str(rows.get(stage, "")), {})


## Relationship depth chooses how openly warm the line can be. A strained moment overrides
## depth; this is a tone instruction, not a status label the pony may say aloud. With no romance an
## acquaintance stays guarded and a friend opens to friendly; romance opens warmer, a first time
## with romance is tender, and a marefriend is warm.
static func tone(facts: Dictionary) -> String:
	if bool(facts.get("careful", false)):
		return "careful"
	var love_level := int(facts.get("love_level", -1))
	var stage := str(facts.get("stage", ""))
	var romance := love_level >= 0 or stage in ["dating", "engaged", "married"]
	if bool(facts.get("first_time", false)) and romance:
		return "tender"
	match love_level:
		4:
			return "open"
		3:
			return "ardent"
		2:
			return "warm"
		1, 0:
			return "tender"
	if stage in ["dating", "engaged", "married"]:
		return "warm"
	if int(facts.get("friendship_level", -1)) >= 2:
		return "friendly"
	return "guarded"


static func tone_line(tone_name: String) -> String:
	var rows: Dictionary = DEFAULTS_DATA.prompts_block("relationship.tones")
	return PROMPT_TEXT.render(str(rows.get(tone_name, rows.get("default", ""))), {})


static func memory_line(text: String) -> String:
	var cleaned := text.strip_edges().replace("\r", " ").replace("\n", " ")
	if cleaned.is_empty():
		return ""
	if cleaned.length() > 180:
		cleaned = cleaned.left(177).strip_edges() + "..."
	return PROMPT_TEXT.render(DEFAULTS_DATA.prompts_block("relationship.memory"),
		{"text": cleaned})


## A peak act is clean and either very high or technically excellent. The player's climax alone
## is not enough if she disliked something.
static func peak_eligible(peak_satisfaction: float, both_matches: int, dislikes: int) -> bool:
	return dislikes == 0 and (peak_satisfaction >= 90.0 or both_matches >= 6)


## Higher is better; the store keeps the strongest peak per mare.
static func peak_score(peak_satisfaction: float, both_matches: int, liked_touch: int,
		liked_talk: int, dislikes: int) -> float:
	return peak_satisfaction + float(both_matches) * 3.0 + float(liked_touch) \
		+ float(liked_talk) - float(dislikes) * 10.0
