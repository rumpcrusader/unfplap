extends RefCounted
## Pure briefcase ownership checks for the base-game footstool.

const WORLD := preload("res://mods/unfplap/world/api.gd")

const ID := "goods:footstool"
const SLOT_COUNT := 27


## The first case slot with an unheld footstool, or -1.
static func case_slot(store: Object) -> int:
	if store == null:
		return -1
	var briefcase := WORLD.inventory()
	var rows := briefcase.slots(store)
	for i: int in mini(rows.size(), SLOT_COUNT):
		var slot := rows[i]
		if str(slot.get("id", "")) != ID:
			continue
		var amount := briefcase.available(store, i)
		if amount < 0:
			amount = int(slot.get("count", 0))
		if amount > 0:
			return i
	return -1


## Units in the briefcase that can be taken now (an equipped unit is not available).
static func case_count(store: Object) -> int:
	if store == null:
		return 0
	var briefcase := WORLD.inventory()
	var total := 0
	var rows := briefcase.slots(store)
	for i: int in mini(rows.size(), SLOT_COUNT):
		var slot := rows[i]
		if str(slot.get("id", "")) != ID:
			continue
		var amount := briefcase.available(store, i)
		if amount < 0:
			amount = int(slot.get("count", 0))
		total += maxi(0, amount)
	return total


## Every owned footstool: case units, held units, placed furniture and world drops.
static func owned_count(store: Object) -> int:
	if store == null:
		return 0
	var briefcase := WORLD.inventory()
	var total := 0
	for slot: Dictionary in briefcase.slots(store):
		if str(slot.get("id", "")) == ID:
			total += maxi(0, int(slot.get("count", 0)))
	for loan: Dictionary in briefcase.loans(store):
		if str(loan.get("id", "")) == ID:
			total += 1
	return total


static func free_slots(store: Object) -> int:
	if store == null:
		return 0
	var total := 0
	for slot: Dictionary in WORLD.inventory().slots(store):
		if slot.is_empty():
			total += 1
	return total


static func writable(store: Object) -> bool:
	return store != null and WORLD.inventory().writable(store)
