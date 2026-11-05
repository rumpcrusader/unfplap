extends SceneTree
## Pure long-term act history: hurt/comfort, tiers, offer weight and cooldown, repair and decay.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/test_act_history.gd

const HISTORY := preload("res://mods/unfplap/act_history.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func outcome(grade: String, severe := false, text := "The act happened.") -> Dictionary:
	return {
		"grade": grade,
		"quality": 0.90 if grade == "good" else (0.10 if grade == "bad" else 0.50),
		"severe": severe,
		"reasons": ["test"],
		"text": text,
		"wants": "be gentle",
		"romance": 2 if grade == "good" else (-1 if grade == "bad" else 1),
		"mood": "happy" if grade == "good" else ("sad" if grade == "bad" else "relaxed"),
	}


func run() -> void:
	var rules: Dictionary = HISTORY.rules()
	var reminder := int(rules.get("reminder_hurt", 2))
	var block := int(rules.get("offer_block_hurt", 4))
	var withdraw := int(rules.get("withdraw_hurt", 6))
	var bad_hurt := int(rules.get("bad_hurt", 1))
	var severe_hurt := int(rules.get("severe_hurt", 2))
	var good_comfort := int(rules.get("good_comfort", 1))
	var great_comfort := int(rules.get("great_comfort", 2))
	var good_repair := int(rules.get("good_repair", 1))

	var section: Dictionary = {}
	var fresh: Dictionary = HISTORY.row(section, "rarity")
	check(int(fresh.get("acts", -1)) == 0, "a new mare starts with no acts")
	check(HISTORY.tier_index(fresh) == 0, "a new mare is steady")
	check(HISTORY.offer_weight(fresh) > 0.0, "a steady mare may offer")
	check(not HISTORY.blocks_offers(fresh), "a steady mare is not blocked from offering")
	check(not HISTORY.blocks_start(fresh), "a steady mare is not refused")

	var first: Dictionary = HISTORY.commit(section, "rarity", outcome("good"), 10.0)
	var row: Dictionary = first.get("row", {})
	check(int(row.get("comfort", 0)) == good_comfort, "a good act adds comfort")
	check(int(row.get("hurt", 0)) == 0, "a good act does not add hurt")
	check(int(row.get("good", 0)) == 1, "good acts are counted")
	check(str(row.get("last_text", "")).contains("act happened"), "the last text is stored")
	check(str(row.get("last_wants", "")) == "be gentle", "the last want is stored")
	check((row.get("recent", []) as Array).size() == 1, "the recent list grows")

	var great_row: Dictionary = HISTORY.commit(section, "rarity",
		{"grade": "great", "quality": 0.98, "severe": false, "reasons": [], "text": "Great.",
		"wants": "keep going", "romance": 2, "mood": "happy"}, 10.0).get("row", {})
	check(int(great_row.get("comfort", 0)) == good_comfort + great_comfort,
		"a great act adds more comfort")

	# A bad act costs comfort and adds hurt. Repeat until the tiers.
	var bad: Dictionary = outcome("bad")
	var res: Dictionary = HISTORY.commit(section, "rarity", bad, 10.0)
	row = res.get("row", {})
	check(int(row.get("hurt", 0)) == bad_hurt, "one bad act adds hurt")
	check(int(row.get("comfort", 0)) < int(great_row.get("comfort", 0)),
		"a bad act costs comfort")
	check(int(row.get("bad", 0)) == 1, "bad acts are counted")
	check(HISTORY.tier_index(row) == 0, "one bad act is still steady")

	var tries := 1
	while int(row.get("hurt", 0)) < reminder and tries < 20:
		row = HISTORY.commit(section, "rarity", bad, 10.0).get("row", {})
		tries += 1
	check(HISTORY.tier_index(row) == 1, "hurt reaches the uneasy tier")
	check(HISTORY.blocks_offers(row) == false, "an uneasy mare still offers")
	check(bool(row.get("reminder_pending", false)), "an uneasy tier arms a reminder")

	while int(row.get("hurt", 0)) < block and tries < 20:
		row = HISTORY.commit(section, "rarity", bad, 10.0).get("row", {})
		tries += 1
	check(HISTORY.tier_index(row) == 2, "hurt reaches the hurt tier")
	check(HISTORY.blocks_offers(row), "a hurt mare stops offering")
	check(not HISTORY.blocks_start(row), "a hurt mare still accepts a player's attempt")
	check(bool(row.get("complaint_pending", false)), "the hurt tier arms a complaint")
	check(HISTORY.offer_weight(row) == 0.0, "a hurt mare has no offer weight")

	while int(row.get("hurt", 0)) < withdraw and tries < 30:
		row = HISTORY.commit(section, "rarity", bad, 10.0).get("row", {})
		tries += 1
	check(HISTORY.tier_index(row) == 3, "hurt reaches the withdrawn tier")
	check(HISTORY.blocks_start(row), "a withdrawn mare refuses an act")
	check(str(HISTORY.tier_name(row)) == "withdrawn", "the tier is named")

	# A good act repairs one point; enough of them move her back below the gate.
	var before_repair := int(row.get("hurt", 0))
	row = HISTORY.commit(section, "rarity", outcome("good"), 10.0).get("row", {})
	check(int(row.get("hurt", 0)) == maxi(0, before_repair - good_repair),
		"a good act repairs hurt")
	var guard := 0
	while HISTORY.blocks_start(row) and guard < 20:
		row = HISTORY.commit(section, "rarity", outcome("good"), 10.0).get("row", {})
		guard += 1
	check(not HISTORY.blocks_start(row), "good acts eventually lift the refusal")
	check(HISTORY.blocks_offers(row) == (int(row.get("hurt", 0)) >= block),
		"offers follow the hurt threshold")

	# Severe bad handling adds more than a regular bad act.
	var severe_section: Dictionary = {}
	var severe_row: Dictionary = HISTORY.commit(severe_section, "rarity",
		outcome("bad", true), 10.0).get("row", {})
	check(int(severe_row.get("hurt", 0)) == severe_hurt, "a severe bad act adds extra hurt")

	var early_section: Dictionary = {}
	var early_row: Dictionary = HISTORY.commit(early_section, "rarity", {
		"grade": "neutral", "quality": 0.55, "severe": false, "early": true,
		"reasons": ["ended_early"], "text": "You were left wanting.",
		"wants": "let me finish", "romance": 0, "mood": "relaxed",
	}, 10.0).get("row", {})
	check(int(early_row.get("hurt", 0)) == 1, "a clean early end is a one-point hurt")
	check(int(early_row.get("neutral", 0)) == 1, "the early end is still neutral")

	# Time decay is in in-game days and works on a copy.
	var decay_section: Dictionary = {}
	HISTORY.commit(decay_section, "rarity", bad, 10.0)
	HISTORY.commit(decay_section, "rarity", bad, 10.0)
	HISTORY.commit(decay_section, "rarity", bad, 10.0)
	HISTORY.commit(decay_section, "rarity", bad, 10.0)
	var before_decay: Dictionary = HISTORY.row(decay_section, "rarity")
	var decay_days := float(rules.get("decay_days", 2.0))
	var decay_amount := int(rules.get("decay_amount", 1))
	var later := HISTORY.effective_row(decay_section, "rarity", 10.0 + decay_days)
	check(int(later.get("hurt", 0)) == maxi(0, int(before_decay.get("hurt", 0)) - decay_amount),
		"hurt decays after the in-game decay period")
	var same_day := HISTORY.effective_row(decay_section, "rarity", 10.0)
	check(int(same_day.get("hurt", 0)) == int(before_decay.get("hurt", 0)),
		"no decay inside the same day")

	# Apology repairs once per in-game day.
	var apology_section: Dictionary = {}
	HISTORY.commit(apology_section, "rarity", bad, 20.0)
	HISTORY.commit(apology_section, "rarity", bad, 20.0)
	HISTORY.commit(apology_section, "rarity", bad, 20.0)
	var apology_before: Dictionary = HISTORY.row(apology_section, "rarity")
	check(HISTORY.apology_repair(apology_section, "rarity", 20.0), "an apology repairs hurt")
	check(not HISTORY.apology_repair(apology_section, "rarity", 20.0),
		"a second apology on the same day does nothing")
	var apology_row: Dictionary = HISTORY.row(apology_section, "rarity")
	check(int(apology_row.get("hurt", 0)) == maxi(0, int(apology_before.get("hurt", 0))
		- int(rules.get("apology_repair", 1))), "the apology removes one point")

	# Offer weight and cooldown react to comfort and hurt.
	var steady_section: Dictionary = {}
	var steady: Dictionary = HISTORY.commit(steady_section, "rarity",
		outcome("good"), 30.0).get("row", {})
	var base_weight := HISTORY.offer_weight(HISTORY.row({}, "rarity"))
	check(HISTORY.offer_weight(steady) > base_weight, "comfort raises offer weight")
	var hurt_row: Dictionary = steady.duplicate(true)
	hurt_row["hurt"] = reminder
	check(HISTORY.offer_weight(hurt_row) < HISTORY.offer_weight(steady),
		"hurt lowers offer weight")
	var base_cooldown := float(rules.get("offer_base_s", 600.0))
	var min_cooldown := float(rules.get("offer_min_s", 300.0))
	var cooldown_steady := HISTORY.offer_cooldown(steady)
	check(cooldown_steady <= base_cooldown and cooldown_steady >= min_cooldown,
		"comfort shortens the offer cooldown within its floor")

	# A malformed row is repaired instead of crashing a save load.
	var dirty: Dictionary = {
		"acts": "many", "hurt": 99, "comfort": -4, "recent": [
			{"grade": 5, "quality": "bad", "reasons": "no", "text": "x".repeat(400)},
		],
	}
	var clean: Dictionary = HISTORY.sanitize(dirty)
	check(int(clean.get("hurt", -1)) <= int(rules.get("max_hurt", 8)), "hurt is capped")
	check(int(clean.get("comfort", -1)) == 0, "comfort is clamped")
	check((clean.get("recent", []) as Array).size() == 1, "recent rows survive sanitising")
	check(str((clean.get("recent", [])[0] as Dictionary).get("text", "")).length() <= 180,
		"recent text is shortened")

	# Pending lines are consumed once.
	var line_row: Dictionary = HISTORY.row(apology_section, "rarity")
	check(str(HISTORY.pending_line(HISTORY.sanitize({}))).is_empty(),
		"a steady row has no pending line")
	var pending := line_row.duplicate(true)
	pending["complaint_pending"] = true
	pending["reminder_pending"] = true
	check(str(HISTORY.pending_line(pending)) == "complaint", "a complaint wins over a reminder")
	HISTORY.mark_announced(apology_section, "rarity", "complaint")
	check(str(HISTORY.pending_line(HISTORY.row(apology_section, "rarity"))) == "",
		"a complaint clears both pending lines")

	var text := HISTORY.prompt_note(pending)
	check(not text.is_empty(), "a hurt mare has a prompt note")
	check(not text.contains("0."), "the prompt note carries no raw score")
	check(str(HISTORY.ask_note(HISTORY.sanitize({}))).is_empty(),
		"a steady mare has no ask note")

	var reset_section: Dictionary = {}
	HISTORY.commit(reset_section, "rarity", outcome("good"), 10.0)
	check(HISTORY.reset(reset_section, "rarity"), "reset removes a row")
	check(int(HISTORY.row(reset_section, "rarity").get("acts", -1)) == 0,
		"reset leaves a clean row")

	print("ACT_HISTORY_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACT_HISTORY_PASS")
	quit(0 if failures == 0 else 1)
