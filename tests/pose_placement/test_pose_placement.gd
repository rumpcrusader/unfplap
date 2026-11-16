extends SceneTree
## Pure pose placement: the live feasibility facts for one chosen option.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/pose_placement/test_pose_placement.gd

const PLACEMENT := preload("res://mods/unfplap/shared/pose_placement.gd")
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
	var bed := PLACEMENT.Facts.new()
	bed.bed_known = true
	bed.bed_front_known = true
	check(PLACEMENT.check(CATALOG.MISSIONARY, "bed_side", bed).ok,
		"a known bed with a front spot places missionary")
	check(PLACEMENT.check(CATALOG.MISSIONARY, "already_lying", bed).ok,
		"the already-lying source places missionary")

	var no_bed := PLACEMENT.Facts.new()
	check(PLACEMENT.check(CATALOG.MISSIONARY, "bed_side", no_bed).reason ==
		PLACEMENT.REASON_BED, "a missing bed names the bed row")
	no_bed.bed_known = true
	check(PLACEMENT.check(CATALOG.MISSIONARY, "bed_side", no_bed).reason ==
		PLACEMENT.REASON_BED_FRONT, "a missing front spot names the front row")

	check(PLACEMENT.check(CATALOG.MISSIONARY, "", bed).reason == PLACEMENT.REASON_SOURCE,
		"an unsupported source fails")
	check(PLACEMENT.check(CATALOG.MISSIONARY, "cradle", bed).ok,
		"the cradle source is authored for missionary")

	var standing := PLACEMENT.Facts.new()
	check(not PLACEMENT.check(CATALOG.STANDING, "", standing).ok,
		"a held mare cannot take a standing pose")
	check(PLACEMENT.check(CATALOG.STANDING, "", standing).reason ==
		PLACEMENT.REASON_STANDING, "the standing row is named")
	standing.standing_free = true
	check(PLACEMENT.check(CATALOG.STANDING, "", standing).ok,
		"a free mare places standing")

	var stool := PLACEMENT.Facts.new()
	stool.standing_free = true
	stool.stool_ok = false
	check(PLACEMENT.check(CATALOG.STANDING, "", stool).reason == PLACEMENT.REASON_STOOL,
		"a stool shortage fails standing")

	var player := PLACEMENT.Facts.new()
	player.standing_free = true
	player.player_ready = false
	check(PLACEMENT.check(CATALOG.STANDING, "", player).reason == PLACEMENT.REASON_PLAYER,
		"Anon's position is a placement row")

	check(not PLACEMENT.check(CATALOG.STANDING_TEST, "", standing).ok,
		"an internal pose is not placeable")
	check(PLACEMENT.source_allowed(CATALOG.STANDING, ""), "standing accepts any source")
	check(not PLACEMENT.source_allowed(CATALOG.MISSIONARY, "flying"),
		"missionary rejects an unborn source")

	print("POSE_PLACEMENT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
