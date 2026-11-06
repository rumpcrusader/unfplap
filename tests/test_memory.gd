extends SceneTree
## Witness memory wording: adults are told what it was, fillies and colts get a perception with
## the place it happened, and impressions never carry an explicit thought for a young witness.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_memory.gd

const MEMORY := preload("res://mods/unfplap/memory.gd")

var failures := 0
var checks := 0


class FakeGame extends Node:
	var world_context: Node


class FakeContext extends Node:
	var impressions: Node
	var events: Array = []

	func record(kind: String, text: String, witnesses: Array, subjects: Array,
			event_id: String) -> void:
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
	check(MEMORY.witness_kind(false) == "witnessed_intimacy", "adult event kind")
	check(MEMORY.witness_kind(true) == "witnessed_scene", "young event kind")

	var adult := MEMORY.witness_text("Fluttershy", false, true, 0)
	check(adult == "She saw Anon and Fluttershy having sex.", "adult text is unchanged indoors")
	check(MEMORY.witness_text("Fluttershy", false, false, 7) == adult, "adult text ignores place and serial")

	for indoors: bool in [true, false]:
		var prefix := MEMORY.witness_scene_prefix("Fluttershy", indoors)
		for serial: int in [0, 1, 2, 3]:
			var text := MEMORY.witness_text("Fluttershy", true, indoors, serial)
			check(text.begins_with(prefix), "young text starts with the place prefix")
			for word: String in ["sex", "climax", "naked", "bed"]:
				check(not text.to_lower().contains(word), "young text omits '%s'" % word)
	check(MEMORY.witness_text("Fluttershy", true, true, 0) != MEMORY.witness_text("Fluttershy", true, true, 1),
		"young text varies by act")
	check(MEMORY.witness_text("Fluttershy", true, true, 0) == MEMORY.witness_text("Fluttershy", true, true, 0),
		"young text is stable for one act")
	check(MEMORY.witness_scene_prefix("Fluttershy", true).contains("walked in on"),
		"indoors wording")
	check(MEMORY.witness_scene_prefix("Fluttershy", false).contains("out in the open"),
		"outdoors wording")

	check(MEMORY.witness_thought("Fluttershy", true, true) == "", "young witness has no thought")
	check(MEMORY.witness_thought("Fluttershy", true, false) == "", "young outdoor witness has no thought")
	check(MEMORY.witness_thought("Fluttershy", false, true).contains("having sex"),
		"adult indoor thought says what it was")
	check(MEMORY.witness_thought("Fluttershy", false, false).contains("having sex"),
		"adult outdoor thought says what it was")

	var young: Dictionary = MEMORY.witness_impression("Fluttershy", true, true)
	check(young == {"mood": "amused"}, "young impression is mood only")
	check(not young.has("thought"), "young impression carries no explicit thought")
	check(not young.has("romance") and not young.has("friendship"), "young impression carries no score")

	var grown: Dictionary = MEMORY.witness_impression("Fluttershy", false, false)
	check(str(grown.get("mood", "")) == "surprised", "adult impression mood")
	check(str(grown.get("thought", "")) == "I saw Anon and Fluttershy having sex out in the open.",
		"adult outdoors thought")
	check(not grown.has("romance") and not grown.has("friendship"), "adult impression carries no score")

	var game := FakeGame.new()
	var context := FakeContext.new()
	var impressions := FakeImpressions.new()
	context.impressions = impressions
	game.world_context = context
	root.add_child(game)
	root.add_child(context)
	root.add_child(impressions)

	MEMORY.commit_act(game, "rarity", "Rarity", "intimacy_1", {
		"mood": "happy", "romance": 2, "thought": "He gave me what I needed.",
		"text": "You and Anon made love. You felt wanted.",
	}, false)
	check(impressions.calls.size() == 1, "a good act writes one impression")
	var good: Dictionary = impressions.calls[0]
	check(int((good["data"] as Dictionary).get("romance", 0)) == 2, "a good act gives romance +2")
	check(str((good["data"] as Dictionary).get("mood", "")) == "happy", "a good act is happy")
	check(str(good.get("event_id", "")).ends_with(":gain"), "an afterglow summary uses the act gain id")
	check(context.events.size() == 1 and str(context.events[0].kind) == "relationship",
		"the summary is recorded as a relationship event")

	MEMORY.commit_act(game, "rarity", "Rarity", "intimacy_1", {
		"mood": "sad", "romance": -1, "thought": "He did not give me what I need.",
		"text": "You felt used.",
	}, false)
	var bad: Dictionary = impressions.calls[1]
	check(int((bad["data"] as Dictionary).get("romance", 0)) == -1, "a bad act gives romance -1")
	check(str((bad["data"] as Dictionary).get("mood", "")) == "sad", "a bad act is sad")

	MEMORY.commit_act(game, "rarity", "Rarity", "intimacy_2", {
		"mood": "relaxed", "romance": 1, "thought": "It was nice.",
		"text": "It was nice, but something was missing.",
	}, false)
	check(int((impressions.calls[2]["data"] as Dictionary).get("romance", 0)) == 1,
		"a neutral act gives romance +1")

	MEMORY.stay_close_reward(game, "rarity", "intimacy_1", true, true)
	var stay: Dictionary = impressions.calls[3]
	check(int((stay["data"] as Dictionary).get("romance", 0)) == 1,
		"a positive stay-close caress gives its extra romance")
	MEMORY.stay_close_reward(game, "rarity", "intimacy_2", true, false)
	var hurt_stay: Dictionary = impressions.calls[4]
	check(not (hurt_stay["data"] as Dictionary).has("romance"),
		"staying close after a bad act gives no romance")

	MEMORY.history_apology(game, "rarity", "I am sorry.")
	check(str(context.events[-1].kind) == "relationship", "an apology is recorded as a relationship event")
	check(str(context.events[-1].text).contains("apologized"), "the apology event says what happened")

	MEMORY.refusal_event(game, "rarity", "Rarity", "refusal_1", false)
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
	check(str(context.events[-1].text).contains("turned Anon away"),
		"the refusal event says what happened")

	MEMORY.refusal_event(game, "rarity", "Rarity", "refusal_2", true)
	var bucked: Dictionary = impressions.calls[6]
	check(str((bucked["data"] as Dictionary).get("mood", "")) == "angry",
		"a buck is angry")
	check(str((bucked["data"] as Dictionary).get("thought", "")).contains("bucked"),
		"the buck thought names the buck")

	game.queue_free()
	context.queue_free()
	impressions.queue_free()

	print("MEMORY_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("MEMORY_PASS")
	quit(0 if failures == 0 else 1)
