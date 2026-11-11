extends SceneTree
## Eligibility API adapter: live facts, adult predicates, consent and one verdict. No world file is
## touched; SETTINGS uses a throwaway XDG data dir in the test runner.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/test_eligibility_api.gd

const ELIGIBILITY := preload("res://mods/unfplap/eligibility.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")

var failures := 0
var checks := 0


class FakeIdentity extends RefCounted:
	var id := "rarity"
	var display_name := "Rarity"
	var filly := false
	var stallion := false


class FakeBonds extends RefCounted:
	var adults := {"rarity": true}
	var stage := "dating"
	var welcome := true

	func eligible_for_romance(_id: String) -> bool:
		return true

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
	var mares: Array = []


class FakeMain extends Node:
	var game: Node
	var player: Node
	var runtimes: Dictionary = {}
	var eligibility: Variant

	func runtime_for(pony: Node) -> Node:
		var runtime: Variant = runtimes.get(pony)
		return runtime if is_instance_valid(runtime) else null


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func run() -> void:
	var main := FakeMain.new()
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
	relation.bonds = FakeBonds.new()
	pony.set_meta("relationship_runtime", relation)
	root.add_child(pony)

	check(main.eligibility.adult_mare(pony), "an adult mare is a target")
	check(main.eligibility.adult_pony(pony), "an adult mare is an adult pony")
	check(main.eligibility.adult_player(), "the human form is adult")

	var facts: Dictionary = main.eligibility.facts(pony)
	check(str(facts.id) == "rarity", "facts take the relationship id")
	check(bool(facts.has_relationship) and bool(facts.registered_adult),
		"facts read the relationship runtime")
	check(bool(facts.willing), "facts read kiss willingness")
	check(str(facts.stage) == "dating" and int(facts.love_level) == 2,
		"facts read the ladder and stage")
	check(not bool(facts.stored_bond), "no Mods node means no stored bond")

	var verdict: Dictionary = main.eligibility.evaluate(pony, ELIGIBILITY.MODE_START)
	check(bool(verdict.show) and bool(verdict.attempt), "Try Your Luck starts a willing mare")
	check(bool(verdict.offer) and bool(verdict.bond), "offers and bond grants pass")
	check(not bool(verdict.stop), "a willing mare continues an act")
	check(main.eligibility.debug_text(pony, ELIGIBILITY.MODE_START).contains("eligibility"),
		"debug text is available")

	relation.bonds.welcome = false
	var unwilling: Dictionary = main.eligibility.evaluate(pony, ELIGIBILITY.MODE_START)
	check(bool(unwilling.show), "Try Your Luck still shows the hint")
	check(not bool(unwilling.attempt) and bool(unwilling.buck_refuse),
		"unwilling starts the refusal path")

	var stallion := FakePony.new()
	var stallion_identity := FakeIdentity.new()
	stallion_identity.stallion = true
	stallion.identity = stallion_identity
	root.add_child(stallion)
	check(not main.eligibility.adult_mare(stallion), "a stallion is not an act target")
	check(main.eligibility.adult_pony(stallion), "a stallion is still an adult pony")

	var consent: Dictionary = SETTINGS.consent("rarity")
	for key: String in ELIGIBILITY.ACTIONS:
		check(main.eligibility.action_consent(pony, key) == bool(consent.get(key, false)),
			"action consent matches the resolver: %s" % key)

	relation.bonds.welcome = true
	SETTINGS.sex_start.set_choice("when_available")
	var available: Dictionary = main.eligibility.evaluate(pony, ELIGIBILITY.MODE_START)
	check(not bool(available.show), "When Available needs the stored bond")
	check(bool(available.bond), "the bond mode does not need a stored bond")
	SETTINGS.sex_start.set_choice("try_luck")

	main.eligibility.clear()
	check(not main.eligibility.adult_mare(pony), "cleared service rejects every pony")
	main.eligibility.setup(main)
	check(main.eligibility.adult_mare(pony), "setup after clear restores the service")
	var restored: Dictionary = main.eligibility.evaluate(pony, ELIGIBILITY.MODE_START)
	check(bool(restored.bond), "setup after clear restores the verdict")

	print("ELIGIBILITY_API_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ELIGIBILITY_API_PASS")
	quit(0 if failures == 0 else 1)
