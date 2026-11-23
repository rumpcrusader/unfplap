extends "res://mods/unfplap/tests/support/suite.gd"
## The act frame: the live runtime and its two side effects, the serial store, and the one pending
## body swap with its world-close rule.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/act_owner/test_owner.gd

const ACT_OWNER := preload("res://mods/unfplap/act_owner/service.gd")
const OFFER := preload("res://mods/unfplap/offer/service.gd")
const STOCK_SMACK := preload("res://mods/unfplap/stock_smack/api.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const FAKE_MODS := preload("res://mods/unfplap/tests/support/fakes/fake_mods.gd")


class FakeRuntime extends Node:
	var pony: Node = null


class FakeOffer extends "res://mods/unfplap/offer/service.gd":
	var cleared := 0

	func clear_current() -> void:
		cleared += 1


class FakeSmack extends "res://mods/unfplap/stock_smack/api.gd":
	var journal: Array[String] = []

	func act_start(pony: Node) -> void:
		journal.append("start:" + (str(pony.name) if is_instance_valid(pony) else "?"))

	func act_end(pony: Node) -> void:
		journal.append("end:" + (str(pony.name) if is_instance_valid(pony) else "?"))


## A wired owner; a null side-effect peer is a no-op.
func _owner(offer: OFFER = null, smack: STOCK_SMACK = null) -> ACT_OWNER:
	var owner := ACT_OWNER.new()
	owner.wire(offer, smack)
	return owner


func _pony(pony_name: String) -> Node3D:
	var pony := Node3D.new()
	pony.name = pony_name
	root.add_child(pony)
	return pony


func _runtime(pony: Node) -> FakeRuntime:
	var runtime := FakeRuntime.new()
	runtime.pony = pony
	root.add_child(runtime)
	return runtime


func run() -> void:
	_check_frame()
	_check_serial()
	_check_swap()
	finish()


## The act pointer, the offer reset and the stock smack handoff.
func _check_frame() -> void:
	var offer := FakeOffer.new()
	var smack := FakeSmack.new()
	var owner := _owner(offer, smack)
	var pony := _pony("PinkieBody")
	var runtime := _runtime(pony)
	check(not owner.act_running(), "no act owns the frame before a start")
	check(owner.active() == null, "no act means no active runtime")
	owner.set_active(runtime)
	check(owner.act_running(), "a started act owns the frame")
	check(owner.active() == runtime, "the active runtime is the started one")
	check(offer.cleared == 1, "an act start drops the idle offer")
	check(smack.journal == ["start:PinkieBody"], "the smack layer knows which body is acting")
	owner.clear_active(null)
	check(owner.active() == runtime, "another runtime cannot clear the act")
	owner.clear_active(runtime)
	check(not owner.act_running(), "the act end frees the frame")
	check(smack.journal.back() == "end:PinkieBody", "the smack layer ends the same body")
	owner.set_active(runtime)
	owner.shutdown()
	check(not owner.act_running(), "the teardown clears the act")
	root.remove_child(runtime)
	runtime.free()
	root.remove_child(pony)
	pony.free()
	offer.free()
	smack.free()
	owner.free()


## Serials never repeat inside one process, even where the store cannot keep the write.
func _check_serial() -> void:
	var existing: Node = root.get_node_or_null("Mods")
	if existing != null:
		existing.name = "ModsTestHidden"
	var mods := FAKE_MODS.new()
	mods.name = "Mods"
	root.add_child(mods)
	var owner := _owner()
	var first := owner.allocate_serial()
	var second := owner.allocate_serial()
	var third := owner.allocate_serial()
	check(first >= 1, "the first serial is a real number")
	check(second > first and third > second, "serials climb in one process")
	check(int(mods.data["unfplap"]["serial"]) == third, "the store keeps the last serial")
	owner.shutdown()
	var after := owner.allocate_serial()
	check(after > third, "a teardown does not hand the same serial out again")
	check(mods.saves == 4, "every serial allocation persists the section")
	owner.free()
	root.remove_child(mods)
	mods.free()
	if existing != null and is_instance_valid(existing):
		existing.name = "Mods"


## The one swap record, scoped to its runtime, and the two world hooks' different state.
func _check_swap() -> void:
	var owner := _owner()
	var old_pony := _pony("OldBody")
	var runtime := _runtime(old_pony)
	var change := BODY_CHANGE.new()
	check(owner.pending_swap() == null, "no start means no swap record")
	owner.begin_body_swap(runtime, old_pony, "test_mare", change)
	check(owner.body_swap_pending(), "a suspended act records one pending swap")
	check(owner.pending_swap().runtime == runtime, "the record names the suspended runtime")
	check(owner.pending_swap().id == "test_mare", "the record carries the id")
	check(not owner.act_running(), "the pending swap is not an act start")
	owner.clear_body_swap(null)
	check(owner.body_swap_pending(), "another runtime cannot clear the swap")
	owner.clear_body_swap(runtime)
	check(not owner.body_swap_pending(), "the owning runtime clears its swap")
	owner.begin_body_swap(runtime, old_pony, "test_mare", null)
	check(not owner.body_swap_pending(), "a null change records no swap")

	owner.begin_body_swap(runtime, old_pony, "test_mare", change)
	owner.on_world(null)
	check(not owner.body_swap_pending(), "a world enter drops the old world's swap")

	owner.set_active(runtime)
	owner.begin_body_swap(runtime, old_pony, "test_mare", change)
	owner.on_world_closed()
	check(not owner.body_swap_pending(), "a world close drops the swap")
	check(owner.act_running(),
		"a world close leaves the live act; its runtime leaves with its body")
	owner.shutdown()
	check(not owner.act_running() and not owner.body_swap_pending(), "the teardown clears the frame")
	check(owner.active() == null, "the teardown answers no active runtime")
	owner.free()
	root.remove_child(runtime)
	runtime.free()
	root.remove_child(old_pony)
	old_pony.free()
