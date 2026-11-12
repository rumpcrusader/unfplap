extends SceneTree
## The standing invitation cannot present a pony whose offer gate has closed.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_standing_presentation.gd

const PRESENTATION := preload("res://mods/unfplap/standing_presentation.gd")
const ACT_FACTS := preload("res://mods/unfplap/act_facts.gd")
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

	var offer_ok := {"value": false}
	var facts: RefCounted = ACT_FACTS.new()
	facts.main = main
	facts.pony = pony
	facts.pose_id = "standing"
	facts.cuddle_active = func() -> bool: return false
	facts.free_of_affection = func() -> bool: return true
	facts.can_offer = func(_pose: String, _source: String, _bed: Variant) -> bool:
		return bool(offer_ok["value"])
	facts.pause_face_turn = func(_force: bool) -> void: pass
	facts.restore_face_turn = func() -> void: pass
	facts.now = func() -> float: return 0.0

	var presentation: Variant = PRESENTATION.new(facts)
	check(not bool(presentation.call("present_standing")),
		"a closed offer gate refuses to present")

	offer_ok["value"] = true
	check(bool(presentation.call("present_standing")),
		"an open offer gate reaches the presentation path")
	presentation.call("clear_presentation")
	check(not bool(presentation.call("presentation_active")),
		"the fake presentation clears without leaving a pose")

	print("STANDING_PRESENTATION_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("STANDING_PRESENTATION_PASS")
	quit(0 if failures == 0 else 1)
