extends "res://mods/unfplap/tests/support/suite.gd"
## The Idle Life deep-stretch debug bridge: the entry path, the forced call and the interrupt.
##
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_deep_stretch.gd

const BRIDGE := preload("res://mods/unfplap/debug_actions/idle_stretch.gd")



class FakePony extends Node3D:
	pass


class FakeEntry extends Node:
	var _rows: Dictionary = {}
	var plays: Array = []
	var finishes: Array = []
	var result := true

	func play(pony: Node3D, idle: String, side: float, forced: bool) -> bool:
		plays.append([pony, idle, side, forced])
		return result

	func _finish(pony: Node3D) -> void:
		finishes.append(pony)
		_rows.erase(pony)


class PlayOnlyEntry extends Node:
	var plays := 0

	func play(_pony: Node3D, _idle: String, _side: float, _forced: bool) -> bool:
		plays += 1
		return true


class PlainEntry extends Node:
	pass


func run() -> void:
	_check_contract()
	_check_calls()
	if failures == 0:
		print("DEEP_STRETCH_PASS")
	finish()


func _pony(pony_name: String) -> FakePony:
	var pony := FakePony.new()
	pony.name = pony_name
	return pony


func _check_contract() -> void:
	check(BRIDGE.ENTRY_PATH == "res://mods/idle_life/main.gd", "the entry path is Idle Life's")
	check(BRIDGE.IDLE == "stretch_deep", "the deep variant is the idle")


## Every refusal and the one live call path, without a scene.
func _check_calls() -> void:
	var pony := _pony("Rarity")
	var entry := FakeEntry.new()
	check(BRIDGE.stretch(entry, null) == "No pony to stretch.",
		"a missing pony refuses")
	check(BRIDGE.stretch(null, pony) == "Idle Life isn't running.",
		"a missing entry refuses")
	check(BRIDGE.stretch(PlainEntry.new(), pony) == "Idle Life isn't running.",
		"an entry without play refuses")
	check(entry.plays.is_empty(), "no play call before a live stretch")

	var line := BRIDGE.stretch(entry, pony)
	check(line == "Deep stretch for Rarity.", "a played idle reports the pony")
	check(entry.plays.size() == 1, "one play call per press")
	if entry.plays.size() == 1:
		var row: Array = entry.plays[0]
		check(row[0] == pony, "the aimed pony is the target")
		check(str(row[1]) == "stretch_deep", "the deep stretch is the idle")
		check(float(row[2]) == 0.0, "the side is Idle Life's own random pick")
		check(bool(row[3]) == true, "the idle is forced to the end")
	check(entry.finishes.is_empty(), "no idle to interrupt on a free pony")

	entry._rows[pony] = {}
	BRIDGE.stretch(entry, pony)
	check(entry.finishes == [pony], "a running idle is interrupted first")
	check(entry._rows.is_empty(), "the interrupted row is gone before play")
	check(entry.plays.size() == 2, "the interrupted idle is replaced")

	entry.result = false
	line = BRIDGE.stretch(entry, pony)
	check(line == "Rarity can't play the deep stretch.", "a refused play reports the pony")

	var play_only := PlayOnlyEntry.new()
	line = BRIDGE.stretch(play_only, pony)
	check(line == "Deep stretch for Rarity.", "an entry without _rows still plays")
	check(play_only.plays == 1, "the entry without _rows gets the play call")

	pony.free()
	entry.free()
	play_only.free()
