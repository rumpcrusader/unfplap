extends SceneTree
## The request cooldown store: the `request_times` read, the history wait with the heat shortening,
## and the set/clear round trip. No world file is written outside the throwaway data dir.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/initiation/test_cooldowns.gd

const COOLDOWNS := preload("res://mods/unfplap/initiation/cooldowns.gd")

var failures := 0
var checks := 0


class FakeGame extends Node:
	var world_context: Node


class FakeWorldContext extends Node:
	var state: Dictionary = {}
	var changed := 0

	func _changed() -> void:
		changed += 1


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var now := Time.get_unix_time_from_system()
	var empty := {COOLDOWNS.KEY: {}}
	check(COOLDOWNS.last(empty, "rarity") < 0.0, "no stored clock reads as never")
	check(COOLDOWNS.ready(empty, "rarity", now, false), "a first offer is ready")

	var stored := {COOLDOWNS.KEY: {"rarity": now - 200.0}}
	check(not COOLDOWNS.ready(stored, "rarity", now, false),
		"a fresh cooldown blocks the offer")
	check(COOLDOWNS.ready(stored, "rarity", now, true),
		"heat quarters the history cooldown")
	check(COOLDOWNS.last(stored, "rarity") == now - 200.0, "the store returns the stamped clock")

	var old := {COOLDOWNS.KEY: {"rarity": now - 700.0}}
	check(COOLDOWNS.ready(old, "rarity", now, false), "an expired cooldown frees the offer")

	# The writers: a live Mods autoload with a fake world context gives the real round trip;
	# otherwise they stay quiet.
	var mods := root.get_node_or_null("Mods")
	if mods == null:
		COOLDOWNS.set_last("cooldown_test")
		COOLDOWNS.clear("cooldown_test")
		check(COOLDOWNS.section().is_empty(), "no world means no stored cooldown")
	else:
		var previous_game: Variant = mods.get("game")
		var fake_game := FakeGame.new()
		var fake_context := FakeWorldContext.new()
		fake_game.world_context = fake_context
		root.add_child(fake_game)
		root.add_child(fake_context)
		mods.set("game", fake_game)
		COOLDOWNS.set_last("cooldown_test")
		check(fake_context.changed >= 1, "a stamped cooldown marks the world dirty")
		check(not COOLDOWNS.ready(COOLDOWNS.section(), "cooldown_test",
			Time.get_unix_time_from_system(), false), "a set cooldown blocks the offer")
		COOLDOWNS.clear("cooldown_test")
		check(COOLDOWNS.ready(COOLDOWNS.section(), "cooldown_test",
			Time.get_unix_time_from_system(), false), "a cleared cooldown frees the offer")
		mods.set("game", previous_game)
		fake_game.free()
		fake_context.free()

	print("INITIATION_COOLDOWNS_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("INITIATION_COOLDOWNS_PASS")
	quit(0 if failures == 0 else 1)
