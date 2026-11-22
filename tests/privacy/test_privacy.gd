extends "res://mods/unfplap/tests/support/suite.gd"
## The privacy provider: house/outdoors, target exclusion, the other-mare radius, the offer vs.
## cuddle kind and the world house lookup. A fake house and fake mares; no live world.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/privacy/test_privacy.gd

const WORLD := preload("res://mods/unfplap/world/service.gd")
const PRIVACY := preload("res://mods/unfplap/privacy/service.gd")
const PRIVACY_RULES := preload("res://mods/unfplap/shared/privacy_rules.gd")


class FakeHouse extends Node3D:
	func _reach_squared() -> float:
		return 100000000.0

	func contains(point: Vector3) -> bool:
		return absf(point.x) < 10.0 and absf(point.z) < 10.0


class FakeGame extends Node:
	var mares: Array = []


class FakePony extends Node3D:
	var identity: Dictionary = {}

	func _init(id: String) -> void:
		identity = {"id": id, "filly": false, "stallion": false}
		name = id


class FixtureHost extends Node:
	var player: Node3D
	var game: Node


func run() -> void:
	var main := FixtureHost.new()
	var game := FakeGame.new()
	var player := Node3D.new()
	var target := FakePony.new("target")
	var other := FakePony.new("other")
	root.add_child(main)
	main.add_child(game)
	main.add_child(player)
	main.add_child(target)
	main.add_child(other)
	main.player = player
	WORLD.bind_player(main.player)
	main.game = game
	WORLD.bind_world(main.game)

	var provider := PRIVACY.new()

	# Outdoors with nobody near: both kinds are private.
	game.mares = [target]
	player.global_position = Vector3.ZERO
	target.global_position = Vector3(1.0, 0.0, 0.0)
	other.global_position = Vector3(100.0, 0.0, 0.0)
	check(WORLD.house_at(Vector3.ZERO) == null, "outdoors has no house")
	check(provider.is_private(target), "the solo offer is private")
	check(provider.is_private(target, PRIVACY.Kind.CUDDLE), "the solo cuddle is private")

	# The target is excluded from its own other-mare checks.
	game.mares = [target, other]
	check(provider.is_private(target) and provider.is_private(target, PRIVACY.Kind.CUDDLE),
		"the target does not count as another mare")

	# Another mare within the radius makes both kinds public outdoors.
	other.global_position = Vector3(30.0, 0.0, 0.0)
	check(not provider.is_private(target), "a nearby mare makes the offer public")
	check(not provider.is_private(target, PRIVACY.Kind.CUDDLE),
		"a nearby mare makes the cuddle public")
	other.global_position = Vector3(30.01, 0.0, 0.0)
	check(provider.is_private(target) and provider.is_private(target, PRIVACY.Kind.CUDDLE),
		"just past the radius is private")

	# Indoors the house is the bound for a cuddle; the offer rule still uses house solitude.
	var house := FakeHouse.new()
	root.add_child(house)
	house.add_to_group("house_interiors")
	other.global_position = Vector3(100.0, 0.0, 0.0)
	check(WORLD.house_at(Vector3.ZERO) == house, "the fake house is found")
	check(provider.is_private(target, PRIVACY.Kind.CUDDLE),
		"an indoor cuddle with the house empty is private")
	other.global_position = Vector3(1.0, 0.0, 0.0)
	check(not provider.is_private(target, PRIVACY.Kind.CUDDLE),
		"an indoor cuddle needs house solitude")
	check(not provider.is_private(target), "a near indoor mare also fails the offer rule")

	# House solitude allows an offer even when a mare is outdoors within the radius.
	other.global_position = Vector3(20.0, 0.0, 0.0)
	check(provider.is_private(target), "house solitude allows the offer")
	check(provider.is_private(target, PRIVACY.Kind.CUDDLE),
		"an indoor cuddle ignores the outdoor mare")

	# No world bound: every answer is public (fail closed to not-private).
	WORLD.unbind()
	var unbound := PRIVACY.new()
	check(not unbound.is_private(target), "a provider outside a world is not private")
	check(not unbound.is_private(target, PRIVACY.Kind.CUDDLE),
		"a provider outside a world is not cuddle-private")
	WORLD.bind_world(main.game)
	WORLD.bind_player(main.player)

	# The pure cuddle rule: outdoors only the nearby mares matter, indoors only the house.
	check(PRIVACY_RULES.cuddle_private(false, false, false),
		"an outdoor cuddle needs no house and no near pony")
	check(PRIVACY_RULES.cuddle_private(false, true, false),
		"an outdoor cuddle ignores the house state")
	check(not PRIVACY_RULES.cuddle_private(false, false, true),
		"a nearby pony blocks an outdoor cuddle")

	main.queue_free()
	house.queue_free()
	finish()