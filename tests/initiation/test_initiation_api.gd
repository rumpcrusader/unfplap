extends SceneTree
## The request service facade: typed force results, privacy gathering, the consent transcript, the
## episode lifecycle and cancellation. No world file is touched.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/initiation/test_initiation_api.gd

const INIT := preload("res://mods/unfplap/initiation.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility.gd")
const CATALOG := preload("res://mods/unfplap/poses/catalog.gd")

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

	func debug(_text: String) -> void:
		pass


class FakeGame extends Node:
	var mares: Array = []
	var world_context: Node


class FakeWorldContext extends Node:
	var keys: Array[String] = []

	func record(_kind: String, _text: String, _ids: Array, _witnesses: Array, key: String) -> void:
		keys.append(key)


class FakeRuntime extends Node:
	var pony: Node3D
	var state := 0
	var presented := false
	var phase := "normal"
	var face_on := false

	func cuddle_active() -> bool:
		return false

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

	func cycle_phase() -> String:
		return phase


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var fake_main := FakeMain.new()
	fake_main.name = "FakeMain"
	root.add_child(fake_main)
	var fake_game := FakeGame.new()
	root.add_child(fake_game)
	var player := Node3D.new()
	root.add_child(player)
	var target := Node3D.new()
	target.name = "Rarity"
	target.set_meta("relationship_id", "rarity")
	root.add_child(target)
	var other := Node3D.new()
	other.global_position = Vector3(2.0, 0.0, 0.0)
	root.add_child(other)
	var context := FakeWorldContext.new()
	root.add_child(context)
	var fake_runtime := FakeRuntime.new()
	fake_runtime.pony = target
	root.add_child(fake_runtime)

	fake_game.world_context = context
	fake_game.mares = [target]
	fake_main.player = player
	fake_main.game = fake_game
	fake_main.runtimes[target] = fake_runtime
	fake_main.eligibility = ELIGIBILITY.new()
	fake_main.eligibility.setup(fake_main)

	var initiation := INIT.new()
	initiation.name = "UnfplapInitiation"
	initiation.call("setup", fake_main)
	root.add_child(initiation)

	# Privacy: the offering mare is never "another pony", a nearby one blocks, heat overrides.
	check(initiation._private_at_player(target),
		"the offering mare is not another pony")
	fake_game.mares = [target, other]
	check(not initiation._private_at_player(target),
		"a third nearby pony blocks private")
	fake_runtime.phase = "heat"
	check(initiation._private_at_player(target), "heat overrides the privacy reserve")
	fake_runtime.phase = "normal"
	check(not initiation._private_at_player(target),
		"normal phase restores the privacy reserve")
	fake_game.mares = [target]

	# Consent: a local yes moves the episode to the presentation, a local no closes it.
	var episode := INIT.Episode.new()
	episode.serial = 7
	episode.pony = target
	episode.runtime = fake_runtime
	episode.id = "rarity"
	episode.pose = CATALOG.STANDING
	episode.private = true
	episode.phase = INIT.Phase.ASK
	initiation._serial = 7
	initiation._episode = episode
	initiation._on_player_transcript("yes")
	check(fake_runtime.presented, "a private yes presents")
	check(episode.phase == INIT.Phase.PRESENT, "a private yes moves to present")
	check(context.keys.size() == 1, "an accepted situation is recorded")

	fake_runtime.presented = false
	var declined := INIT.Episode.new()
	declined.serial = 8
	declined.pony = target
	declined.runtime = fake_runtime
	declined.id = "rarity"
	declined.pose = CATALOG.STANDING
	declined.private = true
	declined.phase = INIT.Phase.ASK
	initiation._serial = 8
	initiation._episode = declined
	initiation._on_player_transcript("no")
	check(not fake_runtime.presented, "a private no does not present")
	check(initiation._episode == null, "a private no ends the offer")

	# The typed force result replaces the side-channel reason.
	var missing: INIT.ForceResult = initiation.force(null)
	check(not missing.ok and missing.reject == "no_runtime",
		"force rejects a missing runtime")
	fake_runtime.state = 1
	var busy: INIT.ForceResult = initiation.force(fake_runtime)
	check(not busy.ok and busy.reject.contains("state=1"),
		"force reports the runtime state")
	fake_runtime.state = 0

	# Cancelling a normal Y start gives the presentation back.
	fake_runtime.presented = true
	initiation.cancel_for(target)
	check(not fake_runtime.presented, "cancel_for clears the presentation")

	# Reset closes the episode and clears the session maps.
	var live := INIT.Episode.new()
	live.serial = 9
	live.pony = target
	live.runtime = fake_runtime
	live.id = "rarity"
	live.pose = CATALOG.STANDING
	live.phase = INIT.Phase.ASK
	initiation._episode = live
	initiation._retry_at["rarity"] = 1.0
	initiation.reset()
	check(initiation._episode == null, "reset closes the episode")
	check(initiation._retry_at.is_empty(), "reset clears the retry map")

	initiation.free()
	fake_main.free()
	fake_game.free()
	fake_runtime.free()
	context.free()
	player.free()
	target.free()
	other.free()

	print("INITIATION_API_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("INITIATION_API_PASS")
	quit(0 if failures == 0 else 1)
