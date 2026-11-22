extends "res://mods/unfplap/shared/service.gd"
## Service: act_gate
## Contract: docs/act_gate.md
## Scope: world
## The dynamic act gate: relationship, romance, willingness, cycle, history and consent.

const POLICY := preload("res://mods/unfplap/act_gate/policy.gd")
const FACTS := preload("res://mods/unfplap/act_gate/facts.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const PARTICIPATION := preload("res://mods/unfplap/shared/participation.gd")
const CONSENT := preload("res://mods/unfplap/shared/consent.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const CYCLE_STATE := preload("res://mods/unfplap/shared/cycle_state.gd")
const CLEARANCE := preload("res://mods/unfplap/shared/clearance.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const WORLD := preload("res://mods/unfplap/world/api.gd")

## Verdict modes. The mode is recorded; every verdict field is always computed.
enum Mode { START, OFFER }
## Row effects. `NONE` is a scene row; the rest mirror `act_gate/policy.gd`.
enum Effect { NONE, BLOCK, REFUSE, HISTORY_REFUSE, OFFER_BLOCK, FLAG }

const MODE_NAMES := {
	Mode.START: "start",
	Mode.OFFER: "offer",
}


## The relationship's recent history: the flags and counts the gate reads.
class History extends RefCounted:
	var tier := "steady"
	var hurt := 0
	var comfort := 0
	var blocks_start := false
	var blocks_offers := false
	var offer_weight := 0.0


## The per-call gate snapshot. Never stored.
class Facts extends RefCounted:
	var id := ""
	var eligible: ELIGIBILITY.EligibilityAssertion = ELIGIBILITY.EligibilityAssertion.IDENTITY
	var adult := false
	var participation: ELIGIBILITY.Participation = ELIGIBILITY.Participation.new()
	var has_relationship := false
	var registered_adult := false
	var romance_eligible := false
	var stage := ""
	var love_level := -1
	var willing := false
	var promiscuity := "any"
	var player_young := true
	var player_pony := false
	var cycle_phase := "normal"
	var cycle_allows := false
	var heat := false
	var history: History = History.new()
	var consent: ELIGIBILITY.Consent = ELIGIBILITY.Consent.new()


## The action flags the consent gate reads for one row.
class Actions extends RefCounted:
	var public := false
	var anal := false
	var oral := false


## The relationship facts the gate reads for one mare.
class Relations extends RefCounted:
	var id := ""
	var stage := ""
	var love_level := -1
	var willing := false
	var promiscuity := "any"
	var cycle_phase := "normal"
	var heat := false
	var base := false


## One gate row's answer and the policy effect it carries.
class Row extends RefCounted:
	var key := ""
	var ok := false
	var reason := ""
	var effect: Effect = Effect.NONE


## The gate's one answer for a pony and an act, built from its rows.
class Verdict extends RefCounted:
	var mode: Mode = Mode.START
	var base := false
	var show := false
	var offer := false
	var offer_weight := 0.0
	var facts: Facts = Facts.new()
	var actions: Actions = Actions.new()
	var relations: Relations = Relations.new()
	var rows: Array[Row] = []

	func reasons() -> PackedStringArray:
		var out: PackedStringArray = []
		for row in rows:
			if not row.ok:
				out.append(row.reason)
		return out

	func rows_text() -> String:
		var parts: PackedStringArray = []
		for row in rows:
			parts.append("%s=%s(%s)" % [row.key, "ok" if row.ok else "FAIL",
				_effect_name(row.effect)])
		return " ".join(parts)

	func _effect_name(effect: Effect) -> String:
		match effect:
			Effect.BLOCK:
				return "block"
			Effect.REFUSE:
				return "refuse"
			Effect.HISTORY_REFUSE:
				return "history_refuse"
			Effect.OFFER_BLOCK:
				return "offer_block"
			Effect.FLAG:
				return "flag"
			_:
				return ""


## False once the entry clears the service: every read answers no.
var _live := true
## The eligibility facade this gate asks the identity question. Bound by the entry.
var _eligibility: ELIGIBILITY = null
## Pony instance -> its attach warm already read the relationship row. Cleared with the world.
var _warmed: Dictionary = {}


## A world enter: every read answers again.
func on_world(_host: Node) -> void:
	_live = true
	_warmed.clear()


## The world closed: the warmed bodies are gone.
func on_world_closed() -> void:
	_warmed.clear()


## The process exit: every read answers no.
func shutdown() -> void:
	_live = false
	_warmed.clear()
	_eligibility = null


## The identity service, bound once by the entry after both exist.
func bind_eligibility(service: ELIGIBILITY) -> void:
	_eligibility = service


## The act key in one call: the identity target and the relationship row.
func ready(pony: Node) -> bool:
	if not _live or not is_instance_valid(pony) or not _has_eligibility():
		return false
	return _eligibility.eligible(pony, ELIGIBILITY.Target.ACT) and relationship_ok(pony)


## The relationship row of Base clearance: live relationship, romance, the Promiscuity floor.
## Only those facts: willingness, history, cycle, player form and consent are the verdict's.
func relationship_ok(pony: Node) -> bool:
	if not _live or not is_instance_valid(pony):
		return false
	var rel: Node = pony.get_meta("relationship_runtime") \
		if pony.has_meta("relationship_runtime") else null
	if rel == null or not is_instance_valid(rel):
		return false
	var id := PONY_ID.of(pony)
	var relations := WORLD.relationship()
	var romance := relations.eligible_for_romance(relations.bonds_of(pony), id)
	var love := _love_level(rel, id)
	var floor_ok := POLICY.level_ok(str(SETTINGS.promiscuity.get_choice()), love)
	return CLEARANCE.relationship_ok(true, romance, floor_ok)


## The attach-time read: one clearance row per body, so no offer pays a cold bond read first.
func warm(pony: Node) -> void:
	if not _live or not is_instance_valid(pony):
		return
	if not pony.has_meta("relationship_runtime"):
		return
	var key := int(pony.get_instance_id())
	if _warmed.has(key):
		return
	relationship_ok(pony)
	_warmed[key] = true


## One pony's per-mare consent key: `public`, `anal` or `oral`. An empty id reads false.
func consent(pony: Node, key: String) -> bool:
	var id := PONY_ID.of(pony)
	if id.is_empty():
		return false
	var profile := SETTINGS.consent(id)
	match key:
		"public":
			return profile.bool_value("public", false)
		"anal":
			return profile.bool_value("anal", false)
		"oral":
			return profile.bool_value("oral", false)
	return false


## The cycle line the normal dialogue prompt appends; empty while the base would stay shut.
func cycle_note(pony: Node) -> String:
	if not is_instance_valid(pony):
		return ""
	var verdict := get_verdict(pony, Mode.START)
	if verdict == null or not verdict.base:
		return ""
	return CYCLE.prompt_note(cycle_phase_for(pony))


## The debug override wins even with the feature off, so the lab can force heat.
static func cycle_phase_for(pony: Node) -> String:
	var relations := WORLD.relationship()
	return CYCLE_STATE.phase(pony, SETTINGS.estrus_cycle.get_bool(),
		relations.day(relations.bonds_of(pony)))


## The typed act gate. Never stored.
func get_verdict(pony: Node, mode: Mode = Mode.START) -> Verdict:
	var out := Verdict.new()
	out.mode = mode
	if not _live:
		return out
	var data := _facts_data(pony)
	var policy := POLICY.evaluate(data, _mode_name(mode))
	out.facts = _typed_facts(data)
	out.actions = _typed_actions(policy)
	out.relations = _typed_relations(policy)
	out.rows = _typed_rows(policy.get("rows", []))
	out.base = bool(policy.get("base", false))
	out.show = bool(policy.get("show", false))
	out.offer = bool(policy.get("offer", false))
	out.offer_weight = float(policy.get("offer_weight", 0.0))
	return out


func _facts_data(pony: Node) -> Dictionary:
	var out := FACTS.empty()
	if not is_instance_valid(pony):
		return out
	out.merge(_identity_facts(pony), true)
	var id := str(out.get("id", ""))
	_read_relationship(pony, id, out)
	_read_settings(out)
	_read_player(out)
	_read_cycle(pony, out)
	_read_history(id, out)
	return out


## The identity half: the stable id, the adult answer and the resolved profile blocks.
## A missing eligibility service fails the adult row closed.
func _identity_facts(pony: Node) -> Dictionary:
	var id := PONY_ID.of(pony)
	var out := {
		"id": id,
		"adult": _has_eligibility() and _eligibility.eligible(pony, ELIGIBILITY.Target.CHARACTER),
	}
	if id.is_empty() or not _has_eligibility():
		return out
	var profile := _eligibility.get_profile(id)
	out["eligible"] = profile.eligible_value()
	out["participation"] = profile.participation.to_dict()
	out["consent"] = profile.consent.to_dict()
	return out


## The provider's tri-state assertion wins for unfplap's own registration fact; without one,
## the base game's adult table decides. Base-game willingness and romance still read the game.
func _registered_adult(id: String, adults: Variant) -> bool:
	if SETTINGS.profile_has_assertion(id):
		return SETTINGS.profile_eligible(id)
	return adults is Dictionary and bool((adults as Dictionary).get(id, false))


func _read_relationship(pony: Node, id: String, out: Dictionary) -> void:
	var rel: Node = pony.get_meta("relationship_runtime") if pony.has_meta("relationship_runtime") else null
	if rel == null or not is_instance_valid(rel):
		return
	out["has_relationship"] = true
	var relations := WORLD.relationship()
	var bonds: Object = relations.bonds_of(pony)
	if bonds != null:
		var adults: Variant = bonds.get("adults")
		out["registered_adult"] = _registered_adult(id, adults)
		out["romance_eligible"] = relations.eligible_for_romance(bonds, id)
		out["willing"] = relations.welcomes(bonds, id, "kiss")
		var record := relations.record(bonds, id)
		if not record.rows.is_empty():
			out["stage"] = record.stage
	out["love_level"] = _love_level(rel, id)


func _read_settings(out: Dictionary) -> void:
	out["promiscuity"] = SETTINGS.promiscuity.get_choice()


func _read_player(out: Dictionary) -> void:
	var anon := WORLD.anon()
	out["player_young"] = anon.form_is_young()
	out["player_pony"] = anon.form_is_pony()


func _read_cycle(pony: Node, out: Dictionary) -> void:
	var phase := cycle_phase_for(pony)
	out["cycle_phase"] = phase
	out["cycle_allows"] = CYCLE.allows_sex(phase)
	out["heat"] = phase == CYCLE.HEAT


func _read_history(id: String, out: Dictionary) -> void:
	if id.is_empty():
		return
	var row: Dictionary = ACT_HISTORY.effective_row(
		WORLD.mods().state(ACT_HISTORY.MOD_ID).rows, id, ACT_HISTORY.day_now())
	out["history"] = {
		"tier": ACT_HISTORY.tier_name(row),
		"hurt": int(row.get("hurt", 0)),
		"comfort": int(row.get("comfort", 0)),
		"blocks_start": ACT_HISTORY.blocks_start(row),
		"blocks_offers": ACT_HISTORY.blocks_offers(row),
		"offer_weight": ACT_HISTORY.offer_weight(row),
	}


## Her love level in one read, from the level cache the game keeps current.
## A player-form change is invisible here, so the romance row gates it first.
func _love_level(rel: Node, id: String) -> int:
	var cached := WORLD.bond_level(id)
	if cached.found:
		return cached.love
	if rel != null and is_instance_valid(rel):
		var ladder := WORLD.relationship().ladder(id)
		if ladder.love_found:
			return ladder.love_level
	return -1



func _typed_facts(data: Dictionary) -> Facts:
	var out := Facts.new()
	out.id = str(data.get("id", ""))
	out.eligible = _eligible_from_value(data.get("eligible", null))
	out.adult = bool(data.get("adult", false))
	out.participation = _typed_participation(data.get("participation", {}))
	out.has_relationship = bool(data.get("has_relationship", false))
	out.registered_adult = bool(data.get("registered_adult", false))
	out.romance_eligible = bool(data.get("romance_eligible", false))
	out.stage = str(data.get("stage", ""))
	out.love_level = int(data.get("love_level", -1))
	out.willing = bool(data.get("willing", false))
	out.promiscuity = str(data.get("promiscuity", "any"))
	out.player_young = bool(data.get("player_young", true))
	out.player_pony = bool(data.get("player_pony", false))
	out.cycle_phase = str(data.get("cycle_phase", "normal"))
	out.cycle_allows = bool(data.get("cycle_allows", false))
	out.heat = bool(data.get("heat", false))
	out.history = _typed_history(data.get("history", {}))
	out.consent = _typed_consent(data.get("consent", {}))
	return out


func _typed_actions(policy: Dictionary) -> Actions:
	var data: Dictionary = policy.get("actions", {})
	var out := Actions.new()
	out.public = bool(data.get("public", false))
	out.anal = bool(data.get("anal", false))
	out.oral = bool(data.get("oral", false))
	return out


func _typed_relations(policy: Dictionary) -> Relations:
	var data: Dictionary = policy.get("relations", {})
	var out := Relations.new()
	out.id = str(data.get("id", ""))
	out.stage = str(data.get("stage", ""))
	out.love_level = int(data.get("love_level", -1))
	out.willing = bool(data.get("willing", false))
	out.promiscuity = str(data.get("promiscuity", "any"))
	out.cycle_phase = str(data.get("cycle_phase", "normal"))
	out.heat = bool(data.get("heat", false))
	out.base = bool(data.get("base", false))
	return out


func _typed_rows(raw: Variant) -> Array[Row]:
	var out: Array[Row] = []
	if not raw is Array:
		return out
	for item: Variant in raw:
		if not item is Dictionary:
			continue
		var data: Dictionary = item
		var row := Row.new()
		row.key = str(data.get("key", ""))
		row.ok = bool(data.get("ok", false))
		row.reason = str(data.get("reason", ""))
		row.effect = _effect_from_name(str(data.get("effect", "")))
		out.append(row)
	return out


func _typed_history(raw: Variant) -> History:
	var out := History.new()
	if not raw is Dictionary:
		return out
	var data: Dictionary = raw
	out.tier = str(data.get("tier", "steady"))
	out.hurt = int(data.get("hurt", 0))
	out.comfort = int(data.get("comfort", 0))
	out.blocks_start = bool(data.get("blocks_start", false))
	out.blocks_offers = bool(data.get("blocks_offers", false))
	out.offer_weight = float(data.get("offer_weight", 0.0))
	return out


func _typed_participation(raw: Variant) -> ELIGIBILITY.Participation:
	var out := ELIGIBILITY.Participation.new()
	if not raw is Dictionary:
		return out
	var data: Dictionary = raw
	for key: String in PARTICIPATION.all_keys():
		out.set(key, bool(data.get(key, true)))
	return out


func _typed_consent(raw: Variant) -> ELIGIBILITY.Consent:
	var out := ELIGIBILITY.Consent.new()
	if not raw is Dictionary:
		return out
	var data: Dictionary = raw
	for key: String in CONSENT.KEYS:
		out.set(key, bool(data.get(key, false)))
	return out


func _eligible_from_value(raw: Variant) -> ELIGIBILITY.EligibilityAssertion:
	if raw is bool:
		return ELIGIBILITY.EligibilityAssertion.ELIGIBLE if bool(raw) \
			else ELIGIBILITY.EligibilityAssertion.NOT_ELIGIBLE
	return ELIGIBILITY.EligibilityAssertion.IDENTITY

func _effect_from_name(name: String) -> Effect:
	match name:
		"block":
			return Effect.BLOCK
		"refuse":
			return Effect.REFUSE
		"history_refuse":
			return Effect.HISTORY_REFUSE
		"offer_block":
			return Effect.OFFER_BLOCK
		"flag":
			return Effect.FLAG
		_:
			return Effect.NONE


func _mode_name(mode: Mode) -> String:
	return str(MODE_NAMES.get(mode, "start"))


func _has_eligibility() -> bool:
	return _eligibility != null and is_instance_valid(_eligibility)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree
