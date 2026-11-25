extends "res://mods/unfplap/tests/support/suite.gd"
## The integrations split: the per-pony adapter's binding resolution, save/restore, optional
## bindings, live feature edits and idempotent reset, and the World facade's pack modules.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/integrations/test_service.gd

const ADAPTER := preload("res://mods/unfplap/integrations/act.gd")
const FACADE := preload("res://mods/unfplap/integrations/api.gd")
const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const ANATOMY := preload("res://mods/unfplap/anatomy/api.gd")
const BODY_CHANGE_SERVICE := preload("res://mods/unfplap/body_change/api.gd")
const PONIES := preload("res://mods/unfplap/ponies/api.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/api.gd")



class FakeView extends RefCounted:
	var family := "standing"


class FakeFacts extends RefCounted:
	var state := 2
	var pose_view: Variant = FakeView.new()
	var satisfaction := 75.0
	var mood := "close"
	var seconds_since_stroke := 0.0
	var act_seconds := 1.0
	var pony: Variant = null
	var beat: Variant = null
	var beat_original := false
	var beat_holders: Array[String] = []
	var mods_active: Dictionary = {}

	func mod_active(id: String) -> bool:
		return bool(mods_active.get(id, false))

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


## The pack-active seam both modules read; the facade fixture keeps both packs off.
class PackGate extends RefCounted:
	var on := false

	func active() -> bool:
		return on


## Records the provider the facade registers, without the real source registry.
class SourceRecorder extends BODY_CHANGE_SERVICE:
	var sources: Array[Node] = []

	func register_source(source: Node) -> bool:
		sources.append(source)
		return true


## The pantyhose module's act-start seam: the facade must hand it the pony.
class ActStartSpy extends "res://mods/unfplap/integrations/pantyhose.gd":
	var ponies: Array[Node] = []

	func act_started(pony: Node3D) -> void:
		ponies.append(pony)

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
	var feelings := FakeFeelings.new()
	feelings.name = "KissingFeelings"
	pony.add_child(feelings)
	var affection := FakeAffection.new()
	affection.name = "Affection"
	pony.add_child(affection)
	var facts := FakeFacts.new()
	facts.pony = pony
	var previous := SETTINGS.kissing_reactions.get_bool()
	SETTINGS.kissing_reactions.set_bool(feature)
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
		"kissing_previous": previous,
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
	if scene.has("kissing_previous"):
		SETTINGS.kissing_reactions.set_bool(bool(scene["kissing_previous"]))


func run() -> void:
	_check_basic()
	_check_feature_off()
	_check_missing_required()
	_check_optional_late()
	_check_live_toggle()
	_check_two_owners()
	_check_missing_mid_act()
	_check_climax_fidgets()
	_check_world_only()
	_check_runtime_beat_hold()
	_check_facade()
	finish()


func _check_basic() -> void:
	var scene := _setup()
	var facts: FakeFacts = scene["facts"]
	var service := ADAPTER.new(facts)
	var beat: Timer = scene["beat"]
	var excitement: Variant = scene["excitement"]
	var affection: Variant = scene["affection"]
	var feelings: FakeFeelings = scene["feelings"]
	service.begin()
	service.begin()
	check(service.active_ids().has("kissing"), "the Kissing provider starts")
	check(beat.paused, "start takes the shared excitement hold")
	check(facts.beat_holders.has("kissing"), "the provider owns the hold while it runs")
	check(near(excitement._until, 0.0, 0.00001), "start clears the game's excitement cause")
	check(near(feelings.level, 0.4, 0.00001), "start leaves the level to the act")
	service.tick(0.1)
	check(near(excitement._until, 0.5, 0.00001), "tick gives Kissing the acted cause")
	check(feelings.level > 0.0 and feelings.level <= 0.85,
		"the close tick raises the level under the bond cap")
	affection.kind = "kiss"
	excitement._until = 0.0
	var before_kiss := feelings.level
	service.tick(0.1)
	check(near(excitement._until, 0.0, 0.00001), "an Affection kiss keeps its own cause")
	check(near(feelings.level, before_kiss, 0.00001), "an Affection kiss owns the level")
	affection.kind = ""
	service.tick(0.1)
	check(near(excitement._until, 0.5, 0.00001), "the acted cause resumes after the kiss")
	check(feelings.level > before_kiss, "the level resumes after the kiss")
	service.afterglow()
	check(near(excitement._until, 0.0, 0.00001), "afterglow clears the acted cause")
	var afterglow_level := feelings.level
	service.tick(0.1)
	check(near(excitement._until, 0.0, 0.00001), "afterglow tick does not restart the cause")
	check(near(feelings.level, afterglow_level, 0.00001), "afterglow leaves the fade to Kissing")
	service.reset()
	check(service.active_ids().is_empty(), "reset stops the provider")
	check(not beat.paused, "reset releases the shared hold")
	check(facts.beat_holders.is_empty(), "reset drops the provider hold")
	check(near(excitement._until, 1.25, 0.00001), "reset restores the saved cause")
	check(near(feelings.level, 0.4, 0.00001), "reset restores the saved level")
	service.reset()
	check(near(excitement._until, 1.25, 0.00001), "reset is idempotent")
	_free_scene(scene)


func _check_feature_off() -> void:
	var scene := _setup(false)
	var facts: FakeFacts = scene["facts"]
	var service := ADAPTER.new(facts)
	var beat: Timer = scene["beat"]
	var excitement: Variant = scene["excitement"]
	service.begin()
	check(service.active_ids().is_empty(), "the feature flag can keep the provider off")
	check(not beat.paused, "the beat is untouched when the provider is off")
	check(near(excitement._until, 1.25, 0.00001), "the cause is untouched when the provider is off")
	service.reset()
	check(near(excitement._until, 1.25, 0.00001), "a no-op reset changes nothing")
	_free_scene(scene)


func _check_missing_required() -> void:
	var scene := _setup()
	var facts: FakeFacts = scene["facts"]
	var service := ADAPTER.new(facts)
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
	var service := ADAPTER.new(facts)
	var skeleton: Node = scene["skeleton"]
	var excitement: Variant = scene["excitement"]
	service.begin()
	var fidgets := _add_fidgets(skeleton)
	service.tick(0.1)
	check(int(fidgets._root) == -1, "a late fidget node loses its weight shift")
	check(near(float(fidgets._tap_next), 1.0e9, 0.00001), "a late fidget node loses its hoof taps")
	check(near(excitement._until, 0.5, 0.00001), "the rest of the bridge still runs")
	service.reset()
	check(int(fidgets._root) == 7, "reset restores the fidget root")
	check(near(float(fidgets._tap_next), 0.25, 0.00001), "reset restores the tap clock")
	_free_scene(scene)


func _check_live_toggle() -> void:
	var scene := _setup()
	var facts: FakeFacts = scene["facts"]
	var service := ADAPTER.new(facts)
	var beat: Timer = scene["beat"]
	var excitement: Variant = scene["excitement"]
	service.begin()
	check(service.active_ids().has("kissing"), "the provider starts before the edit")
	SETTINGS.kissing_reactions.set_bool(false)
	service.apply_live_settings()
	check(service.active_ids().is_empty(), "turning the flag off stops the provider live")
	check(not beat.paused, "turning the flag off releases the beat")
	check(facts.beat_holders.is_empty(), "turning the flag off drops the provider hold")
	check(near(excitement._until, 1.25, 0.00001), "turning the flag off restores the cause")
	SETTINGS.kissing_reactions.set_bool(true)
	service.apply_live_settings()
	check(service.active_ids().has("kissing"), "turning the flag on starts the provider live")
	check(beat.paused, "turning the flag on takes the shared hold")
	check(facts.beat_holders.has("kissing"), "turning the flag on owns the hold again")
	check(near(excitement._until, 0.0, 0.00001), "turning the flag on starts from a clean cause")
	service.tick(0.1)
	check(near(excitement._until, 0.5, 0.00001), "the live provider ticks")
	service.reset()
	check(near(excitement._until, 1.25, 0.00001), "reset after live edits restores the original")
	_free_scene(scene)


func _check_two_owners() -> void:
	var scene := _setup()
	var facts: FakeFacts = scene["facts"]
	var service := ADAPTER.new(facts)
	var beat: Timer = scene["beat"]
	var excitement: Variant = scene["excitement"]
	service.begin()
	check(facts.beat_holders.has("kissing"), "the provider takes its hold")
	facts.hold_beat("kiss")
	SETTINGS.kissing_reactions.set_bool(false)
	service.apply_live_settings()
	check(beat.paused, "releasing the provider hold keeps the Beat held by the kiss")
	check(facts.beat_holders.has("kiss"), "the kiss owner remains")
	facts.release_beat("kiss")
	check(not beat.paused, "the last release restores the original Beat")
	check(facts.beat_holders.is_empty(), "no owner remains")
	service.reset()
	beat.paused = true
	SETTINGS.kissing_reactions.set_bool(true)
	service.begin()
	check(beat.paused, "a pre-paused Beat stays paused while held")
	service.reset()
	check(beat.paused, "reset restores the pre-paused Beat")
	_free_scene(scene)


func _check_missing_mid_act() -> void:
	var scene := _setup()
	var facts: FakeFacts = scene["facts"]
	var service := ADAPTER.new(facts)
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
	check(near(excitement._until, 1.25, 0.00001), "losing a required binding restores the saved cause")
	_free_scene(scene)


## Her climax restores Kissing's root sway and hoof taps; the rest of the act suppresses them.
func _check_climax_fidgets() -> void:
	var scene := _setup()
	var facts: FakeFacts = scene["facts"]
	var service := ADAPTER.new(facts)
	var skeleton: Node = scene["skeleton"]
	var fidgets := _add_fidgets(skeleton)
	facts.state = 3
	facts.mood = "climax"
	facts.satisfaction = 100.0
	SETTINGS.kissing_reactions.set_bool(true)
	service.begin()
	service.tick(0.1)
	check(int(fidgets._root) == 7, "the climax restores the root sway")
	check(near(float(fidgets._tap_next), 0.25, 0.00001), "the climax restores the hoof taps")
	facts.state = 2
	facts.mood = "close"
	service.tick(0.1)
	check(int(fidgets._root) == -1, "leaving the climax suppresses the root sway")
	check(near(float(fidgets._tap_next), 1.0e9, 0.00001), "leaving the climax suppresses the hoof taps")
	facts.state = 3
	facts.mood = "climax"
	service.tick(0.1)
	service.afterglow()
	check(int(fidgets._root) == -1, "afterglow suppresses the climax fidgets")
	check(near(float(fidgets._tap_next), 1.0e9, 0.00001), "afterglow restores the tap clock")
	service.reset()
	check(int(fidgets._root) == 7, "reset restores the act-start root")
	check(near(float(fidgets._tap_next), 0.25, 0.00001), "reset restores the act-start tap clock")
	_free_scene(scene)


## The scene hold's named Beat ownership: the last release restores, a repeated owner releases
## once, and an already-paused Beat stays paused.
func _check_runtime_beat_hold() -> void:
	var scene := _runtime_beat()
	var runtime: Node = scene["runtime"]
	var beat: Timer = scene["beat"]
	runtime.act.context.hold.hold_beat("same")
	runtime.act.context.hold.hold_beat("same")
	runtime.act.context.hold.release_beat("same")
	check(not beat.paused, "a repeated owner releases once")
	_free_runtime_beat(scene)

	scene = _runtime_beat(true)
	runtime = scene["runtime"]
	beat = scene["beat"]
	runtime.act.context.hold.hold_beat("first")
	runtime.act.context.hold.release_beat("first")
	check(beat.paused, "an already-paused Beat stays paused")
	_free_runtime_beat(scene)

	scene = _runtime_beat()
	runtime = scene["runtime"]
	beat = scene["beat"]
	runtime.act.context.hold.hold_beat("first")
	runtime.act.context.hold.hold_beat("second")
	runtime.act.context.hold.release_beat("first")
	check(beat.paused, "one remaining owner keeps the Beat paused")
	runtime.act.context.hold.release_beat("second")
	check(not beat.paused, "the last release restores the Beat")
	_free_runtime_beat(scene)

	scene = _runtime_beat()
	runtime = scene["runtime"]
	beat = scene["beat"]
	runtime.act.context.hold.hold_beat("first")
	runtime.act.context.hold.hold_beat("second")
	runtime.act.context.hold.release_all_beats()
	check(not beat.paused, "act teardown restores the Beat even with owners left")
	_free_runtime_beat(scene)

	scene = _runtime_beat(false, false)
	runtime = scene["runtime"]
	runtime.act.context.hold.hold_beat("first")
	runtime.act.context.hold.release_beat("first")
	check((runtime.act.context.hold._beat_holders as Array).is_empty(),
		"a scene without a Beat releases the hold without an owner left")
	check(runtime.act.context.hold._beat == null,
		"a scene without a Beat leaves no resolved timer")
	_free_runtime_beat(scene)


func _runtime_beat(paused := false, with_beat := true) -> Dictionary:
	var pony := FakePony.new()
	var excitement := Node.new()
	excitement.name = "Excitement"
	var beat: Timer = null
	if with_beat:
		beat = Timer.new()
		beat.name = "Beat"
		beat.paused = paused
		excitement.add_child(beat)
	pony.add_child(excitement)
	pony.excitement = excitement
	root.add_child(pony)
	var runtime: Node = RUNTIME.new()
	runtime.pony = pony
	root.add_child(runtime)
	return {"pony": pony, "runtime": runtime, "beat": beat}


func _free_runtime_beat(scene: Dictionary) -> void:
	var runtime: Node = scene["runtime"]
	var pony: Node = scene["pony"]
	runtime.free()
	pony.free()


## The Pantyhose & Panties pack is a world integration. Its adapter has no per-act provider, so
## the per-pony adapter must not create one even when its flags are on and the pack is active.
func _check_world_only() -> void:
	var scene := _setup()
	var facts: FakeFacts = scene["facts"]
	facts.mods_active = {"pantyhose": true}
	var service := ADAPTER.new(facts)
	service.begin()
	check(not service.active_ids().has("pantyhose"),
		"the Pantyhose world integration has no per-act provider")
	check(service.active_ids().has("kissing"), "Kissing still runs beside it")
	service.reset()
	_free_scene(scene)


## The World facade owns both pack modules: it builds and wires them, attaches them under
## itself, registers the provider and forwards the runtime's act start.
func _check_facade() -> void:
	var anatomy := ANATOMY.new()
	var body_change := SourceRecorder.new()
	var ponies := PONIES.new()
	var eligibility := ELIGIBILITY.new()
	var gate := PackGate.new()
	var facade := FACADE.new()
	facade.name = "UnfplapIntegrations"
	facade.wire(anatomy, body_change, ponies, eligibility, null)
	var pantyhose: Node = facade.pantyhose()
	var changelings: Node = facade.changelings()
	check_not_null(pantyhose, "the facade builds the pantyhose module")
	check_not_null(changelings, "the facade builds the changelings module")
	check(pantyhose.get("_anatomy_service") == anatomy,
		"the facade hands the pantyhose module its anatomy peer")
	check(changelings.get("_ponies") == ponies
		and changelings.get("_body_change_service") == body_change,
		"the facade hands the changelings module its body-change peers")
	pantyhose.set("mod_active", Callable(gate, "active"))
	changelings.set("mod_active", Callable(gate, "active"))
	root.add_child(facade)
	check(pantyhose.get_parent() == facade,
		"the facade attaches the pantyhose module under itself")
	check(changelings.get_parent() == facade,
		"the facade attaches the changelings module under itself")
	check(facade.get_node_or_null("UnfplapPantyhose") == pantyhose,
		"the pantyhose module keeps its node name")
	check(facade.get_node_or_null("UnfplapChangelings") == changelings,
		"the changelings module keeps its node name")
	check(body_change.sources.size() == 1 and body_change.sources[0] == changelings,
		"the facade registers the changelings provider")

	var host := Node.new()
	host.name = "FakeWorld"
	root.add_child(host)
	facade.on_world(host)
	check(pantyhose.get("_game") == host, "the facade forwards on_world to the modules")
	facade.on_player(host)
	facade.on_world_closed()
	check_null(pantyhose.get("_game"), "the facade forwards on_world_closed to the modules")

	var spy := ActStartSpy.new()
	facade.set("_pantyhose", spy)
	var pony := Node3D.new()
	root.add_child(pony)
	facade.act_started(pony)
	check(spy.ponies == [pony],
		"the facade forwards the runtime's act start to the pantyhose module")
	facade.set("_pantyhose", pantyhose)
	facade.shutdown()
	root.remove_child(pony)
	pony.free()
	spy.free()
	root.remove_child(host)
	host.free()
	facade.free()
	body_change.free()
	anatomy.free()
	ponies.free()
	eligibility.free()


