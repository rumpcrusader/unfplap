extends "res://mods/unfplap/tests/support/suite.gd"
## The one stable pony id: relationship metadata first, then the identity id.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_pony_id.gd

const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")



func run() -> void:
	check(PONY_ID.from("relationship_id", {"id": "identity_id"}) == "relationship_id",
		"relationship metadata wins over the identity id")
	check(PONY_ID.from("", {"id": "identity_id"}) == "identity_id",
		"the identity id is the fallback")
	check(PONY_ID.from("", null) == "", "no identity has no id")
	check(PONY_ID.from("", {"display_name": "Rarity"}) == "",
		"an identity without an id has no id")

	if failures == 0:
		print("PONY_ID_PASS")
	finish()
