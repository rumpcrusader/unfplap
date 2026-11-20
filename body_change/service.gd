extends Node
## Service: body_change
## Contract: docs/body_change.md
## Scope: world
## Import: body_change/service.gd only
## Per-body form store, provider and binding registries, binding fan-out.

const ANATOMY_BINDING := preload("res://mods/unfplap/anatomy/body_binding.gd")
const BODY_BINDING := preload("res://mods/unfplap/shared/body_binding.gd")
const BODY_CHANGE := preload("res://mods/unfplap/shared/body_change.gd")
const BODY_CHANGE_POLICY := preload("res://mods/unfplap/shared/body_change_policy.gd")
const BODY_CHANGE_SOURCE := preload("res://mods/unfplap/body_change/source.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const GARMENT_BINDING := preload("res://mods/unfplap/body_change/garment_binding.gd")
const LOD_BINDING := preload("res://mods/unfplap/body_change/lod_binding.gd")
const RUNTIME_BINDING := preload("res://mods/unfplap/body_change/runtime_binding.gd")
const SMACK_BINDING := preload("res://mods/unfplap/body_change/smack_binding.gd")
const WIRE := preload("res://mods/unfplap/body_change/wire.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

## The game's `set_body_scale()` clamps the capsule to this range; a form carries the clamped
## value so the descriptor, the mesh scale and the capsule never disagree.
const BODY_SCALE_MIN := 0.25
const BODY_SCALE_MAX := 4.0

## The log sink. `LOG.debug()` carries the mod id and obeys the debug toggle.
var _log: Callable = Callable()
var _sources: Array[BODY_CHANGE_SOURCE] = []
var _bindings: Array[BODY_BINDING] = []
## Presented body -> its form. The default form is cached here too, so a read never rebuilds it.
var _forms: Dictionary = {}
## Presented body -> the revision last applied. Kept beside the form so an in-place provider
## mutation still refreshes; comparing the stored form's own field would compare the new value.
var _revisions: Dictionary = {}
var _bound: Dictionary = {}
var _active_by_source: Dictionary = {}
var _active_by_body: Dictionary = {}


func setup() -> void:
	_log = Callable(LOG, "debug")
	CHANGE.on_changed(Callable(self, "apply_settings"))


func _exit_tree() -> void:
	CHANGE.off_changed(Callable(self, "apply_settings"))


## A settings edit can change the re-seat toggle or a saved tail: the handling source applies its
## own wrapper once for every live body.
func apply_settings() -> void:
	for pony: Variant in PONIES.live_ponies():
		if is_instance_valid(pony):
			apply_tail_placement(pony)


## Builds the built-in binding chain in fan-out order; a missing facade registers none.
func wire(anatomy: Node, pantyhose: Node, stock_smack: Node) -> void:
	if is_instance_valid(anatomy):
		var anatomy_binding: RefCounted = ANATOMY_BINDING.new()
		anatomy_binding.call("setup", anatomy)
		register_binding(anatomy_binding)
	register_binding(RUNTIME_BINDING.new())
	register_binding(LOD_BINDING.new())
	if is_instance_valid(pantyhose):
		var garment_binding: RefCounted = GARMENT_BINDING.new()
		garment_binding.call("setup", pantyhose)
		register_binding(garment_binding)
	if is_instance_valid(stock_smack):
		var smack_binding: RefCounted = SMACK_BINDING.new()
		smack_binding.call("setup", stock_smack)
		register_binding(smack_binding)


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
	_untrack_source(typed)
	_sources.erase(typed)


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


## True when any registered provider is active, for the debug gates.
func active() -> bool:
	for source: BODY_CHANGE_SOURCE in _sources:
		if is_instance_valid(source) and source.is_active():
			return true
	return false


## A world entered: re-read every provider's own installation state. The providers own their gates.
func on_world(_host: Node) -> void:
	for source: BODY_CHANGE_SOURCE in _sources:
		if is_instance_valid(source):
			source.refresh()


## Every installed character id, deduplicated, in registration order.
func installed_character_ids() -> Array[String]:
	var out: Array[String] = []
	for source: BODY_CHANGE_SOURCE in _sources:
		if not is_instance_valid(source) or not source.is_active():
			continue
		for raw: String in source.installed_character_ids():
			var id := raw.strip_edges()
			if not id.is_empty() and not out.has(id):
				out.append(id)
	return out


## True when the body's handling provider owns a tail placement.
func has_tail_placement(body: Node3D) -> bool:
	var source := source_for(body)
	return source != null and source.has_tail_placement(body)


## Re-apply the handling provider's current tail placement.
func apply_tail_placement(body: Node3D) -> void:
	var source := source_for(body)
	if source != null:
		source.apply_tail_placement(body)


## Every active provider's live source-owned tail lines.
func tail_placement_report() -> String:
	var lines := PackedStringArray()
	for source: BODY_CHANGE_SOURCE in _sources:
		if not is_instance_valid(source) or not source.is_active():
			continue
		var text := source.tail_placement_report().strip_edges()
		if not text.is_empty():
			lines.append(text)
	return "\n".join(lines)


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


## The active change for one presented body, or null. The provider observes its pack and pushes;
## the runtime's act watcher reads this value at its own cadence.
func active_change_for(body: Node3D) -> BODY_CHANGE:
	if not is_instance_valid(body):
		return null
	var stored: Variant = _active_by_body.get(body)
	if stored is BODY_CHANGE and _is_live_change(stored):
		return stored
	# A typed field can fill without a notification; a miss here is not per frame.
	for change: BODY_CHANGE in _active_by_source.values():
		if _is_live_change(change) and (change.previous_body == body or change.next_body == body):
			return change
	return null


## Compatibility read for diagnostics and tests; the runtime uses `active_change_for()`.
func active_change() -> BODY_CHANGE:
	for source: BODY_CHANGE_SOURCE in _sources:
		var stored: Variant = _active_by_source.get(source)
		if stored is BODY_CHANGE and _is_live_change(stored):
			return stored
	return null


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
	form.body_scale = _valid_scale(form.body_scale)
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
		# The seat's own exiting hook only covers its tree life; an explicit unbind that keeps the
		# body is the binding's call.
		body.tree_exiting.connect(_unbind_on_exit.bind(body), CONNECT_ONE_SHOT)
		_notify_bind(body, form)
	elif action == "refresh":
		_notify_refresh(body, form)


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
	_prune_body_change(body)


## The provider reports that its own observed state changed. Only a registered source may move the
## active-change maps; an unknown source cannot inject one. A settled or failed change is cleared.
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
	if change == null:
		var stored: Variant = _active_by_source.get(source)
		if stored is BODY_CHANGE:
			change = stored
	if change != null and change.source == null:
		change.source = source
	var live := change != null and _is_live_change(change)
	var owns := false
	if live and change.next_body == null and body != change.previous_body:
		owns = true
	elif live and change.next_body == body:
		owns = true
	elif live and change.next_body == null and body == change.previous_body \
			and change.state == BODY_CHANGE.State.ADOPTED:
		# Same-node in-place revision: the presented body is both the old and the new one.
		owns = true
	elif change != null and change.next_body == body:
		# The provider finished before the spawn hook: keep the late body's form on the change.
		owns = true
	elif change != null and not live:
		# A completed change stays a read-only record; an unrelated body never rewrites it.
		change = null
	if change != null and owns and change.state == BODY_CHANGE.State.REQUESTED:
		change.state = BODY_CHANGE.State.PREPARING
	var form := source.prepare_body(body, change)
	if form == null:
		return
	if change != null and owns:
		change.next_body = body
		change.form = form
		if live:
			change.state = BODY_CHANGE.State.ADOPTED
	apply_form(body, form)
	if live and owns:
		_track_change(source, change)


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
	_track_change(source, source.active_change())


## Store one live change for its provider and index it by both presented bodies. A terminal change
## clears the provider's entry instead; a change that claims another source is refused.
func _track_change(source: BODY_CHANGE_SOURCE, change: BODY_CHANGE) -> void:
	if change == null or not _is_live_change(change):
		_untrack_source(source)
		return
	if change.source == null:
		change.source = source
	elif change.source != source:
		return
	_untrack_source(source)
	_active_by_source[source] = change
	_index_change(change)


func _untrack_source(source: BODY_CHANGE_SOURCE) -> void:
	var stored: Variant = _active_by_source.get(source)
	if stored is BODY_CHANGE:
		_drop_body_index(stored)
	_active_by_source.erase(source)


func _untrack_change(change: BODY_CHANGE) -> void:
	for source: Variant in _active_by_source.keys():
		if _active_by_source[source] == change:
			_active_by_source.erase(source)
	_drop_body_index(change)


func _index_change(change: BODY_CHANGE) -> void:
	# The pack may free the old body before the new body's ready hook runs. `is_instance_valid`
	# must gate the typed call: a freed Node3D argument fails before the callee can test it.
	if is_instance_valid(change.previous_body):
		_index_body(change.previous_body, change)
	if is_instance_valid(change.next_body):
		_index_body(change.next_body, change)


## A body keeps the change it already has while that change is live; a second provider cannot
## overwrite an act's change with an idle one for the same body.
func _index_body(body: Node3D, change: BODY_CHANGE) -> void:
	if not is_instance_valid(body) or not _is_live_change(change):
		return
	var existing: Variant = _active_by_body.get(body)
	if existing is BODY_CHANGE and existing != change and _is_live_change(existing):
		return
	_active_by_body[body] = change


func _drop_body_index(change: BODY_CHANGE) -> void:
	for body: Variant in _active_by_body.keys():
		if _active_by_body[body] == change:
			_active_by_body.erase(body)


func _prune_body_change(body: Node3D) -> void:
	var stored: Variant = _active_by_body.get(body)
	if not stored is BODY_CHANGE:
		return
	var change: BODY_CHANGE = stored
	_active_by_body.erase(body)
	if change.next_body == body:
		_untrack_change(change)
	elif change.previous_body == body and not is_instance_valid(change.next_body):
		_untrack_change(change)


static func _is_live_change(change: BODY_CHANGE) -> bool:
	return change != null and (change.state == BODY_CHANGE.State.REQUESTED
		or change.state == BODY_CHANGE.State.PREPARING
		or change.state == BODY_CHANGE.State.ADOPTED)


func _unbind_on_exit(body: Node3D) -> void:
	unbind_body(body)


## A provider scale that is not finite falls back to the body's ordinary scale; anything outside
## the game's clamp is the nearest value the capsule can take.
static func _valid_scale(value: float) -> float:
	if not is_finite(value):
		return 1.0
	return clampf(value, BODY_SCALE_MIN, BODY_SCALE_MAX)


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
