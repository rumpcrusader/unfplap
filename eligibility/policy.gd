extends RefCounted
## Pure eligibility truth table. It receives a facts dictionary and returns a verdict. No Node,
## no scene, no Time, no Settings and no file access. See `docs/eligibility.md`.

const FACTS := preload("res://mods/unfplap/eligibility/facts.gd")

## The Promiscuity setting, pickiest first. `any` skips the love-level check entirely.
const LEVELS := {
	"soulmates": 4,
	"head_over_hooves": 3,
	"marefriend": 2,
	"new_couple": 1,
	"crush": 0,
	"any": -1,
}
const DEFAULT_LEVEL := "marefriend"

const EFFECT_BLOCK := "block"
const EFFECT_REFUSE := "refuse"
const EFFECT_HISTORY_REFUSE := "history_refuse"
const EFFECT_OFFER_BLOCK := "offer_block"
const EFFECT_FLAG := "flag"


## True when `love_level` meets the selected Promiscuity floor. Unknown values fall back to
## Marefriend, the old hardcoded gate.
static func level_ok(required: String, love_level: int) -> bool:
	var need: int = int(LEVELS.get(required, int(LEVELS[DEFAULT_LEVEL])))
	return need < 0 or love_level >= need


## Starting Sex `try_luck` shows the start hint before she welcomes a kiss. It never skips the
## base kiss willingness for a start or an offer; the policy still checks that separately.
static func hint_without_willingness(sex_start: String) -> bool:
	return sex_start == "try_luck"


static func adult_pony(facts: Dictionary) -> bool:
	return FACTS.adult_pony(bool(facts.get("has_identity", false)),
		bool(facts.get("is_player_pony", false)), bool(facts.get("is_filly", false)),
		facts.get("adult", null))


static func adult_mare(facts: Dictionary) -> bool:
	return FACTS.adult_mare(bool(facts.get("has_identity", false)),
		bool(facts.get("is_player_pony", false)), bool(facts.get("is_filly", false)),
		bool(facts.get("is_stallion", false)), facts.get("adult", null))


static func adult_player(facts: Dictionary) -> bool:
	return not bool(facts.get("player_young", false))


## The capability answer for a consumer: adult mare plus the named participation veto. An empty
## key means identity only, which the Characters selector needs so an opted-out mare stays
## editable. See `docs/eligibility.md` (`## Capability targets`).
static func participates(facts: Dictionary, key := "") -> bool:
	if not adult_mare(facts):
		return false
	if key.is_empty():
		return true
	return bool((facts.get("participation", {}) as Dictionary).get(key, true))


## The witness age category, or `FACTS.AgeKind.NONE` when she can be neither an adult nor a young
## witness. A provider's `adult` assertion wins over the identity flag in both directions.
static func age_kind(facts: Dictionary) -> int:
	return FACTS.age_kind(bool(facts.get("has_identity", false)),
		bool(facts.get("is_player_pony", false)), bool(facts.get("is_filly", false)),
		facts.get("adult", null))


## The shared base: an adult mare with a relationship runtime, a registered adult, an adult
## player, romance eligibility and the selected Promiscuity floor.
static func base_ok(facts: Dictionary) -> bool:
	return adult_mare(facts) \
		and bool(facts.get("has_relationship", false)) \
		and bool(facts.get("registered_adult", false)) \
		and adult_player(facts) \
		and bool(facts.get("romance_eligible", false)) \
		and level_ok(str(facts.get("promiscuity", "any")), int(facts.get("love_level", -1)))


## Evaluate one fact snapshot. Every field is computed; `mode` is recorded for diagnostics and
## call sites choose the field they need.
static func evaluate(raw_facts: Dictionary, mode: String) -> Dictionary:
	var facts := FACTS.normalize(raw_facts)
	var rows: Array = []
	var adult := adult_mare(facts)
	var relationship := bool(facts.get("has_relationship", false)) \
		and bool(facts.get("registered_adult", false))
	var player := adult_player(facts)
	var romance := bool(facts.get("romance_eligible", false))
	var level := level_ok(str(facts.get("promiscuity", "any")),
		int(facts.get("love_level", -1)))
	var willing := bool(facts.get("willing", false))
	var cycle_ok := bool(facts.get("cycle_allows", false))
	var history := facts.get("history", {}) as Dictionary
	var blocks_start := bool(history.get("blocks_start", false))
	var blocks_offers := bool(history.get("blocks_offers", false))
	var participation: Dictionary = facts.get("participation", {}) as Dictionary
	var participates := bool(participation.get("acts", true))
	var base := adult and relationship and player and romance and level
	var hint_early := hint_without_willingness(str(facts.get("sex_start", "")))
	var show := base and participates and cycle_ok and (willing or hint_early)
	var attempt := show and willing and not blocks_start
	var buck_refuse := base and not willing
	var history_refuse := base and blocks_start
	var offer := base and participates and willing and cycle_ok \
		and not blocks_offers and not blocks_start
	var stop := not (base and willing and cycle_ok)
	var offer_weight := 0.0
	if offer:
		offer_weight = float(history.get("offer_weight", 0.0))

	_add_row(rows, "adult", adult, "adult", EFFECT_BLOCK)
	_add_row(rows, "relationship", relationship, "relationship", EFFECT_BLOCK)
	_add_row(rows, "form", player, "form", EFFECT_BLOCK)
	_add_row(rows, "romance", romance, "romance", EFFECT_BLOCK)
	_add_row(rows, "promiscuity", level, "promiscuity", EFFECT_BLOCK)
	_add_row(rows, "participation", participates, "participation", EFFECT_BLOCK)
	_add_row(rows, "relation", willing, "relation", EFFECT_REFUSE)
	_add_row(rows, "cycle", cycle_ok, "cycle", EFFECT_BLOCK)
	_add_row(rows, "history", not blocks_start, "history", EFFECT_HISTORY_REFUSE)
	_add_row(rows, "history_offers", not blocks_offers, "history_offers", EFFECT_OFFER_BLOCK)
	_add_row(rows, "public", true, "public", EFFECT_FLAG)

	var consent: Dictionary = facts.get("consent", {}) as Dictionary
	var heat := bool(facts.get("heat", false))
	var public_consent := bool(consent.get("public", false))
	var public_feature := bool(facts.get("public_feature", false))
	var actions := {
		"public": public_consent,
		"public_offer": heat or (public_feature and public_consent),
		"anal": bool(consent.get("anal", false)),
		"oral": bool(consent.get("oral", false)),
	}
	var relations := {
		"id": str(facts.get("id", "")),
		"stage": str(facts.get("stage", "")),
		"love_level": int(facts.get("love_level", -1)),
		"willing": willing,
		"promiscuity": str(facts.get("promiscuity", "any")),
		"sex_start": str(facts.get("sex_start", "")),
		"cycle_phase": str(facts.get("cycle_phase", "normal")),
		"heat": heat,
		"base": base,
	}
	return {
		"mode": mode,
		"base": base,
		"show": show,
		"attempt": attempt,
		"offer": offer,
		"buck_refuse": buck_refuse,
		"history_refuse": history_refuse,
		"stop": stop,
		"offer_weight": offer_weight,
		"actions": actions,
		"relations": relations,
		"rows": rows,
	}


static func _add_row(rows: Array, key: String, ok: bool, reason: String, effect: String) -> void:
	rows.append({"key": key, "ok": ok, "reason": reason if not ok or not reason.is_empty() else key,
		"effect": effect})
