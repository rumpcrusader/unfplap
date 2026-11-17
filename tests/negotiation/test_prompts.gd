extends SceneTree
## The negotiation model requests: payload shape and reply parsing for the Anon offer, the Anon
## decision and the Mare response. Pure strings; no live model.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/negotiation/test_prompts.gd

const PROMPTS := preload("res://mods/unfplap/negotiation/prompts.gd")
const CONTEXT := preload("res://mods/unfplap/shared/context.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _option(pose: String, source: String, bed: Variant = null, cuddle := false) -> POSE_OPTIONS.Option:
	var out := POSE_OPTIONS.Option.new()
	out.pose = pose
	out.source = source
	out.bed = bed
	out.cuddle = cuddle
	return out


func run() -> void:
	var bed := Node3D.new()
	bed.name = "GuestBed"
	var options: Array[POSE_OPTIONS.Option] = [
		_option(CATALOG.MISSIONARY, "bed_side", bed),
		_option(CATALOG.STANDING, ""),
	]
	var context := CONTEXT.build({"willingness": true, "private": true, "heat": true})
	var payload := PROMPTS.anon_offer_payload("take me to bed", options, context)
	check(str(payload.get("player_line", "")) == "take me to bed", "the payload carries the line")
	var rows: Array = payload.get("options", [])
	check(rows.size() == 2, "the payload carries every option")
	check(int((rows[0] as Dictionary).get("index", -1)) == 0, "the first option is indexed")
	check(str((rows[0] as Dictionary).get("pose", "")) == CATALOG.MISSIONARY,
		"the first option names its pose")
	check(str((rows[0] as Dictionary).get("bed", "")) == "GuestBed",
		"the first option names its bed")
	check((rows[1] as Dictionary).get("cuddle") == false, "the standing option is not a cuddle")
	check((payload.get("context", {}) as Dictionary).get("heat") == true,
		"the payload carries Context")

	var decision_payload := PROMPTS.anon_decision_payload("yes", "come here")
	check(decision_payload.get("offer") == "come here", "the decision payload carries the offer")
	check(decision_payload.get("player_reply") == "yes", "the decision payload carries the reply")

	var mare_payload := PROMPTS.mare_response_payload("want to?", options[1], context)
	check(mare_payload.get("player_offer") == "want to?", "the mare payload carries the offer")
	check((mare_payload.get("option", {}) as Dictionary).get("pose") == CATALOG.STANDING,
		"the mare payload carries the option")
	check((mare_payload.get("context", {}) as Dictionary).get("willing") == true,
		"the mare payload carries Context")

	var anon := PROMPTS.parse_anon_offer("{\"offer\":true,\"option\":1}", "", 2)
	check(anon.answer == "accept" and anon.option_index == 1 and not anon.failed \
		and not anon.out_of_range, "a clear offer with an in-range option parses")
	anon = PROMPTS.parse_anon_offer("{\"offer\":false}", "", 2)
	check(anon.answer == "no_offer" and not anon.failed, "a no-offer reply parses")
	anon = PROMPTS.parse_anon_offer("{\"offer\":true,\"option\":3}", "", 2)
	check(anon.answer == "accept" and anon.option_index == 3 and anon.out_of_range \
		and not anon.failed, "an out-of-list option keeps the index and marks the range")
	anon = PROMPTS.parse_anon_offer("{\"offer\":true,\"option\":-1}", "", 2)
	check(anon.out_of_range, "a negative option is out of range")
	anon = PROMPTS.parse_anon_offer("{\"offer\":true}", "", 2)
	check(anon.failed, "a missing option is a failure")
	anon = PROMPTS.parse_anon_offer("not json", "", 2)
	check(anon.failed and anon.answer == "no_offer", "a malformed offer reply is no offer")
	anon = PROMPTS.parse_anon_offer("{\"offer\":true,\"option\":0}", "timeout", 2)
	check(anon.failed, "a provider error is a failure")

	var answer := PROMPTS.parse_anon_decision("{\"answer\":\"accept\"}", "")
	check(answer.answer == "accept" and not answer.failed, "an accept parses")
	answer = PROMPTS.parse_anon_decision("{\"answer\":\"counter_offer\"}", "")
	check(answer.answer == "counter_offer", "a counter-offer parses")
	answer = PROMPTS.parse_anon_decision("{\"answer\":\"unclear\"}", "")
	check(answer.answer == "refuse" and not answer.failed, "an ambiguous answer is a refusal")
	answer = PROMPTS.parse_anon_decision("{\"answer\":\"yes\"}", "")
	check(answer.answer == "accept", "a clear yes normalizes")
	answer = PROMPTS.parse_anon_decision("nope", "")
	check(answer.answer == "refuse" and answer.failed, "a malformed answer is a failure")
	answer = PROMPTS.parse_anon_decision("{\"answer\":\"accept\"}", "refused")
	check(answer.failed, "a provider refusal is a failure")

	var response := PROMPTS.parse_mare_response("{\"answer\":\"refuse\"}", "")
	check(response.answer == "refuse" and not response.failed, "a mare refusal parses")
	response = PROMPTS.parse_mare_response("{\"answer\":\"not here\"}", "")
	check(response.answer == "counter_offer", "a mare counter-offer parses")
	response = PROMPTS.parse_mare_response("{\"answer\":\"unclear\"}", "")
	check(response.answer == "refuse" and response.failed, "an unclear mare answer is a failure")

	check(PROMPTS.ANON_OFFER_INSTRUCTION.contains("\"offer\""), "the classifier asks for JSON")
	check(PROMPTS.MARE_RESPONSE_INSTRUCTION.contains("counter_offer"),
		"the mare response names the counter-offer")

	var request := PROMPTS.Request.new()
	request.kind = "anon_offer"
	request.text = "take me to bed"
	request.context = context
	request.options = options
	check(PROMPTS.system_for(request.kind) == PROMPTS.ANON_OFFER_INSTRUCTION,
		"the Anon offer instruction is dispatched")
	var dispatch := PROMPTS.payload_for(request)
	check(str(dispatch.get("player_line", "")) == "take me to bed",
		"the Anon offer payload is dispatched")
	request.kind = "anon_decision"
	request.text = "yes"
	request.line = "come here"
	check(PROMPTS.payload_for(request).get("offer") == "come here",
		"the Anon decision payload is dispatched")
	request.kind = "mare_response"
	request.options = [options[1]]
	check((PROMPTS.payload_for(request).get("option", {}) as Dictionary).get("pose")
		== CATALOG.STANDING, "the Mare response payload is dispatched")
	check(PROMPTS.system_for("nonsense").is_empty(), "an unknown kind has no instruction")
	check(PROMPTS.payload_for(null).is_empty(), "a missing request has no payload")
	var unknown := PROMPTS.parse("nonsense", "{}", "", 0)
	check(unknown.failed and unknown.answer == "no_offer", "an unknown parse kind fails")
	var parsed := PROMPTS.parse("anon_offer", "{\"offer\":true,\"option\":1}", "", 2)
	check(parsed.answer == "accept" and parsed.option_index == 1,
		"the offer parse is dispatched")
	var overflow := PROMPTS.parse("anon_offer", "{\"offer\":true,\"option\":4}", "", 2)
	check(overflow.out_of_range, "the dispatched offer parse keeps the range marker")
	check(PROMPTS.parse("anon_decision", "{\"answer\":\"refuse\"}", "", 0).answer == "refuse",
		"the decision parse is dispatched")
	check(PROMPTS.parse("mare_response", "{\"answer\":\"counter_offer\"}", "", 0).answer
		== "counter_offer", "the mare response parse is dispatched")
	bed.free()
	print("NEGOTIATION_PROMPTS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
