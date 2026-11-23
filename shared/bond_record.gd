extends RefCounted
## One pony's bond record, read once and written back through the store's own save.
## `world/views/relationship.gd` hands it out; the store keeps the untouched rows.

var stage := "acquaintance"
var familiarity := 0.0
var trust := 0.0
var anger := 0.0
var together_s := 0.0
var plan: Dictionary = {}
var offer: Dictionary = {}
var cooldowns: Dictionary = {}
## The untouched rows, so a key this record does not model survives the save.
var rows: Dictionary = {}


## Read the store's row in place, keeping the untouched keys for the write back.
func read(row: Dictionary) -> void:
	rows = row.duplicate(true)
	stage = str(row.get("stage", "acquaintance"))
	familiarity = float(row.get("familiarity", 0.0))
	trust = float(row.get("trust", 0.0))
	anger = float(row.get("anger", 0.0))
	together_s = float(row.get("together_s", 0.0))
	var stored_plan: Variant = row.get("plan", {})
	plan = stored_plan if stored_plan is Dictionary else {}
	var stored_offer: Variant = row.get("offer", {})
	offer = stored_offer if stored_offer is Dictionary else {}
	var stored_cooldowns: Variant = row.get("cooldowns", {})
	cooldowns = stored_cooldowns if stored_cooldowns is Dictionary else {}


## The live record as the store's own row; the untouched keys stay in place.
func to_row() -> Dictionary:
	var row := rows
	row["stage"] = stage
	row["familiarity"] = familiarity
	row["trust"] = trust
	row["anger"] = anger
	row["together_s"] = together_s
	row["plan"] = plan
	row["offer"] = offer
	row["cooldowns"] = cooldowns
	return row
