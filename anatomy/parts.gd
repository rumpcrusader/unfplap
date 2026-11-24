extends RefCounted
## Keeps each presented body's controller and form, plus the shared tail and player pieces.
## The API constructs it; nothing else reaches into it.

const SETTINGS := preload("res://mods/unfplap/settings/api.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const CONTROLLER := preload("res://mods/unfplap/anatomy/controller.gd")
const PLAYER_HOST := preload("res://mods/unfplap/anatomy/player_host.gd")
const PLACEMENT_EDITOR := preload("res://mods/unfplap/anatomy/placement_editor.gd")
const RIG := preload("res://mods/unfplap/anatomy/rig.gd")
const TAIL_SEAT := preload("res://mods/unfplap/anatomy/tail/seat.gd")
const TAIL_VISIBILITY := preload("res://mods/unfplap/anatomy/tail/visibility.gd")

var owner: Node
var rig: RIG
var player_host: PLAYER_HOST
var tail_seat: TAIL_SEAT
var tail_visibility: TAIL_VISIBILITY
var placement_editor: PLACEMENT_EDITOR

## pony -> controller
var controllers: Dictionary[Node, CONTROLLER] = {}
## Body -> its presented form; a body with none keeps the default own form.
var forms: Dictionary[Node, BODY_FORM.BodyForm] = {}


func setup(owner_node: Node, rig_node: RIG) -> void:
	owner = owner_node
	rig = rig_node
	player_host = PLAYER_HOST.new()
	player_host.setup(owner, rig)
	tail_visibility = TAIL_VISIBILITY.new()
	tail_visibility.name = "UnfplapTailVisibility"
	tail_visibility.setup(rig)
	owner.add_child(tail_visibility)
	tail_seat = TAIL_SEAT.new()
	tail_seat.name = "UnfplapTailSeat"
	tail_seat.setup(rig)
	owner.add_child(tail_seat)
	placement_editor = PLACEMENT_EDITOR.new()
	placement_editor.setup(self, rig)


func controller(pony: Node) -> CONTROLLER:
	var value: CONTROLLER = controllers.get(pony)
	return value if is_instance_valid(value) else null


## Store the presented form; a null form resolves to the body's own.
func remember(pony: Node, form: BODY_FORM.BodyForm) -> BODY_FORM.BodyForm:
	if not is_instance_valid(pony):
		return null
	var stored: BODY_FORM.BodyForm = form if form != null else BODY_FORM.default_form(pony)
	forms[pony] = stored
	return stored


## Create or reuse the controller and its tail seat from the remembered form. The identity gate
## has already answered yes; a revised form on the same body updates both instead of adding one.
func attach(pony: Node3D, status: Callable) -> CONTROLLER:
	var stored := form_for(pony)
	if stored == null:
		return null
	var existing := controller(pony)
	if is_instance_valid(existing):
		existing.refresh_form(stored)
		existing.refresh()
		if is_instance_valid(tail_seat):
			tail_seat.refresh_form(pony, stored)
		return existing
	var fresh := CONTROLLER.new()
	fresh.name = "UnfplapAnatomyController"
	owner.add_child(fresh)
	fresh.setup(pony, stored, rig, status, Callable(owner, "_refresh_dock_color"))
	controllers[pony] = fresh
	fresh.refresh()
	fresh.set_part(player_host.part())
	if is_instance_valid(tail_seat):
		tail_seat.attach(pony, stored)
		_retry_tail.call_deferred(pony)
	pony.tree_exiting.connect(func() -> void: detach(pony))
	return fresh


## The controller and the tail row go; the remembered form stays for the next decision.
func release(pony: Node3D) -> void:
	if not is_instance_valid(pony):
		return
	if is_instance_valid(tail_seat):
		tail_seat.release(pony)
	var handle := controller(pony)
	controllers.erase(pony)
	if is_instance_valid(handle):
		handle.detach()
		handle.queue_free()


## The body is leaving, or the roster withdrew it: release everything and forget its form.
func detach(pony: Node3D) -> void:
	release(pony)
	forms.erase(pony)


## A mod may finish its hair or dock a frame after the pony is ready. The retry is idempotent and
## does nothing once the body is no longer presented.
func _retry_tail(pony: Node) -> void:
	if not is_instance_valid(pony) or not is_instance_valid(tail_seat) or not controllers.has(pony):
		return
	tail_seat.attach(pony, form_for(pony))


func form_for(pony: Node) -> BODY_FORM.BodyForm:
	var stored: BODY_FORM.BodyForm = forms.get(pony)
	return stored


## Hand the current Anon part to each live controller.
func push_part() -> void:
	var part = player_host.part() if player_host != null else null
	for handle: CONTROLLER in controllers.values():
		if is_instance_valid(handle):
			handle.set_part(part)


func refresh_all() -> void:
	for pony: Node in controllers.keys():
		var handle: CONTROLLER = controllers.get(pony)
		if not is_instance_valid(pony) or not is_instance_valid(handle):
			controllers.erase(pony)
			continue
		handle.refresh()
	if is_instance_valid(tail_visibility):
		tail_visibility.set_enabled(SETTINGS.debug_hide_tails.get_bool())


func apply_live() -> void:
	for pony: Node in controllers.keys():
		var handle: CONTROLLER = controllers.get(pony)
		if not is_instance_valid(pony) or not is_instance_valid(handle):
			controllers.erase(pony)
			continue
		handle.apply_live()


func refresh_tails() -> void:
	if is_instance_valid(tail_seat):
		tail_seat.refresh_all()


func refresh_dock_color(pony: Node) -> void:
	if is_instance_valid(tail_seat):
		tail_seat.refresh_dock_color(pony)


func tail_report() -> String:
	if not is_instance_valid(tail_seat):
		return ""
	return tail_seat.report_all()


func can_dock(pony: Node) -> bool:
	return is_instance_valid(tail_seat) and tail_seat.can_dock(pony)


func can_seat(pony: Node) -> bool:
	return is_instance_valid(tail_seat) and tail_seat.can_seat(pony)


func clear() -> void:
	var bodies: Array[Node] = []
	for pony: Node in controllers.keys():
		bodies.append(pony)
	for pony: Node in forms.keys():
		if not bodies.has(pony):
			bodies.append(pony)
	for pony: Node in bodies:
		detach(pony)
	controllers.clear()
	forms.clear()
