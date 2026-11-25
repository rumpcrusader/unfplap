extends RefCounted
## Private typed records and pure caress math for the hands package.

const SELF := preload("res://mods/unfplap/hands/model.gd")

## A hand side; NONE is the smack hand's "no preference" sentinel.
enum Side { NONE, LEFT, RIGHT }

const CARESS_SPEED_RAD_S := 3.6
## A caress is one continuous action, not a per-frame sample: five seconds of contact count as
## one liked or disliked touch.
const CARESS_TOUCH_SECONDS := 5.0
const CARESS_ORAL_BLEND_S := 0.35
## Per-preset caress-point offsets in metres, before the body scale reaches the oval radius only.
const CARESS_PROFILES := {
	"canon": {"up": 0.08, "back": 0.06, "out": 0.0},
	"mounting": {"up": 0.16, "back": 0.08, "out": 0.02},
	"same height": {"up": 0.18, "back": 0.09, "out": 0.03},
	"hoers": {"up": 0.20, "back": 0.10, "out": 0.04},
}


## One body preset's caress-point offsets in metres.
class CaressProfile extends RefCounted:
	var up := 0.0
	var back := 0.0
	var out := 0.0

	func _init(up_m := 0.0, back_m := 0.0, out_m := 0.0) -> void:
		up = up_m
		back = back_m
		out = out_m

	func scaled(scale: float) -> CaressProfile:
		return CaressProfile.new(up * scale, back * scale, out * scale)


## One caress tick's contact time and the number of five-second actions it completed.
class TouchStep extends RefCounted:
	var seconds := 0.0
	var events := 0

	func _init(left := 0.0, count := 0) -> void:
		seconds = left
		events = count


## Nearest posed flank face to a point.
class FlankHit extends RefCounted:
	var hit := false
	var point := Vector3.ZERO
	var normal := Vector3.ZERO
	var distance := 0.0
	var face := -1

	func _init(found := false, at := Vector3.ZERO, towards := Vector3.ZERO,
			range := 0.0, index := -1) -> void:
		hit = found
		point = at
		normal = towards
		distance = range
		face = index


## The smack's presentation values; the defaults are the bed's own motion.
class SmackPresentation extends RefCounted:
	var raise_m := 0.30
	var pitch_deg := 12.0
	var arc_m := 0.06
	var height_m := -0.03
	var hind_m := 0.10
	var raise_speed := 2.0
	var return_speed := 6.0

	static func from_dict(values: Dictionary) -> SmackPresentation:
		var out := SmackPresentation.new()
		out.raise_m = float(values.get("raise_m", out.raise_m))
		out.pitch_deg = float(values.get("pitch_deg", out.pitch_deg))
		out.arc_m = float(values.get("arc_m", out.arc_m))
		out.height_m = float(values.get("height_m", out.height_m))
		out.hind_m = float(values.get("hind_m", out.hind_m))
		out.raise_speed = float(values.get("raise_speed", out.raise_speed))
		out.return_speed = float(values.get("return_speed", out.return_speed))
		return out


## The missionary arm's world shoulder and bone lengths, empty when the body does not expose them.
class ReachInfo extends RefCounted:
	var valid := false
	var origin := Vector3.ZERO
	var upper := 0.0
	var lower := 0.0
	var hand := 0.0


## The values one caress hand needs for this tick.
class CaressContext extends RefCounted:
	var side: SELF.Side = Side.NONE
	var lean := 0.0
	var phase := 0.0
	var scale := 1.0
	var size := 1.0
	var oval := Vector2(0.01, 0.02)
	var hover := 0.0
	var profile: CaressProfile = null
	var reach: ReachInfo = null
	var delta := 0.016
	var contact_smooth := 0.0
	var normal_deg_s := 0.0
	var debug := false
	var path_id := "one"
	var reach_shoulder_m := 0.0


## The resolved values a hull coat query needs; no settings are read downstream.
class CoatContext extends RefCounted:
	var hover := 0.0
	var contact_smooth := 0.0
	var normal_deg_s := 0.0
	var debug := false
	var ignore: Array[String] = []
	var radial := true
	var regions: Array[String] = []
	var extra_hover := 0.0
	var state_key := ""
	var delta := 0.016


## One ordered path contact, preferred first.
class Candidate extends RefCounted:
	var point := Vector3.INF
	var normal := Vector3.UP
	var oval_x := Vector3.RIGHT
	var oval_y := Vector3.UP
	var center := Vector3.ZERO
	var radius := 0.0
	var finger := Vector3.FORWARD
	var mode := "palm"
	var roll := 0.0
	var region := "torso"
	var exact := false
	var u := 0.0


## The per-hand smoothing state for one contact source.
class ContactState extends RefCounted:
	var point := Vector3.INF
	var normal := Vector3.UP
	var source := ""
	var switches := 0
	var miss := 0
	var offset := Vector3.ZERO
	var offset_valid := false
	var normal_valid := false


## The last precise contact the engine placed for one hand.
class DebugState extends RefCounted:
	var candidate: Candidate = null
	var intended := Vector3.INF
	var contact := Vector3.INF
	var normal := Vector3.UP
	var target := Transform3D.IDENTITY
	var radius := 0.0


## One skinned debug anchor for the path overlay.
class DebugAnchor extends RefCounted:
	var id := ""
	var position := Vector3.INF
	var normal := Vector3.UP

	func _init(anchor_id := "", at := Vector3.INF, towards := Vector3.UP) -> void:
		id = anchor_id
		position = at
		normal = towards


## A resolved coat contact and the source that supplied it.
class Contact extends RefCounted:
	var point := Vector3.INF
	var normal := Vector3.UP
	var source := "fallback"


## One PonyTouchBody entry, parsed at the base-game edge.
class TouchEntry extends RefCounted:
	var region := ""
	var world := Transform3D.IDENTITY
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var r := 0.0


## The nearest touch hull and whether one was found.
class TouchHit extends RefCounted:
	var hit := false
	var entry: TouchEntry = null
	var distance := 0.0
	var local := Vector3.ZERO
	var normal := Vector3.UP


## A point on the posed flank patch, in its local frame.
class FlankContact extends RefCounted:
	var point := Vector3.ZERO
	var normal := Vector3.UP
	var local := Vector3.ZERO


## One sphere on a skin bone, in rest space.
class Influence extends RefCounted:
	var bone := -1
	var bind := Transform3D.IDENTITY
	var weight := 0.0

	func _init(bone_index := -1, bind_pose := Transform3D.IDENTITY, amount := 0.0) -> void:
		bone = bone_index
		bind = bind_pose
		weight = amount


## One authored caress area fitted as a sphere and followed by its skin.
class Anchor extends RefCounted:
	var skeleton: Skeleton3D = null
	var center := Vector3.ZERO
	var normal := Vector3.UP
	var radius := 0.0
	var influences: Array[Influence] = []
	var id := ""
	var lateral := 0.0
	var roll := 0.0
	var region := "torso"


## One skinned anchor in world space.
class AnchorWorld extends RefCounted:
	var id := ""
	var position := Vector3.INF
	var center := Vector3.ZERO
	var radius := 0.0
	var normal := Vector3.UP
	var lateral := 1.0
	var roll := 1.0
	var region := "torso"


## One authored area point queued for the background fit.
class AnchorPoint extends RefCounted:
	var region := "torso"
	var position := Vector3.INF

	func _init(area_region := "torso", at := Vector3.INF) -> void:
		region = area_region
		position = at


## One analytic sample between skinned anchors.
class Sample extends RefCounted:
	var u := 0.0
	var point := Vector3.INF
	var center := Vector3.ZERO
	var radius := 0.0
	var normal := Vector3.UP
	var finger := Vector3.FORWARD
	var side := Vector3.RIGHT
	var lateral := 1.0
	var roll := 1.0
	var region := "torso"
	var id := ""


## The shoulder bone's palm point and its outward hint.
class ShoulderPoint extends RefCounted:
	var palm := Vector3.INF
	var outward := Vector3.UP

	func _init(at := Vector3.INF, towards := Vector3.UP) -> void:
		palm = at
		outward = towards


## A resolved smack: hand, pose target and the frames the swing needs.
class SmackTarget extends RefCounted:
	var valid := false
	var side: SELF.Side = Side.NONE
	var index := 0
	var at := Vector3.INF
	var normal := Vector3.UP
	var from_frame := Transform3D.IDENTITY
	var target := Transform3D.IDENTITY
	var from_coat := false
	var standing := false
	var caressing := false
	var reaching := false


## The mesh and skeleton the caress reads for one coat region.
class CoatMesh extends RefCounted:
	var mesh: MeshInstance3D = null
	var skeleton: Skeleton3D = null
	var surface := -1


## One bone influence of a fitted coat vertex.
class CoatInfluence extends RefCounted:
	var bone_name := ""
	var bind := Transform3D.IDENTITY
	var weight := 0.0

	func _init(name := "", bind_pose := Transform3D.IDENTITY, amount := 0.0) -> void:
		bone_name = name
		bind = bind_pose
		weight = amount


## One fitted rest-space coat sphere.
class CoatPrimitive extends RefCounted:
	var center := Vector3.ZERO
	var normal := Vector3.UP
	var radius := 0.0
	var influences: Array[CoatInfluence] = []
	var residual_mm := 0.0
	var snap_mm := 0.0


static func side_key(side: SELF.Side) -> String:
	if side == Side.LEFT:
		return "left"
	if side == Side.RIGHT:
		return "right"
	return ""


static func side_letter(side: SELF.Side) -> String:
	if side == Side.LEFT:
		return "L"
	if side == Side.RIGHT:
		return "R"
	return ""


static func side_index(side: SELF.Side) -> int:
	if side == Side.LEFT:
		return 0
	if side == Side.RIGHT:
		return 1
	return -1


static func side_other(side: SELF.Side) -> SELF.Side:
	if side == Side.LEFT:
		return Side.RIGHT
	if side == Side.RIGHT:
		return Side.LEFT
	return Side.NONE


static func side_from_letter(letter: String) -> SELF.Side:
	if letter == "L":
		return Side.LEFT
	if letter == "R":
		return Side.RIGHT
	return Side.NONE


## Per-size caress-point offsets. Unknown presets use the JRHNBR reference.
static func caress_profile_for(size_name: String) -> CaressProfile:
	var profile: Dictionary = CARESS_PROFILES.get(size_name, CARESS_PROFILES["mounting"])
	return CaressProfile.new(float(profile["up"]), float(profile["back"]),
		float(profile["out"]))


## Advance the oval phase only while that hand is moving.
static func caress_phase_step(phase: float, moving: bool, delta: float) -> float:
	if not moving:
		return phase
	return fmod(phase + CARESS_SPEED_RAD_S * delta, TAU)


## One caress tick: accumulate contact time and report the seconds left and the actions completed.
static func caress_touch_step(seconds: float, active: bool, delta: float) -> TouchStep:
	if not active:
		return TouchStep.new()
	var left := maxf(0.0, seconds) + maxf(0.0, delta)
	var events := 0
	while left >= CARESS_TOUCH_SECONDS:
		left -= CARESS_TOUCH_SECONDS
		events += 1
	return TouchStep.new(left, events)


## Ease a live caress hand from its last contact to the new path target.
static func caress_oral_blend(from: Transform3D, target: Transform3D,
		elapsed: float) -> Transform3D:
	if elapsed <= 0.0:
		return from
	if elapsed >= CARESS_ORAL_BLEND_S:
		return target
	var t := smoothstep(0.0, 1.0, elapsed / CARESS_ORAL_BLEND_S)
	return from.interpolate_with(target, t)
