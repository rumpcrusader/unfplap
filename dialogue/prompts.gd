extends RefCounted
## Pure prompt-note assembly for the normal dialogue prompt. The runtime supplies the act state,
## the history note, the relationship note, the afterglow beat and the live caress/lean reads;
## this module owns the precedence and `prompt_text` words the lines.

const ACT_STATE := preload("res://mods/unfplap/shared/act_state.gd")
const DEFAULTS_DATA := preload("res://mods/unfplap/shared/defaults_data.gd")
const PROMPT_TEXT := preload("res://mods/unfplap/shared/prompt_text.gd")
const STATE_ACTIVE := ACT_STATE.State.ACTIVE
const STATE_CLIMAX := ACT_STATE.State.CLIMAX
const STATE_AFTERGLOW := ACT_STATE.State.AFTERGLOW


static func in_act(state: int) -> bool:
	return state in [STATE_ACTIVE, STATE_CLIMAX, STATE_AFTERGLOW]


## The presented-body line; a pony with no body-change source adds none, so ordinary dialogue
## stays unchanged.
static func body_note(values: Dictionary) -> String:
	if not bool(values.get("form_source", false)):
		return ""
	var form_name := str(values.get("form_name", "")).strip_edges()
	var key := "own"
	if bool(values.get("form_borrowed", false)):
		key = "borrowed" if not form_name.is_empty() else "borrowed_unnamed"
	elif not form_name.is_empty():
		key = "own_named"
	var rows: Dictionary = DEFAULTS_DATA.prompts_block("act.note.body")
	return PROMPT_TEXT.render(rows.get(key, ""), {"name": form_name})


## Build the note from plain data, so the wording and precedence are testable without a scene.
static func note(values: Dictionary) -> String:
	var state := int(values.get("state", 0))
	var history := str(values.get("history", ""))
	var body := body_note(values)
	var rows: Dictionary = DEFAULTS_DATA.prompts_block("act.note")
	if not in_act(state):
		if bool(values.get("warm", false)):
			var warm := PROMPT_TEXT.render(rows.get("warm", ""), {})
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
		parts.append(PROMPT_TEXT.render(rows.get("afterglow", ""), {}))
		if not body.is_empty():
			parts.append(body)
		var beat := str(values.get("beat", ""))
		if not beat.is_empty():
			parts.append("- " + beat)
	else:
		parts.append(PROMPT_TEXT.render(rows.get("act", ""), {}))
		if not body.is_empty():
			parts.append(body)
		if not history.is_empty():
			parts.append(history)
	var relation := str(values.get("relation", ""))
	if not relation.is_empty():
		parts.append("- " + relation)
	var caress := _caress_note(values)
	if not caress.is_empty():
		parts.append(caress)
	return " ".join(parts)


static func _caress_note(values: Dictionary) -> String:
	var caressing := bool(values.get("caressing", false))
	var leaning := bool(values.get("leaning", false))
	var key := ""
	if caressing and leaning:
		key = "both_chest" if bool(values.get("missionary", false)) else "both_flank"
	elif caressing:
		key = "caressing_chest" if bool(values.get("missionary", false)) else "caressing_flank"
	elif leaning:
		key = "leaning"
	if key.is_empty():
		return ""
	var rows: Dictionary = DEFAULTS_DATA.prompts_block("act.note.caress")
	return PROMPT_TEXT.render(rows.get(key, ""), {})
