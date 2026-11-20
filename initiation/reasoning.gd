extends RefCounted
## Mare Initiation Reasoning: whether to offer, and which available option.
## Pure instruction, payload and parser; the adapter owns the model call.
## Context and the placeable options are the only inputs; no service, scene, clock or file.
## Contract: `docs/initiation.md` (`## Reasoning`).

const CONTEXT := preload("res://mods/unfplap/shared/context.gd")
const DEFAULTS_DATA := preload("res://mods/unfplap/shared/defaults_data.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const PROMPT_TEXT := preload("res://mods/unfplap/shared/prompt_text.gd")

const MAX_REPLY_CHARS := 256


## The instruction. The answer is one boolean and one option index from the supplied list.
static func instruction() -> String:
	var rows: Dictionary = DEFAULTS_DATA.prompts_block("classify")
	return PROMPT_TEXT.render(rows.get("mare_offer", ""), {})


## The parsed reasoning answer. `failed` marks a missing, malformed or untrustworthy reply.
class Decision:
	var offer := false
	var option_index := -1
	var failed := false


## The payload: the Context facts plus the option list, each row indexed.
static func payload(context: CONTEXT.Context, options: Array[POSE_OPTIONS.Option]) -> Dictionary:
	var rows: Array = []
	for index: int in range(options.size()):
		rows.append(_option_row(index, options[index]))
	return {
		"context": context.prompt_facts() if context != null else {},
		"options": rows,
	}


## Parse a reasoning reply. Only a clear offer with an in-range option is an offer; an unclear or
## out-of-range reply is a no-offer, and an unusable reply is `failed`.
static func parse(reply: String, error: String, option_count: int) -> Decision:
	var out := Decision.new()
	if not error.is_empty():
		out.failed = true
		return out
	var text := reply.strip_edges()
	if text.is_empty() or text.length() > MAX_REPLY_CHARS:
		out.failed = true
		return out
	var parser := JSON.new()
	if parser.parse(text) != OK:
		out.failed = true
		return out
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		out.failed = true
		return out
	var row := parsed as Dictionary
	if not row.get("offer") is bool:
		out.failed = true
		return out
	if not bool(row.get("offer", false)):
		return out
	var value: Variant = row.get("option")
	if not (value is int or value is float):
		out.failed = true
		return out
	var index := int(value)
	if index < 0 or index >= option_count:
		return out
	out.offer = true
	out.option_index = index
	return out


static func _option_row(index: int, option: POSE_OPTIONS.Option) -> Dictionary:
	var pose := ""
	var source := ""
	var cuddle := false
	var bed := "none"
	if option != null:
		pose = option.pose
		source = option.source
		cuddle = option.cuddle
		if is_instance_valid(option.bed):
			bed = str((option.bed as Node).name)
	return {
		"index": index,
		"pose": pose,
		"source": source,
		"bed": bed,
		"cuddle": cuddle,
	}
