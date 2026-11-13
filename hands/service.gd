extends "res://mods/unfplap/hands/session.gd"
## Act hands in both poses: caress, shoulder reach, smack and palm-on-coat contact. The runtime
## owns scoring and the act state; this controller drives the palms and contact frames. Standing
## rubs the flank; missionary rubs her chest, neck and cheek.

const CATALOG := preload("res://mods/unfplap/shared/pose_catalog.gd")
const SETTINGS := preload("res://mods/unfplap/settings/service.gd")
const PLACEMENT := preload("res://mods/unfplap/hands/placement.gd")
const FLANK_PATH := preload("res://mods/unfplap/hands/paths/standing.gd")
const MISSIONARY_PATH := preload("res://mods/unfplap/hands/paths/missionary.gd")
const COAT := preload("res://mods/unfplap/hands/contact.gd")
const SMACK := preload("res://mods/unfplap/hands/smack.gd")

## Ease the hand from its rest frame onto the shoulder instead of teleporting it.
const REACH_HAND_BLEND_S := 0.35
const REACH_HAND_RELEASE_S := 0.35
## Standing A/D caress: an oval rub on the flank surface. The oval is wider along the body
## than up/down, so the hand reads as stroking instead of drawing a perfect circle.
const CARESS_SPEED_RAD_S := 3.6
## A caress is one continuous action, not a per-frame sample: five seconds of contact count as
## one liked or disliked touch. The runtime's scoring and tolerance paths see discrete events.
const CAESS_TOUCH_SECONDS := 5.0
## A smack swings the caress hand to the cheek and back; ease the return so the contact reset
## does not read as a teleport.
const CARESS_RETURN_SECONDS := 0.12
## Caress-point offsets are per size preset, in metres before the body scale is applied to
## only the circle radius. `out` moves each hand out from the flank; both hands together gain
## twice that amount. JRHNBR (`mounting`) is 4 cm wider; Canon sits lower.
const CARESS_PROFILES := {
	"canon": {"up": 0.08, "back": 0.06, "out": 0.0},
	"mounting": {"up": 0.16, "back": 0.08, "out": 0.02},
	"same height": {"up": 0.18, "back": 0.09, "out": 0.03},
	"hoers": {"up": 0.20, "back": 0.10, "out": 0.04},
}
const SMACK_UP_M := 0.08
const SMACK_BACK_M := 0.08
const SMACK_ZONE_RADIUS_M := 0.035
## Missionary keeps the old hidden-hand swing; the standing hand uses the phases below.
## Standing smack: lift off the coat, accelerate into the contact, hold for a frame or two,
## then return to the live caress point or the rest hand. The raise distance is the debug
## `presentation.standing.smack.raise_m` value, scaled by the pony's body size.
## Non-caress smack: the query is offset vertically from the cheek centre by
## `presentation.standing.smack.height_m` (positive up, default -0.03 = 3 cm below), and the
## wind-up is a backswing from behind/below rather than an outward lift. All distances scale
## with the pony.
const SMACK_HEIGHT_M := -0.03
const SMACK_HIND_M := 0.10
## Native impact strength for the smack; also drives the tail jiggle propagation.
## The stock flank slap is bright and compressed. Install a peak-normalised OpenNSFW hand-smack
## variant on the native FlankTouch player; the stock stream, level and pitch are restored at
## act end.
const STATE_ACTIVE := 2
const STATE_CLIMAX := 3

## Pure palm geometry for tests and the controller.
static func palm_clearance_for(body_scale: float, distance := 0.02) -> float:
	return distance * clampf(body_scale, 0.5, 2.0)


## Per-size caress-point offsets. Unknown presets use the JRHNBR reference.
static func caress_profile_for(size_name: String) -> Dictionary:
	var profile: Dictionary = CARESS_PROFILES.get(size_name, CARESS_PROFILES["mounting"])
	return profile


## Advance the oval phase only while that hand is moving. Stopping keeps the palm at the
## current point instead of resetting the stroke.
static func caress_phase_step(phase: float, moving: bool, delta: float) -> float:
	if not moving:
		return phase
	return fmod(phase + CARESS_SPEED_RAD_S * delta, TAU)


## One caress tick: accumulate contact time and report `[seconds_left, events]`, where events is
## how many CAESS_TOUCH_SECONDS actions this tick completed. A stopped caress keeps no credit.
static func caress_touch_step(seconds: float, active: bool, delta: float) -> Array:
	if not active:
		return [0.0, 0]
	var left := maxf(0.0, seconds) + maxf(0.0, delta)
	var events := 0
	while left >= CAESS_TOUCH_SECONDS:
		left -= CAESS_TOUCH_SECONDS
		events += 1
	return [left, events]


## 0 = left cheek, 1 = right cheek, -1 = centered (caller picks at random).
static func smack_side_index(side: float) -> int:
	if side > 0.0:
		return 0
	if side < 0.0:
		return 1
	return -1


## Roll about the coat normal, in degrees. The right hand turns counter-clockwise and the left
## clockwise as seen from above.
static func smack_finger_hint(caressing: bool, forward: Vector3) -> Vector3:
	if caressing:
		var hint := forward.normalized()
		if hint.length_squared() > 0.5:
			return hint
		return Vector3.FORWARD
	return Vector3.DOWN


## Non-caress wind-up: a backswing from behind and below the contact, with the fingers down.
static func closest_flank_hit(faces: PackedVector3Array, normals: PackedVector3Array,
		point: Vector3) -> Dictionary:
	if faces.size() < 3:
		return {}
	var best := INF
	var best_point := Vector3.ZERO
	var best_normal := Vector3.ZERO
	var triangles := int(faces.size() / 3.0)
	for triangle: int in triangles:
		var i := triangle * 3
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var closest := _closest_on_triangle(a, b, c, point)
		var distance := closest.distance_squared_to(point)
		if distance >= best:
			continue
		best = distance
		best_point = closest
		var barycentric := _triangle_barycentric(a, b, c, closest)
		var normal := Vector3.ZERO
		if normals.size() >= i + 3:
			normal = normals[i] * barycentric.x + normals[i + 1] * barycentric.y \
				+ normals[i + 2] * barycentric.z
		if normal.length_squared() < 0.0001:
			normal = (b - a).cross(c - a)
		best_normal = normal.normalized()
	return {"point": best_point, "normal": best_normal, "distance": sqrt(best)}


## Closest point on triangle ABC to P, from Real-Time Collision Detection (Ericson).
static func _closest_on_triangle(a: Vector3, b: Vector3, c: Vector3, p: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denominator := 1.0 / (va + vb + vc)
	return a + ab * (vb * denominator) + ac * (vc * denominator)


static func _triangle_barycentric(a: Vector3, b: Vector3, c: Vector3, p: Vector3) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var denominator := d00 * d11 - d01 * d01
	if absf(denominator) < 0.0000001:
		return Vector3(1.0, 0.0, 0.0)
	var v := (d11 * d20 - d01 * d21) / denominator
	var w := (d00 * d21 - d01 * d20) / denominator
	return Vector3(1.0 - v - w, v, w)


var facts: Variant
var main: Variant
var pony: Variant
var _presentation_cfg: Dictionary = {}
var _profile: Dictionary = {}
var _flank: Node

var _reach_shoulder := ""
var _reach_holding := false
var _reach_hand_from := Transform3D.IDENTITY
var _reach_hand_rest := Transform3D.IDENTITY
var _reach_hand_rest_valid := false
var _reach_hand_started := 0
var _reach_hand_logged := false
var _reach_hand_returning := false
var _reach_hand_return_from := Transform3D.IDENTITY
var _reach_hand_return_started := 0
var _reach_hand_return_side := ""
var _caress_active := {"L": false, "R": false}
var _caress_latched := {"L": false, "R": false}
var _caress_key_down := {"L": false, "R": false}
var _caress_moving := {"L": true, "R": true}
var _caress_move_key_down := {"L": false, "R": false}
var _caress_phase := {"L": 0.0, "R": 0.0}
var _caress_touch_seconds := 0.0
var _caress_logged := {"L": false, "R": false}
var _caress_return_from := {"L": Transform3D.IDENTITY, "R": Transform3D.IDENTITY}
var _caress_return_started := {"L": 0, "R": 0}
var _caress_engine: RefCounted
var _smack_ctl: RefCounted
var _flank_path: RefCounted
var _missionary_path: RefCounted
var _debug_draw_mesh: MeshInstance3D = null
var _debug_draw_depth_mesh: MeshInstance3D = null
var _debug_immediate: ImmediateMesh = null
func _shoulder_hand_point(side: String) -> Dictionary:
	if side.is_empty() or not is_instance_valid(pony):
		return {}
	var path: Variant = _path_for_pose()
	if path == null or not path.has_method("shoulder_point"):
		return {}
	return path.call("shoulder_point", "left" if side == "L" else "right")


## Approximate phase-1 hand placement: the palm rests on the named shoulder. This uses the
## desktop hold-target path, so it does not need `request_action` or release `controls_locked`.
func _set_reach_hand() -> void:
	if _reach_shoulder.is_empty() or not is_instance_valid(pony):
		return
	var driver: Node = facts.pose_driver()
	if not is_instance_valid(driver) or not driver.has_method("set_hold_target"):
		return
	var info := _shoulder_hand_point(_reach_shoulder)
	if info.is_empty():
		return
	var outward: Vector3 = info["outward"]
	var point: Vector3 = info["palm"]
	var side := "left" if _reach_shoulder == "L" else "right"
	var reach_key := "reach:" + side
	if _reach_hand_started <= 0:
		_engine().reset_hand(reach_key)
	# Palm flat on the shoulder coat: the shared hull frame keeps the fingers forward with the
	# palm inward.
	var delta := float(facts.physics_delta)
	var target: Transform3D = _engine().coat_frame(pony, side, point, outward,
		-pony.global_basis.z, _palm_clearance(), true, delta, [], true, [], 0.0, reach_key)
	if _reach_hand_started <= 0:
		_reach_hand_started = Time.get_ticks_msec()
		_reach_hand_from = Transform3D.IDENTITY
		if driver.has_method("hand_frame"):
			var from_frame: Variant = driver.call("hand_frame", side)
			if from_frame is Transform3D:
				_reach_hand_from = from_frame
		_reach_hand_rest = _reach_hand_from
		_reach_hand_rest_valid = _reach_hand_from.is_finite()
	var frame := target
	if _reach_hand_started > 0 and _reach_hand_from.is_finite():
		var t := clampf(float(Time.get_ticks_msec() - _reach_hand_started)
			/ (REACH_HAND_BLEND_S * 1000.0), 0.0, 1.0)
		frame = _reach_hand_from.interpolate_with(target, smoothstep(0.0, 1.0, t))
	if not _reach_hand_logged:
		_reach_hand_logged = true
		var palm_normal: Vector3 = target.basis.x * (1.0 if side == "left" else -1.0)
		_log("reach hand side=%s target=%s x=%s y=%s z=%s fingers=%s palm=%s" % [
			side, str(target.origin), str(target.basis.x), str(target.basis.y),
			str(target.basis.z), str(-target.basis.z), str(palm_normal)])
	driver.call("set_hold_target", side, frame, "rub")


func _caress_tick(delta: float) -> void:
	var pose := str(facts.pose_id)
	if pose not in [CATALOG.STANDING, CATALOG.MISSIONARY]:
		_end_caress()
		return
	# Hold-X auto settings owns A/D and Z/C, so the keys freeze while the layer is open. The
	# hands keep their current state and the caress keeps scoring; only the input is ignored.
	var frozen := bool(facts.call_value(facts.auto_panel_open, false))
	var keys := {
		"L": Input.is_physical_key_pressed(KEY_A),
		"R": Input.is_physical_key_pressed(KEY_D),
	}
	var motion_keys := {
		"L": KEY_Z,
		"R": KEY_C,
	}
	for side: String in ["L", "R"]:
		if not frozen:
			var held := bool(keys[side])
			var pressed := held and not bool(_caress_key_down[side])
			_caress_key_down[side] = held
			if pressed:
				_caress_latched[side] = not bool(_caress_latched[side])
			var move_held := Input.is_physical_key_pressed(motion_keys[side])
			var move_pressed := move_held and not bool(_caress_move_key_down[side])
			_caress_move_key_down[side] = move_held
			if move_pressed:
				_caress_moving[side] = not bool(_caress_moving[side])
				_log("caress movement side=%s %s" % [
					side, "on" if bool(_caress_moving[side]) else "off"])
		var hand_side := "left" if side == "L" else "right"
		# The slapping hand owns the hold target during its swing. Keep the oval phase moving
		# so the hand can return to the current caress point instead of the one it left.
		if _smack_controller().owns_hand(hand_side):
			if bool(_caress_active[side]) and bool(_caress_moving[side]):
				_caress_phase[side] = caress_phase_step(
					float(_caress_phase[side]), true, delta)
			continue
		var want := bool(_caress_latched[side])
		if want:
			if not bool(_caress_active[side]):
				_caress_active[side] = true
				_caress_phase[side] = 0.0
				_caress_logged[side] = false
				_caress_return_started[side] = 0
				_engine().reset_hand(hand_side)
				_log("caress start side=%s" % side)
			_caress_phase[side] = caress_phase_step(
				float(_caress_phase[side]), bool(_caress_moving[side]), delta)
			_set_caress_hand(side)
		elif bool(_caress_active[side]):
			_end_caress_side(side)
	_caress_touch_tick(delta)


## Count a held caress as one touch per CAESS_TOUCH_SECONDS of contact instead of one per physics
## tick. Short taps score nothing; five seconds of rubbing score once.
func _caress_touch_tick(delta: float) -> void:
	var step := caress_touch_step(_caress_touch_seconds, any_active(), delta)
	_caress_touch_seconds = float(step[0])
	for _index in int(step[1]):
		facts.touch("caress")


func _end_caress_side(side: String) -> void:
	if not bool(_caress_active[side]):
		return
	var hand_side := "left" if side == "L" else "right"
	var driver := _hand_driver()
	if is_instance_valid(driver) and driver.has_method("clear_hold_target"):
		driver.call("clear_hold_target", hand_side)
	_engine().reset_hand(hand_side)
	_log("caress stop side=%s" % side)
	_caress_active[side] = false
	_caress_latched[side] = false
	_caress_phase[side] = 0.0
	_caress_logged[side] = false
	_caress_return_started[side] = 0


func _end_caress() -> void:
	_end_caress_side("L")
	_end_caress_side("R")
	_caress_key_down = {"L": false, "R": false}
	_caress_moving = {"L": true, "R": true}
	_caress_move_key_down = {"L": false, "R": false}
	_caress_phase = {"L": 0.0, "R": 0.0}
	_caress_touch_seconds = 0.0


## Hand-marker basis with the palm flat on the coat: local -Z is the fingers, and the palm
## normal (local -X right / +X left) points inward along -outward. No custom roll.
func _caress_ignore() -> Array:
	return SETTINGS.ignore.get_list()


func _palm_clearance() -> float:
	var scale := 1.0
	if is_instance_valid(pony) and pony.get("body_scale") != null:
		scale = float(pony.get("body_scale"))
	return palm_clearance_for(scale, float(SETTINGS.hover_m.get_num()))


func _caress_oval_across_m() -> float:
	return float(SETTINGS.oval_across_m.get_num())


func _caress_oval_up_m() -> float:
	return float(SETTINGS.oval_up_m.get_num())


## Place one caress hand. The path decides where the caress is; the shared engine does the
## contact and palm frame. This function only blends the smack return and hands the frame to the
## pose's palm holder.
func _set_caress_hand(side: String, apply := true) -> Transform3D:
	if not is_instance_valid(pony):
		return Transform3D.IDENTITY
	var hand_side := "left" if side == "L" else "right"
	var path: Variant = _path_for_pose()
	if path == null:
		return Transform3D.IDENTITY
	var started := Time.get_ticks_usec()
	var target: Transform3D = _engine().frame(pony, path, hand_side,
		_caress_context(side, hand_side))
	if facts != null:
		facts.perf("caress_precise", Time.get_ticks_usec() - started)
	if not target.is_finite() or target.origin.length_squared() < 0.0001:
		return Transform3D.IDENTITY
	if not apply:
		return target
	var return_started := int(_caress_return_started.get(side, 0))
	if return_started > 0:
		var elapsed := float(Time.get_ticks_msec() - return_started) / 1000.0
		if elapsed >= CARESS_RETURN_SECONDS:
			_caress_return_started[side] = 0
		else:
			var t := smoothstep(0.0, 1.0, elapsed / CARESS_RETURN_SECONDS)
			var from: Transform3D = _caress_return_from[side]
			target = from.interpolate_with(target, t)
	if not bool(_caress_logged[side]):
		_caress_logged[side] = true
	var driver := _hand_driver()
	if is_instance_valid(driver) and driver.has_method("set_hold_target"):
		driver.call("set_hold_target", hand_side, target, "rub")
	var debug: Dictionary = _engine().debug_state(hand_side)
	if not debug.is_empty():
		_draw_caress_debug(path, hand_side, debug, target)
	return target


## Everything the pose-free engine needs for one hand this tick. Only the pose-specific path
## receives the lean and path settings; the engine sees one oval, one hover and one mode.
func _caress_context(side: String, hand_side: String) -> Dictionary:
	var scale := _smack_body_scale()
	var size := 1.0
	if facts != null:
		size = float(facts.size_scale)
	var oval := Vector2(_caress_oval_across_m(), _caress_oval_up_m()) * scale
	return {
		"lean": clampf(float(facts.lean_forward), -1.0, 1.0),
		"phase": float(_caress_phase.get(side, 0.0)),
		"scale": scale,
		"size": size,
		"oval": oval,
		"hover": _palm_clearance(),
		"clearance": _palm_clearance(),
		"precise": _precise_on(),
		"ignore": _caress_ignore(),
		"profile": _caress_profile(),
		"reach": _caress_reach(hand_side),
		"delta": float(facts.physics_delta),
	}


func _engine() -> RefCounted:
	if _caress_engine == null:
		_caress_engine = PLACEMENT.new(facts)
	return _caress_engine


func _path_for_pose() -> Variant:
	if facts == null or not is_instance_valid(pony):
		return null
	if str(facts.pose_id) == CATALOG.MISSIONARY:
		if _missionary_path == null:
			_missionary_path = MISSIONARY_PATH.new()
		if _missionary_path.get("pony") != pony:
			_missionary_path.call("setup", pony, facts)
			_missionary_path.call("reset")
		return _missionary_path
	if _flank_path == null:
		_flank_path = FLANK_PATH.new()
	if _flank_path.get("pony") != pony:
		_flank_path.call("setup", pony, facts)
		_flank_path.call("reset")
	return _flank_path


func _caress_reach(hand_side: String) -> Dictionary:
	var driver := _hand_driver()
	if is_instance_valid(driver) and driver.has_method("caress_reach"):
		var value: Variant = driver.call("caress_reach", hand_side)
		if value is Dictionary:
			return value
	return {}


func _precise_on() -> bool:
	if facts == null:
		return false
	# The missionary base pose is authored in bed space, and the procedural hull path's palm
	# frame is not valid on the lying body (the cheek ended up edge-on). The authored surface
	# chain is the missionary path; the standing caress keeps the player-facing precise toggle
	# and its hull fallback.
	if str(facts.pose_id) == CATALOG.MISSIONARY:
		return true
	return facts.feature("caress_surface", false)


func _draw_caress_debug(path: Variant, hand_side: String, chosen: Dictionary,
		target: Transform3D) -> void:
	if not bool(SETTINGS.caress_debug.get_bool()):
		return
	if not is_instance_valid(pony) or not pony.is_inside_tree():
		return
	var world: Variant = path.call("debug_world", hand_side)
	if not world is Array:
		world = []
	var tree: SceneTree = pony.get_tree()
	var scene: Node = tree.current_scene if tree != null else null
	if scene == null:
		return
	if not is_instance_valid(_debug_immediate):
		_debug_immediate = ImmediateMesh.new()
	if not is_instance_valid(_debug_draw_mesh) or not _debug_draw_mesh.is_inside_tree():
		_debug_draw_mesh = _make_debug_overlay(scene, "UnfplapCaressDebug", false)
	if not is_instance_valid(_debug_draw_depth_mesh) \
			or not _debug_draw_depth_mesh.is_inside_tree():
		_debug_draw_depth_mesh = _make_debug_overlay(scene, "UnfplapCaressDebugDepth", true)
	_debug_draw_mesh.mesh = _debug_immediate
	_debug_draw_depth_mesh.mesh = _debug_immediate
	var immediate := _debug_immediate
	immediate.clear_surfaces()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	var previous := Vector3.ZERO
	var have_previous := false
	for anchor_value: Variant in (world as Array):
		if not anchor_value is Dictionary:
			continue
		var anchor: Dictionary = anchor_value
		var point: Vector3 = anchor["position"]
		var normal: Vector3 = anchor["normal"]
		var color := _anchor_debug_color(str(anchor["id"]))
		_debug_cross(immediate, point, color)
		_debug_segment(immediate, point, point + normal * 0.08, color)
		if have_previous:
			_debug_segment(immediate, previous, point, Color.WHITE)
		previous = point
		have_previous = true
	if not chosen.is_empty():
		var contact: Vector3 = chosen["contact"]
		var contact_normal: Vector3 = chosen["normal"]
		_debug_cross(immediate, contact, Color(0.2, 1.0, 1.0), 0.035)
		_debug_segment(immediate, contact, contact + contact_normal * 0.10,
			Color(0.2, 1.0, 1.0))
	if target.is_finite():
		_debug_cross(immediate, target.origin, Color(1.0, 0.55, 0.15), 0.04)
		_debug_segment(immediate, target.origin, target.origin + target.basis.y * 0.06,
			Color(1.0, 0.55, 0.15))
	# White is the actual hand palm; gray is the gap between it and the requested target.
	var driver := _hand_driver()
	if is_instance_valid(driver) and driver.has_method("hand_frame"):
		var hand: Transform3D = driver.call("hand_frame", hand_side)
		if hand.is_finite() and hand.origin.length_squared() > 0.0001:
			_debug_cross(immediate, hand.origin, Color.WHITE, 0.045)
			_debug_segment(immediate, hand.origin, target.origin, Color(0.6, 0.6, 0.6))
	immediate.surface_end()


func _make_debug_overlay(scene: Node, overlay_name: String, depth: bool) -> MeshInstance3D:
	var overlay := MeshInstance3D.new()
	overlay.name = overlay_name
	overlay.top_level = true
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = not depth
	material.albedo_color = Color.WHITE if depth else Color(0.28, 0.28, 0.28)
	overlay.material_override = material
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(overlay)
	overlay.global_transform = Transform3D.IDENTITY
	return overlay


func _debug_segment(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)


func _debug_cross(mesh: ImmediateMesh, point: Vector3, color: Color, size := 0.025) -> void:
	_debug_segment(mesh, point - Vector3.RIGHT * size, point + Vector3.RIGHT * size, color)
	_debug_segment(mesh, point - Vector3.UP * size, point + Vector3.UP * size, color)
	_debug_segment(mesh, point - Vector3.FORWARD * size, point + Vector3.FORWARD * size, color)


func _anchor_debug_color(id: String) -> Color:
	match id:
		"lower":
			return Color(1.0, 0.2, 0.2)
		"flank":
			return Color(1.0, 0.45, 0.1)
		"shoulder":
			return Color(0.2, 0.8, 1.0)
		"belly":
			return Color(0.2, 1.0, 0.2)
		"chest":
			return Color(0.2, 0.5, 1.0)
		"neck":
			return Color(1.0, 1.0, 0.2)
		"cheek":
			return Color(1.0, 0.2, 1.0)
		_:
			return Color.WHITE


func _clear_debug_draw() -> void:
	if is_instance_valid(_debug_draw_mesh):
		_debug_draw_mesh.queue_free()
	if is_instance_valid(_debug_draw_depth_mesh):
		_debug_draw_depth_mesh.queue_free()
	_debug_draw_mesh = null
	_debug_draw_depth_mesh = null
	_debug_immediate = null


## The act camera position; the path anchors are chosen on the side it actually sees.
func _hand_driver() -> Node:
	if facts == null:
		return null
	if str(facts.pose_id) == CATALOG.MISSIONARY:
		var body: Variant = facts.missionary_body()
		if is_instance_valid(body) and body is Node:
			return body as Node
		return null
	var driver: Variant = facts.pose_driver()
	if is_instance_valid(driver) and driver is Node:
		return driver as Node
	return null


## Release from the shoulder smoothly rather than teleporting back.
func _begin_reach_release() -> void:
	if _reach_shoulder.is_empty():
		return
	var side := "left" if _reach_shoulder == "L" else "right"
	var driver: Node = facts.pose_driver()
	_reach_hand_return_from = _reach_hand_from
	if is_instance_valid(driver) and driver.has_method("hand_frame"):
		var current: Variant = driver.call("hand_frame", side)
		if current is Transform3D and (current as Transform3D).is_finite():
			_reach_hand_return_from = current
	if not _reach_hand_rest_valid or not _reach_hand_return_from.is_finite():
		_clear_reach_hand()
		return
	_reach_hand_return_side = side
	_reach_hand_return_started = Time.get_ticks_msec()
	_reach_hand_returning = true


func _reach_hand_return_tick() -> void:
	if not _reach_hand_returning:
		return
	if _reach_hand_return_side.is_empty():
		_reach_hand_returning = false
		return
	var driver: Node = facts.pose_driver()
	if not is_instance_valid(driver) or not driver.has_method("set_hold_target"):
		_reach_hand_returning = false
		return
	var t := clampf(float(Time.get_ticks_msec() - _reach_hand_return_started)
		/ (REACH_HAND_RELEASE_S * 1000.0), 0.0, 1.0)
	if t >= 1.0:
		_reach_hand_returning = false
		if driver.has_method("clear_hold_target"):
			driver.call("clear_hold_target", _reach_hand_return_side)
		_reach_hand_return_side = ""
		_reach_hand_started = 0
		_reach_hand_from = Transform3D.IDENTITY
		return
	var frame: Transform3D = _reach_hand_return_from.interpolate_with(
		_reach_hand_rest, smoothstep(0.0, 1.0, t))
	driver.call("set_hold_target", _reach_hand_return_side, frame, "rub")


func _clear_reach_hand() -> void:
	var side := ""
	if not _reach_shoulder.is_empty():
		side = "left" if _reach_shoulder == "L" else "right"
	elif not _reach_hand_return_side.is_empty():
		side = _reach_hand_return_side
	_reach_hand_returning = false
	_reach_hand_return_side = ""
	_reach_hand_started = 0
	_reach_hand_logged = false
	_reach_hand_from = Transform3D.IDENTITY
	_reach_hand_rest_valid = false
	if side.is_empty():
		return
	var driver: Node = facts.pose_driver()
	if is_instance_valid(driver) and driver.has_method("clear_hold_target"):
		driver.call("clear_hold_target", side)


func _smack_zone_radius() -> float:
	return maxf(0.0, float(_profile.get("smack_zone_radius", SMACK_ZONE_RADIUS_M)))


## The posed FlankTouch frame. `frame` is the current hip frame even while the decal/sound
## node is parked; `global_transform` can lag there, so prefer the stored frame.
func _flank_frame() -> Transform3D:
	if not is_instance_valid(_flank):
		return Transform3D.IDENTITY
	var value: Variant = _flank.get("frame")
	if value is Transform3D and (value as Transform3D).is_finite():
		return value
	return _flank.global_transform


## Nearest point on the posed FlankSurface patch to a world point. The patch is the cheek
## region of her flank; the body hull is deliberately not consulted, so a shoulder or belly
## caress still smacks the flank.
func _closest_flank_contact(point_world: Vector3) -> Dictionary:
	if not is_instance_valid(_flank):
		_flank = pony.get_node_or_null("FlankTouch") if is_instance_valid(pony) else null
	if not is_instance_valid(_flank):
		return {}
	var surface: Variant = _flank.get("surface")
	if surface == null:
		return {}
	var frame := _flank_frame()
	if not frame.is_finite():
		return {}
	var sk: Variant = pony.get("skeleton")
	if sk is Skeleton3D and surface.has_method("update_pose"):
		surface.call("update_pose", sk, frame)
	var faces_value: Variant = surface.get("faces")
	var normals_value: Variant = surface.get("vertex_normals")
	if not faces_value is PackedVector3Array or not normals_value is PackedVector3Array:
		return {}
	var faces: PackedVector3Array = faces_value
	var normals: PackedVector3Array = normals_value
	var local := frame.affine_inverse() * point_world
	var hit := closest_flank_hit(faces, normals, local)
	if hit.is_empty():
		return {}
	var local_point: Vector3 = hit["point"]
	var local_normal: Vector3 = hit["normal"]
	if local_normal.length_squared() < 0.5:
		local_normal = Vector3.UP
	# Refine onto the real triangle so the palm normal matches the coat at that point.
	if surface.has_method("contact"):
		var radii: Variant = _flank.get("radii")
		var reach := 0.10
		if radii is Vector3:
			reach = float((radii as Vector3).z)
		var raw: Variant = surface.call("contact", local_point, local_point,
			-local_normal, reach)
		if raw is Dictionary and not (raw as Dictionary).is_empty():
			var raw_point: Variant = (raw as Dictionary).get("position")
			var raw_normal: Variant = (raw as Dictionary).get("normal")
			if raw_point is Vector3 and raw_normal is Vector3:
				var point_v: Vector3 = raw_point
				var normal_v: Vector3 = raw_normal
				local_point = point_v
				local_normal = normal_v.normalized()
	var world_point := frame * local_point
	var world_normal := (frame.basis.inverse().transposed() * local_normal).normalized()
	var toward_hand := point_world - world_point
	if toward_hand.length_squared() > 0.0001 and world_normal.dot(toward_hand) < 0.0:
		world_normal = -world_normal
	return {"point": world_point, "normal": world_normal, "local": local_point}


## Standing smack target: the live caress point when that hand is already on the flank patch,
## otherwise the bottom of the chosen cheek for a free-hand smack, jittered within the
## character's smack zone. Empty only when the flank patch is unavailable.
func _standing_smack_target(hand_side: String, hand_world: Vector3,
		caressing: bool) -> Dictionary:
	var caress_side := "L" if hand_side == "left" else "R"
	var state: Dictionary = _engine().contact_state(hand_side)
	if caressing and str(state.get("source", "")) == "flank":
		var point_v: Variant = state.get("point", Vector3.INF)
		var normal_v: Variant = state.get("normal", Vector3.UP)
		if point_v is Vector3 and normal_v is Vector3:
			var point: Vector3 = point_v
			var normal: Vector3 = normal_v
			if point.is_finite() and normal.length_squared() > 0.5:
				var frame := _flank_frame()
				return {"local": frame.affine_inverse() * point,
					"normal": normal.normalized()}
	var focus := hand_world
	if not caressing:
		var cheek := _lower_cheek_query(hand_side)
		if cheek.is_finite():
			focus = cheek
	var hit := _closest_flank_contact(focus)
	if hit.is_empty():
		return {}
	var point_world: Vector3 = hit["point"]
	var normal: Vector3 = hit["normal"]
	var local: Vector3 = hit["local"]
	var radius := _smack_zone_radius()
	if radius > 0.0:
		var up := Vector3.UP.slide(normal)
		if up.length_squared() < 0.001:
			up = -pony.global_basis.z.slide(normal)
		up = up.normalized()
		var across := up.cross(normal).normalized()
		var angle := randf() * TAU
		var shift := (up * cos(angle) + across * sin(angle)) * (sqrt(randf()) * radius)
		var jittered := COAT.contact(pony, point_world + shift, normal, _caress_ignore())
		if str(jittered.get("source", "")) == "flank":
			point_world = jittered.get("point", point_world)
			var jittered_normal: Variant = jittered.get("normal", normal)
			if jittered_normal is Vector3:
				var jn: Vector3 = jittered_normal
				normal = jn.normalized()
			local = _flank_frame().affine_inverse() * point_world
	return {"local": local, "normal": normal}


## Free-hand query offset from the cheek mark centre: `height_m` is signed (positive up) and
## `hind_m` moves toward her rump. Both scale with the pony.
static func smack_query_offset(height_m: float, hind_m: float, scale: float,
		up: Vector3, back: Vector3) -> Vector3:
	return up.normalized() * (height_m * scale) + back.normalized() * (hind_m * scale)


## World query point for a free-hand smack: the chosen cheek centre offset by the act's height
## and hind settings, so the nearest surface point is a cheek rather than the leg.
func _lower_cheek_query(hand_side: String) -> Vector3:
	if not is_instance_valid(_flank):
		return Vector3.INF
	var centers: Variant = _flank.get("centers")
	var index := 0 if hand_side == "left" else 1
	if not centers is Array or index >= (centers as Array).size():
		return Vector3.INF
	var centre: Variant = (centers as Array)[index]
	if not centre is Vector3:
		return Vector3.INF
	var world: Vector3 = _flank_frame() * (centre as Vector3)
	var back := Vector3.BACK
	if is_instance_valid(pony):
		back = pony.global_basis.z.normalized()
	var scale := _smack_body_scale()
	return world + smack_query_offset(_smack_height_m(), _smack_hind_m(), scale,
		Vector3.UP, back)


func _smack() -> void:
	if int(facts.state) not in [STATE_ACTIVE, STATE_CLIMAX]:
		return
	var now := Time.get_ticks_msec()
	if not _smack_controller().can_start(now):
		return
	if not is_instance_valid(_flank):
		_flank = pony.get_node_or_null("FlankTouch") if is_instance_valid(pony) else null
	if not is_instance_valid(_flank) or not _flank.has_method("impact"):
		return
	# If a hand is already resting on the flank, slap with that hand. Both on the flank: pick
	# one at random. Otherwise keep the lean-based cheek/hand mapping.
	var hand_side := ""
	if _caress_active["L"] and _caress_active["R"]:
		hand_side = "left" if randf() < 0.5 else "right"
	elif _caress_active["L"]:
		hand_side = "left"
	elif _caress_active["R"]:
		hand_side = "right"
	var index := 0 if hand_side == "left" else (1 if hand_side == "right" else smack_side_index(float(facts.lean_side)))
	if index < 0:
		index = 0 if randf() < 0.5 else 1
		hand_side = "left" if index == 0 else "right"
	elif hand_side.is_empty():
		hand_side = "left" if index == 0 else "right"
	var caress_side := "L" if hand_side == "left" else "R"
	var caressing := bool(_caress_active[caress_side])
	var driver: Node = _hand_driver()
	var from_frame := Transform3D.IDENTITY
	if is_instance_valid(driver) and driver.has_method("hand_frame"):
		var current: Variant = driver.call("hand_frame", hand_side)
		if current is Transform3D and (current as Transform3D).is_finite():
			from_frame = current
	var at := Vector3.INF
	var normal := Vector3.UP
	var centers: Variant = _flank.get("centers")
	var normals: Variant = _flank.get("normals")
	if centers is Array and index < (centers as Array).size() \
			and normals is Array and index < (normals as Array).size():
		var centre: Variant = (centers as Array)[index]
		var normal_local: Variant = (normals as Array)[index]
		if centre is Vector3 and normal_local is Vector3 and is_instance_valid(pony):
			# The mark centres are local to FlankTouch. Map the pony's backward and world-up
			# directions into that frame so the offset is right regardless of model axes.
			var back_local: Vector3 = (_flank.global_basis.inverse() * pony.global_basis.z).normalized()
			var up_local: Vector3 = (_flank.global_basis.inverse() * Vector3.UP).normalized()
			var angle := randf() * TAU
			var radius := sqrt(randf()) * _smack_zone_radius()
			at = (centre as Vector3) + back_local * (SMACK_BACK_M + cos(angle) * radius) \
				+ up_local * (SMACK_UP_M + sin(angle) * radius)
			var frame := _flank_frame()
			normal = (frame.basis.inverse().transposed() * (normal_local as Vector3)).normalized()
			var outward: Vector3 = (frame * (centre as Vector3)) - pony.global_position
			outward.y = 0.0
			if outward.length_squared() > 0.001 and normal.dot(outward.normalized()) < 0.0:
				normal = -normal
	# Standing targets the live caress point or the bottom of the chosen cheek, not the decal
	# centre. The cheek-centre target above remains the fallback when the patch is unavailable.
	if str(facts.pose_id) == CATALOG.STANDING and from_frame.is_finite():
		var standing_target := _standing_smack_target(hand_side, from_frame.origin, caressing)
		if not standing_target.is_empty():
			at = standing_target.get("local", at)
			normal = standing_target.get("normal", normal)
	if at.is_finite() and is_instance_valid(main) and is_instance_valid(main.player):
		if is_instance_valid(driver) and from_frame.is_finite():
			var world_centre: Vector3 = _flank_frame() * at
			var target: Transform3D = _engine().coat_frame(pony, hand_side, world_centre, normal,
				_smack_finger_hint(caressing), _palm_clearance(), false, 0.0, [], true, [],
				0.0, "smack:" + hand_side)
			var standing := str(facts.pose_id) == CATALOG.STANDING
			_smack_controller().begin(hand_side, index, at, from_frame, target, normal,
				caressing, standing, now)
			return
	_smack_controller().instant(index, at)


func _smack_body_scale() -> float:
	if is_instance_valid(pony) and pony.get("body_scale") != null:
		return clampf(float(pony.get("body_scale")), 0.5, 2.0)
	return 1.0


func _smack_finger_hint(caressing: bool) -> Vector3:
	var forward := Vector3.FORWARD
	if is_instance_valid(pony):
		forward = -pony.global_basis.z.normalized()
	return smack_finger_hint(caressing, forward)


func _smack_setting(name: String, fallback: float) -> float:
	var smack: Variant = _presentation_cfg.get("smack", {})
	if smack is Dictionary:
		return float((smack as Dictionary).get(name, fallback))
	return fallback


func _smack_hind_m() -> float:
	return maxf(0.0, _smack_setting("hind_m", SMACK_HIND_M))


func _smack_height_m() -> float:
	return _smack_setting("height_m", SMACK_HEIGHT_M)


## Read the live scene handles and configs from the typed act view. The runtime rewrites the
## view before it hands the controller out, so this is a copy, not a read of the runtime node.
func _sync() -> void:
	if facts == null:
		pony = null
		main = null
		_presentation_cfg = {}
		_profile = {}
		return
	pony = facts.pony
	main = facts.main
	var cfg: Variant = facts.presentation_config
	_presentation_cfg = cfg if cfg is Dictionary else {}
	var profile: Variant = facts.profile
	_profile = profile if profile is Dictionary else {}
	if not is_instance_valid(_flank) and is_instance_valid(pony):
		_flank = pony.get_node_or_null("FlankTouch")


func _init(facts_context: Variant = null) -> void:
	facts = facts_context


## One physics tick: ease the reach hand home, hold it on the shoulder, then run the caress
## and the smack swing in the same order the runtime used before.
## Return easing runs at the top of every lean tick, even while the act is leaving the
## actionable states, so a released reach still blends home.
func return_tick() -> void:
	if facts == null:
		return
	_reach_hand_return_tick()


func tick(delta: float) -> void:
	if facts == null:
		return
	_sync()
	if _reach_holding:
		_set_reach_hand()
	_caress_tick(delta)
	_smack_controller().tick(delta)


## Stop input-driven contact without clearing the reach release.
func stop_inputs() -> void:
	_end_caress()
	_smack_controller().cancel()


func start_reach(shoulder: String) -> void:
	_sync()
	_reach_shoulder = shoulder
	_reach_holding = true
	_reach_hand_returning = false
	_reach_hand_started = 0
	_reach_hand_logged = false
	_set_reach_hand()


func end_reach() -> void:
	_reach_holding = false
	_begin_reach_release()


func reset() -> void:
	_end_caress()
	_smack_controller().reset()
	_clear_reach_hand()
	_reach_shoulder = ""
	_reach_holding = false
	_engine().reset()
	if _missionary_path != null:
		_missionary_path.call("reset")
	if _flank_path != null:
		_flank_path.call("reset")
	_clear_debug_draw()
	_caress_latched = {"L": false, "R": false}
	_caress_key_down = {"L": false, "R": false}
	_caress_moving = {"L": true, "R": true}
	_caress_move_key_down = {"L": false, "R": false}
	_caress_phase = {"L": 0.0, "R": 0.0}
	_caress_touch_seconds = 0.0


func any_active() -> bool:
	return bool(_caress_active.get("L", false)) or bool(_caress_active.get("R", false))


func active(side: String) -> bool:
	return bool(_caress_active.get(side, false))


func smack() -> void:
	_sync()
	_smack()


func _smack_controller() -> RefCounted:
	if _smack_ctl == null:
		_smack_ctl = SMACK.new(self)
	return _smack_ctl


func caress_active(side: String) -> bool:
	return bool(_caress_active.get(side, false))


func caress_latched(side: String) -> bool:
	return bool(_caress_latched.get(side, false))


func caress_phase(side: String) -> float:
	return float(_caress_phase.get(side, 0.0))


func caress_set_hand(side: String, apply := true) -> Transform3D:
	return _set_caress_hand(side, apply)


func caress_begin_return(caress_side: String, from: Transform3D) -> void:
	var side := "left" if caress_side == "L" else "right"
	_engine().reset_hand(side)
	_caress_return_from[caress_side] = from
	_caress_return_started[caress_side] = Time.get_ticks_msec()
	_set_caress_hand(caress_side)


func caress_finish_keep(caress_side: String) -> void:
	_caress_return_started[caress_side] = 0


func caress_reset_hand(side: String) -> void:
	_engine().reset_hand(side)


func caress_return_seconds() -> float:
	return CARESS_RETURN_SECONDS


func hand_driver() -> Node:
	return _hand_driver()


func smack_body_scale() -> float:
	return _smack_body_scale()


func smack_flank() -> Node:
	if not is_instance_valid(_flank) and is_instance_valid(pony):
		_flank = pony.get_node_or_null("FlankTouch")
	return _flank


func smack_presentation() -> Dictionary:
	return _presentation_cfg


func smack_pony() -> Variant:
	return pony


## One readiness touch event from a smack swing.
func hand_on_touch(kind: String) -> void:
	if facts != null:
		facts.touch(kind)


## One smack impact, for the jiggle and rump blush fan-out.
func hand_on_smack_impact(strength: float) -> void:
	if facts != null:
		facts.smack_hit(strength)


func _log(text: String) -> void:
	if facts != null:
		facts.write_log(text)


## Per-size caress-point offsets, scaled for the "same height" preset.
func _caress_profile() -> Dictionary:
	var size := str(facts.size_name)
	var profile := caress_profile_for(size).duplicate(true)
	if size == "same height":
		var scale := float(facts.same_height_scale)
		for key: String in ["up", "back", "out"]:
			profile[key] = float(profile.get(key, 0.0)) * scale
	return profile
