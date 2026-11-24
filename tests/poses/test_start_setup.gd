extends "res://mods/unfplap/tests/support/suite.gd"
## The closed act-start vocabulary and the runtime setup dispatch: the shipped rows, the helper
## defaults, a refused retired name, and both adapters through the same dispatcher the real start
## uses.
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
	_check_retired_name()
	_check_dispatch()
	if failures == 0:
		print("START_SETUP_PASS")
	finish()


func _check_vocabulary() -> void:
	check(SPECS.START_SETUPS == ["bed_stand_up", "standing_place"],
		"the start setups are a closed vocabulary")
	var expected := {
		CATALOG.MISSIONARY: "bed_stand_up",
		CATALOG.STANDING: "standing_place",
		CATALOG.STANDING_TEST: "standing_place",
		CATALOG.STANDING_ORAL: "standing_place",
		CATALOG.BED_FACESIT: "bed_stand_up",
	}
	for id: String in SPECS.ids():
		check(expected.has(id), "the expected start table names %s" % id)
		if not expected.has(id):
			continue
		check(SPECS.start_setup(id) == expected[id], "%s has its start setup" % id)
	check(SPECS.start_setup("not_a_pose").is_empty(), "a missing row has no setup and fails closed")


## The retired bed-lying name is no longer part of the closed vocabulary: a synthetic row that
## still names it is refused by the spec validator and never enters the shipped table.
func _check_retired_name() -> void:
	var row: Dictionary = SPECS.spec(CATALOG.MISSIONARY).duplicate(true)
	row["id"] = "riding_probe"
	row["display_name"] = "Riding probe"
	row["start"] = {"setup": "bed_keep_lying"}
	var found := POSE_SPEC.errors("riding_probe", row, SPECS.SPECS)
	check(not found.is_empty(), "the retired bed_keep_lying setup is refused")
	var spec: Variant = POSE_SPEC.from_dict("riding_probe", row, SPECS.SPECS)
	check(spec == null, "the retired row does not build a typed spec")
	check(SPECS.spec("riding_probe").is_empty() and not SPECS.ids().has("riding_probe"),
		"the synthetic row stays out of the shipped table")


func _check_dispatch() -> void:
	var stand := _fixture()
	var stand_runtime: Node = stand["runtime"]
	var stand_pony: FakePony = stand["pony"]
	var stand_player: FakePlayer = stand["player"]
	check(bool(stand_runtime.act.start.setup.run("bed_stand_up")),
		"the dispatcher runs the bed_stand_up adapter")
	check(stand_player.stood == 1, "bed_stand_up stands Anon up")
	check(stand_pony.posture_requests == ["stand"], "bed_stand_up asks her to stand")
	_free_fixture(stand)

	var place := _fixture()
	var place_runtime: Node = place["runtime"]
	var place_pony: FakePony = place["pony"]
	var place_player: FakePlayer = place["player"]
	check(bool(place_runtime.act.start.setup.run("standing_place")),
		"the dispatcher runs the standing_place adapter")
	check(place_pony.posture_requests == ["stand"], "standing_place asks her to stand")
	check(place_player.stood == 0, "standing_place never stands Anon up")
	_free_fixture(place)

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
