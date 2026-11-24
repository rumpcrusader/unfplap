extends "res://mods/unfplap/tests/support/suite.gd"
## Eligibility API adapter: the capability targets, the typed identity record, witness age, the
## profile snapshots and the provider profile layer. No world file is touched; SETTINGS uses
## a throwaway XDG data dir in the test runner.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/eligibility/test_eligibility_api.gd

const WORLD := preload("res://mods/unfplap/world/api.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/api.gd")
const IDENTITY_RECORD := preload("res://mods/unfplap/eligibility/identity_record.gd")
const FACTS := preload("res://mods/unfplap/eligibility/facts.gd")
const PARTICIPATION := preload("res://mods/unfplap/shared/participation.gd")
const CONSENT := preload("res://mods/unfplap/shared/consent.gd")
const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const ROWS := preload("res://mods/unfplap/settings/rows.gd")
const MARE_REGISTRY := preload("res://mods/unfplap/registry/api.gd")


class FakeIdentity extends RefCounted:
	var id := "rarity"
	var display_name := "Rarity"
	var filly := false
	var stallion := false


class FakeRelation extends Node:
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
	var pony_relation := FakeRelation.new()
	pony.set_meta("relationship_runtime", pony_relation)
	root.add_child(pony)

	check(main.eligibility.eligible(pony, ELIGIBILITY.Target.ACT), "an adult mare is an act target")
	check(main.eligibility.witness_age(pony) == ELIGIBILITY.Age.ADULT,
		"an adult mare witnesses as an adult")

	# The identity record is reused until its era moves. An in-place identity edit is not re-read;
	# a new identity resource, a relationship-meta change and a settings generation do rebuild it.
	var early_identity: FakeIdentity = pony.identity
	early_identity.filly = true
	check(main.eligibility.eligible(pony, ELIGIBILITY.Target.ACT),
		"the identity record is reused while its era holds")
	pony.identity = FakeIdentity.new()
	pony.identity.filly = true
	check(not main.eligibility.eligible(pony, ELIGIBILITY.Target.ACT),
		"a new identity resource rebuilds the record")
	pony.identity = FakeIdentity.new()
	check(main.eligibility.eligible(pony, ELIGIBILITY.Target.ACT), "the rebuilt record follows the new identity")
	pony.set_meta("relationship_id", "rarity_two")
	main.eligibility.eligible(pony, ELIGIBILITY.Target.ACT)
	var record: IDENTITY_RECORD.IdentityRecord = \
		(main.eligibility.get("_identity_records") as Dictionary).values()[0]
	check(str(record.id) == "rarity_two", "a relationship-meta change rebuilds the record's id")
	pony.set_meta("relationship_id", "rarity")
	check(main.eligibility.witness_age(pony) == ELIGIBILITY.Age.ADULT,
		"the rebuilt record keeps the witness age")
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

	var stallion := FakePony.new()
	var stallion_identity := FakeIdentity.new()
	stallion_identity.stallion = true
	stallion.identity = stallion_identity
	root.add_child(stallion)
	check(not main.eligibility.eligible(stallion, ELIGIBILITY.Target.ACT),
		"a stallion is not an act target")
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
	check(not main.eligibility.eligible(nameless, ELIGIBILITY.Target.ACT),
		"an adult identity with no stable id is not an act target")

	# Capability targets keep identity private: the act-side targets accept an adult mare,
	# the character target has no participation veto, and an opt-out stays editable.
	check(main.eligibility.eligible(pony, ELIGIBILITY.Target.ACT)
		and main.eligibility.eligible(pony, ELIGIBILITY.Target.ANATOMY),
		"the act and anatomy targets accept an adult mare")
	check(main.eligibility.eligible(pony, ELIGIBILITY.Target.CHARACTER),
		"the character target accepts an adult mare")
	SETTINGS.save_participation("rarity", ROWS.Rows.of({"acts": false}))
	check(not main.eligibility.eligible(pony, ELIGIBILITY.Target.ACT),
		"a participation opt-out closes the act target")
	check(main.eligibility.eligible(pony, ELIGIBILITY.Target.CHARACTER),
		"an opt-out keeps the character target editable")
	SETTINGS.reset_participation("rarity")

	# The resolved profile carries the stored consent and participation blocks; a deprecated
	# participation key is still accepted and returned.
	var consent: Dictionary = SETTINGS.consent("rarity").raw()
	var profile: ELIGIBILITY.Profile = main.eligibility.get_profile("rarity")
	check(profile.consent.public == bool(consent.get("public", false))
		and profile.consent.anal == bool(consent.get("anal", false))
		and profile.consent.oral == bool(consent.get("oral", false)),
		"the profile consent matches the resolver")
	check(profile.consent.to_dict().keys() == CONSENT.KEYS,
		"the consent snapshot covers the shared consent keys")
	check(profile.participation.to_dict().keys() == PARTICIPATION.all_keys(),
		"the participation snapshot covers the shared participation keys")
	for target: Variant in ELIGIBILITY._TARGET_KEYS:
		var key := str(ELIGIBILITY._TARGET_KEYS[target])
		check(key.is_empty() or key in PARTICIPATION.all_keys(),
			"every target veto is a participation key: %s" % key)

	# The provider layer lives in the registry: the identity half is written there and the
	# capability reads the resolved profile. The write also moves the record's era.
	var owner_id := main.get_instance_id()
	var identity := MARE_REGISTRY.Identity.new()
	identity.has_eligible = true
	identity.eligible = true
	identity.has_profile = true
	identity.profile = {"participation": {"anatomy": false}}
	var written: MARE_REGISTRY.Result = MARE_REGISTRY.set_profile(
		owner_id, "eligibility_test", "rarity", identity)
	check(written is MARE_REGISTRY.Result, "a profile write answers the typed registry result")
	check(written.ok, "the registry stores a provider identity layer")
	var read_back: ELIGIBILITY.Profile = main.eligibility.get_profile("rarity")
	check(read_back.eligible == ELIGIBILITY.EligibilityAssertion.ELIGIBLE,
		"the registry layer stores the eligible assertion")
	check(not read_back.participation.anatomy, "the registry layer stores the participation veto")
	check(not main.eligibility.eligible(pony, ELIGIBILITY.Target.ANATOMY),
		"the provider veto closes the anatomy target")
	check(main.eligibility.eligible(pony, ELIGIBILITY.Target.ACT),
		"the provider veto leaves the act target")
	check(main.eligibility.eligible(pony, ELIGIBILITY.Target.CHARACTER),
		"the provider veto leaves the character target")
	var refused := MARE_REGISTRY.set_profile(0, "eligibility_test", "rarity", identity)
	check(not refused.ok
		and refused.errors == ["owner: must be a valid Node inside the scene tree"],
		"the registry rejects a zero owner with its own validation string")
	check(main.eligibility.get_profile("rarity").eligible_value() == true,
		"the cross-mod shape is the tri-state eligible value")

	# The dynamic questions belong to the act gate, not here.
	for verb: String in ["get_verdict", "relationship_ok", "consent", "cycle_note"]:
		check(not main.eligibility.has_method(verb),
			"eligibility exposes no dynamic %s" % verb)

	# A provider eligible assertion opens the identity target a base-game filly flag closed.
	var filly := FakePony.new()
	filly.name = "Scootaloo"
	var filly_identity := FakeIdentity.new()
	filly_identity.id = "scootaloo"
	filly_identity.display_name = "Scootaloo"
	filly_identity.filly = true
	filly.identity = filly_identity
	filly.set_meta("relationship_id", "scootaloo")
	var filly_relation := FakeRelation.new()
	filly.set_meta("relationship_runtime", filly_relation)
	root.add_child(filly)
	check(not main.eligibility.eligible(filly, ELIGIBILITY.Target.ACT),
		"a filly is not an act target without an assertion")

	var filly_layer := MARE_REGISTRY.Identity.new()
	filly_layer.has_eligible = true
	filly_layer.eligible = true
	check(MARE_REGISTRY.set_profile(owner_id, "eligibility_test", "scootaloo", filly_layer).ok,
		"the registry writes the filly provider layer")
	check(main.eligibility.eligible(filly, ELIGIBILITY.Target.ACT),
		"the provider eligible assertion opens the identity target")

	# A provider not-eligible assertion overrides a base-game adult.
	identity.eligible = false
	check(MARE_REGISTRY.set_profile(owner_id, "eligibility_test", "rarity", identity).ok,
		"the registry rewrites the eligible assertion")
	check(not main.eligibility.eligible(pony, ELIGIBILITY.Target.ACT),
		"the provider not-eligible assertion closes the identity target")
	identity.eligible = true
	MARE_REGISTRY.set_profile(owner_id, "eligibility_test", "rarity", identity)

	# The attach warm builds the identity record once per era; a second warm is a no-op.
	var warm := ELIGIBILITY.new()
	warm.on_world(null)
	check((warm.get("_identity_records") as Dictionary).is_empty(),
		"a fresh service holds no identity record")
	var warm_pony := FakePony.new()
	warm_pony.name = "WarmPony"
	warm_pony.identity = FakeIdentity.new()
	warm_pony.set_meta("relationship_id", "rarity")
	root.add_child(warm_pony)
	warm.warm(warm_pony)
	var warm_record: IDENTITY_RECORD.IdentityRecord = \
		(warm.get("_identity_records") as Dictionary).values()[0]
	warm.warm(warm_pony)
	check((warm.get("_identity_records") as Dictionary).values()[0] == warm_record,
		"a second warm keeps the same record")
	warm_pony.set_meta("relationship_id", "rarity_two")
	warm.warm(warm_pony)
	var moved: IDENTITY_RECORD.IdentityRecord = \
		(warm.get("_identity_records") as Dictionary).values()[0]
	check(moved != warm_record and str(moved.id) == "rarity_two",
		"a moved era rebuilds the warmed record")
	warm.shutdown()

	main.eligibility.shutdown()
	check(not main.eligibility.eligible(pony, ELIGIBILITY.Target.ACT), "cleared service rejects every pony")
	main.eligibility.on_world(null)
	check(main.eligibility.eligible(pony, ELIGIBILITY.Target.ACT), "setup after clear restores the service")
	main.eligibility.free()
	warm.free()
	pony_relation.free()
	filly_relation.free()

	if failures == 0:
		print("ELIGIBILITY_API_PASS")
	finish()
