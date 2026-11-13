extends SceneTree
## The idle hint's policy snapshot: reuse, every invalidation key, the TTL fallback and the fresh
## path a real gate takes. The scene rows are covered by `tests/scene_gate/`.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_runtime_offer_policy.gd

const RUNTIME := preload("res://mods/unfplap/runtime.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const MARE_REGISTRY := preload("res://mods/unfplap/registry/service.gd")

var failures := 0
var checks := 0


class FakeIdentity extends RefCounted:
	var id := "rarity"
	var display_name := "Rarity"
	var filly := false
	var stallion := false


class FakeBonds extends RefCounted:
	signal changed
	var adults := {"rarity": true}
	var stage := "dating"
	var welcome := true
	var romance := true

	func eligible_for_romance(_id: String) -> bool:
		return romance

	func welcomes(_id: String, _kind: String) -> bool:
		return welcome

	func record_for(_id: String) -> Dictionary:
		return {"stage": stage}


class FakeRelation extends Node:
	var bonds: FakeBonds

	func ladder(_id: String) -> Dictionary:
		return {"love": {"level": 2}, "friendship": {"level": 3}}


class FakePony extends Node3D:
	var identity: Variant


class FakeGame extends Node:
	pass


class FakeMain extends Node:
	var game: Node
	var player: Node
	var eligibility: ELIGIBILITY
	var runtimes: Dictionary = {}

	func runtime_for(pony: Node) -> Node:
		var runtime: Variant = runtimes.get(pony)
		return runtime if is_instance_valid(runtime) else null


class FakeForm extends Node:
	var form: Dictionary = {"kind": "human"}


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var main := FakeMain.new()
	main.name = "FakeMain"
	main.game = FakeGame.new()
	main.player = Node3D.new()
	root.add_child(main)
	root.add_child(main.game)
	root.add_child(main.player)
	main.eligibility = ELIGIBILITY.new()
	main.eligibility.setup(main)

	var pony := FakePony.new()
	pony.name = "Rarity"
	pony.identity = FakeIdentity.new()
	pony.set_meta("relationship_id", "rarity")
	var relation := FakeRelation.new()
	var bonds := FakeBonds.new()
	relation.bonds = bonds
	pony.set_meta("relationship_runtime", relation)
	root.add_child(pony)

	var runtime: Node = RUNTIME.new()
	runtime.main = main
	runtime.pony = pony
	main.runtimes[pony] = runtime
	root.add_child(runtime)

	var first: ELIGIBILITY.Verdict = runtime.offer_policy_verdict()
	check(first != null, "the hint builds a policy snapshot")
	check(runtime.offer_policy_verdict() == first,
		"the snapshot is reused while its key is unchanged")

	var generation := SETTINGS.generation
	SETTINGS.generation += 1
	var after_settings: ELIGIBILITY.Verdict = runtime.offer_policy_verdict()
	check(after_settings != first, "a settings generation bump rebuilds the snapshot")
	SETTINGS.generation = generation

	var registry_revision := MARE_REGISTRY.revision
	MARE_REGISTRY.revision += 1
	var after_registry: ELIGIBILITY.Verdict = runtime.offer_policy_verdict()
	check(after_registry != after_settings, "a registry revision bump rebuilds the snapshot")
	MARE_REGISTRY.revision = registry_revision

	var history_revision := ACT_HISTORY.revision
	ACT_HISTORY.revision += 1
	var after_history: ELIGIBILITY.Verdict = runtime.offer_policy_verdict()
	check(after_history != after_registry, "a history revision bump rebuilds the snapshot")
	ACT_HISTORY.revision = history_revision

	bonds.changed.emit()
	var after_signal: ELIGIBILITY.Verdict = runtime.offer_policy_verdict()
	check(after_signal != after_history, "the relationship change signal rebuilds the snapshot")

	runtime.set_cycle_override("heat")
	var after_cycle: ELIGIBILITY.Verdict = runtime.offer_policy_verdict()
	check(after_cycle != after_signal, "a cycle phase change rebuilds the snapshot")
	runtime.set_cycle_override("")

	var form_driver := FakeForm.new()
	form_driver.form = {"kind": "human"}
	form_driver.add_to_group("player_pony_form")
	root.add_child(form_driver)
	var after_human: ELIGIBILITY.Verdict = runtime.offer_policy_verdict()
	form_driver.form = {"kind": "pony", "race": "earth", "sex": "mare", "age": "adult",
		"eyes": "blue"}
	var after_form: ELIGIBILITY.Verdict = runtime.offer_policy_verdict()
	check(after_form != after_human, "a player form change rebuilds the snapshot")
	form_driver.remove_from_group("player_pony_form")
	form_driver.queue_free()

	# The fallback TTL is a safety net for a missed signal: expire the stamp without changing
	# anything else and the next scan rebuilds.
	runtime._offer_policy_at_usec -= RUNTIME.OFFER_POLICY_TTL_USEC + 1
	var after_ttl: ELIGIBILITY.Verdict = runtime.offer_policy_verdict()
	check(after_ttl != after_form, "the fallback TTL rebuilds the snapshot")

	# A real start/refusal/debug gate asks `_policy_verdict()` directly, so it never gets the
	# hint's cached object even when one is warm.
	var fresh: ELIGIBILITY.Verdict = runtime._policy_verdict(ELIGIBILITY.Mode.START)
	check(fresh != after_ttl, "the fresh gate path bypasses the hint snapshot")

	print("RUNTIME_OFFER_POLICY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
