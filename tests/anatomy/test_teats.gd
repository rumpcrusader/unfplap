extends "res://mods/unfplap/tests/support/suite.gd"
## The generated teats and the body fit: the size curve, the build guards, the mare-rest to
## her-rest map and the profile of the body a pony is wearing.
##   godot --headless --xr-mode off --path <project> \
##     --script res://mods/unfplap/tests/anatomy/test_teats.gd

const UDDER := preload("res://mods/unfplap/anatomy/udder.gd")
const BODY_FIT := preload("res://mods/unfplap/anatomy/body_fit.gd")
const BODY_PROFILE := preload("res://mods/unfplap/shared/body_profile.gd")



class FakePony extends Node3D:
	var identity: Variant = null


func near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func run() -> void:
	_check_dims()
	_check_build_guards()
	_check_base_map()
	_check_part_map()
	_check_body_profile_for()
	if failures == 0:
		print("ANATOMY_TEATS_PASS")
	finish()


## The shape grows with the size, clamps at both ends and never shrinks between steps.
func _check_dims() -> void:
	var growing: Array[String] = ["spread", "radius", "height", "droop", "nipple_r",
		"nipple_len"]
	var small := UDDER.dims(0.0)
	var full := UDDER.dims(UDDER.SIZE_MAX)
	for key: String in growing:
		check(float(full[key]) > float(small[key]), "%s grows with the size" % key)
	check(near(float(UDDER.dims(0.0)["length"]), float(UDDER.dims(UDDER.SIZE_MAX)["length"])),
		"the lobe length is a ratio, not a size")
	check(UDDER.dims(-1.0) == UDDER.dims(0.0), "a size below zero clamps to the smallest")
	check(UDDER.dims(UDDER.SIZE_MAX + 1.0) == UDDER.dims(UDDER.SIZE_MAX),
		"a size above the cap clamps to the biggest")
	var previous := UDDER.dims(0.0)
	for step in range(1, 29):
		var current := UDDER.dims(float(step) * UDDER.SIZE_MAX / 28.0)
		for key: String in growing:
			check(float(current[key]) >= float(previous[key]),
				"%s never shrinks at step %d" % [key, step])
		previous = current


## A body without a mesh, a skin or belly triangles builds nothing instead of failing.
func _check_build_guards() -> void:
	check(UDDER.build(null, Vector3.ZERO, 1.0, 0.5) == null, "no body builds no teats")
	var body := MeshInstance3D.new()
	check(UDDER.build(body, Vector3.ZERO, 1.0, 0.5) == null, "no body mesh builds no teats")
	body.mesh = BoxMesh.new()
	check(UDDER.build(body, Vector3.ZERO, 1.0, 0.5) == null, "no skin builds no teats")
	body.skin = Skin.new()
	check(UDDER.build(body, Vector3.ZERO, 1.0, 0.5) == null,
		"a body with no belly triangles builds no teats")
	body.free()


## The mare-rest to her-rest map: identity for an ordinary body, Celestia's scale and her hand
## placement for the princess profile.
func _check_base_map() -> void:
	check(BODY_FIT.base_map([]).is_equal_approx(Transform3D.IDENTITY),
		"an ordinary body needs no fit")
	check(BODY_FIT.base_map([0.0, 0.0]).is_equal_approx(Transform3D.IDENTITY),
		"a profile without a size needs no fit")
	var profile: Array = BODY_PROFILE.WINKING_BODIES["celestia"]
	var plain := BODY_FIT.base_map(profile)
	var placed := BODY_FIT.base_map(profile, "celestia")
	check(near(placed.basis.get_scale().x, float(profile[2])),
		"Celestia's fit uses her body scale")
	check(near(placed.origin.z - plain.origin.z, 0.0759),
		"Celestia's fit sits 7.59 cm further back")
	check(near(placed.origin.y, plain.origin.y),
		"the height is measured on her belly, not hand placed")
	check(BODY_FIT.base_map(profile, "luna").is_equal_approx(plain),
		"an unlisted body keeps the measured fit")


## An ordinary body is already the part's rest space; a profile without a part cannot be fitted.
func _check_part_map() -> void:
	check(BODY_FIT.part_map(null, null, []).is_equal_approx(Transform3D.IDENTITY),
		"an ordinary body needs no part map")
	var profile: Array = BODY_PROFILE.WINKING_BODIES["celestia"]
	check(BODY_FIT.part_map(null, null, profile).is_equal_approx(Transform3D.IDENTITY),
		"a princess profile without a part maps to identity")
	var part := MeshInstance3D.new()
	part.mesh = BoxMesh.new()
	check(BODY_FIT.part_map(part, null, profile).is_equal_approx(Transform3D.IDENTITY),
		"a princess profile without a body maps to identity")
	part.free()


## The profile follows the body a pony is wearing: her body-fit metadata first.
func _check_body_profile_for() -> void:
	var pony := FakePony.new()
	pony.identity = {"id": "celestia"}
	check(BODY_PROFILE.body_profile_for(pony).size() == 3,
		"her own princess body names the profile")
	pony.set_meta("body_fit_id", "chrysalis")
	check(BODY_PROFILE.body_profile_for(pony).is_empty(),
		"the body-fit metadata wins over the identity")
	pony.identity = {"id": "chrysalis", "character_id": "celestia"}
	pony.remove_meta("body_fit_id")
	check(BODY_PROFILE.body_profile_for(pony).size() == 3,
		"a copied princess body names the profile")
	pony.identity = {"id": "an_ordinary_mare"}
	check(BODY_PROFILE.body_profile_for(pony).is_empty(),
		"an ordinary mare has no princess profile")
	pony.free()
