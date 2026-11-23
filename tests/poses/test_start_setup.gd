extends "res://mods/unfplap/tests/support/suite.gd"
## The closed act-start vocabulary and the runtime setup dispatch: the shipped rows, the helper
## defaults, a synthetic `auto`/`bed_keep_lying` row, and the two bed adapters through the same
## dispatcher the real start uses.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_start_setup.gd

const WORLD := preload("res://mods/unfplap/world/api.gd")
const SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const POSE_SPEC := preload("res://mods/unfplap/poses/pose_spec.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")



class FakePony extends Node3D:
	var posture: Variant = null
	var posture_requests: Array[String] = []

	func request_posture(name: String) -> bool:
		posture_requests.append(name)
		return true


class FakePlayer extends Node3D:
	var stood := 0

	func force_stand_up() -> void:
		stood += 1


class FakeMain extends Node:
	var player: FakePlayer = null


func run() -> void:
	_check_vocabulary()
	_check_synthetic_row()
	_check_dispatch()
	if failures == 0:
		print("START_SETUP_PASS")
	finish()


func _check_vocabulary() -> void:
	check(SPECS.START_MODES == ["key", "auto"], "the start modes are a closed vocabulary")
	check(SPECS.START_SETUPS == ["bed_stand_up", "bed_keep_lying", "standing_place"],
		"the start setups are a closed vocabulary")
	var expected := {
		CATALOG.MISSIONARY: ["key", "bed_stand_up"],
		CATALOG.STANDING: ["key", "standing_place"],
		CATALOG.STANDING_TEST: ["key", "standing_place"],
		CATALOG.STANDING_ORAL: ["key", "standing_place"],
		CATALOG.BED_FACESIT: ["key", "bed_stand_up"],
	}
	for id: String in SPECS.ids():
		check(expected.has(id), "the expected start table names %s" % id)
		if not expected.has(id):
			continue
		check(SPECS.start_mode(id) == expected[id][0], "%s has its start mode" % id)
		check(SPECS.start_setup(id) == expected[id][1], "%s has its start setup" % id)
	check(SPECS.start_mode("not_a_pose") == "key", "a missing row claims the safe key mode")
	check(SPECS.start_setup("not_a_pose").is_empty(), "a missing row has no setup and fails closed")


## The riding pose is the first intended bed_keep_lying consumer. The row is synthetic here: it
## validates as data, and it never enters the shipped table or the catalog.
func _check_synthetic_row() -> void:
	var row: Dictionary = SPECS.spec(CATALOG.MISSIONARY).duplicate(true)
	row["id"] = "riding_probe"
	row["display_name"] = "Riding probe"
	row["start"] = {"mode": "auto", "setup": "bed_keep_lying"}
	var found := POSE_SPEC.errors("riding_probe", row, SPECS.SPECS)
	check(found.is_empty(), "the synthetic auto/bed_keep_lying row validates: %s" % str(found))
	var spec: Variant = POSE_SPEC.from_dict("riding_probe", row, SPECS.SPECS)
	check(spec != null, "the synthetic row builds a typed spec")
	check(spec != null and spec.start_mode == "auto" and spec.start_setup == "bed_keep_lying",
		"the typed spec carries the synthetic start block")
	check(SPECS.spec("riding_probe").is_empty() and not SPECS.ids().has("riding_probe"),
		"the synthetic row stays out of the shipped table")


func _check_dispatch() -> void:
	var keep := _fixture()
	var keep_runtime: Node = keep["runtime"]
	var keep_pony: FakePony = keep["pony"]
	var keep_player: FakePlayer = keep["player"]
	check(bool(keep_runtime.act.start.setup.run("bed_keep_lying")),
		"the dispatcher runs the bed_keep_lying adapter")
	check(keep_pony.posture_requests == ["stand"],
		"bed_keep_lying gives the authored body her pose")
	check(keep_player.stood == 0, "bed_keep_lying never stands Anon up")
	_free_fixture(keep)

	var stand := _fixture()
	var stand_runtime: Node = stand["runtime"]
	var stand_pony: FakePony = stand["pony"]
	var stand_player: FakePlayer = stand["player"]
	check(bool(stand_runtime.act.start.setup.run("bed_stand_up")),
		"the dispatcher runs the bed_stand_up adapter")
	check(stand_player.stood == 1, "bed_stand_up stands Anon up")
	check(stand_pony.posture_requests == ["stand"], "bed_stand_up asks her to stand")
	_free_fixture(stand)

	var unknown := _fixture()
	var unknown_runtime: Node = unknown["runtime"]
	var unknown_pony: FakePony = unknown["pony"]
	var unknown_player: FakePlayer = unknown["player"]
	check(not bool(unknown_runtime.act.start.setup.run("bench_place")),
		"an unknown setup aborts the start")
	check(unknown_pony.posture_requests.is_empty() and unknown_player.stood == 0,
		"an unknown setup touches nobody")
	_free_fixture(unknown)


func _fixture() -> Dictionary:
	var runtime: Node = RUNTIME.new()
	var pony := FakePony.new()
	pony.posture = Node.new()
	var main := FakeMain.new()
	var player := FakePlayer.new()
	main.player = player
	WORLD.bind_player(main.player)
	runtime.pony = pony
	runtime.act.bed = Node3D.new()
	runtime.act.source = "bed_side"
	root.add_child(runtime)
	return {"runtime": runtime, "pony": pony, "main": main, "player": player}


func _free_fixture(made: Dictionary) -> void:
	var runtime: Node = made["runtime"]
	var bed: Node3D = runtime.act.bed
	var pony: FakePony = made["pony"]
	var main: FakeMain = made["main"]
	var player: FakePlayer = made["player"]
	var posture: Node = pony.posture
	runtime.free()
	pony.free()
	main.free()
	player.free()
	bed.free()
	posture.free()
