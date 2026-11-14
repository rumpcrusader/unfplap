extends SceneTree
## The request service through its public path: `force()` builds a standing ask against a fake
## director and runtime, the director's transcript drives the consent flow, and every assertion is
## an observable effect. No private member is touched.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/initiation/test_initiation_api.gd

const INIT := preload("res://mods/unfplap/initiation/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
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

	func runtime_for(pony: Node) -> Node:
		var runtime: Variant = runtimes.get(pony)
		return runtime if is_instance_valid(runtime) else null

	func menu_open() -> bool:
		return false

	func camera() -> Camera3D:
		return null

	func bed_occupied(_bed: Node3D, _target: Node) -> bool:
		return false

	func debug(_text: String) -> void:
		pass


class FakeGame extends Node:
	var mares: Array = []
	var world_context: Node


class FakeWorldContext extends Node:
	var keys: Array[String] = []
	var texts: Array[String] = []

	func record(_kind: String, text: String, _ids: Array, _witnesses: Array, key: String) -> void:
		keys.append(key)
		texts.append(text)


class FakeNavigator extends Node:
	var reserved_by := ""
	var command_owner := ""
	var wander_enabled := true
	var command_speed_limit: Variant = INF
	var command_pace_target: Variant = -1.0
	var _has_target := false

	func stay() -> void:
		_has_target = false

	func command_support(point: Vector3) -> Vector3:
		return point

	func command_destination(_point: Vector3, _gait: String) -> bool:
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


func run() -> void:
	var fake_main := FakeMain.new()
	root.add_child(fake_main)
	var game := FakeGame.new()
	root.add_child(game)
	var player := Node3D.new()
	root.add_child(player)
	var target := Node3D.new()
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

	game.world_context = context
	game.mares = [target]
	fake_main.player = player
	fake_main.game = game
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
	check(context.keys.size() == 1 and context.keys[0].ends_with(":situation"),
		"the ask records one situation")

	# A local yes waits for the ask line to finish, then presents and queues the invitation.
	director.state = "speaking"
	director.transcript.emit("yes")
	check(not runtime.presented, "a private yes waits for the offer line")
	initiation.tick(0.0)
	check(not runtime.presented, "a speaking offer still waits")
	check(context.keys.size() == 2 and context.keys[1].ends_with(":accepted"),
		"an accepted situation is recorded")
	director.state = "idle"
	initiation.tick(0.0)
	check(runtime.presented, "the presentation starts after the offer line")
	check(director.queued.size() == 1, "the presentation queues one invitation")
	check(director.queued[0].begins_with("unfplap:request:rarity:")
		and director.queued[0].ends_with(":invite"), "the invitation key names the request")

	# The queued ask key uses the same shape when the greeting cannot open the line.
	initiation.reset()
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

	# A closed start gate after the settled presentation closes the accepted offer instead of
	# inviting her.
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
	check(not runtime.presented and not runtime.face_on,
		"the closed start gate closes the accepted offer before the invite")
	runtime.start_ok = true

	# The typed force result replaces the side-channel reason.
	var missing: INIT.ForceResult = initiation.force(null)
	check(not missing.ok and missing.reject == "no_runtime",
		"force rejects a missing runtime")
	runtime.state = 1
	var busy: INIT.ForceResult = initiation.force(runtime)
	check(not busy.ok and busy.reject.contains("state=1"),
		"force reports the runtime state")
	runtime.state = 0

	# Cancelling a normal Y start keeps the bed rest and the stretch choice for the act, but gives
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

	initiation.free()
	fake_main.free()
	game.free()
	director.free()
	runtime.free()
	context.free()
	player.free()
	target.free()
	other.free()

	print("INITIATION_API_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("INITIATION_API_PASS")
	quit(0 if failures == 0 else 1)
