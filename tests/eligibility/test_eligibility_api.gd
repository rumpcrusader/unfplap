extends SceneTree
## Eligibility API adapter: live facts, capability targets, consent, the typed verdict and the
## provider profile layer. No world file is touched; SETTINGS uses
## a throwaway XDG data dir in the test runner.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/eligibility/test_eligibility_api.gd

const WORLD := preload("res://mods/unfplap/world/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const FACTS := preload("res://mods/unfplap/eligibility/facts.gd")
const PARTICIPATION := preload("res://mods/unfplap/shared/participation.gd")
const CONSENT := preload("res://mods/unfplap/shared/consent.gd")
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
	var romance := true
	var welcomes_calls := 0

	func eligible_for_romance(_id: String) -> bool:
		return romance

	func welcomes(_id: String, _kind: String) -> bool:
		welcomes_calls += 1
		return welcome

	func record_for(_id: String) -> Dictionary:
		return {"stage": stage}


class FakeRelation extends Node:
	var bonds: FakeBonds

	func ladder(_id: String) -> Dictionary:
		return {"love": {"level": 2}, "friendship": {"level": 3}}


class FakePony extends Node3D:
	var identity: Variant


class FakeContext extends Node:
	var state := {}


class FakePopulation extends Node:
	var available: Dictionary = {}


class FakeGame extends Node:
	var mares: Array = []
	var world_context: Node
	var population: Node


class FakeMain extends Node:
	var game: Node
	var player: Node
	var eligibility: ELIGIBILITY


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
	WORLD.bind_world(main.game)
	main.game.world_context = FakeContext.new()
	main.game.population = FakePopulation.new()
	main.game.population.available = {
		"rarity": "res://world/characters/mane6/rarity.tscn",
		"scootaloo": "res://world/characters/background/scootaloo.tscn",
	}
	main.player = Node3D.new()
	WORLD.bind_player(main.player)
	root.add_child(main)
	root.add_child(main.game)
	root.add_child(main.game.world_context)
	root.add_child(main.game.population)
	root.add_child(main.player)
	main.eligibility = ELIGIBILITY.new()
	main.eligibility.on_world(null)

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
	check(main.eligibility.eligible_id("rarity"),
		"a non-live adult shape is a character target")
	check(not main.eligibility.eligible_id("scootaloo"),
		"a non-live filly shape is not a character target")
	check(not main.eligibility.eligible_id("not_a_pony"),
		"an unknown shape is not a character target")
	check(FACTS.AgeKind.NONE == ELIGIBILITY.Age.NONE
		and FACTS.AgeKind.YOUNG == ELIGIBILITY.Age.YOUNG
		and FACTS.AgeKind.ADULT == ELIGIBILITY.Age.ADULT,
		"the pure age kind and the public witness age stay in step")

	var verdict: ELIGIBILITY.Verdict = main.eligibility.get_verdict(pony, ELIGIBILITY.Mode.START)
	check(str(verdict.facts.id) == "rarity", "facts take the relationship id")
	check(not bool(verdict.facts.player_young), "the human form is adult")
	check(bool(verdict.facts.has_relationship) and bool(verdict.facts.registered_adult),
		"facts read the relationship runtime")
	check(bool(verdict.facts.willing), "facts read kiss willingness")
	check(str(verdict.facts.stage) == "dating" and int(verdict.facts.love_level) == 2,
		"facts read the ladder and stage")

	check(bool(verdict.show), "a willing mare starts")
	check(bool(verdict.offer), "offers pass")
	check(verdict.rows_text().contains("adult"), "the typed rows are readable")
	check(verdict.reasons().is_empty(), "a passing verdict has no reasons")

	# Base clearance reads only the relationship facts it uses; willingness, history and cycle
	# stay on the full verdict.
	relation.bonds.welcomes_calls = 0
	check(main.eligibility.relationship_ok(pony), "the clearance relationship row passes")
	check(relation.bonds.welcomes_calls == 0, "clearance does not read kiss willingness")
	relation.bonds.welcome = false
	check(main.eligibility.relationship_ok(pony), "clearance ignores willingness")
	var saved_promiscuity := SETTINGS.promiscuity.get_choice()
	SETTINGS.promiscuity.set_choice("any")
	relation.bonds.romance = false
	check(not main.eligibility.relationship_ok(pony), "romance eligibility gates clearance")
	relation.bonds.romance = true
	check(main.eligibility.relationship_ok(pony), "Any Adult passes the floor")
	SETTINGS.promiscuity.set_choice("head_over_hooves")
	check(not main.eligibility.relationship_ok(pony), "the love floor gates clearance")
	pony.remove_meta("relationship_runtime")
	check(not main.eligibility.relationship_ok(pony), "no relationship runtime fails clearance")
	pony.set_meta("relationship_runtime", relation)
	# The love level comes from the game's own ladder cache, and `ladder()` is the fallback for a
	# pony the game has not recorded yet. The fake ladder says New Couple (2); the cache says
	# No crush yet (0), so a floor that the cached level fails and the ladder level passes proves
	# which read answered.
	main.game.world_context.state["bond_levels"] = {"rarity": {"friendship": 3, "love": 0}}
	SETTINGS.promiscuity.set_choice("new_couple")
	check(not main.eligibility.relationship_ok(pony),
		"the clearance floor reads the game's cached love level")
	check(int(main.eligibility.get_verdict(pony, ELIGIBILITY.Mode.START).facts.love_level) == 0,
		"the facts snapshot reads the cached love level too")
	main.game.world_context.state["bond_levels"] = {}
	check(main.eligibility.relationship_ok(pony),
		"an unrecorded pony falls back to the relationship ladder")
	check(int(main.eligibility.get_verdict(pony, ELIGIBILITY.Mode.START).facts.love_level) == 2,
		"the fallback fills the facts snapshot")
	SETTINGS.promiscuity.set_choice(saved_promiscuity)
	relation.bonds.welcome = false
	var unwilling: ELIGIBILITY.Verdict = main.eligibility.get_verdict(pony, ELIGIBILITY.Mode.START)
	check(not bool(unwilling.show), "an unwilling mare has no legacy hint")

	var stallion := FakePony.new()
	var stallion_identity := FakeIdentity.new()
	stallion_identity.stallion = true
	stallion.identity = stallion_identity
	root.add_child(stallion)
	check(not main.eligibility.eligible(stallion), "a stallion is not an act target")
	check(main.eligibility.witness_age(stallion) == ELIGIBILITY.Age.ADULT,
		"a stallion is an adult witness")

	# The identity predicate is age and sex only; the capability also needs a stable id.
	var nameless := FakePony.new()
	nameless.name = "Nameless"
	var nameless_identity := FakeIdentity.new()
	nameless_identity.id = ""
	nameless.identity = nameless_identity
	root.add_child(nameless)
	check(FACTS.adult_mare(true, false, false, false, null),
		"the pure predicate accepts an adult identity")
	check(not main.eligibility.eligible(nameless),
		"an adult identity with no stable id is not an act target")

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
	# The snapshots and target vetoes follow the shared key tables, so a new key cannot drift.
	check(profile.consent.to_dict().keys() == CONSENT.KEYS,
		"the consent snapshot covers the shared consent keys")
	check(profile.participation.to_dict().keys() == PARTICIPATION.KEYS,
		"the participation snapshot covers the shared participation keys")
	for target: Variant in ELIGIBILITY.TARGET_KEYS:
		var key := str(ELIGIBILITY.TARGET_KEYS[target])
		check(key.is_empty() or key in PARTICIPATION.KEYS,
			"every target veto is a participation key: %s" % key)

	# The provider layer: set_profile writes the identity half, and the capability reads it.
	var layer := ELIGIBILITY.Profile.new()
	layer.eligible = ELIGIBILITY.EligibilityAssertion.ELIGIBLE
	layer.participation.anatomy = false
	var written := main.eligibility.set_profile(main, "rarity", layer)
	check(bool(written.get("ok", false)), "set_profile writes a provider layer")
	var read_back: ELIGIBILITY.Profile = main.eligibility.get_profile("rarity")
	check(read_back.eligible == ELIGIBILITY.EligibilityAssertion.ELIGIBLE,
		"set_profile stores the eligible assertion")
	check(not read_back.participation.anatomy, "set_profile stores the participation veto")
	check(not main.eligibility.eligible(pony, ELIGIBILITY.Target.ANATOMY),
		"the provider veto closes the anatomy target")
	check(main.eligibility.eligible(pony, ELIGIBILITY.Target.ACT),
		"the provider veto leaves the act target")
	check(main.eligibility.eligible(pony, ELIGIBILITY.Target.CHARACTER),
		"the provider veto leaves the character target")
	check(not bool(main.eligibility.set_profile(null, "rarity", layer).get("ok", false)),
		"set_profile rejects a null owner")
	check(main.eligibility.get_profile("rarity").eligible_value() == true,
		"the cross-mod shape is the tri-state eligible value")

	# A provider eligible assertion resolves unfplap's registered-adult fact even when the base
	# game has not registered the pony as an adult. Base-game willingness and romance still gate.
	var filly := FakePony.new()
	filly.name = "Scootaloo"
	var filly_identity := FakeIdentity.new()
	filly_identity.id = "scootaloo"
	filly_identity.display_name = "Scootaloo"
	filly_identity.filly = true
	filly.identity = filly_identity
	filly.set_meta("relationship_id", "scootaloo")
	var filly_relation := FakeRelation.new()
	filly_relation.bonds = FakeBonds.new()
	filly_relation.bonds.adults = {"scootaloo": false}
	filly_relation.bonds.romance = false
	filly_relation.bonds.welcome = false
	filly.set_meta("relationship_runtime", filly_relation)
	root.add_child(filly)

	var fallback: ELIGIBILITY.Verdict = main.eligibility.get_verdict(filly, ELIGIBILITY.Mode.START)
	check(not bool(fallback.facts.registered_adult),
		"without a provider assertion registered_adult follows the base game")

	var filly_layer := ELIGIBILITY.Profile.new()
	filly_layer.eligible = ELIGIBILITY.EligibilityAssertion.ELIGIBLE
	check(bool(main.eligibility.set_profile(main, "scootaloo", filly_layer).get("ok", false)),
		"set_profile writes the filly provider layer")
	var filly_verdict: ELIGIBILITY.Verdict = main.eligibility.get_verdict(filly, ELIGIBILITY.Mode.START)
	check(filly_verdict.facts.eligible == ELIGIBILITY.EligibilityAssertion.ELIGIBLE,
		"the provider eligible assertion reaches the fact snapshot")
	check(bool(filly_verdict.facts.registered_adult),
		"the provider eligible assertion resolves registered_adult")
	check(not bool(filly_verdict.facts.romance_eligible),
		"base-game romance eligibility still gates")
	check(not bool(filly_verdict.facts.willing),
		"base-game kiss willingness still gates")
	check(not bool(filly_verdict.show), "base-game gates still block the act")

	# A provider not-eligible assertion overrides a base-game registered adult.
	layer.eligible = ELIGIBILITY.EligibilityAssertion.NOT_ELIGIBLE
	check(bool(main.eligibility.set_profile(main, "rarity", layer).get("ok", false)),
		"set_profile rewrites the eligible assertion")
	var blocked: ELIGIBILITY.Verdict = main.eligibility.get_verdict(pony, ELIGIBILITY.Mode.START)
	check(blocked.facts.eligible == ELIGIBILITY.EligibilityAssertion.NOT_ELIGIBLE,
		"the provider not-eligible assertion reaches the fact snapshot")
	check(not bool(blocked.facts.registered_adult),
		"the provider not-eligible assertion overrides registered_adult")
	layer.eligible = ELIGIBILITY.EligibilityAssertion.ELIGIBLE
	main.eligibility.set_profile(main, "rarity", layer)

	relation.bonds.welcome = true
	var available: ELIGIBILITY.Verdict = main.eligibility.get_verdict(pony, ELIGIBILITY.Mode.START)
	check(bool(available.show), "a willing mare shows the legacy hint")
	relation.bonds.welcome = false
	var available_unwilling: ELIGIBILITY.Verdict = main.eligibility.get_verdict(
		pony, ELIGIBILITY.Mode.START)
	check(not bool(available_unwilling.show), "an unwilling mare has no legacy hint")
	relation.bonds.welcome = true

	main.eligibility.shutdown()
	check(not main.eligibility.eligible(pony), "cleared service rejects every pony")
	main.eligibility.on_world(null)
	check(main.eligibility.eligible(pony), "setup after clear restores the service")
	var restored: ELIGIBILITY.Verdict = main.eligibility.get_verdict(pony, ELIGIBILITY.Mode.START)
	check(bool(restored.show), "setup after clear restores the verdict")

	print("ELIGIBILITY_API_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ELIGIBILITY_API_PASS")
	quit(0 if failures == 0 else 1)
