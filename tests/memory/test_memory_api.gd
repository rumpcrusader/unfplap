extends "res://mods/unfplap/tests/support/suite.gd"
## The memory facade's public API: one impression and its event per slot, one event per note,
## and the stay-close reward.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/memory/test_memory_api.gd

const WORLD := preload("res://mods/unfplap/world/api.gd")
const MEMORY := preload("res://mods/unfplap/memory/api.gd")



class FakeGame extends Node:
	var world_context: Node


class FakeMain extends Node:
	var game: Node


class FakeMods extends Node:
	var _state: Dictionary = {}

	func state(_id: String) -> Dictionary:
		return _state


class FakeContext extends Node:
	var impressions: Node
	var events: Array = []

	func record(kind: String, text: String, witnesses: Array, subjects: Array,
			event_id: String, _place := "") -> void:
		events.append({"kind": kind, "text": text, "witnesses": witnesses,
			"subjects": subjects, "id": event_id})


class FakeImpressions extends "res://mods/unfplap/tests/support/fakes/fake_impressions.gd":
	pass


func run() -> void:
	var game := FakeGame.new()
	var context := FakeContext.new()
	var impressions := FakeImpressions.new()
	context.impressions = impressions
	game.world_context = context
	var existing: Node = root.get_node_or_null("Mods")
	if existing != null:
		existing.name = "ModsTestHidden"
	var mods := FakeMods.new()
	mods.name = "Mods"
	root.add_child(game)
	root.add_child(context)
	root.add_child(impressions)
	root.add_child(mods)
	var main := FakeMain.new()
	main.game = game
	WORLD.bind_world(main.game)
	root.add_child(main)
	var memory := MEMORY.new()

	var good := MEMORY.Impression.new()
	good.id = "rarity"
	good.event_id = "intimacy_1"
	good.slot = MEMORY.ImpressionSlot.ACT
	good.mood = "happy"
	good.romance = 2
	good.thought = "He gave me what I needed."
	good.event_text = "You and Anon made love. You felt wanted."
	memory.commit(good)
	check(impressions.calls.size() == 1, "a good act writes one impression")
	var good_row: Dictionary = impressions.calls[0]
	check(int((good_row["data"] as Dictionary).get("romance", 0)) == 2, "a good act gives romance +2")
	check(str((good_row["data"] as Dictionary).get("mood", "")) == "happy", "a good act is happy")
	check(str(good_row.get("event_id", "")).ends_with(":gain"), "an afterglow summary uses the act gain id")
	check(context.events.size() == 1 and str(context.events[0].kind) == "relationship",
		"the summary is recorded as a relationship event")
	check(str(context.events[0].id) == "intimacy_1:summary", "the summary event keeps its own id")

	var bad := MEMORY.Impression.new()
	bad.id = "rarity"
	bad.event_id = "intimacy_1"
	bad.slot = MEMORY.ImpressionSlot.ACT
	bad.mood = "sad"
	bad.romance = -1
	bad.thought = "He did not give me what I need."
	bad.event_text = "You felt used."
	memory.commit(bad)
	var bad_row: Dictionary = impressions.calls[1]
	check(int((bad_row["data"] as Dictionary).get("romance", 0)) == -1, "a bad act gives romance -1")
	check(str((bad_row["data"] as Dictionary).get("mood", "")) == "sad", "a bad act is sad")

	var neutral := MEMORY.Impression.new()
	neutral.id = "rarity"
	neutral.event_id = "intimacy_2"
	neutral.slot = MEMORY.ImpressionSlot.ACT
	neutral.mood = "relaxed"
	neutral.romance = 1
	neutral.thought = "It was nice."
	neutral.event_text = "It was nice, but something was missing."
	memory.commit(neutral)
	check(int((impressions.calls[2]["data"] as Dictionary).get("romance", 0)) == 1,
		"a neutral act gives romance +1")

	var stay := MEMORY.Impression.new()
	stay.id = "rarity"
	stay.event_id = "intimacy_1"
	stay.slot = MEMORY.ImpressionSlot.STAY_CLOSE
	stay.mood = "happy"
	stay.romance = 1
	memory.commit(stay)
	var stay_row: Dictionary = impressions.calls[3]
	check(int((stay_row["data"] as Dictionary).get("romance", 0)) == 1,
		"a positive stay-close caress gives its extra romance")
	check(str((stay_row["data"] as Dictionary).get("thought", "")).contains("caressed"),
		"the stay-close thought names the caress")
	check(str(stay_row.get("event_id", "")).ends_with(":stay_close_gain"),
		"the stay-close reward keeps its own id")
	var hurt_stay := MEMORY.Impression.new()
	hurt_stay.id = "rarity"
	hurt_stay.event_id = "intimacy_2"
	hurt_stay.slot = MEMORY.ImpressionSlot.STAY_CLOSE
	hurt_stay.mood = ""
	memory.commit(hurt_stay)
	var hurt_row: Dictionary = impressions.calls[4]
	check(not (hurt_row["data"] as Dictionary).has("romance"),
		"staying close after a bad act gives no romance")
	check(not (hurt_row["data"] as Dictionary).has("mood"),
		"a bad stay-close keeps the base mood")

	memory.note(MEMORY.NoteKind.APOLOGY, "rarity", "apology_1")
	check(str(context.events[-1].kind) == "relationship", "an apology is recorded as a relationship event")
	check(str(context.events[-1].text).contains("apologized"), "the apology event says what happened")

	var reveal: Variant = memory.form_reveal_impression("rarity", "intimacy_1")
	memory.commit(reveal)
	var reveal_row: Dictionary = impressions.calls[-1]
	check(str(reveal_row.get("event_id", "")).ends_with(":form_reveal"),
		"the reveal impression keeps its own id")
	check(str((reveal_row["data"] as Dictionary).get("thought", "")).contains("not the shape"),
		"the reveal thought says he wanted her")
	check(not str((reveal_row["data"] as Dictionary).get("thought", "")).contains(" you "),
		"the reveal thought stays first person")
	check(str(context.events[-1].id).ends_with(":form_reveal"),
		"the reveal event keeps its own id")
	var peak: Variant = memory.form_reveal_peak("rarity", "intimacy_1", 150.0)
	check(str(peak.event_id) == "intimacy_1:form_reveal", "the reveal peak has its own event")
	check(is_equal_approx(float(peak.score), 150.0), "the reveal peak keeps its score")

	var used: Array[String] = []
	var missing := memory.shared_memory("rarity", "", "", used)
	check(missing is MEMORY.MemoryHit, "an absent memory is a typed hit")
	check(not missing.found(), "an absent memory is not found")
	mods._state["peak_memories"] = {"rarity": {"text": "The night we met.", "score": 10.0}}
	var peak_hit := memory.shared_memory("rarity", "", "", used)
	check(peak_hit.found(), "a stored peak is a found memory")
	check(peak_hit.text == "The night we met.", "the peak text is the hit")
	check(peak_hit.id == "peak:rarity", "the peak hit keeps its id")
	used.append("peak:rarity")
	var used_hit := memory.shared_memory("rarity", "", "", used)
	check(not used_hit.found(), "a used peak is skipped")

	memory.free()
	game.queue_free()
	context.queue_free()
	impressions.queue_free()
	mods.queue_free()
	if existing != null and is_instance_valid(existing):
		existing.name = "Mods"
	main.queue_free()

	if failures == 0:
		print("MEMORY_API_PASS")
	finish()
