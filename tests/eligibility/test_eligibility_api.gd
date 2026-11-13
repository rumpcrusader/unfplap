extends SceneTree
## Eligibility API adapter: live facts, capability targets, consent, the typed verdict and the
## provider profile layer. No world file is touched; SETTINGS uses a throwaway XDG data dir in the
## test runner.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/eligibility/test_eligibility_api.gd

const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")

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
	var eligibility: ELIGIBILITY

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
	relation.bonds = FakeBonds.new()
	pony.set_meta("relationship_runtime", relation)
	root.add_child(pony)

	check(main.eligibility.eligible(pony), "an adult mare is an act target")
	check(main.eligibility.witness_age(pony) == ELIGIBILITY.Age.ADULT,
		"an adult mare witnesses as an adult")

	var verdict: ELIGIBILITY.Verdict = main.eligibility.get_verdict(pony, ELIGIBILITY.Mode.START)
	check(str(verdict.facts.id) == "rarity", "facts take the relationship id")
	check(not bool(verdict.facts.player_young), "the human form is adult")
	check(bool(verdict.facts.has_relationship) and bool(verdict.facts.registered_adult),
		"facts read the relationship runtime")
	check(bool(verdict.facts.willing), "facts read kiss willingness")
	check(str(verdict.facts.stage) == "dating" and int(verdict.facts.love_level) == 2,
		"facts read the ladder and stage")
	check(not bool(verdict.facts.stored_bond), "no Mods node means no stored bond")

	check(bool(verdict.show) and bool(verdict.attempt), "Try Your Luck starts a willing mare")
	check(bool(verdict.offer) and bool(verdict.bond), "offers and bond grants pass")
	check(not bool(verdict.stop), "a willing mare continues an act")
	check(verdict.rows_text().contains("adult"), "the typed rows are readable")
	check(verdict.reasons().is_empty(), "a passing verdict has no reasons")

	relation.bonds.welcome = false
	var unwilling: ELIGIBILITY.Verdict = main.eligibility.get_verdict(pony, ELIGIBILITY.Mode.START)
	check(bool(unwilling.show), "Try Your Luck still shows the hint")
	check(not bool(unwilling.attempt) and bool(unwilling.buck_refuse),
		"unwilling starts the refusal path")

	var stallion := FakePony.new()
	var stallion_identity := FakeIdentity.new()
	stallion_identity.stallion = true
	stallion.identity = stallion_identity
	root.add_child(stallion)
	check(not main.eligibility.eligible(stallion), "a stallion is not an act target")
	check(main.eligibility.witness_age(stallion) == ELIGIBILITY.Age.ADULT,
		"a stallion is an adult witness")

	# Capability targets keep identity private: the three act-side targets accept an adult mare,
	# the character target has no participation veto, and an opt-out stays editable.
	check(main.eligibility.eligible(pony, ELIGIBILITY.Target.ACT)
		and main.eligibility.eligible(pony, ELIGIBILITY.Target.ANATOMY)
		and main.eligibility.eligible(pony, ELIGIBILITY.Target.TAIL),
		"the act, anatomy and tail targets accept an adult mare")
	check(main.eligibility.eligible(pony, ELIGIBILITY.Target.CHARACTER),
		"the character target accepts an adult mare")
	SETTINGS.save_participation("rarity", {"acts": false})
	check(not main.eligibility.eligible(pony, ELIGIBILITY.Target.ACT),
		"a participation opt-out closes the act target")
	check(main.eligibility.eligible(pony, ELIGIBILITY.Target.CHARACTER),
		"an opt-out keeps the character target editable")
	SETTINGS.reset_participation("rarity")

	# Consent is read through the typed profile, not a raw settings dictionary.
	var consent: Dictionary = SETTINGS.consent("rarity")
	var profile: ELIGIBILITY.Profile = main.eligibility.get_profile("rarity")
	check(profile.consent.public == bool(consent.get("public", false))
		and profile.consent.anal == bool(consent.get("anal", false))
		and profile.consent.oral == bool(consent.get("oral", false)),
		"the profile consent matches the resolver")

	# The provider layer: set_profile writes the identity half, and the capability reads it.
	var layer := ELIGIBILITY.Profile.new()
	layer.adult = ELIGIBILITY.AdultAssertion.ADULT
	layer.participation.anatomy = false
	var written := main.eligibility.set_profile(main, "rarity", layer)
	check(bool(written.get("ok", false)), "set_profile writes a provider layer")
	var read_back: ELIGIBILITY.Profile = main.eligibility.get_profile("rarity")
	check(read_back.adult == ELIGIBILITY.AdultAssertion.ADULT,
		"set_profile stores the adult assertion")
	check(not read_back.participation.anatomy, "set_profile stores the participation veto")
	check(not main.eligibility.eligible(pony, ELIGIBILITY.Target.ANATOMY),
		"the provider veto closes the anatomy target")
	check(main.eligibility.eligible(pony, ELIGIBILITY.Target.ACT),
		"the provider veto leaves the act target")
	check(main.eligibility.eligible(pony, ELIGIBILITY.Target.CHARACTER),
		"the provider veto leaves the character target")
	check(not bool(main.eligibility.set_profile(null, "rarity", layer).get("ok", false)),
		"set_profile rejects a null owner")
	check(main.eligibility.get_profile("rarity").adult_value() == true,
		"the cross-mod shape is the tri-state adult value")

	relation.bonds.welcome = true
	SETTINGS.sex_start.set_choice("when_available")
	var available: ELIGIBILITY.Verdict = main.eligibility.get_verdict(pony, ELIGIBILITY.Mode.START)
	check(not bool(available.show), "When Available needs the stored bond")
	check(bool(available.bond), "the bond mode does not need a stored bond")
	SETTINGS.sex_start.set_choice("try_luck")

	main.eligibility.clear()
	check(not main.eligibility.eligible(pony), "cleared service rejects every pony")
	main.eligibility.setup(main)
	check(main.eligibility.eligible(pony), "setup after clear restores the service")
	var restored: ELIGIBILITY.Verdict = main.eligibility.get_verdict(pony, ELIGIBILITY.Mode.START)
	check(bool(restored.bond), "setup after clear restores the verdict")

	print("ELIGIBILITY_API_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ELIGIBILITY_API_PASS")
	quit(0 if failures == 0 else 1)
