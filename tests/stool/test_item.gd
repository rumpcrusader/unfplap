extends SceneTree
## Footstool briefcase ownership, counting and take/put.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/stool/test_item.gd

const ITEM := preload("res://mods/unfplap/stool/item.gd")
const STORE := preload("res://world/inventory/inventory_store.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var store = STORE.new()
	store.slots[0] = {"id": ITEM.ID, "count": 1}
	store.slots[1] = {"id": "apple", "count": 2}
	check(ITEM.case_slot(store) == 0, "the footstool case slot is found")
	check(ITEM.owned_count(store) == 1, "one footstool is owned")
	check(ITEM.free_slots(store) == 25, "two filled slots leave 25 free")
	check(ITEM.writable(store), "a fresh store is writable")

	var token := store.take(0)
	check(not token.is_empty(), "the footstool leaves the case")
	check(ITEM.case_slot(store) == -1, "the case has no unheld footstool")
	check(ITEM.owned_count(store) == 1, "the checked-out footstool is still owned")
	check(store.put(token, 0), "the footstool returns to its slot")
	check(ITEM.case_slot(store) == 0, "the returned footstool is usable again")

	store.loans["placed"] = {"id": ITEM.ID, "slot": 0}
	check(ITEM.owned_count(store) == 2, "a placed footstool counts as owned")

	var missing = null
	check(ITEM.case_slot(missing) == -1, "no store has no case slot")
	check(ITEM.owned_count(missing) == 0, "no store owns nothing")

	print("STOOL_ITEM_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
