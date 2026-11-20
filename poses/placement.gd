extends RefCounted
## The standing act's placement: facing, act gap, floor probe, stool spot, whole-body fit and pelvis
## handshake. The runtime fills the live facts; this handle owns the math. Contract: `docs/poses.md`
## (`## Standing`).

const WORLD := preload("res://mods/unfplap/world/service.gd")
const PONIES := preload("res://mods/unfplap/ponies/service.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const ACT_CAMERA := preload("res://mods/unfplap/camera/service.gd")
const ELIGIBILITY := preload("res://mods/unfplap/eligibility/service.gd")

## The largest whole-body fit: past it the offer cone no longer matches her, and the hip offset is
## left to carry the rest.
const FIT_MAX_M := 0.6
const LOG := preload("res://mods/unfplap/shared/log.gd")


## The live scene values for one placement pass. The runtime writes them before each call; the
## handle never reads a runtime or the entry.
class Facts:
	var pony: Node = null
	var player: Node = null
	var bed: Node3D = null
	var stool: Variant = null
	## The form the caller asked to place. An empty call falls back to `body_form`.
	var form: Variant = null
	## The presented body's current form, used by the camera-rig transform.
	var body_form: Variant = null
	var id := ""
	var gaps: Dictionary = {}
	var camera: Variant = null
	var anatomy: Variant = null
	var player_pony := false
	var headset_view := false


## One call's act values, filled by the act session (their owner) and copied into the reused
## `Facts`. A start adapter and a body swap both place Anon from this same record.
class ActBind:
	var pony: Node = null
	var player: Node = null
	var bed: Node3D = null
	var stool: RefCounted = null
	var form: Variant = null
	var body_form: Variant = null
	var id := ""
	var gaps: Dictionary = {}
	var camera: Variant = null
	var anatomy: Variant = null
	var player_pony := false
	var headset_view := false

	## Fill from the act's live values. The act session owns them; the start adapter and the body
	## swap both place Anon from this one record.
	func fill(pony_node: Node, player_node: Node, bed_node: Node3D, stool_handle: RefCounted,
			asked_form: Variant, current_form: Variant, id_value: String, gaps_value: Dictionary,
			camera_handle: Variant, anatomy_handle: Variant, pony_player: bool,
			headset: bool) -> void:
		pony = pony_node
		player = player_node
		bed = bed_node
		stool = stool_handle
		form = asked_form
		body_form = current_form
		id = id_value
		gaps = gaps_value
		camera = camera_handle
		anatomy = anatomy_handle
		player_pony = pony_player
		headset_view = headset


## The one placement record this handle reuses, so a placement pass allocates no facts.
var facts := Facts.new()


func bind_act(values: ActBind) -> void:
	facts.pony = values.pony
	facts.player = values.player
	facts.bed = values.bed
	facts.stool = values.stool
	facts.form = values.form
	facts.body_form = values.body_form
	facts.id = values.id
	facts.gaps = values.gaps
	facts.camera = values.camera
	facts.anatomy = values.anatomy
	facts.player_pony = values.player_pony
	facts.headset_view = values.headset_view


## The start's standing placement from the last `bind_act()` values.
func begin_act() -> Transform3D:
	return begin(facts)


## Re-anchor the standing act from the last bound record after a body resume or form revision.
func reanchor_act(family: String) -> Variant:
	return reanchor(facts, family)


## The current bind's standing gap, with the entrance offset folded in.
func gap_act() -> float:
	return gap(facts)


func reset_pelvis_act() -> void:
	reset_pelvis(facts)


func new_body_is_adult_act() -> bool:
	return new_body_is_adult(facts)


## Place the standing start and return the facing transform. A headset or player-pony act puts her
## in front of the player, because she rides that rig; otherwise Anon stands behind her.
func begin(facts: Facts) -> Transform3D:
	var forward := _forward(facts)
	var standing := Transform3D(Basis.looking_at(forward, Vector3.UP), facts.pony.global_position)
	if facts.player_pony or facts.headset_view:
		if _stool_active(facts):
			facts.stool.set("failed", true)
		var placed: Transform3D = transform(facts) if _has_player(facts) else standing
		_place_pony(facts, placed)
		return placed
	if not _has_player(facts):
		if _stool_active(facts):
			facts.stool.set("failed", true)
		_place_pony(facts, standing)
		return standing
	# The offer cone already requires him within 0.8 m of her rump, so the correction is small.
	# The act end leaves him there instead of snapping him back.
	var body: Variant = facts.player
	var target: Vector3 = facts.pony.global_position - forward * gap(facts)
	var floor_y := floor_y_at(facts, Vector3(target.x, body.global_position.y + 0.4, target.z), body)
	if not is_finite(floor_y) or absf(floor_y - body.global_position.y) > 1.0:
		floor_y = body.global_position.y
	target.y = body.global_position.y
	if _stool_active(facts):
		var raised: Variant = facts.stool.call("place", target, body.rotation.y, floor_y)
		if raised is Vector3:
			target = raised
	body.global_position = target
	if facts.stool != null and bool(facts.stool.get("lifted")) and body.get("velocity") != null:
		body.set("velocity", Vector3.ZERO)
	# Do not inherit the previous act's view: face him along her forward, so his body is in front
	# of the camera instead of off to one side after a missionary restore.
	body.rotation.y = atan2(-forward.x, -forward.z)
	# The stance is the pre-act view; the contact distance is hers. Fit the whole body once before
	# the act so the shaft starts at her entrance instead of pulling the Hips bone across the gap.
	var fit := Vector3.ZERO if _stool_active(facts) else part_shift(facts)
	if fit.length_squared() > 0.000001:
		body.global_position += fit
	# The fit has measured the natural pivot; clear the old handshake before the first act tick
	# reseeds the penetration from the fitted stance.
	reset_pelvis(facts)
	body.reset_physics_interpolation()
	LOG.debug("standing keeps pony at=%s and places Anon at=%s yaw=%.3f fit=%+.3f stool=%s", [
		str(facts.pony.global_position), str(body.global_position), body.rotation.y,
		fit.dot(forward), str(_stool_active(facts))])
	return standing


## The camera-rig transform: put her in front of the player along the view, not behind him.
func transform(facts: Facts) -> Transform3D:
	var view: Camera3D = WORLD.camera()
	var forward := Vector3.FORWARD
	if view != null:
		forward = -view.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -facts.player.global_basis.z
	forward = forward.normalized()
	var at: Vector3 = facts.player.global_position + forward * _gap(facts, facts.body_form)
	at.y = facts.player.global_position.y
	return Transform3D(Basis.looking_at(forward, Vector3.UP), at)


## Move the part's rest pivot out to a shaft length from her entrance, so the start meets her
## instead of the Hips bone spanning the pre-act gap; the fit shifts him once, the aim still strokes.
func part_shift(facts: Facts) -> Vector3:
	var service: Variant = facts.anatomy
	if service == null or not service.has_method("player_prepare") \
			or not service.has_method("player_root_natural") \
			or not service.has_method("player_shaft_length_m") \
			or not service.has_method("controller"):
		return Vector3.ZERO
	if not bool(service.call("player_prepare")):
		return Vector3.ZERO
	var length := float(service.call("player_shaft_length_m"))
	if not is_finite(length) or length <= 0.001:
		return Vector3.ZERO
	var root_value: Variant = service.call("player_root_natural")
	if not (root_value is Vector3) or not (root_value as Vector3).is_finite():
		return Vector3.ZERO
	var controller: Variant = service.call("controller", facts.pony)
	if not is_instance_valid(controller) or not controller.has_method("hole_point") \
			or not controller.has_method("hole_rear"):
		return Vector3.ZERO
	if controller.has_method("is_attached") and not bool(controller.call("is_attached")):
		return Vector3.ZERO
	var opening: Variant = controller.call("hole_point", 0.0)
	var rear: Variant = controller.call("hole_rear", 0.0)
	if not (opening is Vector3) or not (opening as Vector3).is_finite():
		return Vector3.ZERO
	if not (rear is Vector3) or not (rear as Vector3).is_finite():
		return Vector3.ZERO
	var flat := Vector3((rear as Vector3).x, 0.0, (rear as Vector3).z)
	if flat.length_squared() < 0.000001:
		return Vector3.ZERO
	# The mesh's outward rear points at Anon, so one shaft along it is the rest pivot.
	var pivot_target: Vector3 = (opening as Vector3) + flat.normalized() * length
	var shift: Vector3 = pivot_target - (root_value as Vector3)
	shift.y = 0.0
	if not shift.is_finite() or shift.length() > FIT_MAX_M:
		return Vector3.ZERO
	return shift


## The act gap from her centre with the body's entrance offset folded in, because a princess body's
## entrance sits elsewhere than the mare body the gaps were tuned on.
func gap(facts: Facts) -> float:
	return _gap(facts, facts.form)


## Re-anchor a standing act after a body change: clear the pelvis handshake and place the new body.
## A non-standing act returns null and leaves the placement alone.
func reanchor(facts: Facts, family: String) -> Variant:
	if family != "standing":
		return null
	reset_pelvis(facts)
	return begin(facts)


## Drop the part's pelvis handshake after the placement fit or a new body. The service owns the
## part; a missing service (a suite or the anatomy off) is a no-op.
func reset_pelvis(facts: Facts) -> void:
	var service: Variant = facts.anatomy
	if service != null and service.has_method("player_reset_pelvis"):
		service.call("player_reset_pelvis")


## The replacement body must still clear the adult-mare gate. Without the service it is let through,
## so a suite can drive the handover without the world's eligibility graph.
func new_body_is_adult(facts: Facts) -> bool:
	if not is_instance_valid(WORLD.game):
		return true
	var service: Variant = PONIES.eligibility
	if service == null or not service.has_method("eligible"):
		return true
	return bool(service.call("eligible", facts.pony, ELIGIBILITY.Target.ACT))


## The floor under a standing spot. The per-act handle owns the facade probe; the player is
## excluded so his own capsule cannot answer.
func floor_y_at(facts: Facts, at: Vector3, body: Node3D) -> float:
	if facts.stool != null and facts.stool.has_method("floor_y_at"):
		return float(facts.stool.call("floor_y_at", at, body))
	return NAN


func _forward(facts: Facts) -> Vector3:
	var forward: Vector3 = -facts.pony.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001 and _has_player(facts):
		forward = -facts.player.global_basis.z
	return forward.normalized()


func _gap(facts: Facts, form: Variant) -> float:
	var size := "same height"
	var settings: Node = facts.pony.get_node_or_null("/root/Settings") \
		if is_instance_valid(facts.pony) else null
	if settings != null:
		size = str(settings.call("get_value", "ponies/size"))
	var gaps: Dictionary = facts.gaps
	if gaps.is_empty():
		gaps = SETTINGS.pose(str(facts.id), CATALOG.STANDING).get("gaps", {})
	var base: float = float(gaps.get(size, gaps["same height"]))
	var gap_m := base * float(facts.camera.call("same_height_scale"))
	gap_m += SETTINGS.gap_offset_m.get_num()
	var target_form: Variant = form if form != null else facts.body_form
	var entrance: Vector2 = ACT_CAMERA.entrance_offset_for(target_form)
	gap_m += entrance.y
	LOG.debug("standing size=%s gap=%.2f entrance_shift=%+.3f", [size, gap_m, entrance.y])
	return gap_m


func _has_player(facts: Facts) -> bool:
	return is_instance_valid(facts.player) and facts.player is Node3D


func _stool_active(facts: Facts) -> bool:
	return facts.stool != null and bool(facts.stool.get("active"))


func _place_pony(facts: Facts, placed: Transform3D) -> void:
	facts.pony.reset_motion(placed)
	facts.pony.reset_physics_interpolation()


