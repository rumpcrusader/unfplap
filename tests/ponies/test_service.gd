extends "res://mods/unfplap/tests/support/suite.gd"
## The pony registry: attach and detach, the live act pointer, the serial allocator, the prepare
## hooks, the adoption order with its duplicate guard, the character lists and the teardown.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/ponies/test_service.gd

const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
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


## A standing body the cone scan reads; the hook lets a test grow the live mare array mid-pass.
class ConePony extends Node3D:
	var requested := "stand"
	var hook := Callable()

	func posture_status() -> Dictionary:
		if hook.is_valid():
			hook.call()
		return {"requested": requested}


## The act-target rule: the ponies this fixture allows, with one call per answer.
class Targets extends ELIGIBILITY:
	var allowed: Array = []
	var calls := 0

	func eligible(pony: Node, _target: Target = Target.ACT) -> bool:
		calls += 1
		return allowed.has(pony)


class FakeGame extends Node:
	var mares: Array = []


class FakeRuntime extends Node:
	var pony: Node = null
	var stopped := 0
	var adopted: Array[Node] = []
	var attached: Array[Node] = []
	var live_settings := 0
	var act: Variant = null

	func _init() -> void:
		act = self

	func force_stop() -> void:
		stopped += 1
		PONIES.clear_active(self)

	func attach_to_body(parent: Node) -> void:
		attached.append(parent)
		reparent(parent)

	func adopt_body(new_pony: Node) -> void:
		pony = new_pony
		adopted.append(new_pony)

	func apply_live_settings() -> void:
		live_settings += 1


## The three services one attached body passes through, with their calls in order.
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

	func reseat_tail(pony: Node3D, _form: BODY_FORM.BodyForm = null) -> void:
		journal.append("tail:" + str(pony.name))

	func withdraw(pony: Node3D) -> void:
		presented.erase(pony)
		journal.append("withdraw:" + str(pony.name))

	func withdraw_tail(pony: Node3D) -> void:
		journal.append("untail:" + str(pony.name))


class FakeBodyChange extends Node:
	var journal: Array[String] = []
	var installed: Array[String] = []

	func notify_body_ready(pony: Node) -> void:
		journal.append("form:" + str(pony.name))

	func form_for(_pony: Node3D) -> Variant:
		return null

	func installed_character_ids() -> Array[String]:
		return installed


class FakeSmack extends Node:
	var journal: Array[String] = []

	func pony_ready(pony: Node) -> void:
		journal.append("ready:" + str(pony.name))

	func act_start(pony: Node) -> void:
		journal.append("start:" + str(pony.name))

	func act_end(pony: Node) -> void:
		journal.append("end:" + str(pony.name))


class FakeOffer extends Node:
	var cleared := 0

	func clear_current() -> void:
		cleared += 1


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


## A clean registry with a factory that hands out a fresh fake runtime per body.
func _bind() -> Dictionary:
	PONIES.shutdown()
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
	var offer := FakeOffer.new()
	offer.name = "FakeOffer"
	root.add_child(offer)
	var made: Array[FakeRuntime] = []
	WORLD.bind_world(host)
	PONIES.anatomy = anatomy
	PONIES.eligibility = FakeEligibility.new()
	PONIES.body_change = body_change
	PONIES.stock_smack = smack
	PONIES.offer = offer
	PONIES.factory = func(pony: Node) -> Node:
		var runtime := FakeRuntime.new()
		runtime.name = "UnfplapRuntime"
		runtime.pony = pony
		made.append(runtime)
		return runtime
	return {"host": host, "anatomy": anatomy, "body_change": body_change, "smack": smack,
		"offer": offer, "made": made}


func _free(made: Dictionary) -> void:
	PONIES.shutdown()
	for key: String in ["host", "anatomy", "body_change", "smack", "offer"]:
		var node: Node = made[key]
		root.remove_child(node)
		node.free()


func run() -> void:
	_check_cone_target()
	_check_attach()
	_check_detach()
	_check_player_pony()
	_check_active()
	_check_serial()
	_check_prepare()
	_check_adoption()
	_check_duplicate_guard()
	_check_world_close()
	_check_character_lists()
	finish()


## The standing cone scan: one live pass over the game's mares, eligibility only for the winner.
func _check_cone_target() -> void:
	var game := FakeGame.new()
	game.name = "ConeGame"
	root.add_child(game)
	WORLD.bind_world(game)
	var targets := Targets.new()
	PONIES.eligibility = targets
	var eye := Vector3(0.0, 1.6, 3.2)
	var near := _cone_mare(Vector3(0.0, 0.0, 2.6), "Near")
	var farther := _cone_mare(Vector3(0.0, 0.0, 1.8), "Farther")
	var stallion := _cone_mare(Vector3(0.0, 0.0, 2.8), "Stallion")
	var outside := _cone_mare(Vector3(0.0, 0.0, 2.0), "Outside")
	outside.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	var lying := _cone_mare(Vector3(0.0, 0.0, 2.4), "Lying")
	lying.requested = "lie_down"
	var beyond := _cone_mare(Vector3(0.0, 0.0, 0.5), "Beyond")
	game.mares = [near, farther, outside, lying, beyond]
	targets.allowed = [near, farther, outside, lying, beyond]
	check(PONIES.cone_target(eye) == near, "the nearest standing mare in the fan wins")
	check(targets.calls == 1, "eligibility is asked only for the winner")
	targets.calls = 0
	game.mares = [stallion, farther]
	targets.allowed = [farther]
	check(PONIES.cone_target(eye) == farther,
		"a nearer body that is not an act target is skipped")
	check(targets.calls == 2, "the nearer non-target is checked before the target")
	targets.calls = 0
	game.mares = [farther, outside, lying, beyond]
	check(PONIES.cone_target(eye) == farther,
		"the nearer allowed standing mare wins over a lying or out-of-fan one")
	check(targets.calls == 1, "the winner's eligibility is read once")

	# The scan walks the game's own array: a mare appended during the pass is seen by it.
	var grower := _cone_mare(Vector3(0.0, 0.0, 2.0), "Grower")
	var newcomer := _cone_mare(Vector3(0.0, 0.0, 2.6), "Newcomer")
	game.mares = [grower]
	targets.allowed = [grower, newcomer]
	grower.hook = func() -> void: game.mares.append(newcomer)
	check(PONIES.cone_target(eye) == newcomer,
		"the scan walks the game's live mare array, not a copy")
	grower.hook = Callable()
	game.mares = []

	for pony: Node in [near, farther, stallion, outside, lying, beyond, grower, newcomer]:
		if pony.get_parent() != null:
			pony.get_parent().remove_child(pony)
		pony.free()
	PONIES.eligibility = null
	root.remove_child(game)
	game.free()
	WORLD.unbind()


func _cone_mare(at: Vector3, mare_name: String) -> ConePony:
	var pony := ConePony.new()
	pony.name = mare_name
	root.add_child(pony)
	pony.global_position = at
	return pony


## A spawned body gets one runtime, bound to anatomy first, and the log names it.
func _check_attach() -> void:
	var f := _bind()
	var anatomy: FakeAnatomy = f["anatomy"]
	var body_change: FakeBodyChange = f["body_change"]
	var smack: FakeSmack = f["smack"]
	var pony := _pony("fluttershy", "FluttershyBody")
	root.add_child(pony)
	PONIES.attach(pony)
	var runtime: Node = PONIES.runtime_for(pony)
	check(is_instance_valid(runtime), "an attached body gets one runtime")
	check(runtime.get_parent() == pony, "the runtime lives under its body")
	check(runtime.get("pony") == pony, "the factory hands the runtime its body")
	check(anatomy.journal == ["present:FluttershyBody", "tail:FluttershyBody"],
		"the prepare presents the body and seats its tail, in that order")
	check(body_change.journal == ["form:FluttershyBody"], "the body is prepared once")
	check(smack.journal == ["ready:FluttershyBody"], "the smack layer is told about the body")
	PONIES.attach(pony)
	check(body_change.journal == ["form:FluttershyBody", "form:FluttershyBody"],
		"a second attach prepares again")
	var live: Array[Node] = PONIES.live_ponies()
	check(live.size() == 1 and live[0] == pony, "the registry lists the body once")
	root.remove_child(pony)
	pony.free()
	_free(f)


## A body leaving the tree leaves the registry; a bodiless lookup falls back to the node a
## runtime was parented under.
func _check_detach() -> void:
	var f := _bind()
	var pony := _pony("rarity", "RarityBody")
	root.add_child(pony)
	PONIES.attach(pony)
	var runtime: Node = PONIES.runtime_for(pony)
	pony.remove_child(runtime)
	root.remove_child(pony)
	pony.free()
	check(PONIES.live_ponies().is_empty(), "a freed body leaves the registry")
	check(PONIES.runtime_for(null) == null, "a missing body has no runtime")
	var stray := _pony("stray", "StrayBody")
	root.add_child(stray)
	stray.add_child(runtime)
	check(PONIES.runtime_for(stray) == runtime, "a runtime found by name answers the lookup")
	PONIES.shutdown()
	stray.remove_child(runtime)
	runtime.free()
	root.remove_child(stray)
	stray.free()
	_free(f)


## The player's own body is a locomotion too and never takes a runtime.
func _check_player_pony() -> void:
	var f := _bind()
	var player := _pony("anon", "PlayerPony")
	root.add_child(player)
	PONIES.attach(player)
	check(PONIES.runtime_for(player) == null, "the player's AnonPony gets no runtime")
	var rigged := _pony("rigged", "RiggedBody")
	rigged.rig = Node3D.new()
	root.add_child(rigged)
	PONIES.attach(rigged)
	check(PONIES.runtime_for(rigged) == null, "a body that is the player's rig gets no runtime")
	PONIES.shutdown()
	root.remove_child(player)
	player.free()
	root.remove_child(rigged)
	rigged.free()
	_free(f)


## The act pointer, the offer reset and the stock smack handoff.
func _check_active() -> void:
	var f := _bind()
	var smack: FakeSmack = f["smack"]
	var offer: FakeOffer = f["offer"]
	var pony := _pony("pinkie", "PinkieBody")
	root.add_child(pony)
	PONIES.attach(pony)
	var runtime: Node = PONIES.runtime_for(pony)
	check(not PONIES.act_running(), "no act owns the frame before a start")
	check(PONIES.active() == null, "no act means no active runtime")
	PONIES.set_active(runtime)
	check(PONIES.act_running(), "a started act owns the frame")
	check(PONIES.active() == runtime, "the active runtime is the started one")
	check(offer.cleared == 1, "an act start drops the idle offer")
	check(smack.journal == ["ready:PinkieBody", "start:PinkieBody"],
		"the smack layer knows which body is acting")
	PONIES.clear_active(null)
	check(PONIES.active() == runtime, "another runtime cannot clear the act")
	PONIES.clear_active(runtime)
	check(not PONIES.act_running(), "the act end frees the frame")
	check(smack.journal.back() == "end:PinkieBody", "the smack layer ends the same body")
	PONIES.set_active(runtime)
	PONIES.shutdown()
	check(not PONIES.act_running(), "the teardown clears the act")
	root.remove_child(pony)
	pony.free()
	_free(f)


## Serials never repeat inside one process, even where the store cannot keep the write.
func _check_serial() -> void:
	var first := PONIES.allocate_serial()
	var second := PONIES.allocate_serial()
	var third := PONIES.allocate_serial()
	check(first >= 1, "the first serial is a real number")
	check(second > first and third > second, "serials climb in one process")
	PONIES.shutdown()
	var after := PONIES.allocate_serial()
	check(after > third, "a teardown does not hand the same serial out again")


## Every prepare hook is idempotent; the late prepare needs a live entry.
func _check_prepare() -> void:
	var f := _bind()
	var anatomy: FakeAnatomy = f["anatomy"]
	var body_change: FakeBodyChange = f["body_change"]
	var smack: FakeSmack = f["smack"]
	var pony := _pony("applejack", "ApplejackBody")
	root.add_child(pony)
	PONIES.prepare_late(pony)
	check(anatomy.journal == ["present:ApplejackBody", "tail:ApplejackBody"],
		"the late prepare presents the body and seats the tail")
	check(body_change.journal == ["form:ApplejackBody"], "the late prepare fits the body")
	check(smack.journal == ["ready:ApplejackBody"], "the late prepare arms the smack layer")
	PONIES.prepare_late(pony)
	check(anatomy.journal.size() == 3, "a second late prepare seats the tail again")
	check(PONIES.runtime_for(pony) == null, "a prepare never creates a runtime")
	var host: Node = f["host"]
	WORLD.unbind()
	PONIES.prepare_late(pony)
	check(anatomy.journal.size() == 3, "a prepare without the entry does nothing")
	WORLD.bind_world(host)
	PONIES.shutdown()
	root.remove_child(pony)
	pony.free()
	_free(f)


## Suspend, adopt and drop the old body's entry, with the source's claim deciding the identity.
func _check_adoption() -> void:
	var f := _bind()
	var anatomy: FakeAnatomy = f["anatomy"]
	var pony := _pony("test_mare", "OldBody")
	root.add_child(pony)
	PONIES.attach(pony)
	var runtime: FakeRuntime = PONIES.runtime_for(pony)
	var source := FakeSource.new()
	var change := BODY_CHANGE.new()
	change.source = source
	runtime.pony = pony
	PONIES.begin_body_swap(runtime, pony, "test_mare", change)
	check(PONIES.body_swap_pending(), "a suspended act records one pending swap")
	check(PONIES.live_ponies().is_empty(), "the old body's registry entry goes at the suspend")
	check(not PONIES.act_running(), "the pending swap is not an act start")

	# A body with another id is not the one this act waits for.
	var other := _pony("other_mare", "OtherBody")
	root.add_child(other)
	PONIES.attach(other)
	check(PONIES.body_swap_pending(), "another id leaves the pending swap alone")
	check(PONIES.runtime_for(other) != runtime, "another id gets its own runtime")

	var new_pony := _pony("test_mare", "NewBody")
	root.add_child(new_pony)
	source.next = new_pony
	PONIES.attach(new_pony)
	check(not PONIES.body_swap_pending(), "the new body adopts and clears the swap")
	check(PONIES.runtime_for(new_pony) == runtime, "the new body keeps the same runtime")
	check(runtime.get_parent() == new_pony, "the runtime moves under the new body")
	check(runtime.attached == [new_pony], "the runtime is reparented once")
	check(runtime.adopted == [new_pony], "the runtime adopts the new body once")
	check(runtime.pony == new_pony, "the runtime owns the new body")
	check(anatomy.journal.count("present:NewBody") == 1, "anatomy presents the adopted body once")

	# The runtime's own late adoption: the spawn hook never reached the attach.
	PONIES.begin_body_swap(runtime, new_pony, "test_mare", change)
	var late_pony := _pony("test_mare", "LateBody")
	root.add_child(late_pony)
	source.next = late_pony
	check(PONIES.adopt_pending_body(late_pony), "the watcher adopts the body the source claims")
	check(PONIES.runtime_for(late_pony) == runtime, "the late body keeps the same runtime")
	check(not PONIES.body_swap_pending(), "the late adoption clears the swap")

	# An unclaimed id and a dead runtime both refuse quietly.
	source.next = null
	PONIES.begin_body_swap(runtime, late_pony, "test_mare", change)
	var stranger := _pony("stranger", "StrangerBody")
	root.add_child(stranger)
	check(not PONIES.adopt_pending_body(stranger), "an unclaimed id is not adopted")
	PONIES.clear_body_swap(null)
	check(PONIES.body_swap_pending(), "another runtime cannot clear the swap")
	PONIES.clear_body_swap(runtime)
	check(not PONIES.body_swap_pending(), "the owning runtime clears its swap")
	PONIES.begin_body_swap(runtime, late_pony, "test_mare", null)
	check(not PONIES.body_swap_pending(), "a null change records no swap")

	PONIES.shutdown()
	source.free()
	for node: Node in [pony, other, new_pony, late_pony, stranger]:
		root.remove_child(node)
		node.free()
	_free(f)


## A runtime that a race created on the adopting body is dropped for the suspended act.
func _check_duplicate_guard() -> void:
	var f := _bind()
	var anatomy: FakeAnatomy = f["anatomy"]
	var pony := _pony("test_mare", "RaceOldBody")
	root.add_child(pony)
	PONIES.attach(pony)
	var runtime: FakeRuntime = PONIES.runtime_for(pony)
	# The race: the new body's spawn hook arrives before the act's swap is recorded, so it already
	# carries a runtime of its own when the adoption finds it.
	var new_pony := _pony("test_mare", "RaceNewBody")
	root.add_child(new_pony)
	PONIES.attach(new_pony)
	var duplicate: FakeRuntime = PONIES.runtime_for(new_pony)
	check(duplicate != runtime, "the race created its own runtime first")
	var source := FakeSource.new()
	source.next = new_pony
	var change := BODY_CHANGE.new()
	change.source = source
	PONIES.begin_body_swap(runtime, pony, "test_mare", change)
	check(PONIES.adopt_pending_body(new_pony),
		"the suspended act still adopts the body although another runtime held it")
	check(PONIES.runtime_for(new_pony) == runtime, "the act's runtime wins the body")
	check(duplicate.stopped == 1, "the duplicate is stopped once")
	check(duplicate.is_queued_for_deletion(), "the duplicate is freed")
	check(anatomy.journal.has("withdraw:RaceNewBody"),
		"the duplicate's anatomy controller is dropped before the act's present")

	PONIES.shutdown()
	source.free()
	for node: Node in [pony, new_pony]:
		root.remove_child(node)
		node.free()
	_free(f)


## A world close ends the act through its owner, drops the swap and frees every runtime.
func _check_world_close() -> void:
	var f := _bind()
	var pony := _pony("twilight", "TwilightBody")
	root.add_child(pony)
	PONIES.attach(pony)
	var runtime: FakeRuntime = PONIES.runtime_for(pony)
	PONIES.set_active(runtime)
	var source := FakeSource.new()
	var change := BODY_CHANGE.new()
	change.source = source
	PONIES.begin_body_swap(runtime, pony, "twilight", change)
	# The adopted body registers the runtime again, as the real handover does.
	PONIES.attach(pony)
	PONIES.close_world()
	check(runtime.stopped == 1, "the world close stops the act once")
	check(not PONIES.act_running(), "the world close frees the frame")
	check(not PONIES.body_swap_pending(), "the world close drops the pending swap")
	var live: Array[Node] = PONIES.live_ponies()
	check(live.size() == 1 and live[0] == pony,
		"the world close keeps the bodies' runtimes; they leave with their bodies")
	PONIES.reset()
	PONIES.shutdown()
	check(runtime.is_queued_for_deletion(), "the teardown frees the runtime")
	check(PONIES.live_ponies().is_empty(), "the teardown empties the registry")
	check(PONIES.anatomy == null and not PONIES.factory.is_valid(),
		"the teardown drops the bound services")
	source.free()
	root.remove_child(pony)
	pony.free()
	_free(f)


## The installed list and the live pass: one per runtime, not only the act's.
func _check_character_lists() -> void:
	var f := _bind()
	var body_change: FakeBodyChange = f["body_change"]
	body_change.installed = ["chrysalis"]
	var installed: Array[String] = PONIES.installed_character_ids()
	check(installed == ["chrysalis"], "the installed list comes from the body-change service")
	check(PONIES.live_character_ids().has("chrysalis"),
		"an installed mare is listed without a live body")
	PONIES.eligibility = ELIGIBILITY.new()
	var pony := _pony("sunny_star", "SunnyBody")
	root.add_child(pony)
	PONIES.attach(pony)
	var runtime: FakeRuntime = PONIES.runtime_for(pony)
	check(PONIES.live_character_ids().has("sunny_star"),
		"a live adult mare with a runtime is listed")
	PONIES.apply_live_settings()
	check(runtime.live_settings == 1, "the live pass reaches a runtime that is not acting")
	PONIES.body_change = null
	check(PONIES.installed_character_ids().is_empty(),
		"without the service the installed list is empty")

	PONIES.shutdown()
	root.remove_child(pony)
	pony.free()
	_free(f)
