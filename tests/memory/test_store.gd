extends "res://mods/unfplap/tests/support/suite.gd"
## The peak-memory store: one per-world record, replaced only when a higher score arrives.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/memory/test_store.gd

const STORE := preload("res://mods/unfplap/memory/store.gd")



class FakeMods extends Node:
	var _state: Dictionary = {}
	var saves := 0

	func state(_id: String) -> Dictionary:
		return _state

	func save_changed() -> void:
		saves += 1


func run() -> void:
	var existing: Node = root.get_node_or_null("Mods")
	if existing != null:
		existing.name = "ModsTestHidden"
	var mods := FakeMods.new()
	mods.name = "Mods"
	root.add_child(mods)

	check(STORE.peak("rarity").is_empty(), "a mare with no peak has no record")
	check(STORE.record("rarity", "act_1", "We made love.", 90.0), "the first peak is written")
	check(STORE.section().has("peak_memories"), "the store writes the section")
	var row: Dictionary = STORE.peak("rarity")
	check(str(row.get("text", "")) == "We made love.", "the peak text is stored")
	check(float(row.get("score", 0.0)) == 90.0, "the peak score is stored")
	check(str(row.get("event_id", "")) == "act_1", "the peak event id is stored")

	check(not STORE.record("rarity", "act_2", "Weaker.", 80.0), "a lower peak is ignored")
	check(str(STORE.peak("rarity").get("text", "")) == "We made love.", "a lower peak leaves the text")
	check(STORE.record("rarity", "act_3", "Stronger.", 95.0), "a higher peak replaces the record")
	check(str(STORE.peak("rarity").get("text", "")) == "Stronger.", "a higher peak replaces the text")
	check(mods.saves >= 2, "the store saves after each write")

	mods.queue_free()
	if existing != null and is_instance_valid(existing):
		existing.name = "Mods"

	if failures == 0:
		print("MEMORY_STORE_PASS")
	finish()
