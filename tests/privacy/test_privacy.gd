extends SceneTree
## The privacy provider: house/outdoors, target exclusion, the other-mare radius, the offer vs.
## cuddle rule. A fake house and fake mares; no live world.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/privacy/test_privacy.gd

const WORLD := preload("res://mods/unfplap/world/service.gd")
const PRIVACY := preload("res://mods/unfplap/privacy/service.gd")
const PRIVACY_RULES := preload("res://mods/unfplap/shared/privacy_rules.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


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


class FakeMain extends Node:
	var player: Node3D
	var game: Node


func run() -> void:
	var main := FakeMain.new()
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

	# Outdoors with nobody near.
	game.mares = [target]
	player.global_position = Vector3.ZERO
	target.global_position = Vector3(1.0, 0.0, 0.0)
	other.global_position = Vector3(100.0, 0.0, 0.0)
	var alone := provider.state_for(target)
	check(alone.house == null and not alone.indoors, "outdoors has no house")
	check(not alone.house_alone, "outdoors has no house solitude")
	check(not alone.others_near, "a distant mare is not near")
	check(alone.offer_private and alone.cuddle_private, "the solo offer and cuddle are private")

	# The target is excluded from its own other-mare checks.
	game.mares = [target, other]
	var excluded := provider.state_for(target)
	check(excluded.offer_private and excluded.cuddle_private,
		"the target does not count as another mare")

	# Another mare within the radius makes both public outdoors.
	other.global_position = Vector3(30.0, 0.0, 0.0)
	var near := provider.state_for(target)
	check(near.others_near, "the radius admits 30 m")
	check(not near.offer_private and not near.cuddle_private, "a nearby mare makes it public")
	other.global_position = Vector3(30.01, 0.0, 0.0)
	check(provider.state_for(target).offer_private, "just past the radius is private")

	# Indoors the house is the bound for a cuddle; the offer rule still uses house solitude.
	var house := FakeHouse.new()
	root.add_child(house)
	house.add_to_group("house_interiors")
	other.global_position = Vector3(100.0, 0.0, 0.0)
	var indoor := provider.state_for(target)
	check(indoor.indoors and indoor.house == house, "the fake house is found")
	check(indoor.house_alone, "one mare indoors is alone")
	check(indoor.cuddle_private, "an indoor cuddle with the house empty is private")
	other.global_position = Vector3(1.0, 0.0, 0.0)
	var crowded := provider.state_for(target)
	check(not crowded.house_alone, "another mare in the house breaks house solitude")
	check(not crowded.cuddle_private, "an indoor cuddle needs house solitude")
	check(not crowded.offer_private, "a near indoor mare also fails the offer rule")

	# House solitude allows an offer even when a mare is outdoors within the radius.
	other.global_position = Vector3(20.0, 0.0, 0.0)
	var house_alone_near := provider.state_for(target)
	check(house_alone_near.house_alone, "the house is still empty")
	check(house_alone_near.others_near, "the outdoor mare is still within the radius")
	check(house_alone_near.offer_private, "house solitude allows the offer")
	check(house_alone_near.cuddle_private, "an indoor cuddle ignores the outdoor mare")

	# No world bound: every answer is public (fail closed to not-private).
	WORLD.unbind()
	var unbound := PRIVACY.new()
	check(not unbound.offer_private(target), "a provider outside a world is not private")
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
	print("PRIVACY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
