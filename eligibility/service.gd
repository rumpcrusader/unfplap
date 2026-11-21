extends "res://mods/unfplap/shared/service.gd"
## Service: eligibility
## Contract: docs/eligibility.md
## Scope: world
## Public eligibility API: the permanent identity answer and the provider profile layer.

const WORLD := preload("res://mods/unfplap/world/service.gd")
const POLICY := preload("res://mods/unfplap/eligibility/policy.gd")
const FACTS := preload("res://mods/unfplap/eligibility/facts.gd")
const IDENTITY_RECORD := preload("res://mods/unfplap/eligibility/identity_record.gd")
const PONY_ID := preload("res://mods/unfplap/shared/pony_id.gd")
const PARTICIPATION := preload("res://mods/unfplap/shared/participation.gd")
const CONSENT := preload("res://mods/unfplap/shared/consent.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const MARE_REGISTRY := preload("res://mods/unfplap/registry/service.gd")

## Capability targets: a consumer names its own target and never reads identity.
## See `docs/eligibility.md` (`## Capability targets`).
enum Target { ACT, ANATOMY, TAIL, CHARACTER }
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


class Participation extends RefCounted:
	var acts := true
	var anatomy := true
	## Deprecated: accepted and returned for the frozen API, but no capability reads it.
	var tail := true

	func to_dict() -> Dictionary:
		var out: Dictionary = {}
		for key: String in PARTICIPATION.all_keys():
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


## Warm one attached body at attach: build its identity record once per era.
func warm(pony: Node) -> void:
	if not _live or not is_instance_valid(pony):
		return
	var record := _identity_record(pony)
	var key := int(pony.get_instance_id())
	if int(_warmed.get(key, -1)) == record.era:
		return
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


## The resolved profile for one id: assertion, participation and consent.
## This is the cross-mod read side and the stored consent block.
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


func _typed_participation(raw: Variant) -> Participation:
	var out := Participation.new()
	if not raw is Dictionary:
		return out
	var data: Dictionary = raw
	for key: String in PARTICIPATION.all_keys():
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
