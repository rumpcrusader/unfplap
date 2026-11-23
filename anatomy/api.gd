extends "res://mods/unfplap/shared/service.gd"
## Service: anatomy
## Scope: world
## Contract: docs/anatomy.md
## The anatomy presentation service: roster verbs, act presentation, tail seat and the player part.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const GARMENT_HULL := preload("res://mods/unfplap/anatomy/garment_hull.gd")
const RIG := preload("res://mods/unfplap/anatomy/rig.gd")
const PARTS := preload("res://mods/unfplap/anatomy/parts.gd")
const CONTROLLER := preload("res://mods/unfplap/anatomy/controller.gd")
const ACT := preload("res://mods/unfplap/anatomy/act.gd")
const PLAYER_HOST := preload("res://mods/unfplap/anatomy/player_host.gd")

## The anatomy action status line. The entry connects it to the HUD.
signal status(text: String, seconds: float)

## The selected opening of a presented act.
enum Target { VULVA, ANUS, MOUTH }
## The act phase the stage carries.
enum Phase { POSING_IN, ACTIVE, CLIMAX, AFTERGLOW, RESTORE }

## The pose read model one act fills. The caller owns it and reuses it per change.
class PoseView extends RefCounted:
	var family := ""
	var frame := ""
	var contact_kind := ""
	var contact_target := Vector3.INF
	## Null outside a missionary act; the trims read it.
	var bed_frame: Variant = null

## The per-frame act values one act fills. The caller owns it and reuses it per tick.
class ActStage extends RefCounted:
	var phase := Phase.POSING_IN
	var depth := 0.0
	var penetration_m := 0.0
	var size_scale := 1.0

## One act's presentation handle. Its `end()` is the only teardown.
class ActPresentation extends RefCounted:
	var _controller: CONTROLLER
	var _act: ACT
	var _view: PoseView = null
	var _stage: ActStage = null
	var _target := Target.VULVA
	var _ended := false

	func _init(controller: CONTROLLER, act: ACT, view: PoseView) -> void:
		_controller = controller
		_act = act
		_view = view
		if _act != null:
			_act.set_view(view)

	func pose(view: PoseView) -> void:
		if _ended or view == null:
			return
		_view = view
		if _act != null:
			_act.set_view(view)
		_controller.set_act_view(view, _stage, view.bed_frame)
		if str(view.contact_kind) == "mouth":
			if can_target_mouth():
				_target = Target.MOUTH
		elif _target == Target.MOUTH:
			_target = Target.VULVA

	func stage(delta: float, stage: ActStage) -> void:
		if _ended or _act == null:
			return
		_stage = stage
		_act.set_stage(stage)
		_controller.set_act_view(_view, stage, _view.bed_frame if _view != null else null)
		_act.stage(delta, stage)

	func climax() -> void:
		if _ended or _act == null:
			return
		_act.set_climaxed(true)
		_act.climax()

	func end() -> void:
		if _ended:
			return
		_ended = true
		if is_instance_valid(_controller):
			_controller.end_act()
		_act = null

	func _phase() -> int:
		return _stage.phase if _stage != null else -1

	func _contact() -> String:
		return str(_view.contact_kind) if _view != null else ""

	func _family() -> String:
		return str(_view.family) if _view != null else ""

	func can_target_vulva() -> bool:
		if _ended or _phase() not in [Phase.ACTIVE, Phase.CLIMAX]:
			return false
		if not SETTINGS.anatomy_holes.get_bool():
			return false
		return _contact() not in ["mouth", "face"]

	func can_target_mouth() -> bool:
		if _ended or _phase() != Phase.ACTIVE:
			return false
		if not SETTINGS.anatomy_oral.get_bool() or _family() != "standing":
			return false
		return _contact() != "face"

	func target_vulva() -> void:
		if _ended or not can_target_vulva():
			return
		_target = Target.VULVA
		if _act != null:
			_act.set_anal(false)

	func target_anus() -> void:
		if _ended or not can_target_vulva():
			return
		_target = Target.ANUS
		if _act != null:
			_act.set_anal(true)

	func target() -> int:
		return _target

	func mouth_point() -> Vector3:
		if _ended or _act == null:
			return Vector3.ZERO
		var value := _act.oral_mouth_point()
		return value if value.is_finite() else Vector3.ZERO

	func hold_mouth() -> void:
		if not _ended and _act != null:
			_act.hold_oral_mouth()

	func set_mouth_viseme(letter: String) -> void:
		if not _ended and _act != null:
			_act.set_oral_viseme(letter)

	## The soft touch/kiss reaction on the persistent mesh.
	func react() -> void:
		if not _ended and is_instance_valid(_controller):
			_controller.react()

	func frame_point() -> Vector3:
		if _ended or _act == null:
			return Vector3.INF
		var value := _act.hole_point()
		return value if value.is_finite() else Vector3.INF

	func frame_axis() -> Vector3:
		if _ended or _act == null:
			return Vector3.ZERO
		var value := _act.opening_normal()
		return value if value.is_finite() and value.length_squared() > 0.000001 \
			else Vector3.ZERO

## The Anon part handle. Its methods are no-ops when the part is absent.
class AnonBody extends RefCounted:
	var _host: PLAYER_HOST

	func _init(host: PLAYER_HOST) -> void:
		_host = host

	## Repoint the shared handle at the live host; the handle is a view, not a snapshot.
	func _bind(host: PLAYER_HOST) -> void:
		_host = host

	func prepare() -> bool:
		return _host.prepare() if _host != null else false

	func showing() -> bool:
		return _host.showing() if _host != null else false

	func root_now() -> Vector3:
		return _host.root_now() if _host != null else Vector3.INF

	func shaft_length_m() -> float:
		return _host.shaft_length_m() if _host != null else 0.0

	func drive_hip(hip: Node3D) -> void:
		if _host != null:
			_host.drive_hip(hip)

	## The wanted pelvis offset, for the bed body's own spine solve.
	func hip_offset() -> Vector3:
		return _host.hip_offset() if _host != null else Vector3.ZERO

	## Record the offset the bed body applied, so next frame measures from the moved body.
	func note_hip_offset(offset: Vector3) -> void:
		if _host != null:
			_host.note_hip_offset(offset)

	## The visible part's world scale, for the act's diagnostic row.
	func debug_scale() -> Vector3:
		return _host.debug_scale() if _host != null else Vector3.INF

	func reset_pelvis() -> void:
		if _host != null:
			_host.reset_pelvis()

	func encounter(on: bool) -> void:
		if _host != null:
			_host.encounter(on)

## The worn-garment depth field handle. A missing anatomy answers null and identity.
class Garment extends RefCounted:
	var _controller: CONTROLLER

	func _init(controller: CONTROLLER) -> void:
		_controller = controller

	## Repoint the handle at the controller now presented for its pony.
	func _bind(controller: CONTROLLER) -> void:
		_controller = controller

	func hull() -> RefCounted:
		if not is_instance_valid(_controller):
			return null
		return _controller.garment_hull()

	func transform() -> Transform3D:
		if not is_instance_valid(_controller):
			return Transform3D.IDENTITY
		return _controller.garment_transform()

	func parent() -> Node3D:
		if not is_instance_valid(_controller):
			return null
		return _controller.garment_parent()

	func visible() -> bool:
		if not is_instance_valid(_controller):
			return false
		return _controller.garment_visible()

var _rig: RIG
var _parts: PARTS
## The identity gate the roster verbs ask; the entry hands it over once.
var _eligibility: ELIGIBILITY = null
var _anon: AnonBody = null
## pony -> its cached handle; a retained handle keeps its pony.
var _garments: Dictionary = {}


func _ready() -> void:
	_rig = RIG.new()
	_parts = PARTS.new()
	_parts.setup(self, _rig)
	CHANGE.on_changed(Callable(self, "_on_settings_changed"))


## The entry hands over the identity gate once; an unbound facade presents nothing.
func wire(eligibility: ELIGIBILITY) -> void:
	_eligibility = eligibility


# --------------------------------------------------------------------------- roster

## Idempotent. A null form means the pony's own default form. The identity gate lives here, so no
## caller can attach a controller or a tail to a body that is not an anatomy target.
func present(pony: Node3D, form: BODY_FORM.BodyForm = null) -> void:
	if not is_instance_valid(pony) or _parts == null:
		return
	_parts.remember(pony, form)
	if not _assigned(pony):
		_parts.release(pony)
		return
	_parts.attach(pony, Callable(self, "_emit_status"))


## Idempotent. Releases the controller, tail row and form.
func withdraw(pony: Node3D) -> void:
	if is_instance_valid(pony) and _parts != null:
		_parts.detach(pony)
		_garments.erase(pony)


## The one identity question these roster verbs ask.
func _assigned(pony: Node) -> bool:
	return _eligibility != null and is_instance_valid(_eligibility) \
		and _eligibility.eligible(pony, ELIGIBILITY.Target.ANATOMY)


# --------------------------------------------------------------------------- act

## Null when the roster has not presented her; the returned handle owns its own close.
func begin_act(pony: Node3D, view: PoseView) -> ActPresentation:
	if _parts == null:
		return null
	var controller := _parts.controller(pony)
	if not is_instance_valid(controller):
		return null
	var act := controller.begin_act(view, view.bed_frame)
	if act == null:
		return null
	return ActPresentation.new(controller, act, view)


# --------------------------------------------------------------------------- anon / stool

## Always returns a handle; its methods no-op when the part is absent.
func anon() -> AnonBody:
	if _anon == null:
		_anon = AnonBody.new(null)
	_anon._bind(_parts.player_host if _parts != null else null)
	return _anon


## World-space vulva point at hole mix 0; INF when absent.
func entrance_point(pony: Node3D) -> Vector3:
	if _parts == null:
		return Vector3.INF
	var controller := _parts.controller(pony)
	if not is_instance_valid(controller) or not controller.is_attached():
		return Vector3.INF
	var value := controller.entrance_point()
	return value if value.is_finite() else Vector3.INF


# --------------------------------------------------------------------------- estrus

## Idle wink only; no-op when absent or an act is presented.
func wink(pony: Node3D, beats: int) -> void:
	if _parts == null:
		return
	var controller := _parts.controller(pony)
	if not is_instance_valid(controller) or controller.act_presented:
		return
	controller.wink_burst(beats)


## Idle resting openness; no-op when absent or an act is presented.
func rest(pony: Node3D, open: float) -> void:
	if _parts == null:
		return
	var controller := _parts.controller(pony)
	if not is_instance_valid(controller) or controller.act_presented:
		return
	controller.set_rest(open)


# --------------------------------------------------------------------------- garment

## Always returns a handle; a detached controller answers null, identity, null and false.
func garment(pony: Node3D) -> Garment:
	if not is_instance_valid(pony):
		return Garment.new(null)
	var controller := _parts.controller(pony) if _parts != null else null
	var handle: Garment = _garments.get(pony) as Garment
	if handle == null:
		handle = Garment.new(controller)
		_garments[pony] = handle
	else:
		handle._bind(controller)
	return handle


## Clear the shared hull cache; the next `hull()` rebuilds once.
func rebuild_garment() -> void:
	if _parts == null:
		return
	GARMENT_HULL.clear_cache()
	for handle: CONTROLLER in _parts.controllers.values():
		if is_instance_valid(handle):
			handle.garment_hull_clear()


# --------------------------------------------------------------------------- body coat

## Idempotent and cheap: register the current and future coat/outline materials with the flank.
func follow_body_coat(pony: Node3D, flank: Node) -> bool:
	if _parts == null or not is_instance_valid(flank):
		return false
	var controller := _parts.controller(pony)
	if not is_instance_valid(controller) or not controller.is_attached():
		return false
	var targets: Variant = flank.get("_jiggle_targets")
	if not targets is Array:
		return false
	var pairs: Variant = controller.body_coat_targets()
	if pairs is Array and (pairs as Array).is_empty():
		controller.body_coat_refresh()
		pairs = controller.body_coat_targets()
	if pairs is Array and not (pairs as Array).is_empty():
		for pair: Variant in pairs as Array:
			if pair is Array and (pair as Array).size() >= 2 \
					and (pair as Array)[0] is ShaderMaterial \
					and (pair as Array)[1] is MeshInstance3D:
				_add_coat_target(targets as Array, (pair as Array)[0] as ShaderMaterial,
					(pair as Array)[1] as MeshInstance3D)
		return true
	var body: Variant = controller.body_coat_mesh()
	var material: Variant = controller.body_coat_material()
	if not body is MeshInstance3D or not material is ShaderMaterial:
		controller.body_coat_refresh()
		body = controller.body_coat_mesh()
		material = controller.body_coat_material()
	if not body is MeshInstance3D or not material is ShaderMaterial:
		return false
	_add_coat_target(targets as Array, material as ShaderMaterial, body as MeshInstance3D)
	var outline: Variant = controller.body_outline_material()
	if outline is ShaderMaterial:
		_add_coat_target(targets as Array, outline as ShaderMaterial, body as MeshInstance3D)
	return true


func _add_coat_target(targets: Array, material: ShaderMaterial, body: MeshInstance3D) -> void:
	for target: Variant in targets:
		if target is Array and not (target as Array).is_empty() \
				and (target as Array)[0] == material:
			return
	targets.append([material, body])


# --------------------------------------------------------------------------- debug

func debug_placement(pony: Node3D, op: String, value: float, tail_owned: bool) -> String:
	if _parts == null or not is_instance_valid(_parts.placement_editor):
		return ""
	return _parts.placement_editor.placement_debug(pony, op, value, tail_owned)


func debug_show(pony: Node3D) -> String:
	if _parts == null or not is_instance_valid(_parts.placement_editor):
		return ""
	return _parts.placement_editor.placement_show(pony)


# --------------------------------------------------------------------------- lifecycle

func on_world(_host: Node) -> void:
	if _parts != null:
		_parts.refresh_all()
		_parts.apply_live()
		_parts.refresh_tails()


func on_world_closed() -> void:
	if _parts != null:
		_parts.player_host.on_world_closed()
		_parts.push_part()
	_garments.clear()
	_anon = null


func on_player(body: Node) -> void:
	if _parts == null:
		return
	_parts.player_host.on_player(body)
	_parts.push_part()


func shutdown() -> void:
	CHANGE.off_changed(Callable(self, "_on_settings_changed"))
	if _parts != null:
		_parts.clear()
		_parts.player_host.on_world_closed()
	_parts = null
	_rig = null
	_garments.clear()
	_anon = null


func _on_settings_changed() -> void:
	if _parts == null:
		return
	# Re-ask the gate before the live refresh, so a body that lost the capability is released
	# before its controller would be refreshed.
	var ponies: Array = _parts.forms.keys()
	for value: Variant in ponies:
		if value is Node3D and is_instance_valid(value):
			_reconcile(value as Node3D)
	_parts.player_host.refresh()
	_parts.push_part()
	_parts.refresh_all()
	_parts.apply_live()
	_parts.refresh_tails()


## Re-attach or release one remembered body; the listener's single refresh pass covers survivors.
func _reconcile(pony: Node3D) -> void:
	if not _assigned(pony):
		_parts.release(pony)
	elif _parts.controller(pony) == null:
		_parts.attach(pony, Callable(self, "_emit_status"))


func _emit_status(text: String, seconds := 2.0) -> void:
	status.emit(text, seconds)


func _refresh_dock_color(pony: Node) -> void:
	if _parts != null:
		_parts.refresh_dock_color(pony)
