extends "res://mods/unfplap/tests/support/suite.gd"
## The version 7 authored asset: the schema and its refusals, the `local_rest` bone math, the
## anchor/contact placement at four sizes, the v6 uniform scale, variants, the bed clearance and
## the spec asset resolution. Synthetic assets keep the suite away from the shipped file's numbers.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_pose_asset_v7.gd

const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const SERVICE := preload("res://mods/unfplap/poses/service.gd")
const POSE_SPEC := preload("res://mods/unfplap/poses/pose_spec.gd")
const SPECS := preload("res://mods/unfplap/shared/pose_specs.gd")
const FIXTURE_V6 := "res://mods/unfplap/tests/poses/fixtures/missionary_pose_v6.json"

const MISSIONARY_PATH := "res://mods/unfplap/poses/missionary_pose.json"
const SIZES := [1.0, 1.35, 1.7, 2.3]
const PONY_BONES := AUTHORED.PONY_BONES

var _scenes: Array[Node] = []

func near_v(a: Vector3, b: Vector3, eps := 0.0001) -> bool:
	return a.distance_to(b) <= eps


func run() -> void:
	_check_schema()
	_check_local_rest()
	_check_placement()
	_check_variants()
	_check_resolution()
	_check_v6()
	_check_v6_scale()
	_check_facesit_asset()
	await _check_bed_clearance()
	if failures == 0:
		print("POSE_ASSET_V7_PASS")
	finish()


## A valid synthetic asset dictionary. Each call is fresh, so a case can mutate one field.
func _asset() -> Dictionary:
	return {
		"version": 7,
		"id": "standing",
		"space": "local_rest",
		"frame": "ground",
		"rig": {"name": "hybrid_mare", "version": 1, "bones": 30},
		"reference": {
			"size": "canon", "body_scale": 1.0,
			"config": {
				"bow": 2.4, "foreleg": 2.0, "foreleg_spread": 0.172,
				"hind_spread": 0.32, "chin_up_deg": 30.0, "neck_down_deg": 30.0,
			},
		},
		"anchor": {
			"bone": "pony_hips",
			"transform": var_to_str(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.8, 0.0))),
			"contact": var_to_str(Vector3(0.0, -0.8, 0.0)),
			"support": 0.0,
		},
		"root": var_to_str(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.8, 0.0))),
		"pony": {"bones": _identity_bones()},
		"shots": {
			"start": var_to_str(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 2.0))),
		},
	}


func _identity_bones() -> Dictionary:
	var out := {}
	for name: String in PONY_BONES:
		out[name] = {
			"rotation": var_to_str(Quaternion.IDENTITY),
			"position": var_to_str(Vector3.ZERO),
		}
	return out


func _write(name: String, data: Variant) -> String:
	var path := "user://unfplap_v7_%s.json" % name
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return path


func _load(data: Variant, name: String) -> Variant:
	var pose: Variant = AUTHORED.new()
	pose.call("load_file", _write(name, data))
	return pose


func _refused(data: Variant, name: String, needle := "") -> void:
	var pose: Variant = _load(data, name)
	check(not bool(pose.get("available")), "%s is refused" % name)
	var why := str(pose.get("error"))
	check(not why.is_empty(), "%s carries a reason" % name)
	if not needle.is_empty():
		check(why.contains(needle), "%s reason names %s (%s)" % [name, needle, why])


func _check_schema() -> void:
	var pose: Variant = _load(_asset(), "valid")
	check(bool(pose.get("available")), "the synthetic asset loads: %s" % str(pose.get("error")))
	check(int(pose.get("version")) == 7, "version 7")
	check(str(pose.get("space")) == AUTHORED.SPACE_LOCAL_REST, "local_rest space")
	check(bool(pose.call("usable", "ground")), "usable for its ground frame")
	check(not bool(pose.call("usable", "bed")), "not usable for a bed frame")
	check(bool(pose.call("has_shot", "start")), "an authored shot is readable")
	check(int(pose.get("rig_version")) == AUTHORED.RIG_VERSION, "the rig version is pinned")

	var newer := _asset()
	newer["version"] = 8
	_refused(newer, "newer", "newer")
	var older := _asset()
	older["version"] = 5
	_refused(older, "older", "older")
	var space := _asset()
	space["space"] = "world"
	_refused(space, "space", "space")
	var frame := _asset()
	frame["frame"] = "orbit"
	_refused(frame, "frame", "frame")
	var rig := _asset()
	(rig["rig"] as Dictionary)["version"] = 2
	_refused(rig, "rig_version", "rig version")
	var missing := _asset()
	(missing["pony"]["bones"] as Dictionary).erase("pony_hips")
	_refused(missing, "missing_bone", "missing body bone")
	var anchor := _asset()
	(anchor["anchor"] as Dictionary)["bone"] = "pony_head"
	_refused(anchor, "anchor_bone", "pony_hips")
	var contact := _asset()
	(contact["anchor"] as Dictionary)["contact"] = var_to_str(Vector3.INF)
	_refused(contact, "contact", "contact")
	var delta := _asset()
	((delta["pony"]["bones"] as Dictionary)["pony_hips"] as Dictionary)["position"] = \
		var_to_str(Vector3(INF, 0.0, 0.0))
	_refused(delta, "delta", "local-rest delta")
	var banned := _asset()
	(banned["pony"]["bones"] as Dictionary)["pony_head"] = {
		"rotation": var_to_str(Quaternion.IDENTITY), "position": var_to_str(Vector3.ZERO),
	}
	_refused(banned, "banned", "runtime-owned")
	var root := _asset()
	root["root"] = var_to_str(Transform3D(Basis.IDENTITY, Vector3.INF))
	_refused(root, "root", "root")


## The bone math: the delta is identity at rest, a known delta lands at `rest * delta`, and the
## written scale is the rig's rest scale again.
func _check_local_rest() -> void:
	var pose: Variant = _load(_asset(), "local_rest")
	var sk := _skeleton(1.0)
	var rest := Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0.0, 0.3, 0.0))
	var spine := sk.find_bone("pony_spine1")
	sk.set_bone_rest(spine, rest)
	sk.reset_bone_poses()
	check(bool(pose.call("apply_pony", sk, 1.0, Transform3D.IDENTITY, 1.0, "canon")), "apply")
	check(near_v(sk.get_bone_pose_position(spine), rest.origin, 0.00001),
		"an identity delta leaves the bone at its rest position")
	check(sk.get_bone_pose_rotation(spine).is_equal_approx(
		rest.basis.get_rotation_quaternion()), "an identity delta leaves the rest rotation")

	var delta := {
		"rotation": Quaternion(Vector3.UP, 0.4),
		"position": Vector3(0.05, 0.0, 0.0),
	}
	(pose.get("pony_bones") as Dictionary)["pony_spine1"] = delta
	sk.set_bone_pose_scale(spine, Vector3.ONE * 0.001)
	pose.call("apply_pony", sk, 1.0, Transform3D.IDENTITY, 1.0, "canon")
	var half := Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.05, 0.0, 0.0))
	var expected := rest * half
	check(near_v(sk.get_bone_pose_position(spine), expected.origin, 0.00001),
		"a known delta lands at rest * delta")
	check(sk.get_bone_pose_rotation(spine).is_equal_approx(
		expected.basis.get_rotation_quaternion()),
		"a known delta lands at the expected rotation")
	check(sk.get_bone_pose_scale(spine).is_equal_approx(sk.get_bone_rest(spine).basis.get_scale()),
		"the pose scale is reset to the rest scale")
	_free_skeleton(sk)


## The anchor/contact placement: the hips stay over the anchor, the contact on the support, the
## world root carries the live body scale and the skeleton-space root pose stays orthonormal.
func _check_placement() -> void:
	var pose: Variant = _load(_asset(), "placement")
	var frame := Transform3D(Basis(Vector3.UP, 0.7), Vector3(1.0, 0.0, -2.0))
	var anchor := frame * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.8, 0.0))
	var contact := Vector3(0.0, 0.0, 0.0)
	var canon_root := frame * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.8, 0.0))
	for size: float in SIZES:
		var sk := _skeleton(size)
		check(bool(pose.call("apply_pony", sk, 1.0, frame, size, "canon")), "apply at %.2f" % size)
		var root := AUTHORED.root_bone(sk)
		var hips := sk.find_bone("pony_hips")
		var hips_world: Vector3 = sk.global_transform * sk.get_bone_global_pose(hips).origin
		var root_pose := sk.get_bone_global_pose(root)
		var lift := 0.8 * (size - 1.0)
		check(near(hips_world.x, anchor.origin.x, 0.00001),
			"hips keep the anchor x at %.2f: %.4f" % [size, hips_world.x])
		check(near(hips_world.z, anchor.origin.z, 0.00001),
			"hips keep the anchor z at %.2f: %.4f" % [size, hips_world.z])
		check(near(hips_world.y, anchor.origin.y + lift, 0.00001),
			"hips ride the contact lift at %.2f: %.4f" % [size, hips_world.y])
		check(near(root_pose.basis.determinant(), 1.0, 0.0001),
			"skeleton-space root basis is orthonormal at %.2f" % size)
		var placed_contact: Vector3 = pose.call("place_origin",
			pose.call("contact_world", frame), frame, size)
		check(near(placed_contact.y, frame.origin.y, 0.00001),
			"the placed contact sits on the support at %.2f: %.5f" % [size, placed_contact.y])
		if is_equal_approx(size, 1.0):
			var wanted: Transform3D = pose.call("placed_root", frame, 1.0)
			check(near_v(wanted.origin, canon_root.origin, 0.00001),
				"at canon the root is the asset root")
		_free_skeleton(sk)

	var s := 1.7
	var world_point := frame * Vector3(1.0, 1.5, 0.5)
	var here := anchor.origin
	var lift := 0.8 * (s - 1.0)
	var expected := here + (world_point - here) * s + Vector3.UP * lift
	check(near_v(pose.call("place_origin", world_point, frame, s), expected, 0.00001),
		"place_origin follows the anchor, the scale and the lift")
	var shot: Vector3 = pose.call("shot_origin", "start", frame, s)
	var shot_point := frame * Vector3(0.0, 1.0, 2.0)
	var shot_expected := here + (shot_point - here) * s + Vector3.UP * lift
	check(near_v(shot, shot_expected, 0.00001), "shot_origin follows the same rule")
	var missing_shot: Vector3 = pose.call("shot_origin", "nope", frame, s)
	check(not missing_shot.is_finite(), "a missing shot has no origin")


func _check_variants() -> void:
	var data := _asset()
	var variants := {
		"canon": {
			"body_scale": 1.0,
			"anchor": {
				"bone": "pony_hips",
				"transform": var_to_str(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.8, 0.0))),
				"contact": var_to_str(Vector3(0.0, -0.8, 0.0)),
				"support": 0.0,
			},
		},
		"jrh": {
			"body_scale": 1.35,
			"anchor": {
				"bone": "pony_hips",
				"transform": var_to_str(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.9, 0.0))),
				"contact": var_to_str(Vector3(0.0, -0.8, 0.0)),
				"support": 0.0,
			},
			"pony": {"bones": {"pony_spine1": {
				"rotation": var_to_str(Quaternion(Vector3.UP, 0.2)),
				"position": var_to_str(Vector3(0.02, 0.0, 0.0)),
			}}},
		},
	}
	data["variants"] = variants
	var pose: Variant = _load(data, "variants")
	check(bool(pose.get("available")), "the variant asset loads: %s" % str(pose.get("error")))
	var exact: Dictionary = pose.call("variant_for", "jrh", 1.35)
	check(near(float(exact.get("body_scale", 0.0)), 1.35), "an exact size name wins")
	var nearest: Dictionary = pose.call("variant_for", "mounting", 1.30)
	check(near(float(nearest.get("body_scale", 0.0)), 1.35), "an unknown name snaps to the nearest scale")
	var merged: Dictionary = exact.get("bones", {})
	check(merged.size() == PONY_BONES.size(), "a variant keeps every base bone")
	check(not (merged["pony_spine1"] as Dictionary)["position"].is_zero_approx(),
		"a variant merges its bone override")
	var base: Dictionary = pose.call("variant_for", "nope", 0.5)
	check(near(float(base.get("body_scale", 0.0)), 1.0), "the nearest is the canon variant")

	var bad := _asset()
	bad["variants"] = {"jrh": {"body_scale": 1.35, "space": "world"}}
	_refused(bad, "variant_space", "changes space")
	var no_scale := _asset()
	no_scale["variants"] = {"jrh": {}}
	_refused(no_scale, "variant_scale", "no body scale")


## The spec table's `asset` field and the base-chain resolution.
func _check_resolution() -> void:
	var service: SERVICE = SERVICE.new()
	check(service.call("asset_for", SPECS.MISSIONARY) == "poses/missionary_pose.json",
		"missionary resolves its asset")
	var row: Dictionary = SPECS.spec(SPECS.MISSIONARY).duplicate(true)
	row["id"] = "missionary_child"
	row["display_name"] = "Missionary child"
	row["base"] = SPECS.MISSIONARY
	row["driver"] = ""
	row["asset"] = ""
	var child: Variant = POSE_SPEC.from_dict("missionary_child", row)
	check(child != null, "a synthetic base row builds")
	check(str(service.call("_effective_asset", child)) == "poses/missionary_pose.json",
		"a base-chain row inherits the asset")
	var standing_asset := str(service.call("asset_for", SPECS.STANDING))
	check(standing_asset == "poses/standing_pose.json", "the standing row declares its asset")
	check(str(service.call("asset_for", SPECS.STANDING_TEST)) == standing_asset,
		"standing_test inherits the standing asset")
	check(str(service.call("asset_for", SPECS.STANDING_ORAL)) == standing_asset,
		"standing_oral inherits the standing asset")
	var shipped: Variant = AUTHORED.shared(standing_asset)
	check(bool(shipped.get("available")), "the standing asset loads: %s" % str(shipped.get("error")))
	check(int(shipped.get("version")) == 7, "the standing asset is v7")
	check(str(shipped.get("space")) == AUTHORED.SPACE_LOCAL_REST, "local_rest space")
	check(str(shipped.get("frame")) == "ground", "the standing asset is a ground pose")
	check(int(shipped.get("rig_bones")) == 30, "the standing rig is 30 bones")
	check((shipped.get("pony_bones") as Dictionary).size() == 30, "30 body deltas")
	var anchor: Dictionary = shipped.get("anchor")
	check(str(anchor.get("bone", "")) == "pony_hips", "the anchor is the hips")
	check((anchor.get("contact", Vector3.INF) as Vector3).is_finite(), "the contact is finite")
	check(near(float(anchor.get("support", -1.0)), 0.0), "the ground support is zero")
	check((shipped.get("variants") as Dictionary).is_empty(), "v1 ships no variants")
	var reference: Dictionary = shipped.get("reference")
	var ref_config: Dictionary = reference.get("config", {})
	check(ref_config.size() == 6, "the reference config has the six keys")
	service.free()


## The version 6 migration fixture: it loads, applies, and is refused for a ground view.
func _check_v6() -> void:
	var pose: Variant = AUTHORED.new()
	check(str(pose.call("load_file", FIXTURE_V6)).is_empty(), "the v6 fixture loads")
	check(int(pose.get("version")) == 6, "the fixture reports version 6")
	check(str(pose.get("space")) == "bed", "the fixture is bed space")
	check(bool(pose.call("usable", "bed")), "the v6 asset is usable for a bed frame")
	check(not bool(pose.call("usable", "ground")), "the v6 asset is refused for a ground view")
	check(not (pose.get("pony_bones") as Dictionary).is_empty(), "the fixture carries the body")
	var sk := _skeleton(1.0)
	check(bool(pose.call("apply_pony", sk, 1.0, Transform3D.IDENTITY, 1.0)),
		"the v6 migration path applies")
	_free_skeleton(sk)


## A bare rig: an armature, hips and one spine bone. `rest` offsets put the hips under the root.
func _skeleton(scale: float) -> Skeleton3D:
	var parent := Node3D.new()
	parent.scale = Vector3.ONE * scale
	root.add_child(parent)
	var sk := Skeleton3D.new()
	parent.add_child(sk)
	var armature := sk.add_bone("armature")
	sk.set_bone_parent(armature, -1)
	sk.set_bone_rest(armature, Transform3D.IDENTITY)
	var hips := sk.add_bone("pony_hips")
	sk.set_bone_parent(hips, armature)
	sk.set_bone_rest(hips, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	var spine := sk.add_bone("pony_spine1")
	sk.set_bone_parent(spine, hips)
	sk.set_bone_rest(spine, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)))
	sk.reset_bone_poses()
	return sk


func _free_skeleton(sk: Skeleton3D) -> void:
	var parent := sk.get_parent()
	if parent != null:
		parent.queue_free()
	else:
		sk.queue_free()


## The shipped bed face-sit: the shape the D4 asset must carry, its v7 placement and the optional
## Anon/shot blocks. The numbers belong to the D4 lab, not to this suite.
func _check_facesit_asset() -> void:
	var path := "res://mods/unfplap/poses/bed_facesit_pose.json"
	var pose: Variant = AUTHORED.shared(path)
	check(bool(pose.get("available")), "the face-sit asset loads: %s" % str(pose.get("error")))
	if not bool(pose.get("available")):
		return
	check(int(pose.get("version")) == 7, "the face-sit asset is v7")
	check(str(pose.get("id")) == "bed_facesit", "the face-sit id")
	check(str(pose.get("space")) == AUTHORED.SPACE_LOCAL_REST, "the face-sit is local_rest")
	check(str(pose.get("frame")) == "bed", "the face-sit is a bed pose")
	check(bool(pose.call("usable", "bed")), "the face-sit is usable in bed space")
	check(not bool(pose.call("usable", "ground")), "the face-sit is refused for a ground view")
	check(str(pose.get("rig_name")) == AUTHORED.RIG_NAME, "the face-sit rig name")
	check(int(pose.get("rig_version")) == AUTHORED.RIG_VERSION, "the face-sit rig version")
	check(int(pose.get("rig_bones")) == AUTHORED.RIG_BONES, "the face-sit rig bone count")
	check((pose.get("pony_bones") as Dictionary).size() == PONY_BONES.size(),
		"the face-sit carries every body bone")
	var anchor: Dictionary = pose.get("anchor")
	check(str(anchor.get("bone", "")) == "pony_hips", "the face-sit anchor is the hips")
	check((anchor.get("contact", Vector3.INF) as Vector3).is_finite(),
		"the face-sit contact is finite")
	check(near(float(anchor.get("support", -1.0)), 0.0), "the face-sit support is the mattress top")
	check((pose.get("root") as Transform3D).origin.is_finite(), "the face-sit root is finite")
	check(str(pose.call("active_anon_mode")) == "act_body", "the face-sit Anon mode is act_body")
	check(str(pose.call("active_anon_rig")) == AUTHORED.ANON_RIG, "the face-sit Anon rig")
	var anon_transform: Transform3D = pose.call("active_anon_transform")
	check(anon_transform.origin.is_finite() and anon_transform.basis.determinant() > 0.0,
		"the face-sit Anon placement is finite and right-handed")
	var anon_bones: Dictionary = pose.call("active_anon_bones")
	check(anon_bones.size() == 52, "the face-sit carries the full 52-bone Anon rig")
	for bone: String in ["Hips", "Spine", "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
		check(anon_bones.has(bone), "the face-sit Anon block carries %s" % bone)
	var shots: Dictionary = pose.get("shots")
	check(shots.size() == 5, "the face-sit carries five shots")
	for shot: String in ["start", "front", "back", "left", "right"]:
		check(pose.call("has_shot", shot), "the face-sit carries the %s shot" % shot)
	check((pose.get("variants") as Dictionary).is_empty(), "the face-sit ships no variants")
	var frame := Transform3D(Basis(Vector3.UP, 0.4), Vector3(1.0, 0.7, -2.0))
	for size: float in SIZES:
		var placed: Vector3 = pose.call("place_origin", pose.call("contact_world", frame), frame, size)
		check(near(placed.y, frame.origin.y, 0.00001),
			"the face-sit contact sits on the mattress at %.2f" % size)


## Version 6 is bed space with absolute local poses, so its placement scales uniformly with the
## rig's pivot: the hips and the lateral/longitudinal axes follow the body scale, and a scaled
## root basis would multiply the body twice.
func _check_v6_scale() -> void:
	var pose: Variant = AUTHORED.new()
	pose.available = true
	pose.pony_frame = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0))
	pose.pony_bones = {}
	for name: String in PONY_BONES:
		pose.pony_bones[name] = {"rotation": Quaternion.IDENTITY, "position": Vector3.ZERO}
	pose.pony_bones["pony_hips"] = {"rotation": Quaternion.IDENTITY,
		"position": Vector3(0.0, 0.1, 0.0)}

	var canon := _skeleton(1.0)
	var canon_world := _apply_v6(pose, canon)
	check(near(canon_world.y, 0.6), "the canon v6 hips sit at the authored height: %.3f"
		% canon_world.y)

	var big := _skeleton(1.35)
	var big_world := _apply_v6(pose, big)
	check(near(big_world.y, 0.81), "the v6 placement scales the hips with the body: %.3f"
		% big_world.y)
	var root := AUTHORED.root_bone(big)
	var determinant := big.get_bone_global_pose(root).basis.determinant()
	check(near(determinant, 1.0), "the v6 root pose stays orthonormal: %.4f" % determinant)


## The v6 pose placed on a synthetic rig and the hips' world position.
func _apply_v6(pose: Variant, sk: Skeleton3D) -> Vector3:
	check(bool(pose.call("apply_pony", sk, 1.0, Transform3D.IDENTITY,
		sk.global_transform.basis.get_scale().x)), "the v6 asset applies")
	var hips := sk.find_bone("pony_hips")
	return sk.global_transform * sk.get_bone_global_pose(hips).origin


## A body that is not the mare's own hangs further from its armature root, so the mare's root
## placement sinks it into the mattress. The lift is measured once per body and only in a bed pose.
func _check_bed_clearance() -> void:
	var frame := Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.0, 0.65, 0.0))
	var asset: Variant = AUTHORED.new()
	check(str(asset.call("load_file", MISSIONARY_PATH)).is_empty(), "the lift reads the asset")
	check(float(asset.call("bed_clearance", null)) == 0.0, "no skeleton has no bed lift")

	var mare := await _body("res://world/characters/hybrid_mare/body.glb")
	check(mare != null, "the mare body has a skeleton")
	if mare != null:
		asset.call("apply_pony", mare, 1.0, frame, 1.0, "canon")
		mare.force_update_all_bone_transforms()
		check(near(float(asset.call("bed_clearance", mare)), 0.0),
			"the mare body sits on the mattress with no lift")

	var celestia := await _body("res://world/characters/princesses/celestia_body.glb")
	check(celestia != null, "the princess body has a skeleton")
	if celestia != null:
		var before := AUTHORED._clearance.size()
		asset.call("apply_pony", celestia, 1.0, frame, 1.0, "canon")
		celestia.force_update_all_bone_transforms()
		var lift := float(asset.call("bed_clearance", celestia))
		check(lift > AUTHORED.BED_LIFT_MIN_M, "an oversized body is lifted: %.3f m" % lift)
		check(AUTHORED._clearance.size() == before + 1, "the lift is measured once per body")
		check(near(float(asset.call("bed_clearance", celestia)), lift),
			"the measured lift is cached")

		# The same asset on a ground pose applies no lift, and the same body in a bed pose does.
		var ground: Variant = AUTHORED.new()
		ground.available = true
		ground.version = 7
		ground.space = AUTHORED.SPACE_LOCAL_REST
		ground.frame = "ground"
		ground.anchor = {
			"bone": "pony_hips",
			"transform": Transform3D.IDENTITY,
			"contact": Vector3.ZERO,
			"support": 0.0,
		}
		ground.root = Transform3D.IDENTITY
		ground.pony_bones = {}
		for name: String in PONY_BONES:
			ground.pony_bones[name] = {"rotation": Quaternion.IDENTITY, "position": Vector3.ZERO}
		var root := AUTHORED.root_bone(celestia)
		var wanted: Transform3D = ground.call("placed_root", Transform3D.IDENTITY, 1.0)
		ground.call("apply_pony", celestia, 1.0, Transform3D.IDENTITY, 1.0, "canon")
		check(near(celestia.get_bone_global_pose(root).origin.y, wanted.origin.y),
			"a ground pose is never lifted")
		ground.frame = "bed"
		var bed_lift := float(ground.call("bed_clearance", celestia))
		check(bed_lift > 0.0, "the same body sinks in a bed pose")
		ground.call("apply_pony", celestia, 1.0, Transform3D.IDENTITY, 1.0, "canon")
		check(near(celestia.get_bone_global_pose(root).origin.y, wanted.origin.y + bed_lift),
			"a bed pose lifts the root by the measured sink")

	for scene: Node in _scenes:
		root.remove_child(scene)
		scene.free()
	_scenes.clear()


## A real body scene's skeleton, kept alive until the check finishes.
func _body(path: String) -> Skeleton3D:
	var scene: Node = load(path).instantiate()
	root.add_child(scene)
	_scenes.append(scene)
	await process_frame
	for node: Node in scene.find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null