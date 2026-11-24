extends RefCounted
## The negotiation model requests: the payload builders, the reply parsers and their instructions.

const CONTEXT := preload("res://mods/unfplap/shared/context.gd")
const DEFAULTS_DATA := preload("res://mods/unfplap/shared/defaults_data.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const PROMPT_TEXT := preload("res://mods/unfplap/shared/prompt_text.gd")

const MAX_REPLY_CHARS := 256
const MAX_TEXT_CHARS := 600


## The parsed model answer. `failed` marks a missing, malformed or untrustworthy reply, and
## `out_of_range` a clear offer whose index falls beyond the options sent.
class Reply:
	var answer := ""
	var option_index := -1
	var failed := false
	var out_of_range := false


## One model request for the Negotiation service. `kind` is `anon_offer`, `anon_decision` or
## `mare_response`. The bridge builds it; the director turns it into the classifier call.
class Request:
	var kind := ""
	var text := ""
	var line := ""
	var context: CONTEXT.Context = null
	var options: Array[POSE_OPTIONS.Option] = []


## The instruction for one request kind, or "" for an unknown kind.
static func system_for(kind: String) -> String:
	if kind != "anon_offer" and kind != "anon_decision" and kind != "mare_response":
		return ""
	var rows: Dictionary = DEFAULTS_DATA.prompts_block("classify")
	return PROMPT_TEXT.render(rows.get(kind, ""), {})


## The JSON payload for one request.
static func payload_for(request: Request) -> Dictionary:
	if request == null:
		return {}
	match request.kind:
		"anon_offer":
			return anon_offer_payload(request.text, request.options, request.context)
		"anon_decision":
			return anon_decision_payload(request.text, request.line)
		"mare_response":
			return mare_response_payload(request.text,
				request.options[0] if not request.options.is_empty() else null, request.context)
	return {}


## Parse one reply through the request kind's parser. An unknown kind is a failure.
static func parse(kind: String, reply: String, error: String, option_count: int) -> Reply:
	match kind:
		"anon_offer":
			return parse_anon_offer(reply, error, option_count)
		"anon_decision":
			return parse_anon_decision(reply, error)
		"mare_response":
			return parse_mare_response(reply, error)
	var out := Reply.new()
	out.answer = "no_offer"
	out.failed = true
	return out


static func anon_offer_payload(text: String, options: Array[POSE_OPTIONS.Option],
		context: CONTEXT.Context) -> Dictionary:
	var rows: Array = []
	for index: int in range(options.size()):
		rows.append(_option_row(index, options[index]))
	return {
		"player_line": text.strip_edges(),
		"options": rows,
		"context": context.prompt_facts() if context != null else {},
	}


static func anon_decision_payload(text: String, offer_line: String) -> Dictionary:
	return {"offer": offer_line.strip_edges(), "player_reply": text.strip_edges()}


static func mare_response_payload(text: String, option: POSE_OPTIONS.Option,
		context: CONTEXT.Context) -> Dictionary:
	var payload := {
		"player_offer": text.strip_edges(),
		"option": _option_row(0, option) if option != null else {},
	}
	if context != null:
		payload["context"] = context.prompt_facts()
	return payload


## Parse an Anon-offer reply. A clear offer keeps the raw index even when it lies beyond the
## options sent, so the service can validate it; a bad index is a failure.
static func parse_anon_offer(reply: String, error: String, option_count: int) -> Reply:
	var out := Reply.new()
	out.answer = "no_offer"
	var parsed := _parse(reply, error)
	if parsed.is_empty():
		out.failed = true
		return out
	if not parsed.get("offer") is bool:
		out.failed = true
		return out
	if not bool(parsed.get("offer", false)):
		return out
	if not _is_int(parsed.get("option")):
		out.failed = true
		return out
	var index := int(parsed.get("option"))
	out.answer = "accept"
	out.option_index = index
	out.out_of_range = index < 0 or index >= option_count
	return out


## Parse the Anon decision. A malformed reply is a failure; a clear "unclear" is a refusal, not
## a failure.
static func parse_anon_decision(reply: String, error: String) -> Reply:
	var out := Reply.new()
	out.answer = "refuse"
	var parsed := _parse(reply, error)
	if parsed.is_empty():
		out.failed = true
		return out
	var answer := _answer_text(parsed.get("answer", ""))
	if answer.is_empty():
		out.failed = true
		return out
	if answer != "unclear":
		out.answer = answer
	return out


## Parse the Mare response. A reasoning failure is `refuse` with `failed`, so the caller ends the
## negotiation without the offer cooldown.
static func parse_mare_response(reply: String, error: String) -> Reply:
	var out := Reply.new()
	out.answer = "refuse"
	var parsed := _parse(reply, error)
	if parsed.is_empty():
		out.failed = true
		return out
	var answer := _answer_text(parsed.get("answer", ""))
	if answer.is_empty() or answer == "unclear":
		out.failed = true
		return out
	out.answer = answer
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


static func _answer_text(value: Variant) -> String:
	var text := str(value).strip_edges().to_lower()
	if text in ["accept", "accepted", "yes"]:
		return "accept"
	if text in ["refuse", "refused", "decline", "declined", "no"]:
		return "refuse"
	if text in ["counter_offer", "counter", "not_here", "not here"]:
		return "counter_offer"
	if text in ["unclear", "ambiguous"]:
		return "unclear"
	return ""


static func _parse(reply: String, error: String) -> Dictionary:
	if not error.is_empty():
		return {}
	var text := reply.strip_edges()
	if text.is_empty() or text.length() > MAX_REPLY_CHARS:
		return {}
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {}
	var parsed: Variant = parser.data
	return parsed if parsed is Dictionary else {}


static func _is_int(value: Variant) -> bool:
	return value is int or value is float
