extends SceneTree
## The request service through its public path: `force()` builds a standing ask against a fake
## director and runtime, the director's transcript drives the consent flow, and every assertion is
## an observable effect. No private member is touched. The distant-walk case uses two real 2.1 s
## waits, so this suite is one of the slow ones for the parallel runner.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/initiation/test_initiation_api.gd

const INIT := preload("res://mods/unfplap/initiation/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const COOLDOWNS := preload("res://mods/unfplap/initiation/cooldowns.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


class FakeMain extends Node:
	var player: Node3D
	var game: Node
	var runtimes: Dictionary = {}
	var eligibility: Variant
	var memory: Node
	var debug_lines: Array[String] = []

	func runtime_for(pony: Node) -> Node:
		var runtime: Variant = runtimes.get(pony)
		return runtime if is_instance_valid(runtime) else null

	func menu_open() -> bool:
		return false

	func camera() -> Camera3D:
		return null

	func bed_occupied(_bed: Node3D, _target: Node) -> bool:
		return false

	func debug(text: String) -> void:
		debug_lines.append(text)


class FakeGame extends Node:
	var mares: Array = []
	var world_context: Node
	var headset_view := false


class FakeForm extends Node:
	var form: Dictionary = {}


class FakePony extends Node3D:
	var identity: Dictionary = {"filly": false, "stallion": false}


class FakeMemory extends Node:
	const MEMORY := preload("res://mods/unfplap/memory/service.gd")

	func cue_facts(_id: String, _note: String) -> Variant:
		return MEMORY.CueFacts.new()


class FakeWorldContext extends Node:
	var keys: Array[String] = []
	var texts: Array[String] = []
	var state: Dictionary = {}

	func record(_kind: String, text: String, _ids: Array, _witnesses: Array, key: String) -> void:
		keys.append(key)
		texts.append(text)

	func _changed() -> void:
		pass


class FakeEligibility extends Node:
	func eligible(_pony: Node, _target: int) -> bool:
		return true

	func get_verdict(_pony: Node, _mode: int) -> Variant:
		return null


class FakeNavigator extends Node:
	var reserved_by := ""
	var command_owner := ""
	var wander_enabled := true
	var command_speed_limit: Variant = INF
	var command_pace_target: Variant = -1.0
	var _has_target := false
	var goal: Variant = null

	func stay() -> void:
		_has_target = false

	func command_support(point: Vector3) -> Vector3:
		return point

	func command_destination(point: Vector3, _gait: String) -> bool:
		goal = point
		_has_target = true
		return true


class FakeDirector extends Node:
	signal transcript(text: String)

	var state := "idle"
	var greet_ok := true
	var queued: Array[String] = []
	var purposes: Array[String] = []
	var keys: Array[String] = []
	var config: Variant = null
	var characters: Dictionary = {}
	var speech: Variant = null
	var player_approaches: Variant = null
	var group: Variant = null
	var _player_text := ""
	var _held_text := ""

	func begin_player_greeting(_id: String, _context: String) -> bool:
		return greet_ok

	func queue_generated_intent(_id: String, purpose: String, key: String, _valid: Callable,
			_empty: Callable, _priority: bool) -> bool:
		queued.append(key)
		purposes.append(purpose)
		keys.append(key)
		return true

	func cancel_authored_line(key: String) -> void:
		keys.erase(key)

	func _now() -> float:
		return 0.0


class FakeRuntime extends Node:
	var pony: Node3D
	var state := 0
	var present_ok := true
	var presented := false
	var face_on := false
	var stretch_clears := 0
	var phase := "normal"
	var start_ok := true

	func offer_verdict(_pose: String, _source: String, _bed: Variant, _forced: bool,
			verdict: Variant) -> Dictionary:
		return {"ok": true, "rows": [], "policy": verdict}

	func can_offer(_pose: String, _source: String, _bed: Variant) -> bool:
		return true

	func can_show_start(_pose: String, _source: String, _bed: Variant) -> bool:
		return start_ok

	func find_bed_under() -> Node3D:
		return null

	func cuddle_active() -> bool:
		return false

	func cycle_phase() -> String:
		return phase

	func present_standing() -> bool:
		if not present_ok:
			return false
		presented = true
		return true

	func presentation_active() -> bool:
		return true

	func presentation_settled() -> bool:
		return true

	func clear_presentation() -> void:
		presented = false

	func set_request_face(on: bool) -> void:
		face_on = on

	func clear_stretch_offer() -> void:
		stretch_clears += 1


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func debug_count(main: Node, text: String) -> int:
	var count := 0
	var lines: Variant = main.get("debug_lines")
	if lines is Array:
		for line: Variant in lines:
			if str(line) == text:
				count += 1
	return count


func run() -> void:
	var fake_main := FakeMain.new()
	root.add_child(fake_main)
	var game := FakeGame.new()
	root.add_child(game)
	var player := Node3D.new()
	root.add_child(player)
	var target := FakePony.new()
	target.name = "Rarity"
	target.set_meta("relationship_id", "rarity")
	root.add_child(target)
	var nav := FakeNavigator.new()
	nav.name = "Navigator"
	target.add_child(nav)
	var other := Node3D.new()
	other.name = "Other"
	root.add_child(other)
	other.global_position = Vector3(1.0, 0.0, 0.0)
	var director := FakeDirector.new()
	root.add_child(director)
	director.add_to_group("conversation_director")
	var context := FakeWorldContext.new()
	root.add_child(context)
	var runtime := FakeRuntime.new()
	runtime.pony = target
	root.add_child(runtime)
	var memory := FakeMemory.new()
	root.add_child(memory)

	game.world_context = context
	game.mares = [target]
	fake_main.player = player
	fake_main.game = game
	fake_main.memory = memory
	fake_main.runtimes[target] = runtime
	fake_main.eligibility = ELIGIBILITY.new()
	fake_main.eligibility.setup(fake_main)

	var initiation := INIT.new()
	initiation.name = "UnfplapInitiation"
	initiation.call("setup", fake_main)
	root.add_child(initiation)

	# A standing ask starts through the debug entry and arms the request face.
	var forced: INIT.ForceResult = initiation.force(runtime, CATALOG.STANDING)
	check(forced.ok, "force starts a standing ask")
	check(forced.id == "rarity" and forced.pose == CATALOG.STANDING,
		"the force result names the mare and the pose")
	check(runtime.face_on, "the private standing ask arms the request face")
	check(nav.command_owner.begins_with("unfplap:request:rarity"),
		"the standing ask owns the navigator")
	check(not nav.wander_enabled and not nav._has_target, "the standing ask holds her still")
	check(context.keys.size() == 1 and context.keys[0].ends_with(":situation"),
		"the ask records one situation")
	check(initiation.start_offer() == null, "an ask is not startable before it is accepted")

	# A local yes waits for the ask line to finish, then presents and queues the invitation.
	director.state = "speaking"
	director.transcript.emit("yes")
	check(not runtime.presented, "a private yes waits for the offer line")
	initiation.tick(0.0)
	check(not runtime.presented, "a speaking offer still waits")
	check(initiation.start_offer() == null,
		"the accepted offer is not startable before the presentation")
	check(context.keys.size() == 2 and context.keys[1].ends_with(":accepted"),
		"an accepted situation is recorded")
	director.state = "idle"
	initiation.tick(0.0)
	check(runtime.presented, "the presentation starts after the offer line")
	check(director.queued.size() == 1, "the presentation queues one invitation")
	check(director.queued[0].begins_with("unfplap:request:rarity:")
		and director.queued[0].ends_with(":invite"), "the invitation key names the request")

	# The accepted offer hands its live shape to the act key, independent of the rump fan.
	var live: INIT.StartOffer = initiation.start_offer()
	check(live != null and live.pose == CATALOG.STANDING and live.source.is_empty(),
		"the accepted standing offer is startable")
	check(live != null and live.pony == target, "the start offer names the mare")
	target.global_position = Vector3(4.0, 0.0, 0.0)
	check(initiation.start_offer() == null, "an accepted offer past 3 m is not startable")
	target.global_position = Vector3(1.732, 0.0, 1.0)
	check(initiation.start_offer() != null,
		"the live offer does not need the rump fan or its angle")
	target.global_position = Vector3.ZERO

	# The queued ask key uses the same shape when the greeting cannot open the line.
	initiation.reset()
	check(nav.command_owner.is_empty() and nav.wander_enabled,
		"reset releases the ask's navigator lease")
	check(runtime.stretch_clears == 1, "reset closes the accepted offer's stretch choice")
	director.greet_ok = false
	director.queued.clear()
	var asked: INIT.ForceResult = initiation.force(runtime, CATALOG.STANDING)
	check(asked.ok, "force starts an ask without a greeting")
	check(director.queued.size() == 1 and director.queued[0].ends_with(":ask"),
		"the ask key names the request")

	# A local no closes the offer and hands the presentation and face back.
	runtime.presented = false
	runtime.face_on = true
	var clears_before_no := runtime.stretch_clears
	director.transcript.emit("no")
	check(not runtime.presented, "a private no does not present")
	check(not runtime.face_on, "a private no clears the request face")
	check(runtime.stretch_clears == clears_before_no + 1,
		"a private no clears the offer's stretch choice")
	check(context.keys.size() == 4 and context.keys[3].ends_with(":declined"),
		"a declined situation is recorded")

	# A third nearby pony makes the ask public, so the private request face is not armed.
	initiation.reset()
	game.mares = [target, other]
	director.greet_ok = true
	runtime.presented = false
	initiation.force(runtime, CATALOG.STANDING)
	check(not runtime.face_on, "a public standing ask does not arm the private face")

	# A private ask that loses its privacy before the answer is refused at accept time.
	initiation.reset()
	game.mares = [target]
	runtime.presented = false
	initiation.force(runtime, CATALOG.STANDING)
	check(runtime.face_on, "the private ask arms the face before the answer")
	var clears_before_refuse := runtime.stretch_clears
	game.mares = [target, other]
	director.transcript.emit("yes")
	check(not runtime.presented, "a private yes is refused when a third pony arrived")
	check(not runtime.face_on, "the refused accept clears the request face")
	check(runtime.stretch_clears == clears_before_refuse + 1,
		"the refused accept clears the offer's stretch choice")

	# Heat opens the public override, so the same crowded offer is accepted.
	initiation.reset()
	runtime.phase = "heat"
	runtime.presented = false
	initiation.force(runtime, CATALOG.STANDING)
	director.state = "idle"
	director.transcript.emit("yes")
	initiation.tick(0.0)
	check(runtime.presented, "heat overrides the privacy reserve")
	runtime.phase = "normal"
	game.mares = [target]

	# A distant walk enters APPROACH, keeps its navigator lease past the old two-second window,
	# then settles in ARRIVE before the ask. This case is the suite's only real-time wait.
	initiation.reset()
	director.greet_ok = false
	director.queued.clear()
	director._player_text = ""
	runtime.presented = false
	target.global_position = Vector3(10.0, 0.0, 0.0)
	var walking: INIT.ForceResult = initiation.force(runtime, CATALOG.STANDING)
	check(walking.ok, "force starts a distant walk")
	check(nav.command_owner.begins_with("unfplap:request:rarity"),
		"the walk owns the navigator")
	check(not nav.wander_enabled and nav._has_target, "the walk stops her wander")
	OS.delay_msec(2100)
	initiation.tick(0.0)
	check(nav.command_owner.begins_with("unfplap:request:rarity"),
		"the walk keeps the navigator past two seconds")
	check(director.queued.is_empty(), "a distant walk has not asked yet")
	target.global_position = Vector3(2.0, 0.0, 0.0)
	initiation.tick(0.0)
	check(not nav._has_target, "arriving stops the walk")
	check(director.queued.is_empty(), "the arrival still settles for two seconds")
	OS.delay_msec(2100)
	initiation.tick(0.0)
	check(director.queued.size() == 1 and director.queued[0].ends_with(":ask"),
		"the ask starts after the arrival settle")
	check(not context.keys.is_empty() and context.keys[-1].ends_with(":situation"),
		"the settled ask records its situation")
	initiation.reset()
	target.global_position = Vector3.ZERO
	director.greet_ok = true

	# A closed start gate after the settled presentation no longer closes the accepted offer: the
	# act key runs the detailed gate and the invitation waits for its own timeout.
	initiation.reset()
	game.mares = [target]
	runtime.phase = "normal"
	runtime.presented = false
	runtime.start_ok = false
	director.state = "idle"
	initiation.force(runtime, CATALOG.STANDING)
	director.transcript.emit("yes")
	initiation.tick(0.0)
	check(runtime.presented, "the settled presentation starts with a closed start gate")
	initiation.tick(0.0)
	check(runtime.presented and runtime.face_on,
		"the closed start gate keeps the accepted offer alive")
	check(initiation.start_offer() != null,
		"the blocked start gate still hands the live offer to the act key")
	initiation.tick(0.0)
	check(runtime.presented, "the sticky invitation keeps waiting")
	runtime.start_ok = true
	initiation.tick(0.0)
	check(runtime.presented and initiation.start_offer() != null,
		"a reopened start gate keeps the same accepted offer")

	# One failed presentation attempt retries inside the accept window instead of closing.
	initiation.reset()
	game.mares = [target]
	runtime.presented = false
	runtime.present_ok = false
	director.state = "idle"
	initiation.force(runtime, CATALOG.STANDING)
	director.transcript.emit("yes")
	initiation.tick(0.0)
	check(not runtime.presented, "a failed presentation attempt does not present")
	check(initiation.start_offer() == null, "a pending presentation is not startable")
	runtime.present_ok = true
	initiation.tick(0.0)
	check(runtime.presented, "the presentation retries after a transient failure")
	check(director.queued.size() > 0 and director.queued[-1].ends_with(":invite"),
		"the retried presentation queues the invitation")

	# A stale director line from an earlier chat is not the answer to a new ask.
	initiation.reset()
	game.mares = [target]
	runtime.presented = false
	runtime.present_ok = true
	director.state = "idle"
	director.greet_ok = false
	director.queued.clear()
	director._player_text = "old line"
	initiation.force(runtime, CATALOG.STANDING)
	check(director.queued.size() == 1 and director.queued[0].ends_with(":ask"),
		"the fallback ask still queues")
	initiation.tick(0.0)
	check(director.queued.size() == 1, "the stale line does not queue a clarification")
	check(runtime.face_on, "the stale line keeps the private request face")
	check(context.keys[-1].ends_with(":situation"), "the stale-line ask records its situation")
	director._player_text = ""
	director.greet_ok = true

	# A public answer stays a hint; once the third pony leaves, the next yes is private.
	initiation.reset()
	game.mares = [target, other]
	runtime.presented = false
	runtime.face_on = false
	initiation.force(runtime, CATALOG.STANDING)
	director.transcript.emit("yes")
	check(not runtime.presented and not runtime.face_on, "a public yes does not present")
	check(initiation.start_offer() == null, "a public yes is not a private accepted offer")
	game.mares = [target]
	director.transcript.emit("yes")
	check(runtime.face_on, "the now-private yes arms the request face")
	initiation.tick(0.0)
	check(runtime.presented, "the now-private yes presents")
	check(initiation.start_offer() != null, "the now-private offer is startable")
	initiation.reset()

	# A public no closes the offer and records the declined situation.
	game.mares = [target, other]
	runtime.presented = false
	initiation.force(runtime, CATALOG.STANDING)
	director.transcript.emit("no")
	check(not runtime.face_on, "a public no clears the request face")
	check(context.keys[-1].ends_with(":declined"),
		"a public no records the declined situation")
	check(initiation.start_offer() == null, "a public no closes the offer")
	initiation.reset()
	game.mares = [target]

	# The typed force result replaces the side-channel reason.
	var missing: INIT.ForceResult = initiation.force(null)
	check(not missing.ok and missing.reject == "no_runtime",
		"force rejects a missing runtime")
	runtime.state = 1
	var busy: INIT.ForceResult = initiation.force(runtime)
	check(not busy.ok and busy.reject.contains("state=1"),
		"force reports the runtime state")
	runtime.state = 0

	# Internal poses are never offer candidates, and the spec's form/view support refuses them
	# before the scene gate runs.
	var internal_pose: INIT.ForceResult = initiation.force(runtime, CATALOG.STANDING_ORAL)
	check(not internal_pose.ok and internal_pose.reject.contains("pose:standing_oral"),
		"an internal pose is never offered")
	var test_pose: INIT.ForceResult = initiation.force(runtime, CATALOG.STANDING_TEST)
	check(not test_pose.ok and test_pose.reject.contains("pose:standing_test"),
		"the internal test pose is never offered")
	var facesit_pose: INIT.ForceResult = initiation.force(runtime, CATALOG.BED_FACESIT)
	check(not facesit_pose.ok and facesit_pose.reject.contains("pose:bed_facesit"),
		"the internal face-sit pose is never offered")
	var form_driver := FakeForm.new()
	form_driver.form = {"kind": "pony"}
	form_driver.add_to_group("player_pony_form")
	root.add_child(form_driver)
	var pony_form: INIT.ForceResult = initiation.force(runtime, CATALOG.MISSIONARY)
	check(not pony_form.ok and pony_form.reject.contains("pose:missionary"),
		"a pose whose forms exclude AnonPony is never offered")
	root.remove_child(form_driver)
	form_driver.free()
	game.headset_view = true
	var vr_bed: INIT.ForceResult = initiation.force(runtime, CATALOG.MISSIONARY)
	check(not vr_bed.ok and vr_bed.reject.contains("pose:missionary"),
		"a desktop-only pose is never offered in the headset view")
	game.headset_view = false

	# Cancelling a normal act-key start keeps the bed rest and the stretch choice for the act, but gives
	# the presentation back.
	var clears_before_y := runtime.stretch_clears
	initiation.force(runtime, CATALOG.STANDING)
	runtime.presented = true
	initiation.cancel_for(target)
	check(not runtime.presented, "cancel_for clears the presentation")
	check(runtime.stretch_clears == clears_before_y,
		"cancel_for keeps the stretch choice for the act")

	initiation.reset()
	check(runtime.presented == false and runtime.face_on == false,
		"reset leaves the runtime clean")

	# The scan names why it is blocked, once per reason change.
	initiation.reset()
	fake_main.debug_lines.clear()
	game.mares = [target]
	director.greet_ok = true
	director.state = "idle"
	director.characters = {"rarity": {"chat_last": 0.0}}
	initiation.tick(0.5)
	check(debug_count(fake_main, "request scan quiet reason=chat") == 1,
		"a recent chat logs one quiet reason")
	initiation.tick(0.5)
	check(debug_count(fake_main, "request scan quiet reason=chat") == 1,
		"the same quiet reason logs once")

	# A cooling mare names the cooldown. The fake world gives the cooldown store a save section.
	director.characters = {}
	var mods := root.get_node_or_null("Mods")
	var previous_game: Variant = null
	var fake_world: FakeGame = null
	if mods != null:
		previous_game = mods.get("game")
		fake_world = FakeGame.new()
		fake_world.world_context = context
		root.add_child(fake_world)
		mods.set("game", fake_world)
		COOLDOWNS.set_last("rarity")
	else:
		check(false, "the test world has a Mods autoload for the cooldown scan")
	initiation.reset()
	fake_main.debug_lines.clear()
	initiation.tick(0.5)
	check(debug_count(fake_main, "request scan skip id=rarity reasons=cooldown") == 1,
		"a cooling mare logs one scan skip")
	initiation.tick(0.5)
	check(debug_count(fake_main, "request scan skip id=rarity reasons=cooldown") == 1,
		"the same scan skip logs once")
	if mods != null:
		mods.set("game", previous_game)
		fake_world.free()

	# Show data's REQUEST rows cover cooldown, retry, phase and the live startable handoff.
	initiation.reset()
	game.mares = [target]
	runtime.presented = false
	director.greet_ok = true
	director._player_text = ""
	initiation.force(runtime, CATALOG.STANDING)
	director.transcript.emit("yes")
	initiation.tick(0.0)
	var request_text := "\n".join(initiation.debug_rows(target))
	check(request_text.contains("cooldown ready="), "the request rows name the cooldown")
	check(request_text.contains("retry left="), "the request rows name the retry")
	check(request_text.contains("episode phase=invite")
		and request_text.contains("startable=true"), "the request rows name the live invite")
	initiation.reset()
	check("\n".join(initiation.debug_rows(target)).contains("episode=none"),
		"the request rows clear with no episode")

	initiation.free()
	fake_main.free()
	game.free()
	director.free()
	runtime.free()
	context.free()
	player.free()
	target.free()
	other.free()
	memory.free()

	print("INITIATION_API_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("INITIATION_API_PASS")
	quit(0 if failures == 0 else 1)
