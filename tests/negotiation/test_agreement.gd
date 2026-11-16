extends SceneTree
## The Agreement package and its opaque handle: the frozen fields, the TTL, the exact hotkey
## match and the late-handle guard. Pure data; no service.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/negotiation/test_agreement.gd

const AGREEMENT := preload("res://mods/unfplap/negotiation/agreement.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
const CLEARANCE := preload("res://mods/unfplap/shared/clearance.gd")
const CONTEXT := preload("res://mods/unfplap/shared/context.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _option(pose := "missionary", source := "bed_side", bed: Variant = null,
		cuddle := false) -> POSE_OPTIONS.Option:
	var out := POSE_OPTIONS.Option.new()
	out.pose = pose
	out.source = source
	out.bed = bed
	out.cuddle = cuddle
	return out


func run() -> void:
	var bed := Node3D.new()
	var option := _option("missionary", "bed_side", bed)
	var package := AGREEMENT.Package.new()
	package.id = 7
	package.generation = 3
	package.pony = Node3D.new()
	package.pony_id = "rarity"
	package.option = option
	package.private = true
	package.clearance = CLEARANCE.evaluate(true, true, true)
	package.context = CONTEXT.build({"willingness": true})
	package.pose_profile_ok = true
	package.pose_source_ok = true
	package.accepted_at = 100.0
	package.ttl_s = AGREEMENT.AGREEMENT_TTL_S
	package.hold_token = "unfplap:negotiation:rarity"
	package.hold_old_wander = true
	package.trigger = AGREEMENT.Trigger.ANON_OFFER
	package.classifier_scope = "negotiation:mare_response:1:2"
	package.offer_line = "come here"
	package.answer = "accept"

	check(package.expires_at() == 220.0, "the Agreement TTL starts at acceptance")
	check(not package.expired(219.9), "the Agreement is live inside its TTL")
	check(package.expired(220.0), "the Agreement expires at its TTL")
	check(package.option_key() == option.key(), "the package key is the option key")
	check(package.clearance.ok(), "the frozen clearance is kept")
	check(package.context.willingness, "the frozen Context is kept")
	check(package.answer == "accept", "the frozen answer is kept")

	check(package.matches(package.pony, _option("missionary", "bed_side", bed)),
		"the same mare and exact option match")
	check(not package.matches(Node3D.new(), _option("missionary", "bed_side", bed)),
		"another mare does not match")
	check(not package.matches(package.pony, _option("missionary", "already_lying", bed)),
		"another source does not match")
	check(not package.matches(package.pony, _option("missionary", "bed_side", Node3D.new())),
		"another bed does not match")
	check(not package.matches(package.pony, _option("missionary", "bed_side", bed, true)),
		"the cuddle flag is part of the match")
	check(not package.matches(package.pony, _option("standing", "", null)),
		"another pose does not match")
	var empty := AGREEMENT.Package.new()
	check(not empty.matches(package.pony, option), "an empty package matches nothing")

	var handle := AGREEMENT.Handle.new()
	check(not handle.valid(), "a handle without an id or callback is invalid")
	handle.id = 7
	handle.generation = 3
	handle.pony = package.pony
	handle.option = option
	handle.cancel = func(_reason: String) -> bool: return true
	check(handle.valid(), "a full handle is valid")
	check(handle.trigger == AGREEMENT.Trigger.MARE_OFFER, "a new handle defaults to the mare route")

	package.pony.free()
	bed.free()
	print("AGREEMENT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
