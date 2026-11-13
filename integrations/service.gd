extends RefCounted
## Service: integrations
## Contract: docs/integrations.md
## Scope: per-act
## Import: integrations/service.gd only
##
## The one scene adapter for optional act-time bridges to other installed mods. Providers are pure:
## they receive a typed context and return property/binding actions. This facade resolves the
## catalog's binding paths against the act pony, saves every original value before the first write,
## watches optional bindings that appear mid-act, and restores everything on stop, feature-off,
## missing required binding, act end or failed start.

const CATALOG := preload("res://mods/unfplap/shared/integrations.gd")
const CONTEXT := preload("res://mods/unfplap/integrations/context.gd")
const ACTION := preload("res://mods/unfplap/integrations/action.gd")
const KISSING := preload("res://mods/unfplap/integrations/kissing.gd")

const POLICY := {"kissing": KISSING}


## One provider's per-act state. The context and action arrays are reused every tick.
class ProviderState:
	var id := ""
	var spec: Dictionary = {}
	var policy: Variant = null
	var context: Variant = null
	var binding_specs: Dictionary = {}
	var bindings: Dictionary = {}
	var flags: Dictionary = {}
	var required: Array[String] = []
	var optional: Array[String] = []
	var pending: Array = []
	var active := false
	var held_excitement := false
	## The verified mod's bond-stage ceiling, read once at start.
	var reaction_cap := 1.0


## One original property value saved before the facade wrote it.
class Saved:
	var provider_id := ""
	var node: Node
	var property := ""
	var value: Variant = null


var _facts: RefCounted
var _providers: Array[ProviderState] = []
var _saved: Array[Saved] = []
var _actions: Array = []
var _affection: Node
var _begun := false
var _afterglow := false


func _init(facts: RefCounted) -> void:
	_facts = facts
	for id: String in CATALOG.ids():
		var script: Variant = POLICY.get(id)
		if script == null or not script is Script:
			continue
		var provider := ProviderState.new()
		provider.id = id
		provider.spec = CATALOG.provider(id)
		provider.policy = (script as Script).new()
		provider.context = CONTEXT.new()
		provider.binding_specs = _prepare_bindings(provider.spec.get("bindings", {}))
		for binding: String in provider.binding_specs:
			var steps: Array = provider.binding_specs[binding]
			if _binding_optional(steps):
				provider.optional.append(binding)
			else:
				provider.required.append(binding)
		_providers.append(provider)


## Start the providers for a new act. Idempotent.
func begin() -> void:
	if _begun:
		return
	_begun = true
	_afterglow = false
	_affection = _find_affection()
	for provider: ProviderState in _providers:
		_clear_provider(provider)
		_refresh_all(provider)
		_sync_context(provider)
		if not _ready(provider):
			continue
		if _start(provider):
			_log("integration %s on" % provider.id)


## Per-tick provider actions. Idempotent and allocation-free after the first tick.
func tick(delta: float) -> void:
	if not _begun or _facts == null:
		return
	for provider: ProviderState in _providers:
		if not provider.active:
			continue
		if not _required_alive(provider):
			_stop(provider, "binding lost")
			continue
		_flush_pending(provider)
		_sync_context(provider)
		_actions.clear()
		provider.policy.call("tick_actions", provider.context, delta, _actions)
		if not _apply(provider, _actions):
			_stop(provider, "write failed")


## Let Kissing's own hold and fade run. Idempotent.
func afterglow() -> void:
	if not _begun or _afterglow:
		return
	_afterglow = true
	for provider: ProviderState in _providers:
		if not provider.active:
			continue
		_sync_context(provider)
		_actions.clear()
		provider.policy.call("afterglow_actions", provider.context, _actions)
		if not _apply(provider, _actions):
			_stop(provider, "write failed")


## Re-read the act feature snapshot and start or stop providers live.
func apply_live_settings() -> void:
	if not _begun or _facts == null:
		return
	for provider: ProviderState in _providers:
		_refresh_all(provider)
		_sync_context(provider)
		var ready := _ready(provider)
		if provider.active and not ready:
			_stop(provider, "unavailable")
		elif not provider.active and ready:
			if _start(provider):
				_log("integration %s on" % provider.id)


## Restore every saved value and forget the act. Idempotent.
func reset() -> void:
	if not _begun and _saved.is_empty():
		return
	for provider: ProviderState in _providers:
		if provider.active:
			provider.active = false
			_log("integration %s off" % provider.id)
		_release_excitement(provider)
		provider.pending.clear()
		provider.bindings.clear()
		provider.flags.clear()
	_restore_provider("")
	_begun = false
	_afterglow = false
	_affection = null


## The ids of the providers currently running, in catalog order.
func active_ids() -> Array[String]:
	var out: Array[String] = []
	for provider: ProviderState in _providers:
		if provider.active:
			out.append(provider.id)
	return out


## Turn the catalog's binding rows into a path of prebuilt child NodePaths.
static func _prepare_bindings(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not raw is Dictionary:
		return out
	var rows := raw as Dictionary
	for binding: String in rows:
		var steps_value: Variant = rows[binding]
		if not steps_value is Array:
			continue
		var steps: Array = []
		for raw_step: Variant in steps_value as Array:
			if not raw_step is Dictionary:
				continue
			var step := raw_step as Dictionary
			var copy: Dictionary = {}
			for key: String in step:
				if key == "child":
					copy[key] = NodePath(str(step[key]))
				else:
					copy[key] = step[key]
			steps.append(copy)
		if not steps.is_empty():
			out[binding] = steps
	return out


static func _binding_optional(steps: Array) -> bool:
	for raw: Variant in steps:
		if raw is Dictionary and bool((raw as Dictionary).get("optional", false)):
			return true
	return false


func _clear_provider(provider: ProviderState) -> void:
	_release_excitement(provider)
	provider.active = false
	provider.pending.clear()
	provider.bindings.clear()
	provider.flags.clear()


## Re-resolve every binding, including optional ones that may have appeared.
func _refresh_all(provider: ProviderState) -> void:
	for binding: String in provider.binding_specs:
		_refresh_binding(provider, binding)


func _refresh_binding(provider: ProviderState, binding: String) -> Node:
	var steps: Variant = provider.binding_specs.get(binding)
	var node: Variant = _resolve(steps) if steps is Array else null
	if node is Node:
		provider.bindings[binding] = node
		provider.flags[binding] = true
		return node as Node
	provider.bindings[binding] = null
	provider.flags[binding] = false
	return null


func _resolve(steps: Array) -> Variant:
	var current: Variant = _facts.get("pony") if _facts != null else null
	for raw: Variant in steps:
		if not raw is Dictionary:
			return null
		var step := raw as Dictionary
		if step.has("property"):
			if not current is Object:
				return null
			current = (current as Object).get(str(step["property"]))
		elif step.has("child"):
			if not current is Node:
				return null
			current = (current as Node).get_node_or_null(step["child"] as NodePath)
		else:
			return null
		if current == null:
			return null
	return current


func _binding(provider: ProviderState, binding: String) -> Node:
	var cached: Variant = provider.bindings.get(binding)
	if cached is Node and is_instance_valid(cached):
		return cached as Node
	return _refresh_binding(provider, binding)


func _required_alive(provider: ProviderState) -> bool:
	for binding: String in provider.required:
		var node: Variant = provider.bindings.get(binding)
		if node is Node and is_instance_valid(node):
			continue
		node = _refresh_binding(provider, binding)
		if not node is Node:
			return false
	return true


func _ready(provider: ProviderState) -> bool:
	if not bool(provider.policy.call("available", provider.context)):
		return false
	return _required_alive(provider)


func _start(provider: ProviderState) -> bool:
	provider.active = true
	_actions.clear()
	provider.policy.call("start_actions", provider.context, _actions)
	if not _apply(provider, _actions):
		_stop(provider, "start failed")
		return false
	provider.reaction_cap = _read_reaction_cap(provider)
	_hold_excitement(provider)
	return true


func _stop(provider: ProviderState, reason: String) -> void:
	var was_active := provider.active
	provider.active = false
	provider.pending.clear()
	_release_excitement(provider)
	_restore_provider(provider.id)
	if was_active:
		_log("integration %s off: %s" % [provider.id, reason])


## Ask the runtime for the act-level excitement Beat hold. The runtime refcounts owners, so the
## kiss service and a provider can hold it at the same time.
func _hold_excitement(provider: ProviderState) -> void:
	if provider.held_excitement:
		return
	if not bool(provider.policy.call("holds_excitement")):
		return
	if _facts != null and _facts.has_method("hold_beat"):
		_facts.call("hold_beat", provider.id)
		provider.held_excitement = true


func _release_excitement(provider: ProviderState) -> void:
	if not provider.held_excitement:
		return
	if _facts != null and _facts.has_method("release_beat"):
		_facts.call("release_beat", provider.id)
	provider.held_excitement = false


func _apply(provider: ProviderState, actions: Array) -> bool:
	for raw: Variant in actions:
		if not raw is RefCounted:
			continue
		var action: Variant = raw
		var kind := str(action.get("kind"))
		var binding := str(action.get("binding"))
		var property := str(action.get("property"))
		if kind == ACTION.BIND:
			var bound := _binding(provider, binding)
			if not bound is Node:
				provider.pending.append(action)
				continue
			_write(provider, bound as Node, property, action.get("value"))
			continue
		if kind == ACTION.RESTORE:
			var restored := _binding(provider, binding)
			if restored is Node:
				_restore_saved(provider, restored as Node, property)
			continue
		var node := _binding(provider, binding)
		if not node is Node:
			return false
		if not _write(provider, node as Node, property, action.get("value")):
			return false
	return true


## Apply pending optional bindings as soon as their node appears.
func _flush_pending(provider: ProviderState) -> void:
	if provider.pending.is_empty():
		return
	var i := provider.pending.size() - 1
	while i >= 0:
		var action: Variant = provider.pending[i]
		var node := _binding(provider, str(action.get("binding")))
		if node is Node:
			_write(provider, node as Node, str(action.get("property")), action.get("value"))
			provider.pending.remove_at(i)
		i -= 1


## Save the original value the first time this provider writes a property, then write.
func _write(provider: ProviderState, node: Node, property: String, value: Variant) -> bool:
	if not is_instance_valid(node):
		return false
	for raw: Variant in _saved:
		var saved := raw as Saved
		if saved.provider_id == provider.id and saved.node == node \
				and saved.property == property:
			node.set(property, value)
			return true
	if not _has_property(node, property):
		return false
	var saved := Saved.new()
	saved.provider_id = provider.id
	saved.node = node
	saved.property = property
	saved.value = node.get(property)
	_saved.append(saved)
	node.set(property, value)
	return true


## Put one saved original back without dropping the record, so a later write still keeps the
## act-start value and the final reset restores it again.
func _restore_saved(provider: ProviderState, node: Node, property: String) -> void:
	for raw: Variant in _saved:
		var saved := raw as Saved
		if saved.provider_id == provider.id and saved.node == node \
				and saved.property == property:
			if is_instance_valid(saved.node) and _has_property(saved.node, saved.property):
				saved.node.set(saved.property, saved.value)
			return


## Restore one provider's saved values in reverse write order, or every provider's for "".
func _restore_provider(provider_id: String) -> void:
	var i := _saved.size() - 1
	while i >= 0:
		var saved := _saved[i]
		if provider_id.is_empty() or saved.provider_id == provider_id:
			if is_instance_valid(saved.node) and _has_property(saved.node, saved.property):
				saved.node.set(saved.property, saved.value)
			_saved.remove_at(i)
		i -= 1


static func _has_property(node: Node, property: String) -> bool:
	for row: Dictionary in node.get_property_list():
		if str(row.get("name", "")) == property:
			return true
	return false


func _find_affection() -> Node:
	if _facts == null:
		return null
	var pony: Variant = _facts.get("pony")
	if pony is Node:
		return (pony as Node).get_node_or_null("Affection")
	return null


func _affection_kind() -> String:
	if not is_instance_valid(_affection):
		_affection = _find_affection()
	if not is_instance_valid(_affection):
		return ""
	return str(_affection.get("kind"))


## Write the typed act facts into the provider's reusable context.
func _sync_context(provider: ProviderState) -> void:
	var context: Variant = provider.context
	context.state = int(_facts.get("state")) if _facts != null else 0
	context.pose_id = str(_facts.get("pose_id")) if _facts != null else ""
	context.satisfaction = float(_facts.get("satisfaction")) if _facts != null else 0.0
	context.mood = str(_facts.get("mood")) if _facts != null else ""
	context.seconds_since_stroke = float(_facts.get("seconds_since_stroke")) \
		if _facts != null else 0.0
	context.reaction_cap = provider.reaction_cap
	context.act_seconds = float(_facts.get("act_seconds")) if _facts != null else 0.0
	context.afterglow = _afterglow
	context.affection_kind = _affection_kind()
	var features: Variant = _facts.get("features") if _facts != null else null
	context.features = features if features is Dictionary else {}
	context.bindings = provider.flags


## The verified mod's bond-stage ceiling. Kissing exposes it as `Feelings._peak()`; a missing
## method leaves the provider uncapped.
func _read_reaction_cap(provider: ProviderState) -> float:
	var feelings: Variant = provider.bindings.get("feelings")
	if not feelings is Node or not is_instance_valid(feelings):
		return 1.0
	var node := feelings as Node
	if not node.has_method("_peak"):
		return 1.0
	var value: Variant = node.call("_peak")
	if not (value is float or value is int):
		return 1.0
	return clampf(float(value), 0.0, 1.0)


func _log(text: String) -> void:
	if _facts != null and _facts.has_method("write_log"):
		_facts.call("write_log", text)
