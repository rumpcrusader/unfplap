extends SceneTree
## The act-body adapter's authored pair: the placement blend, the v7 local-rest bone blend and the
## service-bound pair setter. A bare Anon skeleton keeps it off every game scene.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/poses/test_act_body.gd

const ACT_BODY := preload("res://mods/unfplap/poses/missionary_anon.gd")
const AUTHORED := preload("res://mods/unfplap/poses/authored_pose.gd")

const HIPS := "Hips"
const SPINE := "Spine"
const HEAD := "Head"
const LEFT_HAND := "LeftHand"
const RIGHT_HAND := "RightHand"
const ANON_BONES := [HIPS, SPINE, HEAD, LEFT_HAND, RIGHT_HAND]

var failures := 0
var checks := 0


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
	_check_placement()
	_check_bones()
	_check_pair()
	print("ACT_BODY_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("ACT_BODY_PASS")
	quit(0 if failures == 0 else 1)


## Two placements: the basis slerps, the origin lerps, and a non-finite side returns the other.
func _check_placement() -> void:
	var from := Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.0, 0.1, 0.0))
	var to := Transform3D(Basis(Vector3.UP, -0.4), Vector3(1.0, 0.3, 0.0))
	var at_zero := ACT_BODY.blend_placement(from, to, 0.0)
	var at_half := ACT_BODY.blend_placement(from, to, 0.5)
	var at_one := ACT_BODY.blend_placement(from, to, 1.0)
	check(at_zero.basis.get_rotation_quaternion().angle_to(
		from.basis.get_rotation_quaternion()) < 0.001
		and at_zero.origin.is_equal_approx(from.origin),
		"weight zero lands on the from placement")
	check(_angle(at_half.basis) < 0.001 and at_half.origin.is_equal_approx(Vector3(0.5, 0.2, 0.0)),
		"weight half slerps the basis and lerps the origin")
	check(at_one.basis.get_rotation_quaternion().angle_to(
		to.basis.get_rotation_quaternion()) < 0.001
		and at_one.origin.is_equal_approx(to.origin),
		"weight one lands on the to placement")
	var broken := Transform3D(Basis.IDENTITY, Vector3(INF, 0.0, 0.0))
	check(ACT_BODY.blend_placement(broken, to, 0.5).is_equal_approx(to),
		"a non-finite from side returns the to placement")
	check(ACT_BODY.blend_placement(from, broken, 0.5).is_equal_approx(from),
		"a non-finite to side returns the from placement")


## One observable skeleton with distinct rest transforms for every Anon bone.
func _skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	root.add_child(sk)
	for i: int in ANON_BONES.size():
		var bone := sk.add_bone(str(ANON_BONES[i]))
		sk.set_bone_parent(bone, -1 if i == 0 else sk.find_bone(str(ANON_BONES[i - 1])))
	for i: int in ANON_BONES.size():
		sk.set_bone_rest(i, Transform3D(Basis(Vector3.UP, 0.05 * (i + 1)),
			Vector3(0.01 * (i + 1), 0.0, 0.0)))
	sk.reset_bone_poses()
	return sk


func _free_skeleton(sk: Skeleton3D) -> void:
	root.remove_child(sk)
	sk.free()


func _entry(angle: float, position: Vector3) -> Dictionary:
	return {"rotation": Quaternion(Vector3.RIGHT, angle), "position": position}


## The v7 local-rest pose the entry describes, for the expected values.
func _local(sk: Skeleton3D, name: String, entry: Dictionary) -> Transform3D:
	var bone := sk.find_bone(name)
	var rest := sk.get_bone_rest(bone)
	var rotation: Quaternion = entry["rotation"]
	var position: Vector3 = entry["position"]
	return Transform3D(rest.basis * Basis(rotation), rest.basis * position + rest.origin)


func _angle(basis: Basis) -> float:
	return absf(basis.get_rotation_quaternion().get_angle())


## The two authored blocks blend per bone: shared bones at the midpoint, one-sided bones keep their
## side, a missing bone is left alone, the rest scale is restored and a non-finite entry is skipped.
func _check_bones() -> void:
	var sk := _skeleton()
	var from_bones := {
		HIPS: _entry(0.4, Vector3(0.0, 0.1, 0.0)),
		SPINE: _entry(0.2, Vector3(0.02, 0.0, 0.0)),
		LEFT_HAND: _entry(0.1, Vector3.ZERO),
		"NoSuchBone": _entry(0.3, Vector3.ZERO),
	}
	var to_bones := {
		HIPS: _entry(-0.3, Vector3(0.0, 0.3, 0.0)),
		SPINE: _entry(-0.1, Vector3(0.04, 0.0, 0.0)),
		HEAD: _entry(0.5, Vector3(0.0, 0.0, 0.02)),
		RIGHT_HAND: _entry(-0.2, Vector3.ZERO),
	}
	var hips := sk.find_bone(HIPS)
	var spine := sk.find_bone(SPINE)
	var head := sk.find_bone(HEAD)
	var left := sk.find_bone(LEFT_HAND)
	var right := sk.find_bone(RIGHT_HAND)
	var from_hips := _local(sk, HIPS, from_bones[HIPS])
	var to_hips := _local(sk, HIPS, to_bones[HIPS])
	sk.set_bone_pose_scale(hips, Vector3.ONE * 2.0)
	ACT_BODY.blend_anon_bones(sk, from_bones, to_bones, 0.0)
	check(sk.get_bone_pose_rotation(hips).is_equal_approx(from_hips.basis.get_rotation_quaternion()),
		"weight zero lands on the from bone rotation")
	check(sk.get_bone_pose_position(hips).is_equal_approx(from_hips.origin),
		"weight zero lands on the from bone position")
	check(sk.get_bone_pose_scale(hips).is_equal_approx(sk.get_bone_rest(hips).basis.get_scale()),
		"the blend restores the rest scale")
	ACT_BODY.blend_anon_bones(sk, from_bones, to_bones, 0.5)
	var midpoint := from_hips.basis.orthonormalized().slerp(
		to_hips.basis.orthonormalized(), 0.5)
	check(sk.get_bone_pose_rotation(hips).is_equal_approx(midpoint.get_rotation_quaternion()),
		"weight half slerps the two local-rest rotations")
	check(sk.get_bone_pose_position(hips).is_equal_approx(
		from_hips.origin.lerp(to_hips.origin, 0.5)),
		"weight half lerps the two local-rest positions")
	ACT_BODY.blend_anon_bones(sk, from_bones, to_bones, 1.0)
	check(sk.get_bone_pose_rotation(hips).is_equal_approx(to_hips.basis.get_rotation_quaternion()),
		"weight one lands on the to bone rotation")
	check(sk.get_bone_pose_position(spine).is_equal_approx(_local(sk, SPINE, to_bones[SPINE]).origin),
		"weight one carries the to spine")
	check(sk.get_bone_pose_rotation(head).is_equal_approx(
		_local(sk, HEAD, to_bones[HEAD]).basis.get_rotation_quaternion()),
		"a to-only bone uses the to side")
	check(sk.get_bone_pose_rotation(left).is_equal_approx(
		_local(sk, LEFT_HAND, from_bones[LEFT_HAND]).basis.get_rotation_quaternion()),
		"a from-only bone uses the from side")
	check(sk.find_bone("NoSuchBone") < 0, "a missing bone is left out of the skeleton")
	check(sk.get_bone_pose_rotation(right).is_equal_approx(
		_local(sk, RIGHT_HAND, to_bones[RIGHT_HAND]).basis.get_rotation_quaternion()),
		"a bone present on only one side still writes")
	# A non-finite entry is skipped: the bone keeps the pose it already had.
	var before := sk.get_bone_pose(hips)
	var bad := {HIPS: _entry(0.2, Vector3(INF, 0.0, 0.0))}
	ACT_BODY.blend_anon_bones(sk, bad, {}, 1.0)
	check(sk.get_bone_pose(hips).is_equal_approx(before),
		"a non-finite authored entry is skipped")
	_free_skeleton(sk)


## The pair setter stores the two assets and clamps the weight; the same pair is a no-op, a changed
## pair updates, and remove clears the pair with the rest of the state.
func _check_pair() -> void:
	var body := ACT_BODY.new()
	var asset_a := AUTHORED.new()
	var asset_b := AUTHORED.new()
	var other := AUTHORED.new()
	body.set_pose_assets(asset_a, asset_b, 0.5)
	check(is_same(body.from_asset, asset_a) and is_same(body.to_asset, asset_b),
		"the setter stores the authored pair")
	check(near(body.asset_weight, 0.5), "the setter stores the weight")
	body.set_pose_assets(other, other, -2.0)
	check(is_zero_approx(body.asset_weight), "the setter clamps a negative weight")
	body.set_pose_assets(other, other, 3.0)
	check(is_equal_approx(body.asset_weight, 1.0), "the setter clamps an oversized weight")
	body.set_pose_assets(other, other, 3.0)
	check(is_equal_approx(body.asset_weight, 1.0) and is_same(body.from_asset, other),
		"the repeated pair keeps the cached fields")
	body.set_pose_assets(asset_a, asset_b, 1.0)
	check(is_same(body.from_asset, asset_a) and is_same(body.to_asset, asset_b),
		"a changed pair updates the cache")
	body.remove()
	check(body.from_asset == null and body.to_asset == null and is_equal_approx(body.asset_weight, 1.0),
		"remove clears the asset pair and the weight")
	body.free()
