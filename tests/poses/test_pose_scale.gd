extends SceneTree
## The authored pose's size handling: the rig's own pivot scales her body, so the placement has to
## scale the same way, or a bigger pony renders as a canon body shifted along the bed.
##   godot --headless --xr-mode off --path <project> --script res://mods/unfplap/tests/poses/test_pose_scale.gd

const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")
const BODY := preload("res://world/characters/hybrid_mare/body.glb")

const MISSIONARY_PATH := "res://mods/unfplap/poses/missionary_pose.json"
const SIZES := [1.0, 1.35, 1.7, 2.3]

## The 30 body bones the runtime writes, in the pose lab's order.
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

var failures := 0
var checks := 0
var _scenes: Array[Node] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", text)


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	_check_v6()
	_check_v7()
	await _check_shipped_missionary()
	await _check_bed_clearance()
	print("POSE_SCALE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("POSE_SCALE_PASS")
	quit(0 if failures == 0 else 1)


func _check_v6() -> void:
	# Hand-built pose, so the test does not depend on the shipped file's numbers.
	var pose := AUTHORED.new()
	pose.available = true
	pose.pony_frame = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0))
	pose.pony_bones = {}
	for name: String in PONY_BONES:
		pose.pony_bones[name] = {"rotation": Quaternion.IDENTITY, "position": Vector3.ZERO}
	pose.pony_bones["pony_hips"] = {"rotation": Quaternion.IDENTITY,
		"position": Vector3(0.0, 0.1, 0.0)}

	# Canon: the body sits at the authored height with no scale.
	var canon := _skeleton(1.0)
	var canon_world := _apply(pose, canon)
	check(near(canon_world.y, 0.6), "canon hips at 0.6: %.3f" % canon_world.y)

	# JRHNBR: the rig's pivot scales her body, so the placement must scale with it. The hips land
	# at 1.35 x the canon height, not at the canon height.
	var big := _skeleton(1.35)
	var big_world := _apply(pose, big)
	check(near(big_world.y, 0.81), "JRHNBR hips at 1.35 x 0.6: %.3f" % big_world.y)
	check(near(big_world.x, canon_world.x * 1.35), "JRHNBR lateral scale")
	check(near(big_world.z, canon_world.z * 1.35), "JRHNBR longitudinal scale")

	# The root's skeleton-space pose stays orthonormal: the pivot carries the scale, so a scaled
	# root basis would multiply the body twice.
	var root := AUTHORED.root_bone(big)
	var root_pose := big.get_bone_global_pose(root)
	check(near(root_pose.basis.determinant(), 1.0),
		"root basis is orthonormal: %.4f" % root_pose.basis.determinant())


## A synthetic v7 asset: the hips anchor and the contact place the root at every size, the contact
## stays on the support and the skeleton-space root pose stays orthonormal.
func _check_v7() -> void:
	var pose := AUTHORED.new()
	pose.available = true
	pose.version = 7
	pose.space = AUTHORED.SPACE_LOCAL_REST
	pose.frame = "ground"
	pose.anchor = {
		"bone": "pony_hips",
		"transform": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)),
		"contact": Vector3(0.0, -0.5, 0.0),
		"support": 0.0,
	}
	pose.root = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0))
	pose.pony_bones = {}
	for name: String in PONY_BONES:
		pose.pony_bones[name] = {"rotation": Quaternion.IDENTITY, "position": Vector3.ZERO}
	var frame := Transform3D(Basis(Vector3.UP, 0.8), Vector3(2.0, 0.0, -1.0))
	var anchor_local: Transform3D = pose.anchor["transform"]
	var anchor := (frame * anchor_local).origin
	for scale: float in [1.0, 1.35, 1.7, 2.3]:
		var sk := _skeleton(scale)
		check(bool(pose.call("apply_pony", sk, 1.0, frame, scale, "canon")),
			"the v7 asset applies at %.2f" % scale)
		var hips := sk.find_bone("pony_hips")
		var hips_world: Vector3 = sk.global_transform * sk.get_bone_global_pose(hips).origin
		var lift := float(pose.call("body_lift", frame, scale))
		check(near(hips_world.x, anchor.x) and near(hips_world.z, anchor.z),
			"the hips stay over the anchor at %.2f" % scale)
		check(near(hips_world.y, anchor.y + lift),
			"the hips ride the lift at %.2f" % scale)
		var contact: Vector3 = pose.call("place_origin", pose.call("contact_world", frame),
			frame, scale)
		check(near(contact.y, frame.origin.y), "the contact stays on the support at %.2f" % scale)
		var root := AUTHORED.root_bone(sk)
		check(near(sk.get_bone_global_pose(root).basis.determinant(), 1.0, 0.0001),
			"the v7 root pose is orthonormal at %.2f" % scale)


## The shipped missionary v7 asset on the real body: the hips stay at the anchor, the contact on
## the mattress and the body pose is size-invariant at the four shipped sizes.
func _check_shipped_missionary() -> void:
	var pony: Node3D = BODY.instantiate()
	root.add_child(pony)
	await process_frame
	var sk: Skeleton3D = null
	for node: Node in pony.find_children("*", "Skeleton3D", true, false):
		sk = node as Skeleton3D
		break
	check(sk != null, "the body rig has a skeleton")
	if sk == null:
		return
	var asset: Variant = AUTHORED.new()
	check(str(asset.call("load_file", MISSIONARY_PATH)).is_empty(), "the missionary asset loads")
	check(bool(asset.call("usable", "bed")), "the missionary asset is a bed pose")
	var frame := Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.0, 0.65, 0.0))
	var anchor: Transform3D = asset.call("anchor_world", frame)
	var original := pony.transform
	var canon := {}
	var worst_pos := 0.0
	var worst_deg := 0.0
	for size: float in SIZES:
		pony.transform.basis = original.basis * Basis.from_scale(Vector3.ONE * size)
		sk.reset_bone_poses()
		sk.force_update_all_bone_transforms()
		check(bool(asset.call("apply_pony", sk, 1.0, frame, size, "canon")),
			"the missionary asset applies at %.2f" % size)
		sk.force_update_all_bone_transforms()
		var top := AUTHORED.root_bone(sk)
		check(near(sk.get_bone_global_pose(top).basis.determinant(), 1.0, 0.001),
			"the missionary root is orthonormal at %.2f" % size)
		var hips := sk.find_bone("pony_hips")
		var hips_world: Vector3 = sk.global_transform * sk.get_bone_global_pose(hips).origin
		var lift := float(asset.call("body_lift", frame, size))
		check(near(hips_world.x, anchor.origin.x) and near(hips_world.z, anchor.origin.z),
			"the missionary hips stay over the anchor at %.2f" % size)
		check(near(hips_world.y, anchor.origin.y + lift),
			"the missionary hips ride the lift at %.2f" % size)
		var contact: Vector3 = asset.call("place_origin",
			asset.call("contact_world", frame), frame, size)
		check(near(contact.y, frame.origin.y),
			"the missionary contact stays on the mattress at %.2f" % size)
		var local := {}
		for name: String in PONY_BONES:
			var bone := sk.find_bone(name)
			if bone >= 0:
				local[name] = sk.get_bone_pose(bone)
		if canon.is_empty():
			canon = local
			continue
		for name: String in canon:
			var a: Transform3D = canon[name]
			var b: Transform3D = local[name]
			worst_pos = maxf(worst_pos, a.origin.distance_to(b.origin))
			var qa := a.basis.orthonormalized().get_rotation_quaternion().normalized()
			var qb := b.basis.orthonormalized().get_rotation_quaternion().normalized()
			worst_deg = maxf(worst_deg, rad_to_deg(qa.angle_to(qb)))
	check(worst_pos <= 0.002, "the missionary body positions are size-invariant: %.5f m" % worst_pos)
	check(worst_deg <= 0.5, "the missionary body rotations are size-invariant: %.4f deg" % worst_deg)
	pony.transform = original
	root.remove_child(pony)
	pony.free()


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


func _skeleton(scale: float) -> Skeleton3D:
	var parent := Node3D.new()
	parent.scale = Vector3.ONE * scale
	root.add_child(parent)
	var sk := Skeleton3D.new()
	parent.add_child(sk)
	var armature := sk.add_bone("armature")
	sk.set_bone_parent(armature, -1)
	for name: String in PONY_BONES:
		var bone := sk.add_bone(name)
		sk.set_bone_parent(bone, armature)
	sk.reset_bone_poses()
	return sk


func _apply(pose: Variant, sk: Skeleton3D) -> Vector3:
	check(bool(pose.call("apply_pony", sk, 1.0, Transform3D.IDENTITY,
		sk.global_transform.basis.get_scale().x)), "apply_pony")
	var hips := sk.find_bone("pony_hips")
	return sk.global_transform * sk.get_bone_global_pose(hips).origin
