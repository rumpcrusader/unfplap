extends SceneTree
## The lover-bond service: the grant/end gates, the world-context event, idempotence and the
## stale-bond sweep. The store itself is `test_sex_bond.gd`; the eligibility gates live in
## `tests/eligibility/`.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/bond/test_bond_service.gd

const SEX_BOND := preload("res://mods/unfplap/sex_bond.gd")

const STATE_IDLE := 0
const STATE_ACTIVE := 2

var failures := 0
var checks := 0


class FakePony extends Node3D:
	var sleeping := false


class FakeBonds extends RefCounted:
	var stage := "dating"

	func record_for(_id: String) -> Dictionary:
		return {"stage": stage}


class FakeRelationship extends RefCounted:
	var bonds := FakeBonds.new()


class FakeHost extends RefCounted:
	var id := "rarity"
	var state := STATE_IDLE
	var pony: FakePony = null
	var bond := true
	var stage := "dating"
	var love_level := 2
	var relationship: FakeRelationship = null
	var section_data: Dictionary = {}
	var events: Array[String] = []
	var logs: Array[String] = []

	func id_now() -> String:
		return id

	func state_now() -> int:
		return state

	func pony_now() -> Variant:
		return pony

	func relationship_now() -> Variant:
		return relationship

	func bond_facts() -> Dictionary:
		return {"bond": bond, "stage": stage, "love_level": love_level}

	func section() -> Dictionary:
		return section_data

	func on_event(text: String) -> void:
		events.append(text)

	func on_log(text: String) -> void:
		logs.append(text)


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func _service(host: FakeHost) -> RefCounted:
	var service: RefCounted = SEX_BOND.new()
	service.bind({
		"id": Callable(host, "id_now"),
		"state": Callable(host, "state_now"),
		"pony": Callable(host, "pony_now"),
		"bond_facts": Callable(host, "bond_facts"),
		"relationship": Callable(host, "relationship_now"),
		"event": Callable(host, "on_event"),
		"log": Callable(host, "on_log"),
		"section": Callable(host, "section"),
	})
	return service


func _fixture() -> Dictionary:
	var host := FakeHost.new()
	host.pony = FakePony.new()
	host.relationship = FakeRelationship.new()
	return {"service": _service(host), "host": host}


func run() -> void:
	_check_grant()
	_check_end()
	_check_refresh()
	print("BOND_SERVICE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("BOND_SERVICE_PASS")
	quit(0 if failures == 0 else 1)


func _check_grant() -> void:
	var made := _fixture()
	var service: RefCounted = made["service"]
	var host: FakeHost = made["host"]
	host.state = STATE_ACTIVE
	check(not service.grant_bond("test", "line"), "an act blocks the grant")
	host.state = STATE_IDLE
	host.pony.sleeping = true
	check(not service.grant_bond("test", "line"), "a sleeping pony blocks the grant")
	host.pony.sleeping = false
	host.bond = false
	check(not service.grant_bond("test", "line"), "a failed bond policy blocks the grant")
	host.bond = true
	host.id = ""
	check(not service.grant_bond("test", "line"), "no identity blocks the grant")
	host.id = "rarity"
	check(service.grant_bond("dialogue", "I would like that."), "the grant succeeds")
	check(SEX_BOND.bonded(host.section_data, "rarity"), "the row is stored")
	var row: Dictionary = SEX_BOND.row(host.section_data, "rarity")
	check(str(row.get("stage", "")) == "dating", "the stored stage is the live stage")
	check(int(host.events.size()) == 1 and host.events[0] == "You and Anon became lovers.",
		"the grant records one world event")
	check(host.logs.size() == 1, "the grant logs once")
	check(service.grant_bond("test", "again"), "a repeat grant succeeds")
	check(host.events.size() == 1, "a repeat grant records no second event")
	host.pony.free()


func _check_end() -> void:
	var made := _fixture()
	var service: RefCounted = made["service"]
	var host: FakeHost = made["host"]
	check(not service.end_bond("test"), "no bond to end")
	service.grant_bond("test", "")
	check(service.end_bond("dialogue", "I need to stop."), "the end clears the bond")
	check(not SEX_BOND.bonded(host.section_data, "rarity"), "the row is gone")
	check(host.events.size() == 2 and host.events[1] == "You and Anon are no longer lovers.",
		"the end records the event")
	var cleared: Dictionary = host.section_data.get("sex_bonds_last_clear", {})
	check(str(cleared.get("reason", "")) == "dialogue", "the clear reason is stored")
	check(not service.end_bond("test"), "a second end finds nothing")
	host.pony.free()


func _check_refresh() -> void:
	var made := _fixture()
	var service: RefCounted = made["service"]
	var host: FakeHost = made["host"]
	service.refresh_bond()
	check(host.section_data.is_empty(), "no bond needs no refresh")
	service.grant_bond("test", "")
	# A live romantic stage keeps the stored stage current.
	host.relationship.bonds.stage = "engaged"
	service.refresh_bond()
	var row: Dictionary = SEX_BOND.row(host.section_data, "rarity")
	check(str(row.get("stage", "")) == "engaged", "a romantic stage updates the stored stage")
	# A base break-up clears a bond that was made at a romantic stage.
	host.relationship.bonds.stage = "close_friend"
	service.refresh_bond()
	check(not SEX_BOND.bonded(host.section_data, "rarity"), "a break-up clears the bond")
	check(host.logs[-1].contains("lover bond cleared"), "the sweep logs the clear")
	# A bond made at Crush has no romantic stage to leave.
	var crush := FakeHost.new()
	crush.pony = FakePony.new()
	crush.relationship = FakeRelationship.new()
	crush.stage = "crush"
	var crush_service := _service(crush)
	crush_service.grant_bond("test", "")
	crush.relationship.bonds.stage = "close_friend"
	crush_service.refresh_bond()
	check(SEX_BOND.bonded(crush.section_data, "rarity"), "a Crush bond survives a base break-up")
	# Without a relationship runtime the sweep leaves the row alone.
	host.section_data.clear()
	SEX_BOND.grant(host.section_data, "rarity", "dating", 2, "test", "")
	host.relationship = null
	service.refresh_bond()
	check(SEX_BOND.bonded(host.section_data, "rarity"), "no runtime leaves the bond alone")
	crush.pony.free()
	host.pony.free()
