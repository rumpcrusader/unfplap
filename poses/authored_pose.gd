extends RefCounted
## The authored pose asset loader: local-rest pose deltas.

const SELF := preload("res://mods/unfplap/poses/authored_pose.gd")
const LOG := preload("res://mods/unfplap/shared/log.gd")

const PATH := "res://mods/unfplap/poses/missionary_pose.json"
const SPACE_LOCAL_REST := "local_rest"
const SUPPORTED_FRAMES := ["bed", "ground"]
const RIG_NAME := "hybrid_mare"
const RIG_BONES := 30
const ANON_RIG := "Anon3"

## How far the mare body sinks below the support per unit of body scale. Bed poses only.
const BED_SINK_M := 0.004
const BED_LIFT_MIN_M := 0.005

## The body bones the act owns, in the pose lab's order. Every asset carries all of them, rest
## included: the runtime never resets a bone it is not given.
const PONY_BONES := [
	"pony_hips",
	"pony_spine1", "pony_spine2", "pony_spine3",
	"pony_neck1", "pony_neck2",
	"pony_flank_L", "pony_femur_L", "pony_tibia_L", "pony_legLower_L", "pony_tarsal_L",
	"pony_hoof_L",
	"pony_flank_R", "pony_femur_R", "pony_tibia_R", "pony_legLower_R", "pony_tarsal_R",
	"pony_hoof_R",
	"pony_shoulder_L", "pony_upperArm_L", "pony_lowerArm_L", "pony_wrist_L", "pony_hand_L",
	"pony_finger_L",
	"pony_shoulder_R", "pony_upperArm_R", "pony_lowerArm_R", "pony_wrist_R", "pony_hand_R",
	"pony_finger_R",
]
## Bones the game or the act animates every frame: they are never baked.
const BANNED_PREFIXES := ["pony_head", "pony_lid", "pony_ear", "pony_Wing", "pony_wing",
	"pony_Feather", "pony_foldedWing", "pony_tail", "rd_", "jaw", "EYETARGET", "MOUNT_"]

## True once a valid asset is parsed and `error` is empty.
var available := false
var error := ""
var path := PATH
var id := ""
var space := ""
var frame := ""
var rig_name := ""
var rig_bones := 0
## `{size, body_scale, config}`: the bake reference the base was authored at.
var reference: Dictionary = {}
## The base anchor: `{bone, transform, contact, support}`.
var anchor: Dictionary = {}
## The armature root global pose in frame space at canon.
var root := Transform3D.IDENTITY
## Bone name -> `{rotation, position}` as a rest-local delta.
var pony_bones: Dictionary = {}
## The optional act body: mode, rig, transform and local-rest bone deltas.
var anon_mode := ""
var anon_rig := ""
var anon_transform := Transform3D.IDENTITY
var anon_bones: Dictionary = {}
## Authored shot camera transforms in frame space, keyed `start`, `back`, `front`, `left`, `right`.
## The act reads each origin and aims it at her live face and vulva; the rotations are unused.
var shots: Dictionary = {}
var has_shots := false
## Bed reference metadata (`size`, `mattress_top`); placement uses the live mattress frame.
var bed_size := Vector3.ZERO
var mattress_top := 0.0
## `size_name` -> merged variant record. Empty when the asset ships none.
var variants: Dictionary = {}
## The variant selected by the last apply, for diagnostics.
var variant := ""

## Bumped by every `load_file()`, including a failed reload. The pose session caches the rig gate
## against it, so "Reload posed base" re-checks the bones against the new asset in the same act.
static var revision := 0
static var _shared: Dictionary = {}
static var _clearance: Dictionary = {}   # "<body mesh rid>|<pose>|<variant>|<revision>" -> lift

var _indices: Dictionary = {}
var _index_skeleton := 0
var _selected_name := ""
var _selected: Dictionary = {}
var _parse_bad := ""
## The last bed clearance measured for this instance's skeleton, variant and asset revision, so a
## steady pose write is a few comparisons instead of a string key and a child search.
var _clearance_skeleton := 0
var _clearance_variant := ""
var _clearance_revision := -1
var _clearance_value := -1.0


## The one parsed instance for a path. A pose row's `poses/...` path is resolved against the mod.
static func shared(path := PATH) -> Variant:
	var resolved := resolve(path)
	if not _shared.has(resolved):
		var made: Variant = SELF.new()
		made.load_file(resolved)
		_shared[resolved] = made
	return _shared[resolved]


## Re-reads a pose file in place, so a live pose modifier sees the new pose at once. Returns "" or
## the reason the file could not be used.
static func reload_file(path := PATH) -> String:
	var resolved := resolve(path)
	if not _shared.has(resolved):
		var made: Variant = shared(resolved)
		return "" if bool(made.get("available")) else str(made.get("error"))
	var made: Variant = _shared[resolved]
	return str(made.load_file(resolved))


## Resolves a spec row's `poses/...` asset path against the mod root; a `res://` or `user://` path
## is used as given.
static func resolve(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	return "res://mods/unfplap/" + path.lstrip("/")


## Re-reads a pose file in place. `path` is the asset path; the shipped assets are under `poses/`.
## Returns "" or the reason the file was unusable.
func load_file(path_in := PATH) -> String:
	revision += 1
	path = resolve(path_in)
	_reset()
	if not FileAccess.file_exists(path):
		error = "no pose at %s" % path
		return error
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		error = "bad JSON in %s" % path
		return error
	return _parse_data(parsed as Dictionary)


## Parses an already decoded asset document. Dev tools use it to compare a captured asset without
## writing a file; the runtime only reads files.
func load_data(data: Dictionary) -> String:
	path = ""
	_reset()
	return _parse_data(data)


func _parse_data(data: Dictionary) -> String:
	_load_document(data)
	if not error.is_empty():
		available = false
		return error
	available = true
	return ""


func _reset() -> void:
	available = false
	error = ""
	id = ""
	space = ""
	frame = ""
	rig_name = ""
	rig_bones = 0
	reference = {}
	anchor = {}
	root = Transform3D.IDENTITY
	pony_bones = {}
	anon_mode = ""
	anon_rig = ""
	anon_transform = Transform3D.IDENTITY
	anon_bones = {}
	shots = {}
	has_shots = false
	bed_size = Vector3.ZERO
	mattress_top = 0.0
	variants = {}
	variant = ""
	_indices = {}
	_index_skeleton = 0
	_selected_name = ""
	_selected = {}
	_parse_bad = ""


## True when this asset may drive a pose whose own frame is `frame_kind`.
func usable(frame_kind: String) -> bool:
	return available and frame == frame_kind


## The skeleton's root bone (the armature), or -1.
static func root_bone(sk: Skeleton3D) -> int:
	for i: int in sk.get_bone_count():
		if sk.get_bone_parent(i) < 0:
			return i
	return -1


## The authored body bones this rig lacks. A gap leaves the game's pose on that link, so the act
## refuses the rig rather than pose half a body.
func missing_bones(sk: Skeleton3D) -> Array[String]:
	var out: Array[String] = []
	if sk == null:
		return out
	for key: Variant in active_bones():
		var name := str(key)
		if sk.find_bone(name) < 0:
			out.append(name)
	return out


## The base or selected variant bones, without allocating when no variant is selected.
func active_bones() -> Dictionary:
	var value: Variant = _selected["bones"] if not _selected.is_empty() else pony_bones
	return value as Dictionary


func active_anon_bones() -> Dictionary:
	var value: Variant = _selected["anon_bones"] if not _selected.is_empty() else anon_bones
	return value as Dictionary


func active_anon_transform() -> Transform3D:
	var value: Variant = _selected["anon_transform"] if not _selected.is_empty() \
		else anon_transform
	return value as Transform3D


func active_anon_mode() -> String:
	var value: Variant = _selected["anon_mode"] if not _selected.is_empty() else anon_mode
	return str(value)


## The anchor block of the base or the selected variant.
func active_anchor() -> Dictionary:
	var value: Variant = _selected["anchor"] if not _selected.is_empty() else anchor
	return value as Dictionary


func active_root() -> Transform3D:
	var value: Variant = _selected["root"] if not _selected.is_empty() else root
	return value as Transform3D


func active_shots() -> Dictionary:
	var value: Variant = _selected["shots"] if not _selected.is_empty() else shots
	return value as Dictionary


## The world hips anchor pose `F * anchor.transform`.
func anchor_world(world_frame: Transform3D) -> Transform3D:
	var block := active_anchor()
	var value: Variant = block.get("transform")
	var at: Transform3D = value if value is Transform3D else Transform3D.IDENTITY
	return world_frame * at


## The world contact point at canon size: `anchor_world * contact`.
func contact_world(world_frame: Transform3D) -> Vector3:
	var block := active_anchor()
	var value: Variant = block.get("contact")
	var contact: Vector3 = value if value is Vector3 else Vector3.ZERO
	return anchor_world(world_frame) * contact


## The support height in frame space (the mattress top or the ground at zero).
func support() -> float:
	return float(active_anchor().get("support", 0.0))


## The vertical lift that keeps the contact on the support at `body_scale`.
func body_lift(world_frame: Transform3D, body_scale: float) -> float:
	var at := anchor_world(world_frame)
	var here := at.origin
	var scaled := here + (contact_world(world_frame) - here) * body_scale
	return (world_frame.origin.y + support()) - scaled.y


## The anchor/contact size rule for one authored point: hips anchor, body scale, contact lift.
## The act body is placed by this math.
func place_origin(world_point: Vector3, world_frame: Transform3D, body_scale: float) -> Vector3:
	var here := anchor_world(world_frame).origin
	return here + (world_point - here) * body_scale \
		+ Vector3.UP * body_lift(world_frame, body_scale)


## The world armature root at `body_scale`: scaled about the hips anchor, basis scaled once, and
## offset so the contact lands on the support height.
func placed_root(world_frame: Transform3D, body_scale: float) -> Transform3D:
	var here := anchor_world(world_frame).origin
	var canon_root := (world_frame * active_root()).origin
	var wanted := here + (canon_root - here) * body_scale
	wanted.y += body_lift(world_frame, body_scale)
	var basis := world_frame.basis.orthonormalized() * active_root().basis
	basis = basis * Basis.from_scale(Vector3.ONE * body_scale)
	return Transform3D(basis, wanted)


## Applies the base pose about the hips anchor, ramping from the game's current pose by `weight`
## (the caller drives it).
func apply_pony(sk: Skeleton3D, weight: float, world_frame: Transform3D, body_scale: float,
		size_name := "") -> bool:
	if not available or sk == null:
		return false
	_select(size_name, body_scale)
	var root_index := root_bone(sk)
	if root_index >= 0:
		var wanted := placed_root(world_frame, body_scale)
		# A bigger body (the princesses' own) sits lower from its armature root, so the mare's
		# placement sinks her. Lift by the measured amount; zero for a mare and any body that
		# already clears.
		if frame == "bed":
			wanted.origin += Vector3.UP * bed_clearance(sk) * body_scale
		var desired := sk.global_transform.affine_inverse() * wanted
		var current := sk.get_bone_global_pose(root_index)
		sk.set_bone_global_pose(root_index, current.interpolate_with(desired, weight))
	_cache_indices(sk)
	var bones := active_bones()
	for key: Variant in _indices:
		var name := str(key)
		var entry: Variant = bones.get(name)
		if not entry is Dictionary:
			continue
		_write_bone(sk, int(_indices[key]), entry, weight)
	return true


## This body's sink margin below the support, per unit body scale; bed poses only. Measured once
## per body mesh and variant by skinning the posed rest skeleton on the CPU.
func bed_clearance(sk: Skeleton3D) -> float:
	if sk == null:
		return 0.0
	if _clearance_value >= 0.0 and sk.get_instance_id() == _clearance_skeleton \
			and variant == _clearance_variant and revision == _clearance_revision:
		return _clearance_value
	var body := sk.find_child("MareBody", true, false) as MeshInstance3D
	if body == null or body.mesh == null or body.skin == null \
			or body.mesh.get_surface_count() == 0:
		return 0.0
	var key := "%d|%s|%s|%d" % [body.mesh.get_rid().get_id(), path, variant, revision]
	if _clearance.has(key):
		return float(_clearance[key])
	var lift := 0.0
	var root_index := root_bone(sk)
	if root_index >= 0:
		# Every bone's frame-space pose at scale 1: the authored root, the authored bones by the
		# local-rest rule (as _write_bone at weight 1) and the rest pose for the rest.
		var bones := active_bones()
		var poses: Array[Transform3D] = []
		poses.resize(sk.get_bone_count())
		var done: Array[bool] = []
		done.resize(sk.get_bone_count())
		var root_pose := placed_root(Transform3D.IDENTITY, 1.0)
		for i in sk.get_bone_count():
			_frame_pose(sk, i, root_index, root_pose, bones, poses, done)
		var arrays := body.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var vb: PackedInt32Array = arrays[Mesh.ARRAY_BONES] \
			if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var vw: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] \
			if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		if not verts.is_empty() and not vb.is_empty():
			var per := vb.size() / verts.size()
			var skin_mats: Array[Transform3D] = []
			for b in body.skin.get_bind_count():
				var bone := body.skin.get_bind_bone(b)
				if bone < 0:
					bone = sk.find_bone(body.skin.get_bind_name(b))
				skin_mats.append((poses[bone] * body.skin.get_bind_pose(b))
					if bone >= 0 else Transform3D.IDENTITY)
			var low := INF
			for v in verts.size():
				var y := 0.0
				for k in per:
					var wt := vw[v * per + k]
					if wt > 0.0:
						y += (skin_mats[vb[v * per + k]] * verts[v]).y * wt
				low = minf(low, y)
			if is_finite(low):
				var need := (support() - BED_SINK_M) - low
				if need > BED_LIFT_MIN_M:
					lift = need
	_clearance[key] = lift
	_clearance_skeleton = sk.get_instance_id()
	_clearance_variant = variant
	_clearance_revision = revision
	_clearance_value = lift
	if lift > 0.0:
		LOG.debug("bed pose %s: body sits %.3f m into the mattress, lifted", [id, lift])
	return lift


## One bone's frame-space pose at scale 1: the root's authored placement, the authored bones by the
## local-rest rule, and the rest local transform for every other bone.
func _frame_pose(sk: Skeleton3D, bone: int, root_index: int, root_pose: Transform3D,
		bones: Dictionary, poses: Array[Transform3D], done: Array[bool]) -> Transform3D:
	if done[bone]:
		return poses[bone]
	var local := sk.get_bone_rest(bone)
	var entry: Variant = bones.get(sk.get_bone_name(bone))
	if entry is Dictionary:
		var rotation: Quaternion = (entry as Dictionary)["rotation"]
		var position: Vector3 = (entry as Dictionary)["position"]
		local = Transform3D(local.basis * Basis(rotation), local.basis * position + local.origin)
	var parent := sk.get_bone_parent(bone)
	var global := root_pose if bone == root_index else \
		((_frame_pose(sk, parent, root_index, root_pose, bones, poses, done) * local)
			if parent >= 0 else local)
	poses[bone] = global
	done[bone] = true
	return global


## Applies a bone block (the Anon act body) through the same local-rest rule. `weight` blends from
## what the rig holds.
func apply_bones(sk: Skeleton3D, bones: Dictionary, weight: float) -> bool:
	if sk == null or bones.is_empty():
		return false
	_cache_indices(sk)
	for key: Variant in _indices:
		var name := str(key)
		var entry: Variant = bones.get(name)
		if not entry is Dictionary:
			continue
		_write_bone(sk, int(_indices[key]), entry, weight)
	return true


## The variant selection for this frame. The exact size name wins, then the nearest variant scale;
## no variants keeps the base. The selected record is cached, so a steady tick allocates nothing.
func _select(size_name: String, body_scale: float) -> void:
	if variants.is_empty():
		if not _selected.is_empty():
			_selected = {}
			_selected_name = ""
			variant = ""
		return
	var chosen := str(size_name)
	if not variants.has(chosen):
		var best := ""
		var best_gap := INF
		var keys: Array = variants.keys()
		keys.sort()
		for key: Variant in keys:
			var entry: Dictionary = variants[key]
			var gap := absf(float(entry.get("body_scale", 1.0)) - body_scale)
			if gap < best_gap:
				best_gap = gap
				best = str(key)
		chosen = best
	if chosen == _selected_name:
		return
	_selected_name = chosen
	_selected = (variants[chosen] as Dictionary) if variants.has(chosen) else {}
	variant = chosen


func _write_bone(sk: Skeleton3D, bone: int, entry: Dictionary, weight: float) -> void:
	var rotation: Quaternion = entry["rotation"]
	var position: Vector3 = entry["position"]
	var rest := sk.get_bone_rest(bone)
	var basis := rest.basis * Basis(rotation)
	position = rest.basis * position + rest.origin
	rotation = basis.get_rotation_quaternion().normalized()
	sk.set_bone_pose_rotation(bone, sk.get_bone_pose_rotation(bone).slerp(rotation, weight))
	sk.set_bone_pose_position(bone, sk.get_bone_pose_position(bone).lerp(position, weight))
	# Reset the scale to the rig's rest. The proportion and part-hiding modifiers multiply it every
	# pass and lean on the animation to reset it; this write replaced that animation, so the factor
	# would compound and stretch her neck and head.
	sk.set_bone_pose_scale(bone, sk.get_bone_rest(bone).basis.get_scale())


## Bone indices are stable for the life of the skeleton, so resolve the names once per skeleton.
func _cache_indices(sk: Skeleton3D) -> void:
	var skeleton_id := sk.get_instance_id()
	if skeleton_id == _index_skeleton and not _indices.is_empty():
		return
	_indices.clear()
	for key: Variant in active_bones():
		var name := str(key)
		var bone := sk.find_bone(name)
		if bone >= 0:
			_indices[name] = bone
	_index_skeleton = skeleton_id


func _load_document(data: Dictionary) -> void:
	id = str(data.get("id", ""))
	if id.is_empty():
		error = "pose has no id"
		return
	space = str(data.get("space", ""))
	if space != SPACE_LOCAL_REST:
		error = "pose space '%s' is not %s" % [space, SPACE_LOCAL_REST]
		return
	frame = str(data.get("frame", ""))
	if not (frame in SUPPORTED_FRAMES):
		error = "pose frame '%s' is unknown" % frame
		return
	var rig: Variant = data.get("rig")
	if not rig is Dictionary:
		error = "pose has no rig block"
		return
	rig_name = str((rig as Dictionary).get("name", ""))
	rig_bones = int((rig as Dictionary).get("bones", 0))
	if rig_name != RIG_NAME:
		error = "pose rig '%s' is not %s" % [rig_name, RIG_NAME]
		return
	if rig_bones != RIG_BONES:
		error = "pose rig bones %d is not %d" % [rig_bones, RIG_BONES]
		return
	var ref: Variant = data.get("reference")
	if not ref is Dictionary:
		error = "pose has no reference block"
		return
	var ref_config: Variant = (ref as Dictionary).get("config", {})
	reference = {
		"size": str((ref as Dictionary).get("size", "")),
		"body_scale": float((ref as Dictionary).get("body_scale", 0.0)),
		"config": ref_config if ref_config is Dictionary else {},
	}
	if float(reference["body_scale"]) <= 0.0 or not is_finite(float(reference["body_scale"])):
		error = "pose reference body scale is not positive"
		return
	var anchor_error := _parse_anchor(data.get("anchor"), anchor)
	if not anchor_error.is_empty():
		error = anchor_error
		return
	root = _transform(data.get("root", ""))
	if not root.origin.is_finite() or not _finite_basis(root.basis):
		error = "pose root is not finite"
		return
	var pony: Variant = data.get("pony")
	if not pony is Dictionary:
		error = "pose has no pony block"
		return
	pony_bones = _bones((pony as Dictionary).get("bones", ""))
	if not _parse_bad.is_empty():
		error = _parse_bad
		return
	var bones_error := _check_body_bones(pony_bones)
	if not bones_error.is_empty():
		error = bones_error
		return
	var bed: Variant = data.get("bed")
	if bed is Dictionary:
		bed_size = _vec((bed as Dictionary).get("size", ""))
		mattress_top = float((bed as Dictionary).get("mattress_top", 0.0))
	var anon_error := _parse_anon_into(data.get("anon"))
	if not anon_error.is_empty():
		error = anon_error
		return
	shots = _parse_shots(data.get("shots"))
	has_shots = not shots.is_empty()
	var variant_error := _parse_variants(data.get("variants"))
	if not variant_error.is_empty():
		error = variant_error
		return


func _check_body_bones(bones: Dictionary) -> String:
	for name: String in PONY_BONES:
		if not bones.has(name):
			return "pose is missing body bone %s" % name
	for key: Variant in bones:
		var name := str(key)
		for prefix: String in BANNED_PREFIXES:
			if name.begins_with(prefix):
				return "pose authors a runtime-owned bone %s" % name
	return ""


func _parse_anchor(value: Variant, into: Dictionary) -> String:
	if not value is Dictionary:
		return "pose has no anchor block"
	var block: Dictionary = value
	if str(block.get("bone", "")) != "pony_hips":
		return "pose anchor bone '%s' is not pony_hips" % str(block.get("bone", ""))
	var at := _transform(block.get("transform", ""))
	if not at.origin.is_finite() or not _finite_basis(at.basis):
		return "pose anchor transform is not finite"
	var contact := _vec_or_inf(block.get("contact", ""))
	if not contact.is_finite():
		return "pose anchor contact is not finite"
	var support := float(block.get("support", 0.0))
	if not is_finite(support):
		return "pose anchor support is not finite"
	into["bone"] = "pony_hips"
	into["transform"] = at
	into["contact"] = contact
	into["support"] = support
	return ""


## Parse an Anon block into the instance fields. The entry is optional.
func _parse_anon_into(value: Variant) -> String:
	anon_mode = ""
	anon_rig = ""
	anon_transform = Transform3D.IDENTITY
	anon_bones = {}
	if value == null:
		return ""
	var parsed := _parse_anon_block(value)
	if not str(parsed.get("error", "")).is_empty():
		return str(parsed["error"])
	anon_mode = str(parsed["mode"])
	anon_rig = str(parsed["rig"])
	anon_transform = parsed["transform"]
	anon_bones = parsed["bones"]
	return ""


## A parsed Anon block: `{error}` or `{mode, rig, transform, bones}`.
func _parse_anon_block(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"error": "pose anon block is not a dictionary"}
	var block: Dictionary = value
	var mode := str(block.get("mode", ""))
	if mode != "act_body":
		return {"error": "pose anon mode '%s' is not act_body" % mode}
	var rig := str(block.get("rig", ""))
	if rig != ANON_RIG:
		return {"error": "pose anon rig '%s' is not %s" % [rig, ANON_RIG]}
	var at := _transform(block.get("transform", ""))
	if not at.origin.is_finite() or not _finite_basis(at.basis):
		return {"error": "pose anon placement is not finite"}
	var bones := _bones(block.get("bones", ""))
	if not _parse_bad.is_empty():
		return {"error": _parse_bad}
	if bones.is_empty():
		return {"error": "pose anon block has no bones"}
	return {"mode": mode, "rig": rig, "transform": at, "bones": bones}


## Parse the shot dictionary without touching the instance block.
func _parse_shots(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for key: Variant in (raw as Dictionary):
		var shot := _transform((raw as Dictionary)[key])
		if shot.origin.is_finite() and _finite_basis(shot.basis):
			out[str(key)] = shot
	return out


## A variant supplies its own `anchor`, `root`, `anon` and `shots`, plus per-bone `pony.bones`
## overrides. `space`, `frame`, `rig` and `reference` stay base-owned; a variant that sets one is an error.
func _parse_variants(raw: Variant) -> String:
	variants = {}
	if raw == null:
		return ""
	if not raw is Dictionary:
		return "pose variants are not a dictionary"
	var parsed := {}
	for key: Variant in (raw as Dictionary):
		var name := str(key)
		var value: Variant = (raw as Dictionary)[key]
		if not value is Dictionary:
			return "pose variant %s is not a dictionary" % name
		var block: Dictionary = value
		for forbidden: String in ["space", "frame", "rig", "reference"]:
			if block.has(forbidden):
				return "pose variant %s changes %s" % [name, forbidden]
		var scale := float(block.get("body_scale", 0.0))
		if scale <= 0.0 or not is_finite(scale):
			return "pose variant %s has no body scale" % name
		var variant_anchor := _copy_anchor(anchor)
		if block.has("anchor"):
			var anchor_error := _parse_anchor(block.get("anchor"), variant_anchor)
			if not anchor_error.is_empty():
				return "pose variant %s: %s" % [name, anchor_error]
		var variant_root := root
		if block.has("root"):
			variant_root = _transform(block.get("root", ""))
			if not variant_root.origin.is_finite() or not _finite_basis(variant_root.basis):
				return "pose variant %s root is not finite" % name
		var variant_anon := {
			"mode": anon_mode, "rig": anon_rig, "transform": anon_transform,
			"bones": anon_bones.duplicate(),
		}
		if block.has("anon"):
			var anon := _parse_anon_block(block.get("anon"))
			var anon_error := str(anon.get("error", ""))
			if not anon_error.is_empty():
				return "pose variant %s: %s" % [name, anon_error]
			variant_anon = anon
		var variant_shots := shots.duplicate()
		if block.has("shots"):
			variant_shots = _parse_shots(block.get("shots"))
		var variant_bones := pony_bones.duplicate()
		var variant_pony: Variant = block.get("pony")
		if variant_pony is Dictionary:
			var extra := _bones((variant_pony as Dictionary).get("bones", ""))
			if not _parse_bad.is_empty():
				return "pose variant %s: %s" % [name, _parse_bad]
			for bone: Variant in extra:
				variant_bones[bone] = extra[bone]
		parsed[name] = {
			"body_scale": scale,
			"anchor": variant_anchor,
			"root": variant_root,
			"anon_mode": str(variant_anon.get("mode", anon_mode)),
			"anon_rig": str(variant_anon.get("rig", anon_rig)),
			"anon_transform": variant_anon.get("transform", anon_transform),
			"anon_bones": variant_anon.get("bones", anon_bones),
			"shots": variant_shots,
			"bones": variant_bones,
		}
	variants = parsed
	return ""


func _copy_anchor(source: Dictionary) -> Dictionary:
	return {
		"bone": str(source.get("bone", "pony_hips")),
		"transform": source.get("transform", Transform3D.IDENTITY),
		"contact": source.get("contact", Vector3.ZERO),
		"support": float(source.get("support", 0.0)),
	}


func _bones(raw: Variant) -> Dictionary:
	var out := {}
	_parse_bad = ""
	if not raw is Dictionary:
		return out
	for key: Variant in (raw as Dictionary):
		var entry: Variant = (raw as Dictionary)[key]
		if not entry is Dictionary:
			continue
		var rotation := _quat((entry as Dictionary).get("rotation", ""))
		var position := _vec_or_inf((entry as Dictionary).get("position", ""))
		if not rotation.is_normalized() or not position.is_finite():
			_parse_bad = "pose bone %s is not a finite local-rest delta" % str(key)
			return {}
		out[str(key)] = {"rotation": rotation, "position": position}
	return out


func _finite_basis(basis: Basis) -> bool:
	return basis.x.is_finite() and basis.y.is_finite() and basis.z.is_finite()


func _transform(raw: Variant) -> Transform3D:
	var parsed: Variant = str_to_var(str(raw))
	return (parsed as Transform3D) if parsed is Transform3D else Transform3D.IDENTITY


func _vec(raw: Variant) -> Vector3:
	var parsed: Variant = str_to_var(str(raw))
	return (parsed as Vector3) if parsed is Vector3 else Vector3.ZERO


## The strict parse: a missing or unparsable contact is `INF`, so the loader refuses it instead of
## silently accepting a zero point.
func _vec_or_inf(raw: Variant) -> Vector3:
	var parsed: Variant = str_to_var(str(raw))
	return (parsed as Vector3) if parsed is Vector3 else Vector3.INF


func _quat(raw: Variant) -> Quaternion:
	var parsed: Variant = str_to_var(str(raw))
	return (parsed as Quaternion).normalized() if parsed is Quaternion else Quaternion.IDENTITY