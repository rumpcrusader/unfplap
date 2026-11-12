extends RefCounted
## Pure prompt-note assembly for the normal dialogue prompt. The runtime supplies the act state,
## the history note, the relationship note, the afterglow beat and the live caress/lean reads;
## this module owns the wording and the precedence. Contract: `docs/lines.md`.

const STATE_ACTIVE := 2
const STATE_CLIMAX := 3
const STATE_AFTERGLOW := 4

const WARM_NOTE := "- You are still warm and relaxed after making love with Anon. Keep an affectionate tone; do not act stiff or businesslike."
const ACT_NOTE := "- You are in the middle of sex with Anon."
const AFTERGLOW_NOTE := "- You are still in the afterglow with Anon; the act has ended, but the moment is not finished yet."
const STAY_NOTE := "If Anon asks to stay longer, use [stay: 120] to hold the afterglow."
const CHEST := "your chest and belly"
const FLANK := "your flank"


static func in_act(state: int) -> bool:
	return state in [STATE_ACTIVE, STATE_CLIMAX, STATE_AFTERGLOW]


## Build the note. Every value is plain data: `state`, `warm`, `history`, `beat`, `relation`,
## `caressing`, `leaning`, `missionary`.
static func note(values: Dictionary) -> String:
	var state := int(values.get("state", 0))
	var history := str(values.get("history", ""))
	if not in_act(state):
		if bool(values.get("warm", false)):
			var warm := WARM_NOTE
			var warm_relation := str(values.get("relation", ""))
			if not warm_relation.is_empty():
				warm += " " + warm_relation
			return warm
		return history
	var parts: PackedStringArray = []
	if state == STATE_AFTERGLOW:
		parts.append(AFTERGLOW_NOTE)
		var beat := str(values.get("beat", ""))
		if not beat.is_empty():
			parts.append("- " + beat)
	else:
		parts.append(ACT_NOTE)
		if not history.is_empty():
			parts.append(history)
	var relation := str(values.get("relation", ""))
	if not relation.is_empty():
		parts.append("- " + relation)
	var caressing := bool(values.get("caressing", false))
	var leaning := bool(values.get("leaning", false))
	var where := CHEST if bool(values.get("missionary", false)) else FLANK
	if caressing and leaning:
		parts.append("He is leaning in close against you and caressing " + where + ".")
	elif caressing:
		parts.append("He is caressing " + where + ".")
	elif leaning:
		parts.append("He is leaning in close, holding you.")
	else:
		parts.append("He is close but not caressing or leaning in right now.")
	if state == STATE_AFTERGLOW:
		parts.append(STAY_NOTE)
	return " ".join(parts)
