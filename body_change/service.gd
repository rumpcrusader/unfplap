extends Node
## Service: body_change
## Contract: docs/body_change.md
## Scope: world
## Import: body_change/service.gd only
##
## The base body-change service: the per-body form store and its default own form, the typed source
## and binding registries, the active-change read and the legacy metadata mirror. A source provider
## owns its pack and its own observation; the service never polls.

const BODY_BINDING := preload("res://mods/unfplap/shared/body_binding.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_CHANGE_POLICY := preload("res://mods/unfplap/shared/body_change_policy.gd")
const BODY_CHANGE_SOURCE := preload("res://mods/unfplap/body_change/source.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const WIRE := preload("res://mods/unfplap/body_change/wire.gd")

var main: Node = null
## The host's debug sink. `main.debug()` carries the mod id and obeys the debug toggle.
var _log: Callable = Callable()
## Registration order is the binding fan-out order and the source lookup order.
var _sources: Array[BODY_CHANGE_SOURCE] = []
var _bindings: Array[BODY_BINDING] = []
## Presented body -> its form. The default form is cached here too, so a read never rebuilds it.
var _forms: Dictionary = {}
## Presented body -> the revision last applied. Kept beside the form so an in-place provider
## mutation still refreshes; comparing the stored form's own field would compare the new value.
var _revisions: Dictionary = {}
var _bound: Dictionary = {}
var _active_change: BODY_CHANGE = null


func setup(host: Node) -> void:
	main = host
	_log = Callable(host, "debug") if is_instance_valid(host) and host.has_method("debug") \
		else Callable()


## Register one provider. The shared `BodyChange.source` handle is a narrow `Node`; this is the
## boundary that proves a registered provider actually extends the source base.
func register_source(source: Node) -> bool:
	if not is_instance_valid(source) or not source is BODY_CHANGE_SOURCE:
		return false
	var typed: BODY_CHANGE_SOURCE = source
	if _sources.has(typed):
		return true
	_sources.append(typed)
	return true


func unregister_source(source: Node) -> void:
	if not is_instance_valid(source) or not source is BODY_CHANGE_SOURCE:
		return
	var typed: BODY_CHANGE_SOURCE = source
	_sources.erase(typed)
	if _active_change != null and _active_change.source == typed:
		_active_change = null


## Register one body-bound system. The binding base is RefCounted, so the argument is checked
## against the preloaded script before it reaches the typed registry.
func register_binding(binding: RefCounted) -> bool:
	if binding == null or not binding is BODY_BINDING:
		return false
	var typed: BODY_BINDING = binding
	if _bindings.has(typed):
		return true
	_bindings.append(typed)
	return true


func unregister_binding(binding: RefCounted) -> void:
	if binding == null or not binding is BODY_BINDING:
		return
	_bindings.erase(binding)


## Active providers in registration order.
func active_sources() -> Array[BODY_CHANGE_SOURCE]:
	var out: Array[BODY_CHANGE_SOURCE] = []
	for source: BODY_CHANGE_SOURCE in _sources:
		if is_instance_valid(source) and source.is_active():
			out.append(source)
	return out


## The first active provider that handles the presented body, or null.
func source_for(body: Node3D) -> BODY_CHANGE_SOURCE:
	if not is_instance_valid(body):
		return null
	for source: BODY_CHANGE_SOURCE in _sources:
		if not is_instance_valid(source) or not source.is_active():
			continue
		if source.handles_pony(body):
			return source
	return null


## The handling provider's optional offer/reveal policy, or null.
func policy_for(body: Node3D) -> BODY_CHANGE_POLICY:
	var source := source_for(body)
	if source == null:
		return null
	return source.policy()


## The last change a provider announced, or null. The provider observes its pack and pushes; the
## runtime's existing act watcher only reads this value.
func active_change() -> BODY_CHANGE:
	return _active_change


## The form the body presents now. A body without a stored form gets the cached default own form;
## an invalid body has none.
func form_for(body: Node3D) -> BODY_FORM.BodyForm:
	if not is_instance_valid(body):
		return null
	var stored: Variant = _forms.get(body)
	if stored is BODY_FORM.BodyForm:
		return stored
	var form := BODY_FORM.default_form(body)
	_forms[body] = form
	return form


## The stable pony identity, not the presented body's form id.
func pony_id_for(body: Node3D) -> String:
	var form := form_for(body)
	return form.pony_id if form != null else ""


## A fresh default own form for the body; `form_for()` owns the cached copy.
func default_form(body: Node3D) -> BODY_FORM.BodyForm:
	return BODY_FORM.default_form(body)


## Apply one presented body's form: store it, mirror the legacy keys, log one line, then bind a new
## body or refresh the same body when its revision changed.
func apply_form(body: Node3D, form: BODY_FORM.BodyForm) -> void:
	if not is_instance_valid(body) or form == null:
		return
	var stored: Variant = _forms.get(body)
	var previous: BODY_FORM.BodyForm = stored if stored is BODY_FORM.BodyForm else null
	var was_bound := _bound.has(body)
	var last_revision: int = int(_revisions.get(body, -1))
	var action := "bind"
	if was_bound:
		action = "refresh" if form.revision != last_revision or not _same_form(previous, form) \
			else "apply"
	_forms[body] = form
	_revisions[body] = form.revision
	WIRE.apply(body, form)
	_log_apply(body, form, previous, action)
	if action == "bind":
		_bound[body] = true
		_notify_bind(body, form)
	elif action == "refresh":
		_notify_refresh(body, form)


## Adopt a presented body with its stored or default form. Idempotent for an already bound body.
func bind_body(body: Node3D) -> void:
	if not is_instance_valid(body) or _bound.has(body):
		return
	var form := form_for(body)
	if form == null:
		return
	apply_form(body, form)


## Re-read the same body's stored form and refresh every binding. An unbound body binds instead.
func refresh_body(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	if not _bound.has(body):
		bind_body(body)
		return
	var form := form_for(body)
	if form == null:
		return
	WIRE.apply(body, form)
	_notify_refresh(body, form)


## Release every binding for a body that is leaving, then drop its form.
func unbind_body(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	if _bound.erase(body):
		for binding: BODY_BINDING in _bindings:
			if is_instance_valid(binding):
				binding.unbind_body(body)
	_forms.erase(body)
	_revisions.erase(body)


## The provider reports that its own observed state changed. Only a registered source may move the
## active-change read; an unknown source cannot inject one.
func notify_source_changed(source: Node) -> void:
	if not is_instance_valid(source) or not source is BODY_CHANGE_SOURCE:
		return
	var typed: BODY_CHANGE_SOURCE = source
	if not _sources.has(typed):
		return
	_adopt_change(typed)


## The provider reports a spawned or revised body. The service asks the claiming source for the new
## form, stores it and fans it out; a provider that has no form yet leaves the default in place.
func notify_body_ready(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	var source := _claiming_source(body)
	if source == null:
		return
	var change := source.active_change()
	if change == null and _active_change != null and _active_change.source == source:
		change = _active_change
	if change != null and change.source == null:
		change.source = source
	var form := source.prepare_body(body, change)
	if form == null:
		return
	if change != null:
		change.next_body = body
		change.form = form
		if change.state == BODY_CHANGE.State.REQUESTED:
			change.state = BODY_CHANGE.State.PREPARING
		_active_change = change
	apply_form(body, form)
	if change != null and change.state == BODY_CHANGE.State.PREPARING:
		change.state = BODY_CHANGE.State.ADOPTED


## Forward a borrowed/custom form request to the handling provider, then adopt the change it starts.
func request_form(body: Node3D, form_id: String, origin: BODY_CHANGE.Origin) -> bool:
	var source := source_for(body)
	if source == null:
		return false
	var accepted := source.request_form(body, form_id, origin)
	if accepted:
		_adopt_change(source)
	return accepted


## Forward a return-to-own-form request to the handling provider.
func request_own_form(body: Node3D, origin: BODY_CHANGE.Origin) -> bool:
	var source := source_for(body)
	if source == null:
		return false
	var accepted := source.request_own_form(body, origin)
	if accepted:
		_adopt_change(source)
	return accepted


func _claiming_source(body: Node3D) -> BODY_CHANGE_SOURCE:
	for source: BODY_CHANGE_SOURCE in _sources:
		if not is_instance_valid(source) or not source.is_active():
			continue
		if source.claims_body(body):
			return source
	return source_for(body)


func _adopt_change(source: BODY_CHANGE_SOURCE) -> void:
	var change := source.active_change()
	if change == null:
		if _active_change != null and _active_change.source == source:
			_active_change = null
		return
	if change.source == null:
		change.source = source
	_active_change = change


## The same typed values, so a provider form that arrives after the default still refreshes when a
## source's own form has the same empty form id and revision as the default own form.
func _same_form(a: BODY_FORM.BodyForm, b: BODY_FORM.BodyForm) -> bool:
	if a == null or b == null:
		return a == b
	if a.pony_id != b.pony_id or a.form_id != b.form_id or a.form_name != b.form_name:
		return false
	if a.fit_id != b.fit_id or a.owned_mesh_meta != b.owned_mesh_meta:
		return false
	if a.tail_root != b.tail_root or not is_equal_approx(a.body_scale, b.body_scale):
		return false
	var a_rig := a.rig.id if a.rig != null else ""
	var b_rig := b.rig.id if b.rig != null else ""
	return a_rig == b_rig


func _notify_bind(body: Node3D, form: BODY_FORM.BodyForm) -> void:
	for binding: BODY_BINDING in _bindings:
		if is_instance_valid(binding):
			binding.bind_body(body, form)


func _notify_refresh(body: Node3D, form: BODY_FORM.BodyForm) -> void:
	for binding: BODY_BINDING in _bindings:
		if is_instance_valid(binding):
			binding.refresh_body(body, form)


func _log_apply(body: Node3D, form: BODY_FORM.BodyForm, previous: BODY_FORM.BodyForm,
		action: String) -> void:
	if not _log.is_valid():
		return
	var previous_id := "none"
	if previous != null:
		previous_id = previous.form_id if not previous.form_id.is_empty() else "own"
	var form_id := form.form_id if not form.form_id.is_empty() else "own"
	var marker := form.owned_mesh_meta if not form.owned_mesh_meta.is_empty() else "-"
	var rig_id := form.rig.id if form.rig != null else "-"
	var names := PackedStringArray()
	for binding: BODY_BINDING in _bindings:
		if is_instance_valid(binding):
			var binding_name := binding.binding_id().strip_edges()
			names.append(binding_name if not binding_name.is_empty() else "?")
	var bindings := ",".join(names) if not names.is_empty() else "-"
	_log.call("body change body=%s pony=%s form=%s fit=%s rig=%s marker=%s scale=%.3f revision=%d prev=%s action=%s bindings=%s" % [
		str(body.name), form.pony_id, form_id, form.fit_id, rig_id, marker, form.body_scale,
		form.revision, previous_id, action, bindings])
