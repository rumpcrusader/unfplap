extends "res://mods/unfplap/tests/support/suite.gd"
## The entry's ordered service list: every lifecycle broadcast walks the list in order, the scene
## facade is bound around it, and a world close and the process exit share one release sequence.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/entry/test_services.gd
##
## The suite loads `main.gd` with the service list replaced by stand-ins, so it proves the entry's
## own loops; the real services are each tested by their own contract suite.

const MAIN := preload("res://mods/unfplap/main.gd")
const SERVICE := preload("res://mods/unfplap/shared/service.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")

## Every hook call, in the order the entry made it: `<id>.<hook>`.
var order: Array = []


## A base service with all four hooks. It records the hook, and the world root and player the scene
## facade held at that moment, so a broadcast that runs outside the bind or the unbind shows.
class StandIn extends "res://mods/unfplap/shared/service.gd":
	var id: String
	var sink: Array
	var seen_world: Array = []
	var seen_player: Array = []

	func on_world(_host: Node) -> void:
		sink.append("%s.on_world" % id)
		seen_world.append(WORLD.world_root())
		seen_player.append(WORLD.player_rig())

	func on_world_closed() -> void:
		sink.append("%s.on_world_closed" % id)
		seen_world.append(WORLD.world_root())
		seen_player.append(WORLD.player_rig())

	func on_player(_body: Node) -> void:
		sink.append("%s.on_player" % id)
		seen_world.append(WORLD.world_root())
		seen_player.append(WORLD.player_rig())

	func shutdown() -> void:
		sink.append("%s.shutdown" % id)
		seen_world.append(WORLD.world_root())
		seen_player.append(WORLD.player_rig())


func _stand_in(id: String) -> StandIn:
	var service := StandIn.new()
	service.id = id
	service.sink = order
	return service


func run() -> void:
	var entry: Variant = MAIN.new()
	entry.name = "Unfplap"
	# The entry never enters the tree here: `_ready()` would build the real services. The list is
	# the only entry state the broadcasts read, so stand-ins drive it directly.
	var first := _stand_in("first")
	var middle := _stand_in("middle")
	var last := _stand_in("last")
	var services: Array[Node] = [first, middle, last]
	entry.set("_services", services)

	var host := Node.new()
	host.name = "FakeWorld"
	root.add_child(host)
	var body := Node3D.new()
	body.name = "FakePlayer"
	root.add_child(body)

	_check_world(entry, first, last, host)
	_check_player(entry, first, last, body)
	_check_close(entry, first, last, host)
	_check_exit(entry, first, last)
	_check_attach()
	_check_hooks()
	_check_scope_children()

	root.remove_child(body)
	body.free()
	root.remove_child(host)
	host.free()
	entry.free()
	WORLD.unbind()
	finish()


## `_on_world`: every `on_world` in list order, each one with the scene facade already bound.
func _check_world(entry: Variant, first: StandIn, last: StandIn, host: Node) -> void:
	order.clear()
	entry.call("_on_world", host)
	check(order == ["first.on_world", "middle.on_world", "last.on_world"],
		"the entry broadcasts on_world in list order")
	check(first.seen_world == [host] and last.seen_world == [host],
		"the scene facade is bound before the first service's on_world")
	check(first.seen_player == [null], "the first world enter has no player yet")
	entry.call("_on_world", host)
	check(order.size() == 6, "a second world enter broadcasts again")


## `_on_player`: every `on_player` in list order, each one with the player already bound.
func _check_player(entry: Variant, first: StandIn, last: StandIn, body: Node3D) -> void:
	order.clear()
	entry.call("_on_player", body)
	check(order == ["first.on_player", "middle.on_player", "last.on_player"],
		"the entry broadcasts on_player in list order")
	check(first.seen_player.back() == body and last.seen_player.back() == body,
		"the scene facade holds the player before the first service's on_player")


## `_on_world_closed`: every `on_world_closed` in list order while the facade is still bound, and
## the unbind after the last one.
func _check_close(entry: Variant, first: StandIn, last: StandIn, host: Node) -> void:
	order.clear()
	entry.call("_on_world_closed", host)
	check(order == ["first.on_world_closed", "middle.on_world_closed", "last.on_world_closed"],
		"the entry broadcasts on_world_closed in list order")
	check(first.seen_world.back() == host and last.seen_world.back() == host,
		"the scene facade stays bound until the last service has closed")
	check(WORLD.world_root() == null, "the unbind follows the whole list")


## `_exit_tree`: the same release sequence a world close runs, then every `shutdown()` in reverse
## list order.
func _check_exit(entry: Variant, first: StandIn, last: StandIn) -> void:
	var host := Node.new()
	WORLD.bind_world(host)
	order.clear()
	var mark: int = first.seen_world.size()
	var last_mark: int = last.seen_world.size()
	entry.call("_exit_tree")
	check(order == [
		"first.on_world_closed", "middle.on_world_closed", "last.on_world_closed",
		"last.shutdown", "middle.shutdown", "first.shutdown",
	], "the process exit runs the world-close sequence, then shutdown in reverse list order")
	check(first.seen_world[mark] != null and last.seen_world[last_mark] != null,
		"the process exit releases the services with the scene facade still bound")
	check(first.seen_world.back() == null, "the process exit unbinds the scene facade")
	check((entry.get("_services") as Array).is_empty(), "the process exit empties the list")
	host.free()


## `_attach`: a World service is named, parented under the entry, joined to the world group and
## appended to the one ordered list in attach order, which is the broadcast order.
func _check_attach() -> void:
	var builder: Variant = MAIN.new()
	var first := StandIn.new()
	first.id = "first"
	builder.call("_attach", first, "UnfplapFake")
	check(first.name == "UnfplapFake", "_attach names the service")
	check(first.get_parent() == builder, "_attach parents the service under the entry")
	check(first.is_in_group("unfplap_world"), "_attach joins the service to the world group")
	var services: Array = builder.get("_services")
	check(services.size() == 1 and services[0] == first,
		"_attach appends the service to the one ordered list")
	var second := StandIn.new()
	second.id = "second"
	builder.call("_attach", second, "UnfplapSecond")
	var ordered: Array = builder.get("_services")
	check(ordered.size() == 2 and ordered[1] == second,
		"_attach appends in attach order, which is the broadcast order")
	builder.free()


## `_assert_children`: a direct child outside the world group is named; the API node is exempt.
func _check_scope_children() -> void:
	var builder: Variant = MAIN.new()
	var api := Node.new()
	api.name = "UnfplapApi"
	builder.add_child(api)
	builder.call("_attach", _stand_in("first"), "UnfplapFake")
	var quiet: bool = LOG.enabled
	LOG.enabled = true
	check(int(builder.call("_assert_children")) == 0,
		"a World service and the API node are the only direct children")
	var stray := Node.new()
	stray.name = "Stray"
	builder.add_child(stray)
	check(int(builder.call("_assert_children")) == 1,
		"a direct child outside the world group is reported")
	LOG.enabled = quiet
	builder.free()


## `_assert_hooks`: a list member with no hooks is counted and named; the base stand-ins pass.
func _check_hooks() -> void:
	var builder: Variant = MAIN.new()
	var plain := Node.new()
	plain.name = "NoHooks"
	var services: Array[Node] = [plain]
	builder.set("_services", services)
	check(int(builder.call("_assert_hooks")) == 1, "a list member without hooks is reported")
	var stand_in := StandIn.new()
	var good: Array[Node] = [stand_in]
	builder.set("_services", good)
	check(int(builder.call("_assert_hooks")) == 0, "a base service carries all four hooks")
	plain.free()
	stand_in.free()
	builder.free()
