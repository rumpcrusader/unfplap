extends SceneTree
## The standing invitation cannot present a pony whose offer gate has closed.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_standing_presentation.gd

const PRESENTATION := preload("res://mods/unfplap/standing_presentation.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility.gd")

var failures := 0
var checks := 0


class FakeIdentity extends RefCounted:
	var id := "rarity"
	var display_name := "Rarity"
	var filly := false
	var stallion := false


class FakePony extends Node3D:
	var identity: Variant
	var sleeping := false

	func is_held() -> bool:
		return false


class FakeMain extends Node:
	var eligibility: Variant
	var player: Node3D

	func camera() -> Camera3D:
		return null


class FakeRuntime extends Node:
	var state := 0
	var pony: Node3D
	var main: Node
	var offer_ok := false
	var _pose_cfg: Dictionary = {}

	func _cuddle_active() -> bool:
		return false

	func _free_of_affection() -> bool:
		return true

	func _pause_face_turn(_on: bool) -> void:
		pass

	func _restore_face_turn() -> void:
		pass

	func _now_s() -> float:
		return 0.0

	func can_offer(_pose: String, _source: String, _bed: Variant, _forced := false) -> bool:
		return offer_ok


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var main := FakeMain.new()
	root.add_child(main)
	main.eligibility = ELIGIBILITY.new()
	main.eligibility.setup(main)
	main.player = Node3D.new()
	root.add_child(main.player)

	var pony := FakePony.new()
	pony.identity = FakeIdentity.new()
	root.add_child(pony)
	var runtime := FakeRuntime.new()
	runtime.pony = pony
	runtime.main = main
	root.add_child(runtime)

	var presentation: Variant = PRESENTATION.new(runtime)
	check(not bool(presentation.call("present_standing")),
		"a closed offer gate refuses to present")

	runtime.offer_ok = true
	check(bool(presentation.call("present_standing")),
		"an open offer gate reaches the presentation path")
	presentation.call("clear_presentation")
	check(not bool(presentation.call("presentation_active")),
		"the fake presentation clears without leaving a pose")

	print("STANDING_PRESENTATION_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("STANDING_PRESENTATION_PASS")
	quit(0 if failures == 0 else 1)
