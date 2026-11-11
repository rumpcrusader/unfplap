extends RefCounted
## Pure briefcase ownership checks for the base-game footstool. See docs/stool.md.

const ID := "goods:footstool"
const SLOT_COUNT := 27


## The first case slot with an unheld footstool, or -1.
static func case_slot(store: Variant) -> int:
	if store == null:
		return -1
	var slots: Variant = store.get("slots")
	if not slots is Array:
		return -1
	var rows: Array = slots
	for i: int in mini(rows.size(), SLOT_COUNT):
		var slot: Variant = rows[i]
		if not slot is Dictionary:
			continue
		if str((slot as Dictionary).get("id", "")) != ID:
			continue
		var amount := int((slot as Dictionary).get("count", 0))
		if store.has_method("available"):
			amount = int(store.call("available", i))
		if amount > 0:
			return i
	return -1


## Units in the briefcase that can be taken now (an equipped unit is not available).
static func case_count(store: Variant) -> int:
	if store == null:
		return 0
	var slots: Variant = store.get("slots")
	if not slots is Array:
		return 0
	var total := 0
	var rows: Array = slots
	for i: int in mini(rows.size(), SLOT_COUNT):
		var slot: Variant = rows[i]
		if not slot is Dictionary or str((slot as Dictionary).get("id", "")) != ID:
			continue
		if store.has_method("available"):
			total += maxi(0, int(store.call("available", i)))
		else:
			total += maxi(0, int((slot as Dictionary).get("count", 0)))
	return total


## Every owned footstool: case units, held units, placed furniture and world drops.
static func owned_count(store: Variant) -> int:
	if store == null:
		return 0
	var total := 0
	var slots: Variant = store.get("slots")
	if slots is Array:
		for slot: Variant in slots:
			if slot is Dictionary and str((slot as Dictionary).get("id", "")) == ID:
				total += maxi(0, int((slot as Dictionary).get("count", 0)))
	var loans: Variant = store.get("loans")
	if loans is Dictionary:
		for loan: Variant in (loans as Dictionary).values():
			if loan is Dictionary and str((loan as Dictionary).get("id", "")) == ID:
				total += 1
	return total


static func free_slots(store: Variant) -> int:
	if store == null:
		return 0
	var slots: Variant = store.get("slots")
	if not slots is Array:
		return 0
	var total := 0
	for slot: Variant in slots:
		if slot is Dictionary and (slot as Dictionary).is_empty():
			total += 1
	return total


static func writable(store: Variant) -> bool:
	return store != null and bool(store.get("writable"))
