extends "res://mods/unfplap/tests/support/suite.gd"
## The pony roster: attach and detach, the prepare hooks, the adoption order with its duplicate
## guard, the character lists and the teardown.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/ponies/test_service.gd

const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const ACT_OWNER := preload("res://mods/unfplap/act_owner/service.gd")
const HANDLES := preload("res://mods/unfplap/world/handles.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")



class FakeIdentity extends Resource:
	var id := ""
	var display_name := ""
	var filly := false
	var stallion := false


class FakePony extends Node3D:
	var identity: Variant = null
	var rig: Variant = null


class FakeRuntime extends Node:
	var pony: Node = null
	var stopped := 0
	var adopted: Array[Node] = []
	var attached: Array[Node] = []
	var live_settings := 0
	var act: Variant = null

	func _init() -> void:
		act = self

	func _ready() -> void:
		add_to_group("unfplap_pony")

	func force_stop() -> void:
		stopped += 1

	func attach_to_body(parent: Node) -> void:
		attached.append(parent)
		reparent(parent)

	func adopt_body(new_pony: Node) -> void:
		pony = new_pony
		adopted.append(new_pony)

	func apply_live_settings() -> void:
		live_settings += 1


## The eligibility service one attached body passes through, with its calls recorded.
class FakeEligibility extends "res://mods/unfplap/tests/support/fakes/fake_eligibility.gd":
	pass


class FakeAnatomy extends ANATOMY:
	var journal: Array[String] = []
	var presented: Dictionary = {}

	func present(pony: Node3D, _form: BODY_FORM.BodyForm = null) -> void:
		if presented.has(pony):
			return
		presented[pony] = true
		journal.append("present:" + str(pony.name))

	func withdraw(pony: Node3D) -> void:
		presented.erase(pony)
		journal.append("withdraw:" + str(pony.name))


class FakeBodyChange extends "res://mods/unfplap/body_change/service.gd":
	var journal: Array[String] = []
	var installed: Array[String] = []

	func notify_body_ready(pony: Node3D) -> void:
		journal.append("form:" + str(pony.name))

	func form_for(_pony: Node3D) -> BODY_FORM.BodyForm:
		return null

	func installed_character_ids() -> Array[String]:
		return installed


class FakeSmack extends "res://mods/unfplap/stock_smack/api.gd":
	var journal: Array[String] = []

	func pony_ready(pony: Node) -> void:
		journal.append("ready:" + str(pony.name))

	func act_start(pony: Node) -> void:
		journal.append("start:" + str(pony.name))

	func act_end(pony: Node) -> void:
		journal.append("end:" + str(pony.name))


## A source whose claimed body is the one it is changing into, like a body-change provider.
class FakeSource extends Node:
	var next: Node = null

	func claims_body(pony: Node) -> bool:
		return is_instance_valid(next) and pony == next


func _pony(id: String, node_name := "Pony") -> FakePony:
	var pony := FakePony.new()
	pony.name = node_name
	var identity := FakeIdentity.new()
	identity.id = id
	identity.display_name = id.capitalize()
	pony.identity = identity
	pony.set_meta("relationship_id", id)
	return pony


## A clean roster with a factory that hands out a fresh fake runtime per body.
func _bind() -> Dictionary:
	var host := Node.new()
	host.name = "FakeHost"
	root.add_child(host)
	var anatomy := FakeAnatomy.new()
	anatomy.name = "FakeAnatomy"
	root.add_child(anatomy)
	var body_change := FakeBodyChange.new()
	body_change.name = "FakeBodyChange"
	root.add_child(body_change)
	var smack := FakeSmack.new()
	smack.name = "FakeSmack"
	root.add_child(smack)
	var owner := ACT_OWNER.new()
	owner.wire(null, null)
	var world := HANDLES.new()
	world.act_owner = owner
	world.anatomy = anatomy
	world.eligibility = FakeEligibility.new()
	world.body_change = body_change
	world.stock_smack = smack
	WORLD.bind_world(host)
	var roster := PONIES.new()
	roster.name = "UnfplapPonies"
	root.add_child(roster)
	roster.wire(world.anatomy, world.eligibility, world.act_gate, world.body_change,
		world.estrus, world.stock_smack, world.act_owner)
	var made: Array[FakeRuntime] = []
	roster.factory = func(pony: Node) -> Node:
		var runtime := FakeRuntime.new()
		runtime.name = "UnfplapRuntime"
		runtime.pony = pony
		made.append(runtime)
		return runtime
	return {"host": host, "anatomy": anatomy, "body_change": body_change, "smack": smack,
		"owner": owner, "roster": roster, "world": world, "made": made}


func _free(made: Dictionary) -> void:
	var roster: PONIES = made["roster"]
	roster.shutdown()
	root.remove_child(roster)
	roster.free()
	for key: String in ["host", "anatomy", "body_change", "smack"]:
		var node: Node = made[key]
		root.remove_child(node)
		node.free()
	(made["owner"] as Node).free()


func run() -> void:
	_check_attach()
	_check_detach()
	_check_player_pony()
	_check_prepare()
	_check_adoption()
	_check_duplicate_guard()
	_check_world_close()
	_check_character_lists()
	finish()


## A spawned body gets one runtime, bound to anatomy first, and the log names it.
func _check_attach() -> void:
	var f := _bind()
	var roster: PONIES = f["roster"]
	var anatomy: FakeAnatomy = f["anatomy"]
	var body_change: FakeBodyChange = f["body_change"]
	var smack: FakeSmack = f["smack"]
	var pony := _pony("fluttershy", "FluttershyBody")
	root.add_child(pony)
	roster.attach(pony)
	var runtime: Node = roster.runtime_for(pony)
	check(is_instance_valid(runtime), "an attached body gets one runtime")
	check(runtime.get_parent() == pony, "the runtime lives under its body")
	check(runtime.get("pony") == pony, "the factory hands the runtime its body")
	check(anatomy.journal == ["present:FluttershyBody"],
		"the prepare presents the body once")
	check(body_change.journal == ["form:FluttershyBody"], "the body is prepared once")
	check(smack.journal == ["ready:FluttershyBody"], "the smack layer is told about the body")
	roster.attach(pony)
	check(body_change.journal == ["form:FluttershyBody", "form:FluttershyBody"],
		"a second attach prepares again")
	var live: Array[Node] = roster.live_ponies()
	check(live.size() == 1 and live[0] == pony, "the roster lists the body once")
	root.remove_child(pony)
	pony.free()
	_free(f)


## A body leaving the tree leaves the live list; a bodiless lookup falls back to the node a
## runtime was parented under.
func _check_detach() -> void:
	var f := _bind()
	var roster: PONIES = f["roster"]
	var pony := _pony("rarity", "RarityBody")
	root.add_child(pony)
	roster.attach(pony)
	var runtime: Node = roster.runtime_for(pony)
	pony.remove_child(runtime)
	root.remove_child(pony)
	pony.free()
	check(roster.live_ponies().is_empty(), "a freed body leaves the live list")
	check(roster.runtime_for(null) == null, "a missing body has no runtime")
	var stray := _pony("stray", "StrayBody")
	root.add_child(stray)
	stray.add_child(runtime)
	check(roster.runtime_for(stray) == runtime, "a runtime found by name answers the lookup")
	roster.shutdown()
	stray.remove_child(runtime)
	runtime.free()
	root.remove_child(stray)
	stray.free()
	_free(f)


## The player's own body is a locomotion too and never takes a runtime.
func _check_player_pony() -> void:
	var f := _bind()
	var roster: PONIES = f["roster"]
	var player := _pony("anon", "PlayerPony")
	root.add_child(player)
	roster.attach(player)
	check(roster.runtime_for(player) == null, "the player's AnonPony gets no runtime")
	var rigged := _pony("rigged", "RiggedBody")
	rigged.rig = Node3D.new()
	root.add_child(rigged)
	roster.attach(rigged)
	check(roster.runtime_for(rigged) == null, "a body that is the player's rig gets no runtime")
	roster.shutdown()
	root.remove_child(player)
	player.free()
	root.remove_child(rigged)
	rigged.free()
	_free(f)


## Every prepare hook is idempotent; the late prepare needs a live entry.
func _check_prepare() -> void:
	var f := _bind()
	var roster: PONIES = f["roster"]
	var anatomy: FakeAnatomy = f["anatomy"]
	var body_change: FakeBodyChange = f["body_change"]
	var smack: FakeSmack = f["smack"]
	var pony := _pony("applejack", "ApplejackBody")
	root.add_child(pony)
	roster.prepare_late(pony)
	check(anatomy.journal == ["present:ApplejackBody"],
		"the late prepare presents the body once")
	check(body_change.journal == ["form:ApplejackBody"], "the late prepare fits the body")
	check(smack.journal == ["ready:ApplejackBody"], "the late prepare arms the smack layer")
	roster.prepare_late(pony)
	check(anatomy.journal.size() == 1, "a second late prepare presents nothing new")
	check(roster.runtime_for(pony) == null, "a prepare never creates a runtime")
	var host: Node = f["host"]
	WORLD.unbind()
	roster.prepare_late(pony)
	check(anatomy.journal.size() == 1, "a prepare without the entry does nothing")
	WORLD.bind_world(host)
	roster.shutdown()
	root.remove_child(pony)
	pony.free()
	_free(f)


## Suspend, adopt and drop the old body's entry, with the source's claim deciding the identity.
func _check_adoption() -> void:
	var f := _bind()
	var roster: PONIES = f["roster"]
	var anatomy: FakeAnatomy = f["anatomy"]
	var owner: ACT_OWNER = f["owner"]
	var pony := _pony("test_mare", "OldBody")
	root.add_child(pony)
	roster.attach(pony)
	var runtime: FakeRuntime = roster.runtime_for(pony)
	var source := FakeSource.new()
	var change := BODY_CHANGE.new()
	change.source = source
	runtime.pony = pony
	owner.begin_body_swap(runtime, pony, "test_mare", change)
	check(owner.body_swap_pending(), "a suspended act records one pending swap")
	check(roster.live_ponies().is_empty(), "the old body's live entry goes at the suspend")
	check(not owner.act_running(), "the pending swap is not an act start")

	# A body with another id is not the one this act waits for.
	var other := _pony("other_mare", "OtherBody")
	root.add_child(other)
	roster.attach(other)
	check(owner.body_swap_pending(), "another id leaves the pending swap alone")
	check(roster.runtime_for(other) != runtime, "another id gets its own runtime")

	var new_pony := _pony("test_mare", "NewBody")
	root.add_child(new_pony)
	source.next = new_pony
	roster.attach(new_pony)
	check(not owner.body_swap_pending(), "the new body adopts and clears the swap")
	check(roster.runtime_for(new_pony) == runtime, "the new body keeps the same runtime")
	check(runtime.get_parent() == new_pony, "the runtime moves under the new body")
	check(runtime.attached == [new_pony], "the runtime is reparented once")
	check(runtime.adopted == [new_pony], "the runtime adopts the new body once")
	check(runtime.pony == new_pony, "the runtime owns the new body")
	check(anatomy.journal.count("present:NewBody") == 1, "anatomy presents the adopted body once")

	# The runtime's own late adoption: the spawn hook never reached the attach.
	owner.begin_body_swap(runtime, new_pony, "test_mare", change)
	var late_pony := _pony("test_mare", "LateBody")
	root.add_child(late_pony)
	source.next = late_pony
	check(roster.adopt_pending_body(late_pony), "the watcher adopts the body the source claims")
	check(roster.runtime_for(late_pony) == runtime, "the late body keeps the same runtime")
	check(not owner.body_swap_pending(), "the late adoption clears the swap")

	# An unclaimed id and a dead runtime both refuse quietly.
	source.next = null
	owner.begin_body_swap(runtime, late_pony, "test_mare", change)
	var stranger := _pony("stranger", "StrangerBody")
	root.add_child(stranger)
	check(not roster.adopt_pending_body(stranger), "an unclaimed id is not adopted")
	owner.clear_body_swap(null)
	check(owner.body_swap_pending(), "another runtime cannot clear the swap")
	owner.clear_body_swap(runtime)
	check(not owner.body_swap_pending(), "the owning runtime clears its swap")
	owner.begin_body_swap(runtime, late_pony, "test_mare", null)
	check(not owner.body_swap_pending(), "a null change records no swap")

	roster.shutdown()
	source.free()
	for node: Node in [pony, other, new_pony, late_pony, stranger]:
		root.remove_child(node)
		node.free()
	_free(f)


## A runtime that a race created on the adopting body is dropped for the suspended act.
func _check_duplicate_guard() -> void:
	var f := _bind()
	var roster: PONIES = f["roster"]
	var anatomy: FakeAnatomy = f["anatomy"]
	var owner: ACT_OWNER = f["owner"]
	var pony := _pony("test_mare", "RaceOldBody")
	root.add_child(pony)
	roster.attach(pony)
	var runtime: FakeRuntime = roster.runtime_for(pony)
	# The race: the new body's spawn hook arrives before the act's swap is recorded, so it already
	# carries a runtime of its own when the adoption finds it.
	var new_pony := _pony("test_mare", "RaceNewBody")
	root.add_child(new_pony)
	roster.attach(new_pony)
	var duplicate: FakeRuntime = roster.runtime_for(new_pony)
	check(duplicate != runtime, "the race created its own runtime first")
	var source := FakeSource.new()
	source.next = new_pony
	var change := BODY_CHANGE.new()
	change.source = source
	owner.begin_body_swap(runtime, pony, "test_mare", change)
	check(roster.adopt_pending_body(new_pony),
		"the suspended act still adopts the body although another runtime held it")
	check(roster.runtime_for(new_pony) == runtime, "the act's runtime wins the body")
	check(duplicate.stopped == 1, "the duplicate is stopped once")
	check(duplicate.is_queued_for_deletion(), "the duplicate is freed")
	check(anatomy.journal.has("withdraw:RaceNewBody"),
		"the duplicate's anatomy controller is dropped before the act's present")

	roster.shutdown()
	source.free()
	for node: Node in [pony, new_pony]:
		root.remove_child(node)
		node.free()
	_free(f)


## A world close ends the act through its owner, drops the swap and keeps every runtime.
func _check_world_close() -> void:
	var f := _bind()
	var roster: PONIES = f["roster"]
	var owner: ACT_OWNER = f["owner"]
	var pony := _pony("twilight", "TwilightBody")
	root.add_child(pony)
	roster.attach(pony)
	var runtime: FakeRuntime = roster.runtime_for(pony)
	owner.set_active(runtime)
	var source := FakeSource.new()
	var change := BODY_CHANGE.new()
	change.source = source
	owner.begin_body_swap(runtime, pony, "twilight", change)
	# The adopted body registers the runtime again, as the real handover does.
	roster.attach(pony)
	roster.on_world_closed()
	check(runtime.stopped == 1, "the world close stops the act once")
	check(not owner.act_running(), "the world close frees the frame")
	check(not owner.body_swap_pending(), "the world close drops the pending swap")
	var live: Array[Node] = roster.live_ponies()
	check(live.size() == 1 and live[0] == pony,
		"the world close keeps the bodies' runtimes; they leave with their bodies")
	roster.shutdown()
	check(runtime.is_queued_for_deletion(), "the teardown frees the runtime")
	check(roster.live_ponies().is_empty(), "the teardown empties the live list")
	check(not roster.factory.is_valid(), "the teardown drops the runtime factory")
	source.free()
	root.remove_child(pony)
	pony.free()
	_free(f)


## The installed list and the live pass: one per runtime, not only the act's.
func _check_character_lists() -> void:
	var f := _bind()
	var roster: PONIES = f["roster"]
	var world: HANDLES = f["world"]
	var body_change: FakeBodyChange = f["body_change"]
	body_change.installed = ["chrysalis"]
	var installed: Array[String] = roster.installed_character_ids()
	check(installed == ["chrysalis"], "the installed list comes from the body-change service")
	check(roster.live_character_ids().has("chrysalis"),
		"an installed mare is listed without a live body")
	var real_eligibility := ELIGIBILITY.new()
	roster.wire(world.anatomy, real_eligibility, world.act_gate, world.body_change, world.estrus,
		world.stock_smack, world.act_owner)
	var pony := _pony("sunny_star", "SunnyBody")
	root.add_child(pony)
	roster.attach(pony)
	var runtime: FakeRuntime = roster.runtime_for(pony)
	check(roster.live_character_ids().has("sunny_star"),
		"a live adult mare with a runtime is listed")
	roster.apply_live_settings()
	check(runtime.live_settings == 1, "the live pass reaches a runtime that is not acting")
	var bare := PONIES.new()
	bare.wire(null, null, null, null, null, null, null)
	check(bare.installed_character_ids().is_empty(),
		"without the service the installed list is empty")
	bare.free()

	roster.shutdown()
	root.remove_child(pony)
	pony.free()
	_free(f)
