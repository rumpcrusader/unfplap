extends "res://mods/unfplap/tests/support/suite.gd"
## The dynamic act gate: the pure truth table, the act-key readiness row, the typed verdict, the
## consent keys, the cycle note and the attach warm. No world file is touched; SETTINGS uses a
## throwaway XDG data dir in the test runner.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/act_gate/test_act_gate.gd

const WORLD := preload("res://mods/unfplap/world/service.gd")
const ACT_GATE := preload("res://mods/unfplap/act_gate/service.gd")
const FACTS := preload("res://mods/unfplap/act_gate/facts.gd")
const POLICY := preload("res://mods/unfplap/act_gate/policy.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const ROWS := preload("res://mods/unfplap/settings/rows.gd")


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
	var romance_calls := 0

	func eligible_for_romance(_id: String) -> bool:
		romance_calls += 1
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


## A bond store that predates the reader methods: every accessor must answer its typed zero.
class FakeBareBonds extends RefCounted:
	pass


class FakeBareRelation extends Node:
	var bonds: FakeBareBonds = FakeBareBonds.new()

	func ladder(_id: String) -> Dictionary:
		return {"love": {"level": 2}, "friendship": {"level": 3}}


class FakePony extends Node3D:
	var identity: Variant


class FakeContext extends Node:
	var state := {}


class FakeGame extends Node:
	var mares: Array = []
	var world_context: Node


class FakeMain extends Node:
	var game: Node
	var player: Node


func facts(over: Dictionary = {}) -> Dictionary:
	var out := FACTS.empty()
	out["id"] = "rarity"
	out["adult"] = true
	out["has_relationship"] = true
	out["registered_adult"] = true
	out["romance_eligible"] = true
	out["stage"] = "dating"
	out["love_level"] = 2
	out["willing"] = true
	out["promiscuity"] = "any"
	out["player_young"] = false
	out["player_pony"] = false
	out["cycle_phase"] = "normal"
	out["cycle_allows"] = true
	out["heat"] = false
	out["history"] = {
		"tier": "steady", "hurt": 0, "comfort": 0,
		"blocks_start": false, "blocks_offers": false, "offer_weight": 0.7,
	}
	out["consent"] = {"public": false, "anal": true, "oral": true}
	for key: Variant in over.keys():
		var name := str(key)
		if out[name] is Dictionary and over[key] is Dictionary:
			var merged: Dictionary = (out[name] as Dictionary).duplicate(true)
			for sub: Variant in (over[key] as Dictionary).keys():
				merged[str(sub)] = (over[key] as Dictionary)[sub]
			out[name] = merged
		else:
			out[name] = over[key]
	return out


func run() -> void:
	_check_table()
	_check_facade()
	if failures == 0:
		print("ACT_GATE_PASS")
	finish()


## The pure truth table: the Promiscuity floor and the row effects.
func _check_table() -> void:
	check(POLICY.level_ok("soulmates", 4), "Soulmates accepts level 4")
	check(not POLICY.level_ok("soulmates", 3), "Soulmates rejects level 3")
	check(POLICY.level_ok("head_over_hooves", 3), "Head Over Hooves accepts level 3")
	check(not POLICY.level_ok("head_over_hooves", 2), "Head Over Hooves rejects level 2")
	check(POLICY.level_ok("marefriend", 2), "Marefriend accepts level 2")
	check(not POLICY.level_ok("marefriend", 1), "Marefriend rejects level 1")
	check(POLICY.level_ok("new_couple", 1), "New Couple accepts level 1")
	check(not POLICY.level_ok("new_couple", 0), "New Couple rejects level 0")
	check(POLICY.level_ok("crush", 0), "Crush accepts level 0")
	check(not POLICY.level_ok("crush", -1), "Crush rejects no crush")
	check(POLICY.level_ok("any", -1), "Any Adult skips the love level")
	check(POLICY.level_ok("", 2), "unknown Promiscuity falls back to Marefriend")
	check(not POLICY.level_ok("", 1), "fallback still has a floor")

	var base := POLICY.evaluate(facts(), "start")
	check(bool(base.base), "steady adult mare has a base")
	check(bool(base.show), "all gates pass for a willing mare")
	check(bool(base.offer), "all gates allow an offer")
	check(bool(base.actions.anal) and bool(base.actions.oral), "action consent is read")
	check(not bool(base.actions.public), "public consent defaults off")

	var opt_out := POLICY.evaluate(facts({"participation": {"acts": false}}), "start")
	check(not bool(opt_out.show), "a participation opt-out hides the hint")
	check(not bool(opt_out.offer), "a participation opt-out does not offer")
	var not_adult := POLICY.evaluate(facts({"adult": false}), "start")
	check(not bool(not_adult.show), "the identity answer gates the base")

	var young_player := POLICY.evaluate(facts({"player_young": true}), "start")
	check(not bool(young_player.show), "a young player is not a target")
	var no_relationship := POLICY.evaluate(facts({"has_relationship": false}), "start")
	check(not bool(no_relationship.show), "no relationship runtime blocks")
	var unregistered := POLICY.evaluate(facts({"registered_adult": false}), "start")
	check(not bool(unregistered.show), "an unregistered adult blocks")

	var low_level := POLICY.evaluate(facts({"promiscuity": "marefriend", "love_level": 1}), "start")
	check(not bool(low_level.show), "Promiscuity still blocks the hint")
	check(not bool(low_level.actions.public), "Promiscuity is not consent")
	var no_romance := POLICY.evaluate(facts({"romance_eligible": false}), "start")
	check(not bool(no_romance.show), "romance eligibility blocks")

	var unwilling := POLICY.evaluate(facts({"willing": false}), "start")
	check(not bool(unwilling.show), "an unwilling mare has no legacy hint")
	check(not bool(unwilling.offer), "an unwilling mare never offers")

	var withdrawn := POLICY.evaluate(facts({"history": {"blocks_start": true}}), "start")
	check(bool(withdrawn.show), "a withdrawn mare still shows the hint")
	check(not bool(withdrawn.offer), "a withdrawn mare does not offer")
	var hurt := POLICY.evaluate(facts({"history": {"blocks_offers": true}}), "offer")
	check(bool(hurt.show), "a hurt mare still starts")
	check(not bool(hurt.offer), "a hurt mare does not offer")
	check(float(hurt.offer_weight) == 0.0, "a hurt mare has no offer weight")

	var cold := POLICY.evaluate(facts({"cycle_allows": false, "cycle_phase": "diestrus"}), "start")
	check(not bool(cold.show), "diestrus hides the hint")
	check(not bool(cold.offer), "diestrus blocks offers")

	var public_consent := POLICY.evaluate(facts({"consent": {"public": true}}), "offer")
	check(bool(public_consent.actions.public), "public consent is read as a soft preference")
	var anal_off := POLICY.evaluate(facts({"consent": {"anal": false}}), "start")
	check(not bool(anal_off.actions.anal), "anal consent is independent of start eligibility")

	var rows: Array = POLICY.evaluate(facts({"willing": false}), "start").rows
	var relation_row: Dictionary = {}
	for row: Variant in rows:
		if row is Dictionary and str((row as Dictionary).get("key", "")) == "relation":
			relation_row = row
	check(str(relation_row.get("effect", "")) == "refuse", "relation row uses the refusal effect")
	check(not bool(relation_row.get("ok", true)), "relation row fails when unwilling")


## The facade against a fake world: the identity answer is the real eligibility service.
func _check_facade() -> void:
	var main := FakeMain.new()
	main.name = "FakeMain"
	main.game = FakeGame.new()
	WORLD.bind_world(main.game)
	main.game.world_context = FakeContext.new()
	main.player = Node3D.new()
	WORLD.bind_player(main.player)
	root.add_child(main)
	root.add_child(main.game)
	root.add_child(main.game.world_context)
	root.add_child(main.player)

	var eligibility := ELIGIBILITY.new()
	eligibility.on_world(null)
	var gate := ACT_GATE.new()
	gate.on_world(null)
	gate.bind_eligibility(eligibility)

	var pony := FakePony.new()
	pony.name = "Rarity"
	pony.identity = FakeIdentity.new()
	pony.set_meta("relationship_id", "rarity")
	var relation := FakeRelation.new()
	relation.bonds = FakeBonds.new()
	pony.set_meta("relationship_runtime", relation)
	root.add_child(pony)

	check(gate.ready(pony), "the identity act target and clearance row pass")
	var verdict: ACT_GATE.Verdict = gate.get_verdict(pony, ACT_GATE.Mode.START)
	check(str(verdict.facts.id) == "rarity", "facts take the relationship id")
	check(bool(verdict.facts.adult), "the identity answer reaches the facts")
	check(bool(verdict.facts.participation.acts), "the resolved participation reaches the facts")
	check(not bool(verdict.facts.player_young), "the human form is adult")
	check(bool(verdict.facts.has_relationship) and bool(verdict.facts.registered_adult),
		"facts read the relationship runtime")
	check(bool(verdict.facts.willing), "facts read kiss willingness")
	check(str(verdict.facts.stage) == "dating" and int(verdict.facts.love_level) == 2,
		"facts read the ladder and stage")
	check(bool(verdict.facts.consent.anal), "facts read the resolved consent")
	check(bool(verdict.show), "a willing mare starts")
	check(bool(verdict.offer), "offers pass")
	check(verdict.rows_text().contains("adult"), "the typed rows are readable")
	check(verdict.reasons().is_empty(), "a passing verdict has no reasons")
	var keys: Array[String] = []
	for row: ACT_GATE.Row in verdict.rows:
		keys.append(row.key)
	check(keys == ["adult", "relationship", "form", "romance", "promiscuity", "participation",
		"relation", "cycle", "history", "history_offers", "public"],
		"the verdict keeps the policy rows and their order")

	SETTINGS.save_participation("rarity", ROWS.Rows.of({"acts": false}))
	check(not gate.ready(pony), "a participation opt-out closes the act key")
	var opted_out: ACT_GATE.Verdict = gate.get_verdict(pony, ACT_GATE.Mode.START)
	check(not bool(opted_out.facts.participation.acts), "the opt-out reaches the facts")
	check(not bool(opted_out.show), "the opt-out hides the hint")
	SETTINGS.reset_participation("rarity")

	# Base clearance reads only the relationship facts it uses; willingness, history and cycle
	# stay on the full verdict.
	relation.bonds.welcomes_calls = 0
	check(gate.relationship_ok(pony), "the clearance relationship row passes")
	check(relation.bonds.welcomes_calls == 0, "clearance does not read kiss willingness")
	relation.bonds.welcome = false
	check(gate.relationship_ok(pony), "clearance ignores willingness")
	var saved_promiscuity := SETTINGS.promiscuity.get_choice()
	SETTINGS.promiscuity.set_choice("any")
	relation.bonds.romance = false
	check(not gate.relationship_ok(pony), "romance eligibility gates clearance")
	relation.bonds.romance = true
	check(gate.relationship_ok(pony), "Any Adult passes the floor")
	SETTINGS.promiscuity.set_choice("head_over_hooves")
	check(not gate.relationship_ok(pony), "the love floor gates clearance")
	pony.remove_meta("relationship_runtime")
	check(not gate.relationship_ok(pony), "no relationship runtime fails clearance")
	pony.set_meta("relationship_runtime", relation)
	# The love level comes from the game's own ladder cache, and `ladder()` is the fallback for a
	# pony the game has not recorded yet. The fake ladder says New Couple (2); the cache says
	# No crush yet (0), so a floor that the cached level fails and the ladder level passes proves
	# which read answered.
	main.game.world_context.state["bond_levels"] = {"rarity": {"friendship": 3, "love": 0}}
	SETTINGS.promiscuity.set_choice("new_couple")
	check(not gate.relationship_ok(pony),
		"the clearance floor reads the game's cached love level")
	check(int(gate.get_verdict(pony, ACT_GATE.Mode.START).facts.love_level) == 0,
		"the facts snapshot reads the cached love level too")
	main.game.world_context.state["bond_levels"] = {}
	check(gate.relationship_ok(pony),
		"an unrecorded pony falls back to the relationship ladder")
	check(int(gate.get_verdict(pony, ACT_GATE.Mode.START).facts.love_level) == 2,
		"the fallback fills the facts snapshot")

	# A bond store without the reader ops answers each accessor's typed zero, and the ladder
	# fallback still supplies the level.
	var bare_relation := FakeBareRelation.new()
	var bare_pony := FakePony.new()
	bare_pony.name = "BareBonds"
	bare_pony.identity = FakeIdentity.new()
	bare_pony.set_meta("relationship_id", "rarity")
	bare_pony.set_meta("relationship_runtime", bare_relation)
	root.add_child(bare_pony)
	var bare: ACT_GATE.Verdict = gate.get_verdict(bare_pony, ACT_GATE.Mode.START)
	check(not bool(bare.facts.romance_eligible) and not bool(bare.facts.willing)
		and str(bare.facts.stage).is_empty(),
		"absent bond readers answer the typed zero")
	check(int(bare.facts.love_level) == 2, "the ladder fallback survives absent bond readers")
	check(not gate.relationship_ok(bare_pony),
		"absent bond readers fail the clearance romance row")
	SETTINGS.estrus_cycle.set_bool(true)
	check(ACT_GATE.cycle_phase_for(bare_pony) == CYCLE.NORMAL,
		"an absent bond clock answers the normal cycle phase")
	SETTINGS.estrus_cycle.set_bool(false)
	SETTINGS.promiscuity.set_choice(saved_promiscuity)
	relation.bonds.welcome = false
	var unwilling: ACT_GATE.Verdict = gate.get_verdict(pony, ACT_GATE.Mode.START)
	check(not bool(unwilling.show), "an unwilling mare has no legacy hint")
	relation.bonds.welcome = true

	# Consent reads one resolved key: the shared table decides the keys, the settings resolve
	# the values.
	check(gate.consent(pony, "anal") == SETTINGS.consent("rarity").bool_value("anal", false),
		"consent reads the resolved anal key")
	check(gate.consent(pony, "public") == SETTINGS.consent("rarity").bool_value("public", false),
		"consent reads the resolved public key")
	check(not gate.consent(pony, "unknown"), "an unknown consent key reads false")
	var nameless := FakePony.new()
	nameless.name = "Nameless"
	nameless.identity = FakeIdentity.new()
	nameless.identity.id = ""
	root.add_child(nameless)
	check(not gate.consent(nameless, "anal"), "no stable id reads no consent")

	# The cycle note appends the heat sentence only while the base holds.
	CYCLE.set_override("rarity", CYCLE.HEAT)
	check(not gate.cycle_note(pony).is_empty(), "heat has a note while the gate is open")
	CYCLE.set_override("rarity", "")
	check(gate.cycle_note(pony).is_empty(), "a normal cycle has no note")

	# The attach warm reads the relationship row once and skips a pony with no runtime.
	var warm := ACT_GATE.new()
	warm.on_world(null)
	warm.bind_eligibility(eligibility)
	var warm_pony := FakePony.new()
	warm_pony.name = "WarmPony"
	warm_pony.identity = FakeIdentity.new()
	warm_pony.set_meta("relationship_id", "rarity")
	var warm_relation := FakeRelation.new()
	warm_relation.bonds = FakeBonds.new()
	warm_pony.set_meta("relationship_runtime", warm_relation)
	root.add_child(warm_pony)
	warm.warm(warm_pony)
	check(warm_relation.bonds.romance_calls == 1, "the warm reads the relationship row once")
	warm.warm(warm_pony)
	check(warm_relation.bonds.romance_calls == 1, "a second warm is a no-op")
	var warm_bare := FakePony.new()
	warm_bare.name = "WarmBare"
	warm_bare.identity = FakeIdentity.new()
	root.add_child(warm_bare)
	warm.warm(warm_bare)
	check(not (warm.get("_warmed") as Dictionary).has(int(warm_bare.get_instance_id())),
		"a pony without a relationship runtime warms nothing")

	# Fail closed: an unbound identity or a cleared service opens no gate.
	var unbound := ACT_GATE.new()
	unbound.on_world(null)
	check(not unbound.ready(pony), "an unbound gate is never ready")
	check(not bool(unbound.get_verdict(pony).show), "an unbound gate has no base")
	warm.shutdown()
	check(not warm.ready(pony) and not warm.relationship_ok(pony),
		"a shut-down gate answers no")
	gate.shutdown()
	eligibility.shutdown()
	root.remove_child(pony)
	pony.free()
	root.remove_child(main.player)
	main.player.free()
	root.remove_child(main.game.world_context)
	main.game.world_context.free()
	root.remove_child(main.game)
	main.game.free()
	root.remove_child(main)
	main.free()
	WORLD.unbind()
