extends "res://mods/unfplap/shared/service.gd"
## Service: anatomy
## Contract: docs/anatomy.md
## Scope: world + per-act handles
## Import: anatomy/api.gd only
## The anatomy presentation service: roster verbs, act presentation, tail seat and the player part.

const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CHANGE := preload("res://mods/unfplap/shared/settings_change.gd")
const BODY_FORM := preload("res://mods/unfplap/shared/body_form.gd")
const GARMENT_HULL := preload("res://mods/unfplap/anatomy/garment_hull.gd")
const RIG := preload("res://mods/unfplap/anatomy/rig.gd")
const PARTS := preload("res://mods/unfplap/anatomy/parts.gd")
const CONTROLLER := preload("res://mods/unfplap/anatomy/controller.gd")
const ACT := preload("res://mods/unfplap/anatomy/act.gd")

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
	var _pony: Node3D
	var _ended_cb: Callable
	var _view: Variant = null
	var _stage: Variant = null
	var _bed_frame: Variant = null
	var _target := Target.VULVA
	var _ended := false
	var _climaxed := false

	func _init(controller: CONTROLLER, act: ACT, view: Variant, bed_frame: Variant,
			ended_cb: Callable) -> void:
		_controller = controller
		_act = act
		_pony = controller.pony if is_instance_valid(controller) else null
		_view = view
		_bed_frame = bed_frame
		_ended_cb = ended_cb
		if _act != null:
			_act.set_view(view)

	func pose(view: Variant) -> void:
		if _ended or view == null:
			return
		_view = view
		_bed_frame = view.bed_frame if view.bed_frame is Transform3D else _bed_frame
		if _act != null:
			_act.set_view(view)
		_controller.set_act_view(view, _stage, _bed_frame)
		if _target == Target.MOUTH and str(view.contact_kind) != "mouth":
			_target = Target.VULVA

	func stage(delta: float, stage: Variant) -> void:
		if _ended or _act == null:
			return
		_stage = stage
		if _view != null and _view.bed_frame is Transform3D:
			_bed_frame = _view.bed_frame
		_act.set_stage(stage)
		_controller.set_act_view(_view, stage, _bed_frame)
		_act.stage(delta, stage)

	func climax() -> void:
		if _ended or _act == null:
			return
		_climaxed = true
		_act.set_climaxed(true)
		_act.climax()

	func end() -> void:
		if _ended:
			return
		_ended = true
		if is_instance_valid(_controller):
			_controller.end_act()
		_act = null
		if _ended_cb.is_valid():
			_ended_cb.call()

	func _phase() -> int:
		return int(_stage.phase) if _stage != null else -1

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

	func can_target_anus() -> bool:
		return can_target_vulva()

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
		if _ended or not can_target_anus():
			return
		_target = Target.ANUS
		if _act != null:
			_act.set_anal(true)

	func target_mouth() -> void:
		if _ended or not can_target_mouth() or _contact() != "mouth":
			return
		_target = Target.MOUTH

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
	const PLAYER_HOST := preload("res://mods/unfplap/anatomy/player_host.gd")

	var _host: PLAYER_HOST

	func _init(host: PLAYER_HOST) -> void:
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

var rig: RIG
var parts: PARTS
var _player: Node = null


func _ready() -> void:
	rig = RIG.new()
	parts = PARTS.new()
	parts.setup(self, rig)
	CHANGE.on_changed(Callable(self, "_on_settings_changed"))


# --------------------------------------------------------------------------- roster

## Idempotent. A null form means the pony's own default form.
func present(pony: Node3D, form: BODY_FORM.BodyForm = null) -> void:
	if not is_instance_valid(pony) or parts == null:
		return
	parts.present(pony, form, Callable(self, "_emit_status"))
	parts.push_part()


## Idempotent. Releases the controller, tail row and form.
func withdraw(pony: Node3D) -> void:
	if is_instance_valid(pony) and parts != null:
		parts.withdraw(pony)


## A revised form on the same body: refresh what already exists, never add a controller.
func body_changed(pony: Node3D, form: BODY_FORM.BodyForm = null) -> void:
	if not is_instance_valid(pony) or parts == null:
		return
	if not is_instance_valid(parts.controller(pony)):
		return
	parts.present(pony, form, Callable(self, "_emit_status"))


## Idempotent. A null form means the pony's own default.
func reseat_tail(pony: Node3D, form: BODY_FORM.BodyForm = null) -> void:
	if is_instance_valid(pony) and parts != null:
		parts.reseat_tail(pony, form)


## Idempotent. Releases only the tail row.
func withdraw_tail(pony: Node3D) -> void:
	if is_instance_valid(pony) and parts != null:
		parts.withdraw_tail(pony)


# --------------------------------------------------------------------------- act

## Null when the roster has not presented her; the returned handle owns its own close.
func begin_act(pony: Node3D, view: PoseView, bed_frame: Variant) -> ActPresentation:
	if parts == null:
		return null
	var controller := parts.controller(pony)
	if not is_instance_valid(controller):
		return null
	var act := controller.begin_act(view, bed_frame)
	if act == null:
		return null
	return ActPresentation.new(controller, act, view, bed_frame,
		Callable(self, "_on_act_ended").bind(pony))


# --------------------------------------------------------------------------- anon / stool

## Always returns a handle; its methods no-op when the part is absent.
func anon(_pony: Node3D) -> AnonBody:
	return AnonBody.new(parts.player_host if parts != null else null)


## World-space vulva point at hole mix 0; INF when absent.
func entrance_point(pony: Node3D) -> Vector3:
	if parts == null:
		return Vector3.INF
	var controller := parts.controller(pony)
	if not is_instance_valid(controller) or not controller.is_attached():
		return Vector3.INF
	var value := controller.entrance_point()
	return value if value.is_finite() else Vector3.INF


# --------------------------------------------------------------------------- estrus

## Idle wink only; no-op when absent or an act is presented.
func wink(pony: Node3D, beats: int) -> void:
	if parts == null:
		return
	var controller := parts.controller(pony)
	if not is_instance_valid(controller) or controller.act_presented:
		return
	controller.wink_burst(beats)


## Idle resting openness; no-op when absent or an act is presented.
func rest(pony: Node3D, open: float) -> void:
	if parts == null:
		return
	var controller := parts.controller(pony)
	if not is_instance_valid(controller) or controller.act_presented:
		return
	controller.set_rest(open)


# --------------------------------------------------------------------------- garment

## Always returns a handle; a detached controller answers null, identity, null and false.
func garment(pony: Node3D) -> Garment:
	return Garment.new(parts.controller(pony) if parts != null else null)


## Clear the shared hull cache; the next `hull()` rebuilds once.
func rebuild_garment() -> void:
	if parts == null:
		return
	GARMENT_HULL.clear_cache()
	for handle: CONTROLLER in parts.controllers.values():
		if is_instance_valid(handle):
			handle.garment_hull_clear()


# --------------------------------------------------------------------------- body coat

## Idempotent and cheap: register the current and future coat/outline materials with the flank.
func follow_body_coat(pony: Node3D, flank: Node) -> bool:
	if parts == null or not is_instance_valid(flank):
		return false
	var controller := parts.controller(pony)
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
	if parts == null or not is_instance_valid(parts.placement_editor):
		return ""
	return parts.placement_editor.placement_debug(pony, op, value, tail_owned)


func debug_show(pony: Node3D) -> String:
	if parts == null or not is_instance_valid(parts.placement_editor):
		return ""
	return parts.placement_editor.placement_show(pony)


func debug_anon_scale(_pony: Node3D) -> Vector3:
	if parts == null:
		return Vector3.INF
	return parts.player_host.debug_scale()


# --------------------------------------------------------------------------- lifecycle

func on_world(_host: Node) -> void:
	if parts != null:
		parts.refresh_all()
		parts.apply_live()
		parts.refresh_tails()


func on_world_closed() -> void:
	if parts != null:
		parts.player_host.on_world_closed()
		parts.push_part()
	_player = null


func on_player(body: Node) -> void:
	_player = body
	if parts == null:
		return
	parts.player_host.on_player(body)
	parts.push_part()


func shutdown() -> void:
	CHANGE.off_changed(Callable(self, "_on_settings_changed"))
	if parts != null:
		parts.clear()
		parts.player_host.on_world_closed()
	parts = null
	rig = null
	_player = null


func _on_settings_changed() -> void:
	if parts == null:
		return
	parts.player_host.refresh()
	parts.push_part()
	parts.refresh_all()
	parts.apply_live()
	parts.refresh_tails()


func _on_act_ended(_pony: Node3D) -> void:
	pass


func _emit_status(text: String, seconds := 2.0) -> void:
	status.emit(text, seconds)


func _refresh_dock_color(pony: Node) -> void:
	if parts != null:
		parts.refresh_dock_color(pony)
