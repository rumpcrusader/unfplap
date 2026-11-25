extends "res://mods/unfplap/tests/support/suite.gd"
## The standing oral segment's quiet gate: the impact keeps the slide, vocal, wings, blush and ear
## twitch but drops the plap and the rump/tail jiggle; her act line, voice and climax line stop
## while the base game's soft kiss plays on the idle timer. Regular standing is unchanged.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/readiness/test_oral_quiet.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const WING := preload("res://mods/unfplap/poses/wing_control.gd")
const POSE_SESSION := preload("res://mods/unfplap/poses/api.gd")
const POSE := preload("res://mods/unfplap/poses/skeleton_pose.gd")
const ACT_CAMERA := preload("res://mods/unfplap/camera/api.gd")
const REACTIONS := preload("res://mods/unfplap/reactions/api.gd")
const ACT_DIALOGUE := preload("res://mods/unfplap/dialogue/api.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const THRUST_STATE := preload("res://mods/unfplap/readiness/thrust_state.gd")
const READINESS := preload("res://mods/unfplap/readiness/api.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const PREF := preload("res://mods/unfplap/shared/preferences.gd")
const VIEW := preload("res://mods/unfplap/shared/pose_view.gd")

const STATE_ACTIVE := 2



class FakePresentation extends RefCounted:
	var holds := 0
	var visemes: Array[String] = []
	var mouth := Vector3(0.2, 1.3, 0.5)
	var point := Vector3(0.9, 0.0, 1.1)

	func hold_mouth() -> void:
		holds += 1

	func set_mouth_viseme(letter: String) -> void:
		visemes.append(letter)

	func mouth_point() -> Vector3:
		return mouth

	func frame_point() -> Vector3:
		return point

	func frame_axis() -> Vector3:
		return Vector3.BACK

	func react() -> void:
		pass

	func stage(_delta: float, _stage: Variant) -> void:
		pass

	func pose(_view: Variant) -> void:
		pass

	func climax() -> void:
		pass

	func end() -> void:
		pass

	func target() -> int:
		return 0

	func can_target_vulva() -> bool:
		return true

	func can_target_mouth() -> bool:
		return true


class FakeCamera extends ACT_CAMERA:
	var ends := 0

	func end_lean_action() -> void:
		ends += 1


class FakeReactions extends REACTIONS:
	var thrusts := 0
	var tails := 0
	var blushes := 0

	func thrust(_weight: float) -> void:
		thrusts += 1

	func tail_thrust(_weight: float) -> void:
		tails += 1

	func add_blush(_impact: float) -> void:
		blushes += 1

	func rump_point() -> Vector3:
		return Vector3.ZERO

	func dock_point() -> Vector3:
		return Vector3.ZERO


class FakeWings extends WING:
	var thrusts := 0

	func on_thrust(_impact: float) -> void:
		thrusts += 1


class FakePose extends POSE_SESSION:
	var ear_checks := 0
	var pose_id := ""

	func view() -> VIEW:
		return _facts.pose_view as VIEW if _facts != null else null

	func pose_changed() -> void:
		pass

	func pose() -> POSE:
		return null

	func trigger_ear_twitch(_impact: float) -> void:
		ear_checks += 1


class FakeAudio extends RefCounted:
	var impacts: Array = []
	var withdraws := 0
	var vocals := 0
	var oral_kisses := 0

	func impact(tier: String, strength: float, _rump: Vector3,
			_gap: float, body_slap: bool) -> void:
		impacts.append({"tier": tier, "strength": strength, "plap": body_slap})

	func crossing_out(_before: float, _now: float) -> bool:
		return true

	func slide_out(_before: float, _now: float, _strength: float, _rump: Vector3) -> void:
		withdraws += 1

	func vocal() -> void:
		vocals += 1

	func tick(_delta: float, _state: int, _rate: float) -> void:
		pass

	func oral_kiss() -> void:
		oral_kisses += 1


class FakeBoop extends Node:
	var kisses := 0
	var volumes: Array[float] = []
	var softs: Array[bool] = []

	func play_kiss(volume_db := -22.0, soft := false) -> void:
		kisses += 1
		volumes.append(volume_db)
		softs.append(soft)


class FakePony extends Node3D:
	var speaking := false
	var stops := 0
	var boop_node: Variant = null

	func is_speaking() -> bool:
		return speaking

	func stop_speaking() -> void:
		stops += 1
		speaking = false


class FakeDirector extends Node:
	var state := "idle"
	var _current := ""
	var interrupts := 0

	func interrupt() -> void:
		interrupts += 1
		state = "idle"


class FakeDialogue extends ACT_DIALOGUE:
	var ends: Array = []
	var reaction_calls := 0
	var notes := 0

	func setup() -> void:
		pass

	func reset(_now: float, _gap: float) -> void:
		pass

	func configure(_pacing: ACT_DIALOGUE.Pacing) -> void:
		pass

	func end_act(event_id: String, keep_speaking := true) -> void:
		ends.append([event_id, keep_speaking])

	func reaction_line(_reaction: int, _event_id: String, _fallback: String,
			_validate: ACT_DIALOGUE.Validity) -> String:
		reaction_calls += 1
		return "unfplap:test:reaction"

	func climax_line(mouth_busy: bool, _cue: String, _act_id: String, _count: int,
			_max_age: float) -> String:
		if mouth_busy:
			return ""
		reaction_calls += 1
		return "unfplap:test:climax"

	func note_reaction(_key: String, _cue_text: String, _until: float) -> void:
		notes += 1


class FakeMain extends Node:
	var anatomy: Variant = null
	var hud: Variant = null
	var game: Variant = null


func _fixture() -> Dictionary:
	var runtime: Node = RUNTIME.new()
	var pony := FakePony.new()
	var boop := FakeBoop.new()
	pony.add_child(boop)
	pony.boop_node = boop
	var main := FakeMain.new()
	var director := FakeDirector.new()
	director.add_to_group("conversation_director")
	var presentation := FakePresentation.new()
	var reactions := FakeReactions.new()
	var wings := FakeWings.new()
	var pose := FakePose.new(runtime.act.context.facts)
	var audio := FakeAudio.new()
	var dialogue := FakeDialogue.new()
	dialogue.facts = runtime.act.context.facts
	var act_camera := FakeCamera.new()
	runtime.pony = pony
	runtime.act.pony_id = "rarity"
	runtime.act.pony_id = "rarity"
	runtime.act.display_name = "Rarity"
	runtime.act.event_id = "unfplap:test"
	runtime.act._set_state(STATE_ACTIVE)
	runtime.act.pose_id = CATALOG.STANDING
	runtime.act.preferences = PREF.resolve({
		"intensity": "firm",
		"pattern": "steady",
		"touch": ["caress"],
		"dislikes": ["smack"],
		"talk": ["praise"],
		"warmth": "normal",
	})
	runtime.act.apply_start()
	runtime.act.context.reactions = reactions
	runtime.act.context.wings = wings
	runtime.act.context.pose = pose
	runtime.act.context.audio = audio
	runtime.act.context.dialogue = dialogue
	runtime.act.context.camera = act_camera
	runtime.act.context.reactions = reactions
	runtime.act.context.wings = wings
	runtime.act.context.pose = pose
	runtime.act.context.camera = act_camera
	runtime.act.context.audio = audio
	runtime.act.context.dialogue = dialogue
	runtime.act.context.anatomy = presentation
	runtime.act.reset_thrust_state()
	runtime.act.context.readiness.start_act(
		READINESS.Profile.from_dict(runtime.act.preferences))
	runtime.act.context.readiness.activate()
	root.add_child(main)
	WORLD.bind_world(main)
	root.add_child(director)
	root.add_child(pony)
	root.add_child(runtime)
	return {
		"runtime": runtime, "pony": pony, "boop": boop, "director": director,
		"main": main, "presentation": presentation,
		"reactions": reactions, "wings": wings, "pose": pose,
		"audio": audio, "dialogue": dialogue, "camera": act_camera,
	}


func _impact() -> RefCounted:
	var event := THRUST_STATE.StrokeEvent.new()
	event.kind = "impact"
	event.direction = 1
	event.thrust = true
	event.travel = 0.5
	event.duration = 0.5
	event.speed = 1.0
	event.peak_speed = 1.0
	event.impact_speed = 2.0
	event.strength = 0.8
	event.end_depth = 1.0
	event.tier = "firm"
	event.plap = true
	event.gap = 0.0
	event.jiggle = 0.4
	event.visual = 1.0
	return event


func run() -> void:
	var made := _fixture()
	var runtime: Node = made["runtime"]
	var pony: FakePony = made["pony"]
	var boop: FakeBoop = made["boop"]
	var main: FakeMain = made["main"]
	var director: FakeDirector = made["director"]
	var presentation: FakePresentation = made["presentation"]
	var reactions: FakeReactions = made["reactions"]
	var wings: FakeWings = made["wings"]
	var pose: FakePose = made["pose"]
	var audio: FakeAudio = made["audio"]
	var dialogue: FakeDialogue = made["dialogue"]
	var act_camera: FakeCamera = made["camera"]

	# A regular standing impact is untouched.
	var view: RefCounted = VIEW.new()
	view.contact_kind = "opening"
	runtime.act.context.facts.pose_view = view
	runtime.act.context.impact.impact(_impact())
	check(audio.impacts.size() == 1 and bool(audio.impacts[0]["plap"]),
		"a regular impact keeps the plap")
	check(reactions.thrusts == 1 and reactions.tails == 1,
		"a regular impact jiggles the rump and tail")
	check(wings.thrusts == 1, "a regular impact flaps the wings")
	check(reactions.blushes == 1, "a regular impact blushes")
	check(pose.ear_checks == 1, "a regular impact twitches the ear")
	check(audio.vocals == 1, "a regular impact plays the vocal")

	# The mouth contact keeps the reactions, drops the plap and skips the rump/tail jiggle.
	view.contact_kind = "mouth"
	runtime.act.context.impact.impact(_impact())
	check(audio.impacts.size() == 2 and not bool(audio.impacts[1]["plap"]),
		"an oral impact drops the plap")
	check(reactions.thrusts == 1 and reactions.tails == 1,
		"an oral impact skips the rump and tail jiggle")
	check(wings.thrusts == 2, "an oral impact keeps the wings")
	check(reactions.blushes == 2, "an oral impact keeps the blush")
	check(pose.ear_checks == 2, "an oral impact keeps the ear twitch")
	check(audio.vocals == 2, "an oral impact keeps the vocal")
	check(boop.kisses == 0, "an oral stroke plays no kiss")

	# The speech stop host action: her act line, director turn and voice stop, and the mouth is
	# re-asserted defensively.
	director.state = "speaking"
	director._current = "rarity"
	pony.speaking = true
	runtime.act.ticker.phases.oral_speech_stop()
	check(dialogue.ends.size() == 1 and not bool(dialogue.ends[0][1]),
		"the speech stop cancels her act line without letting it finish")
	check(director.interrupts == 1, "the speech stop interrupts her own director turn")
	check(pony.stops == 1 and not pony.speaking, "the speech stop stops her base-game voice")
	check(presentation.holds == 1, "the speech stop re-asserts the mouth")
	check(boop.kisses == 0, "the speech stop plays no kiss")

	# The edge's viseme event sets and clears the mouth through the anatomy handle.
	runtime.act.context.anatomy.set_mouth_viseme("D")
	runtime.act.context.anatomy.set_mouth_viseme("")
	check(presentation.visemes == ["D", ""], "the viseme event reaches the anatomy provider")

	# The edge's mouth and opening host reads reach the anatomy handle.
	check(runtime.act.anatomy_mouth_point().is_equal_approx(presentation.mouth),
		"the pose turn reads the provider's mouth point")
	check(runtime.act.anatomy_opening().is_equal_approx(presentation.point),
		"the pose turn reads the provider's opening")

	# The soft kiss cue is one base-game soft kiss; the audio facade owns the cue and its level
	# (`test_audio.gd` covers the stock volume and the soft variant).
	boop.kisses = 0
	runtime.act.context.audio.oral_kiss()
	check(audio.oral_kisses == 1, "the soft kiss reaches the audio facade")

	# Her climax line is skipped while the mouth contact is live, and returns once released.
	dialogue.reaction_calls = 0
	runtime.act.context.readiness.readout().climaxes = 1
	runtime.act.view.climax_line(runtime.act)
	check(dialogue.reaction_calls == 0, "no climax line is queued during the mouth contact")
	view.contact_kind = "opening"
	runtime.act.view.climax_line(runtime.act)
	check(dialogue.reaction_calls == 1, "the climax line returns with the mouth contact off")

	# Both withdrawal slides still fire: the mouth contact keeps the slide.
	view.contact_kind = "mouth"
	runtime.act.context.impact.move(-0.4)
	var oral_withdraws := audio.withdraws
	check(oral_withdraws >= 1, "the withdrawal slide still fires during oral")
	view.contact_kind = "opening"
	runtime.act.context.impact.move(0.4)
	check(audio.withdraws > oral_withdraws, "the regular withdrawal slide is unchanged")

	# The bed face-sit contact uses the same quiet branch: no plap, no rump/tail jiggle, no
	# withdrawal cue; the wings and the vocal stay.
	var face_thrusts := reactions.thrusts
	var face_tails := reactions.tails
	var face_wings := wings.thrusts
	var face_vocal := audio.vocals
	view.contact_kind = "face"
	runtime.act.context.impact.impact(_impact())
	check(audio.impacts.size() == 3 and not bool(audio.impacts[2]["plap"]),
		"a face-sit impact drops the plap")
	check(reactions.thrusts == face_thrusts and reactions.tails == face_tails,
		"a face-sit impact skips the rump and tail jiggle")
	check(wings.thrusts == face_wings + 1 and audio.vocals == face_vocal + 1,
		"a face-sit impact keeps the wings and the vocal")
	var face_withdraws := audio.withdraws
	runtime.act.context.impact.move(-0.4)
	check(audio.withdraws == face_withdraws, "a face-sit withdraw plays no withdrawal cue")
	view.contact_kind = "opening"
	runtime.act.context.impact.move(0.4)
	check(audio.withdraws > face_withdraws, "the regular withdrawal cue returns after the face-sit")

	root.remove_child(runtime)
	runtime.free()
	root.remove_child(director)
	director.free()
	root.remove_child(pony)
	pony.free()
	root.remove_child(main)
	main.free()
	reactions.free()
	pose.free()
	dialogue.free()
	act_camera.free()

	finish()
