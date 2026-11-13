extends SceneTree
## The integrations facade: binding resolution, save/restore, optional bindings, live feature
## edits, shared excitement Beat ownership and idempotent reset.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/integrations/test_service.gd

const SERVICE := preload("res://mods/unfplap/integrations/service.gd")

var failures := 0
var checks := 0


class FakeFacts extends RefCounted:
	var state := 2
	var pose_id := "standing"
	var satisfaction := 75.0
	var mood := "close"
	var seconds_since_stroke := 0.0
	var act_seconds := 1.0
	var pony: Variant = null
	var features: Dictionary = {}
	var logs: Array[String] = []
	var beat: Variant = null
	var beat_original := false
	var beat_holders: Array[String] = []
	var mods_active: Dictionary = {}

	func mod_active(id: String) -> bool:
		return bool(mods_active.get(id, false))

	func write_log(text: String) -> void:
		logs.append(text)

	func hold_beat(owner: String) -> void:
		if owner.is_empty() or beat_holders.has(owner):
			return
		if beat_holders.is_empty() and beat is Timer:
			beat_original = (beat as Timer).paused
		beat_holders.append(owner)
		if beat is Timer:
			(beat as Timer).paused = true

	func release_beat(owner: String) -> void:
		var index := beat_holders.find(owner)
		if index >= 0:
			beat_holders.remove_at(index)
		if beat_holders.is_empty() and beat is Timer:
			(beat as Timer).paused = beat_original


class FakePony extends Node3D:
	var excitement: Variant = null
	var skeleton: Variant = null


class FakeExcitement extends Node:
	var _until := 1.25


class FakeFeelings extends Node:
	var level := 0.4

	func _peak() -> float:
		return 0.85


class FakeAffection extends Node:
	var kind := ""


class FakeFidgets extends Node3D:
	var _root := 7
	var _tap_next := 0.25


class FakePose extends Node3D:
	var stretch := false


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.00001) -> bool:
	return absf(a - b) <= eps


func _setup(feature := true) -> Dictionary:
	var pony := FakePony.new()
	pony.name = "TestPony"
	var excitement := FakeExcitement.new()
	excitement.name = "Excitement"
	var beat := Timer.new()
	beat.name = "Beat"
	excitement.add_child(beat)
	pony.add_child(excitement)
	pony.excitement = excitement
	var skeleton := Node3D.new()
	skeleton.name = "Skeleton"
	pony.add_child(skeleton)
	pony.skeleton = skeleton
	var pose := FakePose.new()
	pose.name = "UnfplapPose"
	skeleton.add_child(pose)
	var feelings := FakeFeelings.new()
	feelings.name = "KissingFeelings"
	pony.add_child(feelings)
	var affection := FakeAffection.new()
	affection.name = "Affection"
	pony.add_child(affection)
	var facts := FakeFacts.new()
	facts.pony = pony
	facts.features = {"kissing_reactions": feature}
	facts.beat = beat
	root.add_child(pony)
	return {
		"pony": pony,
		"facts": facts,
		"excitement": excitement,
		"beat": beat,
		"skeleton": skeleton,
		"feelings": feelings,
		"affection": affection,
		"pose": pose,
	}


func _add_fidgets(skeleton: Node) -> Node:
	var fidgets := FakeFidgets.new()
	fidgets.name = "KissingFidgets"
	skeleton.add_child(fidgets)
	return fidgets


func _free_scene(scene: Dictionary) -> void:
	var pony: Variant = scene.get("pony")
	if pony is Node and is_instance_valid(pony):
		(pony as Node).free()


func run() -> void:
	_check_basic()
	_check_feature_off()
	_check_missing_required()
	_check_optional_late()
	_check_live_toggle()
	_check_two_owners()
	_check_missing_mid_act()
	_check_full_fidgets()
	_check_idle_life()
	_check_idle_life_gates()
	_check_coexist()
	print("INTEGRATIONS_SERVICE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_basic() -> void:
	var scene := _setup()
	var facts: FakeFacts = scene["facts"]
	var service := SERVICE.new(facts)
	var beat: Timer = scene["beat"]
	var excitement: Variant = scene["excitement"]
	var affection: Variant = scene["affection"]
	var feelings: FakeFeelings = scene["feelings"]
	service.begin()
	service.begin()
	check(service.active_ids().has("kissing"), "the Kissing provider starts")
	check(beat.paused, "start takes the shared excitement hold")
	check(facts.beat_holders.has("kissing"), "the provider owns the hold while it runs")
	check(near(excitement._until, 0.0), "start clears the game's excitement cause")
	check(near(feelings.level, 0.4), "start leaves the level to the act")
	check(facts.logs.has("integration kissing on"), "activation is logged once")
	service.tick(0.1)
	check(near(excitement._until, 0.5), "tick gives Kissing the acted cause")
	check(feelings.level > 0.0 and feelings.level <= 0.85,
		"the close tick raises the level under the bond cap")
	affection.kind = "kiss"
	excitement._until = 0.0
	var before_kiss := feelings.level
	service.tick(0.1)
	check(near(excitement._until, 0.0), "an Affection kiss keeps its own cause")
	check(near(feelings.level, before_kiss), "an Affection kiss owns the level")
	affection.kind = ""
	service.tick(0.1)
	check(near(excitement._until, 0.5), "the acted cause resumes after the kiss")
	check(feelings.level > before_kiss, "the level resumes after the kiss")
	service.afterglow()
	check(near(excitement._until, 0.0), "afterglow clears the acted cause")
	var afterglow_level := feelings.level
	service.tick(0.1)
	check(near(excitement._until, 0.0), "afterglow tick does not restart the cause")
	check(near(feelings.level, afterglow_level), "afterglow leaves the fade to Kissing")
	service.reset()
	check(service.active_ids().is_empty(), "reset stops the provider")
	check(not beat.paused, "reset releases the shared hold")
	check(facts.beat_holders.is_empty(), "reset drops the provider hold")
	check(near(excitement._until, 1.25), "reset restores the saved cause")
	check(near(feelings.level, 0.4), "reset restores the saved level")
	check(facts.logs.has("integration kissing off"), "deactivation is logged")
	service.reset()
	check(near(excitement._until, 1.25), "reset is idempotent")
	check(facts.logs.count("integration kissing on") == 1, "a repeated begin does not restart")
	_free_scene(scene)


func _check_feature_off() -> void:
	var scene := _setup(false)
	var facts: FakeFacts = scene["facts"]
	var service := SERVICE.new(facts)
	var beat: Timer = scene["beat"]
	var excitement: Variant = scene["excitement"]
	service.begin()
	check(service.active_ids().is_empty(), "the feature flag can keep the provider off")
	check(not beat.paused, "the beat is untouched when the provider is off")
	check(near(excitement._until, 1.25), "the cause is untouched when the provider is off")
	service.reset()
	check(near(excitement._until, 1.25), "a no-op reset changes nothing")
	_free_scene(scene)


func _check_missing_required() -> void:
	var scene := _setup()
	var facts: FakeFacts = scene["facts"]
	var service := SERVICE.new(facts)
	var beat: Timer = scene["beat"]
	var feelings: Node = scene["feelings"]
	feelings.free()
	service.begin()
	check(service.active_ids().is_empty(), "a missing required binding keeps the provider off")
	check(not beat.paused, "a missing required binding leaves the beat alone")
	service.reset()
	_free_scene(scene)


func _check_optional_late() -> void:
	var scene := _setup()
	var facts: FakeFacts = scene["facts"]
	var service := SERVICE.new(facts)
	var skeleton: Node = scene["skeleton"]
	var excitement: Variant = scene["excitement"]
	service.begin()
	var fidgets := _add_fidgets(skeleton)
	service.tick(0.1)
	check(int(fidgets._root) == -1, "a late fidget node loses its weight shift")
	check(near(float(fidgets._tap_next), 1.0e9), "a late fidget node loses its hoof taps")
	check(near(excitement._until, 0.5), "the rest of the bridge still runs")
	service.reset()
	check(int(fidgets._root) == 7, "reset restores the fidget root")
	check(near(float(fidgets._tap_next), 0.25), "reset restores the tap clock")
	_free_scene(scene)


func _check_live_toggle() -> void:
	var scene := _setup()
	var facts: FakeFacts = scene["facts"]
	var service := SERVICE.new(facts)
	var beat: Timer = scene["beat"]
	var excitement: Variant = scene["excitement"]
	service.begin()
	check(service.active_ids().has("kissing"), "the provider starts before the edit")
	facts.features = {"kissing_reactions": false}
	service.apply_live_settings()
	check(service.active_ids().is_empty(), "turning the flag off stops the provider live")
	check(not beat.paused, "turning the flag off releases the beat")
	check(facts.beat_holders.is_empty(), "turning the flag off drops the provider hold")
	check(near(excitement._until, 1.25), "turning the flag off restores the cause")
	facts.features = {"kissing_reactions": true}
	service.apply_live_settings()
	check(service.active_ids().has("kissing"), "turning the flag on starts the provider live")
	check(beat.paused, "turning the flag on takes the shared hold")
	check(facts.beat_holders.has("kissing"), "turning the flag on owns the hold again")
	check(near(excitement._until, 0.0), "turning the flag on starts from a clean cause")
	service.tick(0.1)
	check(near(excitement._until, 0.5), "the live provider ticks")
	service.reset()
	check(near(excitement._until, 1.25), "reset after live edits restores the original")
	_free_scene(scene)


func _check_two_owners() -> void:
	var scene := _setup()
	var facts: FakeFacts = scene["facts"]
	var service := SERVICE.new(facts)
	var beat: Timer = scene["beat"]
	var excitement: Variant = scene["excitement"]
	service.begin()
	check(facts.beat_holders.has("kissing"), "the provider takes its hold")
	facts.hold_beat("kiss")
	facts.features = {"kissing_reactions": false}
	service.apply_live_settings()
	check(beat.paused, "releasing the provider hold keeps the Beat held by the kiss")
	check(facts.beat_holders.has("kiss"), "the kiss owner remains")
	facts.release_beat("kiss")
	check(not beat.paused, "the last release restores the original Beat")
	check(facts.beat_holders.is_empty(), "no owner remains")
	service.reset()
	beat.paused = true
	facts.features = {"kissing_reactions": true}
	service.begin()
	check(beat.paused, "a pre-paused Beat stays paused while held")
	service.reset()
	check(beat.paused, "reset restores the pre-paused Beat")
	_free_scene(scene)


func _check_missing_mid_act() -> void:
	var scene := _setup()
	var facts: FakeFacts = scene["facts"]
	var service := SERVICE.new(facts)
	var beat: Timer = scene["beat"]
	var excitement: Variant = scene["excitement"]
	var feelings: Node = scene["feelings"]
	service.begin()
	service.tick(0.1)
	check(service.active_ids().has("kissing"), "the provider starts before the node disappears")
	feelings.free()
	service.tick(0.1)
	check(service.active_ids().is_empty(), "losing a required binding stops the provider")
	check(not beat.paused, "losing a required binding releases the hold")
	check(near(excitement._until, 1.25), "losing a required binding restores the saved cause")
	_free_scene(scene)


## The debug feature restores Kissing's root sway and hoof taps for the climax only.
func _check_full_fidgets() -> void:
	var scene := _setup()
	var facts: FakeFacts = scene["facts"]
	var service := SERVICE.new(facts)
	var skeleton: Node = scene["skeleton"]
	var fidgets := _add_fidgets(skeleton)
	facts.state = 3
	facts.mood = "climax"
	facts.satisfaction = 100.0
	facts.features = {"kissing_reactions": true, "kissing_full_fidgets": true}
	service.begin()
	service.tick(0.1)
	check(int(fidgets._root) == 7, "the climax restores the root sway")
	check(near(float(fidgets._tap_next), 0.25), "the climax restores the hoof taps")
	facts.state = 2
	facts.mood = "close"
	service.tick(0.1)
	check(int(fidgets._root) == -1, "leaving the climax suppresses the root sway")
	check(near(float(fidgets._tap_next), 1.0e9), "leaving the climax suppresses the hoof taps")
	facts.state = 3
	facts.mood = "climax"
	service.tick(0.1)
	service.afterglow()
	check(int(fidgets._root) == -1, "afterglow suppresses the full fidgets")
	check(near(float(fidgets._tap_next), 1.0e9), "afterglow restores the tap clock")
	service.reset()
	check(int(fidgets._root) == 7, "reset restores the act-start root")
	check(near(float(fidgets._tap_next), 0.25), "reset restores the act-start tap clock")
	_free_scene(scene)


## The Idle Life provider writes the act pose node's stretch flag and restores it on reset.
func _check_idle_life() -> void:
	var scene := _setup(false)
	var facts: FakeFacts = scene["facts"]
	var service := SERVICE.new(facts)
	var pose: FakePose = scene["pose"]
	facts.features = {"idle_life_stretch": true}
	facts.mods_active = {"idle_life": true}
	service.begin()
	check(service.active_ids().has("idle_life"), "the Idle Life provider starts")
	check(pose.stretch, "start turns the act pose into stretch mode")
	check(facts.logs.has("integration idle_life on"), "the stretch activation is logged")
	service.tick(0.1)
	check(pose.stretch, "the stretch stays on every tick")
	service.afterglow()
	check(pose.stretch, "the stretch holds through afterglow")
	facts.features = {"idle_life_stretch": false}
	service.apply_live_settings()
	check(not pose.stretch, "turning the feature off restores the normal pose live")
	facts.features = {"idle_life_stretch": true}
	service.apply_live_settings()
	check(pose.stretch, "turning the feature on reinstalls stretch mode live")
	service.reset()
	check(not pose.stretch, "reset restores the act-start pose mode")
	service.reset()
	check(not pose.stretch, "reset is idempotent")
	_free_scene(scene)


## Every gate keeps the normal standing pose: wrong pose, inactive mod, missing pose node.
func _check_idle_life_gates() -> void:
	var scene := _setup(false)
	var facts: FakeFacts = scene["facts"]
	var service := SERVICE.new(facts)
	var pose: FakePose = scene["pose"]
	facts.features = {"idle_life_stretch": true}
	facts.mods_active = {"idle_life": false}
	service.begin()
	check(not service.active_ids().has("idle_life"),
		"an inactive Idle Life leaves the pose alone")
	check(not pose.stretch, "an inactive Idle Life does not stretch")
	service.reset()
	facts.mods_active = {"idle_life": true}
	facts.pose_id = "missionary"
	service.begin()
	check(not service.active_ids().has("idle_life"),
		"a missionary act does not use the standing stretch")
	check(not pose.stretch, "a missionary act does not stretch")
	service.reset()
	facts.pose_id = "standing"
	pose.free()
	service.begin()
	check(not service.active_ids().has("idle_life"),
		"a missing pose binding keeps the stretch off")
	service.reset()
	scene["pose"] = null
	_free_scene(scene)


## Kissing and Idle Life run together: one owns the Beat, the other owns the stretch flag.
func _check_coexist() -> void:
	var scene := _setup(false)
	var facts: FakeFacts = scene["facts"]
	var service := SERVICE.new(facts)
	var pose: FakePose = scene["pose"]
	var beat: Timer = scene["beat"]
	var excitement: Variant = scene["excitement"]
	facts.features = {"kissing_reactions": true, "idle_life_stretch": true}
	facts.mods_active = {"idle_life": true}
	service.begin()
	var active: Array[String] = service.active_ids()
	check(active.has("kissing") and active.has("idle_life"),
		"both integrations start together")
	check(pose.stretch, "the stretch provider writes its pose")
	check(beat.paused and facts.beat_holders.has("kissing"),
		"the Kissing provider keeps the shared Beat hold")
	service.tick(0.1)
	check(near(excitement._until, 0.5), "the Kissing ramp still ticks beside the stretch")
	check(pose.stretch, "the stretch survives a Kissing tick")
	service.reset()
	check(not pose.stretch, "reset restores the normal pose with both providers")
	check(near(excitement._until, 1.25), "reset restores the Kissing cause")
	_free_scene(scene)
