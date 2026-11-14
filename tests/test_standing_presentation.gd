extends SceneTree
## The standing invitation: the accepted offer presents even with the pre-turn offer gate closed,
## the navigator's face_point owns the turn away, the pose attaches only after the away settle,
## a blocked turn aborts without snapping, and the external stretch follows the turn.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_standing_presentation.gd

const PRESENTATION := preload("res://mods/unfplap/poses/standing_presentation.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const STRETCH := preload("res://mods/unfplap/poses/idle_stretch.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

const STRETCH_FAKE := "res://mods/unfplap/tests/fixtures/idle_stretch_fake.gd"
const AWAY_YAW := PI
const AWAY_EPSILON := deg_to_rad(45.0)

var failures := 0
var checks := 0


class FakeIdentity extends RefCounted:
	var id := "rarity"
	var display_name := "Rarity"
	var filly := false
	var stallion := false


class FakeNavigator extends Node:
	var face_point := Vector3.INF
	var conversation_target: Variant = null
	var stays := 0

	func stay() -> void:
		stays += 1

	func set_conversation_target(who: Variant, _hold := true) -> void:
		conversation_target = who


class FakePony extends Node3D:
	var identity: Variant
	var sleeping := false
	var skeleton: Variant = null
	var hair_skeleton: Variant = null
	var body_scale := 0.66
	var face_turn_rate := 0.45
	var actual_speed := 0.0
	var posture := "stand"

	func is_held() -> bool:
		return false

	func grounded() -> bool:
		return true

	func posture_status() -> Dictionary:
		return {"requested": posture}


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
	pony.global_position = Vector3(0.0, 0.0, 2.0)
	root.add_child(pony)
	var body := Skeleton3D.new()
	body.name = "Body"
	pony.add_child(body)
	pony.skeleton = body
	var nav := FakeNavigator.new()
	nav.name = "Navigator"
	pony.add_child(nav)

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
	check(bool(presentation.call("present_standing")),
		"an accepted offer presents even with the pre-turn offer gate closed")
	check(bool(presentation.call("presentation_active"))
		and not bool(presentation.call("presentation_settled")),
		"the presentation is active but unsettled while she turns")
	check(nav.stays == 1, "the turn takes the navigator with one stay")
	check(nav.face_point.is_finite(), "the turn sets the navigator's face point")
	check(is_equal_approx(nav.face_point.distance_to(pony.global_position), 4.0),
		"the face point sits 4 m away")
	check(nav.face_point.z > pony.global_position.z, "the face point lies along the away direction")
	check(body.get_node_or_null("UnfplapPresentPose") == null,
		"no presentation pose exists during the turn")
	check(pony.face_turn_rate >= 1.5, "the stepping turn raises her face turn rate")

	# The away threshold is reached: hold the reached yaw and attach the pose without snapping.
	var held_yaw := AWAY_YAW - deg_to_rad(20.0)
	pony.rotation.y = held_yaw
	presentation.call("physics", 0.016)
	check(body.get_node_or_null("UnfplapPresentPose") != null,
		"the pose attaches once she is away enough")
	check(bool(presentation.call("presentation_settled")), "the settled pose reports settled")
	check(nav.face_point == Vector3.INF, "the settled turn releases its face point")
	check(is_equal_approx(pony.rotation.y, held_yaw), "the settle never snaps her yaw")
	check(is_equal_approx(pony.face_turn_rate, 0.45), "the settle restores her face turn rate")
	presentation.call("clear_presentation")
	check(not bool(presentation.call("presentation_active")),
		"the fake presentation clears without leaving a pose")
	await process_frame
	check(body.get_node_or_null("UnfplapPresentPose") == null,
		"clearing frees the presentation pose")

	# A blocked turn stalls: no pose, no snap, and no stale facing target.
	pony.rotation.y = 0.0
	var stalled_yaw := pony.rotation.y
	check(bool(presentation.call("present_standing")), "a blocked turn still starts")
	for i: int in 4:
		presentation.call("physics", 0.5)
	check(not bool(presentation.call("presentation_active")),
		"a blocked turn aborts instead of waiting forever")
	check(body.get_node_or_null("UnfplapPresentPose") == null,
		"an aborted turn attaches no pose")
	check(is_equal_approx(pony.rotation.y, stalled_yaw), "an aborted turn never snaps her yaw")
	check(nav.face_point == Vector3.INF, "an aborted turn releases its face point")

	# An unusual actor without navigator or locomotion turn rotates only before the pose attaches.
	pony.remove_child(nav)
	pony.rotation.y = 0.0
	check(bool(presentation.call("present_standing")), "the fallback presents an unusual actor")
	check(body.get_node_or_null("UnfplapPresentPose") == null,
		"the fallback keeps the pose off while it turns")
	var ticks := 0
	while not bool(presentation.call("presentation_settled")) and ticks < 60:
		presentation.call("physics", 0.1)
		ticks += 1
	check(bool(presentation.call("presentation_settled")),
		"the fallback settles at the away threshold")
	check(body.get_node_or_null("UnfplapPresentPose") != null,
		"the fallback attaches the pose after the settle")
	check(absf(wrapf(pony.rotation.y - AWAY_YAW, -PI, PI)) <= AWAY_EPSILON,
		"the fallback stops away enough")
	check(is_equal_approx(pony.face_turn_rate, 0.45), "the fallback leaves her face turn rate intact")
	presentation.call("clear_presentation")
	await process_frame

	pony.add_child(nav)
	await _check_presentation_stretch(presentation, pony, facts, body)
	root.remove_child(body)
	body.free()

	print("STANDING_PRESENTATION_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("STANDING_PRESENTATION_PASS")
	quit(0 if failures == 0 else 1)


## The accepted presentation attaches the external stretch after its turn, survives a live flag
## edit, and preserves the episode choice for the act.
func _check_presentation_stretch(presentation: Variant, pony: FakePony, facts: RefCounted,
		body: Skeleton3D) -> void:
	var before := bool(SETTINGS.idle_life_stretch.get_bool())
	facts.pony_id = "rarity"
	facts.mod_enabled = func(_id: String) -> bool: return true
	facts.keep_chin_last = func() -> void: pass
	STRETCH.pose_path = STRETCH_FAKE
	SETTINGS.idle_life_stretch.set_bool(true)
	presentation.call("set_request_face", true)
	check(bool(presentation.call("present_standing")),
		"the accepted offer reaches the presentation")
	pony.rotation.y = AWAY_YAW - deg_to_rad(10.0)
	presentation.call("physics", 0.016)
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


func _active_holder(body: Skeleton3D) -> Node:
	for child: Node in body.get_children():
		if str(child.name) == "UnfplapIdleStretch" and not child.is_queued_for_deletion():
			return child
	return null
