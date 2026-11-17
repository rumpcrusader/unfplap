extends SceneTree
## The Mare Initiation Reasoning: the payload shape and the reply parser. Pure strings; no model.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/initiation/test_reasoning.gd

const REASONING := preload("res://mods/unfplap/initiation/reasoning.gd")
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


func _option(pose: String, source := "", bed: Variant = null, cuddle := false) -> POSE_OPTIONS.Option:
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
		_option(CATALOG.MISSIONARY, "bed_side", bed, true),
		_option(CATALOG.STANDING),
	]
	var context := CONTEXT.build({"willingness": true, "heat": true, "history": {"hurt": 1}})
	var payload := REASONING.payload(context, options)
	var rows: Array = payload.get("options", [])
	check(rows.size() == 2, "the payload carries every option")
	check(int((rows[0] as Dictionary).get("index", -1)) == 0, "the first option is indexed")
	check(str((rows[0] as Dictionary).get("bed", "")) == "GuestBed",
		"the option names its bed")
	check((rows[0] as Dictionary).get("cuddle") == true, "the option keeps its cuddle flag")
	check((payload.get("context", {}) as Dictionary).get("heat") == true,
		"the payload carries Context")
	check((payload.get("context", {}) as Dictionary).get("willing") == true,
		"the payload carries willingness")
	check(REASONING.payload(null, []).get("context") == {},
		"a missing context is an empty payload")

	var decision := REASONING.parse("{\"offer\":true,\"option\":1}", "", 2)
	check(decision.offer and decision.option_index == 1 and not decision.failed,
		"a clear offer with an in-range option parses")
	decision = REASONING.parse("{\"offer\":false}", "", 2)
	check(not decision.offer and not decision.failed, "a no-offer reply parses")
	decision = REASONING.parse("{\"offer\":true,\"option\":4}", "", 2)
	check(not decision.offer and not decision.failed, "an out-of-list option is no offer")
	decision = REASONING.parse("{\"offer\":true}", "", 2)
	check(decision.failed, "a missing option is a failure")
	decision = REASONING.parse("{\"option\":0}", "", 2)
	check(decision.failed, "a missing offer flag is a failure")
	decision = REASONING.parse("not json", "", 2)
	check(decision.failed and not decision.offer, "a malformed reply is a failure")
	decision = REASONING.parse("{\"offer\":true,\"option\":0}", "timeout", 2)
	check(decision.failed, "a provider error is a failure")
	check(REASONING.INSTRUCTION.contains("offer"), "the instruction names the offer answer")
	check(REASONING.INSTRUCTION.contains("Never invent"), "the instruction pins the option list")
	bed.free()
	print("INITIATION_REASONING_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
