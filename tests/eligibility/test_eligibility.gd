extends "res://mods/unfplap/tests/support/suite.gd"
## Pure eligibility policy: adults, Promiscuity, willingness, history, cycle and per-mare
## consent. No world or user:// file is touched.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/eligibility/test_eligibility.gd

const FACTS := preload("res://mods/unfplap/eligibility/facts.gd")
const POLICY := preload("res://mods/unfplap/eligibility/policy.gd")
const IDENTITY_RECORD := preload("res://mods/unfplap/eligibility/identity_record.gd")



func facts(over: Dictionary = {}) -> Dictionary:
	var out := FACTS.empty()
	out["id"] = "rarity"
	out["has_identity"] = true
	out["is_player_pony"] = false
	out["is_filly"] = false
	out["is_stallion"] = false
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

	check(POLICY.adult_pony(facts()), "an identified adult pony")
	check(POLICY.adult_mare(facts()), "an adult mare")
	check(not POLICY.adult_mare(facts({"is_stallion": true})),
		"stallion is not an adult mare")
	check(not POLICY.adult_pony(facts({"is_filly": true})), "filly is not adult")
	check(not POLICY.adult_pony(facts({"is_player_pony": true})),
		"player pony is not a target")
	# The pure predicate takes values, so the live rule has exactly one definition.
	check(FACTS.adult_mare(true, false, false, false, null),
		"the pure predicate accepts an adult mare")
	check(not FACTS.adult_mare(true, false, false, true, null),
		"the pure predicate rejects a stallion")
	check(not FACTS.adult_pony(false, false, false, null),
		"the pure predicate needs an identity")

	# Capability targets: an adult mare plus the named participation veto. An empty key is the
	# identity-only character target, which must keep an opted-out mare editable.
	var mare := facts()
	check(POLICY.participates(mare, "acts"), "an adult mare is an act target")
	check(POLICY.participates(mare, "anatomy") and POLICY.participates(mare, "tail"),
		"an adult mare is an anatomy and tail target")
	check(POLICY.participates(mare, ""), "the character target has no participation veto")
	check(not POLICY.participates(facts({"participation": {"acts": false}}), "acts"),
		"the act target respects the participation veto")
	check(POLICY.participates(facts({"participation": {"acts": false}}), ""),
		"an opt-out keeps the character target")
	check(not POLICY.participates(facts({"is_stallion": true}), "acts"),
		"a stallion is no target")
	check(not POLICY.participates(facts({"has_identity": false}), "acts"),
		"no identity is no target")

	# The typed record answers the same predicate without a facts dictionary.
	var typed := IDENTITY_RECORD.IdentityRecord.new()
	typed.id = "rarity"
	typed.has_identity = true
	typed.participation = {"acts": true, "anatomy": true, "tail": true}
	check(POLICY.participates_identity(typed, "acts"), "the typed record is an act target")
	check(POLICY.participates_identity(typed, ""), "the typed record has a character target")
	typed.participation = {"acts": false}
	check(not POLICY.participates_identity(typed, "acts"),
		"the typed record respects the participation veto")
	check(POLICY.participates_identity(typed, ""), "an opt-out keeps the typed character target")
	typed.participation = {}
	typed.is_stallion = true
	check(not POLICY.participates_identity(typed, ""), "a stallion is no typed target")
	typed.is_stallion = false
	typed.has_eligible_assertion = true
	typed.eligible = false
	check(not POLICY.participates_identity(typed, ""), "a provider veto closes the typed record")
	check(not POLICY.participates_identity(null, ""), "no record is no target")

	# Witness age categories. A provider's `eligible` assertion wins over the identity flag.
	check(POLICY.age_kind(mare) == FACTS.AgeKind.ADULT,
		"an adult mare witnesses as an adult")
	check(POLICY.age_kind(facts({"is_filly": true})) == FACTS.AgeKind.YOUNG,
		"a filly witnesses as young")
	check(POLICY.age_kind(facts({"is_filly": true, "eligible": true})) == FACTS.AgeKind.ADULT,
		"a provider's eligible assertion makes a filly an adult witness")
	check(POLICY.age_kind(facts({"eligible": false})) == FACTS.AgeKind.NONE,
		"a vetoed adult is neither an adult nor a young witness")
	check(POLICY.age_kind(facts({"is_player_pony": true})) == FACTS.AgeKind.NONE,
		"the player pony is not a witness")

	var base := POLICY.evaluate(facts(), "start")
	check(bool(base.base), "steady adult mare has a base")
	check(bool(base.show), "all gates pass for a willing mare")
	check(bool(base.offer), "all gates allow an offer")
	check(bool(base.actions.anal) and bool(base.actions.oral), "action consent is read")
	check(not bool(base.actions.public), "public consent defaults off")

	var opt_out := POLICY.evaluate(facts({"participation": {"acts": false}}), "start")
	check(not bool(opt_out.show), "a participation opt-out hides the hint")
	check(not bool(opt_out.offer), "a participation opt-out does not offer")
	var adult_override := POLICY.evaluate(facts({"is_filly": true, "eligible": true}), "start")
	check(bool(adult_override.show), "a provider's eligible assertion overrides the filly flag")
	var adult_override_off := POLICY.evaluate(facts({"is_filly": false, "eligible": false}), "start")
	check(not bool(adult_override_off.show), "a provider's eligible assertion can block a base adult")

	var filly := POLICY.evaluate(facts({"is_filly": true}), "start")
	check(not bool(filly.show), "a filly is not a target")
	var stallion := POLICY.evaluate(facts({"is_stallion": true}), "start")
	check(not bool(stallion.show), "a stallion is not a target")
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

	if failures == 0:
		print("ELIGIBILITY_PASS")
	finish()
