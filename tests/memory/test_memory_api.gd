extends SceneTree
## The memory facade's public API: one impression and its event per slot, one event per note,
## the refusal mood, and the stay-close reward.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/memory/test_memory_api.gd

const MEMORY := preload("res://mods/unfplap/memory/service.gd")

var failures := 0
var checks := 0


class FakeGame extends Node:
	var world_context: Node


class FakeMain extends Node:
	var game: Node


class FakeContext extends Node:
	var impressions: Node
	var events: Array = []

	func record(kind: String, text: String, witnesses: Array, subjects: Array,
			event_id: String, _place := "") -> void:
		events.append({"kind": kind, "text": text, "witnesses": witnesses,
			"subjects": subjects, "id": event_id})


class FakeImpressions extends Node:
	var calls: Array = []

	func commit(id: String, data: Dictionary, event_id: String) -> void:
		calls.append({"id": id, "data": data.duplicate(true), "event_id": event_id})


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var game := FakeGame.new()
	var context := FakeContext.new()
	var impressions := FakeImpressions.new()
	context.impressions = impressions
	game.world_context = context
	root.add_child(game)
	root.add_child(context)
	root.add_child(impressions)
	var main := FakeMain.new()
	main.game = game
	root.add_child(main)
	var memory := MEMORY.new()
	memory.setup(main)

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

	var refused := MEMORY.Impression.new()
	refused.id = "rarity"
	refused.event_id = "refusal_1"
	refused.slot = MEMORY.ImpressionSlot.REFUSAL
	refused.mood = "annoyed"
	memory.commit(refused)
	var turned_away: Dictionary = impressions.calls[5]
	check(str((turned_away["data"] as Dictionary).get("mood", "")) == "annoyed",
		"a plain refusal is annoyed")
	check(not (turned_away["data"] as Dictionary).has("romance"),
		"a refusal never changes romance")
	check(not str((turned_away["data"] as Dictionary).get("thought", "")).is_empty(),
		"a refusal keeps a private thought")
	check(str(turned_away.get("event_id", "")).ends_with(":mood"),
		"the refusal mood uses its own commit id")
	check(str(context.events[-1].kind) == "intimacy", "a refusal is recorded as an intimacy event")
	check(str(context.events[-1].id) == "refusal_1", "the refusal event keeps its bare id")
	check(str(context.events[-1].text).contains("turned Anon away"),
		"the refusal event says what happened")

	var bucked := MEMORY.Impression.new()
	bucked.id = "rarity"
	bucked.event_id = "refusal_2"
	bucked.slot = MEMORY.ImpressionSlot.REFUSAL
	bucked.mood = "angry"
	memory.commit(bucked)
	var bucked_row: Dictionary = impressions.calls[6]
	check(str((bucked_row["data"] as Dictionary).get("mood", "")) == "angry",
		"a buck is angry")
	check(str((bucked_row["data"] as Dictionary).get("thought", "")).contains("bucked"),
		"the buck thought names the buck")

	game.queue_free()
	context.queue_free()
	impressions.queue_free()
	main.queue_free()

	print("MEMORY_API_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("MEMORY_API_PASS")
	quit(0 if failures == 0 else 1)
