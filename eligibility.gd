extends RefCounted
## Public eligibility API and the only scene adapter. The rules live in
## `eligibility/policy.gd`; this file reads the live relationship runtime, settings profile,
## lover bond, act history, cycle and per-mare consent, then discards the facts.
##
## Facts are never stored. See `docs/eligibility.md`.

const POLICY := preload("res://mods/unfplap/eligibility/policy.gd")
const FACTS := preload("res://mods/unfplap/eligibility/facts.gd")
const VERDICT := preload("res://mods/unfplap/eligibility/verdict.gd")
const SETTINGS := preload("res://mods/unfplap/settings.gd")
const SEX_BOND := preload("res://mods/unfplap/sex_bond.gd")
const ACT_HISTORY := preload("res://mods/unfplap/act_history.gd")
const CYCLE := preload("res://mods/unfplap/cycle.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")

const MODE_START := "start"
const MODE_OFFER := "offer"
const MODE_BOND := "bond"
const MODE_MID_ACT := "mid_act"

const ACTION_PUBLIC := "public"
const ACTION_ANAL := "anal"
const ACTION_ORAL := "oral"
const ACTIONS := [ACTION_PUBLIC, ACTION_ANAL, ACTION_ORAL]

var main: Node


func setup(main_node: Node) -> void:
	main = main_node


func clear() -> void:
	main = null


## The live fact snapshot for one pony. Read-only and transient.
func facts(pony: Node) -> Dictionary:
	var out := FACTS.empty()
	if not is_instance_valid(pony):
		return out
	var identity: Variant = pony.get("identity")
	var id := _pony_id(pony)
	out["id"] = id
	out["has_identity"] = identity != null
	out["is_player_pony"] = _is_player_pony(pony)
	out["is_filly"] = identity != null and bool(identity.get("filly"))
	out["is_stallion"] = identity != null and bool(identity.get("stallion"))
	_read_relationship(pony, id, out)
	_read_settings(out)
	_read_player(out)
	_read_cycle(pony, out)
	_read_history(id, out)
	if not id.is_empty():
		out["consent"] = SETTINGS.consent(id)
	return out


## Evaluate live facts. `mode` is recorded for diagnostics; every field is always computed.
func evaluate(pony: Node, mode := MODE_START) -> Dictionary:
	return POLICY.evaluate(facts(pony), mode)


## Evaluate a snapshot a caller already built, e.g. one offer scan across several pose candidates.
func evaluate_facts(snapshot: Dictionary, mode := MODE_START) -> Dictionary:
	return POLICY.evaluate(snapshot, mode)


func adult_pony(pony: Node) -> bool:
	if not is_instance_valid(main) or not is_instance_valid(pony):
		return false
	return FACTS.adult_pony_identity(pony.get("identity"), _is_player_pony(pony))


func adult_mare(pony: Node) -> bool:
	if not is_instance_valid(main) or not is_instance_valid(pony):
		return false
	return FACTS.adult_mare_identity(pony.get("identity"), _is_player_pony(pony))


func adult_player() -> bool:
	if not is_instance_valid(main):
		return false
	return not PLAYER_FORM.is_young(PLAYER_FORM.active(_tree()))


## One per-mare action consent. Feature switches are capability gates, not consent.
func action_consent(pony: Node, key: String) -> bool:
	if not key in ACTIONS:
		return false
	var id := _pony_id(pony)
	if id.is_empty():
		return false
	return bool(SETTINGS.consent(id).get(key, false))


func reasons(verdict: Dictionary) -> PackedStringArray:
	return VERDICT.reasons(verdict)


func rows_text(verdict: Dictionary) -> String:
	return VERDICT.rows_text(verdict)


func debug_text(pony: Node, mode := MODE_START) -> String:
	var snapshot := facts(pony)
	var verdict := POLICY.evaluate(snapshot, mode)
	var relations: Dictionary = verdict.get("relations", {})
	return "eligibility mode=%s base=%s show=%s attempt=%s offer=%s bond=%s buck=%s history=%s stop=%s weight=%.2f | stage=%s love=%d willing=%s bond=%s sex_start=%s promiscuity=%s cycle=%s heat=%s | %s" % [
		mode, str(bool(verdict.get("base", false))), str(bool(verdict.get("show", false))),
		str(bool(verdict.get("attempt", false))), str(bool(verdict.get("offer", false))),
		str(bool(verdict.get("bond", false))), str(bool(verdict.get("buck_refuse", false))),
		str(bool(verdict.get("history_refuse", false))), str(bool(verdict.get("stop", false))),
		float(verdict.get("offer_weight", 0.0)),
		str(relations.get("stage", "")), int(relations.get("love_level", -1)),
		str(relations.get("willing", false)), str(relations.get("stored_bond", false)),
		str(relations.get("sex_start", "")), str(relations.get("promiscuity", "")),
		str(relations.get("cycle_phase", "")), str(relations.get("heat", false)),
		VERDICT.rows_text(verdict)]


func _read_relationship(pony: Node, id: String, out: Dictionary) -> void:
	var rel: Variant = pony.get_meta("relationship_runtime") if pony.has_meta("relationship_runtime") else null
	if rel == null or not is_instance_valid(rel):
		return
	out["has_relationship"] = true
	var bonds: Variant = rel.get("bonds")
	if bonds != null and is_instance_valid(bonds):
		var adults: Variant = bonds.get("adults")
		out["registered_adult"] = adults is Dictionary and bool((adults as Dictionary).get(id, false))
		if bonds.has_method("eligible_for_romance"):
			out["romance_eligible"] = bool(bonds.call("eligible_for_romance", id))
		if bonds.has_method("welcomes"):
			out["willing"] = bool(bonds.call("welcomes", id, "kiss"))
		if bonds.has_method("record_for"):
			var record: Variant = bonds.call("record_for", id)
			if record is Dictionary:
				out["stage"] = str((record as Dictionary).get("stage", ""))
	if rel.has_method("ladder"):
		var ladder: Variant = rel.call("ladder", id)
		if ladder is Dictionary:
			var love: Variant = (ladder as Dictionary).get("love", {})
			if love is Dictionary:
				out["love_level"] = int((love as Dictionary).get("level", -1))
	var section: Dictionary = SEX_BOND.section()
	if SEX_BOND.bonded(section, id):
		out["stored_bond"] = true
		out["bond_stage"] = str(SEX_BOND.row(section, id).get("stage", ""))


func _read_settings(out: Dictionary) -> void:
	out["promiscuity"] = SETTINGS.promiscuity.get_choice()
	out["sex_start"] = SETTINGS.sex_start.get_choice()
	out["public_feature"] = SETTINGS.act_public_offer.get_bool()


func _read_player(out: Dictionary) -> void:
	var form: Dictionary = PLAYER_FORM.active(_tree())
	out["player_young"] = PLAYER_FORM.is_young(form)
	out["player_pony"] = PLAYER_FORM.is_pony(form)


func _read_cycle(pony: Node, out: Dictionary) -> void:
	var phase := CYCLE.NORMAL
	var runtime: Variant = null
	if is_instance_valid(main) and main.has_method("runtime_for"):
		runtime = main.call("runtime_for", pony)
	if runtime != null and is_instance_valid(runtime) and runtime.has_method("cycle_phase"):
		phase = str(runtime.call("cycle_phase"))
	out["cycle_phase"] = phase
	out["cycle_allows"] = CYCLE.allows_sex(phase)
	out["heat"] = phase == CYCLE.HEAT


func _read_history(id: String, out: Dictionary) -> void:
	if id.is_empty():
		return
	var row: Dictionary = ACT_HISTORY.effective_row(ACT_HISTORY.section(), id,
		ACT_HISTORY.day_now())
	out["history"] = {
		"tier": ACT_HISTORY.tier_name(row),
		"hurt": int(row.get("hurt", 0)),
		"comfort": int(row.get("comfort", 0)),
		"blocks_start": ACT_HISTORY.blocks_start(row),
		"blocks_offers": ACT_HISTORY.blocks_offers(row),
		"offer_weight": ACT_HISTORY.offer_weight(row),
	}


func _pony_id(pony: Node) -> String:
	if not is_instance_valid(pony):
		return ""
	var id := str(pony.get_meta("relationship_id", ""))
	if not id.is_empty():
		return id
	var identity: Variant = pony.get("identity")
	return str(identity.get("id")) if identity != null else ""


func _is_player_pony(pony: Node) -> bool:
	if not is_instance_valid(pony):
		return false
	return pony.name == "PlayerPony" or is_instance_valid(pony.get("rig"))


func _tree() -> SceneTree:
	if is_instance_valid(main) and main.is_inside_tree():
		return main.get_tree()
	return Engine.get_main_loop() as SceneTree
