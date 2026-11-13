extends RefCounted
## Public eligibility API and the only scene adapter. The rules live in
## `eligibility/policy.gd`; this file reads the live relationship runtime, settings profile,
## act history, cycle and per-mare consent, then discards its working snapshot.
##
## The callable surface is deliberately small:
##   eligible()       one capability answer for a consumer
##   witness_age()    the witness age category
##   get_verdict()    the typed act gate
##   get_profile()    the resolved provider/player profile, by id
##   set_profile()    write the provider identity layer, by owner
## Age, sex and the provider assertion stay private here.
##
## Verdicts are built per call and never stored. See `docs/eligibility.md`.

const POLICY := preload("res://mods/unfplap/eligibility/policy.gd")
const FACTS := preload("res://mods/unfplap/eligibility/facts.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const MARE_REGISTRY := preload("res://mods/unfplap/registry/service.gd")

## Capability targets. A consumer asks about its own target; it never inspects age, sex or the
## provider assertion. See `docs/eligibility.md` (`## Capability targets`).
enum Target { ACT, ANATOMY, TAIL, CHARACTER }
## Verdict modes. The mode is recorded; every verdict field is always computed.
enum Mode { START, OFFER, MID_ACT }
## Row effects. `NONE` is a scene row; the rest mirror `eligibility/policy.gd`.
enum Effect { NONE, BLOCK, REFUSE, HISTORY_REFUSE, OFFER_BLOCK, FLAG }
## Witness age categories.
enum Age { NONE, YOUNG, ADULT }
## The provider's tri-state `adult` assertion.
enum AdultAssertion { IDENTITY, ADULT, NOT_ADULT }

## Target -> the `profile.participation` veto it respects. An empty key means identity only.
const TARGET_KEYS := {
	Target.ACT: "acts",
	Target.ANATOMY: "anatomy",
	Target.TAIL: "tail",
	Target.CHARACTER: "",
}
const MODE_NAMES := {
	Mode.START: "start",
	Mode.OFFER: "offer",
	Mode.MID_ACT: "mid_act",
}



class Participation extends RefCounted:
	var acts := true
	var anatomy := true
	var tail := true

	func to_dict() -> Dictionary:
		return {"acts": acts, "anatomy": anatomy, "tail": tail}


class Consent extends RefCounted:
	var public := false
	var anal := false
	var oral := false

	func to_dict() -> Dictionary:
		return {"public": public, "anal": anal, "oral": oral}


## One mare's resolved provider/player profile. `adult` is the provider-only tri-state assertion.
class Profile extends RefCounted:
	var adult: AdultAssertion = AdultAssertion.IDENTITY
	var participation: Participation = Participation.new()
	var consent: Consent = Consent.new()

	## The cross-mod `describe_mare` shape: `null`, `true` or `false`.
	func adult_value() -> Variant:
		match adult:
			AdultAssertion.ADULT:
				return true
			AdultAssertion.NOT_ADULT:
				return false
			_:
				return null

	func to_dict() -> Dictionary:
		return {
			"adult": adult_value(),
			"participation": participation.to_dict(),
			"consent": consent.to_dict(),
		}


class History extends RefCounted:
	var tier := "steady"
	var hurt := 0
	var comfort := 0
	var blocks_start := false
	var blocks_offers := false
	var offer_weight := 0.0


## The per-call eligibility snapshot. Never stored.
class Facts extends RefCounted:
	var id := ""
	var has_identity := false
	var is_player_pony := false
	var is_filly := false
	var is_stallion := false
	var adult: AdultAssertion = AdultAssertion.IDENTITY
	var participation: Participation = Participation.new()
	var has_relationship := false
	var registered_adult := false
	var romance_eligible := false
	var stage := ""
	var love_level := -1
	var willing := false
	var promiscuity := "any"
	var sex_start := "try_luck"
	var public_feature := true
	var player_young := true
	var player_pony := false
	var cycle_phase := "normal"
	var cycle_allows := false
	var heat := false
	var history: History = History.new()
	var consent: Consent = Consent.new()


class Actions extends RefCounted:
	var public := false
	var public_offer := false
	var anal := false
	var oral := false


class Relations extends RefCounted:
	var id := ""
	var stage := ""
	var love_level := -1
	var willing := false
	var promiscuity := "any"
	var sex_start := ""
	var cycle_phase := "normal"
	var heat := false
	var base := false


class Row extends RefCounted:
	var key := ""
	var ok := false
	var reason := ""
	var effect: Effect = Effect.NONE


class Verdict extends RefCounted:
	var mode: Mode = Mode.START
	var base := false
	var show := false
	var attempt := false
	var offer := false
	var buck_refuse := false
	var history_refuse := false
	var stop := true
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


var main: Node


func setup(main_node: Node) -> void:
	main = main_node


func clear() -> void:
	main = null


## One capability answer for a consumer. Cheap by design: identity, provider assertion, stable id
## and the target's participation veto, never the full snapshot. This is called in per-frame
## discovery loops.
func eligible(pony: Node, target: Target = Target.ACT) -> bool:
	if not is_instance_valid(main) or not is_instance_valid(pony):
		return false
	if not TARGET_KEYS.has(target):
		return false
	var snapshot := _identity_facts(pony)
	if str(snapshot.get("id", "")).is_empty():
		return false
	return POLICY.participates(snapshot, str(TARGET_KEYS[target]))


## The witness age category. This is the only place a consumer needs the age instead of a
## capability.
func witness_age(pony: Node) -> Age:
	if not is_instance_valid(main) or not is_instance_valid(pony):
		return Age.NONE
	match POLICY.age_kind(_identity_facts(pony)):
		"adult":
			return Age.ADULT
		"young":
			return Age.YOUNG
		_:
			return Age.NONE


## The typed act gate. Never stored.
func get_verdict(pony: Node, mode: Mode = Mode.START) -> Verdict:
	var data := _facts_data(pony)
	var policy := POLICY.evaluate(data, _mode_name(mode))
	var out := Verdict.new()
	out.mode = mode
	out.facts = _typed_facts(data)
	out.actions = _typed_actions(policy)
	out.relations = _typed_relations(policy)
	out.rows = _typed_rows(policy.get("rows", []))
	out.base = bool(policy.get("base", false))
	out.show = bool(policy.get("show", false))
	out.attempt = bool(policy.get("attempt", false))
	out.offer = bool(policy.get("offer", false))
	out.buck_refuse = bool(policy.get("buck_refuse", false))
	out.history_refuse = bool(policy.get("history_refuse", false))
	out.stop = bool(policy.get("stop", true))
	out.offer_weight = float(policy.get("offer_weight", 0.0))
	return out


## The resolved provider/player profile for one id: adult assertion, participation and consent.
## This is the cross-mod read side and the anatomy consent lookup.
func get_profile(id: String) -> Profile:
	var mare_id := id.strip_edges()
	var resolved := SETTINGS.profile_identity(mare_id)
	var out := Profile.new()
	out.adult = _adult_from_value(resolved.get("adult", null))
	out.participation = _typed_participation(resolved.get("participation", {}))
	out.consent = _typed_consent(SETTINGS.consent(mare_id))
	return out


## Write the provider identity layer for one owner: the adult assertion, participation and
## consent. The layer lives in `mare_registry`; this service stores nothing. Returns the standard
## registration result.
func set_profile(owner: Node, id: String, profile: Profile) -> Dictionary:
	var mare_id := id.strip_edges()
	if not is_instance_valid(owner) or not owner.is_inside_tree():
		return _profile_result(mare_id, "", false,
			["owner: must be a valid Node inside the scene tree"])
	if profile == null:
		return _profile_result(mare_id, "", false, ["profile: required"])
	var source := _owner_source(owner)
	var result := MARE_REGISTRY.set_profile(owner.get_instance_id(), source, mare_id,
		_profile_descriptor(profile))
	if bool(result.get("ok", false)) and is_instance_valid(main) \
			and main.has_method("refresh_api_state"):
		main.call("refresh_api_state")
	return result


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
	if not id.is_empty():
		out["consent"] = SETTINGS.consent(id)
	return out


## The provider's tri-state assertion wins for unfplap's own registration fact; without one,
## the base game's adult table decides. Base-game willingness and romance still read the game.
func _registered_adult(id: String, adults: Variant) -> bool:
	var asserted: Variant = SETTINGS.profile_adult(id)
	if asserted is bool:
		return asserted
	return adults is Dictionary and bool((adults as Dictionary).get(id, false))


func _read_relationship(pony: Node, id: String, out: Dictionary) -> void:
	var rel: Variant = pony.get_meta("relationship_runtime") if pony.has_meta("relationship_runtime") else null
	if rel == null or not is_instance_valid(rel):
		return
	out["has_relationship"] = true
	var bonds: Variant = rel.get("bonds")
	if bonds != null and is_instance_valid(bonds):
		var adults: Variant = bonds.get("adults")
		out["registered_adult"] = _registered_adult(id, adults)
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


## The identity half of the snapshot. `eligible()` and `witness_age()` build only this block, so a
## discovery scan never reads bonds, history or cycle.
func _identity_facts(pony: Node) -> Dictionary:
	var identity: Variant = pony.get("identity")
	var id := _pony_id(pony)
	var profile := SETTINGS.profile_identity(id)
	return {
		"id": id,
		"adult": profile.get("adult", null),
		"participation": profile.get("participation", {}),
		"has_identity": identity != null,
		"is_player_pony": _is_player_pony(pony),
		"is_filly": identity != null and bool(identity.get("filly")),
		"is_stallion": identity != null and bool(identity.get("stallion")),
	}


func _typed_facts(data: Dictionary) -> Facts:
	var out := Facts.new()
	out.id = str(data.get("id", ""))
	out.has_identity = bool(data.get("has_identity", false))
	out.is_player_pony = bool(data.get("is_player_pony", false))
	out.is_filly = bool(data.get("is_filly", false))
	out.is_stallion = bool(data.get("is_stallion", false))
	out.adult = _adult_from_value(data.get("adult", null))
	out.participation = _typed_participation(data.get("participation", {}))
	out.has_relationship = bool(data.get("has_relationship", false))
	out.registered_adult = bool(data.get("registered_adult", false))
	out.romance_eligible = bool(data.get("romance_eligible", false))
	out.stage = str(data.get("stage", ""))
	out.love_level = int(data.get("love_level", -1))
	out.willing = bool(data.get("willing", false))
	out.promiscuity = str(data.get("promiscuity", "any"))
	out.sex_start = str(data.get("sex_start", "try_luck"))
	out.public_feature = bool(data.get("public_feature", true))
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
	out.public_offer = bool(data.get("public_offer", false))
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
	out.sex_start = str(data.get("sex_start", ""))
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


func _typed_participation(raw: Variant) -> Participation:
	var out := Participation.new()
	if not raw is Dictionary:
		return out
	var data: Dictionary = raw
	out.acts = bool(data.get("acts", true))
	out.anatomy = bool(data.get("anatomy", true))
	out.tail = bool(data.get("tail", true))
	return out


func _typed_consent(raw: Variant) -> Consent:
	var out := Consent.new()
	if not raw is Dictionary:
		return out
	var data: Dictionary = raw
	out.public = bool(data.get("public", false))
	out.anal = bool(data.get("anal", false))
	out.oral = bool(data.get("oral", false))
	return out


func _adult_from_value(raw: Variant) -> AdultAssertion:
	if raw is bool:
		return AdultAssertion.ADULT if bool(raw) else AdultAssertion.NOT_ADULT
	return AdultAssertion.IDENTITY


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


func _profile_descriptor(profile: Profile) -> Dictionary:
	var out := {
		"consent": profile.consent.to_dict(),
		"profile": {"participation": profile.participation.to_dict()},
	}
	match profile.adult:
		AdultAssertion.ADULT:
			out["adult"] = true
		AdultAssertion.NOT_ADULT:
			out["adult"] = false
		_:
			pass
	return out


func _profile_result(id: String, source: String, replaced: bool, errors: Array) -> Dictionary:
	return {
		"ok": false, "id": id, "source": source, "replaced": replaced,
		"warnings": [], "errors": errors,
	}


## A provider source for an identity-only write. The existing layer keeps its source; a new layer
## is named after the owner node.
func _owner_source(owner: Node) -> String:
	var raw := str(owner.name).strip_edges().to_lower()
	var out := ""
	for index in raw.length():
		var ch := raw.substr(index, 1)
		if ch == " " or ch == "." or ch == ":":
			out += "_"
		else:
			out += ch
	out = out.strip_edges()
	if out.is_empty():
		return "provider"
	return out.substr(0, 64)


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
