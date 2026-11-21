extends "res://mods/unfplap/shared/service.gd"
## Service: eligibility
## Contract: docs/eligibility.md
## Scope: world
## Public eligibility API and the only scene adapter; age and sex stay private here.

const WORLD := preload("res://mods/unfplap/world/service.gd")
const POLICY := preload("res://mods/unfplap/eligibility/policy.gd")
const FACTS := preload("res://mods/unfplap/eligibility/facts.gd")
const IDENTITY_RECORD := preload("res://mods/unfplap/eligibility/identity_record.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const PARTICIPATION := preload("res://mods/unfplap/shared/participation.gd")
const CONSENT := preload("res://mods/unfplap/shared/consent.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const ACT_HISTORY := preload("res://mods/unfplap/shared/act_history.gd")
const CYCLE := preload("res://mods/unfplap/shared/cycle.gd")
const CLEARANCE := preload("res://mods/unfplap/shared/clearance.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const PLAYER_FORM := preload("res://world/life/player_form.gd")
const MARE_REGISTRY := preload("res://mods/unfplap/registry/service.gd")

## Capability targets: a consumer names its own target and never reads identity.
## See `docs/eligibility.md` (`## Capability targets`).
enum Target { ACT, ANATOMY, TAIL, CHARACTER }
## Verdict modes. The mode is recorded; every verdict field is always computed.
enum Mode { START, OFFER }
## Row effects. `NONE` is a scene row; the rest mirror `eligibility/policy.gd`.
enum Effect { NONE, BLOCK, REFUSE, HISTORY_REFUSE, OFFER_BLOCK, FLAG }
## Witness age categories.
enum Age { NONE, YOUNG, ADULT }
## The provider's tri-state `eligible` assertion.
enum EligibilityAssertion { IDENTITY, ELIGIBLE, NOT_ELIGIBLE }

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
}



class Participation extends RefCounted:
	var acts := true
	var anatomy := true
	var tail := true

	func to_dict() -> Dictionary:
		var out: Dictionary = {}
		for key: String in PARTICIPATION.KEYS:
			out[key] = bool(get(key))
		return out


class Consent extends RefCounted:
	var public := false
	var anal := false
	var oral := false

	func to_dict() -> Dictionary:
		var out: Dictionary = {}
		for key: String in CONSENT.KEYS:
			out[key] = bool(get(key))
		return out


## One mare's resolved provider/player profile. `eligible` is the provider-only tri-state assertion.
class Profile extends RefCounted:
	var eligible: EligibilityAssertion = EligibilityAssertion.IDENTITY
	var participation: Participation = Participation.new()
	var consent: Consent = Consent.new()

	## The cross-mod `describe_mare` shape: `null`, `true` or `false`.
	func eligible_value() -> Variant:
		match eligible:
			EligibilityAssertion.ELIGIBLE:
				return true
			EligibilityAssertion.NOT_ELIGIBLE:
				return false
			_:
				return null

	func to_dict() -> Dictionary:
		return {
			"eligible": eligible_value(),
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
	var eligible: EligibilityAssertion = EligibilityAssertion.IDENTITY
	var participation: Participation = Participation.new()
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
	var consent: Consent = Consent.new()


class Actions extends RefCounted:
	var public := false
	var anal := false
	var oral := false


class Relations extends RefCounted:
	var id := ""
	var stage := ""
	var love_level := -1
	var willing := false
	var promiscuity := "any"
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


## False once the entry clears the service: every capability read answers no.
var _live := true
## Pony instance -> its typed identity record. Cleared with the world.
var _identity_records: Dictionary = {}
## Pony instance -> the record era its attach warm already read. Cleared with the world.
var _warmed: Dictionary = {}
## Shape id -> its scene identity, for the id-only capability. Cleared with the world.
var _shape_identities: Dictionary = {}


## A world enter: every capability read answers again.
func on_world(_host: Node) -> void:
	_live = true
	_identity_records.clear()
	_warmed.clear()


## The world closed: the records belonged to the bodies that are gone.
func on_world_closed() -> void:
	_identity_records.clear()
	_warmed.clear()


## The process exit: every capability read answers no.
func shutdown() -> void:
	_live = false
	_identity_records.clear()
	_warmed.clear()
	_shape_identities.clear()


## One capability answer for a consumer, called in per-frame discovery loops.
## Cheap: the cached identity record, provider assertion, stable id and the veto.
func eligible(pony: Node, target: Target = Target.ACT) -> bool:
	if not _live or not is_instance_valid(pony):
		return false
	if not TARGET_KEYS.has(target):
		return false
	var record := _identity_record(pony)
	if record.id.is_empty():
		return false
	return POLICY.participates_identity(record, str(TARGET_KEYS[target]))


## Warm one attached body at attach: the identity record and the relationship row, once per era.
## A missing relationship runtime leaves only the record warm.
func warm(pony: Node) -> void:
	if not _live or not is_instance_valid(pony):
		return
	var record := _identity_record(pony)
	var key := int(pony.get_instance_id())
	if int(_warmed.get(key, -1)) == record.era:
		return
	if record.id.is_empty():
		_warmed[key] = record.era
		return
	# A relationship runtime assigned after the spawn is warmed by the next prepare, so the record
	# stays unmarked until that read happens.
	if not pony.has_meta("relationship_runtime"):
		return
	relationship_ok(pony)
	_warmed[key] = record.era


## The id-only answer for a body that is not live, from a named shape's scene identity.
## Its default is the character target, which a shape source asks about.
func eligible_id(id: String, target: Target = Target.CHARACTER) -> bool:
	var mare_id := id.strip_edges()
	if mare_id.is_empty() or not _live or not TARGET_KEYS.has(target):
		return false
	var pony := _live_pony(mare_id)
	if is_instance_valid(pony):
		return eligible(pony, target)
	var identity := _shape_identity(mare_id)
	if identity == null:
		return false
	var profile: Dictionary = SETTINGS.profile_identity(mare_id).raw()
	var facts := FACTS.empty()
	facts["id"] = mare_id
	facts["has_identity"] = true
	var filly: Variant = identity.get("filly")
	var stallion: Variant = identity.get("stallion")
	facts["is_filly"] = filly is bool and filly
	facts["is_stallion"] = stallion is bool and stallion
	facts["eligible"] = profile.get("eligible", null)
	facts["participation"] = profile.get("participation", {})
	return POLICY.participates(facts, str(TARGET_KEYS[target]))


## The relationship row of Base clearance: live relationship, romance, the Promiscuity floor.
## Only those facts: willingness, history, cycle, player form and consent are the verdict's.
func relationship_ok(pony: Node) -> bool:
	if not _live or not is_instance_valid(pony):
		return false
	var rel: Node = pony.get_meta("relationship_runtime") \
		if pony.has_meta("relationship_runtime") else null
	if rel == null or not is_instance_valid(rel):
		return false
	var id := _identity_record(pony).id
	var romance := GAME.bond_eligible_for_romance(GAME.bonds_of(pony), id)
	var love := _love_level(rel, id)
	var floor_ok := POLICY.level_ok(str(SETTINGS.promiscuity.get_choice()), love)
	return CLEARANCE.relationship_ok(true, romance, floor_ok)


## Her love level in one read, from the level cache the game keeps current.
## A player-form change is invisible here, so the romance row gates it first.
func _love_level(rel: Node, id: String) -> int:
	var cached: Variant = _bond_levels().get(id)
	if cached is Dictionary:
		return int((cached as Dictionary).get("love", -1))
	if rel != null and is_instance_valid(rel):
		var ladder := GAME.relationship_ladder(rel, id)
		if ladder.love_found:
			return ladder.love_level
	return -1


## The game's per-pony level cache, or an empty dictionary outside a live world.
func _bond_levels() -> Dictionary:
	if not _live:
		return {}
	var game: Variant = WORLD.game
	if game == null or not is_instance_valid(game):
		return {}
	var context: Variant = game.get("world_context")
	if context == null or not is_instance_valid(context):
		return {}
	var state: Variant = context.get("state")
	if not state is Dictionary:
		return {}
	var levels: Variant = (state as Dictionary).get("bond_levels")
	return levels if levels is Dictionary else {}


## The witness age category. This is the only place a consumer needs the age instead of a
## capability.
func witness_age(pony: Node) -> Age:
	if not _live or not is_instance_valid(pony):
		return Age.NONE
	var record := _identity_record(pony)
	match FACTS.age_kind(record.has_identity, record.is_player_pony, record.is_filly,
			record.eligible_assertion()):
		FACTS.AgeKind.ADULT:
			return Age.ADULT
		FACTS.AgeKind.YOUNG:
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
	out.offer = bool(policy.get("offer", false))
	out.offer_weight = float(policy.get("offer_weight", 0.0))
	return out


## The resolved profile for one id: assertion, participation and consent.
## This is the cross-mod read side and the anatomy consent lookup.
func get_profile(id: String) -> Profile:
	var mare_id := id.strip_edges()
	var resolved := SETTINGS.profile_identity(mare_id)
	var out := Profile.new()
	out.eligible = _eligible_from_value(resolved.raw().get("eligible", null))
	out.participation = _typed_participation(resolved.rows("participation").raw())
	out.consent = _typed_consent(SETTINGS.consent(mare_id).raw())
	return out


## Write the provider layer for one owner: assertion, participation and consent.
## It lives in the registry; this service stores nothing and returns the registration result.
func set_profile(owner: Node, id: String, profile: Profile) -> MARE_REGISTRY.Result:
	var mare_id := id.strip_edges()
	if not is_instance_valid(owner) or not owner.is_inside_tree():
		return _profile_result(mare_id, "", false,
			["owner: must be a valid Node inside the scene tree"])
	if profile == null:
		return _profile_result(mare_id, "", false, ["profile: required"])
	var source := _owner_source(owner)
	var result: MARE_REGISTRY.Result = MARE_REGISTRY.set_profile(owner.get_instance_id(), source,
		mare_id, _profile_descriptor(profile))
	if result.ok and _live:
		SETTINGS.apply_live()
	return result


func _facts_data(pony: Node) -> Dictionary:
	var out := FACTS.empty()
	if not is_instance_valid(pony):
		return out
	out.merge(_record_facts(pony), true)
	var id := str(out.get("id", ""))
	_read_relationship(pony, id, out)
	_read_settings(out)
	_read_player(out)
	_read_cycle(pony, out)
	_read_history(id, out)
	if not id.is_empty():
		out["consent"] = SETTINGS.consent(id).raw()
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
	var bonds: Object = GAME.bonds_of(pony)
	if bonds != null:
		var adults: Variant = bonds.get("adults")
		out["registered_adult"] = _registered_adult(id, adults)
		out["romance_eligible"] = GAME.bond_eligible_for_romance(bonds, id)
		out["willing"] = GAME.bond_welcomes(bonds, id, "kiss")
		var record := GAME.bond_record_for(bonds, id)
		if not record.rows.is_empty():
			out["stage"] = record.stage
	out["love_level"] = _love_level(rel, id)


func _read_settings(out: Dictionary) -> void:
	out["promiscuity"] = SETTINGS.promiscuity.get_choice()


func _read_player(out: Dictionary) -> void:
	var form: Dictionary = PLAYER_FORM.active(_tree())
	out["player_young"] = PLAYER_FORM.is_young(form)
	out["player_pony"] = PLAYER_FORM.is_pony(form)


## The debug override wins even with the feature off, so the lab can force heat.
## A just-spawned pony has no relationship runtime, so that reads as normal.
static func cycle_phase_for(pony: Node, id: String) -> String:
	var override := CYCLE.override_for(id)
	if not override.is_empty():
		return override
	if not SETTINGS.estrus_cycle.get_bool() or id.is_empty() or not is_instance_valid(pony):
		return CYCLE.NORMAL
	if not pony.has_meta("relationship_runtime"):
		return CYCLE.NORMAL
	var day := GAME.bond_day(GAME.bonds_of(pony))
	if is_nan(day):
		return CYCLE.NORMAL
	return CYCLE.phase(day, id)


## The heat/diestrus note for the normal dialogue prompt, during and outside acts.
## Empty while the act gate would stay shut.
func cycle_note(pony: Node) -> String:
	if not is_instance_valid(pony):
		return ""
	var verdict := get_verdict(pony, Mode.START)
	if verdict == null or not verdict.base:
		return ""
	return CYCLE.prompt_note(cycle_phase_for(pony, _identity_record(pony).id))


func _read_cycle(pony: Node, out: Dictionary) -> void:
	var phase := cycle_phase_for(pony, str(out.get("id", "")))
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


## The identity half of the snapshot, copied from the record into the cold facts dictionary.
func _record_facts(pony: Node) -> Dictionary:
	var record := _identity_record(pony)
	return {
		"id": record.id,
		"eligible": record.eligible_assertion(),
		"participation": record.participation,
		"has_identity": record.has_identity,
		"is_player_pony": record.is_player_pony,
		"is_filly": record.is_filly,
		"is_stallion": record.is_stallion,
	}


## One pony's cached identity record; a moved era rebuilds it.
func _identity_record(pony: Node) -> IDENTITY_RECORD.IdentityRecord:
	var key := int(pony.get_instance_id())
	var identity: Variant = pony.get("identity")
	var era := _identity_era(pony, identity)
	var cached: Variant = _identity_records.get(key)
	if cached is IDENTITY_RECORD.IdentityRecord:
		var known := cached as IDENTITY_RECORD.IdentityRecord
		if known.era == era:
			return known
	var record := IDENTITY_RECORD.IdentityRecord.new()
	record.era = era
	record.has_identity = identity != null
	record.is_player_pony = _is_player_pony(pony)
	record.is_filly = identity != null and identity.get("filly") == true
	record.is_stallion = identity != null and identity.get("stallion") == true
	record.id = PONY_ID.from(str(pony.get_meta("relationship_id", "")), identity)
	var profile: Dictionary = SETTINGS.profile_identity(record.id).raw()
	var assertion: Variant = profile.get("eligible", null)
	record.has_eligible_assertion = assertion is bool
	record.eligible = assertion is bool and bool(assertion)
	var participation: Variant = profile.get("participation", {})
	record.participation = participation if participation is Dictionary else {}
	_identity_records[key] = record
	return record


## The era of one record: four integers mixed without an allocation.
func _identity_era(pony: Node, identity: Variant) -> int:
	var identity_id := 0
	if identity is Object and is_instance_valid(identity):
		identity_id = int((identity as Object).get_instance_id())
	var era := SETTINGS.generation
	era = era * 31 + MARE_REGISTRY.revision
	era = era * 31 + identity_id
	return era * 31 + hash(str(pony.get_meta("relationship_id", "")))


func _typed_facts(data: Dictionary) -> Facts:
	var out := Facts.new()
	out.id = str(data.get("id", ""))
	out.has_identity = bool(data.get("has_identity", false))
	out.is_player_pony = bool(data.get("is_player_pony", false))
	out.is_filly = bool(data.get("is_filly", false))
	out.is_stallion = bool(data.get("is_stallion", false))
	out.eligible = _eligible_from_value(data.get("eligible", null))
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


func _typed_participation(raw: Variant) -> Participation:
	var out := Participation.new()
	if not raw is Dictionary:
		return out
	var data: Dictionary = raw
	for key: String in PARTICIPATION.KEYS:
		out.set(key, bool(data.get(key, true)))
	return out


func _typed_consent(raw: Variant) -> Consent:
	var out := Consent.new()
	if not raw is Dictionary:
		return out
	var data: Dictionary = raw
	for key: String in CONSENT.KEYS:
		out.set(key, bool(data.get(key, false)))
	return out


func _eligible_from_value(raw: Variant) -> EligibilityAssertion:
	if raw is bool:
		return EligibilityAssertion.ELIGIBLE if bool(raw) else EligibilityAssertion.NOT_ELIGIBLE
	return EligibilityAssertion.IDENTITY


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


func _profile_descriptor(profile: Profile) -> MARE_REGISTRY.Identity:
	var out := MARE_REGISTRY.Identity.new()
	out.has_consent = true
	out.consent = profile.consent.to_dict()
	out.has_profile = true
	out.profile = {"participation": profile.participation.to_dict()}
	match profile.eligible:
		EligibilityAssertion.ELIGIBLE:
			out.has_eligible = true
			out.eligible = true
		EligibilityAssertion.NOT_ELIGIBLE:
			out.has_eligible = true
			out.eligible = false
	return out


func _profile_result(id: String, source: String, replaced: bool,
		errors: Array[String]) -> MARE_REGISTRY.Result:
	var out := MARE_REGISTRY.Result.new()
	out.id = id
	out.source = source
	out.replaced = replaced
	out.errors = errors
	return out


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


## The live body for a shape id, when one is loaded. It is the authority for a provider mod's
## off-roster mare.
func _live_pony(id: String) -> Node:
	if not _live:
		return null
	var game: Variant = WORLD.game
	if game == null or not is_instance_valid(game):
		return null
	var mares: Variant = (game as Node).get("mares")
	if not mares is Array:
		return null
	for pony: Variant in mares:
		if is_instance_valid(pony) and _pony_id(pony as Node) == id:
			return pony as Node
	return null


## The population scene's identity for a shape that is not live. The population's `available`
## map is the catalogue the pack copies from; the scene's root carries its identity resource.
func _shape_identity(id: String) -> Resource:
	if _shape_identities.has(id):
		return _shape_identities[id] as Resource
	var identity: Resource = null
	var game: Variant = WORLD.game
	if game == null or not is_instance_valid(game):
		_shape_identities[id] = identity
		return null
	var population: Variant = (game as Node).get("population")
	if population == null or not is_instance_valid(population):
		_shape_identities[id] = identity
		return null
	var available: Variant = (population as Node).get("available")
	if not available is Dictionary:
		_shape_identities[id] = identity
		return null
	var path := str((available as Dictionary).get(id, ""))
	if path.is_empty():
		_shape_identities[id] = identity
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		_shape_identities[id] = identity
		return null
	var state := scene.get_state()
	if state.get_node_count() > 0:
		for i in state.get_node_property_count(0):
			if state.get_node_property_name(0, i) == &"identity":
				identity = state.get_node_property_value(0, i) as Resource
				break
	_shape_identities[id] = identity
	return identity


func _pony_id(pony: Node) -> String:
	if not is_instance_valid(pony):
		return ""
	return PONY_ID.from(str(pony.get_meta("relationship_id", "")), pony.get("identity"))


func _is_player_pony(pony: Node) -> bool:
	if not is_instance_valid(pony):
		return false
	return pony.name == "PlayerPony" or is_instance_valid(pony.get("rig"))


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree
