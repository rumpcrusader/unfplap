extends Node
## The stable cross-mod API facade, and the only script of this mod another mod calls. It returns
## plain data, never internal Nodes, runtimes, settings paths or resource handles.
##
## Discovery is by group, `unfplap_api` and the pinned `unfplap_api_v1`; the human contract is
## `docs/api.md`.

const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const REGISTRY := preload("res://mods/unfplap/registry/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const GAME := preload("res://mods/unfplap/world/game.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const API_MAJOR := 1
const API_MINOR := 1
const API_VERSION := "1.1"
const SCHEMA := 1
const SCHEMAS := {"mare": 1, "preferences": 1, "placement": 1}
const CAPABILITIES := {"registry.mare": 1, "mare.read": 1, "profile.mare": 1}
## Methods that still work but should be replaced. None in 1.0; the entry shape is part of the
## contract so a future deprecation is data, not a code change in every consumer.
const DEPRECATIONS := []

## owner instance id -> true, for the auto-unregister on tree exit.
var _owners: Dictionary = {}


func _enter_tree() -> void:
	add_to_group("unfplap_api")
	add_to_group("unfplap_api_v1")


func _exit_tree() -> void:
	_shutdown()


## The complete contract. Plain data; safe to cache for the process lifetime.
func contract() -> Dictionary:
	return {
		"provider": "unfplap",
		"api_version": API_VERSION,
		"api_major": API_MAJOR,
		"api_minor": API_MINOR,
		"mod_version": _mod_version(),
		"game_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"schemas": SCHEMAS.duplicate(true),
		"capabilities": CAPABILITIES.duplicate(true),
		"deprecations": DEPRECATIONS.duplicate(true),
	}


## True when this build has the named capability at least at `min_version`.
func supports(capability: String, min_version: int = 1) -> bool:
	return int(CAPABILITIES.get(capability, 0)) >= maxi(1, min_version)


## Register or replace one provider template for `owner`; removing that Node from the tree removes
## every layer it registered. Returns {ok, id, source, replaced, warnings, errors}.
func register_mare(owner: Node, descriptor: Dictionary) -> Dictionary:
	if not is_instance_valid(owner) or not owner.is_inside_tree():
		return _failure(descriptor, "owner: must be a valid Node inside the scene tree")
	var result: REGISTRY.Result = REGISTRY.register(owner.get_instance_id(),
		REGISTRY.Descriptor.from_dict(descriptor))
	if result.ok:
		_watch_owner(owner)
		SETTINGS.bump_placement_revision()
		_refresh_live()
		LOG.debug("api registered %s from %s", [result.id, result.source])
	else:
		LOG.warning("api register failed: %s", [", ".join(result.errors)])
	return result.to_dict()


## Remove one provider layer owned by `owner`. Returns {ok, id, removed}.
func unregister_mare(owner: Node, id: String) -> Dictionary:
	var mare_id := id.strip_edges()
	if not is_instance_valid(owner):
		return {"ok": false, "id": mare_id, "removed": false,
			"errors": ["owner: must be a valid Node"]}
	var removed: bool = REGISTRY.unregister(owner.get_instance_id(), mare_id)
	if removed:
		SETTINGS.bump_placement_revision()
		_refresh_live()
		LOG.debug("api unregistered %s", [mare_id])
	return {"ok": true, "id": mare_id, "removed": removed}


## Everything static unfplap resolves for a mare, never live act, history, relationship or anatomy
## state. Always complete; an unknown id gets global defaults with `known: false`.
func describe_mare(id: String) -> Dictionary:
	var mare_id := id.strip_edges()
	var template: Dictionary = SETTINGS.template_for(mare_id).raw()
	var event_prompts: Dictionary = {}
	var raw_events: Variant = template.get("event_prompts", {})
	for key: String in REGISTRY.EVENT_PROMPT_KEYS:
		var value: Variant = (raw_events as Dictionary).get(key, "") if raw_events is Dictionary else ""
		event_prompts[key] = str(value)
	var poses: Dictionary = {}
	var raw_poses: Variant = template.get("poses", {})
	for pose_key: String in CATALOG.all():
		var value: Variant = (raw_poses as Dictionary).get(pose_key, {}) if raw_poses is Dictionary else {}
		poses[pose_key] = (value as Dictionary).duplicate(true) if value is Dictionary else {}
	var act_prompts: Dictionary = {}
	var raw_act: Variant = template.get("act_prompts", {})
	if raw_act is Dictionary:
		act_prompts = (raw_act as Dictionary).duplicate(true)
	var smack_value: Variant = template.get("smack_zone_radius", 0.035)
	var smack_radius := 0.035
	if smack_value is float or smack_value is int:
		smack_radius = maxf(0.0, float(smack_value))
	# The identity slice is read through the eligibility service so its rules and the registry
	# stay in one place.
	var service: ELIGIBILITY = PONIES.eligibility
	var profile: ELIGIBILITY.Profile = service.get_profile(mare_id) if service != null else null
	var consent: Dictionary = profile.consent.to_dict() if profile != null else {}
	var eligible: Variant = profile.eligible_value() if profile != null else null
	var participation: Dictionary = profile.participation.to_dict() if profile != null else {}
	return {
		"schema": SCHEMA,
		"id": mare_id,
		"name": SETTINGS.character_name(mare_id),
		"known": SETTINGS.CHARACTER_NAMES.has(mare_id)
			or SETTINGS.CHARACTER_TEMPLATES.has(mare_id) or REGISTRY.has(mare_id),
		"registered": REGISTRY.has(mare_id),
		"sources": REGISTRY.sources(mare_id),
		"preferences": SETTINGS.preferences(mare_id).raw(),
		"consent": consent,
		"eligible": eligible,
		"profile": {"participation": participation},
		"placement": SETTINGS.anatomy_placement(mare_id).raw(),
		"poses": poses,
		"act_prompts": act_prompts,
		"event_prompts": event_prompts,
		"cue_gap": SETTINGS.cue_gap(mare_id),
		"aftercare_min": SETTINGS.aftercare_min(mare_id),
		"smack_zone_radius": smack_radius,
	}


## Internal teardown, also called by the entry before it frees this node.
func _shutdown() -> void:
	_owners.clear()
	REGISTRY.reset()


func _watch_owner(owner: Node) -> void:
	var owner_id := owner.get_instance_id()
	if _owners.has(owner_id):
		return
	_owners[owner_id] = true
	owner.tree_exiting.connect(_on_owner_tree_exiting.bind(owner_id))


func _on_owner_tree_exiting(owner_id: int) -> void:
	_owners.erase(owner_id)
	if REGISTRY.unregister_owner(owner_id) > 0:
		SETTINGS.bump_placement_revision()
		_refresh_live()


func _refresh_live() -> void:
	if not is_inside_tree():
		return
	# A provider layer changed: one settings pass re-reads every service that caches a value,
	# the live anatomy and tail seat included. The entry is not asked.
	SETTINGS.apply_live()


func _failure(descriptor: Dictionary, error: String) -> Dictionary:
	return {
		"ok": false,
		"id": str(descriptor.get("id", "")).strip_edges(),
		"source": str(descriptor.get("source", "")).strip_edges(),
		"replaced": false,
		"warnings": [],
		"errors": [error],
	}


func _mod_version() -> String:
	var mods := get_node_or_null("/root/Mods")
	for mod: Dictionary in GAME.mods_list(mods):
		if str(mod.get("id", "")) == "unfplap":
			return str(mod.get("version", ""))
	return ""
