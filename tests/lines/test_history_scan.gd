extends SceneTree
## The lines facade's idle history scan: a sincere apology repairs one point, and a pending
## reminder or complaint becomes one short queued line and is marked announced.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/lines/test_history_scan.gd

const LINES := preload("res://mods/unfplap/lines/service.gd")
const FACTS := preload("res://mods/unfplap/shared/act_facts.gd")
const MEMORY := preload("res://mods/unfplap/memory/service.gd")

var failures := 0
var checks := 0


class FakeMods extends Node:
	var data := {"unfplap": {}}
	var saves := 0

	func state(id: String) -> Dictionary:
		var value: Variant = data.get(id, {})
		return value if value is Dictionary else {}

	func save_changed() -> void:
		saves += 1


class FakeGame extends Node:
	pass


class FakeMemory extends Node:
	var notes: Array = []
	var requests: Array = []

	func note(kind: int, id: String, event_id: String, _reason := 0) -> void:
		notes.append({"kind": kind, "id": id, "event_id": event_id})

	func line(request: MEMORY.LineRequest) -> MEMORY.Line:
		requests.append(request)
		var line := MEMORY.Line.new()
		line.key = "line:%d" % requests.size()
		line.queued = true
		return line


class FakeMain extends Node:
	var game: Node = FakeGame.new()
	var memory: Node = FakeMemory.new()


class FakePony extends Node3D:
	pass


class FakeDirector extends Node:
	var state := "idle"


class Host extends RefCounted:
	var director: Node
	var clock := 0.0

	func get_director() -> Node:
		return director

	func clock_now() -> float:
		return clock


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _mods() -> FakeMods:
	var existing: Node = root.get_node_or_null("Mods")
	if existing != null:
		existing.name = "ModsTestHidden"
	var mods := FakeMods.new()
	mods.name = "Mods"
	root.add_child(mods)
	return mods


func _context(main: FakeMain, pony: FakePony, director: FakeDirector, turn: int,
		text: String, target_is_player: bool) -> Dictionary:
	return {
		"main": main,
		"pony": pony,
		"director": director,
		"pony_id": "rarity",
		"event_id": "intimacy_test",
		"now": 100.0,
		"turn": turn,
		"text": text,
		"paused": false,
		"speech_busy": false,
		"director_state": "idle",
		"distance": 1.0,
		"target_is_player": target_is_player,
	}


func run() -> void:
	var mods := _mods()
	var main := FakeMain.new()
	root.add_child(main)
	main.add_child(main.game)
	root.add_child(main.memory)
	var pony := FakePony.new()
	root.add_child(pony)
	var director := FakeDirector.new()
	root.add_child(director)
	var host := Host.new()
	host.director = director

	var facts := FACTS.new()
	facts.pony = pony
	facts.pony_id = "rarity"
	facts.event_id = "intimacy_test"
	facts.state = 0
	facts.director = Callable(host, "get_director")
	facts.now = Callable(host, "clock_now")

	var lines := LINES.new(facts)
	lines.setup(main)

	# The first turn is the baseline; a later turn with an apology repairs one point.
	mods.data["unfplap"]["act_history"] = {
		"rarity": {"hurt": 3, "last_apology_day": -1.0, "reminder_pending": false},
	}
	lines.history_tick(0.0, _context(main, pony, director, 2, "", false))
	lines.history_tick(1.1, _context(main, pony, director, 3, "I'm sorry", true))
	var repair_row: Dictionary = (mods.data["unfplap"]["act_history"] as Dictionary)["rarity"]
	check(int(repair_row.get("hurt", 3)) == 2, "a sincere apology repairs one point")
	check(main.memory.notes.size() == 1, "the apology writes one note")
	if not main.memory.notes.is_empty():
		check(int(main.memory.notes[0].get("kind", -1)) == MEMORY.NoteKind.APOLOGY,
			"the apology note carries its kind")

	# A pending reminder queues one line and is marked announced.
	mods.data["unfplap"]["act_history"] = {
		"rarity": {"hurt": 2, "last_at": 0.0, "reminder_pending": true,
			"complaint_pending": false},
	}
	lines.history_tick(1.1, _context(main, pony, director, 3, "", false))
	check(main.memory.requests.size() == 1, "a pending reminder queues one line")
	var reminder_row: Dictionary = (mods.data["unfplap"]["act_history"] as Dictionary)["rarity"]
	check(not bool(reminder_row.get("reminder_pending", true)),
		"the queued reminder is marked announced")

	# A busy or paused scene queues nothing.
	mods.data["unfplap"]["act_history"] = {
		"rarity": {"hurt": 2, "last_at": 0.0, "complaint_pending": true},
	}
	var busy := _context(main, pony, director, 3, "", false)
	busy["speech_busy"] = true
	lines.history_tick(1.1, busy)
	check(main.memory.requests.size() == 1, "a busy scene queues no reminder")

	print("HISTORY_SCAN_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("HISTORY_SCAN_PASS")
	quit(0 if failures == 0 else 1)
