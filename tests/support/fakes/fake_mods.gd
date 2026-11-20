extends Node
## Shared mods fake: in-memory state and a save counter for the suites that drive Mods.

var data := {"unfplap": {}}
var saves := 0

func state(id: String) -> Dictionary:
	var value: Variant = data.get(id, {})
	return value if value is Dictionary else {}

func save_changed() -> void:
	saves += 1
