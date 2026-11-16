extends SceneTree
## Pure pose options: capability plus placement produces the offerable list.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/pose_options/test_pose_options.gd

const OPTIONS := preload("res://mods/unfplap/shared/pose_options.gd")
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


func run() -> void:
	var bed := Node3D.new()
	var other := Node3D.new()

	var empty := OPTIONS.build("human", "desktop", OPTIONS.Placement.new())
	check(empty.is_empty(), "an empty placement has no options")
	check(OPTIONS.describe(empty) == "none", "an empty list renders none")

	var cuddle := OPTIONS.Placement.new()
	cuddle.cuddle = true
	cuddle.cuddle_bed = bed
	cuddle.bed = bed
	cuddle.bed_front = Vector3(1.0, 0.0, 0.0)
	cuddle.standing_free = true
	var list := OPTIONS.build("human", "desktop", cuddle)
	check(list.size() == 3, "a full placement offers cuddle, bed and standing")
	check(list[0].pose == CATALOG.MISSIONARY and list[0].cuddle, "the cuddle option is first")
	check(list[0].source == OPTIONS.SOURCE_BED_SIDE, "a human cuddle uses the bed side")
	check(list[0].bed == bed, "the cuddle option carries the bed under her")
	check(not list[1].cuddle and list[1].bed == bed, "the bed option is a separate walk")
	check(list[2].pose == CATALOG.STANDING and list[2].bed == null, "the standing option is last")
	check(list[2].source.is_empty(), "a standing option has no bed source")

	var pony := OPTIONS.Placement.new()
	pony.cuddle = true
	pony.cuddle_bed = bed
	pony.standing_free = true
	var pony_list := OPTIONS.build("pony", "vr", pony)
	check(pony_list.size() == 1, "a pony form only offers the supported standing pose")
	check(pony_list[0].pose == CATALOG.STANDING, "the pony keeps standing")

	var no_front := OPTIONS.Placement.new()
	no_front.bed = bed
	no_front.bed_front = null
	check(OPTIONS.build("human", "desktop", no_front).is_empty(),
		"a bed without a front spot is not an option")

	var vr := OPTIONS.Placement.new()
	vr.bed = bed
	vr.bed_front = Vector3(1.0, 0.0, 0.0)
	check(OPTIONS.build("human", "vr", vr).is_empty(),
		"missionary is not authored for VR")

	var found := OPTIONS.find(list, CATALOG.MISSIONARY, OPTIONS.SOURCE_BED_SIDE, bed, false)
	check(found == list[1], "find returns the exact bed option")
	check(OPTIONS.has(list, CATALOG.MISSIONARY, OPTIONS.SOURCE_BED_SIDE, bed, true),
		"has matches the cuddle flag")
	check(not OPTIONS.has(list, CATALOG.MISSIONARY, OPTIONS.SOURCE_BED_SIDE, other),
		"another bed is not a match")
	check(list[1].key().contains(OPTIONS.SOURCE_BED_SIDE), "the key names the source")
	check(OPTIONS.same_bed(null, null), "two empty beds match")
	check(not OPTIONS.same_bed(bed, null), "one empty bed does not match")

	bed.free()
	other.free()

	print("POSE_OPTIONS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
