extends SceneTree
## The standing invitation cannot present a pony whose offer gate has closed.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_standing_presentation.gd

const PRESENTATION := preload("res://mods/unfplap/poses/standing_presentation.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const STRETCH := preload("res://mods/unfplap/poses/idle_stretch.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

const STRETCH_FAKE := "res://mods/unfplap/tests/fixtures/idle_stretch_fake.gd"

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
	var skeleton: Variant = null
	var hair_skeleton: Variant = null
	var body_scale := 0.66

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
	await _check_presentation_stretch(presentation, pony, facts)

	print("STANDING_PRESENTATION_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("STANDING_PRESENTATION_PASS")
	quit(0 if failures == 0 else 1)


## The accepted presentation attaches the external stretch after its turn, survives a live flag
## edit, and preserves the episode choice for the act.
func _check_presentation_stretch(presentation: Variant, pony: FakePony, facts: RefCounted) -> void:
	var before := bool(SETTINGS.idle_life_stretch.get_bool())
	var body := Skeleton3D.new()
	body.name = "Body"
	pony.add_child(body)
	pony.skeleton = body
	facts.pony_id = "rarity"
	facts.mod_enabled = func(_id: String) -> bool: return true
	facts.keep_chin_last = func() -> void: pass
	STRETCH.pose_path = STRETCH_FAKE
	SETTINGS.idle_life_stretch.set_bool(true)
	presentation.call("set_request_face", true)
	check(bool(presentation.call("present_standing")),
		"the accepted offer reaches the presentation")
	await process_frame
	var pose: Node = body.get_node_or_null("UnfplapPresentPose")
	var holder := _active_holder(body)
	check(pose != null and bool(pose.get("stretch")),
		"the presentation attaches in stretch mode")
	check(holder != null and pose != null and holder.get_index() + 1 == pose.get_index(),
		"the presentation holder runs before the presentation pose")
	check(pony.has_meta(STRETCH.META_IDLE) and pony.has_meta(STRETCH.META_SIDE),
		"the presentation rolls and stores the episode choice")
	SETTINGS.idle_life_stretch.set_bool(false)
	presentation.call("apply_live_settings")
	check(pose != null and not bool(pose.get("stretch")),
		"turning the flag off live restores the normal presentation")
	await process_frame
	check(_active_holder(body) == null, "the live-off presentation leaves no stretch modifier")
	SETTINGS.idle_life_stretch.set_bool(true)
	presentation.call("apply_live_settings")
	check(pose != null and bool(pose.get("stretch")),
		"turning the flag on live reinstalls the presentation stretch")
	var again := _active_holder(body)
	check(again != null and pose != null and again.get_index() + 1 == pose.get_index(),
		"the live-on holder keeps the presentation order")
	presentation.call("clear_presentation")
	check(pony.has_meta(STRETCH.META_IDLE) and pony.has_meta(STRETCH.META_SIDE),
		"clearing the presentation keeps the choice for the act")
	presentation.call("clear_stretch_offer")
	check(not pony.has_meta(STRETCH.META_IDLE) and not pony.has_meta(STRETCH.META_SIDE),
		"a cancelled offer drops the choice")
	SETTINGS.idle_life_stretch.set_bool(before)
	STRETCH.pose_path = STRETCH.POSE_PATH
	await process_frame
	root.remove_child(body)
	body.free()


func _active_holder(body: Skeleton3D) -> Node:
	for child: Node in body.get_children():
		if str(child.name) == "UnfplapIdleStretch" and not child.is_queued_for_deletion():
			return child
	return null
