extends RefCounted
## Wording for a proactive ask: the `ask` prompts say the words; this file picks the pose, the
## privacy branch and the heat line.
## Notes arrive as strings, so this file reads no Settings, scene or game state.

const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const DEFAULTS_DATA := preload("res://mods/unfplap/shared/defaults_data.gd")
const FACTS := preload("res://mods/unfplap/initiation/facts.gd")
const POLICY := preload("res://mods/unfplap/initiation/policy.gd")
const PROMPT_TEXT := preload("res://mods/unfplap/shared/prompt_text.gd")


## The observed-situation prompt that opens the ask.
static func ask_context(request: FACTS.Request) -> String:
	return _build("ask.context", _context_opening(request), _context_mode(request), request)


## The generated-intent purpose for the ask line.
static func ask_purpose(request: FACTS.Request) -> String:
	return _build("ask.purpose", _purpose_opening(request), _purpose_mode(request), request)


## World-context text: she has decided to ask.
static func situation_ask(request: FACTS.Request) -> String:
	return PROMPT_TEXT.render(DEFAULTS_DATA.prompts_block("ask.situation"), {
		"opening": _situation_opening(request),
		"crowd": "" if request.private else _variant("ask", "crowd"),
	})


## The heat sentence appended to both ask forms. Empty outside heat.
static func heat_line(heat: bool) -> String:
	return _variant("ask", "heat") if heat else ""


## One ask composite: the branch opening and mode, with the notes and the heat line.
static func _build(id: String, opening: String, mode: String,
		request: FACTS.Request) -> String:
	return PROMPT_TEXT.render(DEFAULTS_DATA.prompts_block(id), {
		"opening": opening,
		"relation": request.relation_note,
		"mode": mode,
		"heat": heat_line(request.heat),
		"history": request.history_note,
	})


static func _context_opening(request: FACTS.Request) -> String:
	var key := "context_standing"
	if request.cuddle:
		key = "context_cuddle"
	elif request.pose == CATALOG.MISSIONARY:
		key = "context_bed"
	return _variant("ask.openings", key)


static func _purpose_opening(request: FACTS.Request) -> String:
	var key := "purpose_default"
	if request.cuddle:
		key = "purpose_cuddle"
	elif request.pose == CATALOG.MISSIONARY:
		key = "purpose_bed"
	elif request.pose == CATALOG.STANDING:
		key = "purpose_standing"
	return _variant("ask.openings", key)


static func _situation_opening(request: FACTS.Request) -> String:
	var key := "situation_default"
	if request.cuddle:
		key = "situation_cuddle"
	elif request.pose == CATALOG.MISSIONARY:
		key = "situation_bed"
	elif request.pose == CATALOG.STANDING:
		key = "situation_standing"
	return _variant("ask.openings", key)


static func _context_mode(request: FACTS.Request) -> String:
	if not _free(request):
		return _variant("ask.modes", "context_public")
	if request.pose == CATALOG.STANDING:
		return _variant("ask.modes", "context_free_standing")
	if request.pose == CATALOG.MISSIONARY:
		return _variant("ask.modes", "context_free_bed")
	return _variant("ask.modes", "context_free")


static func _purpose_mode(request: FACTS.Request) -> String:
	if not _free(request):
		return _variant("ask.modes", "purpose_public")
	if request.pose == CATALOG.STANDING:
		return _variant("ask.modes", "purpose_free_standing")
	if request.pose == CATALOG.MISSIONARY:
		return _variant("ask.modes", "purpose_free_bed")
	return _variant("ask.modes", "purpose_free")


static func _variant(group: String, key: String) -> String:
	var rows: Dictionary = DEFAULTS_DATA.prompts_block(group)
	return PROMPT_TEXT.render(str(rows.get(key, "")), {})


## The single free/indirect decision. Every builder above branches on this once.
static func _free(request: FACTS.Request) -> bool:
	return POLICY.wording_mode(request.private) == POLICY.MODE_FREE
