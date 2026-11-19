extends Node
## The anatomy system's world facade. One world service owns the per-pony controllers, the
## player part, the tail seating and the placement editor delegate. Other systems call this facade,
## never a controller's internals.
##
## The per-pony controller is `anatomy/controller.gd`; it owns the per-act handle
## `anatomy/act.gd`.
##
## See `docs/anatomy.md`.

const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const CONTROLLER := preload("res://mods/unfplap/anatomy/controller.gd")
const ACT_BRIDGE := preload("res://mods/unfplap/anatomy/act_bridge.gd")
const PLAYER := preload("res://mods/unfplap/anatomy/player.gd")
const TAIL_SEAT := preload("res://mods/unfplap/anatomy/tail/seat.gd")
const TAIL_VISIBILITY := preload("res://mods/unfplap/anatomy/tail/visibility.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const FACTS := preload("res://mods/unfplap/anatomy/facts.gd")
const PLACEMENT_EDITOR := preload("res://mods/unfplap/anatomy/placement_editor.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const GARMENT_HULL := preload("res://mods/unfplap/anatomy/garment_hull.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")
const HUD := preload("res://mods/unfplap/hud/service.gd")

## Emitted when a pony's per-act anatomy handle is built, before the pose starts. A world
## integration uses it to take a worn garment off before the first rendered act frame.
signal act_started(pony: Node3D)

var player: Node
var tail_seat: Node
var tail_visibility: Node
## The Anatomy Placement editor. The facade keeps the debug entry points and delegates here.
var placement_editor: RefCounted

## pony -> controller
var _controllers: Dictionary = {}
## Presented body -> the body-change service's form. A body with no stored form keeps the default
## own form built from its identity.
var _forms: Dictionary = {}
var _player_part: Node
## The part whose hidden mesh is already built, and whether a deferred warm is queued.
var _player_warm_part: Node = null
var _player_warm_queued := false


func setup() -> void:
	placement_editor = PLACEMENT_EDITOR.new()
	placement_editor.setup(self)
	tail_visibility = TAIL_VISIBILITY.new()
	tail_visibility.name = "UnfplapTailVisibility"
	add_child(tail_visibility)
	tail_seat = TAIL_SEAT.new()
	tail_seat.name = "UnfplapTailSeat"
	var perf_call := func() -> bool:
		return LOG.debug_perf
	var log_call := func(text: String) -> void:
		LOG.debug(text)
	var eligible_tail := func(pony_node: Node) -> bool:
		return _eligible_target(pony_node, ELIGIBILITY.Target.TAIL)
	tail_seat.set("perf_on", perf_call)
	tail_seat.set("log", log_call)
	tail_seat.set("eligible", eligible_tail)
	add_child(tail_seat)
	CHANGE.on_changed(Callable(self, "apply_settings"))


## Host consent lookup for the act's V/N actions. The facade is the scene adapter; the act
## receives this as a callback.
func consent(pony_node: Node, key: String) -> bool:
	if not is_instance_valid(WORLD.game) or not is_instance_valid(pony_node):
		return false
	var service: ELIGIBILITY = PONIES.eligibility
	if service == null:
		return false
	var id := CONTROLLER.pony_id(pony_node)
	if id.is_empty():
		return false
	var profile := service.get_profile(id)
	match key:
		"public":
			return profile.consent.public
		"anal":
			return profile.consent.anal
		"oral":
			return profile.consent.oral
		_:
			return false


## HUD status line for the anatomy actions.
func status(text: String) -> void:
	HUD.anatomy_status(text, 2.0)


## Host capability lookup. The eligibility service owns the rule; anatomy only names its target
## and never inspects identity or participation itself.
func _eligible_target(pony_node: Node, target: ELIGIBILITY.Target) -> bool:
	if not is_instance_valid(WORLD.game):
		return false
	var service: ELIGIBILITY = PONIES.eligibility
	if service == null:
		return false
	return service.eligible(pony_node, target)


## The live controller for a pony, created on first use. The runtime supplies its typed facts;
## the facade supplies the anatomy service and the host callbacks for the act handle. A controller
## created by a body binding before its runtime exists receives the runtime's facts here.
func controller_for(pony: Node, runtime: Node) -> Node:
	if not is_instance_valid(pony):
		return null
	var facts: Variant = null
	if is_instance_valid(runtime) and runtime.has_method("anatomy_facts"):
		facts = runtime.call("anatomy_facts")
	var existing: Variant = _controllers.get(pony)
	if is_instance_valid(existing):
		var known: Node = existing
		if facts != null:
			known.call("set_facts", facts)
		var stored: Variant = _forms.get(pony)
		if stored is BODY_FORM.BodyForm:
			known.call("set_form", stored)
		return known
	if facts == null:
		facts = FACTS.new()
	var controller: Node = CONTROLLER.new()
	controller.name = "UnfplapAnatomyController"
	add_child(controller)
	var eligible_anatomy := func(pony_node: Node) -> bool:
		return _eligible_target(pony_node, ELIGIBILITY.Target.ANATOMY)
	var consent_for := func(key: String) -> bool:
		return consent(pony, key)
	controller.call("setup", pony, facts, self, consent_for,
		Callable(self, "status"), Callable(self, "refresh_dock_color"), eligible_anatomy)
	var stored: Variant = _forms.get(pony)
	if stored is BODY_FORM.BodyForm:
		controller.call("set_form", stored)
	_controllers[pony] = controller
	_push_part()
	pony.tree_exiting.connect(func() -> void:
		detach_controller(pony)
		_forms.erase(pony))
	return controller


func bind(pony: Node, runtime: Node) -> Node:
	return controller_for(pony, runtime)


## The form the body-change service applied to this body, or null when it only has the default own
## form. The tail seat uses it to resolve the fit before it measures the tail.
func form_for(pony: Node) -> BODY_FORM.BodyForm:
	var stored: Variant = _forms.get(pony)
	return stored as BODY_FORM.BodyForm if stored is BODY_FORM.BodyForm else null


## A new presented body's form: store it, make sure its controller exists and refresh the tail
## seat's row. The body-change service calls this before `tail_ready` and before the runtime
## attaches, so the anatomy and tail measure the form that is already on the body.
func bind_body(pony: Node3D, form: BODY_FORM.BodyForm) -> void:
	_apply_body_form(pony, form)


## The same body carries a revised form: update its controller and tail row without creating a
## second controller.
func refresh_body(pony: Node3D, form: BODY_FORM.BodyForm) -> void:
	_apply_body_form(pony, form)


## One write path for a body's form: the controller reads a new body's stored form when it is
## created, and an existing controller is refreshed once. The tail row follows the same call.
func _apply_body_form(pony: Node3D, form: BODY_FORM.BodyForm) -> void:
	if not is_instance_valid(pony) or form == null:
		return
	_forms[pony] = form
	var known := controller(pony)
	if is_instance_valid(known):
		known.call("refresh_form", form)
	else:
		controller_for(pony, null)
	if is_instance_valid(tail_seat):
		tail_seat.call("refresh_form", pony, form)


## The body is leaving: release its tail seat row here instead of waiting for the node's
## tree-exiting hook, then drop its form and controller. A body that stays in the tree must not
## keep the old fit's seated tail.
func unbind_body(pony: Node3D) -> void:
	if not is_instance_valid(pony):
		return
	if is_instance_valid(tail_seat):
		tail_seat.call("release", pony)
	_forms.erase(pony)
	detach_controller(pony)


## One act's anatomy bridge. The runtime creates one per act and binds the host callbacks.
static func new_act(host: Dictionary) -> RefCounted:
	var bridge: RefCounted = ACT_BRIDGE.new()
	bridge.bind(host)
	return bridge


func controller(pony: Node) -> Node:
	var value: Variant = _controllers.get(pony)
	return value if is_instance_valid(value) else null


## The controller tells the facade that an act handle was built; the facade re-emits it for the
## world integrations. The controller never emits on its own node, so the signal has one owner.
func note_act_started(pony_node: Node3D) -> void:
	act_started.emit(pony_node)


## The worn-garment depth field for a pony, or null when the anatomy is absent.
func garment_hull(pony_node: Node) -> GARMENT_HULL.Hull:
	var handle := controller(pony_node)
	if not is_instance_valid(handle) or not handle.has_method("garment_hull"):
		return null
	var value: Variant = handle.call("garment_hull")
	if value is GARMENT_HULL.Hull:
		return value as GARMENT_HULL.Hull
	return null


## The anatomy-local to garment-model transform for a pony. Identity when the anatomy is absent.
func garment_transform(pony_node: Node) -> Transform3D:
	var handle := controller(pony_node)
	if not is_instance_valid(handle) or not handle.has_method("garment_transform"):
		return Transform3D.IDENTITY
	var value: Variant = handle.call("garment_transform")
	return value if value is Transform3D else Transform3D.IDENTITY


## Whether the anatomy mesh is attached and currently shown; a hidden far mesh or act-only
## hiding leaves the worn garment alone.
func garment_visible(pony_node: Node) -> bool:
	var handle := controller(pony_node)
	if not is_instance_valid(handle) or not handle.has_method("garment_visible"):
		return false
	return bool(handle.call("garment_visible"))


## The anatomy mesh the hull field lives in. The debug heatmap parents itself here so it
## follows the live bone transform without a per-frame write.
func garment_parent(pony_node: Node) -> Node3D:
	var handle := controller(pony_node)
	if not is_instance_valid(handle) or not handle.has_method("garment_parent"):
		return null
	var value: Variant = handle.call("garment_parent")
	if value is Node3D:
		return value as Node3D
	return null


## Clear the shared hull cache and every controller's cached field after a precision edit or the
## debug Rebuild button. The next `garment_hull()` read rebuilds once per source mesh; no
## per-frame work.
func garment_hull_rebuild() -> void:
	GARMENT_HULL.clear_cache()
	for pony: Variant in _controllers.keys():
		var handle: Variant = _controllers[pony]
		if is_instance_valid(handle) and handle.has_method("garment_hull_clear"):
			handle.call("garment_hull_clear")


## Re-read settings and identity for every live controller.
func refresh_all() -> void:
	for pony: Variant in _controllers.keys():
		if not is_instance_valid(pony):
			_controllers.erase(pony)
			continue
		var controller: Variant = _controllers[pony]
		if is_instance_valid(controller) and controller.has_method("refresh"):
			controller.call("refresh")
	if is_instance_valid(tail_visibility):
		tail_visibility.call("set_enabled", SETTINGS.debug_hide_tails.get_bool())


func apply_live() -> void:
	for pony: Variant in _controllers.keys():
		if not is_instance_valid(pony):
			_controllers.erase(pony)
			continue
		var controller: Variant = _controllers[pony]
		if is_instance_valid(controller) and controller.has_method("apply_live"):
			controller.call("apply_live")


func tail_ready(pony: Node) -> void:
	if not is_instance_valid(tail_seat) or not is_instance_valid(pony):
		return
	var form := form_for(pony)
	if form == null:
		form = BODY_FORM.default_form(pony)
	tail_seat.call("attach", pony, form)
	# A mod may finish its hair or dock a frame after the pony is ready; attach is idempotent.
	tail_seat.call_deferred("attach", pony, form)


func refresh_tails() -> void:
	if is_instance_valid(tail_seat):
		tail_seat.call("refresh_all")


## A settings edit: the player part and every live controller re-read their switches, then the
## tail seats rebuild against them.
func apply_settings() -> void:
	refresh_player()
	refresh_all()
	apply_live()
	player_apply_live()
	refresh_tails()


func refresh_dock_color(pony: Node) -> void:
	if is_instance_valid(tail_seat):
		tail_seat.call("refresh_dock_color", pony)


func can_seat(pony: Node) -> bool:
	return is_instance_valid(tail_seat) and bool(tail_seat.call("can_seat", pony))


## True when a tail placement action can move this pony: a regular seat or a source-owned tail.
func can_place_tail(pony: Node) -> bool:
	if can_seat(pony):
		return true
	var change: Node = PONIES.body_change
	return is_instance_valid(change) and bool(change.call("has_tail_placement", pony))


## True when this pony has a dock the placement controls can move.
func can_dock(pony: Node) -> bool:
	return is_instance_valid(tail_seat) and bool(tail_seat.call("can_dock", pony))


func tail_report() -> String:
	if not is_instance_valid(tail_seat):
		return ""
	return str(tail_seat.call("report_all"))


# --------------------------------------------------------------------------- placement editor

func placement_debug(op: String, value := 0.0) -> String:
	return placement_editor.placement_debug(op, value)


func placement_show() -> String:
	return placement_editor.placement_show()


func detach_controller(pony: Node) -> void:
	var controller: Variant = _controllers.get(pony)
	_controllers.erase(pony)
	if not is_instance_valid(controller):
		return
	controller.call("detach")
	controller.queue_free()


func shutdown() -> void:
	CHANGE.off_changed(Callable(self, "apply_settings"))
	for pony: Variant in _controllers.keys():
		if is_instance_valid(pony):
			var controller: Variant = _controllers[pony]
			if is_instance_valid(controller):
				controller.call("detach")
				controller.queue_free()
	_controllers.clear()
	_forms.clear()
	on_world_closed()
	tail_seat = null
	tail_visibility = null
	placement_editor = null


# --------------------------------------------------------------------------- player part

## The player rig arrived.
func on_player(body: Node) -> void:
	if player != body:
		_player_warm_part = null
		_player_warm_queued = false
	player = body
	refresh_player()


## A world enter or a world close: the player part belongs to the world that is gone.
func on_world_closed() -> void:
	if is_instance_valid(_player_part):
		_player_part.call("encounter", false)
		_player_part.queue_free()
	_player_part = null
	_player_warm_part = null
	_player_warm_queued = false
	player = null
	_push_part()


func refresh_player() -> void:
	var enabled := SETTINGS.anatomy_on() and is_instance_valid(player)
	if not enabled:
		if is_instance_valid(_player_part):
			_player_part.call("encounter", false)
			_player_part.queue_free()
			_player_part = null
		_player_warm_part = null
		_player_warm_queued = false
		_push_part()
		return
	if not is_instance_valid(_player_part):
		_player_part = PLAYER.new()
		_player_part.name = "UnfplapAnonPart"
		add_child(_player_part)
	_player_part.set("player_body", _player_body())
	if _player_part.has_method("apply_live"):
		_player_part.call("apply_live")
	_push_part()
	# The first standing offer needs the part's natural root. Build the hidden mesh now, under the
	# loading cover, instead of loading its scene, shader and textures inside the offer scan. The
	# gate keeps `player_prepare()` as the idempotent fallback when this body is not ready yet.
	_queue_player_warm()


func _queue_player_warm() -> void:
	if _player_warm_queued or not is_instance_valid(_player_part):
		return
	if is_instance_valid(_player_warm_part) and _player_warm_part == _player_part:
		return
	_player_warm_queued = true
	_warm_player_part.call_deferred()


func _warm_player_part() -> void:
	_player_warm_queued = false
	if not SETTINGS.anatomy_on() or not is_instance_valid(_player_part):
		return
	if bool(_player_part.call("prepare")):
		_player_warm_part = _player_part


## The Anon body the player part binds to. The facade resolves it; the part never reads the entry.
func _player_body() -> Node3D:
	if not is_instance_valid(player):
		return null
	var anon: Variant = (player as Node).find_child("AnonBody", true, false)
	if anon is Node3D:
		return anon as Node3D
	var body := WORLD.player_body()
	if body != null:
		return body
	return player as Node3D if player is Node3D else null


## Push the live part handle to every controller. The act reads it through its own anatomy, so
## the facade's part never becomes a second act dependency.
func _push_part() -> void:
	for pony: Variant in _controllers.keys():
		var handle: Variant = _controllers[pony]
		if is_instance_valid(handle) and handle.has_method("set_part"):
			handle.call("set_part", _player_part)


func player_encounter(on: bool) -> void:
	if is_instance_valid(_player_part):
		_player_part.call("encounter", on)


func player_showing() -> bool:
	return is_instance_valid(_player_part) and bool(_player_part.call("showing"))


func player_shaft_length_m() -> float:
	if not is_instance_valid(_player_part):
		return 0.0
	return float(_player_part.call("shaft_length_m"))


func player_prepare() -> bool:
	if not is_instance_valid(_player_part):
		return false
	return bool(_player_part.call("prepare"))


func player_root_now() -> Vector3:
	if not is_instance_valid(_player_part):
		return Vector3.INF
	var value: Variant = _player_part.call("root_now")
	return value if value is Vector3 and (value as Vector3).is_finite() else Vector3.INF


## The pivot without the pose's last Hips offset. The standing placement fit uses it, so a stale
## offset from an earlier body cannot look like a contact distance.
func player_root_natural() -> Vector3:
	if not is_instance_valid(_player_part):
		return Vector3.INF
	var value: Variant = _player_part.call("root_natural")
	return value if value is Vector3 and (value as Vector3).is_finite() else Vector3.INF


## Clear the part's pelvis handshake and smoothed penetration after a body swap or a re-anchor.
func player_reset_pelvis() -> void:
	if is_instance_valid(_player_part) and _player_part.has_method("reset_pelvis"):
		_player_part.call("reset_pelvis")


func player_hip_offset() -> Vector3:
	if not is_instance_valid(_player_part) or not bool(_player_part.call("showing")):
		return Vector3.ZERO
	var value: Variant = _player_part.call("hip_offset_wanted")
	return value if value is Vector3 and (value as Vector3).is_finite() else Vector3.ZERO


func player_note_hip_offset(offset: Vector3) -> void:
	if is_instance_valid(_player_part) and bool(_player_part.call("showing")):
		_player_part.set("hip_offset_applied", offset)


func player_debug_scale() -> Variant:
	if not is_instance_valid(_player_part) or not bool(_player_part.call("showing")):
		return null
	return _player_part.call("debug_scale")


func player_apply_live() -> void:
	if is_instance_valid(_player_part) and _player_part.has_method("apply_live"):
		_player_part.call("apply_live")


# --------------------------------------------------------------------------- static helpers

static func pony_id(pony_node: Node) -> String:
	return CONTROLLER.pony_id(pony_node)


static func body_profile(identity: Variant) -> Array:
	return CONTROLLER.body_profile(identity)


static func off_roster_ids(ids: Array[String], base_ids: Array) -> Array[String]:
	return CONTROLLER.off_roster_ids(ids, base_ids)
