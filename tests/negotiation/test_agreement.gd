extends "res://mods/unfplap/tests/support/suite.gd"
## The Agreement package and its opaque handle: the frozen fields, the TTL, the exact hotkey
## match and the late-handle guard. Pure data; no service.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/negotiation/test_agreement.gd

const AGREEMENT := preload("res://mods/unfplap/shared/agreement.gd")
const POSE_OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")



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
	package.pose_profile_ok = true
	package.pose_source_ok = true
	package.accepted_at = 100.0
	package.ttl_s = AGREEMENT.AGREEMENT_TTL_S
	package.trigger = AGREEMENT.Trigger.ANON_OFFER

	var expires := package.accepted_at + package.ttl_s
	check(package.expires_at() == expires, "the Agreement TTL starts at acceptance")
	check(not package.expired(expires - 0.1), "the Agreement is live inside its TTL")
	check(package.expired(expires), "the Agreement expires at its TTL")
	check(package.option_key() == option.key(), "the package key is the option key")

	check(package.matches(package.pony, _option("missionary", "bed_side", bed)),
		"the same mare and exact option match")
	var other_mare := Node3D.new()
	check(not package.matches(other_mare, _option("missionary", "bed_side", bed)),
		"another mare does not match")
	check(not package.matches(package.pony, _option("missionary", "already_lying", bed)),
		"another source does not match")
	var other_bed := Node3D.new()
	check(not package.matches(package.pony, _option("missionary", "bed_side", other_bed)),
		"another bed does not match")
	check(not package.matches(package.pony, _option("missionary", "bed_side", bed, true)),
		"the cuddle flag is part of the match")
	check(not package.matches(package.pony, _option("standing", "", null)),
		"another pose does not match")
	var empty := AGREEMENT.Package.new()
	check(not empty.matches(package.pony, option), "an empty package matches nothing")

	var handle := AGREEMENT.Handle.new()
	check(not handle.valid(), "a handle without an id or generation is invalid")
	handle.id = 7
	check(not handle.valid(), "a handle without a generation is invalid")
	handle.generation = 3
	handle.pony = package.pony
	handle.option = option
	check(handle.valid(), "a formed handle is valid")

	package.pony.free()
	bed.free()
	other_mare.free()
	other_bed.free()
	finish()
