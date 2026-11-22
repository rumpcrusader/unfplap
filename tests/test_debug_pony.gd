extends "res://mods/unfplap/tests/support/suite.gd"
## The debug pony-preparation helper shared by the wheel's Bed cuddle and Sex ready actions.
## Run:
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_debug_pony.gd
##
## Fake nodes only: the helper touches a pony's Navigator, CuddleSession, act metas and public
## posture state, never a game file.

const WORLD := preload("res://mods/unfplap/world/api.gd")
const DEBUG_PONY := preload("res://mods/unfplap/debug/pony.gd")



class FakeNavigator extends Node:
	var command_owner := ""
	var reserved_by := ""
	var wander_enabled := true
	var _has_target := false
	var stayed := false

	func stay() -> void:
		stayed = true


class FakeSession extends Node:
	var enabled := false
	var blend := 0.0
	var ended := false

	func end(_immediate := false) -> void:
		ended = true
		enabled = false


class FakeRuntime extends Node:
	var state := 0


class FakeImpressions extends Node:
	var moods := {}
	var commits: Array = []

	func profile(id: String) -> Dictionary:
		return {"mood": str(moods.get(id, "neutral"))}

	func commit(id: String, raw: Dictionary, event_id: String) -> void:
		moods[id] = str(raw.get("mood", moods.get(id, "neutral")))
		commits.append([id, raw.duplicate(true), event_id])


class FakeContext extends Node:
	var impressions: Node


class FakeGame extends Node:
	var world_context: Node


class FakeBonds extends RefCounted:
	var records := {}
	var saves := 0
	var met := 0

	func record_for(id: String) -> Dictionary:
		if records.has(id):
			return (records[id] as Dictionary).duplicate(true)
		return {"stage": "acquaintance", "familiarity": 0.0, "trust": 0.0,
			"together_s": 0.0, "plan": {}, "offer": {}, "cooldowns": {}}

	func _save(id: String, row: Dictionary) -> void:
		records[id] = row.duplicate(true)
		saves += 1

	func mark_met(_id: String) -> void:
		met += 1


class NoRecordBonds extends RefCounted:
	func _save(_id: String, _row: Dictionary) -> void:
		pass


class NoSaveBonds extends RefCounted:
	func record_for(_id: String) -> Dictionary:
		return {"stage": "acquaintance"}


class FakeRelation extends Node:
	var bonds: Variant


class FakePony extends Node3D:
	var identity: Variant
	var velocity := Vector3.ZERO
	var motion_paused := false
	var requested := ""
	var requests := 0
	var sleeping := false
	var actual_speed := 0.0

	func posture_status() -> Dictionary:
		return {"requested": requested}

	func request_posture(name: String) -> void:
		requested = name
		requests += 1

	func is_held() -> bool:
		return false

	func grounded() -> bool:
		return true

	func action_interruption_reason() -> String:
		return ""


class Fixture extends RefCounted:
	var host: Node
	var game: FakeGame
	var context: FakeContext
	var impressions: FakeImpressions
	var pony: FakePony
	var relation: FakeRelation
	var bonds: Variant

	func clear() -> void:
		pony.free()
		relation.free()
		host.free()
		game.free()
		context.free()
		impressions.free()


func run() -> void:
	_check_upright()
	_check_idle()
	_check_clear_busy()
	_check_context()
	_check_sex_ready()
	_check_sex_ready_kept()
	_check_sex_ready_floors()
	_check_sex_ready_refusals()
	if failures == 0:
		print("DEBUG_PONY_PASS")
	finish()


func _pony(name: String) -> FakePony:
	var pony := FakePony.new()
	pony.name = name
	root.add_child(pony)
	return pony


## A full fake relationship stack: world -> world context -> impressions, a host node and a pony
## relationship runtime carries a bonds store for applejack.
func _fixture(pony_name: String, stage := "acquaintance") -> Fixture:
	var fixture := Fixture.new()
	fixture.host = Node.new()
	fixture.host.name = "FakeHost"
	fixture.game = FakeGame.new()
	fixture.game.name = "FakeGame"
	fixture.context = FakeContext.new()
	fixture.context.name = "FakeContext"
	fixture.impressions = FakeImpressions.new()
	fixture.impressions.name = "FakeImpressions"
	WORLD.bind_world(fixture.game)
	fixture.game.world_context = fixture.context
	fixture.context.impressions = fixture.impressions
	root.add_child(fixture.host)
	root.add_child(fixture.game)
	root.add_child(fixture.context)
	root.add_child(fixture.impressions)
	fixture.pony = _pony(pony_name)
	fixture.pony.set_meta("relationship_id", "applejack")
	fixture.relation = FakeRelation.new()
	fixture.relation.name = "FakeRelation"
	fixture.bonds = FakeBonds.new()
	fixture.relation.bonds = fixture.bonds
	fixture.pony.set_meta("relationship_runtime", fixture.relation)
	root.add_child(fixture.relation)
	(fixture.bonds as FakeBonds).records["applejack"] = {
		"stage": stage, "familiarity": 10.0, "trust": 5.0, "together_s": 30.0,
		"plan": {"kind": "date"}, "offer": {"kind": "dating"},
		"cooldowns": {"boundary": 10.0, "dating": 20.0, "outing": 30.0},
	}
	return fixture


func _check_upright() -> void:
	var pony := _pony("Tilted")
	pony.global_transform = Transform3D(
		Basis.from_euler(Vector3(0.35, 0.7, -0.2)) * Basis.from_scale(Vector3(1.2, 1.2, 1.2)),
		Vector3(4.0, 5.0, 6.0))
	pony.velocity = Vector3(1.0, 0.0, 0.0)
	DEBUG_PONY.upright(pony)
	var euler := pony.global_basis.get_euler()
	check(absf(euler.x) < 0.001 and absf(euler.z) < 0.001, "upright zeroes the tilt")
	check(absf(angle_difference(euler.y, 0.7)) < 0.001, "upright keeps the facing yaw")
	check(pony.global_basis.get_scale().is_equal_approx(Vector3(1.2, 1.2, 1.2)),
		"upright keeps the scale")
	check(pony.velocity == Vector3.ZERO, "upright stops the residual velocity")
	pony.free()


func _check_idle() -> void:
	var pony := _pony("Busy")
	var nav := FakeNavigator.new()
	nav.name = "Navigator"
	nav.command_owner = "life:graze"
	nav.reserved_by = "rest_spot"
	nav._has_target = true
	pony.add_child(nav)
	pony.global_transform = Transform3D(Basis.from_euler(Vector3(0.2, 1.1, 0.1)), Vector3.ZERO)
	pony.velocity = Vector3(2.0, 0.0, 0.0)
	pony.motion_paused = true
	pony.set_meta("active_follow", "player")
	var notes := DEBUG_PONY.idle(pony)
	check(nav.stayed, "idle stops the navigator")
	check(nav.command_owner == "", "idle clears the command owner")
	check(nav.reserved_by == "", "idle clears the reservation")
	check(not nav.wander_enabled, "idle disables wandering")
	check(not pony.has_meta("active_follow"), "idle removes the follow meta")
	check(not pony.motion_paused, "idle unpauses motion")
	check(pony.requested == "stand", "idle requests the standing pose")
	check(notes.contains("owner life:graze"), "idle reports the cleared owner")
	check(notes.contains("reserved rest_spot"), "idle reports the cleared reservation")
	check(notes.contains("stand requested"), "idle reports the posture request")
	check(absf(pony.global_basis.get_euler().x) < 0.001, "idle uprights the pony")
	pony.free()

	var clean := _pony("Clean")
	var clean_nav := FakeNavigator.new()
	clean_nav.name = "Navigator"
	clean.add_child(clean_nav)
	clean.requested = "stand"
	check(DEBUG_PONY.idle(clean) == "none", "a clean idle reports none")
	check(clean_nav.stayed, "a clean idle still stops the navigator")
	check(clean.requests == 0, "a pony already standing is not re-requested")
	clean.free()


func _check_clear_busy() -> void:
	var pony := _pony("Cuddled")
	var session := FakeSession.new()
	session.name = "CuddleSession"
	session.enabled = true
	session.blend = 0.4
	pony.add_child(session)
	pony.set_meta("couch_cuddle", true)
	pony.set_meta("cuddle_active", true)
	pony.set_meta("sex_aftercare", true)
	pony.set_meta("sex_active", true)
	var runtime := FakeRuntime.new()
	runtime.name = "UnfplapRuntime"
	runtime.state = 0
	pony.add_child(runtime)
	var notes := DEBUG_PONY.clear_busy(pony)
	check(session.ended, "clear_busy ends the live cuddle")
	check(not pony.has_meta("couch_cuddle"), "clear_busy clears couch_cuddle")
	check(not pony.has_meta("cuddle_active"), "clear_busy clears cuddle_active")
	check(not pony.has_meta("sex_aftercare"), "clear_busy clears sex_aftercare")
	check(not pony.has_meta("sex_active"), "clear_busy clears sex_active outside an act")
	check(notes.contains("cuddle ended"), "clear_busy reports the ended cuddle")
	pony.free()

	var live := _pony("Live")
	var live_runtime := FakeRuntime.new()
	live_runtime.name = "UnfplapRuntime"
	live_runtime.state = 1
	live.add_child(live_runtime)
	live.set_meta("sex_active", true)
	DEBUG_PONY.clear_busy(live)
	check(live.has_meta("sex_active"), "clear_busy never drops sex_active mid-act")
	live.free()

	var clean := _pony("Clean")
	check(DEBUG_PONY.clear_busy(clean) == "none", "a clean pony reports none")
	clean.free()


func _check_context() -> void:
	var fixture := _fixture("Pony")
	fixture.pony.set("identity", {"display_name": "Applejack"})
	var nav := FakeNavigator.new()
	nav.name = "Navigator"
	nav.command_owner = "life:graze"
	nav.reserved_by = "rest_spot"
	nav._has_target = true
	fixture.pony.add_child(nav)
	fixture.pony.requested = "stand"
	fixture.pony.motion_paused = true
	fixture.pony.actual_speed = 1.5
	fixture.pony.set_meta("seated", true)
	fixture.impressions.moods["applejack"] = "happy"
	var act := {
		"state": 2, "presenting": true, "cuddle": false, "max_pony_climaxes": 2,
		"satisfaction": 12.5, "pony_climaxes": 1, "last_intensity": "firm",
		"last_pattern": "steady", "cue": "warm", "thrust_up": true,
		"penetration_m": 0.12, "penetration_reach": 0.2, "preferences": "touch=caress",
		"voice_status_line": "voice ok",
	}
	var context := DEBUG_PONY.context(fixture.pony, "applejack", act)
	check(str(context.get("id", "")) == "applejack", "the context carries the pony id")
	check(str(context.get("display", "")) == "Applejack",
		"the display name comes from the identity")
	check(str(context.get("mood", "")) == "happy", "the mood comes from the impressions profile")
	check(str(context.get("posture", "")) == "stand", "the posture is her requested posture")
	check(float(context.get("speed", 0.0)) == 1.5, "the speed is the live value")
	check(bool(context.get("seated", false)), "the seated meta is reported")
	check(bool(context.get("target", false)) and str(context.get("owner", "")) == "life:graze",
		"the navigator row is reported")
	check(int(context.get("state", 0)) == 2 and int(context.get("pony_climaxes", 0)) == 1,
		"the act values pass through")
	check(not bool(context.get("paused", true)), "the tree is not paused")
	check(bool(context.get("presenting", false)) and str(context.get("cue", "")) == "warm",
		"the act-session values are kept")
	check(str(context.get("stage", "")) == "",
		"no live eligibility service reads empty relations")
	fixture.clear()


func _check_sex_ready() -> void:
	var stranger := _fixture("Applejack", "acquaintance")
	var toast := DEBUG_PONY.sex_ready(stranger.host, stranger.pony)
	check(toast == "Sex ready for Applejack.", "a raised stranger toasts the qualifying line")
	var row: Dictionary = (stranger.bonds as FakeBonds).records["applejack"]
	check(str(row.get("stage", "")) == "dating", "the saved record is dating")
	check((stranger.bonds as FakeBonds).saves == 1, "the record is written once")
	check((stranger.bonds as FakeBonds).met == 1, "the record marks her met")
	stranger.clear()

	var friend := _fixture("Applejack", "friend")
	DEBUG_PONY.sex_ready(friend.host, friend.pony)
	friend.clear()


func _check_sex_ready_kept() -> void:
	for stage: String in ["dating", "engaged", "married"]:
		var fixture := _fixture("Applejack", stage)
		var toast := DEBUG_PONY.sex_ready(fixture.host, fixture.pony)
		check(str((fixture.bonds as FakeBonds).records["applejack"].get("stage", "")) == stage,
			"%s stays in the saved record" % stage)
		check(toast == "Sex ready for Applejack.", "%s still toasts ready" % stage)
		fixture.clear()


func _check_sex_ready_floors() -> void:
	var fixture := _fixture("Applejack", "acquaintance")
	var bonds := fixture.bonds as FakeBonds
	bonds.records["applejack"]["familiarity"] = 200.0
	fixture.impressions.moods["applejack"] = "annoyed"
	DEBUG_PONY.sex_ready(fixture.host, fixture.pony)
	var row: Dictionary = bonds.records["applejack"]
	check(float(row.get("familiarity", 0.0)) == 200.0, "a familiarity above the floor is kept")
	check(float(row.get("trust", 0.0)) == DEBUG_PONY.TRUST_FLOOR, "the trust floor is applied")
	check(float(row.get("together_s", 0.0)) == DEBUG_PONY.TOGETHER_FLOOR_S,
		"the together floor is applied")
	check((row.get("plan", {}) as Dictionary).is_empty(), "the pending plan is cleared")
	check((row.get("offer", {}) as Dictionary).is_empty(), "the pending offer is cleared")
	var cooldowns: Dictionary = row.get("cooldowns", {})
	check(not cooldowns.has("boundary"), "the boundary cooldown is erased")
	check(not cooldowns.has("dating"), "the dating cooldown is erased")
	check(cooldowns.has("outing"), "other cooldowns are kept")
	check(fixture.impressions.commits.size() == 1, "one neutral impression is committed")
	check(str(fixture.impressions.moods["applejack"]) == "neutral", "the mood is neutral")
	fixture.clear()


func _check_sex_ready_refusals() -> void:
	var missing := _fixture("Applejack", "acquaintance")
	var nav := FakeNavigator.new()
	nav.name = "Navigator"
	nav.command_owner = "life:graze"
	missing.pony.add_child(nav)
	missing.pony.motion_paused = true
	missing.pony.remove_meta("relationship_runtime")
	var toast := DEBUG_PONY.sex_ready(missing.host, missing.pony)
	check(toast == "Sex ready refused for Applejack.", "missing bonds refuses")
	check(nav.command_owner == "life:graze" and missing.pony.motion_paused,
		"a refusal leaves the pony untouched")
	check(missing.impressions.commits.is_empty(), "a refusal writes no mood")
	missing.clear()

	var unsaved := _fixture("Applejack", "acquaintance")
	unsaved.relation.bonds = NoSaveBonds.new()
	toast = DEBUG_PONY.sex_ready(unsaved.host, unsaved.pony)
	check(toast == "Sex ready refused for Applejack.", "missing _save refuses")
	unsaved.clear()

	var unread := _fixture("Applejack", "acquaintance")
	unread.relation.bonds = NoRecordBonds.new()
	toast = DEBUG_PONY.sex_ready(unread.host, unread.pony)
	check(toast == "Sex ready refused for Applejack.", "missing record_for refuses")
	unread.clear()
