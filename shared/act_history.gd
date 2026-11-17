extends RefCounted
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
## Durable per-mare act history. Pure policy plus one `Mods.state("unfplap").act_history`
## dictionary; no scene access. A good act builds comfort and repairs hurt, a bad act adds hurt
## and costs comfort, and the middle of the range changes nothing. Time and apologies repair hurt.
##
## There is deliberately no break-up path. The highest tier is a spoken refusal, not a change to
## the base relationship stage.


const MOD_ID := "unfplap"
const KEY := "act_history"
const VERSION := 1
const MAX_RECENT := 6
const MAX_TEXT := 180
const MAX_WANTS := 120

## Bumped by every stored-row write, so a read-only policy snapshot can tell when its history
## facts are stale. Reads and decay never bump it.
static var revision := 0

## The live setting behind each rule key, declared once so `rules()` needs no path strings.
static var _RULES := {
	"apology_repair": SETTINGS.apology_repair,
	"bad_hurt": SETTINGS.bad_hurt,
	"decay_amount": SETTINGS.decay_amount,
	"decay_days": SETTINGS.decay_days,
	"good_comfort": SETTINGS.good_comfort,
	"good_repair": SETTINGS.good_repair,
	"great_comfort": SETTINGS.great_comfort,
	"great_repair": SETTINGS.great_repair,
	"max_comfort": SETTINGS.max_comfort,
	"max_hurt": SETTINGS.max_hurt,
	"mild_hurt": SETTINGS.mild_hurt,
	"normal_cooldown_s": SETTINGS.normal_cooldown_s,
	"offer_base_s": SETTINGS.offer_base_s,
	"offer_block_hurt": SETTINGS.offer_block_hurt,
	"offer_comfort_scale": SETTINGS.offer_comfort_scale,
	"offer_min_s": SETTINGS.offer_min_s,
	"offer_weight_base": SETTINGS.offer_weight_base,
	"offer_weight_comfort": SETTINGS.offer_weight_comfort,
	"offer_weight_hurt": SETTINGS.offer_weight_hurt,
	"reminder_hurt": SETTINGS.reminder_hurt,
	"severe_hurt": SETTINGS.severe_hurt,
	"strict_cooldown_s": SETTINGS.strict_cooldown_s,
	"withdraw_hurt": SETTINGS.withdraw_hurt,
	}

## The live rule table and the settings generation it was built from. `rules()` shares this table
## with every caller; readers must not write to it.
static var _rules_generation := -1
static var _rules_cache: Dictionary = {}


## The live rules for the current settings generation. The table is shared rather than copied, so
## a hot gate pays one dictionary reference instead of a rebuild per tier check.
static func rules() -> Dictionary:
	if _rules_generation == SETTINGS.generation:
		return _rules_cache
	var out: Dictionary = {}
	for key: String in _RULES:
		out[key] = _RULES[key].get_num()
	_rules_cache = out
	_rules_generation = SETTINGS.generation
	return _rules_cache


## The live mod section for the current world, or an empty dictionary outside one.
static func section() -> Dictionary:
	var mods := _mods()
	if mods == null:
		return {}
	var state: Variant = mods.call("state", MOD_ID)
	return state if state is Dictionary else {}


static func records(section: Dictionary) -> Dictionary:
	var rows: Variant = section.get(KEY, {})
	if rows is Dictionary:
		return rows
	var fresh: Dictionary = {}
	section[KEY] = fresh
	return fresh


static func row(section: Dictionary, id: String) -> Dictionary:
	if id.is_empty():
		return _fresh()
	var rows: Dictionary = records(section)
	var found: Variant = rows.get(id, {})
	return sanitize(found) if found is Dictionary else _fresh()


## Read-only act count. Unlike `row()`, this never creates the history block.
static func stored_acts(section: Dictionary, id: String) -> int:
	if id.is_empty():
		return 0
	var rows: Variant = section.get(KEY, {})
	if not rows is Dictionary:
		return 0
	var found: Variant = (rows as Dictionary).get(id, {})
	if not found is Dictionary:
		return 0
	return int((found as Dictionary).get("acts", 0))


## The stored row with time decay applied to a copy. Reads never write.
static func effective_row(section: Dictionary, id: String, now_day: float) -> Dictionary:
	var out := row(section, id)
	_decay(out, now_day)
	return out


static func commit(section: Dictionary, id: String, outcome: Dictionary,
		now_day: float) -> Dictionary:
	if id.is_empty():
		return out_noop(section, id)
	var rows: Dictionary = records(section)
	var stored: Variant = rows.get(id, {})
	var row := sanitize(stored) if stored is Dictionary else _fresh()
	_decay(row, now_day)
	var previous := tier_index(row)
	var grade := str(outcome.get("grade", "neutral"))
	var severe := bool(outcome.get("severe", false))
	var regular := rules()
	if grade == "good" or grade == "great":
		var comfort_add := int(regular["great_comfort"]) if grade == "great" \
			else int(regular["good_comfort"])
		var repair := int(regular["great_repair"]) if grade == "great" \
			else int(regular["good_repair"])
		row["comfort"] = mini(int(regular["max_comfort"]),
			int(row.get("comfort", 0)) + comfort_add)
		row["hurt"] = maxi(0, int(row.get("hurt", 0)) - repair)
		row["good"] = int(row.get("good", 0)) + 1
		row["streak_good"] = int(row.get("streak_good", 0)) + 1
		row["streak_bad"] = 0
	elif grade == "bad":
		var hurt_add := int(regular["severe_hurt"]) if severe \
			else int(regular["bad_hurt"])
		row["hurt"] = mini(int(regular["max_hurt"]),
			int(row.get("hurt", 0)) + hurt_add)
		row["comfort"] = maxi(0, int(row.get("comfort", 0)) - 1)
		row["bad"] = int(row.get("bad", 0)) + 1
		row["streak_bad"] = int(row.get("streak_bad", 0)) + 1
		row["streak_good"] = 0
	else:
		row["neutral"] = int(row.get("neutral", 0)) + 1
		if bool(outcome.get("early", false)):
			row["hurt"] = mini(int(regular["max_hurt"]),
				int(row.get("hurt", 0)) + int(regular["mild_hurt"]))
	row["acts"] = int(row.get("acts", 0)) + 1
	row["last_grade"] = grade
	row["last_quality"] = clampf(float(outcome.get("quality", 0.0)), 0.0, 1.0)
	row["last_reasons"] = _clean_reasons(outcome.get("reasons", []))
	row["last_text"] = str(outcome.get("text", "")).strip_edges().left(MAX_TEXT)
	row["last_wants"] = str(outcome.get("wants", "")).strip_edges().left(MAX_WANTS)
	row["last_at"] = Time.get_unix_time_from_system()
	if now_day > 0.0:
		row["last_day"] = now_day
	if bool(outcome.get("stopped_by_her", false)):
		var tolerance := str(outcome.get("tolerance", "normal"))
		var cooldown := float(regular["strict_cooldown_s"]) \
			if tolerance == "strict" else float(regular["normal_cooldown_s"])
		row["stop_until"] = Time.get_unix_time_from_system() + cooldown
		row["last_stop_kind"] = tolerance
		row["last_stop_at"] = Time.get_unix_time_from_system()
	_append_recent(row, outcome, now_day)

	var current := tier_index(row)
	var events: Array[String] = []
	if current <= 0:
		row["reminder_pending"] = false
		row["complaint_pending"] = false
	elif current > previous:
		if current >= 2:
			row["reminder_pending"] = true
			row["complaint_pending"] = true
			events.append("complaint")
			if current >= 3:
				events.append("withdrawn")
		else:
			# Tier 1 is a rare, vague hint, not a post-act reminder list.
			var hint := tier_one_hint(row)
			row["reminder_pending"] = hint
			row["complaint_pending"] = false
			if hint:
				events.append("reminder")
	elif current < previous:
		row["reminder_pending"] = false
		row["complaint_pending"] = false
	row["announced_tier"] = maxi(int(row.get("announced_tier", 0)), current)
	rows[id] = row
	section[KEY] = rows
	revision += 1
	return {"row": row.duplicate(true), "previous_tier": previous, "tier": current,
	"events": events}


## Repair hurt from a good act, staying close, or another non-sexual kindness.
static func repair(section: Dictionary, id: String, amount: int, now_day: float) -> bool:
	if id.is_empty() or amount <= 0:
		return false
	var rows: Dictionary = records(section)
	var stored: Variant = rows.get(id, {})
	if not stored is Dictionary:
		return false
	var row := sanitize(stored)
	_decay(row, now_day)
	var before := int(row.get("hurt", 0))
	row["hurt"] = maxi(0, before - amount)
	if now_day > 0.0:
		row["last_day"] = now_day
	_tidy_pending(row)
	rows[id] = row
	section[KEY] = rows
	var repaired := int(row["hurt"]) < before
	if repaired:
		revision += 1
	return repaired


## A sincere apology repairs at most once per in-game day. The caller saves.
static func apology_repair(section: Dictionary, id: String, now_day: float) -> bool:
	if id.is_empty():
		return false
	var rows: Dictionary = records(section)
	var stored: Variant = rows.get(id, {})
	if not stored is Dictionary:
		return false
	var row := sanitize(stored)
	_decay(row, now_day)
	var last := float(row.get("last_apology_day", -1.0))
	if now_day >= 0.0 and absf(last - now_day) < 0.001:
		return false
	var before := int(row.get("hurt", 0))
	var amount := int(rules()["apology_repair"])
	row["hurt"] = maxi(0, before - amount)
	row["last_apology_day"] = now_day
	if now_day > 0.0:
		row["last_day"] = now_day
	_tidy_pending(row)
	rows[id] = row
	section[KEY] = rows
	var repaired := int(row["hurt"]) < before
	if repaired:
		revision += 1
	return repaired


static func reset(section: Dictionary, id: String) -> bool:
	if id.is_empty():
		return false
	var rows: Dictionary = records(section)
	if not rows.has(id):
		return false
	rows.erase(id)
	section[KEY] = rows
	revision += 1
	return true


static func tier_index(row: Dictionary) -> int:
	var regular := rules()
	var hurt := int(row.get("hurt", 0))
	if hurt >= int(regular["withdraw_hurt"]):
		return 3
	if hurt >= int(regular["offer_block_hurt"]):
		return 2
	if hurt >= int(regular["reminder_hurt"]):
		return 1
	return 0


## A tier-1 hint is deliberately rare and vague. The choice is deterministic for one act.
static func tier_one_hint(row: Dictionary) -> bool:
	if tier_index(row) != 1:
		return false
	var seed := int(float(row.get("last_at", 0.0))) + int(row.get("hurt", 0)) * 17
	return posmod(seed, 4) == 0


static func tier_name(row: Dictionary) -> String:
	match tier_index(row):
		3:
			return "withdrawn"
		2:
			return "hurt"
		1:
			return "uneasy"
		_:
			return "steady"


## No proactive offers from the hurt tier onward.
static func blocks_offers(row: Dictionary) -> bool:
	if Time.get_unix_time_from_system() < float(row.get("stop_until", 0.0)):
		return true
	return tier_index(row) >= 2


## A hard spoken refusal at the withdrawn tier. The player may still ask; she says no.
static func blocks_start(row: Dictionary) -> bool:
	if Time.get_unix_time_from_system() < float(row.get("stop_until", 0.0)):
		return true
	return tier_index(row) >= 3


static func offer_weight(row: Dictionary) -> float:
	if Time.get_unix_time_from_system() < float(row.get("stop_until", 0.0)):
		return 0.0
	if blocks_offers(row):
		return 0.0
	var regular := rules()
	var value := float(regular["offer_weight_base"]) \
		+ float(int(row.get("comfort", 0))) * float(regular["offer_weight_comfort"]) \
		- float(int(row.get("hurt", 0))) * float(regular["offer_weight_hurt"])
	return clampf(value, 0.0, 1.0)


static func offer_cooldown(row: Dictionary, base_seconds := -1.0) -> float:
	var regular := rules()
	var base := base_seconds if base_seconds >= 0.0 else float(regular["offer_base_s"])
	var scale := float(regular["offer_comfort_scale"])
	var floor_s := float(regular["offer_min_s"])
	return maxf(floor_s, base * (1.0 - float(int(row.get("comfort", 0))) * scale))


## The stored summary is for the HUD. A normal-dialogue note keeps the reason and drops the
## repeated "You and Anon made love ..." opening sentence.
static func private_text(row: Dictionary) -> String:
	var text := str(row.get("last_text", "")).strip_edges()
	var cut := text.find(". ")
	if cut < 0:
		return text
	return text.substr(cut + 2).strip_edges()


static func prompt_note(row: Dictionary) -> String:
	if Time.get_unix_time_from_system() < float(row.get("stop_until", 0.0)):
		return "- You stopped Anon and need a little space. You are not ready to try again yet."
	var tier := tier_index(row)
	if tier <= 0:
		return ""
	var text := private_text(row)
	if tier >= 3:
		var note := "- You love Anon, but you are very reluctant to try again."
		if not text.is_empty():
			note += " Privately, you remember: " + text
			note += " Do not recite it or list what he did."
		return note + " If he asks, refuse gently and let the feeling show without explaining it all."
	if tier == 2:
		var note := "- You are still hurt about the last time."
		if not text.is_empty():
			note += " Privately, you remember: " + text
			note += " Do not recite it or list what he did."
		return note + " You do not want to ask him again; if he starts, let the hurt show in your " \
			+ "tone and give him only a small piece of it, not a review."
	if not tier_one_hint(row):
		return ""
	return "- Something about last time is still sitting with you. You are not ready to spell it out."


static func ask_note(row: Dictionary) -> String:
	if tier_index(row) <= 0:
		return ""
	var text := private_text(row)
	var note := "You still feel a little hurt from last time."
	if not text.is_empty():
		note += " Privately, you remember: " + text
		note += " Do not recite it."
	return note + " If you ask, keep it soft and indirect; do not turn it into a list of what he " \
		+ "did wrong."


static func line_purpose(row: Dictionary, kind: String) -> String:
	if kind != "complaint":
		return "Anon is close. Something about last time is still sitting with you. Say one " \
			+ "short, in-character line that hints at it; do not summarize the act or list " \
			+ "requests. One short sentence, at most 14 words. Do not narrate actions."
	var text := private_text(row)
	var note := "You are still hurt about the last time with Anon."
	if not text.is_empty():
		note += " Privately, you remember: " + text
	return note + " Say one short line in your own voice that hints at the hurt without naming " \
		+ "what he did or listing what you need. At most 14 words. Do not narrate actions."


static func refusal_purpose(row: Dictionary) -> String:
	if Time.get_unix_time_from_system() < float(row.get("stop_until", 0.0)):
		return "Anon wants to try again. You stopped him and are not ready to try again yet. " \
			+ "Refuse gently in your own voice, one short sentence, at most 14 words. " \
			+ "Do not narrate actions."
	var text := private_text(row)
	var note := "Anon wants to try again. You love him, but you are very reluctant."
	if not text.is_empty():
		note += " Privately, you remember: " + text
		note += " Do not recite it or list what he did."
	return note + " Refuse gently in your own voice. One short sentence, at most 14 words. " \
		+ "Do not narrate actions."


static func mark_announced(section: Dictionary, id: String, kind: String) -> bool:
	if id.is_empty():
		return false
	var rows: Dictionary = records(section)
	var stored: Variant = rows.get(id, {})
	if not stored is Dictionary:
		return false
	var row := sanitize(stored)
	if kind == "complaint":
		row["complaint_pending"] = false
		row["reminder_pending"] = false
	else:
		row["reminder_pending"] = false
	rows[id] = row
	section[KEY] = rows
	revision += 1
	return true


## Whether a reminder or complaint line is waiting for a quiet moment.
static func pending_line(row: Dictionary) -> String:
	if bool(row.get("complaint_pending", false)):
		return "complaint"
	if bool(row.get("reminder_pending", false)):
		return "reminder"
	return ""


static func sanitize(raw: Variant) -> Dictionary:
	var out := _fresh()
	if not raw is Dictionary:
		return out
	var value: Dictionary = raw
	out["version"] = VERSION
	for key: String in ["acts", "good", "bad", "neutral", "hurt", "comfort",
			"streak_good", "streak_bad", "announced_tier"]:
		out[key] = maxi(0, int(value.get(key, 0)))
	var regular := rules()
	out["hurt"] = mini(int(regular["max_hurt"]), int(out["hurt"]))
	out["comfort"] = mini(int(regular["max_comfort"]), int(out["comfort"]))
	out["announced_tier"] = mini(3, int(out["announced_tier"]))
	out["last_grade"] = str(value.get("last_grade", "")).left(16)
	out["last_quality"] = clampf(float(value.get("last_quality", 0.0)), 0.0, 1.0)
	out["last_reasons"] = _clean_reasons(value.get("last_reasons", []))
	out["last_text"] = str(value.get("last_text", "")).strip_edges().left(MAX_TEXT)
	out["last_wants"] = str(value.get("last_wants", "")).strip_edges().left(MAX_WANTS)
	out["last_at"] = maxf(0.0, float(value.get("last_at", 0.0)))
	out["last_day"] = maxf(0.0, float(value.get("last_day", 0.0)))
	out["last_apology_day"] = float(value.get("last_apology_day", -1.0))
	out["stop_until"] = maxf(0.0, float(value.get("stop_until", 0.0)))
	out["last_stop_kind"] = str(value.get("last_stop_kind", "")).left(16)
	out["last_stop_at"] = maxf(0.0, float(value.get("last_stop_at", 0.0)))
	out["reminder_pending"] = bool(value.get("reminder_pending", false))
	out["complaint_pending"] = bool(value.get("complaint_pending", false))
	var recent: Variant = value.get("recent", [])
	if recent is Array:
		for entry: Variant in recent:
			if not entry is Dictionary:
				continue
			var source: Dictionary = entry
			out["recent"].append({
				"grade": str(source.get("grade", "")).left(16),
				"quality": clampf(float(source.get("quality", 0.0)), 0.0, 1.0),
				"at": maxf(0.0, float(source.get("at", 0.0))),
				"reasons": _clean_reasons(source.get("reasons", [])),
				"text": str(source.get("text", "")).strip_edges().left(MAX_TEXT),
			})
			if out["recent"].size() >= MAX_RECENT:
				break
	return out


static func save() -> void:
	var mods := _mods()
	if mods != null and mods.has_method("save_changed"):
		mods.call("save_changed")


## In-game day as a float. Tests pass an explicit day instead of calling this.
static func day_now() -> float:
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null:
		var clock: Node = loop.root.get_node_or_null("TimeOfDay")
		if clock != null:
			return float(clock.get("day")) + float(clock.get("hours")) / 24.0
	return Time.get_unix_time_from_system() / 86400.0


static func _fresh() -> Dictionary:
	return {
	"version": VERSION,
	"acts": 0,
	"good": 0,
	"bad": 0,
	"neutral": 0,
	"hurt": 0,
	"comfort": 0,
	"streak_good": 0,
	"streak_bad": 0,
	"last_grade": "",
	"last_quality": 0.0,
	"last_reasons": [],
	"last_text": "",
	"last_wants": "",
	"last_at": 0.0,
	"last_day": 0.0,
	"last_apology_day": -1.0,
	"stop_until": 0.0,
	"last_stop_kind": "",
	"last_stop_at": 0.0,
	"reminder_pending": false,
	"complaint_pending": false,
	"announced_tier": 0,
	"recent": [],
	}


static func _decay(row: Dictionary, now_day: float) -> void:
	if now_day <= 0.0:
		return
	var last := float(row.get("last_day", 0.0))
	if last <= 0.0 or now_day < last:
		row["last_day"] = now_day
		return
	var days := now_day - last
	var period := maxf(1.0, float(rules()["decay_days"]))
	if days < period:
		return
	var steps := int(days / period)
	var amount := steps * int(rules()["decay_amount"])
	row["hurt"] = maxi(0, int(row.get("hurt", 0)) - amount)
	row["last_day"] = now_day
	_tidy_pending(row)


static func _tidy_pending(row: Dictionary) -> void:
	var tier := tier_index(row)
	if tier <= 0:
		row["reminder_pending"] = false
		row["complaint_pending"] = false
	elif tier < 2:
		row["complaint_pending"] = false


static func _append_recent(row: Dictionary, outcome: Dictionary, _now_day: float) -> void:
	var recent: Variant = row.get("recent", [])
	var list: Array = recent if recent is Array else []
	list.append({
	"grade": str(outcome.get("grade", "neutral")).left(16),
	"quality": clampf(float(outcome.get("quality", 0.0)), 0.0, 1.0),
	"at": Time.get_unix_time_from_system(),
	"reasons": _clean_reasons(outcome.get("reasons", [])),
	"text": str(outcome.get("text", "")).strip_edges().left(MAX_TEXT),
	})
	while list.size() > MAX_RECENT:
		list.pop_front()
	row["recent"] = list


static func _clean_reasons(raw: Variant) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	for item: Variant in raw:
		var text := str(item).strip_edges().left(32)
		if text.is_empty() or text in out:
			continue
		out.append(text)
		if out.size() >= 8:
			break
	return out


## A no-op commit outside a world or with the feature off. Runtime treats an empty row as
## "nothing was stored"; it still has the in-memory summary for the HUD and debug log.
static func out_noop(section: Dictionary, id: String) -> Dictionary:
	return {"row": row(section, id), "previous_tier": 0, "tier": 0, "events": []}


static func _mods() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("Mods")
