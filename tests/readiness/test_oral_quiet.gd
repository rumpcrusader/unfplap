extends SceneTree
## The standing oral segment's quiet gate: the impact keeps the slide, vocal, wings, blush and ear
## twitch but drops the plap and the rump/tail jiggle; her act line, voice and climax line stop
## while the base game's soft kiss plays on the idle timer. Regular standing is unchanged.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/readiness/test_oral_quiet.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const THRUST := preload("res://mods/unfplap/readiness/thrust.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const PREF := preload("res://mods/unfplap/shared/preferences.gd")

const STATE_ACTIVE := 2

var failures := 0
var checks := 0


class FakeBridge extends RefCounted:
	var oral := false
	var holds := 0

	func bind(_host: Dictionary) -> void:
		pass

	func refresh() -> void:
		pass

	func oral_active() -> bool:
		return oral

	func hold_oral_mouth() -> void:
		holds += 1


class FakeCamera extends RefCounted:
	var ends := 0

	func bind(_facts: Variant, _hands: Variant, _kiss: Variant, _standing: Variant,
			_missionary: Variant) -> void:
		pass

	func end_lean_action() -> void:
		ends += 1


class FakeKiss extends RefCounted:
	var ends := 0

	func end_lean_kiss() -> void:
		ends += 1


class FakeReactions extends RefCounted:
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


class FakeWings extends RefCounted:
	var thrusts := 0

	func on_thrust(_impact: float) -> void:
		thrusts += 1


class FakePose extends RefCounted:
	var ear_checks := 0
	var pose_id := ""
	var id := ""
	var place_anon := Callable()
	var eye_camera := Callable()
	var perf := Callable()
	var facts: Variant = null
	var pose_config: Dictionary = {}

	func bind(_runtime: Variant, _pony_node: Variant) -> void:
		pass

	func pose() -> Variant:
		return null

	func trigger_ear_twitch(_impact: float) -> void:
		ear_checks += 1


class FakeAudio extends RefCounted:
	var impacts: Array = []
	var withdraws := 0

	func play_impact(pose: String, tier: String, strength: float, _rump: Vector3,
			_bed_at: Vector3, _soft_bed: bool, _gap: float, _eps: float, plap := true) -> void:
		impacts.append({"pose": pose, "tier": tier, "strength": strength, "plap": plap})

	func crossed(_before: float, _after: float) -> bool:
		return true

	func withdraw_crossed(_before: float, _after: float, _strength: float,
			_pose: String, _rump: Vector3, _bed_at: Vector3, _soft_bed: bool) -> void:
		withdraws += 1


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


class FakeVocal extends RefCounted:
	var plays := 0

	func play(_id: String, _kind: String, _pony_node: Variant, _db: float) -> bool:
		plays += 1
		return true


class FakeDirector extends Node:
	var state := "idle"
	var _current := ""
	var vocal: Variant = null
	var interrupts := 0

	func interrupt() -> void:
		interrupts += 1
		state = "idle"


class FakeLines extends RefCounted:
	var ends: Array = []
	var reaction_calls := 0
	var notes := 0

	func setup(_main_node: Node) -> void:
		pass

	func reset(_now: float, _gap: float) -> void:
		pass

	func configure(_pacing: Dictionary) -> void:
		pass

	func end_act(event_id: String, keep_speaking := true) -> void:
		ends.append([event_id, keep_speaking])

	func reaction_line(_reaction: int, _event_id: String, _fallback: String,
			_validate: Callable) -> String:
		reaction_calls += 1
		return "unfplap:test:reaction"

	func note_reaction(_key: String, _cue_text: String, _until: float) -> void:
		notes += 1


class FakeMain extends Node:
	var anatomy: Variant = null
	var hud: Variant = null
	var lines: Array[String] = []

	func debug(text: String) -> void:
		lines.append(text)

	func clear_active(_runtime: Node) -> void:
		pass


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _fixture() -> Dictionary:
	var runtime: Node = RUNTIME.new()
	var pony := FakePony.new()
	var boop := FakeBoop.new()
	pony.add_child(boop)
	pony.boop_node = boop
	var main := FakeMain.new()
	var director := FakeDirector.new()
	var vocal := FakeVocal.new()
	director.vocal = vocal
	director.add_to_group("conversation_director")
	var bridge := FakeBridge.new()
	var reactions := FakeReactions.new()
	var wings := FakeWings.new()
	var pose := FakePose.new()
	var audio := FakeAudio.new()
	var lines := FakeLines.new()
	var act_camera := FakeCamera.new()
	var kiss := FakeKiss.new()
	runtime.pony = pony
	runtime.main = main
	runtime._id = "rarity"
	runtime._display_name = "Rarity"
	runtime._event_id = "unfplap:test"
	runtime.state = STATE_ACTIVE
	runtime.pose_id = CATALOG.STANDING
	runtime._preferences = PREF.resolve({
		"intensity": "firm",
		"pattern": "steady",
		"touch": ["caress"],
		"dislikes": ["smack"],
		"talk": ["praise"],
		"warmth": "normal",
	})
	runtime._anatomy_bridge = bridge
	runtime._reactions = reactions
	runtime._wings = wings
	runtime._pose_session = pose
	runtime._act_audio = audio
	runtime._act_lines = lines
	runtime._act_lines_main = main
	runtime._act_camera = act_camera
	runtime._kiss = kiss
	runtime._thrust_tracker = THRUST.new()
	runtime._reset_thrust_state()
	root.add_child(main)
	root.add_child(director)
	root.add_child(pony)
	root.add_child(runtime)
	return {
		"runtime": runtime, "pony": pony, "boop": boop, "main": main,
		"director": director, "vocal": vocal, "bridge": bridge,
		"reactions": reactions, "wings": wings, "pose": pose,
		"audio": audio, "lines": lines, "camera": act_camera, "kiss": kiss,
	}


func _impact() -> Dictionary:
	return {
		"direction": 1, "thrust": true, "travel": 0.5, "duration": 0.5,
		"speed": 1.0, "peak_speed": 1.0, "impact_speed": 2.0, "strength": 0.8,
		"end_depth": 1.0,
	}


func run() -> void:
	var made := _fixture()
	var runtime: Node = made["runtime"]
	var pony: FakePony = made["pony"]
	var boop: FakeBoop = made["boop"]
	var main: FakeMain = made["main"]
	var director: FakeDirector = made["director"]
	var vocal: FakeVocal = made["vocal"]
	var bridge: FakeBridge = made["bridge"]
	var reactions: FakeReactions = made["reactions"]
	var wings: FakeWings = made["wings"]
	var pose: FakePose = made["pose"]
	var audio: FakeAudio = made["audio"]
	var lines: FakeLines = made["lines"]
	var act_camera: FakeCamera = made["camera"]
	var kiss: FakeKiss = made["kiss"]

	# Regular standing: the impact fan-out is untouched.
	bridge.oral = false
	runtime._vocal_cooldown = 0.0
	runtime._on_impact(_impact())
	check(audio.impacts.size() == 1 and bool(audio.impacts[0]["plap"]),
		"a regular impact keeps the plap")
	check(reactions.thrusts == 1 and reactions.tails == 1,
		"a regular impact jiggles the rump and tail")
	check(wings.thrusts == 1, "a regular impact flaps the wings")
	check(reactions.blushes == 1, "a regular impact blushes")
	check(pose.ear_checks == 1, "a regular impact twitches the ear")
	check(vocal.plays == 1, "a regular impact plays the vocal")

	# Oral: the kept reactions stay, the plap and jiggle go, and no kiss rides a stroke.
	bridge.oral = true
	runtime._vocal_cooldown = 0.0
	runtime._on_impact(_impact())
	check(audio.impacts.size() == 2 and not bool(audio.impacts[1]["plap"]),
		"an oral impact drops the plap")
	check(reactions.thrusts == 1 and reactions.tails == 1,
		"an oral impact skips the rump and tail jiggle")
	check(wings.thrusts == 2, "an oral impact keeps the wings")
	check(reactions.blushes == 2, "an oral impact keeps the blush")
	check(pose.ear_checks == 2, "an oral impact keeps the ear twitch")
	check(vocal.plays == 2, "an oral impact keeps the vocal")
	check(boop.kisses == 0, "an oral stroke plays no kiss")

	# Entry: her act line, director turn and voice stop; the mouth is re-asserted and no kiss yet.
	director.state = "speaking"
	director._current = "rarity"
	pony.speaking = true
	runtime._oral_was_active = false
	runtime._oral_tick(0.1)
	check(lines.ends.size() == 1 and not bool(lines.ends[0][1]),
		"oral entry cancels her act line without letting it finish")
	check(director.interrupts == 1, "oral entry interrupts her own director turn")
	check(pony.stops == 1 and not pony.speaking, "oral entry stops her base-game voice")
	check(act_camera.ends == 1, "oral entry ends a live lean action")
	check(kiss.ends == 1, "oral entry ends a live lean kiss")
	check(bridge.holds == 2, "oral entry holds the mouth after the stop and once more")
	check(boop.kisses == 0, "oral entry plays no kiss")
	var waited := float(runtime._oral_kiss_left)
	check(waited >= runtime.ORAL_KISS_IDLE_MIN_S and waited <= runtime.ORAL_KISS_IDLE_MAX_S,
		"the idle kiss timer starts inside its window")

	# Release, then re-enter while she is already silent: the viseme hold still runs.
	bridge.oral = false
	runtime._oral_tick(0.1)
	check(float(runtime._oral_kiss_left) == 0.0, "a release clears the idle kiss timer")
	pony.speaking = false
	bridge.oral = true
	runtime._oral_tick(0.1)
	check(bridge.holds == 3, "oral holds the defensive viseme even when she was silent")

	# The idle timer plays exactly one soft kiss per window.
	boop.kisses = 0
	runtime._oral_kiss_left = 0.05
	runtime._oral_tick(0.1)
	check(boop.kisses == 1, "the idle timer plays one base-game kiss")
	check(boop.volumes.size() == 1 and is_equal_approx(boop.volumes[0], runtime.ORAL_KISS_DB),
		"the idle kiss uses the stock soft volume")
	check(boop.softs.size() == 1 and bool(boop.softs[0]), "the idle kiss is the soft variant")
	check(float(runtime._oral_kiss_left) >= runtime.ORAL_KISS_IDLE_MIN_S,
		"the idle timer restarts after a kiss")
	runtime._oral_tick(0.1)
	check(boop.kisses == 1, "a tick inside the window adds no second kiss")

	# A line that starts during oral is stopped and the mouth is re-asserted again.
	pony.speaking = true
	var holds_before := bridge.holds
	runtime._oral_tick(0.1)
	check(not pony.speaking, "a new line is stopped while oral lasts")
	check(bridge.holds == holds_before + 1, "the repeated stop re-asserts the oral viseme")

	# Her climax line is skipped while oral, and returns once she is released.
	lines.reaction_calls = 0
	runtime.pony_climaxes = 1
	runtime._queue_climax_reaction()
	check(lines.reaction_calls == 0, "no climax line is queued while oral")
	bridge.oral = false
	runtime._queue_climax_reaction()
	check(lines.reaction_calls == 1, "the climax line returns with oral off")

	# The release leaves speech and the kiss alone, and a new act starts clean.
	runtime._oral_tick(0.1)
	var ends_after := lines.ends.size()
	var holds_after := bridge.holds
	boop.kisses = 0
	runtime._oral_tick(0.1)
	check(lines.ends.size() == ends_after and bridge.holds == holds_after and boop.kisses == 0,
		"a released turn stops touching speech and the kiss")
	runtime._oral_was_active = true
	runtime._oral_kiss_left = 1.0
	runtime._reset_thrust_state()
	check(not bool(runtime._oral_was_active) and float(runtime._oral_kiss_left) == 0.0,
		"a new act starts with no oral gate and a fresh idle timer")

	# Both withdrawal slides still fire: oral keeps the slide and regular standing is unchanged.
	bridge.oral = true
	runtime._thrust_move(-0.4, 0.1)
	var oral_withdraws := audio.withdraws
	check(oral_withdraws >= 1, "the withdrawal slide still fires during oral")
	bridge.oral = false
	runtime._thrust_move(0.4, 0.2)
	check(audio.withdraws > oral_withdraws, "the regular withdrawal slide is unchanged")

	root.remove_child(runtime)
	runtime.free()
	root.remove_child(director)
	director.free()
	root.remove_child(pony)
	pony.free()
	root.remove_child(main)
	main.free()

	print("RUNTIME_ORAL_QUIET_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
