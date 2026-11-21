extends "res://mods/unfplap/shared/service.gd"
## The anatomy system's world facade: controllers, the player part, tail seats and the
## placement editor. Other systems call this facade, never a controller's internals.
## The per-pony controller is `anatomy/controller.gd`; it owns the per-act handle `anatomy/act.gd`.
## See `docs/anatomy.md`.

const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const WORLD := preload("res://mods/unfplap/world/service.gd")
const CONTROLLER := preload("res://mods/unfplap/anatomy/controller.gd")
const ACT_BRIDGE := preload("res://mods/unfplap/anatomy/act_bridge.gd")
const ACT_HOST := preload("res://mods/unfplap/anatomy/act_host.gd")
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
const GAME := preload("res://mods/unfplap/world/game.gd")

## A per-act handle was built; a world integration can undress on it.
signal act_started(pony: Node3D)

var player: Node
var tail_seat: TAIL_SEAT
var tail_visibility: TAIL_VISIBILITY
## The Placement editor; the facade only delegates to it.
var placement_editor: PLACEMENT_EDITOR

## pony -> controller
var _controllers: Dictionary[Node, CONTROLLER] = {}
## Body -> its presented form; a body with none keeps the default own form.
var _forms: Dictionary[Node, BODY_FORM.BodyForm] = {}
var _player_part: PLAYER
## The part whose hidden mesh is already built, and whether a deferred warm is queued.
var _player_warm_part: PLAYER = null
var _player_warm_queued := false
## The world HUD the status line reports to; the entry passes it at setup.
var _hud: Node = null


func setup(hud: Node = null) -> void:
	_hud = hud
	placement_editor = PLACEMENT_EDITOR.new()
	placement_editor.setup(self)
	tail_visibility = TAIL_VISIBILITY.new()
	tail_visibility.name = "UnfplapTailVisibility"
	add_child(tail_visibility)
	tail_seat = TAIL_SEAT.new()
	tail_seat.name = "UnfplapTailSeat"
	var eligible_tail := func(pony_node: Node) -> bool:
		return _eligible_target(pony_node, ELIGIBILITY.Target.TAIL)
	tail_seat.eligible = eligible_tail
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
	if is_instance_valid(_hud):
		_hud.anatomy_status(text, 2.0)


## Host capability lookup. The eligibility service owns the rule; anatomy only names its target
## and never inspects identity or participation itself.
func _eligible_target(pony_node: Node, target: ELIGIBILITY.Target) -> bool:
	if not is_instance_valid(WORLD.game):
		return false
	var service: ELIGIBILITY = PONIES.eligibility
	if service == null:
		return false
	return service.eligible(pony_node, target)


## The live controller for a pony, created on first use with the runtime's typed facts.
## A controller a body binding created earlier receives them here.
func controller_for(pony_node: Node, runtime: Node) -> CONTROLLER:
	if not is_instance_valid(pony_node):
		return null
	var facts: FACTS
	if is_instance_valid(runtime):
		var session: Variant = runtime.get("act")
		if session != null:
			facts = session.anatomy_facts()
	var existing: CONTROLLER = _controllers.get(pony_node)
	if is_instance_valid(existing):
		if facts != null:
			existing.set_facts(facts)
		var stored: BODY_FORM.BodyForm = _forms.get(pony_node)
		if stored != null:
			existing.set_form(stored)
		return existing
	if facts == null:
		facts = FACTS.new()
	var controller := CONTROLLER.new()
	controller.name = "UnfplapAnatomyController"
	add_child(controller)
	var eligible_anatomy := func(pony: Node) -> bool:
		return _eligible_target(pony, ELIGIBILITY.Target.ANATOMY)
	var consent_for := func(key: String) -> bool:
		return consent(pony_node, key)
	controller.setup(pony_node, facts, self, consent_for,
		Callable(self, "status"), Callable(self, "refresh_dock_color"), eligible_anatomy)
	var stored: BODY_FORM.BodyForm = _forms.get(pony_node)
	if stored != null:
		controller.set_form(stored)
	_controllers[pony_node] = controller
	_push_part()
	pony_node.tree_exiting.connect(func() -> void:
		detach_controller(pony_node)
		_forms.erase(pony_node))
	return controller


func bind(pony_node: Node, runtime: Node) -> CONTROLLER:
	return controller_for(pony_node, runtime)


## The form the body-change service applied to this body, or null when it only has the default own
## form. The tail seat uses it to resolve the fit before it measures the tail.
func form_for(pony_node: Node) -> BODY_FORM.BodyForm:
	var stored: BODY_FORM.BodyForm = _forms.get(pony_node)
	return stored


## A new presented body's form: store it, ensure its controller and refresh the tail row.
## The body-change service calls this before the runtime attaches, so both measure the real form.
func bind_body(pony_node: Node3D, form: BODY_FORM.BodyForm) -> void:
	_apply_body_form(pony_node, form)


## The same body carries a revised form: update its controller and tail row without creating a
## second controller.
func refresh_body(pony_node: Node3D, form: BODY_FORM.BodyForm) -> void:
	_apply_body_form(pony_node, form)


## One write path for a body's form: the controller reads a new body's stored form when it is
## created, and an existing controller is refreshed once. The tail row follows the same call.
func _apply_body_form(pony_node: Node3D, form: BODY_FORM.BodyForm) -> void:
	if not is_instance_valid(pony_node) or form == null:
		return
	_forms[pony_node] = form
	var known := controller(pony_node)
	if is_instance_valid(known):
		known.refresh_form(form)
	else:
		controller_for(pony_node, null)
	if is_instance_valid(tail_seat):
		tail_seat.refresh_form(pony_node, form)


## The body is leaving: release its tail row here, then drop its form and controller.
## A body that outlives its fit must not keep the old seated tail.
func unbind_body(pony_node: Node3D) -> void:
	if not is_instance_valid(pony_node):
		return
	if is_instance_valid(tail_seat):
		tail_seat.release(pony_node)
	_forms.erase(pony_node)
	detach_controller(pony_node)


## One act's anatomy bridge. The runtime creates one per act and binds the host callbacks.
static func new_act(host: ACT_HOST) -> ACT_BRIDGE:
	var bridge := ACT_BRIDGE.new()
	bridge.bind(host)
	return bridge


func controller(pony_node: Node) -> CONTROLLER:
	var value: CONTROLLER = _controllers.get(pony_node)
	return value if is_instance_valid(value) else null


## The controller tells the facade that an act handle was built; the facade re-emits it for the
## world integrations. The controller never emits on its own node, so the signal has one owner.
func note_act_started(pony_node: Node3D) -> void:
	act_started.emit(pony_node)


## The worn-garment depth field for a pony, or null when the anatomy is absent.
func garment_hull(pony_node: Node) -> GARMENT_HULL.Hull:
	var handle := controller(pony_node)
	if not is_instance_valid(handle):
		return null
	return handle.garment_hull()


## The anatomy-local to garment-model transform for a pony. Identity when the anatomy is absent.
func garment_transform(pony_node: Node) -> Transform3D:
	var handle := controller(pony_node)
	if not is_instance_valid(handle):
		return Transform3D.IDENTITY
	return handle.garment_transform()


## Whether the anatomy mesh is attached and currently shown; a hidden far mesh or act-only
## hiding leaves the worn garment alone.
func garment_visible(pony_node: Node) -> bool:
	var handle := controller(pony_node)
	if not is_instance_valid(handle):
		return false
	return handle.garment_visible()


## The anatomy mesh the hull field lives in. The debug heatmap parents itself here so it
## follows the live bone transform without a per-frame write.
func garment_parent(pony_node: Node) -> Node3D:
	var handle := controller(pony_node)
	if not is_instance_valid(handle):
		return null
	return handle.garment_parent()


## Clear the shared hull cache and every controller's cached field; the next read rebuilds once.
func garment_hull_rebuild() -> void:
	GARMENT_HULL.clear_cache()
	for handle: CONTROLLER in _controllers.values():
		if is_instance_valid(handle):
			handle.garment_hull_clear()


## Re-read settings and identity for every live controller.
func refresh_all() -> void:
	for pony: Node in _controllers.keys():
		if not is_instance_valid(pony):
			_controllers.erase(pony)
			continue
		var controller: CONTROLLER = _controllers[pony]
		if is_instance_valid(controller):
			controller.refresh()
	if is_instance_valid(tail_visibility):
		tail_visibility.set_enabled(SETTINGS.debug_hide_tails.get_bool())


func apply_live() -> void:
	for pony: Node in _controllers.keys():
		if not is_instance_valid(pony):
			_controllers.erase(pony)
			continue
		var controller: CONTROLLER = _controllers[pony]
		if is_instance_valid(controller):
			controller.apply_live()


func tail_ready(pony_node: Node) -> void:
	if not is_instance_valid(tail_seat) or not is_instance_valid(pony_node):
		return
	var form := form_for(pony_node)
	if form == null:
		form = BODY_FORM.default_form(pony_node)
	tail_seat.attach(pony_node, form)
	# A mod may finish its hair or dock a frame after the pony is ready; attach is idempotent.
	tail_seat.attach.call_deferred(pony_node, form)


func refresh_tails() -> void:
	if is_instance_valid(tail_seat):
		tail_seat.refresh_all()


## A settings edit: the player part and every live controller re-read their switches, then the
## tail seats rebuild against them.
func apply_settings() -> void:
	refresh_player()
	refresh_all()
	apply_live()
	player_apply_live()
	refresh_tails()


func refresh_dock_color(pony_node: Node) -> void:
	if is_instance_valid(tail_seat):
		tail_seat.refresh_dock_color(pony_node)


func can_seat(pony_node: Node) -> bool:
	return is_instance_valid(tail_seat) and tail_seat.can_seat(pony_node)


## True when a tail placement action can move this pony: a regular seat or a source-owned tail.
func can_place_tail(pony_node: Node) -> bool:
	if can_seat(pony_node):
		return true
	var change := PONIES.body_change
	return is_instance_valid(change) and bool(change.has_tail_placement(pony_node))


## True when this pony has a dock the placement controls can move.
func can_dock(pony_node: Node) -> bool:
	return is_instance_valid(tail_seat) and tail_seat.can_dock(pony_node)


func tail_report() -> String:
	if not is_instance_valid(tail_seat):
		return ""
	return tail_seat.report_all()


# --------------------------------------------------------------------------- placement editor

func placement_debug(op: String, value := 0.0) -> String:
	return placement_editor.placement_debug(op, value)


func placement_show() -> String:
	return placement_editor.placement_show()


func detach_controller(pony_node: Node) -> void:
	var controller: CONTROLLER = _controllers.get(pony_node)
	_controllers.erase(pony_node)
	if not is_instance_valid(controller):
		return
	controller.detach()
	controller.queue_free()


func shutdown() -> void:
	CHANGE.off_changed(Callable(self, "apply_settings"))
	for pony: Node in _controllers.keys():
		if is_instance_valid(pony):
			var controller: CONTROLLER = _controllers[pony]
			if is_instance_valid(controller):
				controller.detach()
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


## A world enter or close: the player part dies with its world.
func on_world_closed() -> void:
	if is_instance_valid(_player_part):
		_player_part.encounter(false)
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
			_player_part.encounter(false)
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
	_player_part.player_body = _player_body()
	_player_part.apply_live()
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
	if _player_part.prepare():
		_player_warm_part = _player_part


## The Anon body the player part binds to. The facade resolves it; the part never reads the entry.
func _player_body() -> Node3D:
	if not is_instance_valid(player):
		return null
	var anon := GAME.anon_body_of(player)
	if anon != null:
		return anon
	var body := WORLD.player_body()
	if body != null:
		return body
	return player as Node3D if player is Node3D else null


## Push the live part handle to every controller. The act reads it through its own anatomy, so
## the facade's part never becomes a second act dependency.
func _push_part() -> void:
	for handle: CONTROLLER in _controllers.values():
		if is_instance_valid(handle):
			handle.set_part(_player_part)


func player_encounter(on: bool) -> void:
	if is_instance_valid(_player_part):
		_player_part.encounter(on)


func player_showing() -> bool:
	return is_instance_valid(_player_part) and _player_part.showing()


func player_shaft_length_m() -> float:
	if not is_instance_valid(_player_part):
		return 0.0
	return _player_part.shaft_length_m()


func player_prepare() -> bool:
	if not is_instance_valid(_player_part):
		return false
	return _player_part.prepare()


func player_root_now() -> Vector3:
	if not is_instance_valid(_player_part):
		return Vector3.INF
	var value := _player_part.root_now()
	return value if value.is_finite() else Vector3.INF


## The pivot without the pose's last Hips offset. The standing placement fit uses it, so a stale
## offset from an earlier body cannot look like a contact distance.
func player_root_natural() -> Vector3:
	if not is_instance_valid(_player_part):
		return Vector3.INF
	var value := _player_part.root_natural()
	return value if value.is_finite() else Vector3.INF


## Clear the part's pelvis handshake and smoothed penetration after a body swap or a re-anchor.
func player_reset_pelvis() -> void:
	if is_instance_valid(_player_part):
		_player_part.reset_pelvis()


func player_hip_offset() -> Vector3:
	if not is_instance_valid(_player_part) or not _player_part.showing():
		return Vector3.ZERO
	var value := _player_part.hip_offset_wanted()
	return value if value.is_finite() else Vector3.ZERO


func player_note_hip_offset(offset: Vector3) -> void:
	if is_instance_valid(_player_part) and _player_part.showing():
		_player_part.hip_offset_applied = offset


func player_debug_scale() -> Vector3:
	if not is_instance_valid(_player_part) or not _player_part.showing():
		return Vector3.INF
	return _player_part.debug_scale()


func player_apply_live() -> void:
	if is_instance_valid(_player_part):
		_player_part.apply_live()


# --------------------------------------------------------------------------- static helpers

static func pony_id(pony_node: Node) -> String:
	return CONTROLLER.pony_id(pony_node)


static func body_profile(identity: Resource) -> Array[float]:
	return CONTROLLER.body_profile(identity)


static func off_roster_ids(ids: Array[String], base_ids: Array[String]) -> Array[String]:
	return CONTROLLER.off_roster_ids(ids, base_ids)
