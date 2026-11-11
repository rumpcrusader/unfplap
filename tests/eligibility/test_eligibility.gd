extends SceneTree
## Pure eligibility policy: adults, Promiscuity, willingness, lover bond, history, cycle and
## per-mare consent. No world or user:// file is touched.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/eligibility/test_eligibility.gd

const FACTS := preload("res://mods/unfplap/eligibility/facts.gd")
const POLICY := preload("res://mods/unfplap/eligibility/policy.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


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
	out["stored_bond"] = true
	out["bond_stage"] = "dating"
	out["promiscuity"] = "any"
	out["sex_start"] = "try_luck"
	out["public_feature"] = true
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
	check(POLICY.bypasses_bond("try_luck"), "Try Your Luck bypasses the bond")
	check(not POLICY.bypasses_bond("when_available"), "When Available requires the bond")
	check(not POLICY.bypasses_bond(""), "unknown Starting Sex is not a bypass")

	var identity: Variant = {"id": "rarity", "filly": false, "stallion": false}
	check(FACTS.adult_pony_identity(identity), "adult identity")
	check(FACTS.adult_mare_identity(identity), "adult mare identity")
	check(not FACTS.adult_mare_identity({"id": "x", "filly": false, "stallion": true}),
		"stallion is not an adult mare")
	check(not FACTS.adult_pony_identity({"id": "x", "filly": true}), "filly is not adult")
	check(not FACTS.adult_pony_identity(identity, true), "player pony is not a target")

	var base := POLICY.evaluate(facts(), "start")
	check(bool(base.base), "steady adult mare has a base")
	check(bool(base.show) and bool(base.attempt), "all gates pass in Try Your Luck")
	check(bool(base.offer), "all gates allow an offer")
	check(bool(base.bond), "a willing adult passes the bond mode")
	check(not bool(base.stop), "all gates keep an act going")
	check(bool(base.actions.anal) and bool(base.actions.oral), "action consent is read")
	check(not bool(base.actions.public), "public consent defaults off")
	check(not bool(base.actions.public_offer), "public consent needs the feature or heat")

	var filly := POLICY.evaluate(facts({"is_filly": true}), "start")
	check(not bool(filly.show) and not bool(filly.buck_refuse), "a filly is not a target")
	var stallion := POLICY.evaluate(facts({"is_stallion": true}), "start")
	check(not bool(stallion.show) and not bool(stallion.buck_refuse), "a stallion is not a target")
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

	var no_bond := POLICY.evaluate(facts({"stored_bond": false, "sex_start": "when_available"}), "start")
	check(not bool(no_bond.show), "When Available needs the stored bond")
	check(not bool(no_bond.offer), "When Available needs the stored bond for offers")
	check(bool(no_bond.bond), "the bond mode does not need a stored bond")
	check(bool(no_bond.stop), "a missing bond stops a mid-act check")
	var no_bond_luck := POLICY.evaluate(facts({"stored_bond": false}), "start")
	check(bool(no_bond_luck.show) and bool(no_bond_luck.attempt), "Try Your Luck skips the bond")
	check(bool(no_bond_luck.offer), "Try Your Luck allows offers")
	check(not bool(no_bond_luck.stop), "Try Your Luck keeps a mid-act check going")

	var unwilling_luck := POLICY.evaluate(facts({"willing": false}), "start")
	check(bool(unwilling_luck.show), "Try Your Luck still shows the hint when unwilling")
	check(not bool(unwilling_luck.attempt), "an unwilling mare does not start")
	check(bool(unwilling_luck.buck_refuse), "an unwilling mare can refuse")
	check(not bool(unwilling_luck.offer), "an unwilling mare never offers")
	check(bool(unwilling_luck.stop), "an unwilling mare stops a mid-act check")
	var unwilling_available := POLICY.evaluate(
		facts({"willing": false, "sex_start": "when_available"}), "start")
	check(not bool(unwilling_available.show), "When Available hides the hint when unwilling")
	check(bool(unwilling_available.buck_refuse), "a refusal is still possible")

	var withdrawn := POLICY.evaluate(facts({"history": {"blocks_start": true}}), "start")
	check(bool(withdrawn.show), "a withdrawn mare still shows the hint")
	check(not bool(withdrawn.attempt), "a withdrawn mare does not start")
	check(bool(withdrawn.history_refuse), "a withdrawn mare speaks the refusal")
	check(not bool(withdrawn.offer), "a withdrawn mare does not offer")
	check(not bool(withdrawn.stop), "history does not stop an act")
	var hurt := POLICY.evaluate(facts({"history": {"blocks_offers": true}}), "offer")
	check(bool(hurt.show) and bool(hurt.attempt), "a hurt mare still starts")
	check(not bool(hurt.offer), "a hurt mare does not offer")
	check(float(hurt.offer_weight) == 0.0, "a hurt mare has no offer weight")
	var both_refusals := POLICY.evaluate(
		facts({"willing": false, "history": {"blocks_start": true}}), "start")
	check(bool(both_refusals.history_refuse) and bool(both_refusals.buck_refuse),
		"a withdrawn and unwilling mare keeps both refusal routes; history is checked first")

	var cold := POLICY.evaluate(facts({"cycle_allows": false, "cycle_phase": "diestrus"}), "start")
	check(not bool(cold.show), "diestrus hides the hint")
	check(not bool(cold.offer), "diestrus blocks offers")
	check(bool(cold.bond), "diestrus does not block a lover-bond dialogue grant")
	check(bool(cold.stop), "diestrus stops a mid-act check")

	var public_consent := POLICY.evaluate(facts({"consent": {"public": true}}), "offer")
	check(bool(public_consent.actions.public), "public consent is read")
	check(bool(public_consent.actions.public_offer), "public consent is an offer override")
	var public_off := POLICY.evaluate(
		facts({"consent": {"public": true}, "public_feature": false}), "offer")
	check(not bool(public_off.actions.public_offer), "the feature switch still gates public offers")
	var heat := POLICY.evaluate(facts({"heat": true, "consent": {"public": false}}), "offer")
	check(bool(heat.actions.public_offer), "heat overrides privacy")
	var anal_off := POLICY.evaluate(facts({"consent": {"anal": false}}), "start")
	check(not bool(anal_off.actions.anal), "anal consent is independent of start eligibility")

	var rows: Array = POLICY.evaluate(facts({"willing": false}), "start").rows
	var relation_row: Dictionary = {}
	for row: Variant in rows:
		if row is Dictionary and str((row as Dictionary).get("key", "")) == "relation":
			relation_row = row
	check(str(relation_row.get("effect", "")) == "refuse", "relation row uses the refusal effect")
	check(not bool(relation_row.get("ok", true)), "relation row fails when unwilling")

	print("ELIGIBILITY_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ELIGIBILITY_PASS")
	quit(0 if failures == 0 else 1)
