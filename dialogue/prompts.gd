extends RefCounted
## Pure prompt-note assembly for the normal dialogue prompt. The runtime supplies the act state,
## the history note, the relationship note, the afterglow beat and the live caress/lean reads;
## this module owns the wording and the precedence. Contract: `docs/dialogue.md`.

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const STATE_ACTIVE := ACT_STATE.State.ACTIVE
const STATE_CLIMAX := ACT_STATE.State.CLIMAX
const STATE_AFTERGLOW := ACT_STATE.State.AFTERGLOW

const WARM_NOTE := "- You are still warm and relaxed after making love with Anon. Keep an affectionate tone; do not act stiff or businesslike."
const ACT_NOTE := "- You are having sex with Anon right now."
const AFTERGLOW_NOTE := "- The act has ended, but you are still close with Anon in the afterglow."
const CHEST := "your chest and belly"
const FLANK := "your flank"
const BODY_OWN := "- Your body right now: your own body."
const BODY_OWN_NAMED := "- Your body right now: your own body, %s."
const BODY_BORROWED := "- Your body right now: %s's shape, not your own body."
const BODY_BORROWED_UNNAMED := "- Your body right now: a borrowed shape, not your own body."


static func in_act(state: int) -> bool:
	return state in [STATE_ACTIVE, STATE_CLIMAX, STATE_AFTERGLOW]


## The presented-body line; a pony with no body-change source adds none, so ordinary dialogue
## stays unchanged.
static func body_note(values: Dictionary) -> String:
	if not bool(values.get("form_source", false)):
		return ""
	var form_name := str(values.get("form_name", "")).strip_edges()
	if bool(values.get("form_borrowed", false)):
		return BODY_BORROWED % form_name if not form_name.is_empty() else BODY_BORROWED_UNNAMED
	return BODY_OWN_NAMED % form_name if not form_name.is_empty() else BODY_OWN


## Build the note from plain data, so the wording and precedence are testable without a scene.
static func note(values: Dictionary) -> String:
	var state := int(values.get("state", 0))
	var history := str(values.get("history", ""))
	var body := body_note(values)
	if not in_act(state):
		if bool(values.get("warm", false)):
			var warm := WARM_NOTE
			var warm_relation := str(values.get("relation", ""))
			if not warm_relation.is_empty():
				warm += " " + warm_relation
			if not body.is_empty():
				warm += " " + body
			return warm
		if body.is_empty():
			return history
		return body if history.is_empty() else body + " " + history
	var parts: PackedStringArray = []
	if state == STATE_AFTERGLOW:
		parts.append(AFTERGLOW_NOTE)
		if not body.is_empty():
			parts.append(body)
		var beat := str(values.get("beat", ""))
		if not beat.is_empty():
			parts.append("- " + beat)
	else:
		parts.append(ACT_NOTE)
		if not body.is_empty():
			parts.append(body)
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
	return " ".join(parts)
