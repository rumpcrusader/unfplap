extends "res://mods/unfplap/tests/support/suite.gd"
## The standing invitation: the accepted offer presents even with the pre-turn offer gate closed,
## the navigator's face_point owns the turn away, the pose attaches only after the 60-degree away
## settle, a blocked turn aborts without snapping, the settled pose holds the affectionate face
## and one stronger glance before the soft hold.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_standing_presentation.gd

const WORLD := preload("res://mods/unfplap/world/api.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const PRESENTATION := preload("res://mods/unfplap/poses/standing_presentation.gd")
const ACT_FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const AWAY_YAW := PI
const AWAY_EPSILON := deg_to_rad(60.0)
const PRESENT_FACE := "affectionate"

var clock := {"now": 0.0}


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


class FakeExpressions extends RefCounted:
	var dialogue_face := ""
	var stares: Array = []

	func set_dialogue(value: String) -> void:
		dialogue_face = value

	func clear_dialogue() -> void:
		dialogue_face = ""

	func stare(on: bool, lids := 0.5) -> void:
		stares.append([on, lids])


class FakeBoop extends Node:
	var blushes: Array = []

	func sustain_blush(level := 1.0) -> void:
		blushes.append(level)


class FakeSecondary extends Node:
	var last_angles := Vector3.ZERO
	var looks := 0

	func look_toward(angles: Vector3, _duration: float) -> void:
		last_angles = angles
		looks += 1


class FakeEyeMotion extends Node:
	var target_world := Vector3.ZERO
	var target_weight := 0.0


class FakePony extends Node3D:
	var identity: Variant
	var sleeping := false
	var skeleton: Variant = null
	var hair_skeleton: Variant = null
	var body_scale := 0.66
	var face_turn_rate := 0.45
	var actual_speed := 0.0
	var posture := "stand"
	var expressions: Variant = null
	var boop_node: Variant = null
	var secondary: Variant = null
	var eye_motion: Variant = null

	func is_held() -> bool:
		return false

	func grounded() -> bool:
		return true

	func posture_status() -> Dictionary:
		return {"requested": posture}


## An actor with the body's own locomotion turn and no navigator.
class FakeTurnPony extends FakePony:
	var facings: Array = []

	func face_direction(direction: Vector3) -> void:
		facings.append(direction)


## The live player rig as the world facade reads it: the camera hangs off the body.
class FakePlayer extends Node3D:
	var camera: Variant = null


class FakeMain extends Node:
	var eligibility: Variant
	var player: Node3D
	var view: Camera3D = null

	func camera() -> Camera3D:
		return view

func run() -> void:
	var main := FakeMain.new()
	root.add_child(main)
	main.eligibility = ELIGIBILITY.new()
	PONIES.eligibility = main.eligibility
	main.player = FakePlayer.new()
	WORLD.bind_player(main.player)
	root.add_child(main.player)
	var game := Node.new()
	root.add_child(game)
	WORLD.bind_world(game)

	var pony := FakePony.new()
	pony.identity = FakeIdentity.new()
	pony.global_position = Vector3(0.0, 0.0, 2.0)
	root.add_child(pony)
	var expressions := FakeExpressions.new()
	var boop := FakeBoop.new()
	var secondary := FakeSecondary.new()
	var eye_motion := FakeEyeMotion.new()
	pony.expressions = expressions
	pony.boop_node = boop
	pony.secondary = secondary
	pony.eye_motion = eye_motion
	var body := Skeleton3D.new()
	body.name = "Body"
	pony.add_child(body)
	pony.skeleton = body
	var nav := FakeNavigator.new()
	nav.name = "Navigator"
	pony.add_child(nav)
	var view := Camera3D.new()
	main.add_child(view)
	view.global_position = Vector3.ZERO
	(main.player as FakePlayer).camera = view

	var facts: RefCounted = ACT_FACTS.new()
	facts.pony = pony
	facts.cuddle_active = func() -> bool: return false
	facts.free_of_affection = func() -> bool: return true
	facts.pause_face_turn = func(_force: bool) -> void: pass
	facts.restore_face_turn = func() -> void: pass
	facts.now = func() -> float: return float(clock["now"])

	var presentation: Variant = PRESENTATION.new(facts)
	check(bool(presentation.call("present_standing")),
		"an accepted offer presents without a pre-turn gate")
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

	# A 61-degree error is outside the away threshold: one tick keeps turning without stalling.
	pony.rotation.y = AWAY_YAW - deg_to_rad(61.0)
	presentation.call("physics", 0.016)
	check(body.get_node_or_null("UnfplapPresentPose") == null,
		"a 61-degree error keeps the turn going")
	check(bool(presentation.call("presentation_active")),
		"one short tick does not abort the turn")

	# The away threshold is reached: hold the reached yaw and attach the pose without snapping.
	var held_yaw := AWAY_YAW - deg_to_rad(50.0)
	pony.rotation.y = held_yaw
	presentation.call("physics", 0.016)
	check(body.get_node_or_null("UnfplapPresentPose") != null,
		"the pose attaches once she is away enough")
	check(bool(presentation.call("presentation_settled")), "the settled pose reports settled")
	check(nav.face_point == Vector3.INF, "the settled turn releases its face point")
	check(is_equal_approx(pony.rotation.y, held_yaw), "the settle never snaps her yaw")
	check(is_equal_approx(pony.face_turn_rate, 0.45), "the settle restores her face turn rate")

	# The settled presentation holds the bedroom face, the blush and one stronger glance.
	presentation.call("process")
	check(expressions.dialogue_face == PRESENT_FACE,
		"the settled presentation holds the affectionate face")
	check(not boop.blushes.is_empty() and near(float(boop.blushes[-1]), 1.0),
		"the presentation sustains the full blush")
	check(expressions.stares.is_empty(), "the presentation takes no request stare")
	check(secondary.looks > 0 and secondary.last_angles.x > 0.5,
		"the first look is the stronger over-the-shoulder glance")
	check(near(eye_motion.target_weight, 1.0)
		and eye_motion.target_world == view.global_position,
		"the eyes stay aimed at Anon through the glance")

	clock["now"] = float(PRESENTATION.PRESENT_GLANCE_BACK_S) + 0.1
	presentation.call("process")
	check(secondary.last_angles.x < 0.0,
		"the glance relaxes into the softer over-the-shoulder hold")

	# A spoken line's face wins while it owns the expression, then the held face returns.
	expressions.dialogue_face = "shy"
	presentation.call("process")
	check(expressions.dialogue_face == "shy", "a spoken line face wins over the held face")
	expressions.dialogue_face = ""
	presentation.call("process")
	check(expressions.dialogue_face == PRESENT_FACE,
		"the affectionate face returns after the line clears")

	presentation.call("clear_presentation")
	check(expressions.dialogue_face.is_empty(),
		"closing clears only the presentation's own face")
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

	# An actor with the body's own locomotion turn but no navigator: her body turns itself, and
	# the settled turn hands the facing and her rate back.
	var turn_pony := FakeTurnPony.new()
	root.add_child(turn_pony)
	turn_pony.global_position = Vector3(0.0, 0.0, 2.0)
	turn_pony.identity = pony.identity
	facts.pony = turn_pony
	check(bool(presentation.call("present_standing")), "a body-only turn starts the presentation")
	check(turn_pony.facings.size() == 1
		and is_equal_approx(turn_pony.face_turn_rate, PRESENTATION.PRESENT_FACE_TURN_RATE),
		"the turn asks her own locomotion facing and raises her rate")
	turn_pony.rotation.y = AWAY_YAW - deg_to_rad(50.0)
	presentation.call("physics", 0.016)
	check(turn_pony.facings.size() == 3 and turn_pony.facings[-1] == Vector3.ZERO,
		"the settled turn releases her facing")
	check(is_equal_approx(turn_pony.face_turn_rate, 0.45), "the body-only turn restores her rate")
	presentation.call("clear_presentation")
	check(not turn_pony.has_meta("affection_active"), "closing releases the body-only hold")
	facts.pony = pony
	turn_pony.queue_free()
	await process_frame

	pony.add_child(nav)
	await _check_presentation_face(presentation, pony, facts, body, expressions)
	root.remove_child(body)
	body.free()

	if failures == 0:
		print("STANDING_PRESENTATION_PASS")
	finish()


## The settled presentation holds the affectionate face, and closing it leaves a foreign line's
## face alone.
func _check_presentation_face(presentation: Variant, pony: FakePony, facts: RefCounted,
		body: Skeleton3D, expressions: FakeExpressions) -> void:
	facts.pony_id = "rarity"
	facts.mod_enabled = func(_id: String) -> bool: return true
	check(bool(presentation.call("present_standing")),
		"the accepted offer reaches the presentation")
	check(pony.has_meta("affection_active"),
		"the presentation takes its own affection hold")
	pony.rotation.y = AWAY_YAW - deg_to_rad(10.0)
	presentation.call("physics", 0.016)
	await process_frame
	check(body.get_node_or_null("UnfplapPresentPose") != null,
		"the presentation attaches its pose after the turn")
	check(expressions.dialogue_face == PRESENT_FACE,
		"the presentation holds the affectionate face")
	expressions.dialogue_face = "shy"
	presentation.call("clear_presentation")
	check(not pony.has_meta("affection_active"),
		"closing releases the presentation hold")
	check(expressions.dialogue_face == "shy",
		"closing leaves a foreign line face alone")
	expressions.dialogue_face = ""
	await process_frame


